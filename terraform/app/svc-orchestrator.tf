# FIXME:  We need to get all of this configured.
locals {
  ecas_image_id = "ecas-ami"
  lb_image_id = "lb-ami"
  ece_image_id = "ece-ami"
  lambda_deploy_request_url = "https://${module.awslambdadeploy-service.service-hostname}:${module.awslambdadeploy-service.service-port}/lambda/deploy"
}

module "orchestrator-service" {
  source = "../modules/elisity-microservice"

  tenant_id = local.tenant_id
  name  = "orchestrator"
  service_defaults = local.service_defaults

  replicas = 1

  env = concat(
    [
      { name = "ecas.imageId", value = local.ecas_image_id },
      { name = "lb.imageId", value = local.lb_image_id },
      { name = "ece.imageId", value = local.ece_image_id },
      { name = "elasticsearch.host", value = local.elastic_endpoint_url },
      { name = "elisity.lambdaDeploy.svc.deployRequestUrl", value = local.lambda_deploy_request_url },
      { name = "tlsNodeIP", value = join(",",local.tls_uplink_ips) },
    ],
    local.common_envs
  )
  
  env_from = [
    { type = "configmap", name = duplocloud_k8_config_map.common.name },
  ]
}
