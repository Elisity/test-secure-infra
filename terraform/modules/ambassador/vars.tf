variable "name" {
  type = string
  default = "ambassador"
  description = "The name of the ambassador instance"
}

variable "namespace" {
  type = string
  description = "The namespace where the ambassador instance is running"
}

variable "tenant_id" {
  type = string
  description = "The ID of the duplo tenant where the ambassador instance is running"
}

variable "ambassador_replicas" {
  type  = number
  description = "The number of replicas to run"
}

variable "ambassador_image" {
  type  = string
  default = "quay.io/datawire/ambassador:0.86.1"
  description = "The docker image for ambassador"
}

variable "ambassador_service_annotations" {
  type = map(string)
  default = {}
  description = "The annotations to put on the ambassador service"
}

variable "ambassador_is_internal" {
  type = bool
  default = false
  description = "Is this an internal ambassador"
}

variable "ambassador_certificate_arn" {
  type  = string
  description = "The ACM certificate ARN for the ambassador load balancer"
  default = ""
}

variable "dns_prefix" {
  type = string
  description = "The DNS subdomain to use if this is an external ambassador"
  default = ""
}

variable "waf_id" {
  type = string
  description = "The WAF to use if this is an external ambassador"
  default = ""
}
