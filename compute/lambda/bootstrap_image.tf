################################################################################
# Bootstrap container image
#
# Lambda requires an Image package function to point at an image that already
# exists in private ECR. When this module owns the ECR repository and no initial
# image_uri is supplied, seed a tiny Lambda-compatible image during the same
# apply so the function can be created before the first real deployment.
################################################################################

resource "terraform_data" "bootstrap_image" {
  count = local.create_bootstrap_image ? 1 : 0

  input = {
    image_uri       = local.bootstrap_image_uri
    image_tag       = local.bootstrap_image_tag
    platform        = local.bootstrap_image_platform
    region          = local.region
    registry        = split("/", module.ecr[0].repository_url)[0]
    repository_name = module.ecr[0].repository_name
  }

  triggers_replace = {
    image_uri = local.bootstrap_image_uri
    platform  = local.bootstrap_image_platform
    version   = "nodejs20-v1"
  }

  provisioner "local-exec" {
    interpreter = ["/bin/sh", "-c"]

    environment = {
      AWS_REGION             = local.region
      BOOTSTRAP_ECR_REGISTRY = split("/", module.ecr[0].repository_url)[0]
      BOOTSTRAP_IMAGE_TAG    = local.bootstrap_image_tag
      BOOTSTRAP_IMAGE_URI    = local.bootstrap_image_uri
      BOOTSTRAP_PLATFORM     = local.bootstrap_image_platform
      BOOTSTRAP_REPOSITORY   = module.ecr[0].repository_name
    }

    command = <<-EOT
      set -eu

      for binary in aws docker mktemp; do
        if ! command -v "$binary" >/dev/null 2>&1; then
          echo "Missing required command for Lambda bootstrap image: $binary" >&2
          exit 1
        fi
      done

      aws ecr wait repository-exists \
        --region "$AWS_REGION" \
        --repository-names "$BOOTSTRAP_REPOSITORY"

      if aws ecr describe-images \
        --region "$AWS_REGION" \
        --repository-name "$BOOTSTRAP_REPOSITORY" \
        --image-ids imageTag="$BOOTSTRAP_IMAGE_TAG" >/dev/null 2>&1; then
        exit 0
      fi

      BOOTSTRAP_WORKDIR="$(mktemp -d)"
      trap 'rm -rf "$BOOTSTRAP_WORKDIR"' EXIT

      cat > "$BOOTSTRAP_WORKDIR/Dockerfile" <<'DOCKERFILE'
FROM public.ecr.aws/lambda/nodejs:20
RUN printf '%s\n' 'exports.handler = async () => ({ statusCode: 200, body: "ravion lambda bootstrap" });' > /var/task/index.js
CMD ["index.handler"]
DOCKERFILE

      aws ecr get-login-password --region "$AWS_REGION" | docker login \
        --username AWS \
        --password-stdin "$BOOTSTRAP_ECR_REGISTRY"

      if docker buildx version >/dev/null 2>&1; then
        docker buildx build \
          --platform "$BOOTSTRAP_PLATFORM" \
          --provenance=false \
          --tag "$BOOTSTRAP_IMAGE_URI" \
          --push \
          "$BOOTSTRAP_WORKDIR"
      else
        docker build \
          --platform "$BOOTSTRAP_PLATFORM" \
          --tag "$BOOTSTRAP_IMAGE_URI" \
          "$BOOTSTRAP_WORKDIR"
        docker push "$BOOTSTRAP_IMAGE_URI"
      fi
    EOT
  }

  provisioner "local-exec" {
    when        = destroy
    on_failure  = continue
    interpreter = ["/bin/sh", "-c"]

    environment = {
      AWS_REGION           = self.input.region
      BOOTSTRAP_IMAGE_TAG  = self.input.image_tag
      BOOTSTRAP_REPOSITORY = self.input.repository_name
    }

    command = <<-EOT
      set -eu

      if ! command -v aws >/dev/null 2>&1; then
        exit 0
      fi

      aws ecr batch-delete-image \
        --region "$AWS_REGION" \
        --repository-name "$BOOTSTRAP_REPOSITORY" \
        --image-ids imageTag="$BOOTSTRAP_IMAGE_TAG" >/dev/null 2>&1 || true
    EOT
  }
}
