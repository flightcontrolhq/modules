################################################################################
# VPC endpoints
#
# Snapshot chunks are S3 objects and they are the bulk of everything a pool
# moves, so the gateway endpoint — free — is the one that matters. The
# interface pair for SSM keeps Session Manager working in a private subnet, and
# the ECR pair keeps base-image auth off the NAT gateway.
################################################################################

locals {
  s3_route_table_ids = var.create_vpc_endpoints ? (
    var.s3_gateway_route_table_ids != null ? var.s3_gateway_route_table_ids : data.aws_route_tables.vpc[0].ids
  ) : []

  interface_endpoints = var.create_vpc_endpoints ? {
    ssm         = "com.amazonaws.${local.region}.ssm"
    ssmmessages = "com.amazonaws.${local.region}.ssmmessages"
    ecr_api     = "com.amazonaws.${local.region}.ecr.api"
    ecr_dkr     = "com.amazonaws.${local.region}.ecr.dkr"
  } : {}
}

resource "aws_vpc_endpoint" "s3" {
  count = var.create_vpc_endpoints ? 1 : 0

  vpc_id            = var.execution_environment.vpc_id
  service_name      = "com.amazonaws.${local.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = local.s3_route_table_ids

  tags = merge(local.tags, { Name = "${local.name_prefix}-s3" })
}

resource "aws_vpc_endpoint" "interface" {
  for_each = local.interface_endpoints

  vpc_id              = var.execution_environment.vpc_id
  service_name        = each.value
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.execution_environment.subnet_ids
  security_group_ids  = [aws_security_group.endpoints[0].id]
  private_dns_enabled = true

  tags = merge(local.tags, { Name = "${local.name_prefix}-${replace(each.key, "_", "-")}" })
}
