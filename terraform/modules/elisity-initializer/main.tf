terraform {
  required_version = "~> 0.14"

  required_providers {
    duplocloud = {
      version = "~> 0.5.22"
      source = "registry.terraform.io/duplocloud/duplocloud"
    }
    kubernetes = { version = "~> 2.0" }
  }
}

locals {
  default_labels = {
    "app.kubernetes.managed-by" = "Terraform"
  }
}

data "duplocloud_tenant_aws_region" "this" {
  tenant_id = var.tenant_id
}
