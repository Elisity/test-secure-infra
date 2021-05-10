module "searchmgr-service" {
  source = "../modules/elisity-microservice"

  tenant_id = local.tenant_id
  name  = "searchmgr"
  service_defaults = local.service_defaults

  replicas = local.default_replicas

  env = local.common_envs
  
  env_from = [
    { type = "configmap", name = duplocloud_k8_config_map.common.name },
    { type = "configmap", name = duplocloud_k8_config_map.analytics.name },
    { type = "configmap", name = local.mongodb_configmap_name },
    { type = "configmap", name = duplocloud_k8_config_map.log-elastic.name },
    { type = "secret", name = local.mongodb_secret_name },
  ]
}
