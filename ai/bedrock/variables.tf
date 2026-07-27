################################################################################
# General
################################################################################

variable "name" {
  type        = string
  description = "Name prefix for resources created by this module."

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]{0,35}[a-z0-9])?$", var.name))
    error_message = "The name must contain 1-37 lowercase letters, numbers, or hyphens, starting and ending with a letter or number."
  }
}

variable "region" {
  type        = string
  description = "AWS region. When null, the provider's configured region is used."
  default     = null
}

variable "tags" {
  type        = map(string)
  description = "A map of additional tags to assign to resources created by this module."
  default     = {}
}

################################################################################
# Model Invocation Logging
################################################################################

variable "model_invocation_logging_enabled" {
  type        = bool
  description = "Enable account- and region-wide Amazon Bedrock model invocation logging."
  default     = true
}

variable "text_data_delivery_enabled" {
  type        = bool
  description = "Include text model invocation inputs and outputs in delivered logs. Logged data can contain sensitive prompts and responses."
  default     = true
}

variable "image_data_delivery_enabled" {
  type        = bool
  description = "Include image model invocation inputs and outputs in delivered logs."
  default     = false
}

variable "embedding_data_delivery_enabled" {
  type        = bool
  description = "Include embedding model invocation inputs and outputs in delivered logs."
  default     = false
}

variable "video_data_delivery_enabled" {
  type        = bool
  description = "Include video model invocation inputs and outputs in delivered logs."
  default     = false
}

################################################################################
# CloudWatch Logs
################################################################################

variable "log_group_name" {
  type        = string
  description = "Name of the CloudWatch log group to create. Defaults to /aws/bedrock/model-invocations/<name>."
  default     = null

  validation {
    condition     = var.log_group_name == null || can(regex("^[A-Za-z0-9_./#-]{1,512}$", var.log_group_name))
    error_message = "The log_group_name must contain 1-512 valid CloudWatch Logs name characters."
  }
}

variable "log_group_retention_days" {
  type        = number
  description = "Number of days to retain invocation logs in CloudWatch Logs. Use 0 to retain logs indefinitely."
  default     = 90

  validation {
    condition = contains([
      0,
      1,
      3,
      5,
      7,
      14,
      30,
      60,
      90,
      120,
      150,
      180,
      365,
      400,
      545,
      731,
      1096,
      1827,
      2192,
      2557,
      2922,
      3288,
      3653,
    ], var.log_group_retention_days)
    error_message = "The log_group_retention_days must be 0 or a retention period supported by CloudWatch Logs."
  }
}

variable "log_group_kms_key_arn" {
  type        = string
  description = "ARN of an optional customer-managed KMS key used to encrypt the CloudWatch log group. The key policy must allow the regional CloudWatch Logs service."
  default     = null

  validation {
    condition     = var.log_group_kms_key_arn == null || can(regex("^arn:[^:]+:kms:[^:]+:[0-9]{12}:key/[0-9a-fA-F-]+$", var.log_group_kms_key_arn))
    error_message = "The log_group_kms_key_arn must be a valid KMS key ARN."
  }
}

################################################################################
# Guardrails
################################################################################

