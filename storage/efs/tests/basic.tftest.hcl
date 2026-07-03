################################################################################
# EFS Module Unit Tests
################################################################################

# Mock AWS provider with overridden data sources
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
    target = data.aws_vpc.this
    values = {
      cidr_block = "10.0.0.0/16"
    }
  }
}

# The mount-target security group references the client security group ID,
# which must satisfy the sg- validation in the security-groups module.
override_module {
  target = module.client_security_group
  outputs = {
    security_group_id  = "sg-1111aaaa"
    security_group_arn = "arn:aws:ec2:us-east-1:123456789012:security-group/sg-1111aaaa"
  }
}

variables {
  name       = "test-efs"
  vpc_id     = "vpc-12345678"
  subnet_ids = ["subnet-aaaa1111", "subnet-bbbb2222"]
}

#-------------------------------------------------------------------------------
# Defaults
#-------------------------------------------------------------------------------

run "test_defaults" {
  command = plan

  assert {
    condition     = aws_efs_file_system.this.encrypted == true
    error_message = "The file system should be encrypted by default."
  }

  assert {
    condition     = aws_efs_file_system.this.performance_mode == "generalPurpose"
    error_message = "The performance mode should default to generalPurpose."
  }

  assert {
    condition     = aws_efs_file_system.this.throughput_mode == "bursting"
    error_message = "The throughput mode should default to bursting."
  }

  assert {
    condition     = length(aws_efs_file_system.this.lifecycle_policy) == 0
    error_message = "No lifecycle policies should be created by default."
  }

  assert {
    condition     = aws_efs_backup_policy.this.backup_policy[0].status == "ENABLED"
    error_message = "Automatic backups should be enabled by default."
  }

  assert {
    condition     = length(aws_efs_mount_target.this) == 2
    error_message = "One mount target should be created per subnet."
  }

  assert {
    condition     = aws_efs_mount_target.this["subnet-aaaa1111"].subnet_id == "subnet-aaaa1111"
    error_message = "Each mount target should use its subnet ID."
  }

  assert {
    condition     = length(aws_efs_access_point.this) == 0
    error_message = "No access point should be created by default."
  }
}

#-------------------------------------------------------------------------------
# File system options
#-------------------------------------------------------------------------------

run "test_provisioned_throughput" {
  command = plan

  variables {
    throughput_mode                 = "provisioned"
    provisioned_throughput_in_mibps = 128
  }

  assert {
    condition     = aws_efs_file_system.this.provisioned_throughput_in_mibps == 128
    error_message = "Provisioned throughput should be set when throughput_mode is provisioned."
  }
}

run "test_lifecycle_policies" {
  command = plan

  variables {
    transition_to_ia                    = "AFTER_30_DAYS"
    transition_to_archive               = "AFTER_90_DAYS"
    transition_to_primary_storage_class = "AFTER_1_ACCESS"
  }

  assert {
    condition     = length(aws_efs_file_system.this.lifecycle_policy) == 3
    error_message = "All three lifecycle policies should be created."
  }
}

run "test_backup_disabled" {
  command = plan

  variables {
    backup_enabled = false
  }

  assert {
    condition     = aws_efs_backup_policy.this.backup_policy[0].status == "DISABLED"
    error_message = "The backup policy should be DISABLED when backups are turned off."
  }
}

#-------------------------------------------------------------------------------
# Access point
#-------------------------------------------------------------------------------

run "test_access_point_enabled" {
  command = plan

  variables {
    access_point_enabled             = true
    access_point_root_directory_path = "/app-data"
    access_point_posix_uid           = 1001
    access_point_posix_gid           = 1001
    access_point_permissions         = "750"
  }

  assert {
    condition     = length(aws_efs_access_point.this) == 1
    error_message = "An access point should be created when enabled."
  }

  assert {
    condition     = aws_efs_access_point.this[0].root_directory[0].path == "/app-data"
    error_message = "The access point should use the configured root directory path."
  }

  assert {
    condition     = aws_efs_access_point.this[0].posix_user[0].uid == 1001
    error_message = "The access point should use the configured POSIX UID."
  }

  assert {
    condition     = aws_efs_access_point.this[0].root_directory[0].creation_info[0].permissions == "750"
    error_message = "The access point root directory creation info should use the configured permissions."
  }
}

run "test_access_point_root_path_skips_creation_info" {
  command = plan

  variables {
    access_point_enabled             = true
    access_point_root_directory_path = "/"
  }

  assert {
    condition     = length(aws_efs_access_point.this[0].root_directory[0].creation_info) == 0
    error_message = "No creation info should be set when the access point root directory is /."
  }
}

#-------------------------------------------------------------------------------
# Validation failures
#-------------------------------------------------------------------------------

run "test_provisioned_throughput_required" {
  command = plan

  variables {
    throughput_mode = "provisioned"
  }

  expect_failures = [var.provisioned_throughput_in_mibps]
}

run "test_archive_requires_ia" {
  command = plan

  variables {
    transition_to_archive = "AFTER_90_DAYS"
  }

  expect_failures = [var.transition_to_archive]
}

run "test_invalid_name" {
  command = plan

  variables {
    name = "-invalid-name"
  }

  expect_failures = [var.name]
}

run "test_invalid_vpc_id" {
  command = plan

  variables {
    vpc_id = "not-a-vpc"
  }

  expect_failures = [var.vpc_id]
}

run "test_empty_subnets" {
  command = plan

  variables {
    subnet_ids = []
  }

  expect_failures = [var.subnet_ids]
}
