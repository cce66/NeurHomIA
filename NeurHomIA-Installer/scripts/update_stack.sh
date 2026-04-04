#!/bin/bash
DIR="$1"

echo "[INFO] Update $DIR"

cd "$DIR"
docker compose pull
docker compose up -d
