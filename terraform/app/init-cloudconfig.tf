module "init-cloudconfig" {
  source = "../modules/elisity-initializer"

  tenant_id = local.tenant_id
  namespace = data.duplocloud_tenant_eks_credentials.this.namespace
  name = "cloudconfig"

  steps = [ "001", "002", "003" ]

  script = file("${path.module}/files/init-cloudconfig.sh")
  script_args = [
    module.cloud-configuration-service.service-hostname,
    module.cloud-configuration-service.service-port
  ]
  files = {
    "cloudservice.partial.json" = file("${path.module}/files/init-cloudconfig-cloudservice.partial.json"),
    "arncreds.json" = jsonencode({
      "accountId"  = data.terraform_remote_state.app-services.outputs["customer_aws_account_id"],
      "arn"        = data.terraform_remote_state.app-services.outputs["customer_role_arn"],
      "customer"   = false,
      "externalId" = data.terraform_remote_state.app-services.outputs["customer_role_external_id"],
      "region"     = data.duplocloud_tenant_aws_region.this.aws_region,
    })
  }
}
