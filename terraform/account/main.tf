terraform {
  required_version = "~> 0.14"
  required_providers {
    aws = { version = "~> 3.30.0" }
    null = { version = "~> 3.1.0" }
  }
}

provider "aws" {
  region = var.default_region
}

provider "aws" {
  alias = "us-west-2"
  region = "us-west-2"
}

provider "aws" {
  alias = "us-east-2"
  region = "us-east-2"
}

locals {
  # The Elisity organization master account
  master_account_id = "074489987987"
  master_ecr_region = "us-east-2"

  duplo_url = coalesce(var.duplo_url, "https://elisity-${var.tenant_name}.duplocloud.net")
  internal_fqdn = coalesce(var.internal_fqdn, "${var.tenant_name}.intdev.elisity.net")
  external_fqdn = local.internal_fqdn
}

data "aws_caller_identity" "current" {}
