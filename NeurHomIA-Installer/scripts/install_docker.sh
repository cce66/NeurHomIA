#!/bin/bash
set -e

echo "[INFO] Installing Docker..."

apt-get update
apt-get install -y docker.io docker-compose-plugin

systemctl enable docker
systemctl start docker

echo "[OK] Docker ready"
