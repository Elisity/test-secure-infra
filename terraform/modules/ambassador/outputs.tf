output "loadbalancer_arn" {
  description = "The load balancer ARN for this service"
  value = var.ambassador_is_internal ? null : duplocloud_duplo_service_lbconfigs.this.arn
}

output "service-hostname" {
  description = "The k8s service hostname of this service"
  value = duplocloud_duplo_service.this.name
}