variable "guardrails" {
  description = "Map of Amazon Bedrock guardrails, keyed by a stable logical name. Each guardrail applies the configured content, topic, word, sensitive information, and contextual grounding filters to model invocations that reference it. A guardrail must configure at least one filter list."
  type = map(object({
    name                      = optional(string)
    description               = optional(string)
    blocked_input_messaging   = optional(string, "Sorry, I am unable to respond to that request.")
    blocked_outputs_messaging = optional(string, "Sorry, I am unable to respond to that request.")
    kms_key_arn               = optional(string)
    tags                      = optional(map(string))

    # Publishing an immutable version snapshot of the guardrail. A version
    # captures the guardrail as it exists when the version is created; later
    # edits do not change a published version.
    version_creation_enabled = optional(bool, false)
    version_description      = optional(string)
    version_skip_destroy     = optional(bool, false)

    # Full ARN of a guardrail profile used for cross-region guardrail evaluation.
    cross_region_guardrail_profile_identifier = optional(string)

    content_filter_tier = optional(string)
    content_filters = optional(list(object({
      type              = string
      input_strength    = string
      output_strength   = string
      input_action      = optional(string)
      input_enabled     = optional(bool)
      input_modalities  = optional(set(string))
      output_action     = optional(string)
      output_enabled    = optional(bool)
      output_modalities = optional(set(string))
    })), [])

    denied_topic_tier = optional(string)
    denied_topics = optional(list(object({
      name       = string
      definition = string
      examples   = optional(list(string))
    })), [])

    denied_words = optional(list(object({
      text           = string
      input_action   = optional(string)
      input_enabled  = optional(bool)
      output_action  = optional(string)
      output_enabled = optional(bool)
    })), [])

    managed_word_lists = optional(list(object({
      type           = optional(string, "PROFANITY")
      input_action   = optional(string)
      input_enabled  = optional(bool)
      output_action  = optional(string)
      output_enabled = optional(bool)
    })), [])

    pii_entities = optional(list(object({
      type           = string
      action         = string
      input_action   = optional(string)
      input_enabled  = optional(bool)
      output_action  = optional(string)
      output_enabled = optional(bool)
    })), [])

    regex_filters = optional(list(object({
      name           = string
      pattern        = string
      action         = string
      description    = optional(string)
      input_action   = optional(string)
      input_enabled  = optional(bool)
      output_action  = optional(string)
      output_enabled = optional(bool)
    })), [])

    grounding_filters = optional(list(object({
      type      = string
      threshold = number
    })), [])
  }))
  default = {}

  validation {
    condition = alltrue([
      for key, guardrail in var.guardrails :
      can(regex("^[0-9a-zA-Z][0-9a-zA-Z_-]{0,49}$", coalesce(guardrail.name, key)))
    ])
    error_message = "Each guardrail name must contain 1-50 letters, numbers, underscores, or hyphens and start with a letter or number."
  }

  validation {
    condition = alltrue([
      for key, guardrail in var.guardrails : anytrue([
        length(guardrail.content_filters) > 0,
        length(guardrail.denied_topics) > 0,
        length(guardrail.denied_words) > 0,
        length(guardrail.managed_word_lists) > 0,
        length(guardrail.pii_entities) > 0,
        length(guardrail.regex_filters) > 0,
        length(guardrail.grounding_filters) > 0,
      ])
    ])
    error_message = "Each guardrail must configure at least one content filter, denied topic, denied word, managed word list, PII entity, regex filter, or grounding filter."
  }

  validation {
    condition = alltrue(flatten([
      for key, guardrail in var.guardrails : [
        for filter in guardrail.content_filters :
        contains(["SEXUAL", "VIOLENCE", "HATE", "INSULTS", "MISCONDUCT", "PROMPT_ATTACK"], filter.type)
      ]
    ]))
    error_message = "Each guardrail content filter type must be one of: SEXUAL, VIOLENCE, HATE, INSULTS, MISCONDUCT, PROMPT_ATTACK."
  }

  validation {
    condition = alltrue(flatten([
      for key, guardrail in var.guardrails : [
        for filter in guardrail.content_filters : [
          contains(["NONE", "LOW", "MEDIUM", "HIGH"], filter.input_strength),
          contains(["NONE", "LOW", "MEDIUM", "HIGH"], filter.output_strength),
        ]
      ]
    ]))
    error_message = "Each guardrail content filter strength must be one of: NONE, LOW, MEDIUM, HIGH."
  }

  validation {
    condition = alltrue(flatten([
      for key, guardrail in var.guardrails : [
        for entity in guardrail.pii_entities : contains(["BLOCK", "ANONYMIZE", "NONE"], entity.action)
      ]
    ]))
    error_message = "Each guardrail PII entity action must be one of: BLOCK, ANONYMIZE, NONE."
  }

  validation {
    condition = alltrue(flatten([
      for key, guardrail in var.guardrails : [
        for filter in guardrail.regex_filters : contains(["BLOCK", "ANONYMIZE", "NONE"], filter.action)
      ]
    ]))
    error_message = "Each guardrail regex filter action must be one of: BLOCK, ANONYMIZE, NONE."
  }

  validation {
    condition = alltrue(flatten([
      for key, guardrail in var.guardrails : [
        for filter in guardrail.managed_word_lists : contains(["PROFANITY"], filter.type)
      ]
    ]))
    error_message = "Each guardrail managed word list type must be PROFANITY."
  }

  validation {
    condition = alltrue(flatten([
      for key, guardrail in var.guardrails : [
        for filter in guardrail.grounding_filters : [
          contains(["GROUNDING", "RELEVANCE"], filter.type),
          filter.threshold >= 0 && filter.threshold < 1,
        ]
      ]
    ]))
    error_message = "Each guardrail grounding filter type must be GROUNDING or RELEVANCE with a threshold of at least 0 and less than 1."
  }

  validation {
    condition = alltrue(flatten([
      for key, guardrail in var.guardrails : [
        for tier_name in compact([guardrail.content_filter_tier, guardrail.denied_topic_tier]) :
        contains(["CLASSIC", "STANDARD"], tier_name)
      ]
    ]))
    error_message = "Each guardrail content_filter_tier and denied_topic_tier must be CLASSIC or STANDARD when set."
  }

  validation {
    condition = alltrue([
      for key, guardrail in var.guardrails :
      guardrail.cross_region_guardrail_profile_identifier == null ||
      can(regex("^arn:[^:]+:bedrock:", guardrail.cross_region_guardrail_profile_identifier))
    ])
    error_message = "Each guardrail cross_region_guardrail_profile_identifier must be a full Bedrock guardrail profile ARN, for example arn:aws:bedrock:us-west-2:123456789012:guardrail-profile/us.guardrail.v1:0."
  }
}

################################################################################
# Custom Models
################################################################################

