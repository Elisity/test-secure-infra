locals {

  // Builds a map of eks node suffix to zone.
  //
  //  { "a-1" : {"name" : "A", "index" : 0},
  //    "a-2" : {"name" : "A", "index" : 0},
  //    "b-0" : {"name" : "B", "index" : 1},
  //    ....
  //    ....
  eks_nodes          = { for node in setproduct(local.zones, range(var.eks_nodes_per_zone)): 
                           lower("${node[0]}${node[1] + 1}") => { name = node[0], index = index(local.zones, node[0]) } }
  internal_eks_nodes = { for node in setproduct(local.zones, range(var.internal_eks_nodes_per_zone)): 
                           lower("${node[0]}${node[1] + 1}") => { name = node[0], index = index(local.zones, node[0]) } }
  elastic_eks_nodes  = { for node in setproduct(local.zones, range(var.elastic_eks_nodes_per_zone)): 
                           lower("${node[0]}${node[1] + 1}") => { name = node[0], index = index(local.zones, node[0]) } }
}

// Find the right EKS AMI for whatever region we are in.
data "aws_ami" "eks" {
  most_recent      = true
  owners           = ["amazon"]

  filter {
    name   = "name"
    values = [coalesce(var.eks_node_image_name, "amazon-eks-node-1.18-*")]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

// Main tenant - EKS nodes.
resource "duplocloud_aws_host" "eks-node" {
  depends_on = [ aws_route_table_association.eks-node ]
  for_each = local.eks_nodes

  lifecycle {
    create_before_destroy = true
    ignore_changes = [
      metadata,
      zone // NOTE:  duplo cannot detect zone when subnet is custom
    ]
  }

  user_account = duplocloud_tenant.this.account_name
  tenant_id    = duplocloud_tenant.this.tenant_id

  friendly_name  = "eks-node-${each.key}"

  image_id       = data.aws_ami.eks.image_id
  capacity       = var.eks_node_instance_type
  agent_platform = 7
  zone           = each.value["index"]

  metadata {
    key   = "OsDiskSize"
    value = tostring(var.eks_node_os_disk_size)
  }

  network_interface {
    subnet_id = duplocloud_infrastructure_subnet.eks-node[each.value["name"]].subnet_id
  }

  provisioner "local-exec" {
    command = "sleep 60"
  }
}
resource "aws_ec2_tag" "eks-node-infratype" {
  for_each = duplocloud_aws_host.eks-node

  resource_id = each.value.instance_id
  key         = "ElisityInfraType"
  value       = "ESI"
}
resource "aws_ec2_tag" "eks-node-customer" {
  for_each = duplocloud_aws_host.eks-node

  resource_id = each.value.instance_id
  key         = "ElisityCustomerSubdomain"
  value       = local.customer_subdomain
}

// Internal tenant - EKS nodes
resource "duplocloud_aws_host" "eks-node-internal" {
  depends_on = [ aws_route_table_association.eks-node ]
  for_each = local.internal_eks_nodes

  lifecycle {
    create_before_destroy = true
    ignore_changes = [
      metadata,
      zone // NOTE:  duplo cannot detect zone when subnet is custom
    ]
  }

  user_account = duplocloud_tenant.internal.account_name
  tenant_id    = duplocloud_tenant.internal.tenant_id

  friendly_name  = "eks-node-${each.key}"

  image_id       = data.aws_ami.eks.image_id
  capacity       = var.internal_eks_node_instance_type
  agent_platform = 7
  zone           = each.value["index"]

  metadata {
    key   = "OsDiskSize"
    value = tostring(var.eks_node_os_disk_size)
  }

  network_interface {
    subnet_id = duplocloud_infrastructure_subnet.eks-node[each.value["name"]].subnet_id
  }

  provisioner "local-exec" {
    command = "sleep 60"
  }
}
resource "aws_ec2_tag" "eks-node-internal-infratype" {
  for_each = duplocloud_aws_host.eks-node-internal

  resource_id = each.value.instance_id
  key         = "ElisityInfraType"
  value       = "ESI"
}
resource "aws_ec2_tag" "eks-node-internal-customer" {
  for_each = duplocloud_aws_host.eks-node-internal

  resource_id = each.value.instance_id
  key         = "ElisityCustomerSubdomain"
  value       = local.customer_subdomain
}

// ElasticSearch tenant - EKS nodes
resource "duplocloud_aws_host" "eks-node-elastic" {
  depends_on = [ aws_route_table_association.eks-node ]
  for_each = local.elastic_eks_nodes

  lifecycle {
    create_before_destroy = true
    ignore_changes = [
      metadata,

      // NOTE:  duplo cannot detect the below when the subnet is custom
      allocated_public_ip,
      zone
    ]
  }

  user_account = duplocloud_tenant.elastic.account_name
  tenant_id    = duplocloud_tenant.elastic.tenant_id

  friendly_name  = "eks-node-${each.key}"

  image_id       = data.aws_ami.eks.image_id
  capacity       = var.elastic_eks_node_instance_type
  agent_platform = 7
  zone           = each.value["index"]

  metadata {
    key   = "OsDiskSize"
    value = tostring(var.eks_node_os_disk_size)
  }

  network_interface {
    subnet_id = duplocloud_infrastructure_subnet.eks-node[each.value["name"]].subnet_id
  }

  provisioner "local-exec" {
    command = "sleep 60"
  }
}
