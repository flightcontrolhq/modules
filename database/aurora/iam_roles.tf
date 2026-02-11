################################################################################
# IAM Role Associations
################################################################################

resource "aws_rds_cluster_role_association" "this" {
  for_each = var.iam_role_associations

  db_cluster_identifier = aws_rds_cluster.this.cluster_identifier
  role_arn              = each.value.role_arn
  feature_name          = each.value.feature_name
}