variable "custom_models" {
  description = "Map of Amazon Bedrock model customization jobs, keyed by a stable logical name. Each entry runs a fine-tuning or continued pre-training job and registers the resulting custom model."
  type = map(object({
    custom_model_name     = optional(string)
    job_name              = optional(string)
    base_model_identifier = string
    role_arn              = string
    customization_type    = optional(string, "FINE_TUNING")
    hyperparameters       = map(string)
    kms_key_id            = optional(string)
    tags                  = optional(map(string))

    training_data_s3_uri    = string
    output_data_s3_uri      = string
    validation_data_s3_uris = optional(list(string), [])

    # Run the customization job inside a VPC. Both lists must be set together.
    vpc_subnet_ids         = optional(set(string), [])
    vpc_security_group_ids = optional(set(string), [])
  }))
  default = {}

  validation {
    condition = alltrue([
      for key, model in var.custom_models :
      (length(model.vpc_subnet_ids) > 0) == (length(model.vpc_security_group_ids) > 0)
    ])
    error_message = "Each custom model must set both vpc_subnet_ids and vpc_security_group_ids, or neither."
  }

  validation {
    condition = alltrue([
      for key, model in var.custom_models :
      contains(["FINE_TUNING", "CONTINUED_PRE_TRAINING", "DISTILLATION", "IMPORTED"], model.customization_type)
    ])
    error_message = "Each custom model customization_type must be one of: FINE_TUNING, CONTINUED_PRE_TRAINING, DISTILLATION, IMPORTED."
  }

  validation {
    condition = alltrue(flatten([
      for key, model in var.custom_models : [
        can(regex("^s3://", model.training_data_s3_uri)),
        can(regex("^s3://", model.output_data_s3_uri)),
        [for uri in model.validation_data_s3_uris : can(regex("^s3://", uri))],
      ]
    ]))
    error_message = "Each custom model training, output, and validation data URI must be an s3:// URI."
  }

  validation {
    condition = alltrue([
      for key, model in var.custom_models :
      can(regex("^arn:[^:]+:iam::[0-9]{12}:role/", model.role_arn))
    ])
    error_message = "Each custom model role_arn must be a valid IAM role ARN."
  }
}

################################################################################
# Inference Profiles
################################################################################

variable "inference_profiles" {
  description = "Map of Amazon Bedrock application inference profiles, keyed by a stable logical name. Each profile copies a foundation model or system-defined inference profile so invocation costs can be tracked per profile."
  type = map(object({
    name        = optional(string)
    description = optional(string)
    copy_from   = string
    tags        = optional(map(string))
  }))
  default = {}

  validation {
    condition = alltrue([
      for key, profile in var.inference_profiles :
      can(regex("^arn:[^:]+:bedrock:", profile.copy_from))
    ])
    error_message = "Each inference profile copy_from must be a Bedrock foundation model or inference profile ARN."
  }
}

################################################################################
# Provisioned Model Throughput
################################################################################

variable "provisioned_model_throughputs" {
  description = "Map of Amazon Bedrock provisioned model throughput reservations, keyed by a stable logical name. Reservations without a commitment_duration bill on demand and can be deleted at any time."
  type = map(object({
    provisioned_model_name = optional(string)
    model_arn              = string
    model_units            = number
    commitment_duration    = optional(string)
    tags                   = optional(map(string))
  }))
  default = {}

  validation {
    condition = alltrue([
      for key, throughput in var.provisioned_model_throughputs :
      throughput.commitment_duration == null || contains(["OneMonth", "SixMonths"], throughput.commitment_duration)
    ])
    error_message = "Each provisioned model throughput commitment_duration must be OneMonth or SixMonths when set."
  }

  validation {
    condition = alltrue([
      for key, throughput in var.provisioned_model_throughputs :
      throughput.model_units >= 1
    ])
    error_message = "Each provisioned model throughput must reserve at least 1 model unit."
  }
}

################################################################################
# Model Access
################################################################################

variable "foundation_model_agreements" {
  description = "Map of Amazon Bedrock foundation model agreements to accept, keyed by a stable logical name. Accepting an agreement grants the account access to the model in this region. Set offer_token to pin a specific offer; otherwise the first available offer for the model is used."
  type = map(object({
    model_id    = string
    offer_token = optional(string)
    offer_type  = optional(string, "PUBLIC")
  }))
  default = {}

  validation {
    condition = alltrue([
      for key, agreement in var.foundation_model_agreements :
      contains(["PUBLIC", "ALL"], agreement.offer_type)
    ])
    error_message = "Each foundation model agreement offer_type must be PUBLIC or ALL."
  }
}

variable "model_access_use_case_form_data" {
  description = "JSON use case form data submitted for models that require an approved use case before access is granted, such as the Anthropic models. Leave null when no use case submission is required."
  type        = string
  default     = null

  validation {
    condition     = var.model_access_use_case_form_data == null || can(jsondecode(var.model_access_use_case_form_data))
    error_message = "The model_access_use_case_form_data must be a valid JSON document."
  }
}
