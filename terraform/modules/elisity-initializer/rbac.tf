// Permissions for microservice initialization
resource "kubernetes_service_account" "this" {
  metadata {
    name = "init-${var.name}"
    namespace = var.namespace
    labels = local.default_labels
  }
}

resource "kubernetes_role" "state" {
  metadata {
    name = "init-${var.name}-state"
    namespace = var.namespace
    labels = local.default_labels
  }

  rule {
    api_groups = [ "" ]
    resources = [ "configmaps" ]
    resource_names = [ "init-${var.name}-state" ]
    verbs = [ "get", "update", "patch", "watch" ]
  }

  rule {
    api_groups = [ "apps" ]
    resources = [ "deployments" ]
    verbs = [ "get", "list", "watch" ]
  }
}

resource "kubernetes_role_binding" "this" {
  metadata {
    name = "init-${var.name}"
    namespace = var.namespace
    labels = local.default_labels
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind = "Role"
    name = kubernetes_role.state.metadata[0].name
  }

  subject {
    name = kubernetes_service_account.this.metadata[0].name
    namespace = var.namespace
    kind = "ServiceAccount"
  }
}
