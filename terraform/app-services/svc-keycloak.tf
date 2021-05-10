locals {
  keycloak_db_name = "keycloak"
  keycloak_user = "keycloak"
  keycloak_mgmt_user = "keycloak"

  keycloak_http_node_port = 32080
  keycloak_https_node_port = 32443

  keycloak_replicas = 1
  keycloak_image = "jboss/keycloak:4.8.3.Final"

  keycloak_ports = [
    { name = "http", port = 8080 },
    { name = "https", port = 8443 },
    { name = "management", port = 9090 },
    { name = "jgroups-tcp", port = 7600 },
    { name = "jgroups-tcp-fd", port = 57600 },
    { name = "jgroups-udp", port = 55200, protocol = "UDP" },
    { name = "jgroups-udp-mc", port = 45688, protocol = "UDP" },
    { name = "jgroups-udp-fd", port = 54200, protocol = "UDP" },
    { name = "modcluster", port = 23364 },
    { name = "modcluster-udp", port = 23364, protocol = "UDP" },
    { name = "txn-recovery-ev", port = 4712, },
    { name = "txn-status-mgr", port = 4713 }
  ]
}

resource "random_password" "keycloak-password" {
  length  = var.keycloak_password_length
  number  = true
  special = false
}

// Initialize the keycloak database.
resource "kubernetes_job" "postgres-create-keycloak-db" {
  depends_on = [
    duplocloud_rds_instance.postgres,
    duplocloud_aws_host.eks-node
  ]

  metadata {
    name = "init-postgres"
    namespace = data.duplocloud_tenant_eks_credentials.this.namespace
  }
  spec {
    template {
      metadata {}
      spec {
        container {
          name = "init-postgres"
          image = "jberkus/simple-patroni"
          command = [
            "psql",
              "-h", duplocloud_rds_instance.postgres.host,
              "-p", duplocloud_rds_instance.postgres.port,
              "-U", duplocloud_rds_instance.postgres.master_username,
              "-d", "postgres",
              "-w", "-n",  # Never prompt for a password, and disable command-line editing
              "-c", "create database ${local.keycloak_db_name};"
          ]
          env {
            name = "PGPASSWORD"
            value = duplocloud_rds_instance.postgres.master_password
          }
        }
        restart_policy = "Never"
      }
    }
  }

  wait_for_completion = true
}

// Create the keycloak configuration
resource "duplocloud_k8_secret" "keycloak" {
  tenant_id = duplocloud_tenant.this.tenant_id

  secret_name = "keycloak-secret"
  secret_type = "Opaque"
  secret_data = jsonencode({
    POSTGRES_PASSWORD = duplocloud_rds_instance.postgres.master_password,
    KEYCLOAK_PASSWORD = random_password.keycloak-password.result,
    KEYCLOAK_MGMT_PASSWORD = random_password.keycloak-password.result,
  })
}
resource "duplocloud_k8_config_map" "keycloak-env" {
  tenant_id = duplocloud_tenant.this.tenant_id

  name = "keycloak-env"

  data = jsonencode({
    "POSTGRES_HOST" = duplocloud_rds_instance.postgres.host,
    "POSTGRES_PORT" = tostring(duplocloud_rds_instance.postgres.port),
    "POSTGRES_DATABASE" = local.keycloak_db_name,
    "POSTGRES_USER" = duplocloud_rds_instance.postgres.master_username,
    "POXY_ADDRESS_FORWARDING" = "true",
    "KEYCLOAK_USER" = local.keycloak_user,
    "KEYCLOAK_MGMT_USER" = local.keycloak_mgmt_user,
    "BASE_SCRIPT_DIR" = "/scripts",
    "KEYCLOAK_OWNERS_COUNT" = "2"
  })
}
resource "duplocloud_k8_config_map" "keycloak-scripts" {
  tenant_id = duplocloud_tenant.this.tenant_id

  name = "keycloak-scripts-cm"

  data = jsonencode({
    "REPLICAS" = "2",
    "run.sh" = file("${path.module}/files/svc-keycloak-run.sh"),
    "standalone-ha.xml" = file("${path.module}/files/svc-keycloak-standalone-ha.xml"),
  })
}

