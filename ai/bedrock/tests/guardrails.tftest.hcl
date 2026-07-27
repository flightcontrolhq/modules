# Amazon Bedrock guardrail tests — run from module root: tofu test

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
    target = aws_bedrock_guardrail.this
    values = {
      guardrail_arn = "arn:aws:bedrock:us-west-2:123456789012:guardrail/abcdefghijkl"
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

run "no_guardrails_by_default" {
  command = plan

  assert {
    condition     = length(aws_bedrock_guardrail.this) == 0
    error_message = "No guardrails should be created by default"
  }

  assert {
    condition     = length(aws_bedrock_guardrail_version.this) == 0
    error_message = "No guardrail versions should be created by default"
  }
}

################################################################################
# Content policy
################################################################################

run "content_policy_guardrail" {
  command = plan

  variables {
    guardrails = {
      safety = {
        description = "Blocks unsafe content"
        content_filters = [
          {
            type            = "HATE"
            input_strength  = "HIGH"
            output_strength = "HIGH"
          },
          {
            type            = "PROMPT_ATTACK"
            input_strength  = "HIGH"
            output_strength = "NONE"
          },
        ]
      }
    }
  }

  assert {
    condition     = aws_bedrock_guardrail.this["safety"].name == "safety"
    error_message = "The guardrail name should default to the map key"
  }

  assert {
    condition     = aws_bedrock_guardrail.this["safety"].blocked_input_messaging == "Sorry, I am unable to respond to that request."
    error_message = "The guardrail should apply the default blocked input messaging"
  }

  assert {
    condition     = length(aws_bedrock_guardrail.this["safety"].content_policy_config[0].filters_config) == 2
    error_message = "Both content policy filters should be configured"
  }

  assert {
    condition     = aws_bedrock_guardrail.this["safety"].tags["Name"] == "safety"
    error_message = "The guardrail should carry a Name tag"
  }

  assert {
    condition     = aws_bedrock_guardrail.this["safety"].tags["Module"] == "ai/bedrock"
    error_message = "The guardrail should carry the module default tags"
  }

  assert {
    condition     = length(aws_bedrock_guardrail.this["safety"].topic_policy_config) == 0
    error_message = "Unconfigured policies should not emit blocks"
  }
}

################################################################################
# Name override and explicit tags
################################################################################

run "guardrail_name_override_and_tags" {
  command = plan

  variables {
    guardrails = {
      safety = {
        name                = "ravion-prod-safety"
        tags                = { Environment = "production" }
        content_filter_tier = "STANDARD"
        content_filters = [{
          type            = "VIOLENCE"
          input_strength  = "MEDIUM"
          output_strength = "MEDIUM"
        }]
      }
    }
  }

  assert {
    condition     = aws_bedrock_guardrail.this["safety"].name == "ravion-prod-safety"
    error_message = "An explicit guardrail name should override the map key"
  }

  assert {
    condition     = aws_bedrock_guardrail.this["safety"].tags["Environment"] == "production"
    error_message = "Per-guardrail tags should merge into the module tags"
  }

  assert {
    condition     = aws_bedrock_guardrail.this["safety"].content_policy_config[0].tier_config[0].tier_name == "STANDARD"
    error_message = "The content policy tier should be configured when set"
  }
}

################################################################################
# Topic, word, PII, and grounding policies
################################################################################

run "all_policy_types" {
  command = plan

  variables {
    guardrails = {
      full = {
        denied_topics = [{
          name       = "investment-advice"
          definition = "Any recommendation to buy or sell a specific security."
          examples   = ["Should I buy this stock?"]
        }]
        denied_words       = [{ text = "competitor-name" }]
        managed_word_lists = [{}]
        pii_entities = [{
          type   = "EMAIL"
          action = "ANONYMIZE"
        }]
        regex_filters = [{
          name    = "employee-id"
          pattern = "EMP-[0-9]{6}"
          action  = "BLOCK"
        }]
        grounding_filters = [{
          type      = "GROUNDING"
          threshold = 0.75
        }]
      }
    }
  }

  assert {
    condition     = aws_bedrock_guardrail.this["full"].topic_policy_config[0].topics_config[0].type == "DENY"
    error_message = "Topics should default to the DENY type"
  }

  assert {
    condition     = aws_bedrock_guardrail.this["full"].word_policy_config[0].managed_word_lists_config[0].type == "PROFANITY"
    error_message = "Managed word lists should default to PROFANITY"
  }

  assert {
    condition     = aws_bedrock_guardrail.this["full"].sensitive_information_policy_config[0].pii_entities_config[0].action == "ANONYMIZE"
    error_message = "The PII entity action should be configured"
  }

  assert {
    condition     = aws_bedrock_guardrail.this["full"].sensitive_information_policy_config[0].regexes_config[0].pattern == "EMP-[0-9]{6}"
    error_message = "The regex pattern should be configured"
  }

  assert {
    condition     = aws_bedrock_guardrail.this["full"].contextual_grounding_policy_config[0].filters_config[0].threshold == 0.75
    error_message = "The contextual grounding threshold should be configured"
  }

  assert {
    condition     = length(aws_bedrock_guardrail.this["full"].content_policy_config) == 0
    error_message = "An unconfigured content policy should not emit a block"
  }
}

################################################################################
# Versions
################################################################################

run "guardrail_version_published_when_enabled" {
  command = plan

  variables {
    guardrails = {
      versioned = {
        version_creation_enabled = true
        version_description      = "v1 - initial policy set"
        content_filters = [{
          type            = "INSULTS"
          input_strength  = "LOW"
          output_strength = "LOW"
        }]
      }
      unversioned = {
        content_filters = [{
          type            = "INSULTS"
          input_strength  = "LOW"
          output_strength = "LOW"
        }]
      }
    }
  }

  assert {
    condition     = length(aws_bedrock_guardrail_version.this) == 1
    error_message = "Only guardrails with version creation enabled should publish a version"
  }

  assert {
    condition     = aws_bedrock_guardrail_version.this["versioned"].description == "v1 - initial policy set"
    error_message = "The guardrail version description should be configured"
  }
}

################################################################################
# Cross-region
################################################################################

run "guardrail_cross_region_profile" {
  command = plan

  variables {
    guardrails = {
      safety = {
        cross_region_guardrail_profile_identifier = "arn:aws:bedrock:us-west-2:123456789012:guardrail-profile/us.guardrail.v1:0"
        content_filters = [{
          type            = "HATE"
          input_strength  = "HIGH"
          output_strength = "HIGH"
        }]
      }
    }
  }

  assert {
    condition     = aws_bedrock_guardrail.this["safety"].cross_region_config[0].guardrail_profile_identifier == "arn:aws:bedrock:us-west-2:123456789012:guardrail-profile/us.guardrail.v1:0"
    error_message = "The cross-region guardrail profile should be configured when set"
  }
}

################################################################################
# Validation
################################################################################

run "guardrail_without_policy_rejected" {
  command = plan

  variables {
    guardrails = {
      empty = {}
    }
  }

  expect_failures = [
    var.guardrails,
  ]
}

run "invalid_managed_word_list_type_rejected" {
  command = plan

  variables {
    guardrails = {
      safety = {
        managed_word_lists = [{ type = "SLANG" }]
      }
    }
  }

  expect_failures = [
    var.guardrails,
  ]
}

run "invalid_content_filter_type_rejected" {
  command = plan

  variables {
    guardrails = {
      safety = {
        content_filters = [{
          type            = "NOT_A_FILTER"
          input_strength  = "HIGH"
          output_strength = "HIGH"
        }]
      }
    }
  }

  expect_failures = [
    var.guardrails,
  ]
}

run "invalid_content_filter_strength_rejected" {
  command = plan

  variables {
    guardrails = {
      safety = {
        content_filters = [{
          type            = "HATE"
          input_strength  = "EXTREME"
          output_strength = "HIGH"
        }]
      }
    }
  }

  expect_failures = [
    var.guardrails,
  ]
}

run "invalid_pii_action_rejected" {
  command = plan

  variables {
    guardrails = {
      safety = {
        pii_entities = [{
          type   = "EMAIL"
          action = "REDACT"
        }]
      }
    }
  }

  expect_failures = [
    var.guardrails,
  ]
}

run "invalid_grounding_threshold_rejected" {
  command = plan

  variables {
    guardrails = {
      safety = {
        grounding_filters = [{
          type      = "GROUNDING"
          threshold = 1
        }]
      }
    }
  }

  expect_failures = [
    var.guardrails,
  ]
}

run "invalid_tier_name_rejected" {
  command = plan

  variables {
    guardrails = {
      safety = {
        content_filter_tier = "PREMIUM"
        content_filters = [{
          type            = "HATE"
          input_strength  = "HIGH"
          output_strength = "HIGH"
        }]
      }
    }
  }

  expect_failures = [
    var.guardrails,
  ]
}

run "invalid_guardrail_name_rejected" {
  command = plan

  variables {
    guardrails = {
      safety = {
        name = "not a valid guardrail name"
        content_filters = [{
          type            = "HATE"
          input_strength  = "HIGH"
          output_strength = "HIGH"
        }]
      }
    }
  }

  expect_failures = [
    var.guardrails,
  ]
}
