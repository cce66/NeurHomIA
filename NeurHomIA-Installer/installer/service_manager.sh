#!/bin/bash

SERVICE_NAME="$1"
WORKDIR="$2"

cat > /etc/systemd/system/${SERVICE_NAME}.service <<EOF
[Unit]
Description=${SERVICE_NAME}
After=docker.service

[Service]
WorkingDirectory=${WORKDIR}
ExecStart=/usr/bin/docker compose up -d
ExecStop=/usr/bin/docker compose down
Restart=always

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reexec
systemctl enable ${SERVICE_NAME}
systemctl start ${SERVICE_NAME}
