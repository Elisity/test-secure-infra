terraform {
  required_version = "~> 0.14"
  required_providers {
    duplocloud = {
      version = "0.5.22"
      source = "registry.terraform.io/duplocloud/duplocloud"
    }
    aws = { version = "~> 3.30.0" }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "~> 1.7"
    }
  }
}

locals {
  # The Elisity organization master account
  master_account_id = "074489987987"

  infra_name = terraform.workspace
}

provider "duplocloud" {}

// The base duplo infrastructure
resource "duplocloud_infrastructure" "this" {
  infra_name        = local.infra_name
  cloud             = 0
  region            = var.region
  azcount           = max(var.az_count, 2)
  enable_k8_cluster = true
  address_prefix    = var.vpc_cidr
  subnet_cidr       = var.subnet_cidr_bits

  provisioner "local-exec" {
    when = destroy
    command = "sleep 10m"
  }
}

// Additional VPC CIDRS for TLS
resource "aws_vpc_ipv4_cidr_block_association" "tls" {
  for_each = var.tls_vpc_cidrs
  vpc_id = duplocloud_infrastructure.this.vpc_id
  cidr_block = each.value
}

provider "aws" {
  region = duplocloud_infrastructure.this.region
}

data "terraform_remote_state" "account" {
  backend = "s3"

  config = {
    region               = "us-west-2" # bucket region
    bucket               = "duplo-tfstate-${data.aws_caller_identity.current.account_id}"
    key                  = "account"
  }
}

data "aws_caller_identity" "current" {}

data "aws_route_table" "private" {
  # NOTE: Because the app-services project is going to _change_ the route table for private subnets,
  #       we can't look it up by subnet ID.
  # subnet_id = ([for sn in duplocloud_infrastructure.this.private_subnets: sn["id"]])[0]

  vpc_id = duplocloud_infrastructure.this.vpc_id
  tags = {
    Name = "Private"
  }
}


data "aws_route_table" "public" {
  subnet_id = ([for sn in duplocloud_infrastructure.this.public_subnets: sn["id"]])[0]
}

data "duplocloud_eks_credentials" "this" {
  plan_id = duplocloud_infrastructure.this.infra_name
}
data "aws_eks_cluster" "this" {
  name = "duploinfra-${duplocloud_infrastructure.this.infra_name}"
}
provider "kubectl" {
  host                   = data.duplocloud_eks_credentials.this.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
  token                  = data.duplocloud_eks_credentials.this.token
  load_config_file       = false
}
