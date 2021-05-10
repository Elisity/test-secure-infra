module "ui2-service" {
  source = "../modules/elisity-microservice"

  tenant_id = local.tenant_id
  name  = "ui2"
  service_defaults = local.service_defaults

  replicas = local.default_replicas

  env = concat(
    [ { name = "setup", value = "prod" }, ],
    local.common_envs
  )

  ports = [
    { container_port = 3000, name = "server", protocol = "TCP" },
    { container_port = 3000, name = "management", protocol = "TCP" }
  ]

  service = {
    port                        = "3000"
    external_port               = 3000 
    protocol                    = "tcp"
  }
}
