terraform {
  required_version = "~> 0.14"

  required_providers {
    duplocloud = {
      version = "~> 0.5.22"
      source = "registry.terraform.io/duplocloud/duplocloud"
    }
    helm = { version = "~> 2.0" }
  }
}

locals {
  zone_count = length(var.zones)

  es_name = "elasticsearch-${var.name}"
  es_chart_version = coalesce(var.es_chart_version, var.es_version)
  es_image_tag = coalesce(var.es_image_tag, var.es_version)

  kibana_name = "kibana-${var.name}"
  kibana_chart_version = coalesce(var.kibana_chart_version, var.es_version)
  kibana_image_tag = coalesce(var.kibana_image_tag, var.es_version)
}

// ElasticSearch cluster.
resource "helm_release" "elasticsearch" {
  name      = local.es_name
  namespace = var.namespace

  version   = local.es_chart_version
  repository = "https://helm.elastic.co"
  chart     = "elasticsearch"
  atomic    = true
  timeout   = 300 # 5 minutes timeout to wait for hosts

  values = [yamlencode({
    namespace = var.namespace,
    fullnameOverride = local.es_name,

    # Ensure that replicas are in separate zones, and we only run in the selected tenant.
    antiAffinityTopologyKey = "failure-domain.beta.kubernetes.io/zone",
    nodeSelector = { tenantname = var.namespace, },
    
    clusterName = local.es_name,
    image = var.es_image,
    imageTag = local.es_image_tag,
    replicas = local.zone_count,
    minimumMasterNodes = max(1, local.zone_count - 1),
    esJavaOpts = var.es_java_opts,
    resources = {
      requests = var.es_resource_requests,
      limits = var.es_resource_limits,
    },
    readinessProbe = {
      initialDelaySeconds = 60,  # wait 60 seconds before the first probe.
    },
    volumeClaimTemplate = {
      resources = { requests = { storage = "${var.storage_size}Gi" } }
    },
  })]
}

// Kibana
resource "helm_release" "kibana" {
  name      = local.kibana_name
  namespace = var.namespace

  version   = local.kibana_chart_version
  repository = "https://helm.elastic.co"
  chart     = "kibana"
  atomic    = true
  timeout   = 300 # 5 minutes timeout to wait for hosts

  values = [yamlencode({
    namespace = var.namespace,
    fullnameOverride = local.kibana_name,

    # Ensure that replicas are in separate zones, and we only run in the selected tenant.
    nodeSelector = { tenantname = var.namespace, },
    
    elasticsearchHosts = "http://${local.es_name}:9200"
    image = var.kibana_image,
    imageTag = local.kibana_image_tag,
    replicas = local.zone_count,
    resources = {
      requests = var.kibana_resource_requests,
      limits = var.kibana_resource_limits,
    },
    readinessProbe = {
      initialDelaySeconds = 60,  # wait 60 seconds before the first probe.
    },
  })]
}
