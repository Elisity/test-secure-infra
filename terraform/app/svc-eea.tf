module "eea-service" {
  source = "../modules/elisity-microservice"

  tenant_id = local.tenant_id
  name  = "eea"
  service_defaults = local.service_defaults

  replicas = local.default_replicas

  env = concat(
    [
      { name = "server.port", value = "8105" },
      { name = "server.servlet.context-path", value = "/eeasvc" },
      { name = "customer.domain", value = local.customer_subdomain },
    ],
    local.common_envs
  )
  
  env_from = [
    { type = "configmap", name = duplocloud_k8_config_map.common.name },
    { type = "configmap", name = duplocloud_k8_config_map.auth.name },
    { type = "secret", name = duplocloud_k8_secret.auth.secret_name },
    { type = "configmap", name = local.mongodb_configmap_name },
    { type = "secret", name = local.mongodb_secret_name },
  ]

  ports = [
    { container_port = 8105, name = "server", protocol = "TCP" },
    { container_port = 8105, name = "management", protocol = "TCP" }
  ]

  service = { port = "8105", external_port = 8105, protocol = "tcp" }
}
