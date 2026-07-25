################################################################################
# ECR Repository
#
# Optional. Holds images built for this service when the container runtime
# builds from source. The instance role gets pull permissions on it.
################################################################################

module "ecr" {
  count = var.ecr_repository_creation_enabled ? 1 : 0

  source = "../../containers/ecr"

  name = var.name
  tags = var.tags

  image_scan_on_push_enabled = var.ecr_scan_on_push_enabled
  force_delete_enabled       = var.ecr_force_deletion_enabled

  default_lifecycle_policy_enabled = true
}
