# Build the app environment file. Plain values are rendered by Terraform
# (like an ECS task definition's environment); secret values are fetched
# from Secrets Manager / SSM Parameter Store here, so they never land in
# Terraform state or the SSM document. A failed fetch aborts before the
# old env file is replaced.
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
%{ for s in secrets ~}
SECRET_SOURCE='${s.value_from}'
case "$SECRET_SOURCE" in
  arn:*:secretsmanager:*)
    SECRET_VALUE=$(aws secretsmanager get-secret-value --region "$(echo "$SECRET_SOURCE" | cut -d: -f4)" --secret-id "$SECRET_SOURCE" --query SecretString --output text)
    ;;
  arn:*:ssm:*)
    SECRET_VALUE=$(aws ssm get-parameter --region "$(echo "$SECRET_SOURCE" | cut -d: -f4)" --name "$SECRET_SOURCE" --with-decryption --query Parameter.Value --output text)
    ;;
  *)
    SECRET_VALUE=$(aws ssm get-parameter --region ${region} --name "$SECRET_SOURCE" --with-decryption --query Parameter.Value --output text)
    ;;
esac
printf '%s=%s\n' '${s.name}' "$SECRET_VALUE" >> "$ENV_TMP"
%{ endfor ~}
mkdir -p "$(dirname ${env_file_path})"
mv "$ENV_TMP" "${env_file_path}"
