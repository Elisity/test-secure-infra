// Access to the Elisity DNS AWS account
data "aws_secretsmanager_secret" "dnscreds" {
  name = "elisity-dns-awscreds"
}
data "aws_secretsmanager_secret_version" "dnscreds" {
  secret_id = data.aws_secretsmanager_secret.dnscreds.id
}
provider "aws" {
  alias = "dns"

  region = local.region
  access_key = jsondecode(data.aws_secretsmanager_secret_version.dnscreds.secret_string)["accessKeyId"]
  secret_key = jsondecode(data.aws_secretsmanager_secret_version.dnscreds.secret_string)["secretAccessKey"]
}

// The route53 zone to update
data "aws_route53_zone" "this" {
  provider = aws.dns

  name = "elisity.net."
  private_zone = false
}

// TLS uplink DNS records
resource "aws_route53_record" "tls-uplink" {
  provider = aws.dns

  zone_id = data.aws_route53_zone.this.zone_id
  name    = "${local.customer_subdomain}-tls.${data.aws_route53_zone.this.name}"
  type    = "A"
  ttl     = 600
  records = [ for key, eip in aws_eip.tls : eip.public_ip if substr(key,0,7) == "uplink-"  ]
}

// ELB alias DNS records
data "aws_lb" "ambassador" {
  arn = module.ambassador.loadbalancer_arn
}
resource "aws_route53_record" "ambassador" {
  provider = aws.dns

  zone_id = data.aws_route53_zone.this.zone_id
  name    = "${local.customer_subdomain}.${data.aws_route53_zone.this.name}"
  type    = "A"

  alias {
    zone_id = data.aws_lb.ambassador.zone_id
    name = data.aws_lb.ambassador.dns_name
    evaluate_target_health = true
  }
}
