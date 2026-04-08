################################################################################
# ECR Repository
#
# Optional. Creates a repository for this service's container image when
# var.enable_ecr is true. The service's execution role already has ECR pull
# permissions via AmazonECSTaskExecutionRolePolicy, so no additional wiring
# is needed for the task definition to pull from it.
################################################################################

module "ecr" {
  count = var.enable_ecr ? 1 : 0

  source = "../../containers/ecr"

  name = var.ecr_repository_name != null ? var.ecr_repository_name : var.name
  tags = var.tags

  image_tag_mutability = var.ecr_image_tag_mutability
  scan_on_push         = var.ecr_scan_on_push
  force_delete         = var.ecr_force_delete

  enable_default_lifecycle_policy = var.ecr_enable_default_lifecycle_policy
}
