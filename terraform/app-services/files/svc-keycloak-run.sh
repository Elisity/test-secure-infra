#!/bin/bash

KEYCLOAK_STANDALONE_HA_CONF="/opt/jboss/keycloak/standalone/configuration/standalone-ha.xml"

BASE_SCRIPT_DIR="${BASE_SCRIPT_DIR:-/scripts}"

echo "Starting with args: $*"
cp "$BASE_SCRIPT_DIR/standalone-ha.xml" "$KEYCLOAK_STANDALONE_HA_CONF"

if [ -n "$KEYCLOAK_MGMT_USER" ] && [ -n "$KEYCLOAK_MGMT_PASSWORD" ]; then
    /opt/jboss/keycloak/bin/add-user.sh --user "$KEYCLOAK_MGMT_USER" --password "$KEYCLOAK_MGMT_PASSWORD" --enable --realm ManagementRealm -cw
fi

exec /opt/jboss/tools/docker-entrypoint.sh -b="$MY_POD_IP" -bmanagement=127.0.0.1 -Dcluster.instance.service.address="${KEYCLOAK_SERVICE_HOST}" "$@"
