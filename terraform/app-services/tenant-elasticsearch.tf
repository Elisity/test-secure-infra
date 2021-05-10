// The tenant that houses ElasticSearch
resource "duplocloud_tenant" "elastic" {
  account_name = "${local.tenant_name}es"
  plan_id      = local.plan_id
}

// Allow the main tenant to access the elasticsearch tenant
resource "duplocloud_tenant_network_security_rule" "main-to-es" {
  tenant_id = duplocloud_tenant.elastic.tenant_id

  source_tenant = duplocloud_tenant.this.account_name
  description = "Allow ElasticSearch traffic from main workload tenant"
}

// Authenticate to EKS using duplo credentials
data "duplocloud_tenant_eks_credentials" "elastic" {
  tenant_id = duplocloud_tenant.elastic.tenant_id
}
provider "kubernetes" {
  alias = "elastic"
  host                   = data.duplocloud_tenant_eks_credentials.elastic.endpoint
  cluster_ca_certificate = data.duplocloud_tenant_eks_credentials.elastic.ca_certificate_data
  token                  = data.duplocloud_tenant_eks_credentials.elastic.token
}
provider "helm" {
  alias = "elastic"
  kubernetes {
    host                   = data.duplocloud_tenant_eks_credentials.elastic.endpoint
    cluster_ca_certificate = data.duplocloud_tenant_eks_credentials.elastic.ca_certificate_data
    token                  = data.duplocloud_tenant_eks_credentials.elastic.token
  }
}
