# Amazon Bedrock model resource tests — run from module root: tofu test

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

  override_data {
    target = data.aws_bedrock_foundation_model_agreement_offers.this
    values = {
      offers = [{
        offer_id     = "offer-abc123"
        offer_token  = "token-abc123"
        term_details = []
      }]
    }
  }
}

variables {
  name                             = "ravion-prod"
  region                           = "us-west-2"
  model_invocation_logging_enabled = false
}

################################################################################
# Defaults
################################################################################

run "no_model_resources_by_default" {
  command = plan

  assert {
    condition = (
      length(aws_bedrock_custom_model.this) == 0 &&
      length(aws_bedrock_inference_profile.this) == 0 &&
      length(aws_bedrock_provisioned_model_throughput.this) == 0 &&
      length(aws_bedrock_foundation_model_agreement.this) == 0 &&
      length(aws_bedrock_use_case_for_model_access.this) == 0
    )
    error_message = "No model resources should be created by default"
  }
}

################################################################################
# Application inference profiles
################################################################################

run "inference_profiles" {
  command = plan

  variables {
    inference_profiles = {
      chat = {
        description = "Chat workload cost tracking"
        copy_from   = "arn:aws:bedrock:us-west-2::foundation-model/anthropic.claude-sonnet-4-20250514-v1:0"
      }
      batch = {
        name      = "batch-scoring"
        copy_from = "arn:aws:bedrock:us-west-2::foundation-model/anthropic.claude-sonnet-4-20250514-v1:0"
        tags      = { Workload = "batch" }
      }
    }
  }

  assert {
    condition     = aws_bedrock_inference_profile.this["chat"].name == "ravion-prod-chat"
    error_message = "The inference profile name should default to <name>-<key>"
  }

  assert {
    condition     = aws_bedrock_inference_profile.this["batch"].name == "batch-scoring"
    error_message = "An explicit inference profile name should override the default"
  }

  assert {
    condition     = aws_bedrock_inference_profile.this["chat"].model_source[0].copy_from == "arn:aws:bedrock:us-west-2::foundation-model/anthropic.claude-sonnet-4-20250514-v1:0"
    error_message = "The inference profile model source should be configured"
  }

  assert {
    condition     = aws_bedrock_inference_profile.this["batch"].tags["Workload"] == "batch"
    error_message = "Per-profile tags should merge into the module tags"
  }

  assert {
    condition     = aws_bedrock_inference_profile.this["chat"].tags["Module"] == "ai/bedrock"
    error_message = "The inference profile should carry the module default tags"
  }
}

run "inference_profile_non_bedrock_source_rejected" {
  command = plan

  variables {
    inference_profiles = {
      chat = {
        copy_from = "anthropic.claude-sonnet-4-20250514-v1:0"
      }
    }
  }

  expect_failures = [
    var.inference_profiles,
  ]
}

################################################################################
# Provisioned model throughput
################################################################################

run "provisioned_model_throughput" {
  command = plan

  variables {
    provisioned_model_throughputs = {
      chat = {
        model_arn   = "arn:aws:bedrock:us-west-2::foundation-model/anthropic.claude-sonnet-4-20250514-v1:0"
        model_units = 2
      }
      committed = {
        provisioned_model_name = "committed-capacity"
        model_arn              = "arn:aws:bedrock:us-west-2::foundation-model/anthropic.claude-sonnet-4-20250514-v1:0"
        model_units            = 4
        commitment_duration    = "SixMonths"
      }
    }
  }

  assert {
    condition     = aws_bedrock_provisioned_model_throughput.this["chat"].provisioned_model_name == "ravion-prod-chat"
    error_message = "The provisioned model name should default to <name>-<key>"
  }

  assert {
    condition     = aws_bedrock_provisioned_model_throughput.this["chat"].commitment_duration == null
    error_message = "Throughput without a commitment should bill on demand"
  }

  assert {
    condition     = aws_bedrock_provisioned_model_throughput.this["committed"].commitment_duration == "SixMonths"
    error_message = "The commitment duration should be configured when set"
  }

  assert {
    condition     = aws_bedrock_provisioned_model_throughput.this["committed"].model_units == 4
    error_message = "The reserved model units should be configured"
  }
}

