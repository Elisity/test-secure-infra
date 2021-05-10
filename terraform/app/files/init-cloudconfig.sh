#!/bin/bash -eu

# NOTE:
#  - The elisity-initializer module takes care of the "source /app/scripts/setup.sh" for us.
#  - Sourcing that scripts exports 5 functions:  msg err die state_can_run state_update
#
# See:   terraform/modules/elisity-initializer/files/setup.sh
#

# Sensible defaults.
export service_hostname="${1:-elisity-cloud-configuration-service}" service_port="${2:-8080}"

# Utility function to post an API call to the cloud configuration service.
cloudconfig_post() {
  local subpath="$1" data="$2"
  curl -Ssf -H 'Content-type: application/json' -XPOST "http://${service_hostname}:${service_port}/api/v1/cloudconfig/$subpath" -d "$data"
}

# Configure the AWS creds used to manage the Elisity master account.
msg "001: Configure the Elisity master AWS creds."
master_creds="$(aws secretsmanager get-secret-value --secret-id elisity-master-awscreds --version-stage AWSCURRENT | jq -r .SecretString)"
if state_can_run 001; then
  cloudconfig_post awscloudsecuritycredentialsconfig "$master_creds"
  state_update 001 yes
fi

# Configure the AWS cloud services that cloudconfig will utility, in the various regions.
msg "002: Configure the cloud services."
if state_can_run 002; then
  # add the access key id to the partial JSON
  mkdir -p /app/temp
  access_key_id="$(echo "$master_creds" | jq -r .accessKeyId)"
  jq '.regions[].awsServices[] += {"accessKeyId" : "'"$access_key_id"'"}' </app/scripts/cloudservice.partial.json >/app/temp/cloudservice.json

  # submit the newly written config
  cloudconfig_post cloudservices @/app/temp/cloudservice.json
  state_update 002 yes
fi

# Configure the AWS cloud services that cloudconfig will utility, in the various regions.
msg "003: Configure the ARN credentials."
if state_can_run 003; then
  cloudconfig_post aws/credential/arn @/app/scripts/arncreds.json
  state_update 003 yes
fi
