// RBAC to allow deployment restarts.
resource "kubernetes_role" "deployment-restart" {
  metadata {
    name = "elisity-deployment-restart"
    namespace = data.duplocloud_tenant_eks_credentials.this.namespace
    labels = local.default_labels
  }

  rule {
    api_groups = [ "apps", "extensions" ]
    resources = [ "deployments" ]
    verbs = [ "get", "path", "list", "watch" ]
  }
}

// RBAC to allow pod execs.
resource "kubernetes_role" "pod-exec" {
  metadata {
    name = "elisity-pod-exec"
    namespace = data.duplocloud_tenant_eks_credentials.this.namespace
    labels = local.default_labels
  }

  rule {
    api_groups = [ "" ]
    resources = [ "pods", "pods/log" ]
    verbs = [ "get", "list" ]
  }

  rule {
    api_groups = [ "" ]
    resources = [ "pods/exec" ]
    verbs = [ "create" ]
  }
}

