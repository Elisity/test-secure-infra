locals {
  tls_ami_id = data.terraform_remote_state.base-infra.outputs["master_amis"][local.region][var.tls_server_image_name]

  tls_routable_eks_node_ips = concat(
    [ for k, node in duplocloud_aws_host.eks-node: node.private_ip_address ],
    [ for k, node in duplocloud_aws_host.eks-node-internal: node.private_ip_address ]
  )
}

// TLS servers, spread evenly across zones.
resource "duplocloud_aws_host" "tls" {
  depends_on = [ 
    aws_route_table.tls,
    aws_route.tls-peering,
    aws_route.tls-igw,
    aws_route_table_association.tls,
    aws_security_group.tls,
    aws_security_group_rule.tls-egress,
    aws_security_group_rule.tls-core,
    aws_security_group_rule.tls-extra
  ]

  for_each = toset(local.zones)

  lifecycle {
    ignore_changes = [
      metadata,

      // NOTE:  duplo cannot detect the below when the subnet is custom
      allocated_public_ip,
      zone
    ]
  }

  user_account = duplocloud_tenant.this.account_name
  tenant_id    = duplocloud_tenant.this.tenant_id

  friendly_name  = "tls-${lower(each.key)}"

  image_id       = coalesce(var.tls_server_ami_id, local.tls_ami_id)
  capacity       = var.tls_server_instance_type
  cloud          = 0
  agent_platform = 0
  zone           = index(local.zones, each.key)

  base64_user_data = base64encode(
    templatefile("${path.module}/files/tls-nodes-userdata.txt", {
      eth0          = aws_network_interface.tls["mgmt-zone${each.key}"].private_ip,
      eth1          = aws_network_interface.tls["uplink-zone${each.key}"].private_ip,
      eth1Public    = aws_eip.tls["uplink-zone${each.key}"].public_ip,
      eth2          = aws_network_interface.tls["access-zone${each.key}"].private_ip,
      ipAddress     = join("', '", local.tls_routable_eks_node_ips),
    })
  )

  network_interface {
    network_interface_id = aws_network_interface.tls["mgmt-zone${each.key}"].id
    device_index = 0
  }

  provisioner "local-exec" {
    command = "sleep 90"
  }
}
resource "aws_ec2_tag" "tls-infratype" {
  for_each = duplocloud_aws_host.tls

  resource_id = each.value.instance_id
  key         = "ElisityInfraType"
  value       = "TLS"
}
resource "aws_ec2_tag" "tls-customer" {
  for_each = duplocloud_aws_host.tls

  resource_id = each.value.instance_id
  key         = "ElisityCustomerSubdomain"
  value       = local.customer_subdomain
}

// Workaround for AWS issue with network device ordering.
resource "aws_network_interface_attachment" "tls-uplink" {
  for_each = duplocloud_aws_host.tls

  instance_id = each.value.instance_id
  network_interface_id = aws_network_interface.tls["uplink-zone${each.key}"].id
  device_index = 1

  provisioner "local-exec" {
    command = "sleep 15"
  }
}
resource "aws_network_interface_attachment" "tls-access" {
  for_each = duplocloud_aws_host.tls

  instance_id = each.value.instance_id
  network_interface_id = aws_network_interface.tls["access-zone${each.key}"].id

  # NOTE:  This forces Terraform to introduce a dependency on the prior network interface
  device_index = aws_network_interface_attachment.tls-uplink[each.key].device_index + 1

  provisioner "local-exec" {
    command = "sleep 15"
  }
}
