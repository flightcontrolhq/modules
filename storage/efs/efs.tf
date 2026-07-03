################################################################################
# File System
################################################################################

resource "aws_efs_file_system" "this" {
  creation_token = var.name

  encrypted  = var.encrypted
  kms_key_id = var.kms_key_id

  performance_mode                = var.performance_mode
  throughput_mode                 = var.throughput_mode
  provisioned_throughput_in_mibps = var.throughput_mode == "provisioned" ? var.provisioned_throughput_in_mibps : null

  dynamic "lifecycle_policy" {
    for_each = var.transition_to_ia != null ? [var.transition_to_ia] : []
    content {
      transition_to_ia = lifecycle_policy.value
    }
  }

  dynamic "lifecycle_policy" {
    for_each = var.transition_to_archive != null ? [var.transition_to_archive] : []
    content {
      transition_to_archive = lifecycle_policy.value
    }
  }

  dynamic "lifecycle_policy" {
    for_each = var.transition_to_primary_storage_class != null ? [var.transition_to_primary_storage_class] : []
    content {
      transition_to_primary_storage_class = lifecycle_policy.value
    }
  }

  tags = merge(local.tags, {
    Name = var.name
  })
}

################################################################################
# Backup Policy
################################################################################

resource "aws_efs_backup_policy" "this" {
  file_system_id = aws_efs_file_system.this.id

  backup_policy {
    status = var.backup_enabled ? "ENABLED" : "DISABLED"
  }
}

################################################################################
# Mount Targets
################################################################################

resource "aws_efs_mount_target" "this" {
  for_each = toset(var.subnet_ids)

  file_system_id  = aws_efs_file_system.this.id
  subnet_id       = each.value
  security_groups = [module.security_group.security_group_id]
}

################################################################################
# Access Point
################################################################################

resource "aws_efs_access_point" "this" {
  count = local.create_access_point ? 1 : 0

  file_system_id = aws_efs_file_system.this.id

  posix_user {
    uid = var.access_point_posix_uid
    gid = var.access_point_posix_gid
  }

  root_directory {
    path = var.access_point_root_directory_path

    dynamic "creation_info" {
      for_each = local.access_point_creation_info_enabled ? [1] : []
      content {
        owner_uid   = var.access_point_posix_uid
        owner_gid   = var.access_point_posix_gid
        permissions = var.access_point_permissions
      }
    }
  }

  tags = merge(local.tags, {
    Name = var.name
  })
}
