// Elisity internal Ambassador
module "ambassador-internal" {
  depends_on = [ duplocloud_aws_host.eks-node-internal ]

  source = "../modules/ambassador"

  name = "ambassador-internal"
  namespace = data.duplocloud_tenant_eks_credentials.internal.namespace
  tenant_id = duplocloud_tenant.internal.tenant_id

  ambassador_is_internal = true

  ambassador_image = var.ambassador_internal_docker_image
  ambassador_replicas = local.zone_count
  ambassador_service_annotations = {
    "getambassador.io/config" = <<EOYAML
---
apiVersion: ambassador/v1
kind:  Mapping
name:  elisity-user-service1
prefix: /api/v1/usersvc/
service: elisity-device-service.${data.duplocloud_tenant_eks_credentials.this.namespace}:8080
bypass_auth: true
rewrite: ""

---

apiVersion: ambassador/v1
kind:  Mapping
name:  edpd-ediscovery-service1
prefix: /eInventory/v1/
service: elisity-ediscovery-service.${data.duplocloud_tenant_eks_credentials.this.namespace}:8080
bypass_auth: true
rewrite: ""

---

apiVersion: ambassador/v1
kind:  Mapping
name:  edpd-ipallocator-service1
prefix: /ipAllocator/v1/allocate
service: elisity-ipallocator-service.${data.duplocloud_tenant_eks_credentials.this.namespace}:8080
bypass_auth: true
rewrite: ""

---


apiVersion: ambassador/v1
kind:  Mapping
name:  edpd-telemetry-service1
prefix: /api/v1/telemetry/dpdpgpairstats
service: elisity-telemetry-service.${data.duplocloud_tenant_eks_credentials.this.namespace}:8080
bypass_auth: true
rewrite: ""

---


apiVersion: ambassador/v1
kind:  Mapping
name:  edpd-collector-service1
prefix: /collector/v1/
service: elisity-collector-service.${data.duplocloud_tenant_eks_credentials.this.namespace}:8080
bypass_auth: true
rewrite: ""

---
apiVersion: ambassador/v1
kind:  Mapping
name:  elisity-device-service1
prefix: /api/v1/devsvc/
service: elisity-device-service.${data.duplocloud_tenant_eks_credentials.this.namespace}:8080
bypass_auth: true
rewrite: ""

---
apiVersion: ambassador/v1
kind:  Mapping
name:  elisity-nat-tunnel-service
prefix: /api/elisity/nat/
service: elisity-nat-tunnel-service.${data.duplocloud_tenant_eks_credentials.this.namespace}:8080
bypass_auth: true
rewrite: ""

---
EOYAML
  }
}
