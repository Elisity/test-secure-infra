#!/bin/bash -eu

case "$1" in
create|delete)
  ;;
*)
  echo "$0 [create|delete]" 1>&2
  exit 1
  ;;
esac

# Get the subordinate (current) AWS account ID.
ONBOARD_ACCOUNT_ID="$(aws sts get-caller-identity | jq -r .Account)"

# Get the master AWS account credentials.
master_creds="$(aws secretsmanager get-secret-value --secret-id elisity-master-awscreds --version-stage AWSCURRENT | jq -r .SecretString)"
unset AWS_PROFILE
AWS_ACCESS_KEY_ID="$(echo "$master_creds" | jq -r .accessKeyId)"
AWS_SECRET_ACCESS_KEY="$(echo "$master_creds" | jq -r .secretAccessKey)"
export AWS_REGION=us-east-2 AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY

# Get the master AWS account ID.
MASTER_ACCOUNT_ID="$(aws sts get-caller-identity | jq -r .Account)"

# Get the list of ECR repositories as a bash array.
repos=()
while IFS='' read -r line; do repos+=("$line"); done < <(aws ecr describe-repositories --region us-east-2 | jq -r .repositories[].repositoryName)

# Onboard or offboard an account to each ECR repository.
for repo in "${repos[@]}"; do
  policy="$(aws ecr get-repository-policy --repository-name "$repo" 2>/dev/null | jq -r .policyText || true)"

  # Start with a default policy, if there is no policy.
  if [ -z "$policy" ]; then
    policy='{
  "Version" : "2012-10-17",
  "Statement" : [ {
    "Sid" : "FullAccess",
    "Effect" : "Allow",
    "Principal" : {
      "AWS" : "arn:aws:iam::'"$MASTER_ACCOUNT_ID"':root"
    },
    "Action" : "ecr:*"
  } ]
}'
  fi

  # Determine the statement ID to target.
  stmt_id="ReadFromAwsAccount${ONBOARD_ACCOUNT_ID}"
  stmt_present="$(echo "$policy" | jq -r 'any(.Statement[].Sid == "'"$stmt_id"'"; .)')"

  # Onboard an account into the ECR
  if [ "$1" == "create" ]; then

    # Check if the policy already has the statement
    if [ "$stmt_present" == "false" ]; then

      # Merge the new statement into the policy.
      new_policy="$(echo "$policy" | jq '.Statement += [{
  "Sid": "'"$stmt_id"'",
  "Effect": "Allow",
  "Principal": {
    "AWS": "arn:aws:iam::'"$ONBOARD_ACCOUNT_ID"':root"
  },
  "Action": [
    "ecr:GetDownloadUrlForLayer",
    "ecr:BatchCheckLayerAvailability",
    "ecr:BatchGetImage",
    "ecr:ListImages"
  ]
}]')"
      aws ecr set-repository-policy --repository-name "$repo" --policy-text "$new_policy" >/dev/null
      echo "$0: aws account $ONBOARD_ACCOUNT_ID: $repo: added read access"
    else
      echo "$0: aws account $ONBOARD_ACCOUNT_ID: $repo: already has read access"
    fi

  # Offboard an account from ECR
  else

    # Check if the policy already has the statement
    if [ "$stmt_present" == "true" ]; then

      # Delete the statement from the policy
      new_policy="$(echo "$policy" | jq -r 'del(.Statement[] | select(.Sid == "'"$stmt_id"'"))')"
      aws ecr set-repository-policy --repository-name "$repo" --policy-text "$new_policy" >/dev/null
      echo "$0: aws account $ONBOARD_ACCOUNT_ID: $repo: removed read access"
    else
      echo "$0: aws account $ONBOARD_ACCOUNT_ID: $repo: does not have read access"
    fi

  fi
done
