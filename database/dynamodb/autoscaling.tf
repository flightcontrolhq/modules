################################################################################
# Application Auto Scaling — Table Read Capacity
################################################################################

resource "aws_appautoscaling_target" "table_read" {
  count = local.create_table_autoscaling ? 1 : 0

  service_namespace  = "dynamodb"
  scalable_dimension = "dynamodb:table:ReadCapacityUnits"
  resource_id        = "table/${aws_dynamodb_table.this.name}"
  min_capacity       = var.autoscaling_read.min_capacity
  max_capacity       = var.autoscaling_read.max_capacity
}

resource "aws_appautoscaling_policy" "table_read" {
  count = local.create_table_autoscaling ? 1 : 0

  name               = "${var.name}-dynamodb-read-scaling"
  service_namespace  = aws_appautoscaling_target.table_read[0].service_namespace
  scalable_dimension = aws_appautoscaling_target.table_read[0].scalable_dimension
  resource_id        = aws_appautoscaling_target.table_read[0].resource_id
  policy_type        = "TargetTrackingScaling"

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "DynamoDBReadCapacityUtilization"
    }

    target_value       = var.autoscaling_read.target_utilization
    scale_in_cooldown  = var.autoscaling_read.scale_in_cooldown
    scale_out_cooldown = var.autoscaling_read.scale_out_cooldown
  }
}

################################################################################
# Application Auto Scaling — Table Write Capacity
################################################################################

resource "aws_appautoscaling_target" "table_write" {
  count = local.create_table_autoscaling ? 1 : 0

  service_namespace  = "dynamodb"
  scalable_dimension = "dynamodb:table:WriteCapacityUnits"
  resource_id        = "table/${aws_dynamodb_table.this.name}"
  min_capacity       = var.autoscaling_write.min_capacity
  max_capacity       = var.autoscaling_write.max_capacity
}

resource "aws_appautoscaling_policy" "table_write" {
  count = local.create_table_autoscaling ? 1 : 0

  name               = "${var.name}-dynamodb-write-scaling"
  service_namespace  = aws_appautoscaling_target.table_write[0].service_namespace
  scalable_dimension = aws_appautoscaling_target.table_write[0].scalable_dimension
  resource_id        = aws_appautoscaling_target.table_write[0].resource_id
  policy_type        = "TargetTrackingScaling"

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "DynamoDBWriteCapacityUtilization"
    }

    target_value       = var.autoscaling_write.target_utilization
    scale_in_cooldown  = var.autoscaling_write.scale_in_cooldown
    scale_out_cooldown = var.autoscaling_write.scale_out_cooldown
  }
}

################################################################################
# Application Auto Scaling — GSI Read/Write Capacity
################################################################################

resource "aws_appautoscaling_target" "gsi" {
  for_each = local.gsi_autoscaling_targets

  service_namespace  = "dynamodb"
  scalable_dimension = endswith(each.key, "/read") ? "dynamodb:index:ReadCapacityUnits" : "dynamodb:index:WriteCapacityUnits"
  resource_id        = "table/${aws_dynamodb_table.this.name}/index/${each.value.index_name}"
  min_capacity       = each.value.min_capacity
  max_capacity       = each.value.max_capacity
}

resource "aws_appautoscaling_policy" "gsi" {
  for_each = local.gsi_autoscaling_targets

  name               = "${var.name}-dynamodb-${each.value.index_name}-${endswith(each.key, "/read") ? "read" : "write"}-scaling"
  service_namespace  = aws_appautoscaling_target.gsi[each.key].service_namespace
  scalable_dimension = aws_appautoscaling_target.gsi[each.key].scalable_dimension
  resource_id        = aws_appautoscaling_target.gsi[each.key].resource_id
  policy_type        = "TargetTrackingScaling"

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = endswith(each.key, "/read") ? "DynamoDBReadCapacityUtilization" : "DynamoDBWriteCapacityUtilization"
    }

    target_value       = each.value.target_utilization
    scale_in_cooldown  = each.value.scale_in_cooldown
    scale_out_cooldown = each.value.scale_out_cooldown
  }
}
