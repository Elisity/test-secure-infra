variable "region" {
  type = string
  default = "us-east-2"
  description = "The region to create the infrastructure in"
}

variable "prewarming" {
  type = bool
  default = false
}

variable "az_count" {
  description = "The number of AZs to have in the infra"
  default = 3
}

variable "vpc_cidr" {
  description = "The CIDR block to use for the VPC" 
}

variable "subnet_cidr_bits" {
  description = "The CIDR bits to reserve for each subnet"
  default = 25
}

variable "master_amis" {
  description = "list of AMI names to copy from Elisity master"
  type = list(string)
  default = [ "koala-0.74-aws" ]
}

variable "tls_vpc_cidrs" {
  description = "Extra CIDR blocks associated with the VPC, for TLS servers"
  type = map(string)
}
