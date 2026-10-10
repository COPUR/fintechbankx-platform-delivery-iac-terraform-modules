output "vpc_id" {
  description = "VPC id."
  value       = aws_vpc.this.id
}

output "vpc_cidr_block" {
  description = "VPC CIDR."
  value       = aws_vpc.this.cidr_block
}

output "azs" {
  description = "Availability Zones in subnet order."
  value       = local.azs
}

output "public_subnet_ids" {
  description = "Public subnet ids (one per AZ)."
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "Private subnet ids (one per AZ) for EKS, MSK, Aurora, ElastiCache."
  value       = aws_subnet.private[*].id
}

output "intra_subnet_ids" {
  description = "Intra subnet ids (no internet route)."
  value       = aws_subnet.intra[*].id
}

output "private_route_table_ids" {
  description = "Private route table ids (one per AZ)."
  value       = aws_route_table.private[*].id
}

output "nat_public_ips" {
  description = "NAT gateway Elastic IPs (allow-list these at partners)."
  value       = aws_eip.nat[*].public_ip
}

output "vpc_endpoint_security_group_id" {
  description = "Security group of the interface endpoints."
  value       = length(aws_security_group.endpoints) > 0 ? aws_security_group.endpoints[0].id : null
}

output "public_subnet_cidrs" {
  description = "Public subnet CIDRs."
  value       = aws_subnet.public[*].cidr_block
}

output "private_subnet_cidrs" {
  description = "Private subnet CIDRs (EKS pods/nodes, MSK brokers, Aurora). For egress allow-lists such as Istio ServiceEntry/Sidecar."
  value       = aws_subnet.private[*].cidr_block
}

output "intra_subnet_cidrs" {
  description = "Intra subnet CIDRs."
  value       = aws_subnet.intra[*].cidr_block
}

output "interface_endpoint_services" {
  description = "Service suffixes of the interface endpoints created (e.g. ssm, ssmmessages, kms)."
  value       = sort(keys(aws_vpc_endpoint.interface))
}
