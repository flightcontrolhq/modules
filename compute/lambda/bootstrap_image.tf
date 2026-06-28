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
    version   = "nodejs20-v3"
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

      install_optional_skopeo() {
        if command -v skopeo >/dev/null 2>&1; then
          return 0
        fi

        log "installing skopeo"
        if command -v dnf >/dev/null 2>&1; then
          if run_as_root dnf install -y skopeo; then
            return 0
          fi
        elif command -v yum >/dev/null 2>&1; then
          if run_as_root yum install -y skopeo; then
            return 0
          fi
        elif command -v apt-get >/dev/null 2>&1; then
          if run_as_root apt-get update; then
            if run_as_root env DEBIAN_FRONTEND=noninteractive apt-get install -y skopeo; then
              return 0
            fi
          fi
        fi

        log "skopeo is not available; falling back to docker"
        return 1
      }

      install_optional_python3() {
        if command -v python3 >/dev/null 2>&1; then
          return 0
        fi

        log "installing python3"
        if command -v dnf >/dev/null 2>&1; then
          if run_as_root dnf install -y python3; then
            return 0
          fi
        elif command -v yum >/dev/null 2>&1; then
          if run_as_root yum install -y python3; then
            return 0
          fi
        elif command -v apt-get >/dev/null 2>&1; then
          if run_as_root apt-get update; then
            if run_as_root env DEBIAN_FRONTEND=noninteractive apt-get install -y python3; then
              return 0
            fi
          fi
        fi

        log "python3 is not available; falling back to docker"
        return 1
      }

      install_required_docker() {
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

      copy_bootstrap_with_skopeo() {
        if ! command -v skopeo >/dev/null 2>&1 || ! command -v python3 >/dev/null 2>&1; then
          return 1
        fi

        case "$BOOTSTRAP_PLATFORM" in
          linux/amd64) BOOTSTRAP_ARCH=amd64 ;;
          linux/arm64) BOOTSTRAP_ARCH=arm64 ;;
          *)
            echo "Unsupported Lambda bootstrap image platform: $BOOTSTRAP_PLATFORM" >&2
            return 1
            ;;
        esac

        BOOTSTRAP_OCI_DIR="$BOOTSTRAP_WORKDIR/oci"
        BOOTSTRAP_SOURCE_IMAGE="docker://public.ecr.aws/lambda/nodejs:20"

        log "copying Lambda base image with skopeo"
        skopeo copy \
          --override-os linux \
          --override-arch "$BOOTSTRAP_ARCH" \
          "$BOOTSTRAP_SOURCE_IMAGE" \
          "oci:$BOOTSTRAP_OCI_DIR:ravion-bootstrap-base"

        BOOTSTRAP_OCI_DIR="$BOOTSTRAP_OCI_DIR" python3 <<'PYTHON'
import gzip
import hashlib
import io
import json
import os
import tarfile
from pathlib import Path

oci_dir = Path(os.environ["BOOTSTRAP_OCI_DIR"])
blobs_dir = oci_dir / "blobs" / "sha256"
index_path = oci_dir / "index.json"


def load_blob(digest):
    algorithm, value = digest.split(":", 1)
    if algorithm != "sha256":
        raise ValueError(f"Unsupported digest algorithm: {algorithm}")
    return (blobs_dir / value).read_bytes()


def write_blob(payload):
    digest = hashlib.sha256(payload).hexdigest()
    (blobs_dir / digest).write_bytes(payload)
    return f"sha256:{digest}", len(payload)


index = json.loads(index_path.read_text())
if not index.get("manifests"):
    raise ValueError("OCI layout does not contain an image manifest")

manifest_descriptor = index["manifests"][0]
manifest = json.loads(load_blob(manifest_descriptor["digest"]))
config = json.loads(load_blob(manifest["config"]["digest"]))

handler_source = (
    b'exports.handler = async () => ({ statusCode: 200, body: "ravion lambda bootstrap" });\n'
)

layer_buffer = io.BytesIO()
with tarfile.open(fileobj=layer_buffer, mode="w") as layer_tar:
    info = tarfile.TarInfo("var/task/index.js")
    info.size = len(handler_source)
    info.mode = 0o644
    info.uid = 0
    info.gid = 0
    info.mtime = 0
    layer_tar.addfile(info, io.BytesIO(handler_source))

layer_bytes = layer_buffer.getvalue()
layer_diff_id = hashlib.sha256(layer_bytes).hexdigest()
compressed_layer_buffer = io.BytesIO()
with gzip.GzipFile(fileobj=compressed_layer_buffer, mode="wb", mtime=0) as gzip_file:
    gzip_file.write(layer_bytes)

compressed_layer = compressed_layer_buffer.getvalue()
layer_digest, layer_size = write_blob(compressed_layer)

config.setdefault("config", {})["Cmd"] = ["index.handler"]
config["config"]["WorkingDir"] = "/var/task"
config.setdefault("rootfs", {}).setdefault("diff_ids", []).append(f"sha256:{layer_diff_id}")
config.setdefault("history", []).append(
    {
        "created": "1970-01-01T00:00:00Z",
        "created_by": "ravion lambda bootstrap",
        "comment": "Add sample Lambda handler",
    }
)

config_payload = json.dumps(config, separators=(",", ":"), sort_keys=True).encode()
config_digest, config_size = write_blob(config_payload)
manifest["config"]["digest"] = config_digest
manifest["config"]["size"] = config_size

manifest_media_type = manifest.get("mediaType", "")
if manifest_media_type.startswith("application/vnd.oci"):
    layer_media_type = "application/vnd.oci.image.layer.v1.tar+gzip"
else:
    layer_media_type = "application/vnd.docker.image.rootfs.diff.tar.gzip"

manifest.setdefault("layers", []).append(
    {
        "mediaType": layer_media_type,
        "digest": layer_digest,
        "size": layer_size,
    }
)

manifest_payload = json.dumps(manifest, separators=(",", ":"), sort_keys=True).encode()
manifest_digest, manifest_size = write_blob(manifest_payload)
manifest_descriptor["digest"] = manifest_digest
manifest_descriptor["size"] = manifest_size
manifest_descriptor["mediaType"] = manifest.get(
    "mediaType", manifest_descriptor.get("mediaType", "application/vnd.oci.image.manifest.v1+json")
)
manifest_descriptor.setdefault("annotations", {})[
    "org.opencontainers.image.ref.name"
] = "ravion-bootstrap"

index_path.write_text(json.dumps(index, separators=(",", ":"), sort_keys=True))
PYTHON

        ECR_PASSWORD="$(aws ecr get-login-password --region "$AWS_REGION")"
        skopeo copy \
          --dest-creds "AWS:$ECR_PASSWORD" \
          "oci:$BOOTSTRAP_OCI_DIR:ravion-bootstrap" \
          "docker://$BOOTSTRAP_IMAGE_URI"
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

      if install_optional_python3 && install_optional_skopeo; then
        if copy_bootstrap_with_skopeo; then
          exit 0
        fi
        log "skopeo image copy failed; falling back to docker"
      fi

      install_required_docker
      select_docker_command

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
