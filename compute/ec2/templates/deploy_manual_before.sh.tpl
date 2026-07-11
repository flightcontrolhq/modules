#!/bin/bash
set -euo pipefail

DEPLOY_ID="{{ deployId }}"
if [ -z "$DEPLOY_ID" ]; then DEPLOY_ID=$(date +%s); fi
echo "Preparing manual deploy $DEPLOY_ID"

${supervisor_install_script}
${env_file_script}

# Stop the previous supervised app before release preparation. Removing a
# same-named container also makes Container -> Manual switches deterministic.
/usr/local/bin/supervisorctl -c /etc/supervisord.conf stop "${supervisor_program}" >/dev/null 2>&1 || true
docker rm -f ${name} >/dev/null 2>&1 || true

set -a
. "${env_file_path}"
set +a

${git_source_checkout_script}
