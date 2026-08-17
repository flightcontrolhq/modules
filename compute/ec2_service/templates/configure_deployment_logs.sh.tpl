LOG_PATH="${log_directory}/deployment-$${DEPLOY_ID}.log"
mkdir -p "${log_directory}"
touch "$LOG_PATH"
chmod 640 "$LOG_PATH"

dnf install -y amazon-cloudwatch-agent
cat > /opt/aws/amazon-cloudwatch-agent/etc/app-logs.json <<CWCONFIG
{
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "$LOG_PATH",
            "log_group_name": "${log_group_name}",
            "log_stream_name": "deployment/$${DEPLOY_ID}/instance/{instance_id}",
            "timezone": "UTC"
          },
          {
            "file_path": "${backup_log_path}",
            "log_group_name": "${log_group_name}",
            "log_stream_name": "backup/instance/{instance_id}",
            "timezone": "UTC"
          },
          {
            "file_path": "${replication_log_path}",
            "log_group_name": "${log_group_name}",
            "log_stream_name": "replication/instance/{instance_id}",
            "timezone": "UTC"
          }
        ]
      }
    }
  }
}
CWCONFIG

/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -s \
  -c file:/opt/aws/amazon-cloudwatch-agent/etc/app-logs.json
