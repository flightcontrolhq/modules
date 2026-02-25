# Basic Lambda Module Tests
# Run with: tofu test

mock_provider "aws" {
  override_resource {
    target = aws_lambda_function.this
    values = {
      arn           = "arn:aws:lambda:us-east-1:123456789012:function:test-lambda"
      invoke_arn    = "arn:aws:apigateway:us-east-1:lambda:path/2015-03-31/functions/test-lambda/invocations"
      qualified_arn = "arn:aws:lambda:us-east-1:123456789012:function:test-lambda:1"
      version       = "1"
      last_modified = "2026-01-01T00:00:00.000+0000"
    }
  }

  override_resource {
    target = aws_cloudwatch_log_group.this
    values = {
      arn = "arn:aws:logs:us-east-1:123456789012:log-group:/aws/lambda/test-lambda"
    }
  }

  override_resource {
    target = aws_lambda_function_url.this
    values = {
      function_url = "https://example.lambda-url.us-east-1.on.aws/"
    }
  }

  override_resource {
    target = aws_lambda_alias.this
    values = {
      arn = "arn:aws:lambda:us-east-1:123456789012:function:test-lambda:live"
    }
  }
}

variables {
  name         = "test-lambda"
  package_type = "Zip"
  runtime      = "nodejs20.x"
  handler      = "index.handler"
  s3_bucket    = "artifact-bucket"
  s3_key       = "lambda.zip"
  create_role  = false
  role_arn     = "arn:aws:iam::123456789012:role/existing-lambda-role"
}

run "basic_zip_function" {
  command = plan

  assert {
    condition     = aws_lambda_function.this.function_name == "test-lambda"
    error_message = "Lambda function name should match input."
  }

  assert {
    condition     = aws_lambda_function.this.package_type == "Zip"
    error_message = "Package type should be Zip."
  }

  assert {
    condition     = length(aws_iam_role.this) == 0
    error_message = "IAM role should not be created when using an existing role."
  }

  assert {
    condition     = length(aws_cloudwatch_log_group.this) == 1
    error_message = "CloudWatch log group should be created by default."
  }
}

run "existing_role_no_create" {
  command = plan

  variables {
    create_role = false
    role_arn    = "arn:aws:iam::123456789012:role/existing-lambda-role-2"
  }

  assert {
    condition     = length(aws_iam_role.this) == 0
    error_message = "IAM role should not be created when create_role is false."
  }
}

run "function_url_enabled" {
  command = plan

  variables {
    function_url_enabled   = true
    function_url_auth_type = "AWS_IAM"
  }

  assert {
    condition     = length(aws_lambda_function_url.this) == 1
    error_message = "Function URL should be created when enabled."
  }

  assert {
    condition     = aws_lambda_function_url.this[0].authorization_type == "AWS_IAM"
    error_message = "Function URL auth type should match input."
  }
}

run "lambda_at_edge_valid_configuration" {
  command = plan

  variables {
    is_lambda_at_edge      = true
    publish                = true
    architectures          = ["x86_64"]
    timeout                = 30
    memory_size            = 128
    environment_variables  = {}
    vpc_config             = null
    layers                 = []
    file_system_configs    = []
    dead_letter_target_arn = null
  }

  assert {
    condition     = aws_lambda_function.this.publish == true
    error_message = "Edge mode configuration should publish versions."
  }
}

run "permissions_and_event_source_mappings" {
  command = plan

  variables {
    permissions = [
      {
        principal  = "events.amazonaws.com"
        source_arn = "arn:aws:events:us-east-1:123456789012:rule/test-rule"
      }
    ]

    event_source_mappings = [
      {
        event_source_arn = "arn:aws:sqs:us-east-1:123456789012:test-queue"
        batch_size       = 10
      }
    ]
  }

  assert {
    condition     = length(aws_lambda_permission.this) == 1
    error_message = "One lambda permission should be created."
  }

  assert {
    condition     = length(aws_lambda_event_source_mapping.this) == 1
    error_message = "One event source mapping should be created."
  }
}

run "aliases_created" {
  command = plan

  variables {
    publish = true
    aliases = {
      live = {
        function_version = "1"
      }
    }
  }

  assert {
    condition     = length(aws_lambda_alias.this) == 1
    error_message = "One alias should be created."
  }
}
