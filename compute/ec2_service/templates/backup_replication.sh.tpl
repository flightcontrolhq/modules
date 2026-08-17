#!/bin/bash
set -euo pipefail

LITESTREAM_VERSION="${backup_replication_version}"
LITESTREAM_ARCHIVE=""
LITESTREAM_SHA256=""
case "$(uname -m)" in
  x86_64)
    LITESTREAM_ARCHIVE="litestream-$${LITESTREAM_VERSION}-linux-x86_64.tar.gz"
    LITESTREAM_SHA256="e10049d206079ef12dc623d859780b2f7a06d32418dc1939004381abbafd01f1"
    ;;
  aarch64)
    LITESTREAM_ARCHIVE="litestream-$${LITESTREAM_VERSION}-linux-arm64.tar.gz"
    LITESTREAM_SHA256="14f496b640767279e7e9eca71218150d9251bf2d488e9fae6f012543f50a20ec"
    ;;
  *)
    echo "FATAL: Litestream replication requires an x86_64 or arm64 instance." >&2
    exit 1
    ;;
esac

LITESTREAM_URL="https://github.com/benbjohnson/litestream/releases/download/v$${LITESTREAM_VERSION}/$${LITESTREAM_ARCHIVE}"
LITESTREAM_TMP=$(mktemp)
trap 'rm -f "$LITESTREAM_TMP"' EXIT
curl -fsSL "$LITESTREAM_URL" -o "$LITESTREAM_TMP"
printf '%s  %s\n' "$LITESTREAM_SHA256" "$LITESTREAM_TMP" | sha256sum -c -
tar -xzf "$LITESTREAM_TMP" -C /usr/local/bin litestream
chmod 755 /usr/local/bin/litestream

cat > /etc/litestream.yml <<'LITESTREAM_CONFIG'
dbs:
  - path: ${backup_replication_database_path}
    replicas:
      - type: s3
        bucket: ${backup_replication_bucket_name}
        path: ${backup_replication_s3_prefix}
        region: ${region}
        snapshot-interval: ${backup_replication_snapshot_interval}
        retention: ${backup_replication_retention}
LITESTREAM_CONFIG
chmod 600 /etc/litestream.yml

%{ if backup_replication_restore_enabled ~}
if [ ! -f "${backup_replication_restore_marker}" ]; then
  REPLICA_URL="s3://${backup_replication_bucket_name}/${backup_replication_s3_prefix}"
  RESTORE_DIR=$(mktemp -d)
  RESTORE_OUTPUT=$(mktemp)
  trap 'rm -rf "$RESTORE_DIR" "$RESTORE_OUTPUT"' EXIT
  if ! /usr/local/bin/litestream restore -if-db-not-exists -if-replica-exists -json -o "$RESTORE_DIR/database" "$REPLICA_URL" >"$RESTORE_OUTPUT"; then
    echo "FATAL: Litestream replica discovery or restore failed; application startup is blocked." >&2
    exit 1
  fi
  if [ -e "$RESTORE_DIR/database" ]; then
    if ! RESTORE_TIMESTAMP=$(jq -r '[.files[]?.timestamp] | map(select(. != null)) | max // empty' "$RESTORE_OUTPUT"); then
      echo "FATAL: Litestream restore output could not be parsed; application startup is blocked." >&2
      exit 1
    fi
    if [ -z "$RESTORE_TIMESTAMP" ]; then
      echo "FATAL: Litestream restored a replica without a timestamp; application startup is blocked." >&2
      exit 1
    fi
    RESTORE_EPOCH=$(date -d "$RESTORE_TIMESTAMP" +%s)
    RESTORE_AGE=$(( $(date +%s) - RESTORE_EPOCH ))
%{ if backup_replication_max_age_hours != "" ~}
    if [ "$RESTORE_AGE" -gt $(( ${backup_replication_max_age_hours} * 3600 )) ]; then
      echo "FATAL: Litestream replica completed at $${RESTORE_TIMESTAMP} and is $${RESTORE_AGE} seconds old, exceeding the configured maximum age of ${backup_replication_max_age_hours} hours; application startup is blocked." >&2
      exit 1
    fi
%{ endif ~}
    mkdir -p "$(dirname "${backup_replication_database_path}")"
    mv "$RESTORE_DIR/database" "${backup_replication_database_path}"
    echo "Litestream restored replica completed at $${RESTORE_TIMESTAMP} (age $${RESTORE_AGE} seconds)."
  else
    echo "No Litestream replica was found; treating this as a fresh service and continuing without restore."
  fi
  touch "${backup_replication_restore_marker}"
fi
%{ endif ~}

mkdir -p "$(dirname "${backup_replication_log_path}")"
cat > "/etc/supervisord.d/${name}-litestream.ini" <<SUPERVISOR_REPLICATION
[program:${name}-litestream]
command=/usr/local/bin/litestream replicate -config /etc/litestream.yml
autostart=true
autorestart=true
startsecs=5
startretries=3
stopsignal=TERM
stopwaitsecs=30
stopasgroup=true
killasgroup=true
stdout_logfile=${backup_replication_log_path}
stdout_logfile_maxbytes=20MB
stdout_logfile_backups=5
redirect_stderr=true
SUPERVISOR_REPLICATION

/usr/local/bin/supervisorctl -c /etc/supervisord.conf reread
/usr/local/bin/supervisorctl -c /etc/supervisord.conf update
/usr/local/bin/supervisorctl -c /etc/supervisord.conf start "${name}-litestream"
