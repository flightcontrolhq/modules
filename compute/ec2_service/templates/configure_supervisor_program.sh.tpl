cat > "${supervisor_conf}" <<SUPERVISOR_PROGRAM
[program:${supervisor_program}]
command=${app_runner_path}
autostart=true
autorestart=true
startsecs=5
startretries=3
stopsignal=TERM
stopwaitsecs=30
stopasgroup=true
killasgroup=true
stdout_logfile=$LOG_PATH
stdout_logfile_maxbytes=${log_rotation_max_size_mb}MB
stdout_logfile_backups=${log_rotation_backup_count}
redirect_stderr=true
environment=RAVION_DEPLOYMENT_ID="$${DEPLOY_ID}"
SUPERVISOR_PROGRAM

/usr/local/bin/supervisorctl -c /etc/supervisord.conf reread
/usr/local/bin/supervisorctl -c /etc/supervisord.conf update
/usr/local/bin/supervisorctl -c /etc/supervisord.conf start "${supervisor_program}" >/dev/null 2>&1 || true

SUPERVISOR_RUNNING=0
for _ in $(seq 1 30); do
  if /usr/local/bin/supervisorctl -c /etc/supervisord.conf status "${supervisor_program}" | grep -q RUNNING; then
    SUPERVISOR_RUNNING=1
    break
  fi
  sleep 1
done
if [ "$SUPERVISOR_RUNNING" -ne 1 ]; then
  echo "${supervisor_program} did not reach the RUNNING state" >&2
  /usr/local/bin/supervisorctl -c /etc/supervisord.conf status "${supervisor_program}" >&2 || true
  tail -n 100 "$LOG_PATH" >&2 || true
  exit 1
fi
