terraform {
  required_version = "~> 0.14"
  required_providers {
    duplocloud = {
      version = "0.5.22"
      source = "registry.terraform.io/duplocloud/duplocloud"
    }
    kubernetes = { version = "~> 2.0" }
  }
}

locals {
  # The Elisity organization master account
  master_account_id = "074489987987"

  tenant_name = terraform.workspace
  tenant_id = data.terraform_remote_state.app-services.outputs["tenant_id"]
  region = data.terraform_remote_state.app-services.outputs["region"]
  zones = data.terraform_remote_state.app-services.outputs["zones"]
  zone_count = length(local.zones)

  env_name = coalesce(var.env_name, "stage")

  upgrade_time = coalesce(var.upgrade_time, "2021-04-06")
  common_envs = [
    { name = "loadtime", value = local.upgrade_time }
  ]
  default_replicas = var.default_replicas>0 ? var.default_replicas : min(local.zone_count, 2)

  default_labels = {
    "app.kubernetes.managed-by" = "Terraform"
  }

  service_defaults = {
    registry = data.terraform_remote_state.app-services.outputs["ecr_registry_host"]
    names = var.app_image_names
    tags = var.app_image_tags
    default_tag = var.app_image_default_tag
  }

  mongodb_configmap_name = data.terraform_remote_state.app-services.outputs["mongodb_configmap_name"]
  mongodb_secret_name = data.terraform_remote_state.app-services.outputs["mongodb_secret_name"]

  kafka_bootstrap_address = data.terraform_remote_state.app-services.outputs["main_kafka_plaintext_bootstrap_broker_string"]
  elastic_cluster_name = data.terraform_remote_state.app-services.outputs["main_elasticsearch_cluster_name"]
  elastic_endpoint_url = data.terraform_remote_state.app-services.outputs["main_esproxy_host"]
  elastic_endpoint_port = data.terraform_remote_state.app-services.outputs["main_esproxy_port"]
  // elastic_cluster_name = data.terraform_remote_state.app-services.outputs["main_elasticsearch_domain_name"]
  // elastic_endpoint_url = data.terraform_remote_state.app-services.outputs["main_elasticsearch_endpoints"]["vpc"]
  // elastic_endpoint_port = "80"
  kibana_host = data.terraform_remote_state.app-services.outputs["main_kibana_host"]
  kibana_port = data.terraform_remote_state.app-services.outputs["main_kibana_port"]

  tls_uplink_ips = data.terraform_remote_state.app-services.outputs["tls_uplink_ips"]

  okta_oauth2_issuer = ""
  okta_oauth2_client_id = ""
  okta_oauth2_client_secret = ""
  okta_elisity_api_token = ""

  customer_subdomain = data.terraform_remote_state.app-services.outputs["customer_subdomain"]
  customer_fqdn = data.terraform_remote_state.app-services.outputs["customer_fqdn"]

  flowlogs_bucketname = "${local.customer_subdomain}elisity"
  k8s_endpoint = data.duplocloud_tenant_eks_credentials.this.endpoint

  # TODO: For now, just in dev
  kafka_log = local.kafka_bootstrap_address

  # TODO: For now, just in dev
  kafka_bootstrap_analytics_address = local.kafka_bootstrap_address
  elastic_analytics_cluster_name = local.elastic_cluster_name
  elastic_analytics_endpoint_url = local.elastic_endpoint_url
  elastic_analytics_endpoint_port = local.elastic_endpoint_port

  ambassador_elb_url = data.terraform_remote_state.app-services.outputs["internal_ambassador_dns"]
}

data "terraform_remote_state" "app-services" {
  backend = "s3"

  workspace = local.tenant_name

  config = {
    region               = "us-west-2" # bucket region
    bucket               = "duplo-tfstate-${data.duplocloud_aws_account.this.account_id}"
    workspace_key_prefix = "tenant:"
    key                  = "app-services"
  }
}

provider "duplocloud" {}

data "duplocloud_aws_account" "this" { }
data "duplocloud_tenant_aws_region" "this" {
  tenant_id = local.tenant_id
}
data "duplocloud_tenant_eks_credentials" "this" {
  tenant_id = local.tenant_id
}
provider "kubernetes" {
  host                   = data.duplocloud_tenant_eks_credentials.this.endpoint
  cluster_ca_certificate = data.duplocloud_tenant_eks_credentials.this.ca_certificate_data
  token                  = data.duplocloud_tenant_eks_credentials.this.token
}
