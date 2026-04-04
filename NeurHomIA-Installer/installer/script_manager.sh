#!/bin/bash

BASE_URL="https://raw.githubusercontent.com/cce66/NeurHomIA-Installer/main/scripts"
CACHE_DIR="/opt/neurhomia/installer/scripts"

mkdir -p "$CACHE_DIR"

fetch_script() {
    NAME="$1"
    TARGET="$CACHE_DIR/$NAME"

    if [ ! -f "$TARGET" ]; then
        curl -fsSL "$BASE_URL/$NAME" -o "$TARGET"
        chmod +x "$TARGET"
    fi

    echo "$TARGET"
}

run_script() {
    SCRIPT="$1"
    ARG="$2"

    PATH_SCRIPT=$(fetch_script "$SCRIPT")
    bash "$PATH_SCRIPT" "$ARG"
}

if [ "$1" == "run_script" ]; then
    run_script "$2" "$3"
fi
