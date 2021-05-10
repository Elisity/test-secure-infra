// The internal tenant that houses the internal ambassador.
resource "duplocloud_tenant" "internal" {
  account_name = "${local.tenant_name}int"
  plan_id      = local.plan_id
}

// Allow the main tenant to access the internal tenant on port 8080
resource "duplocloud_tenant_network_security_rule" "main-to-internal" {
  tenant_id = duplocloud_tenant.internal.tenant_id

  source_tenant = duplocloud_tenant.this.account_name
  from_port = 8080
  to_port = 8080
  description = "Allow main tenant to access internal tenant on port 8080"
}

// Allow applicable systems to access the internal ambassador
data "aws_security_group" "internal" {
  name = "duploservices-${duplocloud_tenant.internal.account_name}"
  vpc_id = local.vpc_id
}
resource "aws_security_group_rule" "external-edpd-to-internal" {
  count = length(var.external_edpd_servers) > 0 ? 1 : 0

  security_group_id = data.aws_security_group.internal.id

  type = "ingress"
  protocol = "tcp"
  from_port = 31000
  to_port = 31000
  cidr_blocks = var.external_edpd_servers
  description = "Allow external Elisity EDPD to access internal ambassador"
}
resource "aws_security_group_rule" "external-edpd-ping-internal" {
  count = var.allow_icmp && length(var.external_edpd_servers) > 0 ? 1 : 0

  security_group_id = data.aws_security_group.internal.id

  type = "ingress"
  protocol = "icmp"
  from_port = -1
  to_port = -1
  cidr_blocks = var.external_edpd_servers
  description = "Allow external Elisity EDPD to ping nodes"
}
resource "aws_security_group_rule" "tls-to-internal" {
  security_group_id = data.aws_security_group.internal.id

  type = "ingress"
  protocol = "tcp"
  from_port = 0
  to_port = 65535
  source_security_group_id = aws_security_group.tls.id
  description = "Allow TLS server to access the internal ambassador"
}

// Authenticate to EKS using duplo credentials
data "duplocloud_tenant_eks_credentials" "internal" {
  tenant_id = duplocloud_tenant.internal.tenant_id
}
provider "kubernetes" {
  alias = "internal"
  host                   = data.duplocloud_tenant_eks_credentials.internal.endpoint
  cluster_ca_certificate = data.duplocloud_tenant_eks_credentials.internal.ca_certificate_data
  token                  = data.duplocloud_tenant_eks_credentials.internal.token
}
