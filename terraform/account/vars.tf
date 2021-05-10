variable "default_region" {
  type = string
  default = "us-west-2"
  description = "The default region to create infrastructure in"
}

variable "tenant_name" {
  type = string
}

variable "manage_duplo_install" {
  type = bool
  default = true
}

variable "duplo_root_stack_path" {
  type = string
  default = ""
}

variable "duplo_url" {
  type = string
  default = ""
}

variable "internal_fqdn" {
  type = string
  default = ""
}
