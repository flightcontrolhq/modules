mock_provider "aws" {
  override_resource {
    target = aws_iam_policy.this
    values = {
      arn              = "arn:aws:iam::123456789012:policy/test-policy"
      attachment_count = 0
    }
  }

  override_data {
    target = data.aws_caller_identity.current
    values = {
      account_id = "123456789012"
    }
  }

  override_data {
    target = data.aws_region.current
    values = {
      region = "us-east-1"
    }
  }

  override_data {
    target = data.aws_iam_policy_document.structured
    values = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Sid\":\"ReadObjects\",\"Effect\":\"Allow\",\"Action\":\"s3:GetObject\",\"Resource\":\"arn:aws:s3:::example-bucket/*\"}]}"
    }
  }
}

variables {
  name = "test-policy"
  policy_statements = [{
    sid       = "ReadObjects"
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["arn:aws:s3:::example-bucket/*"]
    conditions = [{
      test     = "StringEquals"
      variable = "aws:ResourceAccount"
      values   = ["123456789012"]
    }]
  }]
}

run "structured_policy_defaults" {
  command = plan

  assert {
    condition     = aws_iam_policy.this.name == "test-policy"
    error_message = "The policy name should use the provided name."
  }

  assert {
    condition     = aws_iam_policy.this.path == "/"
    error_message = "The policy path should default to root."
  }

  assert {
    condition     = aws_iam_policy.this.tags["ManagedBy"] == "terraform"
    error_message = "The ManagedBy tag should be present."
  }

  assert {
    condition     = aws_iam_policy.this.tags["Module"] == "security/iam_policy"
    error_message = "The Module tag should identify security/iam_policy."
  }
}

run "raw_json_overrides_structured_statements" {
  command = plan

  variables {
    policy_json = <<-JSON
      {
        "Version": "2012-10-17",
        "Statement": [{
          "Effect": "Deny",
          "Action": "s3:DeleteObject",
          "Resource": "arn:aws:s3:::example-bucket/*"
        }]
      }
    JSON
  }

  assert {
    condition     = jsondecode(aws_iam_policy.this.policy).Statement[0].Effect == "Deny"
    error_message = "Raw policy JSON should override structured statements."
  }
}

run "user_tags_override_defaults" {
  command = plan

  variables {
    tags = {
      ManagedBy   = "ravion"
      Environment = "production"
    }
  }

  assert {
    condition     = aws_iam_policy.this.tags["ManagedBy"] == "ravion"
    error_message = "User tags should override default tag values."
  }

  assert {
    condition     = aws_iam_policy.this.tags["Environment"] == "production"
    error_message = "User tags should be merged with default tags."
  }
}

run "missing_policy_document_rejected" {
  command = plan

  variables {
    policy_statements = []
  }

  expect_failures = [
    aws_iam_policy.this,
  ]
}

run "invalid_name_rejected" {
  command = plan

  variables {
    name = "invalid policy name"
  }

  expect_failures = [
    var.name,
  ]
}

run "invalid_effect_rejected" {
  command = plan

  variables {
    policy_statements = [{
      effect    = "Permit"
      actions   = ["s3:GetObject"]
      resources = ["arn:aws:s3:::example-bucket/*"]
    }]
  }

  expect_failures = [
    var.policy_statements,
  ]
}

run "not_action_and_not_resource_supported" {
  command = plan

  variables {
    policy_statements = [{
      effect              = "Deny"
      action_match_mode   = "not_actions"
      not_actions         = ["iam:GetUser"]
      resource_match_mode = "not_resources"
      not_resources       = ["arn:aws:iam::123456789012:user/break-glass"]
    }]
  }

  assert {
    condition     = var.policy_statements[0].not_actions == ["iam:GetUser"]
    error_message = "Structured statements should accept NotAction values."
  }

  assert {
    condition     = var.policy_statements[0].not_resources == ["arn:aws:iam::123456789012:user/break-glass"]
    error_message = "Structured statements should accept NotResource values."
  }
}

run "action_and_not_action_rejected" {
  command = plan

  variables {
    policy_statements = [{
      actions     = ["s3:GetObject"]
      not_actions = ["s3:DeleteObject"]
      resources   = ["arn:aws:s3:::example-bucket/*"]
    }]
  }

  expect_failures = [
    var.policy_statements,
  ]
}

run "resource_and_not_resource_rejected" {
  command = plan

  variables {
    policy_statements = [{
      actions       = ["s3:GetObject"]
      resources     = ["arn:aws:s3:::example-bucket/*"]
      not_resources = ["arn:aws:s3:::example-bucket/private/*"]
    }]
  }

  expect_failures = [
    var.policy_statements,
  ]
}

run "wildcard_path_rejected" {
  command = plan

  variables {
    path = "/application*/"
  }

  expect_failures = [
    var.path,
  ]
}
