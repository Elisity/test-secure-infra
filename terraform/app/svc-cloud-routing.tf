module "cloud-routing-service" {
  source = "../modules/elisity-microservice"

  tenant_id = local.tenant_id
  name  = "cloud-routing"
  service_defaults = local.service_defaults

  replicas = local.default_replicas

  env = concat(
    [ { name = "server.address", value = "0.0.0.0" } ],
    local.common_envs
  )
  
  env_from = [
    { type = "configmap", name = duplocloud_k8_config_map.common.name },
    { type = "configmap", name = local.mongodb_configmap_name },
    { type = "secret", name = local.mongodb_secret_name },
  ]
}
