terraform {
  required_version = "~> 0.14"

  required_providers {
    duplocloud = {
      version = "~> 0.5.22"
      source = "registry.terraform.io/duplocloud/duplocloud"
    }
    kubernetes = { version = "~> 2.0" }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "~> 1.7"
    }
  }
}

locals {
  default_labels = {
    "app.kubernetes.name" = var.name
    "app.kubernetes.part-of" = var.name
    "app.kubernetes.instance" = var.name
    "app.kubernetes.managed-by" = "Terraform"
  }
}
