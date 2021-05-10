#!/bin/bash -eu

# NOTE:
#  - The elisity-initializer module takes care of the "source /app/scripts/setup.sh" for us.
#  - Sourcing that scripts exports 5 functions:  msg err die state_can_run state_update
#
# See:   terraform/modules/elisity-initializer/files/setup.sh
#

# Sensible defaults.
export service_hostname="${1:-elisity-orchestrator-service}" service_port="${2:-8080}"

# Utility function to post an API call to the cloud configuration service.
orchestrator_post() {
  local subpath="$1" data="$2"
  api_result="$(
    curl -Ssf -H 'Content-type: application/json' -XPOST "http://${service_hostname}:${service_port}/api/elisity/orchestrator/v1/$subpath" -d "$data" |
      jq -r .metadata.status
  )"
  [ "$api_result" == "SUCCESS" ] && return 0
  return 1
}

# Configure the AWS creds used to manage the Elisity master account.
msg "001: Configure the Elisity master AWS creds."
master_creds="$(aws secretsmanager get-secret-value --secret-id elisity-master-awscreds --version-stage AWSCURRENT | jq -r .SecretString)"
if state_can_run 001; then
  access_key_id="$(echo "$master_creds" | jq -r .accessKeyId)"
  secret_key_id="$(echo "$master_creds" | jq -r .secretAccessKey)"
  if orchestrator_post configurations/eca '{"awsAccessKey" : "'"$access_key_id"'", "awsAccountId" : "074489987987", "awsSecretKey" : "'"$secret_key_id"'"}'; then
    state_update 001 yes
  else
    state_update 001 error # forces a human being to investigate
    die "001 - failed!"
  fi
fi

# Configure the AWS cloud services that cloudconfig will utility, in the various regions.
msg "002: Configure the customer AWS access."
if state_can_run 002; then
  if orchestrator_post configurations/customeraccessrole @/app/scripts/customeraccessrole.json; then
    state_update 002 yes
  else
    state_update 002 error # forces a human being to investigate
    die "002 - failed!"
  fi
fi

# Configure the AWS cloud services that cloudconfig will utility, in the various regions.
msg "003: Configure the customer profile."
if state_can_run 003; then
  if orchestrator_post configurations/customerprofile @/app/scripts/custprof.json; then
    state_update 003 yes
  else
    state_update 003 error # forces a human being to investigate
    die "003 - failed!"
  fi
fi
