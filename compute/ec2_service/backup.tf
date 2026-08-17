resource "aws_dlm_lifecycle_policy" "service" {
  count              = var.backup_enabled ? 1 : 0
  description        = "Scheduled EBS backups for ${var.name}"
  execution_role_arn = aws_iam_role.dlm[0].arn
  state              = "ENABLED"

  policy_details {
    resource_types = ["INSTANCE"]

    schedule {
      name = "${var.name} snapshots"

      create_rule {
        interval      = var.backup_interval_hours
        interval_unit = "HOURS"
        times         = [var.backup_start_time]

        dynamic "scripts" {
          for_each = local.backup_scripts_enabled ? [1] : []
          content {
            execute_operation_on_script_failure = false
            execution_handler                   = aws_ssm_document.backup[0].name
            execution_handler_service           = "AWS_SYSTEMS_MANAGER"
            maximum_retry_count                 = 2
            stages                              = ["PRE", "POST"]
          }
        }
      }

      retain_rule {
        count = var.backup_retention_count
      }

      copy_tags = true

      dynamic "cross_region_copy_rule" {
        for_each = var.backup_cross_region_copy_destination != null ? [1] : []
        content {
          target    = var.backup_cross_region_copy_destination
          encrypted = true
          copy_tags = true
          retain_rule {
            interval      = var.backup_retention_count
            interval_unit = "DAYS"
          }
        }
      }
    }

    target_tags = local.backup_target_tag

    dynamic "parameters" {
      for_each = local.backup_root_volume_included ? [] : [1]
      content {
        exclude_boot_volume = true
      }
    }
  }
}
