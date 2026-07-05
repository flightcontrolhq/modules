# Build the app environment file. Values are rendered by Terraform
# (like an ECS task definition's environment).
umask 077
ENV_TMP=$(mktemp)
cat > "$ENV_TMP" <<'RVNENV'
%{ for ev in environment_variables ~}
${ev.name}=${ev.value}
%{ endfor ~}
%{ if app_port != null ~}
PORT=${app_port}
%{ endif ~}
RVNENV
mkdir -p "$(dirname ${env_file_path})"
mv "$ENV_TMP" "${env_file_path}"
