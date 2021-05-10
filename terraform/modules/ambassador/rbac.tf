resource "kubernetes_service_account" "this" {
  metadata {
    name = var.name
    namespace = var.namespace
    labels = local.default_labels
  }
}

resource "kubernetes_role" "this" {
  metadata {
    name = var.name
    namespace = var.namespace
    labels = local.default_labels
  }

  rule {
    api_groups = [ "" ]
    resources = [ "services", "secrets", "endpoints"]
    verbs = ["get", "list", "watch"]
  }

  rule {
    api_groups = [ "getambassador.io" ]
    resources = [ "*" ]
    verbs = ["get", "list", "watch", "update", "patch", "create", "delete" ]
  }

  rule {
    api_groups =[ "apiextensions.k8s.io" ]
    resources = [ "customresourcedefinitions" ]
    verbs = ["get", "list", "watch"]
  }

  rule {
    api_groups = [ "networking.internal.knative.dev"]
    resources = [ "clusteringresses" ]
    verbs = ["get", "list", "watch"]
  }

  rule {
    api_groups = [ "extensions" ]
    resources = [ "ingresses" ]
    verbs = ["get", "list", "watch"]
  }

  rule {
    api_groups = [ "extensions" ]
    resources = [ "ingresses/status" ]
    verbs = ["update"]
  }
}

resource "kubernetes_role_binding" "this" {
  metadata {
    name = var.name
    namespace = var.namespace
    labels = local.default_labels
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind = "Role"
    name = kubernetes_role.this.metadata[0].name
  }

  subject {
    name = kubernetes_service_account.this.metadata[0].name
    namespace = var.namespace
    kind = "ServiceAccount"
  }
}

resource "kubernetes_cluster_role" "this" {
  count = var.ambassador_is_internal ? 0 : 1

  metadata {
    name = "${var.name}-crds"
    labels = local.default_labels
  }
  
  rule {
    api_groups = [ "apiextensions.k8s.io" ]
    verbs = ["get", "list", "watch", "delete"]
    resources = [ "customresourcedefinitions" ]
    resource_names = [
      "authservices.getambassador.io",
      "mappings.getambassador.io",
      "modules.getambassador.io",
      "logservices.getambassador.io",
      "ratelimitservices.getambassador.io",
      "tcpmappings.getambassador.io",
      "tlscontexts.getambassador.io",
      "tracingservices.getambassador.io",
      "kubernetesendpointresolvers.getambassador.io",
      "kubernetesserviceresolvers.getambassador.io",
      "consulresolvers.getambassador.io",
      "filters.getambassador.io",
      "filterpolicies.getambassador.io",
      "ratelimits.getambassador.io"
    ]
  }
}
resource "kubernetes_cluster_role_binding" "this" {
  count = var.ambassador_is_internal ? 0 : 1

  metadata {
    name = "${var.name}-crds"
    labels = local.default_labels
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind = "ClusterRole"
    name = kubernetes_cluster_role.this[0].metadata[0].name
  }

  subject {
    name = kubernetes_service_account.this.metadata[0].name
    namespace = var.namespace
    kind = "ServiceAccount"
  }
}
