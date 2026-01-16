################################################################################
# Scaling Policies
################################################################################

resource "aws_autoscaling_policy" "this" {
  for_each = { for policy in var.scaling_policies : policy.name => policy }

  name                   = each.value.name
  autoscaling_group_name = aws_autoscaling_group.this.name
  policy_type            = each.value.policy_type
  enabled                = each.value.enabled

  # Estimated instance warmup (all policy types except SimpleScaling)
  estimated_instance_warmup = each.value.policy_type != "SimpleScaling" ? each.value.estimated_instance_warmup : null

  ##############################################################################
  # SimpleScaling and StepScaling Configuration
  ##############################################################################

  # Adjustment type (SimpleScaling and StepScaling)
  adjustment_type = contains(["SimpleScaling", "StepScaling"], each.value.policy_type) ? each.value.adjustment_type : null

  # Minimum adjustment magnitude (SimpleScaling and StepScaling with PercentChangeInCapacity)
  min_adjustment_magnitude = contains(["SimpleScaling", "StepScaling"], each.value.policy_type) ? each.value.min_adjustment_magnitude : null

  # Cooldown (SimpleScaling only)
  cooldown = each.value.policy_type == "SimpleScaling" ? each.value.cooldown : null

  # Scaling adjustment (SimpleScaling only)
  scaling_adjustment = each.value.policy_type == "SimpleScaling" ? each.value.scaling_adjustment : null

  # Metric aggregation type (StepScaling only)
  metric_aggregation_type = each.value.policy_type == "StepScaling" ? each.value.metric_aggregation_type : null

  # Step adjustments (StepScaling only)
  dynamic "step_adjustment" {
    for_each = each.value.policy_type == "StepScaling" && each.value.step_adjustments != null ? each.value.step_adjustments : []
    content {
      metric_interval_lower_bound = step_adjustment.value.metric_interval_lower_bound
      metric_interval_upper_bound = step_adjustment.value.metric_interval_upper_bound
      scaling_adjustment          = step_adjustment.value.scaling_adjustment
    }
  }

  ##############################################################################
  # TargetTrackingScaling Configuration
  ##############################################################################

  dynamic "target_tracking_configuration" {
    for_each = each.value.policy_type == "TargetTrackingScaling" && each.value.target_tracking_configuration != null ? [each.value.target_tracking_configuration] : []
    content {
      target_value     = target_tracking_configuration.value.target_value
      disable_scale_in = target_tracking_configuration.value.disable_scale_in

      # Predefined metric specification
      dynamic "predefined_metric_specification" {
        for_each = target_tracking_configuration.value.predefined_metric_specification != null ? [target_tracking_configuration.value.predefined_metric_specification] : []
        content {
          predefined_metric_type = predefined_metric_specification.value.predefined_metric_type
          resource_label         = predefined_metric_specification.value.resource_label
        }
      }

      # Customized metric specification
      dynamic "customized_metric_specification" {
        for_each = target_tracking_configuration.value.customized_metric_specification != null ? [target_tracking_configuration.value.customized_metric_specification] : []
        content {
          # Simple metric specification (legacy style)
          metric_name = customized_metric_specification.value.metric_name
          namespace   = customized_metric_specification.value.namespace
          statistic   = customized_metric_specification.value.statistic
          unit        = customized_metric_specification.value.unit

          # Dimensions for simple metric
          dynamic "metric_dimension" {
            for_each = customized_metric_specification.value.dimensions != null ? customized_metric_specification.value.dimensions : []
            content {
              name  = metric_dimension.value.name
              value = metric_dimension.value.value
            }
          }

          # Multiple metrics with math expressions (advanced)
          dynamic "metrics" {
            for_each = customized_metric_specification.value.metrics != null ? customized_metric_specification.value.metrics : []
            content {
              id          = metrics.value.id
              return_data = metrics.value.return_data
              label       = metrics.value.label
              expression  = metrics.value.expression

              # Metric stat for CloudWatch metrics
              dynamic "metric_stat" {
                for_each = metrics.value.metric_stat != null ? [metrics.value.metric_stat] : []
                content {
                  stat = metric_stat.value.stat
                  unit = metric_stat.value.unit

                  metric {
                    metric_name = metric_stat.value.metric.metric_name
                    namespace   = metric_stat.value.metric.namespace

                    dynamic "dimensions" {
                      for_each = metric_stat.value.metric.dimensions != null ? metric_stat.value.metric.dimensions : []
                      content {
                        name  = dimensions.value.name
                        value = dimensions.value.value
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }

  ##############################################################################
  # PredictiveScaling Configuration
  ##############################################################################

  dynamic "predictive_scaling_configuration" {
    for_each = each.value.policy_type == "PredictiveScaling" && each.value.predictive_scaling_configuration != null ? [each.value.predictive_scaling_configuration] : []
    content {
      mode                         = predictive_scaling_configuration.value.mode
      scheduling_buffer_time       = predictive_scaling_configuration.value.scheduling_buffer_time
      max_capacity_breach_behavior = predictive_scaling_configuration.value.max_capacity_breach_behavior
      max_capacity_buffer          = predictive_scaling_configuration.value.max_capacity_buffer

      # Metric specifications
      dynamic "metric_specification" {
        for_each = predictive_scaling_configuration.value.metric_specifications
        content {
          target_value = metric_specification.value.target_value

          # Predefined load metric specification
          dynamic "predefined_load_metric_specification" {
            for_each = metric_specification.value.predefined_load_metric_specification != null ? [metric_specification.value.predefined_load_metric_specification] : []
            content {
              predefined_metric_type = predefined_load_metric_specification.value.predefined_metric_type
              resource_label         = predefined_load_metric_specification.value.resource_label
            }
          }

          # Predefined scaling metric specification
          dynamic "predefined_scaling_metric_specification" {
            for_each = metric_specification.value.predefined_scaling_metric_specification != null ? [metric_specification.value.predefined_scaling_metric_specification] : []
            content {
              predefined_metric_type = predefined_scaling_metric_specification.value.predefined_metric_type
              resource_label         = predefined_scaling_metric_specification.value.resource_label
            }
          }

          # Predefined metric pair specification
          dynamic "predefined_metric_pair_specification" {
            for_each = metric_specification.value.predefined_metric_pair_specification != null ? [metric_specification.value.predefined_metric_pair_specification] : []
            content {
              predefined_metric_type = predefined_metric_pair_specification.value.predefined_metric_type
              resource_label         = predefined_metric_pair_specification.value.resource_label
            }
          }

          # Customized load metric specification
          dynamic "customized_load_metric_specification" {
            for_each = metric_specification.value.customized_load_metric_specification != null ? [metric_specification.value.customized_load_metric_specification] : []
            content {
              dynamic "metric_data_queries" {
                for_each = customized_load_metric_specification.value.metric_data_queries
                content {
                  id          = metric_data_queries.value.id
                  expression  = metric_data_queries.value.expression
                  label       = metric_data_queries.value.label
                  return_data = metric_data_queries.value.return_data

                  dynamic "metric_stat" {
                    for_each = metric_data_queries.value.metric_stat != null ? [metric_data_queries.value.metric_stat] : []
                    content {
                      stat = metric_stat.value.stat
                      unit = metric_stat.value.unit

                      metric {
                        metric_name = metric_stat.value.metric.metric_name
                        namespace   = metric_stat.value.metric.namespace

                        dynamic "dimensions" {
                          for_each = metric_stat.value.metric.dimensions != null ? metric_stat.value.metric.dimensions : []
                          content {
                            name  = dimensions.value.name
                            value = dimensions.value.value
                          }
                        }
                      }
                    }
                  }
                }
              }
            }
          }

          # Customized scaling metric specification
          dynamic "customized_scaling_metric_specification" {
            for_each = metric_specification.value.customized_scaling_metric_specification != null ? [metric_specification.value.customized_scaling_metric_specification] : []
            content {
              dynamic "metric_data_queries" {
                for_each = customized_scaling_metric_specification.value.metric_data_queries
                content {
                  id          = metric_data_queries.value.id
                  expression  = metric_data_queries.value.expression
                  label       = metric_data_queries.value.label
                  return_data = metric_data_queries.value.return_data

                  dynamic "metric_stat" {
                    for_each = metric_data_queries.value.metric_stat != null ? [metric_data_queries.value.metric_stat] : []
                    content {
                      stat = metric_stat.value.stat
                      unit = metric_stat.value.unit

                      metric {
                        metric_name = metric_stat.value.metric.metric_name
                        namespace   = metric_stat.value.metric.namespace

                        dynamic "dimensions" {
                          for_each = metric_stat.value.metric.dimensions != null ? metric_stat.value.metric.dimensions : []
                          content {
                            name  = dimensions.value.name
                            value = dimensions.value.value
                          }
                        }
                      }
                    }
                  }
                }
              }
            }
          }

          # Customized capacity metric specification
          dynamic "customized_capacity_metric_specification" {
            for_each = metric_specification.value.customized_capacity_metric_specification != null ? [metric_specification.value.customized_capacity_metric_specification] : []
            content {
              dynamic "metric_data_queries" {
                for_each = customized_capacity_metric_specification.value.metric_data_queries
                content {
                  id          = metric_data_queries.value.id
                  expression  = metric_data_queries.value.expression
                  label       = metric_data_queries.value.label
                  return_data = metric_data_queries.value.return_data

                  dynamic "metric_stat" {
                    for_each = metric_data_queries.value.metric_stat != null ? [metric_data_queries.value.metric_stat] : []
                    content {
                      stat = metric_stat.value.stat
                      unit = metric_stat.value.unit

                      metric {
                        metric_name = metric_stat.value.metric.metric_name
                        namespace   = metric_stat.value.metric.namespace

                        dynamic "dimensions" {
                          for_each = metric_stat.value.metric.dimensions != null ? metric_stat.value.metric.dimensions : []
                          content {
                            name  = dimensions.value.name
                            value = dimensions.value.value
                          }
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
