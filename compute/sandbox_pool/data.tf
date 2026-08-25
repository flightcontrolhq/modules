################################################################################
# Data Sources
################################################################################

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

data "aws_partition" "current" {}

# Route tables the S3 gateway endpoint attaches to. Snapshot chunks are the
# bulk of a pool's byte movement and they are all S3, so the gateway endpoint
# is where the money is saved; interface endpoints only fix auth and metadata.
data "aws_route_tables" "vpc" {
  count = var.create_vpc_endpoints && var.s3_gateway_route_table_ids == null ? 1 : 0

  vpc_id = var.execution_environment.vpc_id
}
