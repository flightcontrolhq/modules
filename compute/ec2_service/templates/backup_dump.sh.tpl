#!/bin/bash
set -euo pipefail

ACTION="$${1:-backup-now}"
SERVICE_NAME="${name}"
LOG_PATH="${backup_dump_log_path}"
DESTINATION="${backup_dump_destination}"
BUCKET="${backup_dump_bucket_name}"
ARTIFACT_PREFIX="${backup_dump_s3_prefix}"
EFS_ROOT="${backup_dump_efs_root}"
RETENTION_DAYS="${backup_dump_retention_days}"
DUMP_COMMAND=$(printf '%s' '${backup_dump_command_base64}' | base64 -d)
RESTORE_COMMAND=$(printf '%s' '${backup_dump_restore_command_base64}' | base64 -d)

mkdir -p "$(dirname "$LOG_PATH")"
exec >> >(tee -a "$LOG_PATH") 2>&1

log() {
  printf '[%s] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*"
}

instance_id() {
  local token
  token=$(curl -fsS -X PUT -H "X-aws-ec2-metadata-token-ttl-seconds: 60" \
    http://169.254.169.254/latest/api/token 2>/dev/null || true)
  if [ -n "$token" ]; then
    curl -fsS -H "X-aws-ec2-metadata-token: $token" \
      http://169.254.169.254/latest/meta-data/instance-id 2>/dev/null || true
  fi
}

write_manifest() {
  local completed_at completed_epoch files instance
  completed_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  completed_epoch=$(date +%s)
  instance=$(instance_id)
  files=$(find "$RAVION_BACKUP_DIR" -type f ! -name manifest.json -printf '%P\n' | sort | jq -R -s 'split("\n") | map(select(length > 0))')
  jq -n \
    --arg completed_at "$completed_at" \
    --arg instance_id "$${instance:-unknown}" \
    --argjson completed_at_epoch "$completed_epoch" \
    --argjson files "$files" \
    '{completed_at: $completed_at, completed_at_epoch: $completed_at_epoch, instance_id: $instance_id, files: $files}' \
    > "$RAVION_BACKUP_DIR/manifest.json"
  printf '%s\n' "$completed_at"
}

upload_backup() {
  local timestamp artifact_path completed_at
  completed_at=$(write_manifest)
  timestamp=$(date -u +%Y%m%dT%H%M%SZ)
  artifact_path="$${ARTIFACT_PREFIX}/$${timestamp}"

  if [ "$DESTINATION" = "s3" ]; then
    aws s3 cp "$${RAVION_BACKUP_DIR}/" "s3://$${BUCKET}/$${artifact_path}/" --recursive --exclude manifest.json
    aws s3 cp "$${RAVION_BACKUP_DIR}/manifest.json" "s3://$${BUCKET}/$${artifact_path}/manifest.json"
  else
    mkdir -p "$EFS_ROOT"
    mkdir -p "$${EFS_ROOT}/$${timestamp}"
    while IFS= read -r -d '' file; do
      relative="$${file#"$${RAVION_BACKUP_DIR}/"}"
      relative_dir=$(dirname "$relative")
      mkdir -p "$${EFS_ROOT}/$${timestamp}/$${relative_dir}"
      cp -a "$file" "$${EFS_ROOT}/$${timestamp}/$${relative}"
    done < <(find "$RAVION_BACKUP_DIR" -type f ! -name manifest.json -print0)
    cp -a "$${RAVION_BACKUP_DIR}/manifest.json" "$${EFS_ROOT}/$${timestamp}/manifest.json"
  fi

  if [ "$DESTINATION" = "s3" ]; then
    if ! prune_s3_backups; then
      log "WARNING: logical dump uploaded successfully, but S3 retention cleanup failed"
    fi
  elif ! prune_efs_backups; then
    log "WARNING: logical dump stored successfully, but EFS retention cleanup failed"
  fi

  log "RAVION_BACKUP_SUCCESS completed_at=$${completed_at} artifact=$${artifact_path}"
}

prune_s3_backups() {
  local cutoff listing keys key manifest epoch manifest_dir
  cutoff=$(( $(date +%s) - RETENTION_DAYS * 86400 ))
  if ! listing=$(aws s3api list-objects-v2 --bucket "$${BUCKET}" --prefix "$${ARTIFACT_PREFIX}/" --output json); then
    return 1
  fi
  if ! keys=$(jq -r '.Contents[]?.Key | select(endswith("/manifest.json"))' <<< "$listing"); then
    return 1
  fi
  while IFS= read -r key; do
    [ -n "$key" ] || continue
    manifest=$(mktemp)
    if ! aws s3 cp "s3://$${BUCKET}/$${key}" "$manifest" >/dev/null; then
      rm -f "$manifest"
      return 1
    fi
    if ! epoch=$(jq -r '.completed_at_epoch // 0' "$manifest"); then
      rm -f "$manifest"
      return 1
    fi
    if [ "$epoch" -gt 0 ] && [ "$epoch" -lt "$cutoff" ]; then
      manifest_dir="$${key%/manifest.json}"
      if ! aws s3 rm "s3://$${BUCKET}/$${manifest_dir}/" --recursive; then
        rm -f "$manifest"
        return 1
      fi
    fi
    rm -f "$manifest"
  done <<< "$keys"
}

prune_efs_backups() {
  find "$${EFS_ROOT}" -mindepth 1 -maxdepth 1 -type d -mtime "+$${RETENTION_DAYS}" -exec rm -rf {} +
}

find_s3_manifest() {
  local best_epoch=0 best_key="" key manifest epoch listing keys
  if ! listing=$(aws s3api list-objects-v2 --bucket "$${BUCKET}" --prefix "$${ARTIFACT_PREFIX}/" --output json); then
    return 2
  fi
  if ! keys=$(jq -r '.Contents[]?.Key | select(endswith("/manifest.json"))' <<< "$listing"); then
    return 2
  fi
  while IFS= read -r key; do
    [ -n "$key" ] || continue
    manifest=$(mktemp)
    if ! aws s3 cp "s3://$${BUCKET}/$${key}" "$manifest" >/dev/null; then
      rm -f "$manifest"
      return 2
    fi
    if ! epoch=$(jq -r '.completed_at_epoch // 0' "$manifest"); then
      rm -f "$manifest"
      return 2
    fi
    if [ "$epoch" -gt "$best_epoch" ]; then
      best_epoch="$epoch"
      best_key="$key"
    fi
    rm -f "$manifest"
  done <<< "$keys"
  [ -n "$best_key" ] || return 1
  printf '%s\n' "$best_key"
}

find_efs_manifest() {
  local best_epoch=0 best_manifest="" manifest epoch manifests
  mkdir -p "$EFS_ROOT"
  if ! manifests=$(find "$EFS_ROOT" -type f -name manifest.json 2>/dev/null); then
    return 2
  fi
  while IFS= read -r manifest; do
    if ! epoch=$(jq -r '.completed_at_epoch // 0' "$manifest"); then
      return 2
    fi
    if [ "$epoch" -gt "$best_epoch" ]; then
      best_epoch="$epoch"
      best_manifest="$manifest"
    fi
  done <<< "$manifests"
  [ -n "$best_manifest" ] || return 1
  printf '%s\n' "$best_manifest"
}

restore_backup() {
  local manifest_ref manifest_dir restore_dir completed_at completed_epoch age_hours
  mkdir -p /var/lib/ravion
  restore_dir=$(mktemp -d "/var/lib/ravion/$${SERVICE_NAME}-restore.XXXXXX")

  if [ "$DESTINATION" = "s3" ]; then
    if manifest_ref=$(find_s3_manifest); then
      :
    elif [ "$?" -eq 1 ]; then
      log "No logical backup manifest was found; treating this as a fresh service and continuing without restore"
      return 0
    else
      log "FATAL: no logical backup manifest was found; application startup is blocked"
      return 1
    fi
    manifest=$(mktemp)
    aws s3 cp "s3://$${BUCKET}/$${manifest_ref}" "$manifest" >/dev/null
    manifest_dir="$${manifest_ref%/manifest.json}"
    aws s3 cp "s3://$${BUCKET}/$${manifest_dir}/" "$restore_dir/" --recursive
  else
    if manifest_ref=$(find_efs_manifest); then
      :
    elif [ "$?" -eq 1 ]; then
      log "No logical backup manifest was found; treating this as a fresh service and continuing without restore"
      return 0
    else
      log "FATAL: no logical backup manifest was found; application startup is blocked"
      return 1
    fi
    manifest="$manifest_ref"
    manifest_dir="$${manifest_ref%/manifest.json}"
    cp -a "$manifest_dir/." "$restore_dir/"
  fi

  completed_at=$(jq -r '.completed_at' "$manifest")
  completed_epoch=$(jq -r '.completed_at_epoch' "$manifest")
  age_hours=$(( ( $(date +%s) - completed_epoch ) / 3600 ))
  log "Discovered logical backup completed_at=$${completed_at}, age_hours=$${age_hours}, manifest=$${manifest_ref}"

  if [ -n '${backup_max_age_hours}' ] && [ "$age_hours" -gt '${backup_max_age_hours}' ]; then
    log "FATAL: newest logical backup is $${age_hours} hours old, exceeding backup_max_age_hours=${backup_max_age_hours}; application startup is blocked"
    return 1
  fi

  export RAVION_BACKUP_DIR="$restore_dir"
  bash -lc "$RESTORE_COMMAND"
  log "RAVION_BACKUP_RESTORE_SUCCESS completed_at=$${completed_at} age_hours=$${age_hours}"
}

run_dump() {
  local staging
  [ -n "$DUMP_COMMAND" ] || {
    log "FATAL: backup_dump_command is empty"
    return 1
  }
  mkdir -p /var/lib/ravion
  staging=$(mktemp -d "/var/lib/ravion/$${SERVICE_NAME}-dump.XXXXXX")
  trap 'rm -rf "$staging"' EXIT
  export RAVION_BACKUP_DIR="$staging"
  bash -lc "$DUMP_COMMAND"
  upload_backup
}

case "$ACTION" in
  backup-now)
    run_dump
    ;;
  restore-latest)
    [ -n "$RESTORE_COMMAND" ] || {
      log "FATAL: backup_dump_restore_command is empty"
      exit 1
    }
    restore_backup
    ;;
  *)
    log "FATAL: unsupported backup action: $ACTION"
    exit 1
    ;;
esac
