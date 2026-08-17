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
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Sid\":\"CopyEncryptedSnapshots\",\"Effect\":\"Allow\",\"Action\":[\"kms:Decrypt\",\"kms:DescribeKey\",\"kms:Encrypt\",\"kms:GenerateDataKey\",\"kms:GenerateDataKeyWithoutPlaintext\",\"kms:ReEncryptFrom\",\"kms:ReEncryptTo\"],\"Resource\":\"*\",\"Condition\":{\"StringEquals\":{\"kms:ViaService\":[\"ec2.us-east-1.amazonaws.com\",\"ec2.us-west-2.amazonaws.com\"]}}},{\"Sid\":\"CreateEncryptedSnapshotCopyGrant\",\"Effect\":\"Allow\",\"Action\":\"kms:CreateGrant\",\"Resource\":\"*\",\"Condition\":{\"StringEquals\":{\"kms:ViaService\":[\"ec2.us-east-1.amazonaws.com\",\"ec2.us-west-2.amazonaws.com\"]},\"Bool\":{\"kms:GrantIsForAWSResource\":\"true\"}}}]}"
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

run "cross_region_encrypted_copy_restricts_kms_conditions" {
  command = plan

  variables {
    backup_enabled                       = true
    backup_cross_region_copy_destination = "us-west-2"
  }

  assert {
    condition = anytrue([
      for statement in jsondecode(aws_iam_role_policy.dlm[0].policy).Statement :
      statement.Sid == "CopyEncryptedSnapshots" &&
      statement.Condition.StringEquals["kms:ViaService"] == [
        "ec2.us-east-1.amazonaws.com",
        "ec2.us-west-2.amazonaws.com",
      ]
    ])
    error_message = "Encrypted snapshot copy permissions must be limited to EC2 in the source and destination regions."
  }

  assert {
    condition = anytrue([
      for statement in jsondecode(aws_iam_role_policy.dlm[0].policy).Statement :
      statement.Sid == "CreateEncryptedSnapshotCopyGrant" &&
      statement.Condition.StringEquals["kms:ViaService"] == [
        "ec2.us-east-1.amazonaws.com",
        "ec2.us-west-2.amazonaws.com",
      ] &&
      statement.Condition.Bool["kms:GrantIsForAWSResource"] == "true"
    ])
    error_message = "Encrypted snapshot copy grants must require AWS resources and both EC2 regions."
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
