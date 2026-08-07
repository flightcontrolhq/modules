################################################################################
# Data Sources
################################################################################

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

data "aws_vpc" "this" {
  id = var.vpc_id
}

data "aws_rds_cluster" "password_preservation" {
  count = var.master_user_password_preservation_enabled ? 1 : 0

  cluster_identifier = var.name
}
