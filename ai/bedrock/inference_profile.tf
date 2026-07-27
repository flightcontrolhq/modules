################################################################################
# Application Inference Profiles
################################################################################

resource "aws_bedrock_inference_profile" "this" {
  for_each = var.inference_profiles

  name        = coalesce(each.value.name, "${var.name}-${each.key}")
  description = each.value.description

  model_source {
    copy_from = each.value.copy_from
  }

  tags = merge(local.tags, {
    Name = coalesce(each.value.name, "${var.name}-${each.key}")
  }, each.value.tags != null ? each.value.tags : {})
}
