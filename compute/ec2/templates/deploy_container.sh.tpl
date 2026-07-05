#!/bin/bash
# In-place container deploy for ${name}. Runs on each instance via the
# SSM deploy document; {{ }} placeholders are SSM parameter substitutions.
set -euo pipefail

IMAGE_URI="{{ imageUri }}"
DEPLOY_ID="{{ deployId }}"
if [ -z "$DEPLOY_ID" ]; then DEPLOY_ID=$(date +%s); fi
echo "Deploying image $IMAGE_URI (deploy $DEPLOY_ID)"

TOKEN=$(curl -sf -X PUT http://169.254.169.254/latest/api/token -H "X-aws-ec2-metadata-token-ttl-seconds: 300")
INSTANCE_ID=$(curl -sf -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-id)

# Rebuild the app env file on every deploy.
${env_file_script}

# Log in to ECR when pulling from an ECR registry
case "$IMAGE_URI" in
  *.dkr.ecr.*.amazonaws.com/*)
    ECR_REGISTRY="$${IMAGE_URI%%/*}"
    aws ecr get-login-password --region ${region} | docker login --username AWS --password-stdin "$ECR_REGISTRY"
    ;;
esac

docker pull "$IMAGE_URI"

%{ if target_group_arn != "" ~}
# Drain this instance from the target group before swapping the container
echo "Deregistering $INSTANCE_ID from the target group"
aws elbv2 deregister-targets --region ${region} --target-group-arn "${target_group_arn}" --targets Id="$INSTANCE_ID"
aws elbv2 wait target-deregistered --region ${region} --target-group-arn "${target_group_arn}" --targets Id="$INSTANCE_ID"
%{ endif ~}

docker rm -f ${name} >/dev/null 2>&1 || true

RUN_ARGS=(-d --name ${name} --restart unless-stopped --env-file "${env_file_path}")
%{ if app_port != null ~}
RUN_ARGS+=(-p ${app_port}:${app_port})
%{ endif ~}
%{ if data_volume_mount_path != "" ~}
RUN_ARGS+=(-v ${data_volume_mount_path}:${data_volume_mount_path})
%{ endif ~}
%{ if efs_mount_path != "" ~}
RUN_ARGS+=(-v ${efs_mount_path}:${efs_mount_path})
%{ endif ~}
RUN_ARGS+=(--log-driver awslogs)
RUN_ARGS+=(--log-opt awslogs-region=${region})
RUN_ARGS+=(--log-opt awslogs-group=${log_group_name})
RUN_ARGS+=(--log-opt awslogs-stream=instance/"$INSTANCE_ID"/app-"$DEPLOY_ID")
docker run "$${RUN_ARGS[@]}" "$IMAGE_URI" ${start_command}

%{ if health_check_path != "" && app_port != null ~}
# Gate deploy success on the local health check
HEALTHY=0
for _ in $(seq 1 60); do
  if curl -fsS -o /dev/null "http://localhost:${app_port}${health_check_path}"; then
    HEALTHY=1
    break
  fi
  sleep 5
done
if [ "$HEALTHY" -ne 1 ]; then
  echo "App failed the local health check on port ${app_port}${health_check_path}" >&2
  docker logs --tail 100 ${name} >&2 || true
  exit 1
fi
%{ endif ~}

%{ if target_group_arn != "" ~}
echo "Re-registering $INSTANCE_ID with the target group"
aws elbv2 register-targets --region ${region} --target-group-arn "${target_group_arn}" --targets Id="$INSTANCE_ID"
aws elbv2 wait target-in-service --region ${region} --target-group-arn "${target_group_arn}" --targets Id="$INSTANCE_ID"
%{ endif ~}

docker image prune -f >/dev/null 2>&1 || true
echo "Deploy $DEPLOY_ID complete"
