variable "tenant_id" {
  type = string
}

variable "name" {
  type = string
}

variable "image" {
  type = string
  default = ""
}

variable "replicas" {
  type = number
  default = 2
}

variable "service_account_name" {
  type = string
  default = null
}

variable "uid" {
  type = number
  default = 1000
}

variable "gid" {
  type = number
  default = 1000
}

variable "drop_privileges" {
  type = bool
  default = false
}

variable "env" {
  type = list(object({name = string, value = string}))
  default = []
}

variable "env_from" {
  type = list(object({type = string, name = string}))
  default = []
}

variable "volumes" {
  type = list(any)
  default = []
}

variable "ports" {
  type = list(object({container_port = number, name = string, protocol = string}))
  default = [
    { container_port = 8080, name = "server", protocol = "TCP" },
    { container_port = 8080, name = "management", protocol = "TCP" }
  ]
}

variable "service" {
  type = object({port = string, external_port = number, protocol = string})
  default = {
    port = "8080"
    external_port = 8080
    protocol = "tcp"
  }
}

variable "service_defaults" {
  type = object({registry = string, names = map(string), tags = map(string), default_tag = string})
  default = {
    registry = "557790859333.dkr.ecr.us-west-2.amazonaws.com",
    names = {},
    tags = {},
    default_tag = "latest",
  }
}
