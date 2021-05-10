resource "duplocloud_k8_config_map" "common" {
  tenant_id = local.tenant_id

  name = "eli-common"
  data = jsonencode({
    "spring.profiles.active"         = local.env_name,
    "kafka.bootstrapAddress"         = local.kafka_bootstrap_address,
    "kafka.bootstrap-servers"        = local.kafka_bootstrap_address,
    "spring.kafka.bootstrap-servers" = local.kafka_bootstrap_address,
    "LOG_KAFKA_ADDR"                 = local.kafka_log,
  })
}

resource "duplocloud_k8_config_map" "auth" {
  tenant_id = local.tenant_id

  name = "eli-auth"
  data = jsonencode({
    "customer.domain" = local.customer_subdomain,
    "elisity.kops.host" = local.k8s_endpoint,
  })
}

resource "duplocloud_k8_secret" "auth" {
  tenant_id = local.tenant_id

  secret_name = "eli-okta"
  secret_type = "Opaque"
  secret_data = jsonencode({
    "nothing" = "here"
    // Per Raghavan, these are now taken from the UI.
    //
    // "okta.oauth2.issuer" = local.okta_oauth2_issuer,
    // "okta.oauth2.client_id" = local.okta_oauth2_client_id,
    // "okta.oauth2.client_secret" = local.okta_oauth2_client_secret,
    // "okta.elisity.api.conf" = local.okta_elisity_api_token,
  })
}

resource "duplocloud_k8_config_map" "ambassador-gateway" {
  tenant_id = local.tenant_id

  name = "eli-ambassador-gateway"
  data = jsonencode({
    "ambassador.gateway.host"       = local.ambassador_elb_url,
  })
}

resource "duplocloud_k8_config_map" "log-elastic" {
  tenant_id = local.tenant_id

  name = "eli-elastic-log"
  data = jsonencode({
    "LOG_ELASTIC_HOST"       = local.elastic_endpoint_url,
    "LOG_ELASTIC_PORT"       = tostring(local.elastic_endpoint_port),
  })
}

resource "duplocloud_k8_config_map" "elastic" {
  tenant_id = local.tenant_id

  name = "eli-elastic"
  data = jsonencode({
    "elisity.elastic.cluster"        = local.elastic_cluster_name,
    "elisity.elastic.host.url"       = local.elastic_endpoint_url,
    "elisity.elastic.host.port"      = tostring(local.elastic_endpoint_port),
  })
}

resource "duplocloud_k8_config_map" "kibana" {
  tenant_id = local.tenant_id

  name = "eli-kibana"
  data = jsonencode({
    "kibana.host"       = local.kibana_host,
    "kibana.port"       = tostring(local.kibana_port),
  })
}

resource "duplocloud_k8_config_map" "analytics" {
  tenant_id = local.tenant_id

  name = "eli-analytics"
  data = jsonencode({
    "kafka.bootstrap-analytics-servers"         = local.kafka_bootstrap_analytics_address,
    "spring.kafka.bootstrap-analytics-servers" = local.kafka_bootstrap_analytics_address,
    "elisity.elastic.analytics.cluster"        = local.elastic_analytics_cluster_name,
    "elisity.elastic.analytics.host.url"       = local.elastic_analytics_endpoint_url,
    "elisity.elastic.analytics.host.port"       = tostring(local.elastic_analytics_endpoint_port),
  })
}
