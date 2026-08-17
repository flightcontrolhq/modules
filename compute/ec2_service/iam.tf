################################################################################
# IAM Role for Service Instances
################################################################################

resource "aws_iam_role" "instance" {
  name = "${var.name}-instance"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = local.tags
}

# SSM agent access: required for the SSM-based deploy documents and
# Session Manager shell access.
resource "aws_iam_role_policy_attachment" "instance_ssm" {
  role       = aws_iam_role.instance.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "instance" {
  name = "${var.name}-instance"
  role = aws_iam_role.instance.name

  tags = local.tags
}

################################################################################
# Instance Permissions
################################################################################

data "aws_iam_policy_document" "instance" {
  # SSM Run Command resolves the configured CloudWatch destination before
  # creating its per-command stdout/stderr streams. DescribeLogGroups does
  # not support resource-level permissions.
  statement {
    sid       = "DescribeAppLogGroups"
    actions   = ["logs:DescribeLogGroups"]
    resources = ["*"]
  }

  # App log shipping (Docker awslogs driver and CloudWatch agent)
  statement {
    sid = "AppLogs"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogStreams",
    ]
    resources = [
      aws_cloudwatch_log_group.app.arn,
      "${aws_cloudwatch_log_group.app.arn}:*",
    ]
  }

  # Container image pulls from the service ECR repository
  dynamic "statement" {
    for_each = local.container_runtime ? [1] : []
    content {
      sid       = "EcrAuth"
      actions   = ["ecr:GetAuthorizationToken"]
      resources = ["*"]
    }
  }

  # Manual deploy source checkout receives only the name of a temporary
  # SecureString. The credential itself is fetched on the instance and is
  # deleted by the deploy workflow after the command finishes.
  statement {
    sid = "GitDeployTokenRead"
    actions = [
      "ssm:GetParameter",
    ]
    resources = [
      "arn:${data.aws_partition.current.partition}:ssm:*:${data.aws_caller_identity.current.account_id}:parameter/ravion/git-tokens/ec2/*"
    ]
  }

  dynamic "statement" {
    for_each = local.container_runtime && var.ecr_repository_creation_enabled ? [1] : []
    content {
      sid = "EcrPull"
      actions = [
        "ecr:BatchGetImage",
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchCheckLayerAvailability",
      ]
      resources = [module.ecr[0].repository_arn]
    }
  }

  # Connection draining around in-place deploys
  dynamic "statement" {
    for_each = local.load_balancer_creation_enabled ? [1] : []
    content {
      sid = "TargetGroupDrain"
      actions = [
        "elasticloadbalancing:RegisterTargets",
        "elasticloadbalancing:DeregisterTargets",
      ]
      resources = [aws_lb_target_group.app[0].arn]
    }
  }

  dynamic "statement" {
    for_each = local.load_balancer_creation_enabled ? [1] : []
    content {
      sid       = "TargetGroupDescribe"
      actions   = ["elasticloadbalancing:DescribeTargetHealth"]
      resources = ["*"]
    }
  }

  # Secret env vars: the env-file builder fetches values on the instance.
  # Same-account grants matching the ECS execution role's secrets access
  # (compute/ecs_service/task_definition.tf).
  dynamic "statement" {
    for_each = length(var.secrets) > 0 ? [1] : []
    content {
      sid       = "SecretsManagerRead"
      actions   = ["secretsmanager:GetSecretValue"]
      resources = ["*"]
      condition {
        test     = "StringEquals"
        variable = "aws:ResourceAccount"
        values   = [data.aws_caller_identity.current.account_id]
      }
    }
  }

  dynamic "statement" {
    for_each = length(var.secrets) > 0 ? [1] : []
    content {
      sid = "SsmParameterRead"
      actions = [
        "ssm:GetParameter",
        "ssm:GetParameters",
      ]
      resources = [
        "arn:${data.aws_partition.current.partition}:ssm:*:${data.aws_caller_identity.current.account_id}:parameter/*"
      ]
    }
  }

  dynamic "statement" {
    for_each = length(var.secrets) > 0 ? [1] : []
    content {
      sid       = "SecretsKmsDecrypt"
      actions   = ["kms:Decrypt"]
      resources = ["*"]
      condition {
        test     = "StringEquals"
        variable = "aws:ResourceAccount"
        values   = [data.aws_caller_identity.current.account_id]
      }
    }
  }

  dynamic "statement" {
    for_each = var.backup_dump_enabled && var.backup_dump_destination == "s3" ? [1] : []
    content {
      sid = "LogicalDumpBucketList"
      actions = [
        "s3:ListBucket",
      ]
      resources = [local.backup_dump_bucket_arn]
      condition {
        test     = "StringLike"
        variable = "s3:prefix"
        values   = ["${local.backup_dump_artifact_prefix}/*"]
      }
    }
  }

  dynamic "statement" {
    for_each = var.backup_dump_enabled && var.backup_dump_destination == "s3" ? [1] : []
    content {
      sid = "LogicalDumpObjects"
      actions = [
        "s3:DeleteObject",
        "s3:GetObject",
        "s3:PutObject",
      ]
      resources = ["${local.backup_dump_bucket_arn}/${local.backup_dump_artifact_prefix}/*"]
    }
  }
}

resource "aws_iam_role_policy" "instance" {
  name   = "${var.name}-instance"
  role   = aws_iam_role.instance.id
  policy = data.aws_iam_policy_document.instance.json
}
