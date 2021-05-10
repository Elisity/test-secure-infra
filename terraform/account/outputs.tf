output "tenant_name" {
  value = var.tenant_name
}

output "duplo_url" {
  value = local.duplo_url
}

output "internal_fqdn" {
  value = local.internal_fqdn
}

output "external_fqdn" {
  value = local.external_fqdn
}

output "internal_zone_id" {
  value = aws_route53_zone.internal.id
}

output "ecr_registry_id" {
  description = "The ID of the ECR regisry"
  value       = local.master_account_id
}

output "ecr_registry_host" {
  description = "The DNS name of the ECR regisry"
  value       = "${local.master_account_id}.dkr.ecr.${local.master_ecr_region}.amazonaws.com"
}

output "master_amis" {
  description = "A map of maps:  region => AMI name => AMI ID"
  value = {
    "us-west-2" = module.master-amis-us-west-2.ami_ids,
    "us-east-2" = module.master-amis-us-east-2.ami_ids,
  }
}

output "internal_acm_certificates" {
  description = "A map of certs:  region => cert ARN"
  value = {
    "us-west-2" = aws_acm_certificate.internal-us-west-2.arn,
    "us-east-2" = aws_acm_certificate.internal-us-east-2.arn,
  }
}

output "duplo_authelb_arn" {
  value = data.aws_elb.duplo-authelb.arn
}

output "duplo_authelb_fqdn" {
  value = data.aws_elb.duplo-authelb.dns_name
}
