// Access to the DNS AWS account
data "aws_secretsmanager_secret" "dnscreds" {
  name = "elisity-dns-awscreds"
}
data "aws_secretsmanager_secret_version" "dnscreds" {
  secret_id = data.aws_secretsmanager_secret.dnscreds.id
}
provider "aws" {
  alias = "dns"

  region = "us-east-2"
  access_key = jsondecode(data.aws_secretsmanager_secret_version.dnscreds.secret_string)["accessKeyId"]
  secret_key = jsondecode(data.aws_secretsmanager_secret_version.dnscreds.secret_string)["secretAccessKey"]
}

// Local account:  DNS zone.
resource "aws_route53_zone" "internal" {
  name = local.internal_fqdn
}

// DNS account:  NS glue record.
data "aws_route53_zone" "root" {
  provider = aws.dns

  name = "elisity.net."
  private_zone = false
}
resource "aws_route53_record" "root-glue-internal" {
  provider = aws.dns

  zone_id = data.aws_route53_zone.root.zone_id
  name    = "${local.internal_fqdn}."
  type    = "NS"
  ttl     = 600
  records = [ for ns in aws_route53_zone.internal.name_servers: "${ns}." ]
}

// Local account:  DNS record for ACM validation.
locals {
  dnsval = ([for dvo in aws_acm_certificate.internal-us-west-2.domain_validation_options : dvo if dvo.domain_name == local.internal_fqdn])[0]
}
resource "aws_route53_record" "internal-acm" {
  depends_on = [ aws_route53_record.root-glue-internal ]
  count   = 1

  zone_id = aws_route53_zone.internal.id

  name    = local.dnsval.resource_record_name
  type    = local.dnsval.resource_record_type
  records = [local.dnsval.resource_record_value]
  ttl     = 60
}

// Local account:  ACM.
resource "aws_acm_certificate" "internal-us-west-2" {
  provider = aws.us-west-2

  lifecycle {
    create_before_destroy = true
  }

  validation_method = "DNS"

  # For now, allow nonprod to only have one FQDN
  domain_name = "*.${local.internal_fqdn}"
  subject_alternative_names = [ local.internal_fqdn ]

  tags = {
    Name        = var.tenant_name
    Description = "SSL certificate for ${var.tenant_name} tenant"
  }
}
resource "aws_acm_certificate" "internal-us-east-2" {
  provider = aws.us-east-2

  lifecycle {
    create_before_destroy = true
  }

  validation_method = "DNS"

  # For now, allow nonprod to only have one FQDN
  domain_name = "*.${local.internal_fqdn}"
  subject_alternative_names = [ local.internal_fqdn ]

  tags = {
    Name        = var.tenant_name
    Description = "SSL certificate for ${var.tenant_name} tenant"
  }
}

// Local account:  ACM validation.
resource "aws_acm_certificate_validation" "internal-us-west-2" {
  provider = aws.us-west-2

  certificate_arn = aws_acm_certificate.internal-us-west-2.arn
  validation_record_fqdns = aws_route53_record.internal-acm.*.fqdn
}
resource "aws_acm_certificate_validation" "internal-us-east-2" {
  provider = aws.us-east-2

  certificate_arn = aws_acm_certificate.internal-us-east-2.arn
  validation_record_fqdns = aws_route53_record.internal-acm.*.fqdn
}

// Local account: *.elisity.net certificate
data "aws_secretsmanager_secret" "sslcert" {
  name = "elisity-ambassador-certs"
}
data "aws_secretsmanager_secret_version" "sslcert" {
  secret_id = data.aws_secretsmanager_secret.sslcert.id
}
resource "aws_acm_certificate" "external-us-west-2" {
  provider = aws.us-west-2

  private_key = jsondecode(data.aws_secretsmanager_secret_version.sslcert.secret_string)["tls.key"]
  certificate_body = jsondecode(data.aws_secretsmanager_secret_version.sslcert.secret_string)["tls.crt"]
  certificate_chain = file("${path.module}/files/digicert-root.crt")
}
resource "aws_acm_certificate" "external-us-east-2" {
  provider = aws.us-east-2

  private_key = jsondecode(data.aws_secretsmanager_secret_version.sslcert.secret_string)["tls.key"]
  certificate_body = jsondecode(data.aws_secretsmanager_secret_version.sslcert.secret_string)["tls.crt"]
  certificate_chain = file("${path.module}/files/digicert-root.crt")
}
