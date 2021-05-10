output "infra_name" {
  description = "The duplo infrastructure name"
  value = duplocloud_infrastructure.this.infra_name
}

output "plan_id" {
  description = "The duplo infrastructure plan ID"
  value = duplocloud_infrastructure.this.infra_name
}

output "region" {
  description = "The duplo infrastructure region"
  value = duplocloud_infrastructure.this.region
}

output "subnet_cidr_bits" {
  description = "The number of bits for a VPC CIDR"
  value = var.subnet_cidr_bits
}

output "all_zones" {
  description = "The entire duplo infrastructure zone list"
  value = [for sn in duplocloud_infrastructure.this.private_subnets: sn.zone]
}

output "zones" {
  description = "The applicable duplo infrastructure zones"
  value = slice([for sn in duplocloud_infrastructure.this.private_subnets: sn.zone], 0, var.az_count)
}

output "vpc_id" {
  description = "The duplo infrastructure VPC ID"
  value = duplocloud_infrastructure.this.vpc_id
}

output "vpc_cidr" {
  description = "The duplo infrastructure VPC CIDR"
  value = duplocloud_infrastructure.this.address_prefix
}

output "tls_vpc_cidrs" {
  description = "The extra VPC CIDRs for TLS servers"
  value = var.tls_vpc_cidrs
}

output "all_private_subnets" {
  description = "The duplo infrastructure private subnets"
  value = duplocloud_infrastructure.this.private_subnets
}

output "private_subnets" {
  description = "The applicable duplo infrastructure private subnets"
  value = var.az_count > 1 ? duplocloud_infrastructure.this.private_subnets : [ for sn in duplocloud_infrastructure.this.private_subnets: sn if sn.zone == "A"]
}

output "private_route_table_id" {
  description = "The duplo infrastructure private route table ID"
  value = data.aws_route_table.private.id
}

output "private_routes" {
  description = "The duplo infrastructure private routes"
  value = data.aws_route_table.private.routes
}

output "all_public_subnets" {
  description = "The duplo infrastructure public subnets"
  value = duplocloud_infrastructure.this.private_subnets
}

output "public_subnets" {
  description = "The applicable duplo infrastructure public subnets"
  value = var.az_count > 1 ? duplocloud_infrastructure.this.public_subnets : [ for sn in duplocloud_infrastructure.this.public_subnets: sn if sn.zone == "A"]
}

output "public_route_table_id" {
  description = "The duplo infrastructure public route table ID"
  value = data.aws_route_table.public.id
}

output "public_routes" {
  description = "The duplo infrastructure public routes"
  value = data.aws_route_table.public.routes
}

output "ecr_registry_id" {
  description = "The ID of the ECR regisry"
  value       = data.terraform_remote_state.account.outputs["ecr_registry_id"]
}

output "ecr_registry_host" {
  description = "The DNS name of the ECR regisry"
  value       = data.terraform_remote_state.account.outputs["ecr_registry_host"]
}

output "master_amis" {
  description = "A map of maps:  region => AMI name => AMI ID"
  value       = data.terraform_remote_state.account.outputs["master_amis"]
}
