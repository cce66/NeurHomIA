#!/bin/bash
set -e

echo "[INFO] Installing fail2ban..."

apt-get install -y fail2ban

systemctl enable fail2ban
systemctl start fail2ban

echo "[OK] fail2ban active"
