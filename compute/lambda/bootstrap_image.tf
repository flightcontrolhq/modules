################################################################################
# Bootstrap container image
#
# Lambda requires an Image package function to point at an image that already
# exists in private ECR. When this module owns the ECR repository and no initial
# image_uri is supplied, seed a tiny bootstrap image during the same apply so the
# function can be created before the first real deployment.
################################################################################

resource "terraform_data" "bootstrap_image" {
  count = local.create_bootstrap_image ? 1 : 0

  depends_on = [module.ecr]

  input = {
    image_uri       = local.bootstrap_image_uri
    image_tag       = local.bootstrap_image_tag
    platform        = local.bootstrap_image_platform
    region          = local.region
    repository_name = module.ecr[0].repository_name
  }

  triggers_replace = {
    image_uri = local.bootstrap_image_uri
    platform  = local.bootstrap_image_platform
    version   = "nodejs20-v4"
  }

  provisioner "local-exec" {
    quiet       = true
    interpreter = ["/bin/sh", "-c"]

    environment = {
      AWS_REGION           = local.region
      BOOTSTRAP_IMAGE_TAG  = local.bootstrap_image_tag
      BOOTSTRAP_PLATFORM   = local.bootstrap_image_platform
      BOOTSTRAP_REPOSITORY = module.ecr[0].repository_name
    }

    command = <<-EOT
      set -eu

      log() {
        printf '%s\n' "Lambda bootstrap image: $*"
      }

      AWSCLI_WORKDIR=""
      BOOTSTRAP_WORKDIR=""

      cleanup() {
        status=$?
        if [ -n "$BOOTSTRAP_WORKDIR" ]; then
          rm -rf "$BOOTSTRAP_WORKDIR"
        fi
        if [ -n "$AWSCLI_WORKDIR" ]; then
          rm -rf "$AWSCLI_WORKDIR"
        fi
        if [ "$status" -ne 0 ]; then
          printf "%s\n" "Lambda bootstrap image: failed with exit code $status" >&2
        fi
      }

      trap cleanup EXIT

      run_as_root() {
        if [ "$(id -u)" -eq 0 ]; then
          "$@"
        elif command -v sudo >/dev/null 2>&1 && sudo -n true >/dev/null 2>&1; then
          sudo -n "$@"
        else
          echo "Missing sudo/root access required to install AWS CLI for Lambda bootstrap image seeding." >&2
          exit 1
        fi
      }

      can_run_as_root() {
        [ "$(id -u)" -eq 0 ] || (command -v sudo >/dev/null 2>&1 && sudo -n true >/dev/null 2>&1)
      }

      require_command() {
        if ! command -v "$1" >/dev/null 2>&1; then
          echo "Missing required command for Lambda bootstrap image: $1" >&2
          exit 1
        fi
      }

      install_awscli_from_archive() {
        require_command python3

        AWSCLI_WORKDIR="$(mktemp -d)"
        export AWSCLI_WORKDIR

        log "installing awscli without root"
        python3 - "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" "$AWSCLI_WORKDIR/awscliv2.zip" "$AWSCLI_WORKDIR" <<'PY'
      import sys
      import urllib.request
      import zipfile

      urllib.request.urlretrieve(sys.argv[1], sys.argv[2])
      with zipfile.ZipFile(sys.argv[2]) as archive:
          archive.extractall(sys.argv[3])
      PY
        "$AWSCLI_WORKDIR/aws/install" -i "$AWSCLI_WORKDIR/aws-cli" -b "$AWSCLI_WORKDIR/bin" >/dev/null
        PATH="$AWSCLI_WORKDIR/bin:$PATH"
        export PATH
      }

      install_awscli() {
        if command -v aws >/dev/null 2>&1; then
          return
        fi

        log "installing awscli"
        if can_run_as_root && command -v dnf >/dev/null 2>&1; then
          run_as_root dnf install -y awscli
        elif can_run_as_root && command -v yum >/dev/null 2>&1; then
          run_as_root yum install -y awscli
        elif can_run_as_root && command -v apt-get >/dev/null 2>&1; then
          run_as_root apt-get update
          run_as_root env DEBIAN_FRONTEND=noninteractive apt-get install -y awscli
        else
          install_awscli_from_archive
        fi
      }

      file_sha256() {
        if command -v sha256sum >/dev/null 2>&1; then
          sha256sum "$1" | awk '{print $1}'
        elif command -v shasum >/dev/null 2>&1; then
          shasum -a 256 "$1" | awk '{print $1}'
        else
          echo "Missing required command for Lambda bootstrap image: sha256sum or shasum" >&2
          exit 1
        fi
      }

      file_size() {
        wc -c < "$1" | tr -d '[:space:]'
      }

      upload_blob() {
        blob_path="$1"
        blob_digest="$2"
        blob_size="$3"

        layer_status="$(aws ecr batch-check-layer-availability \
          --region "$AWS_REGION" \
          --repository-name "$BOOTSTRAP_REPOSITORY" \
          --layer-digests "$blob_digest" \
          --query 'layers[0].layerAvailability' \
          --output text 2>/dev/null || true)"

        if [ "$layer_status" = "AVAILABLE" ]; then
          return
        fi

        upload_id="$(aws ecr initiate-layer-upload \
          --region "$AWS_REGION" \
          --repository-name "$BOOTSTRAP_REPOSITORY" \
          --query uploadId \
          --output text)"

        last_byte=$((blob_size - 1))
        aws ecr upload-layer-part \
          --region "$AWS_REGION" \
          --repository-name "$BOOTSTRAP_REPOSITORY" \
          --upload-id "$upload_id" \
          --part-first-byte 0 \
          --part-last-byte "$last_byte" \
          --layer-part-blob "fileb://$blob_path" >/dev/null

        aws ecr complete-layer-upload \
          --region "$AWS_REGION" \
          --repository-name "$BOOTSTRAP_REPOSITORY" \
          --upload-id "$upload_id" \
          --layer-digests "$blob_digest" >/dev/null
      }

      wait_for_repository() {
        attempt=1
        while [ "$attempt" -le 30 ]; do
          if aws ecr describe-repositories \
            --region "$AWS_REGION" \
            --repository-names "$BOOTSTRAP_REPOSITORY" >/dev/null 2>&1; then
            return
          fi

          sleep 2
          attempt=$((attempt + 1))
        done

        echo "Timed out waiting for ECR repository: $BOOTSTRAP_REPOSITORY" >&2
        aws ecr describe-repositories \
          --region "$AWS_REGION" \
          --repository-names "$BOOTSTRAP_REPOSITORY" >/dev/null
      }

      case "$BOOTSTRAP_PLATFORM" in
        linux/amd64) BOOTSTRAP_ARCH=amd64 ;;
        linux/arm64) BOOTSTRAP_ARCH=arm64 ;;
        *)
          echo "Unsupported Lambda bootstrap image platform: $BOOTSTRAP_PLATFORM" >&2
          exit 1
          ;;
      esac

      log "starting bootstrap image seeding for $BOOTSTRAP_REPOSITORY:$BOOTSTRAP_IMAGE_TAG on $BOOTSTRAP_PLATFORM"

      require_command awk
      require_command gzip
      require_command mktemp
      require_command tar
      require_command tr
      require_command wc
      install_awscli

      log "waiting for ECR repository $BOOTSTRAP_REPOSITORY"
      wait_for_repository

      if aws ecr describe-images \
        --region "$AWS_REGION" \
        --repository-name "$BOOTSTRAP_REPOSITORY" \
        --image-ids imageTag="$BOOTSTRAP_IMAGE_TAG" >/dev/null 2>&1; then
        exit 0
      fi

      BOOTSTRAP_WORKDIR="$(mktemp -d)"

      mkdir -p "$BOOTSTRAP_WORKDIR/layer/var/task"
      printf '%s\n' 'exports.handler = async () => ({ statusCode: 200, body: "ravion lambda bootstrap" });' > "$BOOTSTRAP_WORKDIR/layer/var/task/index.js"

      tar -C "$BOOTSTRAP_WORKDIR/layer" -cf "$BOOTSTRAP_WORKDIR/layer.tar" var
      gzip -n -c "$BOOTSTRAP_WORKDIR/layer.tar" > "$BOOTSTRAP_WORKDIR/layer.tar.gz"

      layer_diff_digest="sha256:$(file_sha256 "$BOOTSTRAP_WORKDIR/layer.tar")"
      layer_digest="sha256:$(file_sha256 "$BOOTSTRAP_WORKDIR/layer.tar.gz")"
      layer_size="$(file_size "$BOOTSTRAP_WORKDIR/layer.tar.gz")"

      printf '%s\n' '{"architecture":"'"$BOOTSTRAP_ARCH"'","os":"linux","config":{"Cmd":["index.handler"],"WorkingDir":"/var/task","Labels":{"dev.ravion.bootstrap":"lambda"}},"rootfs":{"type":"layers","diff_ids":["'"$layer_diff_digest"'"]},"history":[{"created":"1970-01-01T00:00:00Z","created_by":"ravion lambda bootstrap","comment":"Add sample Lambda handler"}]}' > "$BOOTSTRAP_WORKDIR/config.json"

      config_digest="sha256:$(file_sha256 "$BOOTSTRAP_WORKDIR/config.json")"
      config_size="$(file_size "$BOOTSTRAP_WORKDIR/config.json")"

      printf '%s\n' '{"schemaVersion":2,"mediaType":"application/vnd.docker.distribution.manifest.v2+json","config":{"mediaType":"application/vnd.docker.container.image.v1+json","size":'"$config_size"',"digest":"'"$config_digest"'"},"layers":[{"mediaType":"application/vnd.docker.image.rootfs.diff.tar.gzip","size":'"$layer_size"',"digest":"'"$layer_digest"'"}]}' > "$BOOTSTRAP_WORKDIR/manifest.json"

      log "uploading bootstrap image blobs"
      upload_blob "$BOOTSTRAP_WORKDIR/config.json" "$config_digest" "$config_size"
      upload_blob "$BOOTSTRAP_WORKDIR/layer.tar.gz" "$layer_digest" "$layer_size"

      log "publishing bootstrap image manifest"
      aws ecr put-image \
        --region "$AWS_REGION" \
        --repository-name "$BOOTSTRAP_REPOSITORY" \
        --image-tag "$BOOTSTRAP_IMAGE_TAG" \
        --image-manifest "file://$BOOTSTRAP_WORKDIR/manifest.json" >/dev/null
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
