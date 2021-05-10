terraform {
  required_version = "~> 0.14"

  required_providers {
    duplocloud = {
      version = "~> 0.5.22"
      source = "registry.terraform.io/duplocloud/duplocloud"
    }
  }
}

locals {
  image_registry = var.service_defaults["registry"]
  image_repository = lookup(var.service_defaults["names"], var.name, "${var.name}-service") 
  image_tag = lookup(var.service_defaults["tags"], var.name, var.service_defaults["default_tag"])

  # Allow overriding the docker image completely, or automatically detecting it.
  image = coalesce(var.image, "${local.image_registry}/${local.image_repository}:${local.image_tag}", null)

  # Pod privileges
  uid = var.uid
  gid = var.gid
  security_context = {
    Capabilities = { Drop = ["ALL"] },
    ReadOnlyRootFilesystem = false,
    RunAsNonRoot = true,
    RunAsUser = var.uid
  }

  # Dynamically calculate docker config.
  raw_docker_config = {
    RestartPolicy      = "Always",
    ServiceAccountName = var.service_account_name,
    PodSecurityContext = var.drop_privileges ? { "FsGroup" = var.gid } : null,
    SecurityContext = var.drop_privileges ? local.security_context : null,
    Env = concat([
      { Name = "tag",      ValueFrom = { FieldRef = { ApiVersion = "v1", FieldPath = "metadata.name" } } },
    ], var.env),
    envFrom = [for ref in var.env_from: ref.type == "configmap" ? { configMapRef = { name = ref.name } } : { secretRef = { name = ref.name } } ],
    Ports = var.ports
  }

  // Remove null values from the map
  other_docker_config = { for k,v in local.raw_docker_config: k => v if v != null }
}

resource "duplocloud_duplo_service" "this" {
  lifecycle {
    //ignore_changes = [docker_image]
  }

  tenant_id = var.tenant_id

  name           = "elisity-${var.name}-service"
  agent_platform = 7

  docker_image   = local.image
  replicas = var.replicas

  volumes = length(var.volumes)==0 ? null : jsonencode(var.volumes)

  other_docker_config = jsonencode(local.other_docker_config)
}

# NOTE: This is does not create a load balancer, but rather a K8S service.
#       What it creates is controlled by the lbconfigs.lb_type attribute.
#
resource "duplocloud_duplo_service_lbconfigs" "this" {
  tenant_id = var.tenant_id

  replication_controller_name = duplocloud_duplo_service.this.name

  lbconfigs {
    lb_type                     = 3
    port                        = var.service.port
    external_port               = var.service.external_port
    protocol                    = var.service.protocol
  }
}
