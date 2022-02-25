



locals {
  deduplicated_region_list = toset(concat([var.region], var.ipam_operating_regions))
}

// Service-Linked Role
resource "aws_iam_service_linked_role" "ipam" {
  aws_service_name = "ipam.amazonaws.com"
  description      = "Service Linked Role for AWS VPC IP Address Manager"
}

// deduplication ?
resource "aws_vpc_ipam" "tutorial" {
  description = "my-ipam"
  dynamic "operating_regions" {
    for_each = local.deduplicated_region_list
    content {
      region_name = operating_regions.value
    }
  }
  depends_on = [
    aws_iam_service_linked_role.ipam
  ]
}

resource "aws_vpc_ipam_pool" "top_level" {
  description    = "top-level-pool"
  address_family = "ipv4"
  ipam_scope_id  = aws_vpc_ipam.tutorial.private_default_scope_id
}

# provision CIDR to the top-level pool
resource "aws_vpc_ipam_pool_cidr" "top_level" {
  ipam_pool_id = aws_vpc_ipam_pool.top_level.id
  cidr         = var.top_level_pool_cidr # "10.0.0.0/8" if following the tutorial
}

// on local.deduplicated_region_list local variable again to create multiple regional pools according to the region list you’ve set.

resource "aws_vpc_ipam_pool" "regional" {
  for_each            = local.deduplicated_region_list
  description         = "${each.key}-pool"
  address_family      = "ipv4"
  ipam_scope_id       = aws_vpc_ipam.tutorial.private_default_scope_id
  locale              = each.key
  source_ipam_pool_id = aws_vpc_ipam_pool.top_level.id
}

resource "aws_vpc_ipam_pool_cidr" "regional" {
  for_each     = { for index, region in tolist(local.deduplicated_region_list) : region => index } 
  ipam_pool_id = aws_vpc_ipam_pool.regional[each.key].id
  cidr         = cidrsubnet(var.top_level_pool_cidr, 8, each.value)
}

// I had to convert the toset-transformed local.deduplicated_region_list to a list again. The purpose was to allow the for expression to properly retrieve the index of each region.
{ 
  us-east-1 = 0,
  us-west-2 = 1
}


resource "aws_vpc" "tutorial" {
  ipv4_ipam_pool_id   = aws_vpc_ipam_pool.regional[var.region].id
  ipv4_netmask_length = 24 
  depends_on = [
    aws_vpc_ipam_pool_cidr.regional
  ]
}


