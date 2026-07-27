################################################################################
# Provisioned Model Throughput
################################################################################

# A reservation with commitment_duration set bills for the full term and cannot
# be cancelled early, so changes to the committed term replace the reservation.
resource "aws_bedrock_provisioned_model_throughput" "this" {
  for_each = var.provisioned_model_throughputs

  provisioned_model_name = coalesce(each.value.provisioned_model_name, "${var.name}-${each.key}")
  model_arn              = each.value.model_arn
  model_units            = each.value.model_units
  commitment_duration    = each.value.commitment_duration

  tags = merge(local.tags, {
    Name = coalesce(each.value.provisioned_model_name, "${var.name}-${each.key}")
  }, each.value.tags != null ? each.value.tags : {})
}
