variable "tenant_id" {
  type = string
  description = "The ID of the Duplo tenant"
}

variable "namespace" {
  type = string
  description = "The K8S namespace to install into"
}

variable "name" {
  type = string
  description = "The name suffix of the ElasticSearch instance"
}

variable "zones" {
  type = list(string)
  description = "A list of Duplo zones for this ES instance"
}

variable "nginx_docker_image" {
  description = "The NGINX image to use for the proxy"
  default = "nginx:1.19.9"
}

variable "es_version" {
  type = string
  default = "7.8.1"
}

variable "es_chart_version" {
  type = string
  default = "7.8.1"
}

variable "es_image" {
  type = string
  default = "docker.elastic.co/elasticsearch/elasticsearch"
}

variable "es_image_tag" {
  type = string
  default = "7.8.1"
}

variable "kibana_chart_version" {
  type = string
  default = "7.8.1"
}

variable "kibana_image" {
  type = string
  default = "docker.elastic.co/kibana/kibana"
}

variable "kibana_image_tag" {
  type = string
  default = "7.8.1"
}

variable "storage_size" {
  type = number
  default = 120
}


variable "es_resource_limits" {
  type = map(string)
  default = {
    cpu = "1000m"
    memory = "12Gi"
  }
}
variable "es_resource_requests" {
  type = map(string)
  default = {
    cpu = "1000m"
    memory = "10Gi"
  }
}

variable "es_java_opts" {
  type = string
  default = "-Xmx9g -Xms9g"
}

variable "kibana_resource_limits" {
  type = map(string)
  default = {
    cpu = "1000m"
    memory = "3Gi"
  }
}
variable "kibana_resource_requests" {
  type = map(string)
  default = {
    cpu = "500m"
    memory = "2Gi"
  }
}