run "invalid_commitment_duration_rejected" {
  command = plan

  variables {
    provisioned_model_throughputs = {
      chat = {
        model_arn           = "arn:aws:bedrock:us-west-2::foundation-model/anthropic.claude-sonnet-4-20250514-v1:0"
        model_units         = 1
        commitment_duration = "TwoYears"
      }
    }
  }

  expect_failures = [
    var.provisioned_model_throughputs,
  ]
}

run "zero_model_units_rejected" {
  command = plan

  variables {
    provisioned_model_throughputs = {
      chat = {
        model_arn   = "arn:aws:bedrock:us-west-2::foundation-model/anthropic.claude-sonnet-4-20250514-v1:0"
        model_units = 0
      }
    }
  }

  expect_failures = [
    var.provisioned_model_throughputs,
  ]
}

################################################################################
# Custom models
################################################################################

run "custom_models" {
  command = plan

  variables {
    custom_models = {
      support = {
        base_model_identifier = "arn:aws:bedrock:us-west-2::foundation-model/amazon.titan-text-lite-v1"
        role_arn              = "arn:aws:iam::123456789012:role/bedrock-customization"
        hyperparameters = {
          epochCount = "2"
        }
        training_data_s3_uri    = "s3://ravion-bedrock-training/support/train.jsonl"
        output_data_s3_uri      = "s3://ravion-bedrock-training/support/output/"
        validation_data_s3_uris = ["s3://ravion-bedrock-training/support/validate.jsonl"]
        vpc_subnet_ids          = ["subnet-11111111"]
        vpc_security_group_ids  = ["sg-11111111"]
      }
    }
  }

  assert {
    condition     = aws_bedrock_custom_model.this["support"].custom_model_name == "ravion-prod-support"
    error_message = "The custom model name should default to <name>-<key>"
  }

  assert {
    condition     = aws_bedrock_custom_model.this["support"].job_name == "ravion-prod-support"
    error_message = "The customization job name should default to <name>-<key>"
  }

  assert {
    condition     = aws_bedrock_custom_model.this["support"].customization_type == "FINE_TUNING"
    error_message = "The customization type should default to FINE_TUNING"
  }

  assert {
    condition     = aws_bedrock_custom_model.this["support"].training_data_config[0].s3_uri == "s3://ravion-bedrock-training/support/train.jsonl"
    error_message = "The training data URI should be configured"
  }

  assert {
    condition     = aws_bedrock_custom_model.this["support"].validation_data_config[0].validator[0].s3_uri == "s3://ravion-bedrock-training/support/validate.jsonl"
    error_message = "The validation data URI should be configured"
  }

  assert {
    condition     = aws_bedrock_custom_model.this["support"].vpc_config[0].subnet_ids == toset(["subnet-11111111"])
    error_message = "The customization job VPC subnets should be configured"
  }
}

run "custom_model_without_validation_data_omits_block" {
  command = plan

  variables {
    custom_models = {
      support = {
        base_model_identifier = "arn:aws:bedrock:us-west-2::foundation-model/amazon.titan-text-lite-v1"
        role_arn              = "arn:aws:iam::123456789012:role/bedrock-customization"
        hyperparameters       = { epochCount = "2" }
        training_data_s3_uri  = "s3://ravion-bedrock-training/support/train.jsonl"
        output_data_s3_uri    = "s3://ravion-bedrock-training/support/output/"
      }
    }
  }

  assert {
    condition     = length(aws_bedrock_custom_model.this["support"].validation_data_config) == 0
    error_message = "The validation data block should be omitted when no validators are given"
  }

  assert {
    condition     = length(aws_bedrock_custom_model.this["support"].vpc_config) == 0
    error_message = "The VPC config block should be omitted when not configured"
  }
}

run "custom_model_partial_vpc_config_rejected" {
  command = plan

  variables {
    custom_models = {
      support = {
        base_model_identifier = "arn:aws:bedrock:us-west-2::foundation-model/amazon.titan-text-lite-v1"
        role_arn              = "arn:aws:iam::123456789012:role/bedrock-customization"
        hyperparameters       = { epochCount = "2" }
        training_data_s3_uri  = "s3://ravion-bedrock-training/support/train.jsonl"
        output_data_s3_uri    = "s3://ravion-bedrock-training/support/output/"
        vpc_subnet_ids        = ["subnet-11111111"]
      }
    }
  }

  expect_failures = [
    var.custom_models,
  ]
}

