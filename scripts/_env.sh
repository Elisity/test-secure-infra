#!/bin/bash -eu

# Detect the infrastructure name
# shellcheck disable=SC2154  # caller sets the tenant env var
case "$tenant" in
default|compliance|tools)
  echo "Tenant cannot be named: $tenant" 1>&2
  exit 1
  ;;

# Tenancy model: aws-account
#
# Each Elisity customer is in it's own AWS account, with it's own duplo host, etc.
*)
  eval "duplo_token=\"\$${tenant/_/-}_duplo_token\""
  eval "duplo_host=\"\${${tenant/_/-}_duplo_host:-'https://elisity-${tenant}.duplocloud.net'}\""
  infra="$tenant"
  ;;

# Tenancy model: shared
#
# FUTURE: re-enable shared infra after Elisity application code changes
# dev)
#   infra="devtest"
#   ;;
# dev[0-9][0-9]|test[0-9][0-9]|qa[0-9][0-9|stage[0-9][0-9])
#   infra="nonprod"
#   ;;
# *)
#   infra="prod"
#   ;;
esac

# Get the AWS account ID
if [ "${AWS_RUNNER:-duplo-admin}" == "env" ]; then
  AWS_ACCOUNT_ID="$(with_aws aws sts get-caller-identity | jq -r .Account)"
else
  AWS_ACCOUNT_ID="$(duplo_api adminproxy/GetAwsAccountId | jq -r .)"
fi

backend="-backend-config=bucket=duplo-tfstate-${AWS_ACCOUNT_ID} -backend-config=dynamodb_table=duplo-tfstate-${AWS_ACCOUNT_ID}-lock"

# Test required environment variables
for key in infra duplo_token duplo_host backend AWS_ACCOUNT_ID
do
  eval "[ -n \"\${${key}:-}\" ]" || die "error: $key: environment variable missing or empty"
done

export infra duplo_host duplo_token backend AWS_ACCOUNT_ID

# Get information specific to git
: "${GITHUB_SHA=$(git rev-parse HEAD)}"
: "${GITHUB_SHORT_SHA=$(git rev-parse --short HEAD)}"
: "${GITHUB_REF=$(git rev-parse --abbrev-ref HEAD)}"
: "${GITHUB_TAG=$(git describe --exact-match --tags "$(git log -n1 --pretty='%h')" 2>/dev/null)}"

export GITHUG_SHA GITHUB_SHORT_SHA GITHUB_REF GITHUB_TAG
