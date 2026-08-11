#!/usr/bin/env bash
# Runtime check for the Supervisor configuration this module generates.
#
# The tofu tests assert that nonzero rotation settings are rendered; this
# script runs a real supervisord with the rendered program stanza to
# confirm the app log actually rotates and the process stays manageable
# through supervisorctl.
#
# Usage: tests/supervisor_runtime_test.sh
# Requires: python3 (supervisor is installed into a throwaway virtualenv).
set -euo pipefail

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK_DIR="$(mktemp -d)"
trap 'supervisorctl_cmd shutdown >/dev/null 2>&1 || true; rm -rf "$WORK_DIR"' EXIT

SERVICE_NAME="supervised-app"
PROGRAM="ravion-$SERVICE_NAME"
LOG_DIR="$WORK_DIR/log"
LOG_PATH="$LOG_DIR/deployment-test.log"
SUPERVISOR_CONF="$WORK_DIR/supervisord.conf"
SOCKET="$WORK_DIR/supervisor.sock"
MAX_SIZE_MB=1
BACKUP_COUNT=2

mkdir -p "$LOG_DIR" "$WORK_DIR/conf.d"

fail() {
  echo "FAIL: $*" >&2
  echo "--- supervisord log ---" >&2
  tail -n 50 "$WORK_DIR/supervisord.log" >&2 || true
  exit 1
}

supervisorctl_cmd() {
  "$WORK_DIR/venv/bin/supervisorctl" -c "$SUPERVISOR_CONF" "$@"
}

# Render the module's program stanza with the same substitutions
# templatefile() performs, so the test exercises the shipped template.
render_program_config() {
  sed -n '/^\[program:/,/^SUPERVISOR_PROGRAM$/p' "$MODULE_DIR/templates/configure_supervisor_program.sh.tpl" |
    sed '$d' |
    sed \
      -e "s|\${supervisor_program}|$PROGRAM|g" \
      -e "s|\${app_runner_path}|$WORK_DIR/app-runner|g" \
      -e "s|\${log_rotation_max_size_mb}|$MAX_SIZE_MB|g" \
      -e "s|\${log_rotation_backup_count}|$BACKUP_COUNT|g" \
      -e "s|\$LOG_PATH|$LOG_PATH|g" \
      -e 's|^environment=.*|environment=RAVION_DEPLOYMENT_ID="test"|'
}

echo "Installing supervisor into a throwaway virtualenv"
python3 -m venv "$WORK_DIR/venv"
"$WORK_DIR/venv/bin/pip" install --quiet supervisor==4.3.0

# A stand-in for the deployed app: prints continuously, so the log grows
# past the rotation threshold quickly.
cat > "$WORK_DIR/app-runner" <<APP_RUNNER
#!/usr/bin/env bash
while true; do
  head -c 4096 /dev/zero | tr '\0' 'x'
  echo
done
APP_RUNNER
chmod 755 "$WORK_DIR/app-runner"

render_program_config > "$WORK_DIR/conf.d/app.ini"

grep -q "stdout_logfile_maxbytes=${MAX_SIZE_MB}MB" "$WORK_DIR/conf.d/app.ini" ||
  fail "the rendered program config does not carry a nonzero rotation size"

cat > "$SUPERVISOR_CONF" <<SUPERVISOR_CONFIG
[unix_http_server]
file=$SOCKET

[supervisord]
logfile=$WORK_DIR/supervisord.log
pidfile=$WORK_DIR/supervisord.pid
childlogdir=$LOG_DIR
nodaemon=false

[rpcinterface:supervisor]
supervisor.rpcinterface_factory=supervisor.rpcinterface:make_main_rpcinterface

[supervisorctl]
serverurl=unix://$SOCKET

[include]
files=$WORK_DIR/conf.d/*.ini
SUPERVISOR_CONFIG

echo "Starting supervisord"
"$WORK_DIR/venv/bin/supervisord" -c "$SUPERVISOR_CONF"

for _ in $(seq 1 30); do
  supervisorctl_cmd status "$PROGRAM" | grep -q RUNNING && break
  sleep 1
done
supervisorctl_cmd status "$PROGRAM" | grep -q RUNNING ||
  fail "the supervised program never reached RUNNING"

echo "Waiting for the app log to rotate"
ROTATED=0
for _ in $(seq 1 60); do
  if [ -f "$LOG_PATH.1" ]; then
    ROTATED=1
    break
  fi
  sleep 1
done
[ "$ROTATED" -eq 1 ] || fail "the app log never rotated"

MAX_BYTES=$((MAX_SIZE_MB * 1024 * 1024))
# Supervisor rotates once the file passes maxbytes, so allow one buffered
# write of slack on top of the configured size.
LOG_SIZE=$(stat -c %s "$LOG_PATH")
[ "$LOG_SIZE" -le $((MAX_BYTES + 65536)) ] ||
  fail "the live app log grew to $LOG_SIZE bytes, past the $MAX_BYTES byte rotation size"

echo "Waiting for rotation to reach the configured backup count"
for _ in $(seq 1 120); do
  [ -f "$LOG_PATH.$BACKUP_COUNT" ] && break
  sleep 1
done
[ -f "$LOG_PATH.$BACKUP_COUNT" ] ||
  fail "supervisor never produced $BACKUP_COUNT backup files"
[ ! -f "$LOG_PATH.$((BACKUP_COUNT + 1))" ] ||
  fail "supervisor kept more than $BACKUP_COUNT backup files"

echo "Checking the service is still manageable through supervisorctl"
supervisorctl_cmd restart "$PROGRAM" >/dev/null
supervisorctl_cmd status "$PROGRAM" | grep -q RUNNING ||
  fail "the program did not come back after a supervisorctl restart"

echo "Checking the program survives a crash of the supervised process"
kill -9 "$(supervisorctl_cmd pid "$PROGRAM")"
sleep 3

supervisorctl_cmd status "$PROGRAM" >/dev/null ||
  fail "supervisorctl lost track of the program after the crash"

echo "PASS: rotation is bounded and the service stays manageable through supervisorctl"
