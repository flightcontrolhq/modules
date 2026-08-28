resource "aws_iam_role" "dlm" {
  count = var.backup_enabled ? 1 : 0
  name  = "${var.name}-dlm"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "dlm.amazonaws.com" }
    }]
  })

  tags = local.tags
}

data "aws_iam_policy_document" "dlm" {
  count = var.backup_enabled ? 1 : 0

  statement {
    sid = "SnapshotLifecycle"
    actions = [
      "ec2:CreateSnapshot",
      "ec2:CreateSnapshots",
      "ec2:DeleteSnapshot",
      "ec2:DescribeInstances",
      "ec2:DescribeVolumes",
      "ec2:DescribeSnapshots",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "TagSnapshots"
    actions   = ["ec2:CreateTags"]
    resources = ["arn:${data.aws_partition.current.partition}:ec2:*::snapshot/*"]
  }

  dynamic "statement" {
    for_each = var.backup_cross_region_copy_destination != null ? [1] : []
    content {
      sid = "CopySnapshots"
      actions = [
        "ec2:CopySnapshot",
        "ec2:ModifySnapshotAttribute",
      ]
      resources = ["*"]
    }
  }

  dynamic "statement" {
    for_each = var.backup_cross_region_copy_destination != null ? [1] : []
    content {
      sid = "CopyEncryptedSnapshots"
      actions = [
        "kms:Decrypt",
        "kms:DescribeKey",
        "kms:Encrypt",
        "kms:GenerateDataKey",
        "kms:GenerateDataKeyWithoutPlaintext",
        "kms:ReEncryptFrom",
        "kms:ReEncryptTo",
      ]
      resources = ["*"]
      condition {
        test     = "StringEquals"
        variable = "kms:ViaService"
        values = [
          "ec2.${local.region}.amazonaws.com",
          "ec2.${var.backup_cross_region_copy_destination}.amazonaws.com",
        ]
      }
    }
  }

  dynamic "statement" {
    for_each = var.backup_cross_region_copy_destination != null ? [1] : []
    content {
      sid       = "CreateEncryptedSnapshotCopyGrant"
      actions   = ["kms:CreateGrant"]
      resources = ["*"]
      condition {
        test     = "StringEquals"
        variable = "kms:ViaService"
        values = [
          "ec2.${local.region}.amazonaws.com",
          "ec2.${var.backup_cross_region_copy_destination}.amazonaws.com",
        ]
      }
      condition {
        test     = "Bool"
        variable = "kms:GrantIsForAWSResource"
        values   = ["true"]
      }
    }
  }
}

resource "aws_iam_role_policy" "dlm" {
  count  = var.backup_enabled ? 1 : 0
  name   = "${var.name}-dlm"
  role   = aws_iam_role.dlm[0].id
  policy = data.aws_iam_policy_document.dlm[0].json
}

resource "aws_iam_role_policy_attachment" "dlm_ssm" {
  count      = local.backup_scripts_enabled ? 1 : 0
  role       = aws_iam_role.dlm[0].name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AWSDataLifecycleManagerSSMFullAccess"
}
