locals {
  ambassador_crds_path = "${path.module}/files/svc-ambassador-crds"
}

// Ambassador CRDs
resource "kubectl_manifest" "ambassador-crds" {
  lifecycle {
    ignore_changes = [ yaml_body ]
  }

  for_each = fileset(local.ambassador_crds_path, "*.yaml")
  yaml_body = file("${local.ambassador_crds_path}/${each.value}")
}
