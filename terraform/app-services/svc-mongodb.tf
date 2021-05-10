resource "random_password" "mongodb-root-password" {
  length  = var.mongodb_root_password_length
  number  = true
  special = false
}

resource "random_password" "mongodb-password" {
  length  = var.mongodb_password_length
  number  = true
  special = false
}

resource "random_password" "mongodb-replica-set-key" {
  length  = var.mongodb_replicaset_key_length
  number  = true
  special = false
}

resource "duplocloud_k8_config_map" "mongodb" {
  tenant_id = duplocloud_tenant.this.tenant_id

  name = "mongodb"
  data = jsonencode({
    "spring.data.mongodb.host"       = "mongodb",
    "spring.data.mongodb.port"       = "27017",
  })
}

resource "duplocloud_k8_secret" "mongodb" {
  tenant_id = duplocloud_tenant.this.tenant_id

  secret_type = "Opaque"
  secret_name = "mongodb"
  secret_data = jsonencode({
    "mongodb-password"                            = random_password.mongodb-password.result,
    "mongodb-root-password"                       = random_password.mongodb-root-password.result,
    "spring.data.mongodb.username"                = "root",
    "spring.data.mongodb.password"                = random_password.mongodb-root-password.result,
    "spring.data.mongodb.authentication-database" = "admin"
  })
}

locals {
  mongodb_password = random_password.mongodb-password.result
  mongodb_root_password = random_password.mongodb-root-password.result
}

resource "duplocloud_duplo_service" "mongodb" {
  tenant_id = duplocloud_tenant.this.tenant_id

  name           = "mongodb"
  agent_platform = 7
  docker_image   = var.mongodb_docker_image
  replicas       = 1

  other_docker_config = jsonencode({
    VolumeMounts       = [{ MountPath = "/bitnami/mongodb", Name = "datadir" }],
    PodSecurityContext = { FsGroup = 1001, RunAsUser = 1001 },
    Env = [
      { Name = "BITNAMI_DEBUG", Value = "false" },
      { Name = "MONGODB_USERNAME", Value = "elisity" },
      { Name = "MONGODB_DATABASE", Value = "elisity" },
      { Name = "MONGODB_PASSWORD", ValueFrom = { SecretKeyRef = { Name = duplocloud_k8_secret.mongodb.secret_name, Key = "mongodb-password" } } },
      { Name = "MONGODB_ROOT_PASSWORD", ValueFrom = { SecretKeyRef = { Name = duplocloud_k8_secret.mongodb.secret_name, Key = "mongodb-root-password" } } },
      { Name = "ALLOW_EMPTY_PASSWORD", Value = "no" },
      { Name = "MONGODB_SYSTEM_LOG_VERBOSITY", Value = "0" },
      { Name = "MONGODB_DISABLE_SYSTEM_LOG", Value = "no" },
      { Name = "MONGODB_ENABLE_IPV6", Value = "no" },
      { Name = "MONGODB_ENABLE_DIRECTORY_PER_DB", Value = "no" },
    ]
  })

  volumes = jsonencode([
    { Name       = "datadir",
      Path       = "/bitnami/mongodb",
      AccessMode = "ReadWriteOnce",
    Size = "10Gi" }
  ])
}

# NOTE: This is does not create a load balancer, but rather a K8S service.
#       What it creates is controlled by the lbconfigs.lb_type attribute.
resource "duplocloud_duplo_service_lbconfigs" "mongodb" {
  tenant_id = duplocloud_tenant.this.tenant_id

  replication_controller_name = duplocloud_duplo_service.mongodb.name

  lbconfigs {
    lb_type                     = 3
    port                        = "27017"
    external_port               = 27017
    protocol                    = "tcp"
    replication_controller_name = duplocloud_duplo_service.mongodb.name
  }
}