// Create the keycloak services.
resource "duplocloud_duplo_service" "keycloak" {
  tenant_id = duplocloud_tenant.this.tenant_id

  name = "keycloak-service"
  agent_platform = 7
  docker_image   = local.keycloak_image
  replicas       = local.keycloak_replicas

  commands       = "/scripts/run.sh"

  volumes = jsonencode([
    { Name = "keycloak-scripts", Path = "scripts", ReadOnly = true,
      Spec = { Projected = { Sources = [ {
        ConfigMap = {
          Name = duplocloud_k8_config_map.keycloak-scripts.name,
          Items = [
            { Key = "REPLICAS", Path = "REPLICAS", Mode = parseint("0444",8) },
            { Key = "run.sh", Path = "run.sh", Mode = parseint("0755",8) },
            { Key = "standalone-ha.xml", Path = "standalone-ha.xml", Mode = parseint("0644",8) }
          ]
        }
      } ] } }
    }
  ])

  other_docker_config = jsonencode({
    Env = [
      { Name = "MY_POD_IP", ValueFrom = { FieldRef = { FieldPath = "status.podIP" } } },
    ],
    EnvFrom = [
      { ConfigMapRef = { Name = duplocloud_k8_config_map.keycloak-env.name } },
      { SecretRef = { Name = duplocloud_k8_secret.keycloak.secret_name } },
    ],

    Resources = {
      Limits = { cpu = "1500m", memory = "2Gi" }
      Requests = { cpu = "750m", memory = "1Gi" }
    }

    LivenessProbe = {
      FailureThreshold = 3,
      HttpGet = {
        Path = "/",
        Port = 8080,
        Scheme = "HTTP"
      },
      InitialDelaySeconds = 25
      PeriodSeconds = 7
    }
    ReadinessProbe = {
      FailureThreshold = 10
      HttpGet = {
        Path = "/",
        Port = 8080,
        Scheme = "HTTP"
      },
      InitialDelaySeconds = 10
      PeriodSeconds = 10
      SuccessThreshold = 2
      TimeoutSeconds = 1
    }
  })

  # Wait for JBoss to initialize before attempting to use Keycloak.
  provisioner "local-exec" {
    command = "sleep 180"
  }
}


# NOTE: This is does not create a load balancer, but rather a K8S service.
#       What it creates is controlled by the lbconfigs.lb_type attribute.
resource "duplocloud_duplo_service_lbconfigs" "keycloak" {
  tenant_id = duplocloud_tenant.this.tenant_id

  replication_controller_name = duplocloud_duplo_service.keycloak.name

  lbconfigs {
    lb_type                     = 4
    port                        = "8080"
    external_port               = local.keycloak_http_node_port
    protocol                    = "tcp"
    replication_controller_name = duplocloud_duplo_service.keycloak.name
  }

  lbconfigs {
    lb_type                     = 4
    port                        = "8443"
    external_port               = local.keycloak_https_node_port
    protocol                    = "tcp"
    replication_controller_name = duplocloud_duplo_service.keycloak.name
  }
}

// TODO:  Find out which internal ports are actually needed by Elisity, and trim down this list.
resource "kubernetes_service" "keycloak-internal" {
  metadata {
    name = "keycloak"
    namespace = data.duplocloud_tenant_eks_credentials.this.namespace
  }

  spec {
    selector = { app = duplocloud_duplo_service.keycloak.name }

    // Reduce duplication by using a dynamic block.
    dynamic "port" {
      for_each = local.keycloak_ports

      content {
        name = port.value["name"]
        port = port.value["port"]
        protocol = lookup(port.value, "protocol", null)
      }
    }

    type = "ClusterIP"
  }
}
