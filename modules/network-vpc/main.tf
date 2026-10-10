# Three-AZ VPC for a FinTechBankX cell:
#  public  - load balancers and NAT gateways only
#  private - EKS nodes/pods, MSK brokers, Aurora, ElastiCache (egress via NAT)
#  intra   - no route to the internet (data stores that never need egress)
# Interface endpoints keep AWS API traffic (ECR, STS, Secrets Manager, SSM,
# CloudWatch Logs) off the NAT path; S3 uses a gateway endpoint.

data "aws_availability_zones" "available" {
  state = "available"
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

data "aws_region" "current" {}

locals {
  azs      = var.azs != null ? var.azs : slice(data.aws_availability_zones.available.names, 0, var.az_count)
  az_count = length(local.azs)

  # Default layout (works for any prefix length <= /20):
  #  private: first az_count blocks of newbits 3 (e.g. /19s of a /16)
  #  public : /24-equivalents (newbits 8) at index 96+i (inside the 4th /19)
  #  intra  : /24-equivalents at index 100+i
  private_cidrs = length(var.private_subnet_cidrs) > 0 ? var.private_subnet_cidrs : [for i in range(local.az_count) : cidrsubnet(var.cidr_block, 3, i)]
  public_cidrs  = length(var.public_subnet_cidrs) > 0 ? var.public_subnet_cidrs : [for i in range(local.az_count) : cidrsubnet(var.cidr_block, 8, 96 + i)]
  intra_cidrs   = length(var.intra_subnet_cidrs) > 0 ? var.intra_subnet_cidrs : [for i in range(local.az_count) : cidrsubnet(var.cidr_block, 8, 100 + i)]

  nat_count = var.enable_nat_gateway ? (var.single_nat_gateway ? 1 : local.az_count) : 0

  cluster_tag = var.eks_cluster_name == null ? {} : { "kubernetes.io/cluster/${var.eks_cluster_name}" = "shared" }

  tags = merge({ ManagedBy = "terraform", Module = "network-vpc" }, var.tags)
}

resource "aws_vpc" "this" {
  cidr_block           = var.cidr_block
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags                 = merge(local.tags, { Name = var.name })

  lifecycle {
    precondition {
      condition     = local.az_count >= 2
      error_message = "At least two Availability Zones are required (three recommended)."
    }
    precondition {
      condition     = length(local.private_cidrs) == local.az_count && length(local.public_cidrs) == local.az_count && length(local.intra_cidrs) == local.az_count
      error_message = "Explicit subnet CIDR lists must have one entry per Availability Zone."
    }
  }
}

# Lock down the default security group: no ingress, no egress.
resource "aws_default_security_group" "this" {
  vpc_id = aws_vpc.this.id
  tags   = merge(local.tags, { Name = "${var.name}-default-deny" })
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags   = merge(local.tags, { Name = var.name })
}

# --- Subnets ----------------------------------------------------------------

resource "aws_subnet" "public" {
  count                   = local.az_count
  vpc_id                  = aws_vpc.this.id
  cidr_block              = local.public_cidrs[count.index]
  availability_zone       = local.azs[count.index]
  map_public_ip_on_launch = false
  tags = merge(local.tags, local.cluster_tag, {
    Name                     = "${var.name}-public-${local.azs[count.index]}"
    Tier                     = "public"
    "kubernetes.io/role/elb" = "1"
  })
}

resource "aws_subnet" "private" {
  count             = local.az_count
  vpc_id            = aws_vpc.this.id
  cidr_block        = local.private_cidrs[count.index]
  availability_zone = local.azs[count.index]
  tags = merge(local.tags, local.cluster_tag, {
    Name                              = "${var.name}-private-${local.azs[count.index]}"
    Tier                              = "private"
    "kubernetes.io/role/internal-elb" = "1"
  })
}

resource "aws_subnet" "intra" {
  count             = local.az_count
  vpc_id            = aws_vpc.this.id
  cidr_block        = local.intra_cidrs[count.index]
  availability_zone = local.azs[count.index]
  tags = merge(local.tags, {
    Name = "${var.name}-intra-${local.azs[count.index]}"
    Tier = "intra"
  })
}

# --- Routing ----------------------------------------------------------------

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
  tags   = merge(local.tags, { Name = "${var.name}-public" })
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "public" {
  count          = local.az_count
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_eip" "nat" {
  count  = local.nat_count
  domain = "vpc"
  tags   = merge(local.tags, { Name = "${var.name}-nat-${local.azs[count.index]}" })
}

resource "aws_nat_gateway" "this" {
  count         = local.nat_count
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id
  tags          = merge(local.tags, { Name = "${var.name}-nat-${local.azs[count.index]}" })

  depends_on = [aws_internet_gateway.this]
}

# One private route table per AZ so each AZ egresses through its own NAT
# gateway (an AZ outage does not take the other AZs' egress with it).
resource "aws_route_table" "private" {
  count  = local.az_count
  vpc_id = aws_vpc.this.id
  tags   = merge(local.tags, { Name = "${var.name}-private-${local.azs[count.index]}" })
}

resource "aws_route" "private_nat" {
  count                  = local.nat_count > 0 ? local.az_count : 0
  route_table_id         = aws_route_table.private[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this[var.single_nat_gateway ? 0 : count.index].id
}

resource "aws_route_table_association" "private" {
  count          = local.az_count
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

resource "aws_route_table" "intra" {
  vpc_id = aws_vpc.this.id
  tags   = merge(local.tags, { Name = "${var.name}-intra" })
}

resource "aws_route_table_association" "intra" {
  count          = local.az_count
  subnet_id      = aws_subnet.intra[count.index].id
  route_table_id = aws_route_table.intra.id
}

# --- VPC endpoints ----------------------------------------------------------

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${data.aws_region.current.name}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = concat(aws_route_table.private[*].id, [aws_route_table.intra.id])
  tags              = merge(local.tags, { Name = "${var.name}-s3" })
}

resource "aws_security_group" "endpoints" {
  count       = length(var.interface_endpoints) > 0 ? 1 : 0
  name        = "${var.name}-vpc-endpoints"
  description = "HTTPS from inside the VPC to interface endpoints"
  vpc_id      = aws_vpc.this.id
  tags        = merge(local.tags, { Name = "${var.name}-vpc-endpoints" })
}

resource "aws_vpc_security_group_ingress_rule" "endpoints_https" {
  count             = length(var.interface_endpoints) > 0 ? 1 : 0
  security_group_id = aws_security_group.endpoints[0].id
  cidr_ipv4         = var.cidr_block
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  description       = "HTTPS from the VPC"
}

resource "aws_vpc_endpoint" "interface" {
  for_each            = toset(var.interface_endpoints)
  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.${each.value}"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.endpoints[0].id]
  tags                = merge(local.tags, { Name = "${var.name}-${each.value}" })
}

# --- Flow logs --------------------------------------------------------------

resource "aws_cloudwatch_log_group" "flow_logs" {
  count             = var.enable_flow_logs ? 1 : 0
  name              = "/aws/vpc/${var.name}/flow-logs"
  retention_in_days = var.flow_log_retention_days
  kms_key_id        = var.flow_log_kms_key_arn
  tags              = local.tags
}

data "aws_iam_policy_document" "flow_logs_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["vpc-flow-logs.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "flow_logs" {
  count              = var.enable_flow_logs ? 1 : 0
  name               = "${var.name}-flow-logs"
  assume_role_policy = data.aws_iam_policy_document.flow_logs_assume.json
  tags               = local.tags
}

data "aws_iam_policy_document" "flow_logs" {
  count = var.enable_flow_logs ? 1 : 0
  statement {
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogGroups",
      "logs:DescribeLogStreams",
    ]
    resources = [aws_cloudwatch_log_group.flow_logs[0].arn, "${aws_cloudwatch_log_group.flow_logs[0].arn}:*"]
  }
}

resource "aws_iam_role_policy" "flow_logs" {
  count  = var.enable_flow_logs ? 1 : 0
  name   = "${var.name}-flow-logs"
  role   = aws_iam_role.flow_logs[0].id
  policy = data.aws_iam_policy_document.flow_logs[0].json
}

resource "aws_flow_log" "this" {
  count                    = var.enable_flow_logs ? 1 : 0
  vpc_id                   = aws_vpc.this.id
  traffic_type             = "ALL"
  log_destination_type     = "cloud-watch-logs"
  log_destination          = aws_cloudwatch_log_group.flow_logs[0].arn
  iam_role_arn             = aws_iam_role.flow_logs[0].arn
  max_aggregation_interval = 60
  tags                     = local.tags
}
