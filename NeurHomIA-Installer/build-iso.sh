#!/bin/bash
set -e

# ==========================================
# CONFIG
# ==========================================

PROJECT_NAME="NeurHomIA"
PROJECT_NAME_LOWER="neurhomia"

UBUNTU_VERSION="22.04.4"
ISO_NAME="ubuntu-${UBUNTU_VERSION}-live-server-amd64.iso"
ISO_URL="https://releases.ubuntu.com/22.04/${ISO_NAME}"

WORKDIR="$(pwd)/build"
ISO_DIR="${WORKDIR}/iso"
EXTRACT_DIR="${WORKDIR}/extract"
AUTOINSTALL_DIR="${EXTRACT_DIR}/nocloud"
CUSTOM_ISO="${WORKDIR}/${PROJECT_NAME_LOWER}-installer.iso"

USERNAME="ubuntu"
PASSWORD_HASH="\$6\$rounds=4096\$xyz\$xyzxyzxyzxyzxyzxyzxyzxyzxyzxyzxyzxyz"

# ==========================================
# COLORS
# ==========================================

GREEN="\033[0;32m"
YELLOW="\033[1;33m"
RED="\033[0;31m"
NC="\033[0m"

# ==========================================
# STEP 01 - CHECK DEPENDENCIES
# ==========================================

step_01_check_deps() {
    echo -e "${YELLOW}1) Vérification des dépendances...${NC}"

    for cmd in wget rsync xorriso sed; do
        if ! command -v $cmd &>/dev/null; then
            echo -e "${RED}   Missing: $cmd${NC}"
            exit 1
        fi
    done

    echo -e "${GREEN}   OK${NC}"
}

# ==========================================
# STEP 02 - PREPARE WORKDIR
# ==========================================

step_02_prepare() {
    echo -e "${YELLOW}2) Préparation workspace...${NC}"

    rm -rf "$WORKDIR"
    mkdir -p "$ISO_DIR" "$EXTRACT_DIR"

    echo -e "${GREEN}   OK${NC}"
}

# ==========================================
# STEP 03 - DOWNLOAD ISO
# ==========================================

step_03_download_iso() {
    echo -e "${YELLOW}3) Téléchargement ISO...${NC}"

    cd "$ISO_DIR"

    if [ ! -f "$ISO_NAME" ]; then
        wget "$ISO_URL"
    else
        echo "   ISO déjà présent"
    fi

    echo -e "${GREEN}   OK${NC}"
}

# ==========================================
# STEP 04 - EXTRACT ISO
# ==========================================

step_04_extract_iso() {
    echo -e "${YELLOW}4) Extraction ISO...${NC}"

    sudo mount -o loop "$ISO_DIR/$ISO_NAME" /mnt
    rsync -a /mnt/ "$EXTRACT_DIR"
    sudo umount /mnt

    chmod -R +w "$EXTRACT_DIR"

    echo -e "${GREEN}   OK${NC}"
}

# ==========================================
# STEP 05 - CREATE AUTOINSTALL
# ==========================================

step_05_autoinstall() {
    echo -e "${YELLOW}5) Création autoinstall (mode frontend)...${NC}"

    rm -rf "$AUTOINSTALL_DIR"
    mkdir -p "$AUTOINSTALL_DIR"

    cat > "$AUTOINSTALL_DIR/user-data" <<EOF
#cloud-config
autoinstall:
  version: 1

  identity:
    hostname: ${PROJECT_NAME_LOWER}
    username: ${USERNAME}
    password: "${PASSWORD_HASH}"

  ssh:
    install-server: true

  packages:
    - python3
    - python3-pip
    - curl

  late-commands:
    - curtin in-target --target=/target mkdir -p /opt/neurhomia

    - curtin in-target --target=/target bash -c "cat > /opt/neurhomia/firstboot.sh << 'EOL'
#!/bin/bash

echo '[INFO] First boot NeurHomIA'

apt-get update
apt-get install -y python3 python3-pip curl

mkdir -p /opt/neurhomia/installer

curl -L https://github.com/cce66/NeurHomIA-Installer/archive/main.tar.gz \\
| tar xz --strip-components=1 -C /opt/neurhomia/installer

cd /opt/neurhomia/installer
pip3 install -r requirements.txt

cat > /etc/systemd/system/neurhomia-installer.service <<EOF2
[Unit]
Description=NeurHomIA Installer
After=network.target

[Service]
ExecStart=/usr/bin/python3 /opt/neurhomia/installer/backend.py
Restart=always

[Install]
WantedBy=multi-user.target
EOF2

systemctl daemon-reexec
systemctl enable neurhomia-installer

echo '[OK] Installer disponible sur http://IP:8081'
EOL"

    - curtin in-target --target=/target chmod +x /opt/neurhomia/firstboot.sh
    - curtin in-target --target=/target ln -s /opt/neurhomia/firstboot.sh /etc/rc.local
EOF

    echo "instance-id: iid-local01" > "$AUTOINSTALL_DIR/meta-data"

    echo -e "${GREEN}   OK${NC}"
}

# ==========================================
# STEP 06 - MODIFY GRUB
# ==========================================

step_06_grub() {
    echo -e "${YELLOW}6) Modification GRUB...${NC}"

    sed -i 's|---| autoinstall ds=nocloud\\;s=/cdrom/nocloud/ ---|g' \
    "$EXTRACT_DIR/boot/grub/grub.cfg"

    echo -e "${GREEN}   OK${NC}"
}

# ==========================================
# STEP 07 - BUILD ISO
# ==========================================

step_07_build_iso() {
    echo -e "${YELLOW}7) Build ISO...${NC}"

    cd "$EXTRACT_DIR"

    sudo xorriso -as mkisofs \
      -r -V "${PROJECT_NAME} Installer" \
      -o "$CUSTOM_ISO" \
      -J -l \
      -b boot/grub/i386-pc/eltorito.img \
      -c boot.catalog \
      -no-emul-boot -boot-load-size 4 -boot-info-table \
      --grub2-boot-info \
      -eltorito-alt-boot \
      -e EFI/boot/bootx64.efi \
      -no-emul-boot .

    echo -e "${GREEN}   ISO générée${NC}"
}

# ==========================================
# STEP 08 - VALIDATE
# ==========================================

step_08_validate() {
    echo -e "${YELLOW}8) Validation...${NC}"

    if [ ! -f "$CUSTOM_ISO" ]; then
        echo -e "${RED}   ISO non générée${NC}"
        exit 1
    fi

    echo -e "${GREEN}   ISO OK${NC}"
}

# ==========================================
# STEP 09 - BURN USB
# ==========================================

step_09_burn() {
    echo -e "${YELLOW}9) Graver sur USB ? (y/n)${NC}"
    read -r RESP

    if [ "$RESP" != "y" ]; then
        return
    fi

    lsblk -d -o NAME,SIZE,MODEL
    echo "Disque (ex: sdb):"
    read -r DISK

    sudo dd if="$CUSTOM_ISO" of="/dev/$DISK" bs=4M status=progress oflag=sync

    echo -e "${GREEN}   USB prête${NC}"
}

# ==========================================
# MAIN
# ==========================================

step_01_check_deps
step_02_prepare
step_03_download_iso
step_04_extract_iso
step_05_autoinstall
step_06_grub
step_07_build_iso
step_08_validate
step_09_burn

echo -e "${GREEN}✔ ISO prête : $CUSTOM_ISO${NC}"
