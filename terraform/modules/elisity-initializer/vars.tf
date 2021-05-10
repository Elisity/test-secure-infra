variable "tenant_id" {
  type = string
}

variable "name" {
  type = string
}

variable "namespace" {
  type = string
}

variable "script" {
  type = string
}

variable "script_args" {
  type = list(string)
  default = []
}

variable "dependent_deployment" {
  type = string
  default = ""
}

variable "extra_sleep" {
  type = number
  default = 120
}

variable "steps" {
  type = list(string)
  default = ["step-001"]
}

variable "files" {
  type = map(string)
  default = {}
}

variable "env" {
  type = list(object({name = string, value = string}))
  default = []
}

variable "image" {
  type = string
  default = "amazon/aws-cli:latest"
}

variable "kubectl_version" {
  type = string
  default = "1.18.8"
}
