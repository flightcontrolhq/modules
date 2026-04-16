################################################################################
# Local Values
################################################################################

locals {
  # Tags
  default_tags = {
    ManagedBy = "terraform"
    Module    = "database/dynamodb"
  }
  tags = merge(local.default_tags, var.tags)

  # Billing mode flags
  is_provisioned = var.billing_mode == "PROVISIONED"
  is_on_demand   = var.billing_mode == "PAY_PER_REQUEST"

  # Autoscaling is only valid for provisioned tables
  create_table_autoscaling = var.autoscaling_enabled && local.is_provisioned

  # Per-GSI autoscaling targets expressed as a flat map keyed by "<gsi>/<read|write>"
  gsi_autoscaling_targets = local.create_table_autoscaling ? merge(
    {
      for k, v in var.autoscaling_indexes : "${k}/read" => merge(v.read, { index_name = k })
      if v.read != null
    },
    {
      for k, v in var.autoscaling_indexes : "${k}/write" => merge(v.write, { index_name = k })
      if v.write != null
    },
  ) : {}

  # Global table replication uses the top-level replica block on aws_dynamodb_table.
  # Streams are required for v2 replicas; validated in the table resource.
  has_replicas = length(var.replicas) > 0
}
