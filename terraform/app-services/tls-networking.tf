locals {
  tls_zone_indices = {
    A = 1,
    B = 0,
    C = 2,
  }
  tls_subnet_infratypes = {
    mgmt = "Mgmt"
    access = "Inside"
    uplink = "Outside"
  }

  # Maps all unique combinations of TLS subnet name and zone
  tls_subnet_map = {
    for name_and_zone in setproduct(keys(local.tls_subnet_infratypes), local.zones) :
      "${name_and_zone[0]}-zone${name_and_zone[1]}" => { subnet = name_and_zone[0], zone = name_and_zone[1] }
  }

  # For public IPs: Maps all unique combinations of TLS subnet name and zone
  tls_public_subnet_map = {
    for name_and_zone in setproduct(keys(local.tls_subnet_infratypes), local.zones) :
      "${name_and_zone[0]}-zone${name_and_zone[1]}" => { subnet = name_and_zone[0], zone = name_and_zone[1] } if name_and_zone[0] != "access"
  }

  tls_core_ingress_rules = [
    { cidr_blocks = [ "0.0.0.0/0" ], protocol = "tcp", from_port = 80, to_port = 80 },
    { cidr_blocks = [ "0.0.0.0/0" ], protocol = "udp", from_port = 6081, to_port = 6081 },
    { cidr_blocks = [ local.vpc_cidr ], protocol = "-1", from_port = 0, to_port = 0, description = "All traffic from ${local.infra_name} VPC" },
    { cidr_blocks = [ "0.0.0.0/0" ], protocol = "udp", from_port = 6080, to_port = 6080 },
    { cidr_blocks = [ "0.0.0.0/0" ], protocol = "tcp", from_port = 6080, to_port = 6080 },
    { cidr_blocks = [ "0.0.0.0/0" ], protocol = "tcp", from_port = 443, to_port = 443 },
    { cidr_blocks = [ "0.0.0.0/0" ], protocol = "icmp", from_port = 0, to_port = 0},
  ]
}

// Security group for TLS
resource "aws_security_group" "tls" {
  vpc_id = local.vpc_id
  name = "${local.tenant_name}-tls-server"
  description = "Security Group for TLS"

  tags = {
    Name = "${local.tenant_name}-tls-server"
    Infrastructure = local.infra_name
    Tenant = local.tenant_name
    Plan = local.plan_id
    ElisityCustomerSubdomain = local.customer_subdomain
  }
}

// Allow any egress from TLS servers
resource "aws_security_group_rule" "tls-egress" {
  type = "egress"
  security_group_id = aws_security_group.tls.id

  cidr_blocks = [ "0.0.0.0/0" ]
  from_port = 0
  to_port = 0
  protocol = "-1"
}

// Core TLS ingress rules that shouldn't be customized
resource "aws_security_group_rule" "tls-core" {
  count = length(local.tls_core_ingress_rules)

  type = "ingress"
  security_group_id = aws_security_group.tls.id

  cidr_blocks = local.tls_core_ingress_rules[count.index]["cidr_blocks"]
  protocol = local.tls_core_ingress_rules[count.index]["protocol"]
  from_port = local.tls_core_ingress_rules[count.index]["from_port"]
  to_port = local.tls_core_ingress_rules[count.index]["to_port"]
  description = lookup(local.tls_core_ingress_rules[count.index], "description", "")
}

// Extra ingress rules that differ per environment.
resource "aws_security_group_rule" "tls-extra" {
  for_each = toset(var.extra_tls_ingress_rules)

  type = "ingress"
  security_group_id = aws_security_group.tls.id

  cidr_blocks = [ each.value["source"] ]
  protocol = each.value["protocol"]
  from_port = each.value["from_port"]
  to_port = each.value["to_port"]
  description = each.value["description"]
}

// Subnets for TLS
resource "aws_subnet" "tls" {
  for_each = local.tls_subnet_map

  vpc_id = local.vpc_id
  cidr_block = var.tls_subnet_cidrs[each.value["subnet"]][each.value["zone"]]
  availability_zone = "${local.region}${lower(each.value["zone"])}"

  tags = {
    Name = "${local.tenant_name}-tls-${each.key}"
    Purpose = "tls"
    Zone = each.value["zone"]
    Subnet = each.value["subnet"]
    Tenant = local.tenant_name
    Infra = local.infra_name
    ElisityCustomerSubdomain = local.customer_subdomain
  }
}

// ENIs for TLS
resource "aws_network_interface" "tls" {
  for_each = local.tls_subnet_map

  description = "${local.tenant_name}-tls-${each.key}"
  subnet_id = aws_subnet.tls[each.key].id
  security_groups = [ aws_security_group.tls.id ]

  # Assign a static private IP
  private_ips = [ cidrhost(aws_subnet.tls[each.key].cidr_block, "7") ]

  # Only do source / dest check on mgmt subnet
  source_dest_check = each.value["subnet"] == "mgmt" ? true : false

  tags = {
    Name = "${local.tenant_name}-tls-${each.key}"
    Zone = each.value["zone"]
    Subnet = each.value["subnet"]
    Tenant = local.tenant_name
    Infra = local.infra_name
    ElisityNetworkInfraType = local.tls_subnet_infratypes[each.value["subnet"]]
    ElisityCustomerSubdomain = local.customer_subdomain
  }
}

// EIPs for TLS
resource "aws_eip" "tls" {
  for_each = local.tls_public_subnet_map

  vpc = true
  network_interface = aws_network_interface.tls[each.key].id

  tags = {
    Name = "${local.tenant_name}-tls-${each.key}"
    Zone = each.value["zone"]
    Subnet = each.value["subnet"]
    Tenant = local.tenant_name
    Infra = local.infra_name
    ElisityCustomerSubdomain = local.customer_subdomain
  }
}

// Route table to use for TLS
resource "aws_route_table" "tls" {
  vpc_id = local.vpc_id

  tags = {
    Name = "${local.tenant_name}-tls"
    Infra = local.infra_name
    Tenant = local.tenant_name
    Reach = "tls"
    ElisityCustomerSubdomain = local.customer_subdomain
  }
}

// Copy the Duplo VPC peering route to the TLS route table
resource "aws_route" "tls-peering" {
  for_each = { for r in local.duplo_private_routes : "duplo" => r if length(lookup(r, "vpc_peering_connection_id", "")) > 0 }

  route_table_id = aws_route_table.tls.id
  destination_cidr_block = each.value["cidr_block"]
  vpc_peering_connection_id = each.value["vpc_peering_connection_id"]
}

// Copy the IGW to the TLS route table
resource "aws_route" "tls-igw" {
  for_each = { for r in local.duplo_public_routes : "duplo" => r if length(lookup(r, "gateway_id", "")) > 0 }

  route_table_id = aws_route_table.tls.id
  destination_cidr_block = each.value["cidr_block"]
  gateway_id = each.value["gateway_id"]
}


// Associate the new TLS route table with the TLS subnets
resource "aws_route_table_association" "tls" {
  depends_on = [ aws_route.tls-peering, aws_route.tls-igw ]

  for_each = local.tls_subnet_map

  route_table_id = aws_route_table.tls.id
  subnet_id = aws_subnet.tls[each.key].id
}
