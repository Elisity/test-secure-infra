// Main ElasticSearch cluster.
module "elasticsearch-main" {
  source = "../modules/elasticsearch"

  depends_on = [ duplocloud_aws_host.eks-node-elastic ]

  providers = {
    kubernetes = kubernetes.elastic,
    helm = helm.elastic,
  }

  tenant_id = duplocloud_tenant.elastic.tenant_id

  name  = "main"

  // elasticsearch_version = var.elasticsearch_version
  namespace = data.duplocloud_tenant_eks_credentials.elastic.namespace
  storage_size = var.main_elasticsearch_storage_size
  zones = data.terraform_remote_state.base-infra.outputs["zones"]
}
