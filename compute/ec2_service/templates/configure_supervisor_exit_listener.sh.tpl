# Install the supervisord event listener that records unexpected app
# process exits. startretries only covers a process that never reaches
# startsecs; a process that starts cleanly and then crashes in a loop is
# invisible to it, so the listener writes one JSON line per unexpected
# exit and the CloudWatch agent ships it to the app log group, where a
# metric filter turns it into a metric an alarm can watch.
mkdir -p ${log_directory} /etc/supervisord.d

cat > ${exit_listener_path} <<'EXIT_LISTENER'
#!/usr/bin/env python3
"""Record supervisord PROCESS_STATE_EXITED events as JSON log lines."""
import json
import os
import sys
import time

EVENT_LOG_PATH = os.environ["RAVION_EVENT_LOG_PATH"]
SERVICE_NAME = os.environ["RAVION_SERVICE_NAME"]


def write_line(payload):
    with open(EVENT_LOG_PATH, "a", encoding="utf-8") as event_log:
        event_log.write(json.dumps(payload) + "\n")


def main():
    while True:
        sys.stdout.write("READY\n")
        sys.stdout.flush()

        header = dict(item.split(":", 1) for item in sys.stdin.readline().split())
        payload = sys.stdin.read(int(header["len"]))

        if header.get("eventname") == "PROCESS_STATE_EXITED":
            fields = dict(item.split(":", 1) for item in payload.split())
            write_line(
                {
                    "event": "process_exit",
                    "service": SERVICE_NAME,
                    "program": fields.get("processname", ""),
                    "from_state": fields.get("from_state", ""),
                    "expected": fields.get("expected") == "1",
                    "pid": fields.get("pid", ""),
                    "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                }
            )

        sys.stdout.write("RESULT 2\nOK")
        sys.stdout.flush()


main()
EXIT_LISTENER
chmod 755 ${exit_listener_path}

touch ${process_event_log_path}
chmod 640 ${process_event_log_path}

cat > ${exit_listener_conf} <<EXIT_LISTENER_PROGRAM
[eventlistener:${exit_listener_program}]
command=${exit_listener_path}
events=PROCESS_STATE_EXITED
autostart=true
autorestart=true
startsecs=1
stopsignal=TERM
stopwaitsecs=10
environment=RAVION_EVENT_LOG_PATH="${process_event_log_path}",RAVION_SERVICE_NAME="${name}"
stdout_logfile=/var/log/supervisor/${exit_listener_program}.log
stdout_logfile_maxbytes=1MB
stdout_logfile_backups=1
stderr_logfile=/var/log/supervisor/${exit_listener_program}-error.log
stderr_logfile_maxbytes=1MB
stderr_logfile_backups=1
EXIT_LISTENER_PROGRAM

# Pick the listener up on instance boot as well as on deploys; the deploy
# path rereads again after writing the app program config.
if [ -S /run/supervisor/supervisor.sock ]; then
  /usr/local/bin/supervisorctl -c /etc/supervisord.conf reread
  /usr/local/bin/supervisorctl -c /etc/supervisord.conf update
fi

# Ship process exit events on their own stream so they stay out of the
# deployment log view. append-config keeps any deployment log config the
# agent already loaded.
if [ -x /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl ]; then
  cat > /opt/aws/amazon-cloudwatch-agent/etc/process-events.json <<PROCESS_EVENTS_CONFIG
{
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "${process_event_log_path}",
            "log_group_name": "${log_group_name}",
            "log_stream_name": "process-events/instance/{instance_id}",
            "timezone": "UTC"
          }
        ]
      }
    }
  }
}
PROCESS_EVENTS_CONFIG

  /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a append-config -m ec2 -s \
    -c file:/opt/aws/amazon-cloudwatch-agent/etc/process-events.json
fi
