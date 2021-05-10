// Ambassador installation.
//
// See:
//   - https://github.com/datawire/ambassador-chart/tree/v1.0.0
//   - https://github.com/datawire/ambassador-chart/blob/v1.0.0/values.yaml
//   - https://www.getambassador.io/docs/1.3/topics/running/ambassador-with-aws/
//

// ACM certs for Ambassador
data "aws_acm_certificate" "ambassador" {
  domain = coalesce(var.acm_certificate_domain, "*.elisity.net")
  types = ["AMAZON_ISSUED", "IMPORTED"]
  statuses = [ "ISSUED" ]
  most_recent = true
}

// Elisity wildcard certs for Ambassador
data "aws_secretsmanager_secret" "ambassador-certs" {
  name = "elisity-ambassador-certs"
}
data "aws_secretsmanager_secret_version" "ambassador-certs" {
  secret_id = data.aws_secretsmanager_secret.ambassador-certs.id
}
resource "duplocloud_k8_secret" "ambassador-certs" {
  tenant_id = duplocloud_tenant.this.tenant_id
  secret_name = "ambassador-certs"
  secret_type = "kubernetes.io/tls"
  secret_data = data.aws_secretsmanager_secret_version.ambassador-certs.secret_string
}

// Elisity TLS config for Ambassador
resource "kubectl_manifest" "ambassador-tls" {
  yaml_body = <<EOF
apiVersion: getambassador.io/v1
kind: TLSContext
metadata:
  namespace: ${data.duplocloud_tenant_eks_credentials.this.namespace}
  name: elisity-tls-context
spec:
  redirect_cleartext_from: 8080
  hosts: ["*"]
  secret: ambassador-certs
  alpn_protocols: h2,http/1.1
EOF
}

// Elisity external Ambassador
module "ambassador" {
  depends_on = [ duplocloud_aws_host.eks-node, kubectl_manifest.ambassador-tls ]

  source = "../modules/ambassador"

  name = "ambassador"
  namespace = data.duplocloud_tenant_eks_credentials.this.namespace
  tenant_id = duplocloud_tenant.this.tenant_id

  dns_prefix = local.customer_subdomain

