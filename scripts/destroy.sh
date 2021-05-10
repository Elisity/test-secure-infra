#!/bin/bash -eu

tenant="$1" ; shift

# Which project to run.
selection="${1:-}"
[ $# -eq 0 ] || shift

# Load environment and utility programs.
export tenant
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/_util.sh"
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/_env.sh"

# Utility function to run "terraform destroy" with proper arguments, and clean state.
tf_destroy() {
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

  local tf_args=( -auto-approve -input=false )
  [ "$project" != "base-infra" ] && tf_args=( "${tf_args[@]}" -var "infra_name=$infra" )
  local varfile="config/$cfg/$project.tfvars.json"
  [ -f "$varfile" ] && tf_args=( "${tf_args[@]}" "-var-file=../../$varfile" )

  echo "Project: $project"

  # shellcheck disable=SC2086    # NOTE: we want word splitting
  (cd "terraform/$project" &&
      tf_init $backend &&
      if tf workspace select "$ws"; then
        tf destroy "${tf_args[@]}" && tf workspace select default && tf workspace delete "$ws"
      fi)
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

tf_destroy app "$@"
tf_destroy app-services "$@"
tf_destroy base-infra "$@"
