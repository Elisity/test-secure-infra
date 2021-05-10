variable "to_region" {
  type = string
  description = "The region to share the AMI(s) to"
}

variable "master_amis" {
  description = "list of AMI names to copy from Elisity master"
  type = list(string)
  default = [ "koala-0.74-aws" ]
}