  ambassador_replicas = local.zone_count
  ambassador_certificate_arn = data.aws_acm_certificate.ambassador.arn
  ambassador_service_annotations = {
    "getambassador.io/config" = <<EOYAML
---
apiVersion: ambassador/v1
kind:  Mapping
name:  elisity-eventsmanager-service
prefix: /api/v1/em
service: https://elisity-eventsmanager-service:8443
rewrite: ""

---
apiVersion: ambassador/v1
kind:  Mapping
name:  elisity-ui2-service
prefix: /
service: elisity-ui2-service:3000
bypass_auth: true

---
apiVersion: ambassador/v1
kind:  Mapping
name:  elisity-user-service
prefix: /api/v1/usersvc/
service: elisity-device-service:8080
rewrite: ""
retry_policy:
  retry_on: "gateway-error"
  num_retries: 3

---
apiVersion: ambassador/v1
kind:  Mapping
name:  elisity-eea-service
prefix: /eeasvc/
service: https://elisity-eea-service:8105
bypass_auth: true
rewrite: ""
idle_timeout_ms: 90000
timeout_ms: 90000
---

apiVersion: ambassador/v1
kind:  Mapping
name:  elisity-ot-service
prefix: /api/v1/otsvc/
service: elisity-device-service:8080
rewrite: ""
keepalive:
  time: 100
  interval: 10
  probes: 3

---
apiVersion: ambassador/v1
kind:  Mapping
name:  elisity-orchestrator-service
prefix: /api/elisity/orchestrator/
service: elisity-orchestrator-service:8080
rewrite: ""
idle_timeout_ms: 90000
timeout_ms: 90000

---
apiVersion: ambassador/v1
kind:  Mapping
name:  elisity-device-service
prefix: /api/v1/devsvc/
service: elisity-device-service:8080
rewrite: ""
idle_timeout_ms: 90000
timeout_ms: 90000
---
apiVersion: ambassador/v1
kind:  Mapping
name:  elisity-device-connector-service
prefix: /api/v1/connector/
service: elisity-device-service:8080
rewrite: ""
idle_timeout_ms: 90000
timeout_ms: 90000
keepalive:
  time: 100
  interval: 10
---
apiVersion: ambassador/v1
kind:  Mapping
name:  elisity-searchmgr-service
prefix: /searchmgr/v1/
service: elisity-searchmgr-service:8080
rewrite: ""
idle_timeout_ms: 90000
timeout_ms: 90000

---

apiVersion: ambassador/v1
kind:  Mapping
name:  elisity-cdprocessor-service
prefix: /cdprocessor/v1/
service: elisity-cdprocessor-service:8080
rewrite: ""

---
apiVersion: ambassador/v1
kind:  Mapping
name:  elisity-policyevaluator-service
prefix: /policyevaluator/v1/
service: elisity-policyevaluator-service:8080
rewrite: ""
idle_timeout_ms: 30000
timeout_ms: 30000

---
apiVersion: ambassador/v1
kind:  Mapping
name:  elisity-policyeng-service
prefix: /api/v1/policyengine/
service: elisity-policyeng-service:8080
rewrite: ""
idle_timeout_ms: 90000
timeout_ms: 90000

---
apiVersion: ambassador/v1
kind:  Mapping
name:  elisity-dispatcher-service
prefix: /dispatcher/
service: elisity-dispatcher-service:8080
rewrite: ""

---
apiVersion: ambassador/v1
kind:  Mapping
name:  elisitysity-keymgr-service
prefix: /keyMgr/
service: elisity-keymgr-service:8080
rewrite: ""

---
apiVersion: ambassador/v1
kind:  Mapping
name:  elisitysity-tunnelmgr-service
prefix: /tunnelMgr/
service: elisity-tunnelmgr-service:8080
rewrite: ""

---
apiVersion: ambassador/v1
kind:  Mapping
name:  elisitysity-ediscovery-service
prefix: /eInventory/v1/
service: elisity-ediscovery-service:8080
rewrite: ""

---
apiVersion: ambassador/v1
kind:  Mapping
name:  elisitysity-app-service
prefix: /api/v1/appsvc/
service: elisity-device-service:8080
rewrite: ""

---
apiVersion: ambassador/v1
kind:  Mapping
name:  elisity-usermanagement-service
prefix: /api/v1/iam/usermanagement/
service: elisity-user-mgmt-service:8080
rewrite: ""
idle_timeout_ms: 9000
timeout_ms: 9000

---
apiVersion: ambassador/v1
kind:  Mapping
name:  elisity-usermanagement-internal-service
prefix: /api/v1/iam/internalaccounts/
service: elisity-user-mgmt-service:8080
rewrite: ""

---
apiVersion: ambassador/v1
kind:  Mapping
name:  elisity-nat-tunnel-service
prefix: /api/elisity/nat/
service: elisity-nat-tunnel-service:8080
rewrite: ""

---
apiVersion: ambassador/v1
kind:  Mapping
name:  elisity-ipallocator-service
prefix: /ipAllocator/
service: elisity-ipallocator-service:8080
rewrite: ""

---
apiVersion: ambassador/v1
kind:  Mapping
name:  elisity-cloudconfig-service
prefix: /api/v1/cloudconfig/
service: elisity-cloudconfig-service:8080
rewrite: ""
idle_timeout_ms: 90000
timeout_ms: 90000

---
apiVersion: ambassador/v1
kind:  Mapping
name:  elisity-telemetry-service
prefix: /api/v1/telemetry/
service: elisity-telemetry-service:8080
rewrite: ""

---
apiVersion: ambassador/v1
kind:  Mapping
name:  kibana-logging
prefix: /kibanabase/
service: ${module.elasticsearch-main.kibana_host}.${data.duplocloud_tenant_eks_credentials.elastic.namespace}:${module.elasticsearch-main.kibana_port}
bypass_auth: true
EOYAML

  }

}

// Elisity external authorization service.
resource "kubernetes_service" "ext-auth" {
  depends_on = [ kubectl_manifest.ambassador-tls ]

  metadata {
    name = "ambassador-auth-ext-service"
    namespace = data.duplocloud_tenant_eks_credentials.this.namespace 

    annotations = {
      "getambassador.io/config" = <<EOCFG
apiVersion: ambassador/v1
kind: AuthService
name: ambassador-auth-ext
auth_service: "elisity-user-mgmt-service:8080"
path_prefix: "/api/v1/iam/authextension/authorize"
allowed_request_headers:
  - "Authorization"
allowed_authorization_headers:
  - "X-Auth-Userinfo"
EOCFG
    }
  }
  spec {
    selector = {
      app = "eli-user-mgmt"
    }
    port {
      name = "auth-ext-port"
      port = 8080
      target_port = 8080
    }
    type = "ClusterIP"
  }
}
