module "init-orchestrator" {
  source = "../modules/elisity-initializer"

  depends_on = [
    module.init-cloudconfig
  ]

  count = var.prewarming ? 0 : 1

  tenant_id = local.tenant_id
  namespace = data.duplocloud_tenant_eks_credentials.this.namespace
  name = "orchestrator"

  steps = [ "001", "002", "003" ]

  script = file("${path.module}/files/init-orchestrator.sh")
  script_args = [
    module.orchestrator-service.service-hostname,
    module.orchestrator-service.service-port
  ]
  files = {
    "customeraccessrole.json" = jsonencode({
      "awsAccountId" = data.terraform_remote_state.app-services.outputs["customer_aws_account_id"],
      "awsRoleArn"   = data.terraform_remote_state.app-services.outputs["customer_role_arn"],
      "awsExternalId" = data.terraform_remote_state.app-services.outputs["customer_role_external_id"],
    })
    "custprof.json" = jsonencode({
      "customerEmail" = data.terraform_remote_state.app-services.outputs["customer_email"],
      "customerName" = data.terraform_remote_state.app-services.outputs["customer_name"],
      "esaasUrl" = "https://${local.customer_fqdn}",
      "externalId" = data.terraform_remote_state.app-services.outputs["customer_role_external_id"],
      "orgName" = data.terraform_remote_state.app-services.outputs["customer_org_name"],
      "region" = local.region,
      "roleArn" = data.terraform_remote_state.app-services.outputs["customer_role_arn"],
    })
  }
}
