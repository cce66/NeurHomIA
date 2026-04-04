#!/bin/bash
set -e

echo "[INFO] Setup UFW..."

apt-get install -y ufw

ufw allow OpenSSH
ufw allow 80
ufw allow 443
ufw allow 1883

ufw --force enable

echo "[OK] UFW enabled"
