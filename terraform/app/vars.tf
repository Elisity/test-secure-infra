variable "env_name" {
  type = string
  default = ""
}

variable "infra_name" {
  type = string
}

variable "prewarming" {
  type = bool
  default = false
}

variable "upgrade_time" {
  type = string
  description = "Allow forcing all services to update by setting this to a unique value"
  default = ""
}

variable "default_replicas" {
  type = number
  default = 0 // use the AZ count
}

variable "app_image_names" {
  type = map(string)
  default = {
    "eventsmanager" = "events-manager-service"
    "cloudconfig" = "cloud-configuration-service"
    "ipallocator" = "ip-allocator-service"
    "keymgr" = "key-manager-service"
    "policyeng" = "policyengine-service"
    "policyevaluator" = "policy-evaluator-service"
    "tunnelmgr" = "tunnel-manager-service"
    "awslambdadeploy" = "aws_lambda_deploy-service"
  }
}

variable "app_image_tags" {
  type = map(string)
  default = {
    "ui2" = "ecr_latest",
  }
}

variable "app_image_default_tag" {
  type = string
  default = "latest"
}
