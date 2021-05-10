#!/bin/bash -eu

tenant="$1" ; shift
case "$tenant" in
default|compliance)
  echo "Tenant cannot be named: $tenant" 1>&2
  exit 1
  ;;
dev|test)
  infra="devtest"
  ;;
*)
  infra="$tenant"
  ;;
esac

# Which project to run.
selection="${1:-}"
[ $# -eq 0 ] || shift

# Load environment and utility programs.
export infra tenant
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/_util.sh"
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/_env.sh"

# Utility function to run "terraform plan" with proper arguments, and clean state.
tf_plan() {
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

  local tf_args=( -input=false "$@" )
  [ "$project" != "base-infra" ] && tf_args=( "${tf_args[@]}" -var "infra_name=$infra" )
  local varfile="config/$cfg/$project.tfvars.json"
  [ -f "$varfile" ] && tf_args=( "${tf_args[@]}" "-var-file=../../$varfile" )

  echo "Project: $project"

  # shellcheck disable=SC2086    # NOTE: we want word splitting
  (cd "terraform/$project" &&
      tf_init $backend &&
      ( tf workspace select "$ws" || tf workspace new "$ws" ) &&
      tf plan "${tf_args[@]}" )
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

tf_plan base-infra "$@"
tf_plan app-services "$@"

# Special logic to due to apply being able to force-reload application pods.
if [ -z "$selection" ] || [ "$selection" == "app" ]; then

  # Default to the prior time (unless it is missing).
  loadtime="$(tf_output app | jq -r .loadtime.value)"
  if [ -n "$loadtime" ] && [ "$loadtime" != "null" ]; then
    tf_plan app "$@" -var upgrade_time="$loadtime"
  else
    tf_plan app "$@"
  fi
fi
