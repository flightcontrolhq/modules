mock_provider "aws" {
  override_data {
    target = data.aws_caller_identity.current
    values = {
      account_id = "123456789012"
    }
  }

  override_data {
    target = data.aws_region.current
    values = {
      id   = "us-east-1"
      name = "us-east-1"
    }
  }

  override_data {
    target = data.aws_partition.current
    values = {
      partition = "aws"
    }
  }

  override_data {
    target = data.aws_iam_policy_document.dlm
    values = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }

  override_resource {
    target = aws_iam_role.dlm
    values = {
      arn = "arn:aws:iam::123456789012:role/backup-test-dlm"
      id  = "backup-test-dlm"
    }
  }

  override_resource {
    target = aws_iam_instance_profile.instance
    values = {
      arn = "arn:aws:iam::123456789012:instance-profile/supervised-app-instance"
    }
  }

  override_resource {
    target = module.instance_security_group.aws_security_group.this
    values = {
      id = "sg-12345678"
    }
  }

  override_resource {
    target = aws_launch_template.app
    values = {
      id = "lt-12345678"
    }
  }

  override_resource {
    target = aws_ssm_document.backup_dump
    values = {
      arn = "arn:aws:ssm:us-east-1:123456789012:document/backup-test-backup"
    }
  }

  override_resource {
    target = aws_ssm_document.backup_termination
    values = {
      arn = "arn:aws:ssm:us-east-1:123456789012:automation-definition/backup-test-backup-termination"
    }
  }

  override_resource {
    target = aws_iam_role.backup_eventbridge
    values = {
      arn = "arn:aws:iam::123456789012:role/backup-test-events"
      id  = "backup-test-events"
    }
  }

  override_resource {
    target = aws_iam_role.backup_termination_automation
    values = {
      arn = "arn:aws:iam::123456789012:role/backup-test-automation"
      id  = "backup-test-automation"
    }
  }
}

variables {
  name          = "backup-test"
  region        = "us-east-1"
  vpc_id        = "vpc-12345678"
  subnet_ids    = ["subnet-12345678"]
  instance_type = "t3.micro"
  ami_id        = "ami-12345678"
  runtime       = "container"
}

run "backups_are_absent_when_disabled" {
  command = plan

  assert {
    condition     = length(aws_dlm_lifecycle_policy.service) == 0
    error_message = "Backups disabled must not create a DLM policy."
  }

  assert {
    condition     = length(aws_iam_role.dlm) == 0
    error_message = "Backups disabled must not create a DLM role."
  }

  assert {
    condition     = length(aws_ssm_document.backup) == 0
    error_message = "Backups disabled must not create a consistency document."
  }
}

run "backups_with_data_volume_use_scripts_and_exclude_boot" {
  command = plan

  variables {
    backup_enabled               = true
    data_volume_creation_enabled = true
  }

  assert {
    condition     = length(aws_dlm_lifecycle_policy.service) == 1
    error_message = "Enabled backups must create a DLM policy."
  }

  assert {
    condition     = length(aws_iam_role.dlm) == 1
    error_message = "Enabled backups must create a DLM role."
  }

  assert {
    condition     = length(aws_ssm_document.backup) == 1
    error_message = "Filesystem-freeze backups with a data volume must create a consistency document."
  }

  assert {
    condition     = length(aws_dlm_lifecycle_policy.service[0].policy_details[0].schedule[0].create_rule[0].scripts) == 1
    error_message = "Filesystem-freeze backups must wire DLM pre/post scripts."
  }

  assert {
    condition     = aws_dlm_lifecycle_policy.service[0].policy_details[0].parameters[0].exclude_boot_volume == true
    error_message = "Data-volume backups must exclude the boot volume by default."
  }
}

run "backups_without_data_volume_include_root_without_freeze_scripts" {
  command = plan

  variables {
    backup_enabled = true
  }

  assert {
    condition     = length(aws_dlm_lifecycle_policy.service) == 1
    error_message = "Enabled backups must create a DLM policy without a data volume."
  }

  assert {
    condition     = length(aws_ssm_document.backup) == 0
    error_message = "Backups without a data volume must not create freeze scripts."
  }

  assert {
    condition     = length(aws_dlm_lifecycle_policy.service[0].policy_details[0].parameters) == 0
    error_message = "Backups without a data volume must include the root volume."
  }
}

