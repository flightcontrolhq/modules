################################################################################
# Custom Models
################################################################################

resource "aws_bedrock_custom_model" "this" {
  for_each = var.custom_models

  custom_model_name       = coalesce(each.value.custom_model_name, "${var.name}-${each.key}")
  job_name                = coalesce(each.value.job_name, "${var.name}-${each.key}")
  base_model_identifier   = each.value.base_model_identifier
  role_arn                = each.value.role_arn
  customization_type      = each.value.customization_type
  hyperparameters         = each.value.hyperparameters
  custom_model_kms_key_id = each.value.kms_key_id

  training_data_config {
    s3_uri = each.value.training_data_s3_uri
  }

  output_data_config {
    s3_uri = each.value.output_data_s3_uri
  }

  dynamic "validation_data_config" {
    for_each = length(each.value.validation_data_s3_uris) > 0 ? [each.value.validation_data_s3_uris] : []

    content {
      dynamic "validator" {
        for_each = validation_data_config.value

        content {
          s3_uri = validator.value
        }
      }
    }
  }

  dynamic "vpc_config" {
    for_each = length(each.value.vpc_subnet_ids) > 0 ? [each.value] : []

    content {
      subnet_ids         = vpc_config.value.vpc_subnet_ids
      security_group_ids = vpc_config.value.vpc_security_group_ids
    }
  }

  tags = merge(local.tags, {
    Name = coalesce(each.value.custom_model_name, "${var.name}-${each.key}")
  }, each.value.tags != null ? each.value.tags : {})
}
