################################################################################
# Model Access
################################################################################

# Some foundation models, such as the Anthropic models, require an approved use
# case submission before their agreements can be accepted.
resource "aws_bedrock_use_case_for_model_access" "this" {
  count = var.model_access_use_case_form_data == null ? 0 : 1

  form_data = var.model_access_use_case_form_data
}

# Resolves the current offer for each model so callers do not have to hardcode
# an offer token that AWS rotates.
data "aws_bedrock_foundation_model_agreement_offers" "this" {
  for_each = {
    for key, agreement in var.foundation_model_agreements : key => agreement
    if agreement.offer_token == null
  }

  model_id   = each.value.model_id
  offer_type = each.value.offer_type
}

resource "aws_bedrock_foundation_model_agreement" "this" {
  for_each = var.foundation_model_agreements

  model_id = each.value.model_id
  offer_token = try(
    coalesce(
      each.value.offer_token,
      try(data.aws_bedrock_foundation_model_agreement_offers.this[each.key].offers[0].offer_token, null)
    ),
    null
  )

  lifecycle {
    precondition {
      condition = anytrue([
        each.value.offer_token != null,
        length(try(data.aws_bedrock_foundation_model_agreement_offers.this[each.key].offers, [])) > 0,
      ])
      error_message = "No ${each.value.offer_type} offer is available for model '${each.value.model_id}' in this region. Check the model ID and region, or set offer_token explicitly."
    }
  }

  depends_on = [aws_bedrock_use_case_for_model_access.this]
}
