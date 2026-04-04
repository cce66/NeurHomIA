#!/bin/bash
set -e

PROFILE="$1"
BASE_DIR="/opt/neurhomia/mcp"

echo "[INFO] Deploy MCP: $PROFILE"

TARGET="$BASE_DIR/$PROFILE"

if [ ! -d "$TARGET" ]; then
    echo "[ERROR] MCP not found: $PROFILE"
    exit 1
fi

cd "$TARGET"
docker compose up -d

echo "[OK] MCP $PROFILE started"
