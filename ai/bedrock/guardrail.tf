################################################################################
# Guardrails
################################################################################

resource "aws_bedrock_guardrail" "this" {
  for_each = var.guardrails

  name                      = coalesce(each.value.name, each.key)
  description               = each.value.description
  blocked_input_messaging   = each.value.blocked_input_messaging
  blocked_outputs_messaging = each.value.blocked_outputs_messaging
  kms_key_arn               = each.value.kms_key_arn

  dynamic "cross_region_config" {
    for_each = each.value.cross_region_guardrail_profile_identifier == null ? [] : [each.value.cross_region_guardrail_profile_identifier]

    content {
      guardrail_profile_identifier = cross_region_config.value
    }
  }

  dynamic "content_policy_config" {
    for_each = length(each.value.content_filters) > 0 ? [each.value] : []

    content {
      tier_config = content_policy_config.value.content_filter_tier == null ? null : [{
        tier_name = content_policy_config.value.content_filter_tier
      }]

      dynamic "filters_config" {
        for_each = content_policy_config.value.content_filters

        content {
          type              = filters_config.value.type
          input_strength    = filters_config.value.input_strength
          output_strength   = filters_config.value.output_strength
          input_action      = filters_config.value.input_action
          input_enabled     = filters_config.value.input_enabled
          input_modalities  = filters_config.value.input_modalities
          output_action     = filters_config.value.output_action
          output_enabled    = filters_config.value.output_enabled
          output_modalities = filters_config.value.output_modalities
        }
      }
    }
  }

  dynamic "topic_policy_config" {
    for_each = length(each.value.denied_topics) > 0 ? [each.value] : []

    content {
      tier_config = topic_policy_config.value.denied_topic_tier == null ? null : [{
        tier_name = topic_policy_config.value.denied_topic_tier
      }]

      dynamic "topics_config" {
        for_each = topic_policy_config.value.denied_topics

        content {
          name       = topics_config.value.name
          definition = topics_config.value.definition
          examples   = topics_config.value.examples
          type       = "DENY"
        }
      }
    }
  }

  dynamic "word_policy_config" {
    for_each = length(each.value.denied_words) > 0 || length(each.value.managed_word_lists) > 0 ? [each.value] : []

    content {
      dynamic "words_config" {
        for_each = word_policy_config.value.denied_words

        content {
          text           = words_config.value.text
          input_action   = words_config.value.input_action
          input_enabled  = words_config.value.input_enabled
          output_action  = words_config.value.output_action
          output_enabled = words_config.value.output_enabled
        }
      }

      dynamic "managed_word_lists_config" {
        for_each = word_policy_config.value.managed_word_lists

        content {
          type           = managed_word_lists_config.value.type
          input_action   = managed_word_lists_config.value.input_action
          input_enabled  = managed_word_lists_config.value.input_enabled
          output_action  = managed_word_lists_config.value.output_action
          output_enabled = managed_word_lists_config.value.output_enabled
        }
      }
    }
  }

  dynamic "sensitive_information_policy_config" {
    for_each = length(each.value.pii_entities) > 0 || length(each.value.regex_filters) > 0 ? [each.value] : []

    content {
      dynamic "pii_entities_config" {
        for_each = sensitive_information_policy_config.value.pii_entities

        content {
          type           = pii_entities_config.value.type
          action         = pii_entities_config.value.action
          input_action   = pii_entities_config.value.input_action
          input_enabled  = pii_entities_config.value.input_enabled
          output_action  = pii_entities_config.value.output_action
          output_enabled = pii_entities_config.value.output_enabled
        }
      }

      dynamic "regexes_config" {
        for_each = sensitive_information_policy_config.value.regex_filters

        content {
          name           = regexes_config.value.name
          pattern        = regexes_config.value.pattern
          action         = regexes_config.value.action
          description    = regexes_config.value.description
          input_action   = regexes_config.value.input_action
          input_enabled  = regexes_config.value.input_enabled
          output_action  = regexes_config.value.output_action
          output_enabled = regexes_config.value.output_enabled
        }
      }
    }
  }

  dynamic "contextual_grounding_policy_config" {
    for_each = length(each.value.grounding_filters) > 0 ? [each.value] : []

    content {
      dynamic "filters_config" {
        for_each = contextual_grounding_policy_config.value.grounding_filters

        content {
          type      = filters_config.value.type
          threshold = filters_config.value.threshold
        }
      }
    }
  }

  tags = merge(local.tags, {
    Name = coalesce(each.value.name, each.key)
  }, each.value.tags != null ? each.value.tags : {})
}

# Immutable snapshots of a guardrail. A version captures the guardrail as it
# exists when the version is created; later guardrail edits do not change a
# published version. Change version_description to publish a new snapshot.
resource "aws_bedrock_guardrail_version" "this" {
  for_each = {
    for key, guardrail in var.guardrails : key => guardrail
    if guardrail.version_creation_enabled
  }

  guardrail_arn = aws_bedrock_guardrail.this[each.key].guardrail_arn
  description   = each.value.version_description
  skip_destroy  = each.value.version_skip_destroy
}
