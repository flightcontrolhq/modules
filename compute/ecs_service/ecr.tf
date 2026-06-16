################################################################################
# ECR Repository
#
# Optional. Creates a repository for this service's container image when
# var.ecr_repository_creation_enabled is true. The service's execution role already has ECR pull
# permissions via AmazonECSTaskExecutionRolePolicy, so no additional wiring
# is needed for the task definition to pull from it.
################################################################################

module "ecr" {
  count = var.ecr_repository_creation_enabled ? 1 : 0

  source = "../../containers/ecr"

  name = var.ecr_repository_name != null ? var.ecr_repository_name : var.name
  tags = var.tags

  image_tag_mutability = var.ecr_image_tag_mutability
  scan_on_push         = var.ecr_scan_on_push_enabled
  force_delete         = var.ecr_force_deletion_enabled

  default_lifecycle_policy_enabled = var.ecr_default_lifecycle_policy_enabled
}