run "restore_preserves_configured_volume_settings" {
  command = plan

  variables {
    data_volume_creation_enabled = true
    data_volume_size             = 100
    data_volume_type             = "gp3"
    data_volume_snapshot_id      = "snap-12345678"
  }

  assert {
    condition     = aws_launch_template.app.block_device_mappings[1].ebs[0].snapshot_id == "snap-12345678"
    error_message = "The restore snapshot ID must reach the data-volume mapping."
  }

  assert {
    condition     = aws_launch_template.app.block_device_mappings[1].ebs[0].volume_size == 100
    error_message = "The configured data-volume size must be preserved for restores."
  }

  assert {
    condition     = aws_launch_template.app.block_device_mappings[1].ebs[0].volume_type == "gp3"
    error_message = "The configured data-volume type must be preserved for restores."
  }
}

run "filesystem_freeze_requires_data_volume" {
  command = plan

  variables {
    backup_enabled          = true
    backup_consistency_mode = "filesystem_freeze"
  }

  expect_failures = [aws_launch_template.app]
}

run "logical_dumps_are_absent_when_disabled" {
  command = plan

  assert {
    condition     = length(aws_s3_bucket.dump) == 0
    error_message = "Logical dumps disabled must not create a dump bucket."
  }

  assert {
    condition     = length(aws_ssm_document.backup_dump) == 0
    error_message = "Logical dumps disabled must not create a dump SSM document."
  }

  assert {
    condition     = length(aws_cloudwatch_event_rule.backup_termination) == 0
    error_message = "Logical dumps disabled must not create termination automation."
  }

  assert {
    condition     = length(aws_cloudwatch_metric_alarm.backup_dump_failure) == 0
    error_message = "Logical dumps disabled must not create a freshness alarm."
  }
}

run "logical_dumps_create_s3_resources_and_wiring" {
  command = plan

  variables {
    backup_dump_enabled            = true
    backup_dump_command            = "sqlite3 /data/app.db '.backup \"$RAVION_BACKUP_DIR/app.db\"'"
    backup_dump_schedule           = "hourly"
    backup_dump_max_interval_hours = 6
    data_volume_creation_enabled   = true
  }

  assert {
    condition     = length(aws_s3_bucket.dump) == 1
    error_message = "Logical dumps should create a module-managed S3 bucket by default."
  }

  assert {
    condition     = aws_s3_bucket_versioning.dump[0].versioning_configuration[0].status == "Enabled"
    error_message = "Logical dump buckets must enable versioning."
  }

  assert {
    condition     = one(aws_s3_bucket_server_side_encryption_configuration.dump[0].rule).apply_server_side_encryption_by_default[0].sse_algorithm == "AES256"
    error_message = "Logical dump buckets must enable server-side encryption."
  }

  assert {
    condition     = aws_s3_bucket_public_access_block.dump[0].block_public_acls
    error_message = "Logical dump buckets must block public access."
  }

  assert {
    condition     = length(aws_s3_bucket_lifecycle_configuration.dump[0].rule) == 1
    error_message = "Logical dump buckets must configure retention expiry."
  }

  assert {
    condition     = length(aws_ssm_document.backup_dump) == 1 && length(aws_cloudwatch_metric_alarm.backup_dump_failure) == 1
    error_message = "Logical dumps must create the one-click document and freshness alarm."
  }

  assert {
    condition     = aws_s3_bucket.dump[0].force_destroy == false
    error_message = "Logical dump buckets must not be force-deleted by default."
  }

  assert {
    condition     = contains([for rule in aws_s3_bucket_lifecycle_configuration.dump[0].rule : rule.noncurrent_version_expiration[0].noncurrent_days], 30)
    error_message = "Logical dump buckets must expire noncurrent versions."
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.backup_dump_failure[0].period == 21600 && aws_cloudwatch_metric_alarm.backup_dump_failure[0].evaluation_periods == 1
    error_message = "The dump freshness alarm window must follow the configured maximum interval."
  }

  assert {
    condition     = strcontains(aws_cloudwatch_event_target.backup_termination[0].arn, "automation-definition/")
    error_message = "Termination EventBridge targets must use the SSM Automation ARN form."
  }

  assert {
    condition     = strcontains(base64decode(aws_launch_template.app.user_data), "fresh service and continuing without restore") && strcontains(base64decode(aws_launch_template.app.user_data), "/backup.log")
    error_message = "Bootstrap must allow a fresh restore-enabled service and configure backup log collection."
  }

}

run "logical_dumps_use_supplied_s3_bucket" {
  command = plan

  variables {
    backup_dump_enabled          = true
    backup_dump_command          = "sqlite3 /data/app.db '.backup \"$RAVION_BACKUP_DIR/app.db\"'"
    backup_dump_s3_bucket_arn    = "arn:aws:s3:::existing-backup-bucket"
    data_volume_creation_enabled = true
  }

  assert {
    condition     = length(aws_s3_bucket.dump) == 0
    error_message = "A supplied S3 bucket ARN must prevent module bucket creation."
  }

  assert {
    condition     = output.backup_dump_bucket_arn == "arn:aws:s3:::existing-backup-bucket"
    error_message = "The effective dump bucket ARN must use the supplied bucket."
  }

  assert {
    condition     = strcontains(base64decode(aws_launch_template.app.user_data), "prune_s3_backups")
    error_message = "Supplied S3 buckets must receive module-side retention pruning."
  }
}

