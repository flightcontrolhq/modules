################################################################################
# ECR Repository
#
# Optional. Creates a repository for Lambda container image builds when
# Ravion owns the Dockerfile or Nixpacks image build.
################################################################################

module "ecr" {
  count = var.ecr_repository_creation_enabled ? 1 : 0

  source = "../../containers/ecr"

  name = var.ecr_repository_name != null ? var.ecr_repository_name : var.name
  tags = local.tags

  image_tag_mutability       = var.ecr_image_tag_mutability
  image_scan_on_push_enabled = var.ecr_scan_on_push_enabled
  force_delete_enabled       = var.ecr_force_deletion_enabled

  default_lifecycle_policy_enabled = var.ecr_default_lifecycle_policy_enabled
}
