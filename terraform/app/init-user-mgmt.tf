locals {
  postgres_host = data.terraform_remote_state.app-services.outputs["postgres_host"]
  postgres_port = data.terraform_remote_state.app-services.outputs["postgres_port"]
  postgres_master_username = data.terraform_remote_state.app-services.outputs["postgres_master_username"]
  postgres_master_password = data.terraform_remote_state.app-services.outputs["postgres_master_password"]
  postgres_keycloak_db_name = data.terraform_remote_state.app-services.outputs["postgres_keycloak_db_name"]
}

// Initialize the keycloak database.
# resource "kubernetes_job" "postgres-fix-keycloak-user-table" {
#   depends_on = [ module.user-mgmt-service ]

#   metadata {
#     name = "fix-user"
#     namespace = data.duplocloud_tenant_eks_credentials.this.namespace
#   }
#   spec {
#     template {
#       metadata {}
#       spec {
#         container {
#           name = "fix-user"
#           image = "jberkus/simple-patroni"
#           command = [
#             "psql",
#               "-h", local.postgres_host,
#               "-p", local.postgres_port,
#               "-U", local.postgres_master_username,
#               "-d", "postgres",
#               "-w", "-n",  # Never prompt for a password, and disable command-line editing
#               "-c", "\\c ${local.postgres_keycloak_db_name};",
#               "-c", "alter table user_attribute add unique (name, user_id);"
#           ]
#           env {
#             name = "PGPASSWORD"
#             value = local.postgres_master_password
#           }
#         }
#         restart_policy = "Never"
#       }
#     }
#   }

#   wait_for_completion = true
# }
