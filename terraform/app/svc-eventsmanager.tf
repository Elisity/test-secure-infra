module "eventsmanager-service" {
  source = "../modules/elisity-microservice"

  tenant_id = local.tenant_id
  name  = "eventsmanager"
  service_defaults = local.service_defaults

  replicas = local.default_replicas

  env = concat(
    [ { name = "bootstrap.servers", value = local.kafka_bootstrap_address }, ],
    local.common_envs
  )
  
  env_from = [
    { type = "configmap", name = duplocloud_k8_config_map.common.name },
    { type = "configmap", name = duplocloud_k8_config_map.elastic.name },
    { type = "configmap", name = local.mongodb_configmap_name },
    { type = "secret", name = local.mongodb_secret_name },
  ]

  ports = [
    { container_port = 8443, name = "server", protocol = "TCP" },
    { container_port = 8443, name = "management", protocol = "TCP" }
  ]

  service = {
    port                        = "8443"
    external_port               = 8443
    protocol                    = "tcp"
  }
}
