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
