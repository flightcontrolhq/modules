################################################################################
# DynamoDB Table
################################################################################

resource "aws_dynamodb_table" "this" {
  name         = var.name
  billing_mode = var.billing_mode
  hash_key     = var.hash_key
  range_key    = var.range_key
  table_class  = var.table_class

  read_capacity  = local.is_provisioned ? var.read_capacity : null
  write_capacity = local.is_provisioned ? var.write_capacity : null

  stream_enabled   = var.stream_enabled || local.has_replicas
  stream_view_type = (var.stream_enabled || local.has_replicas) ? var.stream_view_type : null

  deletion_protection_enabled = var.deletion_protection_enabled

  dynamic "attribute" {
    for_each = var.attributes
    content {
      name = attribute.value.name
      type = attribute.value.type
    }
  }

  dynamic "global_secondary_index" {
    for_each = var.global_secondary_indexes
    content {
      name               = global_secondary_index.value.name
      hash_key           = global_secondary_index.value.hash_key
      range_key          = global_secondary_index.value.range_key
      projection_type    = global_secondary_index.value.projection_type
      non_key_attributes = global_secondary_index.value.non_key_attributes
      read_capacity      = local.is_provisioned ? global_secondary_index.value.read_capacity : null
      write_capacity     = local.is_provisioned ? global_secondary_index.value.write_capacity : null
    }
  }

  dynamic "local_secondary_index" {
    for_each = var.local_secondary_indexes
    content {
      name               = local_secondary_index.value.name
      range_key          = local_secondary_index.value.range_key
      projection_type    = local_secondary_index.value.projection_type
      non_key_attributes = local_secondary_index.value.non_key_attributes
    }
  }

  dynamic "ttl" {
    for_each = var.ttl_enabled ? [1] : []
    content {
      enabled        = true
      attribute_name = var.ttl_attribute_name
    }
  }

  point_in_time_recovery {
    enabled = var.point_in_time_recovery_enabled
  }

  server_side_encryption {
    enabled     = var.server_side_encryption_enabled
    kms_key_arn = var.server_side_encryption_kms_key_arn
  }

  dynamic "replica" {
    for_each = var.replicas
    content {
      region_name            = replica.value.region_name
      kms_key_arn            = replica.value.kms_key_arn
      propagate_tags         = replica.value.propagate_tags
      point_in_time_recovery = replica.value.point_in_time_recovery
    }
  }

  dynamic "timeouts" {
    for_each = (var.timeouts.create != null || var.timeouts.update != null || var.timeouts.delete != null) ? [1] : []
    content {
      create = var.timeouts.create
      update = var.timeouts.update
      delete = var.timeouts.delete
    }
  }

  tags = merge(local.tags, { Name = var.name })

  lifecycle {
    precondition {
      condition     = !local.is_provisioned || (var.read_capacity != null && var.write_capacity != null)
      error_message = "read_capacity and write_capacity are required when billing_mode is PROVISIONED."
    }

    precondition {
      condition     = var.ttl_enabled == false || length(var.ttl_attribute_name) > 0
      error_message = "ttl_attribute_name must be set when ttl_enabled is true."
    }

    precondition {
      condition     = !local.has_replicas || var.stream_enabled
      error_message = "stream_enabled must be true to create global table replicas."
    }

    precondition {
      condition     = length(var.local_secondary_indexes) == 0 || var.range_key != null
      error_message = "range_key must be set when defining local_secondary_indexes."
    }

    # When autoscaling manages capacity, Terraform should not revert to var.read/write_capacity on subsequent plans.
    ignore_changes = [
      read_capacity,
      write_capacity,
      global_secondary_index,
    ]
  }
}
