################################################################################
# Application Auto Scaling — Read Replica Scaling
################################################################################

resource "aws_appautoscaling_target" "this" {
  count = var.enable_autoscaling ? 1 : 0

  service_namespace  = "rds"
  scalable_dimension = "rds:cluster:ReadReplicaCount"
  resource_id        = "cluster:${aws_rds_cluster.this.cluster_identifier}"
  min_capacity       = var.autoscaling_min_capacity
  max_capacity       = var.autoscaling_max_capacity

  lifecycle {
    precondition {
      condition     = var.autoscaling_min_capacity <= var.autoscaling_max_capacity
      error_message = "autoscaling_min_capacity must be less than or equal to autoscaling_max_capacity."
    }
  }

  depends_on = [
    aws_rds_cluster_instance.this,
  ]
}

################################################################################
# CPU Target Tracking Policy
################################################################################

resource "aws_appautoscaling_policy" "cpu" {
  count = var.enable_autoscaling ? 1 : 0

  name               = coalesce(var.autoscaling_policy_name, "${var.name}-aurora-cpu-scaling")
  service_namespace  = aws_appautoscaling_target.this[0].service_namespace
  scalable_dimension = aws_appautoscaling_target.this[0].scalable_dimension
  resource_id        = aws_appautoscaling_target.this[0].resource_id
  policy_type        = "TargetTrackingScaling"

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "RDSReaderAverageCPUUtilization"
    }

    target_value       = var.autoscaling_target_cpu
    scale_in_cooldown  = var.autoscaling_scale_in_cooldown
    scale_out_cooldown = var.autoscaling_scale_out_cooldown
  }
}

################################################################################
# Connection Target Tracking Policy (optional)
################################################################################

resource "aws_appautoscaling_policy" "connections" {
  count = var.enable_autoscaling && var.autoscaling_target_connections != null ? 1 : 0

  name               = "${var.name}-aurora-connections-scaling"
  service_namespace  = aws_appautoscaling_target.this[0].service_namespace
  scalable_dimension = aws_appautoscaling_target.this[0].scalable_dimension
  resource_id        = aws_appautoscaling_target.this[0].resource_id
  policy_type        = "TargetTrackingScaling"

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "RDSReaderAverageDatabaseConnections"
    }

    target_value       = var.autoscaling_target_connections
    scale_in_cooldown  = var.autoscaling_scale_in_cooldown
    scale_out_cooldown = var.autoscaling_scale_out_cooldown
  }
}
