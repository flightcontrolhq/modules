# Install Supervisor from PyPI because Amazon Linux 2023 does not ship a
# Supervisor RPM. Pin the version so instance bootstrap is reproducible.
if ! /usr/local/bin/supervisord --version 2>/dev/null | grep -qx '4.3.0'; then
  dnf install -y python3-pip
  python3 -m pip install --prefix /usr/local supervisor==4.3.0
fi

mkdir -p /etc/supervisord.d /var/log/supervisor
cat > /etc/supervisord.conf <<'SUPERVISOR_CONFIG'
[unix_http_server]
file=/run/supervisor/supervisor.sock
chmod=0700

[supervisord]
logfile=/var/log/supervisor/supervisord.log
pidfile=/run/supervisord.pid
childlogdir=/var/log/supervisor
nodaemon=false

[rpcinterface:supervisor]
supervisor.rpcinterface_factory=supervisor.rpcinterface:make_main_rpcinterface

[supervisorctl]
serverurl=unix:///run/supervisor/supervisor.sock

[include]
files=/etc/supervisord.d/*.ini
SUPERVISOR_CONFIG

cat > /etc/systemd/system/supervisord.service <<'SYSTEMD_UNIT'
[Unit]
Description=Supervisor process control system
After=network-online.target docker.service
Wants=network-online.target

[Service]
Type=forking
ExecStart=/usr/local/bin/supervisord -c /etc/supervisord.conf
ExecStop=/usr/local/bin/supervisorctl -c /etc/supervisord.conf shutdown
ExecReload=/usr/local/bin/supervisorctl -c /etc/supervisord.conf reload
PIDFile=/run/supervisord.pid
RuntimeDirectory=supervisor
RuntimeDirectoryMode=0700
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
SYSTEMD_UNIT

systemctl daemon-reload
systemctl enable --now supervisord
