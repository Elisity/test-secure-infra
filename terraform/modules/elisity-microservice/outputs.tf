output "service-hostname" {
  description = "The k8s service hostname of this service"
  value = duplocloud_duplo_service.this.name
}

output "service-port" {
  description = "The k8s service external port of this service"
  value = var.service.external_port
}
