#!/bin/bash

echo "[INFO] First boot NeurHomIA"

# install python + pip
apt-get update
apt-get install -y python3 python3-pip git

# créer structure
mkdir -p /opt/neurhomia/installer
mkdir -p /opt/neurhomia/mcp

# récupérer installer depuis github
cd /opt/neurhomia

git clone https://github.com/cce66/NeurHomIA-Installer installer

# installer dépendances
cd installer
pip3 install -r requirements.txt

# créer service systemd
cat > /etc/systemd/system/neurhomia-installer.service <<EOF
[Unit]
Description=NeurHomIA Installer
After=network.target

[Service]
ExecStart=/usr/bin/python3 /opt/neurhomia/installer/backend.py
Restart=always

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reexec
systemctl enable neurhomia-installer
systemctl start neurhomia-installer

echo "[OK] Installer ready on port 8081"
