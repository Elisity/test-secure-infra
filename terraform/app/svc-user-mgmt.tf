locals {
  // keycloak_user_realm_client_secret = "FIXME"
  elisity_auditlogs = "false"  
  keycloak_admin_realm_name = "master"
  keycloak_admin_realm_username = data.terraform_remote_state.app-services.outputs["keycloak_admin_realm_user"]
  keycloak_admin_realm_password = data.terraform_remote_state.app-services.outputs["keycloak_admin_realm_password"]
  keycloak_admin_realm_client_id = "admin-cli"
  keycloak_user_realm_name = "elisity"
}

resource "duplocloud_k8_secret" "keycloak" {
  tenant_id = local.tenant_id

  secret_name = "eli-keycloak"
  secret_type = "Opaque"
  secret_data = jsonencode({
    "keycloak.admin-realm.name" = local.keycloak_admin_realm_name,
    "keycloak.admin-realm.username" = local.keycloak_admin_realm_username,
    "keycloak.admin-realm.password" = local.keycloak_admin_realm_password,
    "keycloak.admin-realm.client.id" = local.keycloak_admin_realm_client_id,
    "keycloak.user-realm.name" = local.keycloak_user_realm_name,
  })
}

resource "duplocloud_k8_config_map" "keycloak" {
  tenant_id = local.tenant_id

  name = "eli-keycloak"
  data = jsonencode({
    "keycloak.server" = "http://keycloak-service:8080/auth",
    "keycloak.secure-server" = "https://keycloak-service:8443/auth",
    "keycloak.admin-realm.url" = "http://keycloak-service:8080/auth/realms/master",
    "keycloak.user-realm.url" = "http://keycloak-service:8080/auth/realms/elisity",
    "keycloak.internal-realm.url" = "http://keycloak-service:8080/auth/realms/elisity-internal",
  })
}

module "user-mgmt-service" {
  source = "../modules/elisity-microservice"

  tenant_id = local.tenant_id
  name  = "user-mgmt"
  service_defaults = local.service_defaults

  replicas = local.default_replicas

  env = concat(
    [ { name = "elisity.auditlogs", value = local.elisity_auditlogs }, ],
    local.common_envs
  )
  
  env_from = [
    { type = "configmap", name = duplocloud_k8_config_map.common.name },
    { type = "configmap", name = duplocloud_k8_config_map.keycloak.name },
    { type = "secret", name = duplocloud_k8_secret.keycloak.secret_name },
  ]
}
