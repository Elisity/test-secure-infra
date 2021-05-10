// Environment secrets needed by the service.
data "aws_secretsmanager_secret" "aws_lambda_deploy-env" {
  name = "elisity-aws_lambda_deploy-secrets"
}
data "aws_secretsmanager_secret_version" "aws_lambda_deploy-env" {
  secret_id = data.aws_secretsmanager_secret.aws_lambda_deploy-env.id
}
resource "duplocloud_k8_secret" "aws_lambda_deploy-env" {
  tenant_id = local.tenant_id
  secret_name = "awslambdadeploy-env"
  secret_type = "Opaque"
  secret_data = data.aws_secretsmanager_secret_version.aws_lambda_deploy-env.secret_string
}

// Master account credentials needed by the service.
data "aws_secretsmanager_secret" "aws_lambda_deploy-mastercreds" {
  name = "elisity-master-awscreds"
}
data "aws_secretsmanager_secret_version" "aws_lambda_deploy-mastercreds" {
  secret_id = data.aws_secretsmanager_secret.aws_lambda_deploy-mastercreds.id
}
resource "duplocloud_k8_secret" "aws_lambda_deploy-mastercreds" {
  tenant_id = local.tenant_id
  secret_name = "awslambdadeploy-mastercreds"
  secret_type = "Opaque"
  secret_data = jsonencode({
    "config" = <<-EOAWS
[profile master]
region=${data.duplocloud_tenant_aws_region.this.aws_region}
aws_access_key_id=${jsondecode(data.aws_secretsmanager_secret_version.aws_lambda_deploy-mastercreds.secret_string)["accessKeyId"]}
aws_secret_access_key=${jsondecode(data.aws_secretsmanager_secret_version.aws_lambda_deploy-mastercreds.secret_string)["secretAccessKey"]}
EOAWS
  }) 
}

// RBAC permissions for the pod
resource "kubernetes_service_account" "awslambdadeploy-service" {
  metadata {
    name = "elisity-awslambdadeploy-service"
    namespace = data.duplocloud_tenant_eks_credentials.this.namespace
    labels = local.default_labels
  }
}
resource "kubernetes_role_binding" "awslambdadeploy-service-deploymentrestart" {
  metadata {
    name = "elisity-awslambdadeploy-service-deploymentrestart"
    namespace = data.duplocloud_tenant_eks_credentials.this.namespace
    labels = local.default_labels
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind = "Role"
    name = kubernetes_role.deployment-restart.metadata[0].name
  }

  subject {
    name = kubernetes_service_account.awslambdadeploy-service.metadata[0].name
    namespace = data.duplocloud_tenant_eks_credentials.this.namespace
    kind = "ServiceAccount"
  }
}
resource "kubernetes_role_binding" "awslambdadeploy-service-podexec" {
  metadata {
    name = "elisity-awslambdadeploy-service-podexec"
    namespace = data.duplocloud_tenant_eks_credentials.this.namespace
    labels = local.default_labels
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind = "Role"
    name = kubernetes_role.pod-exec.metadata[0].name
  }

  subject {
    name = kubernetes_service_account.awslambdadeploy-service.metadata[0].name
    namespace = data.duplocloud_tenant_eks_credentials.this.namespace
    kind = "ServiceAccount"
  }
}

// Duplo service
module "awslambdadeploy-service" {
  source = "../modules/elisity-microservice"

  tenant_id = local.tenant_id
  name  = "awslambdadeploy"
  service_defaults = local.service_defaults

  replicas = 1

  service_account_name = kubernetes_service_account.awslambdadeploy-service.metadata[0].name 

  drop_privileges = true
  
  env = [
    { name = "API_GW", value = local.customer_fqdn },
  ]
  env_from = [
    { type = "secret", name = duplocloud_k8_secret.aws_lambda_deploy-env.secret_name }
  ]

  volumes = [
    { Name = "certs", Path = "/data/certs", ReadOnly = true,
      Spec = { Secret = {
        DefaultMode = parseint("444", 8),
        SecretName = "ambassador-certs"
      } }
    },
    { Name = "mastercreds", Path = "/srv/aws_lambda_deploy/.aws", ReadOnly = true,
      Spec = { Secret = {
        DefaultMode = parseint("444", 8),
        SecretName = duplocloud_k8_secret.aws_lambda_deploy-mastercreds.secret_name
      } }
    }
  ]

  ports = [
    { container_port = 9443, name = "server", protocol = "TCP" },
  ]

  service = {
    port                        = "9443"
    external_port               = 9443
    protocol                    = "tcp"
  }
}
