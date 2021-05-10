#!/bin/bash -eu

account="$1" ; shift
echo "$0: 000: prepare script environment"

# We need a reference AWS account to copy secrets from.
: "${ref_profile=elisity-frem01}"
: "${profile=elisity-$account}"
: "${AWS_RUNNER=env}"
export AWS_RUNNER tenant="$account"

# Put in a dummy token until we have one.
eval "${account}_duplo_token=None"

# Load environment and utility programs.
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/_util.sh"
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/_env.sh"

# Copy all secrets from reference account.
ref_secrets=( elisity-aws_lambda_deploy-secrets elisity-master-awscreds elisity-ambassador-certs elisity-dns-awscreds )
echo "$0: 001: copy secrets to $account"
for region in us-west-2 us-east-2; do
  for name in "${ref_secrets[@]}"; do
    result="$(with_aws aws secretsmanager list-secrets --region $region | jq -r 'any(.SecretList[].Name == "'"$name"'"; .)')"
    if [ "$result" == "false" ]; then
      echo "$0: 001: $region: - copy secret '$name'"

      value="$(profile="$ref_profile" with_aws aws secretsmanager get-secret-value --secret-id "$name" | jq -r .SecretString)"
      with_aws aws secretsmanager create-secret --name "$name" --secret-string "$value" --region $region >/dev/null
    else
      echo "$0: 001: $region: - secret '$name' already exists"
    fi
  done
done

# Make sure that we have storage for Terraform state.
#  - S3 bucket
#  - DynamoDB table (for state locking)
echo "$0: 002: ensure TF state storage exists for $account"
bucket="duplo-tfstate-$AWS_ACCOUNT_ID"
result="$(with_aws aws s3api list-buckets --region us-west-2 | jq -r 'any(.Buckets[].Name == "'"$bucket"'"; .)')"
if [ "$result" == "false" ]; then
  echo "$0: 002: - create bucket '$bucket'"

  with_aws aws s3api create-bucket --bucket "$bucket" --region us-west-2 \
    --create-bucket-configuration LocationConstraint=us-west-2 \
    >/dev/null
else
  echo "$0: 002: - bucket '$bucket' already exists"
fi
table="duplo-tfstate-$AWS_ACCOUNT_ID-lock"
result="$(with_aws aws dynamodb list-tables --region us-west-2 | jq -r 'any(.TableNames[] == "'"$table"'"; .)')"
if [ "$result" == "false" ]; then
  echo "$0: 002: - create table '$table'"

  with_aws aws dynamodb create-table --table-name "$table" --region us-west-2 \
    --attribute-definitions 'AttributeName=LockID,AttributeType=S' \
    --key-schema '[{ "AttributeName": "LockID", "KeyType": "HASH" }]' \
    --provisioned-throughput ReadCapacityUnits=5,WriteCapacityUnits=5 \
    --sse-specification '{"Enabled":true,"SSEType":"KMS"}' \
    >/dev/null
else
  echo "$0: 002: - table'$table' already exists"
fi

# Run Terraform to onboard the account.
echo "$0: 003: run terraform/account project"
tf_args=( -var tenant_name="$account" )
[ -f "config/$account/account.tfvars.json" ] && tf_args=( "${tf_args[@]}" -var-file="../../config/$account/account.tfvars.json" )
(cd "terraform/account" &&
    tf_init $backend &&
    tf apply "${tf_args[@]}" )
