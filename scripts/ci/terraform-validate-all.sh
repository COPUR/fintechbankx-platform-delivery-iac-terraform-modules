#!/usr/bin/env bash
# Validate every Terraform root in the repo without credentials or state:
#   1. terraform fmt -check -recursive
#   2. init -backend=false + validate for modules/*, examples/*, stacks/*,
#      services/* and tests/consumer-compat/*
#   3. type-check stacks/*/environments/*.tfvars.example against the stack
#      variables (terraform console with a temporary local-backend override)
# Usage: scripts/ci/terraform-validate-all.sh   (TERRAFORM=/path/to/terraform)
set -euo pipefail

TF="${TERRAFORM:-terraform}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

export TF_IN_AUTOMATION=1
export TF_PLUGIN_CACHE_DIR="${TF_PLUGIN_CACHE_DIR:-$ROOT/.terraform-plugin-cache}"
export TF_PLUGIN_CACHE_MAY_BREAK_DEPENDENCY_LOCK_FILE=true
mkdir -p "$TF_PLUGIN_CACHE_DIR"

failures=0

echo "== terraform fmt -check -recursive"
if ! "$TF" fmt -check -recursive -diff; then
  echo "::error::terraform fmt found unformatted files"
  failures=$((failures + 1))
fi

clean() { rm -rf "$1/.terraform" "$1/.terraform.lock.hcl" "$1/zz_ci_local_backend_override.tf"; }

mapfile -t roots < <(
  for d in modules/* examples/* stacks/* services/* tests/consumer-compat/*; do
    [ -d "$d" ] && compgen -G "$d/*.tf" >/dev/null && echo "$d"
  done
)

for d in "${roots[@]}"; do
  echo "== validate $d"
  if ! (cd "$d" && "$TF" init -backend=false -input=false -no-color >/dev/null && "$TF" validate -no-color); then
    echo "::error::terraform validate failed in $d"
    failures=$((failures + 1))
  fi
  clean "$d"
done

for stack in stacks/*; do
  compgen -G "$stack/environments/*.tfvars.example" >/dev/null || continue
  trap 'clean "$stack"' EXIT
  printf 'terraform {\n  backend "local" {}\n}\n' > "$stack/zz_ci_local_backend_override.tf"
  (cd "$stack" && "$TF" init -input=false -no-color -reconfigure >/dev/null)
  for vars in "$stack"/environments/*.tfvars.example; do
    echo "== type-check $vars"
    if ! (cd "$stack" && echo 'var.environment' | "$TF" console -no-color -var-file="environments/$(basename "$vars")" >/dev/null); then
      echo "::error::$vars does not match the variables of $stack"
      failures=$((failures + 1))
    fi
  done
  clean "$stack"
  rm -f "$stack/terraform.tfstate"
  trap - EXIT
done

echo "== ${#roots[@]} roots validated, $failures failure(s)"
[ "$failures" -eq 0 ]
