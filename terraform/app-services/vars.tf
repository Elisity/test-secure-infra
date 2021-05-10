variable "infra_name" {
  type = string
}

variable "prewarming" {
  type = bool
  default = false
}

variable "external_edpd_servers" {
  type = list(string)
  default = []
}

variable "allow_icmp" {
  type = bool
  default = false
}

variable "manage_eks_private_route_tables" {
  type = bool
  default = true
}

variable "tls_subnet_cidrs" {
  type = object({mgmt = map(string), uplink = map(string), access = map(string)})
}

variable "tls_server_image_name" {
  type  = string
  default = "koala-0.74-aws"
}

variable "tls_server_ami_id" {
  type  = string
  description = "Override the AMI ID used for the TLS servers"
  default = ""
}

variable "tls_server_instance_type" {
  type  = string
  default = "t3a.large"
}

variable "tls_server_os_disk_size" {
  type  = string
  default = "35"
}

variable "extra_tls_ingress_rules" {
  type = list(object({source = string, protocol = string, from_port = number, to_port = number, description = string}))
  default = []
}

variable "eks_subnet_cidrs" {
  type  = map(string)
  description = "A map of duplo zones to private subnet CIDRS, e.g.: { \"A\" : \"10.20.3.0/25\" }"
}

variable "eks_nodes_per_zone" {
  type  = number
  default = 1
}

variable "eks_node_image_name" {
  type  = string
  default = "amazon-eks-node-1.18-v20210322"
}

variable "eks_node_instance_type" {
  type  = string
  default = "m5a.xlarge"
}

variable "internal_eks_nodes_per_zone" {
  type  = number
  default = 1
}

variable "internal_eks_node_instance_type" {
  type  = string
  default = "t3a.medium"
}

variable "elastic_eks_nodes_per_zone" {
  type  = number
  default = 1
}

variable "elastic_eks_node_instance_type" {
  type  = string
  default = "r5.large"
}

variable "eks_node_os_disk_size" {
  type  = string
  default = "50"
}

variable "ambassador_internal_docker_image" {
  type  = string
  default = "quay.io/datawire/ambassador:0.61.0"
}

variable "elasticsearch_version" {
  type = number
  default = "7.8"
}

variable "main_elasticsearch_storage_size" {
  type = number
  default = 120
}

variable "main_elasticsearch_instance_type" {
  type = string
  default = "r5.xlarge.elasticsearch"
}

# variable "analytics_elasticsearch_storage_size" {
#   type = number
#   default = 120
# }

# variable "analytics_elasticsearch_instance_type" {
#   type = string
#   default = "r5.xlarge.elasticsearch"
# }

# variable "log_elasticsearch_storage_size" {
#   type = number
#   default = 100
# }

# variable "log_elasticsearch_instance_type" {
#   type = string
#   default = "m5.large.elasticsearch"
# }

variable "mongodb_docker_image" {
  type        = string
  default     = "docker.io/bitnami/mongodb:4.2.8-debian-10-r47"
  description = "The docker image to use for MongoDB when it is running in Duplo"
}

variable "mongodb_root_password_length" {
  type        = number
  default     = 32
  description = "The length of the MongoDB root password"
}

variable "mongodb_password_length" {
  type        = number
  default     = 32
  description = "The length of the MongoDB password"
}

variable "mongodb_replicaset_key_length" {
  type        = number
  default     = 32
  description = "The length of the MongoDB replicaset key"
}

variable "mongodb_volume_size" {
  type = number
  default = 120
  description = "The size of the MongoDB data volume"
}

variable "postgres_version" {
  type        = string
  default     = "12.5"
  description = "The version of the PostgreSQL RDS instance"
}

variable "postgres_instance_size" {
  type        = string
  default     = "db.m5.large"
  description = "The instance size of the PostgreSQL RDS instance"
}

variable "postgres_master_user_length" {
  type        = number
  default     = 14
  description = "The length of the Postgres master username"
}

variable "postgres_master_password_length" {
  type        = number
  default     = 32
  description = "The length of the Postgres master password"
}

variable "kafka_version" {
  type = string
  default = "2.4.1.1"
}

variable "main_kafka_storage_size" {
  type = number
  default = 100
}

variable "main_kafka_instance_type" {
  type = string
  default = "kafka.m5.large"
}

variable "analytics_kafka_storage_size" {
  type = number
  default = 100
}

variable "analytics_kafka_instance_type" {
  type = string
  default = "kafka.m5.large"
}

variable "log_kafka_storage_size" {
  type = number
  default = 50
}

variable "log_kafka_instance_type" {
  type = string
  default = "kafka.m5.large"
}

variable "keycloak_mgmt_password_length" {
  type        = number
  default     = 16
  description = "The length of the keycloak mgmt password"
}

variable "keycloak_password_length" {
  type        = number
  default     = 16
  description = "The length of the keycloak password"
}

variable "acm_certificate_domain" {
  type = string
  default = ""
  description = "The ACM certificate domain to be used with the ALB for the external Ambassador"  
}

variable "subdomain" {
  type = string
  default = ""
  description = "Subdomain to associate with the external ambassador"
}

variable "fqdn" {
  type = string
  default = ""
  description = "FQDN to associate with the external ambassador"
}

variable "manage_customer_role" {
  type = bool
  default = false
}

variable "customer_role_arn" {
  type = string
  description = "Customer's role ARN that Elisity can assume to manage the customer account"
  default = ""
}

variable "customer_role_external_id" {
  type = string
  description = "Customer's role external ID that Elisity can assume to manage the customer account"
  default = ""
}

variable "customer_aws_account_id" {
  type = string
  description = "Customer's AWS account ID"
  default = ""
}

variable "customer_org_name" {
  type = string
  description = "Customer's Org name"
}

variable "customer_name" {
  type = string
  description = "Customer's name"
}

variable "customer_email" {
  type = string
  description = "Customer's email"
}
