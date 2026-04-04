#!/bin/bash
set -e

DIR="/opt/neurhomia/mosquitto"
ENV_FILE="/opt/neurhomia/.env"

mkdir -p "$DIR/config" "$DIR/data" "$DIR/log"

if [ -f "$ENV_FILE" ]; then
    source "$ENV_FILE"
fi

if [ -n "$MQTT_PASSWORD" ]; then
    mosquitto_passwd -b "$DIR/config/passwd" "$MQTT_USER" "$MQTT_PASSWORD"
fi

cat > "$DIR/config/mosquitto.conf" <<EOF
allow_anonymous false
password_file /mosquitto/config/passwd
listener 1883
EOF

cat > "$DIR/docker-compose.yml" <<EOF
services:
  mosquitto:
    image: eclipse-mosquitto
    container_name: mosquitto
    ports:
      - "1883:1883"
    volumes:
      - ./config:/mosquitto/config
      - ./data:/mosquitto/data
      - ./log:/mosquitto/log
EOF

cd "$DIR"
docker compose up -d

echo "[OK] Mosquitto running"
