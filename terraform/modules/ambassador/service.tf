locals {
  lb_type             = var.ambassador_is_internal ? 4 : 1
  certificate_arn     = var.ambassador_is_internal ? null : var.ambassador_certificate_arn
  external_http_port  = var.ambassador_is_internal ? 31000 : 80
  external_https_port = var.ambassador_is_internal ? 8443  : 443
  http_protocol       = var.ambassador_is_internal ? "tcp" : "http"
  https_protocol      = var.ambassador_is_internal ? "tcp" : "https"
  health_check_url    = var.ambassador_is_internal ? null : "/"
}

// Run the internal Ambassador service on Duplo.
resource "duplocloud_duplo_service" "this" {
  tenant_id = var.tenant_id

  name = var.name
  agent_platform = 7
  docker_image   = var.ambassador_image
  replicas       = var.ambassador_replicas

  other_docker_config = jsonencode({
    ServiceAccountName = kubernetes_service_account.this.metadata[0].name,

    Env = [
      { Name = "HOST_IP", ValueFrom = { FieldRef = { FieldPath = "status.hostIP" } } },
      { Name = "AMBASSADOR_NAMESPACE", ValueFrom = { FieldRef = { FieldPath = "metadata.namespace" } } },
      { Name = "AMBASSADOR_SINGLE_NAMESPACE", Value = "true" },
    ],

    Resources = {
      Limits = { cpu = "1", memory = "400Mi" }
      Requests = { cpu = "200m", memory = "100Mi" }
    }

    LivenessProbe = {
      InitialDelaySeconds = 30,
      PeriodSeconds = 3,
      HttpGet = {
        Path = "/ambassador/v0/check_alive",
        Port = 8877,
      }
    }
    ReadinessProbe = {
      InitialDelaySeconds = 30,
      PeriodSeconds = 3,
      HttpGet = {
        Path = "/ambassador/v0/check_ready"
        Port = 8877
      }
    }
    PodSecurityContext = { RunAsUser = "8888" },

    PodAnnotations = {
      "siddecar.istio.io/inject" = "false",
      "consul.hashicorp.com/connect-inject" = "false",
    },
    PodLabels = {
      "service" = var.name
    },

    ServiceAnnotations = var.ambassador_service_annotations
  })
}

# NOTE: This is does not create a load balancer, but rather a K8S service.
#       What it creates is controlled by the lbconfigs.lb_type attribute.
resource "duplocloud_duplo_service_lbconfigs" "this" {
  tenant_id = var.tenant_id

  replication_controller_name = duplocloud_duplo_service.this.name

  lbconfigs {
    lb_type                     = local.lb_type
    external_port               = local.external_http_port
    health_check_url            = local.health_check_url
    is_native                   = false
    port                        = "8080"
    protocol                    = local.http_protocol
    is_internal                 = var.ambassador_is_internal
  }

  # Only expose HTTPS for external ambassador
  dynamic "lbconfigs" {
    for_each = var.ambassador_is_internal ? [] : [true]

    content {
      lb_type                     = local.lb_type
      certificate_arn             = local.certificate_arn
      external_port               = local.external_https_port
      health_check_url            = local.health_check_url
      is_native                   = false
      port                        = "8443"
      protocol                    = local.https_protocol
      is_internal                 = var.ambassador_is_internal
    }
  }

  # Only expose admin for external ambassador
  dynamic "lbconfigs" {
    for_each = var.ambassador_is_internal ? [true] : []

    content {
      external_port               = 31077
      health_check_url            = local.health_check_url
      is_native                   = false
      lb_type                     = local.lb_type
      port                        = "8877"
      protocol                    = local.http_protocol
      is_internal                 = var.ambassador_is_internal
    }
  }
}
resource "duplocloud_duplo_service_params" "this" {
  count = var.ambassador_is_internal ? 0 : 1

  tenant_id = var.tenant_id

  replication_controller_name = duplocloud_duplo_service.this.name
  dns_prfx                    = length(var.dns_prefix) > 0 ? var.dns_prefix : null
  webaclid                    = length(var.waf_id) > 0 ? var.waf_id : null

  enable_access_logs = true
  drop_invalid_headers = true
}
