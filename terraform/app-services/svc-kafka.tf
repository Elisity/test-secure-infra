resource "aws_msk_configuration" "main" {

  // FIXME: only during development
  lifecycle {
    ignore_changes = [ server_properties ]
  }

  name = "duploservices-${local.tenant_name}-main"
  kafka_versions = [ var.kafka_version ]

  server_properties = <<PROPERTIES
auto.create.topics.enable=true
default.replication.factor=${local.zone_count}
min.insync.replicas=${min(local.zone_count, 2)}
num.io.threads=8
num.network.threads=5
num.partitions=1
num.replica.fetchers=2
replica.lag.time.max.ms=30000
socket.receive.buffer.bytes=102400
socket.request.max.bytes=104857600
socket.send.buffer.bytes=102400
unclean.leader.election.enable=true
zookeeper.session.timeout.ms=18000
PROPERTIES
}

resource "duplocloud_aws_kafka_cluster" "main" {
  tenant_id = duplocloud_tenant.this.tenant_id
  name = "main"
  subnets = [ for sn in local.private_subnets: sn["id"] ]
  kafka_version = var.kafka_version
  configuration_arn = aws_msk_configuration.main.arn
  configuration_revision = aws_msk_configuration.main.latest_revision
  instance_type = var.main_kafka_instance_type
  storage_size = var.main_kafka_storage_size
}

# // Analytics Kafka cluster
# resource "duplocloud_aws_kafka_cluster" "analytics" {
#   tenant_id = duplocloud_tenant.this.tenant_id
#   name = "analytics"
#   kafka_version = var.kafka_version
#   configuration_arn = aws_msk_configuration.main.arn
#   configuration_revision = aws_msk_configuration.main.latest_revision
#   instance_type = var.analytics_kafka_instance_type
#   storage_size = var.analytics_kafka_storage_size
# }

# // Log Kafka cluster
# resource "duplocloud_aws_kafka_cluster" "log" {
#   tenant_id = duplocloud_tenant.this.tenant_id
#   name = "log"
#   kafka_version = var.kafka_version
#   configuration_arn = aws_msk_configuration.main.arn
#   configuration_revision = aws_msk_configuration.main.latest_revision
#   instance_type = var.log_kafka_instance_type
#   storage_size = var.log_kafka_storage_size
# }
