################################################################################
# Bedrock Log Delivery Role
################################################################################

resource "aws_iam_role" "model_invocation_logging" {
  name = "${var.name}-bedrock-invocation-logging"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "bedrock.amazonaws.com"
        }
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
          ArnLike = {
            "aws:SourceArn" = "arn:${data.aws_partition.current.partition}:bedrock:${local.region}:${data.aws_caller_identity.current.account_id}:*"
          }
        }
      }
    ]
  })

  tags = merge(local.tags, {
    Name = "${var.name}-bedrock-invocation-logging"
  })
}

resource "aws_iam_role_policy" "model_invocation_logging" {
  name = "${var.name}-bedrock-invocation-logging"
  role = aws_iam_role.model_invocation_logging.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents",
        ]
        Effect   = "Allow"
        Resource = "${aws_cloudwatch_log_group.model_invocations.arn}:log-stream:aws/bedrock/modelinvocations"
      }
    ]
  })
}