run "non_s3_training_uri_rejected" {
  command = plan

  variables {
    custom_models = {
      support = {
        base_model_identifier = "arn:aws:bedrock:us-west-2::foundation-model/amazon.titan-text-lite-v1"
        role_arn              = "arn:aws:iam::123456789012:role/bedrock-customization"
        hyperparameters       = { epochCount = "2" }
        training_data_s3_uri  = "https://example.com/train.jsonl"
        output_data_s3_uri    = "s3://ravion-bedrock-training/support/output/"
      }
    }
  }

  expect_failures = [
    var.custom_models,
  ]
}

run "invalid_customization_type_rejected" {
  command = plan

  variables {
    custom_models = {
      support = {
        base_model_identifier = "arn:aws:bedrock:us-west-2::foundation-model/amazon.titan-text-lite-v1"
        role_arn              = "arn:aws:iam::123456789012:role/bedrock-customization"
        customization_type    = "TRANSFER_LEARNING"
        hyperparameters       = { epochCount = "2" }
        training_data_s3_uri  = "s3://ravion-bedrock-training/support/train.jsonl"
        output_data_s3_uri    = "s3://ravion-bedrock-training/support/output/"
      }
    }
  }

  expect_failures = [
    var.custom_models,
  ]
}

run "non_role_arn_rejected" {
  command = plan

  variables {
    custom_models = {
      support = {
        base_model_identifier = "arn:aws:bedrock:us-west-2::foundation-model/amazon.titan-text-lite-v1"
        role_arn              = "arn:aws:iam::123456789012:user/not-a-role"
        hyperparameters       = { epochCount = "2" }
        training_data_s3_uri  = "s3://ravion-bedrock-training/support/train.jsonl"
        output_data_s3_uri    = "s3://ravion-bedrock-training/support/output/"
      }
    }
  }

  expect_failures = [
    var.custom_models,
  ]
}

################################################################################
# Model access
################################################################################

run "foundation_model_agreement_resolves_offer_token" {
  command = plan

  variables {
    foundation_model_agreements = {
      claude = {
        model_id = "anthropic.claude-sonnet-4-20250514-v1:0"
      }
    }
  }

  assert {
    condition     = aws_bedrock_foundation_model_agreement.this["claude"].model_id == "anthropic.claude-sonnet-4-20250514-v1:0"
    error_message = "The agreement should target the requested model"
  }

  assert {
    condition     = aws_bedrock_foundation_model_agreement.this["claude"].offer_token == "token-abc123"
    error_message = "The offer token should be resolved from the offers data source"
  }

  assert {
    condition     = length(data.aws_bedrock_foundation_model_agreement_offers.this) == 1
    error_message = "The offers data source should be read for agreements without an explicit token"
  }
}

run "foundation_model_agreement_explicit_token_skips_lookup" {
  command = plan

  variables {
    foundation_model_agreements = {
      claude = {
        model_id    = "anthropic.claude-sonnet-4-20250514-v1:0"
        offer_token = "pinned-token"
      }
    }
  }

  assert {
    condition     = aws_bedrock_foundation_model_agreement.this["claude"].offer_token == "pinned-token"
    error_message = "An explicit offer token should be used verbatim"
  }

  assert {
    condition     = length(data.aws_bedrock_foundation_model_agreement_offers.this) == 0
    error_message = "The offers data source should not be read when a token is pinned"
  }
}

run "invalid_offer_type_rejected" {
  command = plan

  variables {
    foundation_model_agreements = {
      claude = {
        model_id   = "anthropic.claude-sonnet-4-20250514-v1:0"
        offer_type = "PRIVATE"
      }
    }
  }

  expect_failures = [
    var.foundation_model_agreements,
  ]
}

run "use_case_form_submitted_when_provided" {
  command = plan

  variables {
    model_access_use_case_form_data = "{\"companyName\":\"Ravion\",\"intendedUsers\":\"Internal\"}"
  }

  assert {
    condition     = length(aws_bedrock_use_case_for_model_access.this) == 1
    error_message = "The use case form should be submitted when form data is provided"
  }

  assert {
    condition     = jsondecode(aws_bedrock_use_case_for_model_access.this[0].form_data).companyName == "Ravion"
    error_message = "The submitted form data should match the input"
  }
}

run "non_json_use_case_form_rejected" {
  command = plan

  variables {
    model_access_use_case_form_data = "not json"
  }

  expect_failures = [
    var.model_access_use_case_form_data,
  ]
}
