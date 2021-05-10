output "name" {
  description = "The name for the ElasticSearch instance"
  value = local.es_name
}

output "cluster_name" {
  description = "The cluster name of the ElasticSearch instance"
  value = local.es_name
}

output "endpoints" {
  description = "The endpoints for the ElasticSearch instance"
  value = {
    vpc = "${local.es_name}.${var.namespace}"
  }
}

output "proxy_host" {
  description = "The in-cluster proxy host for the ElasticSearch instance"
  value = "${local.es_name}.${var.namespace}"
  // value = "${duplocloud_duplo_service.proxy.name}.${var.namespace}"
}

output "proxy_port" {
  description = "The in-cluster proxy port for the ElasticSearch instance"
  value = 9200
}

output "kibana_host" {
  description = "The in-cluster host for the Kibana instance"
  value = "${local.kibana_name}.${var.namespace}"
}

output "kibana_port" {
  description = "The in-cluster port for the Kibana instance"
  value = 5601
}
