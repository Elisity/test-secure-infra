#!/bin/bash -eu

: "${DUPLO_TF_PROVIDER_VERSION=0.5.22}"
export DUPLO_TF_PROVIDER_VERSION

# OS detection
case "$(uname -s)" in
Darwin)
  export TOOL_OS="darwin"
  ;;
Linux)
  export TOOL_OS="linux"
  ;;
esac

# Utility function for a fatal error.
die() {
  echo "$0:" "$@" 1>&2
  exit 1
}

# Utility function to log a command before running it.
logged() {
  echo "$0:" "$@" 1>&2
  "$@"
}

# Utility function to make a duplo API call with curl, and output JSON.
duplo_api() {
    local path="${1:-}"
    [ $# -eq 0 ] || shift

    [ -z "${path:-}" ] && die "internal error: no API path was given"
    [ -z "${duplo_host:-}" ] && die "internal error: duplo_host environment variable must be set"
    [ -z "${duplo_token:-}" ] && die "internal error: duplo_token environment variable must be set"

    curl -Ssf -H 'Content-type: application/json' -H "Authorization: Bearer $duplo_token" "$@" "${duplo_host}/${path}"
}

# Utility function to set up AWS credentials before running a command.
with_aws() {
  # Run the command in the configured way.
  case "${AWS_RUNNER:-duplo-admin}" in
  env)
    [ -z "${profile:-}" ] && die "internal error: no AWS profile selected"
    env AWS_PROFILE="$profile" AWS_SDK_LOAD_CONFIG=1 "$@"
    ;;
  duplo-admin)
    # Get just-in-time AWS credentials from Duplo and use them to execute the command.
    # shellcheck disable=SC2046     # NOTE: we want word splitting
    env $( duplo_api adminproxy/GetJITAwsConsoleAccessUrl |
            jq -r '{AWS_ACCESS_KEY_ID: .AccessKeyId, AWS_SECRET_ACCESS_KEY: .SecretAccessKey, AWS_DEFAULT_REGION: .Region, AWS_SESSION_TOKEN: .SessionToken} | to_entries | map("\(.key)=\(.value)") | .[]'
        ) AWS_SDK_LOAD_CONFIG=1 "$@"
    ;;
  duplo)
    [ -z "${DUPLO_TENANT_ID:-}" ] && die "error: DUPLO_TENANT_ID environment variable missing or empty"

    # Get just-in-time AWS credentials from Duplo and use them to execute the command.
    # shellcheck disable=SC2046     # NOTE: we want word splitting
    env $( duplo_api "subscriptions/${DUPLO_TENANT_ID:-}/GetAwsConsoleTokenUrl" |
            jq -r '{AWS_ACCESS_KEY_ID: .AccessKeyId, AWS_SECRET_ACCESS_KEY: .SecretAccessKey, AWS_DEFAULT_REGION: .Region, AWS_SESSION_TOKEN: .SessionToken} | to_entries | map("\(.key)=\(.value)") | .[]'
        ) AWS_SDK_LOAD_CONFIG=1 "$@"
    ;;
  esac
}

# Utility function to run Terraform with AWS credentials.
# Also logs the command.
tf() {
  logged with_aws terraform "$@"
}

# Utility function to run "terraform init" with proper arguments, and clean state.
tf_init() {
  rm -f .terraform/environment .terraform/terraform.tfstate

  # NOTE: This will go away once the Terraform provider is official listed in the registry.
  local tf_provider_dir="${HOME}/.terraform.d/plugins/registry.terraform.io/duplocloud/duplocloud/${DUPLO_TF_PROVIDER_VERSION}/${TOOL_OS}_amd64"
  local tf_provider_bin="${tf_provider_dir}/terraform-provider-duplocloud"
  mkdir -p "$tf_provider_dir"
  [ -f "$tf_provider_bin" ] || curl -SsLfo "$tf_provider_bin" \
      "https://github.com/duplocloud/terraform-provider-duplocloud/releases/download/${DUPLO_TF_PROVIDER_VERSION}/terraform-provider-duplocloud_${DUPLO_TF_PROVIDER_VERSION}_${TOOL_OS}_amd64"
  [ -x "$tf_provider_bin" ] || chmod +x "$tf_provider_bin"

  tf init "$@"
}
