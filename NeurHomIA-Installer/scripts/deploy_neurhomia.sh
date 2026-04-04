#!/bin/bash
set -e

DIR="/opt/neurhomia/app"

echo "[INFO] Deploy NeurHomIA..."

if [ ! -d "$DIR" ]; then
    git clone https://github.com/cce66/NeurHomIA "$DIR"
else
    cd "$DIR"
    git pull
fi

cd "$DIR"
docker compose up -d

echo "[OK] NeurHomIA running"
