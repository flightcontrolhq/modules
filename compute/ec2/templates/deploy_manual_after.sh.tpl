printf '%s' '${manual_start_command_base64}' | base64 -d > "${start_command_path}"
chmod 600 "${start_command_path}"

cat > "${app_runner_path}" <<'APP_RUNNER'
#!/bin/bash
set -euo pipefail
set -a
. "${env_file_path}"
set +a
if [ -s "${source_working_directory_path}" ]; then
  cd "$(cat "${source_working_directory_path}")"
fi
START_COMMAND=$(cat "${start_command_path}")
exec /bin/bash -lc "$START_COMMAND"
APP_RUNNER
chmod 755 "${app_runner_path}"

${supervisor_program_script}

echo "Manual deploy $DEPLOY_ID complete; supervisord is managing ${supervisor_program}"
