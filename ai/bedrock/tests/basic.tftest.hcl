# Amazon Bedrock module tests — run from module root: tofu test

mock_provider "aws" {
  override_data {
    target = data.aws_caller_identity.current
    values = {
      account_id = "123456789012"
    }
  }

  override_data {
    target = data.aws_partition.current
    values = {
      partition = "aws"
    }
  }

  override_data {
    target = data.aws_region.current
    values = {
      region = "us-west-2"
    }
  }

  override_resource {
    target = aws_cloudwatch_log_group.model_invocations
    values = {
      arn = "arn:aws:logs:us-west-2:123456789012:log-group:/aws/bedrock/model-invocations/ravion-prod"
    }
  }

  override_resource {
    target = aws_iam_role.model_invocation_logging
    values = {
      arn = "arn:aws:iam::123456789012:role/ravion-prod-bedrock-invocation-logging"
    }
  }

}

variables {
  name   = "ravion-prod"
  region = "us-west-2"
}

################################################################################
# Defaults
################################################################################

run "cloudwatch_text_logging_defaults" {
  command = plan

  assert {
    condition     = aws_cloudwatch_log_group.model_invocations[0].name == "/aws/bedrock/model-invocations/ravion-prod"
    error_message = "The default log group name should include the module name"
  }

  assert {
    condition     = aws_cloudwatch_log_group.model_invocations[0].retention_in_days == 90
    error_message = "Invocation logs should be retained for 90 days by default"
  }

  assert {
    condition     = aws_bedrock_model_invocation_logging_configuration.this[0].logging_config[0].text_data_delivery_enabled
    error_message = "Text invocation logging should be enabled by default"
  }

  assert {
    condition = (
      !aws_bedrock_model_invocation_logging_configuration.this[0].logging_config[0].image_data_delivery_enabled &&
      !aws_bedrock_model_invocation_logging_configuration.this[0].logging_config[0].embedding_data_delivery_enabled &&
      !aws_bedrock_model_invocation_logging_configuration.this[0].logging_config[0].video_data_delivery_enabled
    )
    error_message = "Non-text invocation logging should be disabled by default"
  }

  assert {
    condition = (
      aws_bedrock_model_invocation_logging_configuration.this[0].logging_config[0].cloudwatch_config[0].log_group_name ==
      aws_cloudwatch_log_group.model_invocations[0].name
    )
    error_message = "Bedrock should deliver logs to the module-managed log group"
  }

  assert {
    condition = (
      aws_bedrock_model_invocation_logging_configuration.this[0].logging_config[0].cloudwatch_config[0].role_arn ==
      aws_iam_role.model_invocation_logging[0].arn
    )
    error_message = "Bedrock should use the module-managed IAM role for log delivery"
  }
}

################################################################################
# IAM
################################################################################

run "bedrock_role_is_scoped_to_account_and_region" {
  command = plan

  assert {
    condition = (
      jsondecode(aws_iam_role.model_invocation_logging[0].assume_role_policy).Statement[0].Principal.Service ==
      "bedrock.amazonaws.com"
    )
    error_message = "Only the Bedrock service should be able to assume the logging role"
  }

  assert {
    condition = (
      jsondecode(aws_iam_role.model_invocation_logging[0].assume_role_policy).Statement[0].Condition.StringEquals["aws:SourceAccount"] ==
      "123456789012"
    )
    error_message = "The logging role trust policy should be scoped to the current AWS account"
  }

  assert {
    condition = (
      jsondecode(aws_iam_role.model_invocation_logging[0].assume_role_policy).Statement[0].Condition.ArnLike["aws:SourceArn"] ==
      "arn:aws:bedrock:us-west-2:123456789012:*"
    )
    error_message = "The logging role trust policy should be scoped to Bedrock in the configured region"
  }

  assert {
    condition = (
      jsondecode(aws_iam_role_policy.model_invocation_logging[0].policy).Statement[0].Resource ==
      "arn:aws:logs:us-west-2:123456789012:log-group:/aws/bedrock/model-invocations/ravion-prod:log-stream:aws/bedrock/modelinvocations"
    )
    error_message = "The logging role policy should only allow writes to the Bedrock invocation log stream"
  }
}

################################################################################
# Customization
################################################################################

run "custom_log_group_and_modalities" {
  command = plan

  variables {
    log_group_name                  = "/custom/bedrock/invocations"
    log_group_retention_days        = 365
    text_data_delivery_enabled      = false
    image_data_delivery_enabled     = true
    embedding_data_delivery_enabled = true
    tags = {
      Environment = "production"
    }
  }

  assert {
    condition     = aws_cloudwatch_log_group.model_invocations[0].name == "/custom/bedrock/invocations"
    error_message = "The custom CloudWatch log group name should be used"
  }

  assert {
    condition     = aws_cloudwatch_log_group.model_invocations[0].retention_in_days == 365
    error_message = "The custom CloudWatch retention should be used"
  }

  assert {
    condition     = aws_cloudwatch_log_group.model_invocations[0].tags["Environment"] == "production"
    error_message = "User tags should be merged into the CloudWatch log group tags"
  }
}

################################################################################
# Validation
################################################################################

run "all_delivery_types_disabled_rejected" {
  command = plan

  variables {
    text_data_delivery_enabled      = false
    image_data_delivery_enabled     = false
    embedding_data_delivery_enabled = false
    video_data_delivery_enabled     = false
  }

  expect_failures = [
    aws_bedrock_model_invocation_logging_configuration.this[0],
  ]
}

run "model_invocation_logging_can_be_disabled" {
  command = plan

  variables {
    model_invocation_logging_enabled = false
  }

  assert {
    condition = (
      length(aws_bedrock_model_invocation_logging_configuration.this) == 0 &&
      length(aws_cloudwatch_log_group.model_invocations) == 0 &&
      length(aws_iam_role.model_invocation_logging) == 0
    )
    error_message = "Disabling model invocation logging should omit its Bedrock, CloudWatch, and IAM resources"
  }

  assert {
    condition = (
      output.model_invocation_logging_configuration_id == null &&
      output.model_invocation_log_group_name == null &&
      output.model_invocation_log_group_arn == null &&
      output.model_invocation_logging_role_arn == null
    )
    error_message = "Model invocation logging outputs should be null when the section is disabled"
  }
}

run "unsupported_retention_rejected" {
  command = plan

  variables {
    log_group_retention_days = 2
  }

  expect_failures = [
    var.log_group_retention_days,
  ]
}
