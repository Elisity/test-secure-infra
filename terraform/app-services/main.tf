terraform {
  required_version = "~> 0.14"
  required_providers {
    duplocloud = {
      version = "0.5.22"
      source = "registry.terraform.io/duplocloud/duplocloud"
    }
    aws = { version = "~> 3.30.0" }
    random = { version = "~> 3.0" }
    helm = { version = "~> 2.0" }
    kubernetes = { version = "~> 2.0" }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "~> 1.7"
    }
  }
}

locals {
  # The Elisity organization master account
  master_account_id = "074489987987"

  tenancy_model = "aws-account"

  tenant_name = terraform.workspace
  infra_name = var.infra_name
  region = data.terraform_remote_state.base-infra.outputs["region"]

  plan_id = data.terraform_remote_state.base-infra.outputs["plan_id"]

  zones = data.terraform_remote_state.base-infra.outputs["zones"]
  zone_count = length(local.zones)
  vpc_id = data.terraform_remote_state.base-infra.outputs["vpc_id"]
  vpc_cidr = data.terraform_remote_state.base-infra.outputs["vpc_cidr"]
  private_route_table_id = data.terraform_remote_state.base-infra.outputs["private_route_table_id"]
  duplo_private_routes = data.terraform_remote_state.base-infra.outputs["private_routes"]
  duplo_public_routes = data.terraform_remote_state.base-infra.outputs["public_routes"]
  private_subnets = data.terraform_remote_state.base-infra.outputs["private_subnets"]
  private_subnet_map = {for subnet in local.private_subnets: subnet["zone"] => subnet }

  customer_subdomain = coalesce(var.subdomain, local.tenant_name)
  customer_fqdn = coalesce(var.fqdn, "${local.customer_subdomain}.elisity.net")

  // For now, support an account-level tenancy model
  manage_customer_role = (var.manage_customer_role && local.tenancy_model=="aws-account")
  customer_role_arn = local.manage_customer_role ? aws_iam_role.mgmt-master[0].arn : var.customer_role_arn
  customer_role_external_id = local.manage_customer_role ? "${local.customer_subdomain}_elisity_external_id" : var.customer_role_external_id
  customer_aws_account_id = coalesce(var.customer_aws_account_id, data.duplocloud_aws_account.this.account_id)
}

data "terraform_remote_state" "base-infra" {
  backend = "s3"

  workspace = local.infra_name

  config = {
    region               = "us-west-2" # bucket region
    bucket               = "duplo-tfstate-${data.duplocloud_aws_account.this.account_id}"
    workspace_key_prefix = "infra:"
    key                  = "base-infra"
  }
}

provider "duplocloud" {}

data "duplocloud_aws_account" "this" {}

provider "aws" {
  region = local.region
}

data "aws_caller_identity" "this" {}
