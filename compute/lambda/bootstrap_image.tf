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
    version   = "nodejs20-v2"
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

      log() {
        printf '%s\n' "Lambda bootstrap image: $*"
      }

      run_as_root() {
        if [ "$(id -u)" -eq 0 ]; then
          "$@"
        elif command -v sudo >/dev/null 2>&1 && sudo -n true >/dev/null 2>&1; then
          sudo -n "$@"
        else
          echo "Missing sudo/root access required to prepare Lambda bootstrap image tooling." >&2
          exit 1
        fi
      }

      install_awscli() {
        if command -v aws >/dev/null 2>&1; then
          return
        fi

        log "installing awscli"
        if command -v dnf >/dev/null 2>&1; then
          run_as_root dnf install -y awscli
        elif command -v yum >/dev/null 2>&1; then
          run_as_root yum install -y awscli
        elif command -v apt-get >/dev/null 2>&1; then
          run_as_root apt-get update
          run_as_root env DEBIAN_FRONTEND=noninteractive apt-get install -y awscli
        else
          echo "Missing aws command and no supported package manager found." >&2
          exit 1
        fi
      }

      install_docker() {
        if command -v docker >/dev/null 2>&1; then
          return
        fi

        log "installing docker"
        if command -v dnf >/dev/null 2>&1; then
          run_as_root dnf install -y docker || run_as_root dnf install -y moby-engine
        elif command -v yum >/dev/null 2>&1; then
          run_as_root yum install -y docker
        elif command -v apt-get >/dev/null 2>&1; then
          run_as_root apt-get update
          run_as_root env DEBIAN_FRONTEND=noninteractive apt-get install -y docker.io
        else
          echo "Missing docker command and no supported package manager found." >&2
          exit 1
        fi
      }

      docker_cmd() {
        if [ "$RAVION_BOOTSTRAP_DOCKER_SUDO" = "1" ]; then
          sudo -n docker "$@"
        else
          docker "$@"
        fi
      }

      select_docker_command() {
        if docker info >/dev/null 2>&1; then
          RAVION_BOOTSTRAP_DOCKER_SUDO=0
          return
        fi

        if command -v sudo >/dev/null 2>&1 && sudo -n docker info >/dev/null 2>&1; then
          RAVION_BOOTSTRAP_DOCKER_SUDO=1
          return
        fi

        if command -v systemctl >/dev/null 2>&1; then
          run_as_root systemctl start docker >/dev/null 2>&1 || true
        fi

        if ! docker info >/dev/null 2>&1 && command -v service >/dev/null 2>&1; then
          run_as_root service docker start >/dev/null 2>&1 || true
        fi

        if ! docker info >/dev/null 2>&1 && command -v dockerd >/dev/null 2>&1; then
          run_as_root sh -c 'nohup dockerd >/tmp/ravion-lambda-bootstrap-dockerd.log 2>&1 &' || true
        fi

        for _ in 1 2 3 4 5 6 7 8 9 10; do
          if docker info >/dev/null 2>&1; then
            RAVION_BOOTSTRAP_DOCKER_SUDO=0
            return
          fi
          if command -v sudo >/dev/null 2>&1 && sudo -n docker info >/dev/null 2>&1; then
            RAVION_BOOTSTRAP_DOCKER_SUDO=1
            return
          fi
          sleep 2
        done

        echo "Docker is installed but the Docker daemon is not reachable." >&2
        if [ -f /tmp/ravion-lambda-bootstrap-dockerd.log ]; then
          tail -n 40 /tmp/ravion-lambda-bootstrap-dockerd.log >&2 || true
        fi
        exit 1
      }

      if ! command -v mktemp >/dev/null 2>&1; then
        echo "Missing required command for Lambda bootstrap image: mktemp" >&2
        exit 1
      fi

      install_awscli
      install_docker
      select_docker_command

      log "waiting for ECR repository $BOOTSTRAP_REPOSITORY"
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

      cat > "$BOOTSTRAP_WORKDIR/index.js" <<'JAVASCRIPT'
exports.handler = async () => ({ statusCode: 200, body: "ravion lambda bootstrap" });
JAVASCRIPT

      cat > "$BOOTSTRAP_WORKDIR/Dockerfile" <<'DOCKERFILE'
FROM public.ecr.aws/lambda/nodejs:20
COPY index.js /var/task/index.js
CMD ["index.handler"]
DOCKERFILE

      log "logging in to ECR"
      aws ecr get-login-password --region "$AWS_REGION" | docker_cmd login \
        --username AWS \
        --password-stdin "$BOOTSTRAP_ECR_REGISTRY"

      log "building and pushing $BOOTSTRAP_IMAGE_URI"
      if docker_cmd buildx version >/dev/null 2>&1; then
        docker_cmd buildx build \
          --platform "$BOOTSTRAP_PLATFORM" \
          --provenance=false \
          --tag "$BOOTSTRAP_IMAGE_URI" \
          --push \
          "$BOOTSTRAP_WORKDIR"
      else
        docker_cmd build \
          --platform "$BOOTSTRAP_PLATFORM" \
          --tag "$BOOTSTRAP_IMAGE_URI" \
          "$BOOTSTRAP_WORKDIR"
        docker_cmd push "$BOOTSTRAP_IMAGE_URI"
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
