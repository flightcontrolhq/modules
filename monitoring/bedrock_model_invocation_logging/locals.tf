################################################################################
# Local Values
################################################################################

locals {
  region         = coalesce(var.region, data.aws_region.current.region)
  log_group_name = coalesce(var.log_group_name, "/aws/bedrock/model-invocations/${var.name}")

  default_tags = {
    ManagedBy = "terraform"
    Module    = "monitoring/bedrock_model_invocation_logging"
  }

  tags = merge(local.default_tags, var.tags)
}
