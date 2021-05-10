// Scripts for cloud config initialization.
resource "duplocloud_k8_config_map" "scripts" {
  tenant_id = var.tenant_id
  name = "init-${var.name}-scripts"
  data = jsonencode(merge(var.files, {
    "setup.sh" = file("${path.module}/files/setup.sh")
    "run.sh"   = var.script
  }))
}

// Initialize cloud config
resource "kubernetes_job" "this" {
  depends_on = [ kubernetes_role_binding.this ]

  timeouts {
    create = "5m"
    update = "5m"
  }

  metadata {
    name = "init-${var.name}"
    namespace = var.namespace
  }

  spec {
    backoff_limit = 4

    template {
      metadata {}

      spec {
        service_account_name = kubernetes_service_account.this.metadata[0].name

        container {
          name = "initializer"
          image = var.image
          command = concat([
            "bash",
            "-c",
            "source /app/scripts/setup.sh && /app/scripts/run.sh \"$@\"",
            "--"
          ], var.script_args)

          volume_mount {
            name = "scripts"
            mount_path = "/app/scripts"
            read_only = true
          }

          volume_mount {
            name = "state"
            mount_path = "/app/prior-state"
            read_only = true
          }

          volume_mount {
            name = "temp"
            mount_path = "/app/temp"
            read_only = false
          }

          env {
            name = "AWS_REGION"
            value = data.duplocloud_tenant_aws_region.this.aws_region
          }
          env {
            name = "AWS_DEFAULT_REGION"
            value = data.duplocloud_tenant_aws_region.this.aws_region
          }
          env {
            name = "KUBECTL_VERSION"
            value = var.kubectl_version
          }
          env {
            name = "SCRIPT_NAME"
            value = "init-${var.name}"
          }
          env {
            name = "DEPENDENT_DEPLOYMENT"
            value = coalesce(var.dependent_deployment, "elisity-${var.name}-service")
          }
          env {
            name = "EXTRA_SLEEP"
            value = var.extra_sleep
          }
          env {
            name = "STATE_CONFIGMAP"
            value = "init-${var.name}-state"
          }
          env {
            name = "STATE_STEPS"
            value = join(" ", var.steps)
          }

          dynamic "env" {
            for_each = var.env

            content {
              name = each.value["name"]
              value = each.value["value"]
            }
          }
        }
        restart_policy = "Never"
        node_selector = {
          "tenantname" = var.namespace
        }

        volume {
          name = "scripts"
          config_map {
            name = duplocloud_k8_config_map.scripts.name
            default_mode = "0555"
          }
        }

        volume {
          name = "state"
          config_map {
            name = "init-${var.name}-state"
            default_mode = "0444"
            optional = true
          }
        }

        volume {
          name = "temp"
          empty_dir { }
        }
      }
    }
  }

  wait_for_completion = true
}
