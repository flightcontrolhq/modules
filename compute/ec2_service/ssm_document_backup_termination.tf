################################################################################
# Termination-time logical dump Automation
################################################################################

resource "aws_iam_role" "backup_termination_automation" {
  count = local.backup_dump_termination_enabled ? 1 : 0
  name  = "${var.name}-backup-automation"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "ssm.amazonaws.com" }
    }]
  })

  tags = local.tags
}

resource "aws_iam_role_policy" "backup_termination_automation" {
  count = local.backup_dump_termination_enabled ? 1 : 0
  name  = "${var.name}-backup-automation"
  role  = aws_iam_role.backup_termination_automation[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "ssm:SendCommand"
        Resource = aws_ssm_document.backup_dump[0].arn
      },
      {
        Effect   = "Allow"
        Action   = "ssm:SendCommand"
        Resource = "arn:${data.aws_partition.current.partition}:ec2:*:${data.aws_caller_identity.current.account_id}:instance/*"
      },
      {
        Effect   = "Allow"
        Action   = "autoscaling:CompleteLifecycleAction"
        Resource = module.autoscaling.autoscaling_group_arn
      },
    ]
  })
}

resource "aws_ssm_document" "backup_termination" {
  count           = local.backup_dump_termination_enabled ? 1 : 0
  name            = "${var.name}-backup-termination"
  document_type   = "Automation"
  document_format = "YAML"

  content = yamlencode({
    schemaVersion = "0.3"
    description   = "Run a final logical dump before continuing EC2 service instance termination."
    assumeRole    = aws_iam_role.backup_termination_automation[0].arn
    parameters = {
      InstanceId = {
        type = "String"
      }
      AutoScalingGroupName = {
        type = "String"
      }
      LifecycleHookName = {
        type = "String"
      }
      LifecycleActionToken = {
        type = "String"
      }
    }
    mainSteps = [
      {
        name           = "runDump"
        action         = "aws:runCommand"
        timeoutSeconds = 1500
        onFailure      = "step:completeLifecycleAction"
        inputs = {
          DocumentName = aws_ssm_document.backup_dump[0].name
          InstanceIds  = ["{{ InstanceId }}"]
          Parameters = {
            command = ["backup-now"]
          }
        }
      },
      {
        name   = "completeLifecycleAction"
        action = "aws:executeAwsApi"
        inputs = {
          Service               = "autoscaling"
          Api                   = "CompleteLifecycleAction"
          AutoScalingGroupName  = "{{ AutoScalingGroupName }}"
          LifecycleHookName     = "{{ LifecycleHookName }}"
          LifecycleActionToken  = "{{ LifecycleActionToken }}"
          LifecycleActionResult = "CONTINUE"
        }
        isEnd = true
      },
    ]
  })

  tags = local.tags
}

resource "aws_iam_role" "backup_eventbridge" {
  count = local.backup_dump_termination_enabled ? 1 : 0
  name  = "${var.name}-backup-events"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "events.amazonaws.com" }
    }]
  })

  tags = local.tags
}

resource "aws_iam_role_policy" "backup_eventbridge" {
  count = local.backup_dump_termination_enabled ? 1 : 0
  name  = "${var.name}-backup-events"
  role  = aws_iam_role.backup_eventbridge[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "iam:PassRole",
      ]
      Resource = aws_iam_role.backup_termination_automation[0].arn
      }, {
      Effect   = "Allow"
      Action   = "ssm:StartAutomationExecution"
      Resource = local.backup_dump_termination_automation_arn
    }]
  })
}

resource "aws_cloudwatch_event_rule" "backup_termination" {
  count = local.backup_dump_termination_enabled ? 1 : 0

  name        = "${var.name}-backup-termination"
  description = "Run the ${var.name} logical dump before its backup lifecycle hook continues."

  event_pattern = jsonencode({
    source      = ["aws.autoscaling"]
    detail-type = ["EC2 Instance-terminate Lifecycle Action"]
    detail = {
      AutoScalingGroupName = [module.autoscaling.autoscaling_group_name]
      LifecycleHookName    = ["ravion-backup-terminate"]
    }
  })
}

resource "aws_cloudwatch_event_target" "backup_termination" {
  count = local.backup_dump_termination_enabled ? 1 : 0

  rule     = aws_cloudwatch_event_rule.backup_termination[0].name
  arn      = local.backup_dump_termination_automation_arn
  role_arn = aws_iam_role.backup_eventbridge[0].arn

  input_transformer {
    input_paths = {
      instance_id            = "$.detail.EC2InstanceId"
      autoscaling_group_name = "$.detail.AutoScalingGroupName"
      lifecycle_hook_name    = "$.detail.LifecycleHookName"
      lifecycle_action_token = "$.detail.LifecycleActionToken"
    }
    input_template = <<-EOF
      {"InstanceId":"<instance_id>","AutoScalingGroupName":"<autoscaling_group_name>","LifecycleHookName":"<lifecycle_hook_name>","LifecycleActionToken":"<lifecycle_action_token>"}
    EOF
  }
}