run "logical_dumps_support_efs_destination" {
  command = plan

  variables {
    backup_dump_enabled          = true
    backup_dump_command          = "sqlite3 /data/app.db '.backup \"$RAVION_BACKUP_DIR/app.db\"'"
    backup_dump_destination      = "efs"
    data_volume_creation_enabled = true
    efs_enabled                  = true
    efs_file_system_id           = "fs-12345678"
    efs_client_security_group_id = "sg-12345678"
  }

  assert {
    condition     = length(aws_s3_bucket.dump) == 0
    error_message = "EFS logical dumps must not create an S3 bucket."
  }

  assert {
    condition     = strcontains(base64decode(aws_launch_template.app.user_data), "EFS_ROOT")
    error_message = "EFS logical dumps must configure the shared EFS staging root."
  }
}

run "restore_on_first_boot_requires_restore_command" {
  command = plan

  variables {
    backup_dump_enabled                       = true
    backup_dump_command                       = "sqlite3 /data/app.db '.backup \"$RAVION_BACKUP_DIR/app.db\"'"
    backup_dump_restore_on_first_boot_enabled = true
    data_volume_creation_enabled              = true
  }

  expect_failures = [aws_launch_template.app]
}

run "replication_is_absent_when_disabled" {
  command = plan

  assert {
    condition     = length(aws_s3_bucket.dump) == 0
    error_message = "Replication disabled must not create a replication bucket."
  }

  assert {
    condition     = !strcontains(base64decode(aws_launch_template.app.user_data), "litestream replicate")
    error_message = "Replication disabled must not install a Litestream supervisor program."
  }
}

run "replication_creates_s3_bucket_when_dumps_are_disabled" {
  command = plan

  variables {
    backup_replication_enabled           = true
    backup_replication_database_path     = "/data/app.db"
    data_volume_creation_enabled         = true
    backup_replication_snapshot_interval = "1s"
  }

  assert {
    condition     = length(aws_s3_bucket.dump) == 1
    error_message = "Replication must create an S3 bucket when dumps are disabled."
  }

  assert {
    condition     = strcontains(base64decode(aws_launch_template.app.user_data), "litestream replicate") && strcontains(base64decode(aws_launch_template.app.user_data), "/data/app.db")
    error_message = "Replication bootstrap must configure and supervise Litestream."
  }
}

run "replication_reuses_supplied_s3_bucket" {
  command = plan

  variables {
    backup_replication_enabled       = true
    backup_replication_database_path = "/data/app.db"
    backup_replication_s3_bucket_arn = "arn:aws:s3:::existing-replication-bucket"
    data_volume_creation_enabled     = true
  }

  assert {
    condition     = length(aws_s3_bucket.dump) == 0
    error_message = "A supplied replication bucket ARN must prevent module bucket creation."
  }

  assert {
    condition     = output.backup_replication_bucket_arn == "arn:aws:s3:::existing-replication-bucket"
    error_message = "Replication must use the supplied S3 bucket."
  }
}

run "replication_bucket_wins_when_dumps_use_efs" {
  command = plan

  variables {
    backup_dump_enabled              = true
    backup_dump_command              = "sqlite3 /data/app.db '.backup \"$RAVION_BACKUP_DIR/app.db\"'"
    backup_dump_destination          = "efs"
    backup_dump_s3_bucket_arn        = "arn:aws:s3:::existing-backup-bucket"
    backup_replication_enabled       = true
    backup_replication_database_path = "/data/app.db"
    backup_replication_s3_bucket_arn = "arn:aws:s3:::existing-replication-bucket"
    data_volume_creation_enabled     = true
    efs_enabled                      = true
    efs_file_system_id               = "fs-12345678"
    efs_client_security_group_id     = "sg-12345678"
  }

  assert {
    condition     = output.backup_replication_bucket_arn == "arn:aws:s3:::existing-replication-bucket"
    error_message = "Replication must use its supplied bucket when dumps use EFS."
  }

  assert {
    condition     = output.backup_replication_prefix == "replication/backup-test"
    error_message = "Replication must retain its dedicated S3 prefix when dumps use EFS."
  }
}

run "replication_requires_database_on_data_volume" {
  command = plan

  variables {
    backup_replication_enabled       = true
    backup_replication_database_path = "/var/lib/app.db"
    data_volume_creation_enabled     = true
  }

  expect_failures = [aws_launch_template.app]
}
