#!/bin/bash -eu

tenant="$1" ; shift

# Which project to run.
selection="${1:-}"
[ $# -eq 0 ] || shift

# Whether or not to force all pods to reload.
reload=no
if [ "${1:-}" == "--reload" ]; then
  reload=yes
  [ $# -eq 0 ] || shift
fi

# Load environment and utility programs.
export tenant

# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/_util.sh"
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/_env.sh"

# Utility function to run "terraform apply" with proper arguments, and clean state.
tf_apply() {
  local project="$1" ; shift

  [ -z "${backend:-}" ] && die "internal error: backend should have been configured by _env.sh"

  # Skip projects that are not selected.
  if [ -n "$selection" ] && [ "$selection" != "$project" ]; then
    return 0;
  fi

  # Determine the terraform workspace and config subdir.
  local ws="$tenant" cfg="$tenant"

  # FUTURE: re-enable shared infra after Elisity application code changes
  # shellcheck disable=SC2154  # scripts/_env.sh exports the infra env var
  # local ws="$infra" cfg="$infra"
  # if [ "$project" != "base-infra" ]; then
  #   cfg="$cfg/$tenant"
  #   ws="$tenant"
  # fi

  local tf_args=( -auto-approve -input=false "$@" )
  [ "$project" != "base-infra" ] && tf_args=( "${tf_args[@]}" -var "infra_name=$infra" )
  local varfile="config/$cfg/$project.tfvars.json"
  [ -f "$varfile" ] && tf_args=( "${tf_args[@]}" "-var-file=../../$varfile" )

  echo "Project: $project"

  # shellcheck disable=SC2086    # NOTE: we want word splitting
  (cd "terraform/$project" &&
    tf_init $backend &&
    ( tf workspace select "$ws" || tf workspace new "$ws" ) &&
    if false && [ "$project" == "app-services" ]; then tf_import_subnets "$ws"; fi && # temporarily disabled
    tf apply "${tf_args[@]}" )
}

tf_output() {
  local project="$1" ; shift

  # Determine the terraform workspace.
  local ws="$tenant"
  [ "$project" == "base-infra" ] && ws="$infra"

  # shellcheck disable=SC2086    # NOTE: we want word splitting
  (cd "terraform/$project" &&
    tf_init $backend 1>&2 &&
    ( tf workspace select "$ws" 1>&2 || tf workspace new "$ws" 1>&2 ) &&
    tf output -json )
}

tf_import_subnets() {
  local json='' ws="$1" tfres

  for zone in A B; do
    tfres='aws_route_table_association.private["'"$zone"'"]'

    # If the route association doesn't exist in the state, we need to import it.
    if ! tf state show "$tfres" >/dev/null 2>&1; then

      # Collect the information about the subnet from base infra.
      [ -n "$json" ] || json="$(cd ../.. && tf_output base-infra)"
      rtb="$(echo "$json" | jq -r .private_route_table_id.value)"
      sn="$(echo "$json" | jq -r '.private_subnets.value[] | select(.zone == "'"$zone"'") | .id')"

      # Import the Terraform state.
      tf import "$tfres" "$rtb/$sn"

      # NOTE: The above logic needs to be tested on new infrastructure - it may require changes.
      # - Does the import work when the desired route table is a different ID than the current rout table?
      # - If not, then we need to make the changes in AWS before importing into Terraform.
    fi
  done
}

tf_apply base-infra "$@"
tf_apply app-services "$@"

# Special logic to support force-reloading application pods.
if [ -z "$selection" ] || [ "$selection" == "app" ]; then

  # Default to the current time, but if we aren't reloading - use the prior time (unless it is missing).
  loadtime="$(TZ=UTC date +%Y-%m-%d-%H-%M-%S)"
  if [ "$reload" == "no" ]; then
    _loadtime="$(tf_output app | jq -r .loadtime.value)"
    [ -n "$_loadtime" ] && [ "$_loadtime" != "null" ] && loadtime="$_loadtime"
  fi

  tf_apply app "$@" -var upgrade_time="$loadtime"
fi
