output "tenant_prefix" {
  description = "The duplo tenant prefix"
  value = local.tenant_name
}

output "tenant_name" {
  description = "The duplo tenant name"
  value = duplocloud_tenant.this.account_name
}

output "tenant_id" {
  description = "The duplo tenant ID"
  value = duplocloud_tenant.this.tenant_id
}

output "internal_tenant_name" {
  description = "The internal duplo tenant name"
  value = duplocloud_tenant.internal.account_name
}

output "internal_tenant_id" {
  description = "The internal duplo tenant ID"
  value = duplocloud_tenant.internal.tenant_id
}

output "elastic_tenant_name" {
  description = "The elasticsearch duplo tenant name"
  value = duplocloud_tenant.elastic.account_name
}

output "elastic_tenant_id" {
  description = "The elasticsearch duplo tenant ID"
  value = duplocloud_tenant.elastic.tenant_id
}

output "region" {
  description = "The duplo infrastructure region"
  value = local.region
}

output "customer_subdomain" {
  description = "The customer subdomain"
  value = local.customer_subdomain
}

output "customer_fqdn" {
  description = "The customer FQDN"
  value = local.customer_fqdn
}

output "customer_role_arn" {
  description = "The role ARN that the Elisity master can assume"
  value = local.customer_role_arn
}

output "customer_role_external_id" {
  description = "The external ID that the Elisity master must use when assuming role"
  value = local.customer_role_external_id
}

output "customer_aws_account_id" {
  description = "The customer's AWS account ID"
  value = local.customer_aws_account_id
}

output "customer_email" {
  description = "The customer's email"
  value = var.customer_email
}

output "customer_name" {
  description = "The customer's name"
  value = var.customer_name
}

output "customer_org_name" {
  description = "The customer's org name"
  value = var.customer_org_name
}

output "plan_id" {
  description = "The duplo tenant plan ID"
  value = duplocloud_tenant.this.plan_id
}

output "zones" {
  description = "The zone list for the duplo infrastructure housing the tenant"
  value = data.terraform_remote_state.base-infra.outputs["zones"]
}

output "ecr_registry_id" {
  description = "The ID of the ECR regisry"
  value       = data.terraform_remote_state.base-infra.outputs["ecr_registry_id"]
}

output "ecr_registry_host" {
  description = "The DNS name of the ECR regisry"
  value       = data.terraform_remote_state.base-infra.outputs["ecr_registry_host"]
}

output "internal_ambassador_dns" {
  description = "The DNS name of the internal ambassador"
  value = "ambassador-internal.${data.duplocloud_tenant_eks_credentials.internal.namespace}"
}

output "main_elasticsearch_name" {
  description = "The duplo name for the ElasticSearch instance"
  value = module.elasticsearch-main.name
}

output "main_elasticsearch_cluster_name" {
  description = "The cluster name of the ElasticSearch instance"
  value = module.elasticsearch-main.cluster_name
}

output "main_elasticsearch_endpoints" {
  description = "The endpoints for the ElasticSearch instance"
  value = module.elasticsearch-main.endpoints
}

output "main_esproxy_host" {
  description = "The in-cluster host for the ElasticSearch instance"
  value = module.elasticsearch-main.proxy_host
}

output "main_esproxy_port" {
  description = "The in-cluster port for the ElasticSearch instance"
  value = module.elasticsearch-main.proxy_port
}

output "main_kibana_host" {
  description = "The in-cluster host for the Kibana instance"
  value = module.elasticsearch-main.kibana_host
}

output "main_kibana_port" {
  description = "The in-cluster port for the Kibana instance"
  value = module.elasticsearch-main.kibana_port
}

output "mongodb_configmap_name" {
  description = "The k8s configmap name for mongodb"
  value = duplocloud_k8_config_map.mongodb.name
}

output "mongodb_secret_name" {
  description = "The k8s secret name for mongodb"
  value = duplocloud_k8_secret.mongodb.secret_name
}

output "postgres_identifier" {
  description = "The full identifier for the postgres RDS instance"
  value = duplocloud_rds_instance.postgres.identifier
}

output "postgres_arn" {
  description = "The ARN for the postgres RDS instance"
  value = duplocloud_rds_instance.postgres.arn
}

output "postgres_endpoint" {
  description = "The endpoint for the postgres RDS instance"
  value = duplocloud_rds_instance.postgres.endpoint
}

output "postgres_host" {
  description = "The host for the postgres RDS instance"
  value = duplocloud_rds_instance.postgres.host
}

output "postgres_port" {
  description = "The port for the postgres RDS instance"
  value = duplocloud_rds_instance.postgres.port
}

output "postgres_master_username" {
  sensitive = true
  value = duplocloud_rds_instance.postgres.master_username
}

output "postgres_master_password" {
  sensitive = true
  value = duplocloud_rds_instance.postgres.master_password
}

output "postgres_keycloak_db_name" {
  value = local.keycloak_db_name
}

output "keycloak_admin_realm_user" {
  value = local.keycloak_mgmt_user
}

output "keycloak_admin_realm_password" {
  sensitive = true
  value = random_password.keycloak-password.result
}

output "main_kafka_tls_zookeeper_connect_string" {
  description = "The TLS connect string for the Kafka Zookeeper cluster"
  value = join(",", sort(split(",", duplocloud_aws_kafka_cluster.main.tls_zookeeper_connect_string)))
}

output "main_kafka_plaintext_zookeeper_connect_string" {
  description = "The plaintext connect string for the Kafka Zookeeper cluster"
  value = join(",", sort(split(",", duplocloud_aws_kafka_cluster.main.plaintext_zookeeper_connect_string)))
}

output "main_kafka_tls_bootstrap_broker_string" {
  description = "The TLS connect string for the Kafka bootstrap broker"
  value = join(",", sort(split(",", duplocloud_aws_kafka_cluster.main.tls_bootstrap_broker_string)))
}

output "main_kafka_plaintext_bootstrap_broker_string" {
  description = "The plaintext connect string for the Kafka bootstrap broker"
  value = join(",", sort(split(",", duplocloud_aws_kafka_cluster.main.plaintext_bootstrap_broker_string)))
}

output "tls_uplink_ips" {
  description = "The list of public IP addresses for the TLS servers uplink ENIs"
  value =  [for zone in local.zones: aws_eip.tls["uplink-zone${zone}"].public_ip]
}
