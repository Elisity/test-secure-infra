// The main tenant that houses all services.
resource "duplocloud_tenant" "this" {
  account_name = "${local.tenant_name}svc"
  plan_id      = local.plan_id
}
data "duplocloud_tenant_aws_region" "this" {
  tenant_id = duplocloud_tenant.this.tenant_id
}

// Allow the internal tenant to access the main tenant
resource "duplocloud_tenant_network_security_rule" "internal-to-main" {
  tenant_id = duplocloud_tenant.this.tenant_id

  source_tenant = duplocloud_tenant.internal.account_name
  description = "Allow any traffic from internal tenant"
}

// Allow applicable systems to access the internal ambassador
data "aws_security_group" "main" {
  name = "duploservices-${duplocloud_tenant.this.account_name}"
  vpc_id = local.vpc_id
}
resource "aws_security_group_rule" "external-edpd-to-main" {
  count = length(var.external_edpd_servers) > 0 ? 1 : 0

  security_group_id = data.aws_security_group.main.id

  type = "ingress"
  protocol = "tcp"
  from_port = 31000
  to_port = 31000
  cidr_blocks = var.external_edpd_servers
  description = "Allow external Elisity EDPD to access internal ambassador"
}
resource "aws_security_group_rule" "external-edpd-ping-main" {
  count = var.allow_icmp && length(var.external_edpd_servers) > 0 ? 1 : 0

  security_group_id = data.aws_security_group.main.id

  type = "ingress"
  protocol = "icmp"
  from_port = -1
  to_port = -1
  cidr_blocks = var.external_edpd_servers
  description = "Allow external Elisity EDPD to ping nodes"
}
resource "aws_security_group_rule" "tls-to-main" {
  security_group_id = data.aws_security_group.main.id

  type = "ingress"
  protocol = "tcp"
  from_port = 0
  to_port = 65535
  source_security_group_id = aws_security_group.tls.id
  description = "Allow TLS server to access the nodes"
}

// Allow the internal tenant to manage EC2 route-tables.
// FIXME:  Get a list of required APIs from Elisity, and make this least-priviledge.
data "aws_iam_policy_document" "main-routemgmt" {
  statement {
    sid = "FullEC2"
    effect = "Allow"
    actions = [ "ec2:*" ]
    resources = [ "*" ]
  }
  statement {
    sid = "FullS3"
    effect = "Allow"
    actions = [ "s3:*" ]
    resources = [ "*" ]
  }
}
resource "aws_iam_policy" "main-routemgmt" {
  name = "${duplocloud_tenant.this.account_name}-routemgmt"
  policy = data.aws_iam_policy_document.main-routemgmt.json
}
resource "aws_iam_role_policy_attachment" "main-routemgmt" {
  role = "duploservices-${duplocloud_tenant.this.account_name}"
  policy_arn = aws_iam_policy.main-routemgmt.arn
}

// Allow the internal tenant to read the master credentials secret.
data "aws_iam_policy_document" "main-mastercreds" {
  statement {
    sid = "ReadMasterCredsSecret"
    effect = "Allow"
    actions = [
      "secretsmanager:GetResourcePolicy",
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
      "secretsmanager:ListSecretVersionIds"
    ]
    resources = [
      "arn:aws:secretsmanager:${data.duplocloud_tenant_aws_region.this.aws_region}:${data.duplocloud_aws_account.this.account_id}:secret:elisity-master-awscreds*"
    ]
  }
}
resource "aws_iam_policy" "main-mastercreds" {
  name = "${duplocloud_tenant.this.account_name}-mastercreds"
  policy = data.aws_iam_policy_document.main-mastercreds.json
}
resource "aws_iam_role_policy_attachment" "main-mastercreds" {
  role = "duploservices-${duplocloud_tenant.this.account_name}"
  policy_arn = aws_iam_policy.main-mastercreds.arn
}

// Authenticate to EKS using duplo credentials
data "duplocloud_tenant_eks_credentials" "this" {
  tenant_id = duplocloud_tenant.this.tenant_id
}
provider "kubernetes" {
  host                   = data.duplocloud_tenant_eks_credentials.this.endpoint
  cluster_ca_certificate = data.duplocloud_tenant_eks_credentials.this.ca_certificate_data
  token                  = data.duplocloud_tenant_eks_credentials.this.token
}
provider "kubectl" {
  host                   = data.duplocloud_tenant_eks_credentials.this.endpoint
  cluster_ca_certificate = data.duplocloud_tenant_eks_credentials.this.ca_certificate_data
  token                  = data.duplocloud_tenant_eks_credentials.this.token
  load_config_file       = false
}
provider "helm" {
  kubernetes {
    host                   = data.duplocloud_tenant_eks_credentials.this.endpoint
    cluster_ca_certificate = data.duplocloud_tenant_eks_credentials.this.ca_certificate_data
    token                  = data.duplocloud_tenant_eks_credentials.this.token
  }
}
