# module "flowlogcontrol-service" {
#   source = "../modules/elisity-microservice"

#   tenant_id = local.tenant_id
#   name  = "flowlogcontrol"
#   service_defaults = local.service_defaults

#   env = concat(
#     [ { name = "aws.floglogs.bucketname", value = local.flowlogs_bucketname }, ],
#     local.common_envs
#   )
  
#   env_from = [
#     { type = "configmap", name = duplocloud_k8_config_map.common.name },
#     { type = "configmap", name = duplocloud_k8_config_map.elastic.name },
#   ]
# }
