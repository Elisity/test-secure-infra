locals {
  eks_private_route_table_zones = var.manage_eks_private_route_tables ? local.zones : []
}

// Subnets for private EKS nodes.
resource "duplocloud_infrastructure_subnet" "eks-node" {
  for_each = toset(local.zones)

  infra_name = local.infra_name

  name = "${local.tenant_name}-eks-${lower(each.key)}-private"
  cidr_block = var.eks_subnet_cidrs[each.key]
  type = "private"
  zone = each.key

  tags = {
    Infra = local.infra_name
    Tenant = local.tenant_name
    Purpose = "eks"
    Reach = "private"
    ElisityCustomerSubdomain = local.customer_subdomain
  }
}

// Routing for private EKS nodes.
resource "aws_route_table" "eks-node" {
  for_each = toset(local.zones)

  vpc_id = local.vpc_id

  tags = {
    Name = "${local.tenant_name}-eks-${lower(each.key)}-private"
    Infra = local.infra_name
    Tenant = local.tenant_name
    Reach = "private"
    ElisityCustomerSubdomain = local.customer_subdomain
  }
}

resource "aws_route" "eks-node" {
  count = local.zone_count * length(local.duplo_private_routes)

  route_table_id = aws_route_table.eks-node[local.zones[count.index % local.zone_count]].id

  destination_cidr_block = local.duplo_private_routes[floor(count.index / local.zone_count)]["cidr_block"]

  vpc_peering_connection_id = local.duplo_private_routes[floor(count.index / local.zone_count)]["vpc_peering_connection_id"]
  nat_gateway_id = local.duplo_private_routes[floor(count.index / local.zone_count)]["nat_gateway_id"]
  gateway_id = local.duplo_private_routes[floor(count.index / local.zone_count)]["gateway_id"]
}

resource "aws_route_table_association" "eks-node" {
  for_each = toset(local.eks_private_route_table_zones)

  depends_on = [ aws_route.eks-node ]

  route_table_id = aws_route_table.eks-node[each.key].id
  subnet_id = duplocloud_infrastructure_subnet.eks-node[each.key].subnet_id
}
