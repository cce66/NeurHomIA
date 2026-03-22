#!/bin/bash
# build-iso-server-mcp.sh
set -euo pipefail

# ------------------------------
# Paramètres de base
# ------------------------------
PROJECT_NAME="NeurHomIA"
PROJECT_NAME_LOWER=$(echo "$PROJECT_NAME" | tr '[:upper:]' '[:lower:]')
USERNAME="neurhomia"
DEFAULT_PASSWORD="neurhomia"
GITHUB_OWNER_NAME="cce66"
FIRSTBOOT_SCRIPT_URL="https://raw.githubusercontent.com/${GITHUB_OWNER_NAME}/${PROJECT_NAME}/main/scripts/build-iso2usb/firstboot-config.sh"
DEFAULT_UBUNTU_VERSION="24.04.4"

WORK_DIR="$HOME/${PROJECT_NAME_LOWER}-iso"
EXTRACT_DIR="$WORK_DIR/extracted"
AUTOINSTALL_DIR="$WORK_DIR/autoinstall"
ISO_VERSION="$DEFAULT_UBUNTU_VERSION"
ISO_FILENAME="ubuntu-${ISO_VERSION}-live-server-amd64.iso"
OUTPUT_ISO="$WORK_DIR/${PROJECT_NAME_LOWER}-server-${ISO_VERSION}-auto.iso"
LABEL="${PROJECT_NAME}_SRV"
[ ${#LABEL} -gt 32 ] && LABEL="${LABEL:0:32}"

mkdir -p "$WORK_DIR" "$EXTRACT_DIR" "$AUTOINSTALL_DIR"

# ------------------------------
# 1) Téléchargement ISO si nécessaire
# ------------------------------
if [ ! -f "$WORK_DIR/$ISO_FILENAME" ]; then
    ISO_URL="https://releases.ubuntu.com/${ISO_VERSION%.*}/ubuntu-${ISO_VERSION}-live-server-amd64.iso"
    wget -O "$WORK_DIR/$ISO_FILENAME" "$ISO_URL"
fi

# ------------------------------
# 2) Extraction ISO (mode robuste)
# ------------------------------
MOUNT_DIR="/mnt/iso"
sudo mkdir -p "$MOUNT_DIR"
sudo mount -o loop,ro "$WORK_DIR/$ISO_FILENAME" "$MOUNT_DIR"

# Sur Ubuntu Server, le squashfs est dans live/filesystem.squashfs
if [ -f "$MOUNT_DIR/live/filesystem.squashfs" ]; then
    mkdir -p "$EXTRACT_DIR/live"
    cp -av "$MOUNT_DIR/live/filesystem.squashfs" "$EXTRACT_DIR/live/"
else
    echo "❌ Impossible de trouver live/filesystem.squashfs dans l'ISO server"
    sudo umount "$MOUNT_DIR"
    exit 1
fi

# Copier le reste de l'ISO (ISO bootable)
rsync -aHAX --exclude=/live/filesystem.squashfs "$MOUNT_DIR/" "$EXTRACT_DIR/"

sudo umount "$MOUNT_DIR"

# ------------------------------
# 3) Création fichiers autoinstall
# ------------------------------
PASSWORD_HASH=$(openssl passwd -6 "$DEFAULT_PASSWORD")
mkdir -p "$AUTOINSTALL_DIR"

cat > "$AUTOINSTALL_DIR/user-data" <<EOF
#cloud-config
autoinstall:
  version: 1
  locale: fr_FR.UTF-8
  keyboard:
    layout: fr
  network:
    network:
      version: 2
      ethernets:
        all-eth:
          match:
            name: "en*"
          dhcp4: true
  storage:
    layout:
      name: lvm
  identity:
    hostname: ${PROJECT_NAME_LOWER}-box
    username: $USERNAME
    password: "$PASSWORD_HASH"
  ssh:
    install-server: true
    allow-pw: true
  packages:
    - docker.io
    - docker-compose-plugin
    - git
    - curl
  late-commands:
    - curtin in-target -- mkdir -p /opt/${PROJECT_NAME_LOWER}
    - curtin in-target -- wget -O /opt/${PROJECT_NAME_LOWER}/firstboot.sh $FIRSTBOOT_SCRIPT_URL
    - curtin in-target -- chmod +x /opt/${PROJECT_NAME_LOWER}/firstboot.sh
    - curtin in-target -- bash -c "cd /opt/${PROJECT_NAME_LOWER} && git clone https://github.com/${GITHUB_OWNER_NAME}/MCP-services || true"
EOF

touch "$AUTOINSTALL_DIR/meta-data"

cp -r "$AUTOINSTALL_DIR" "$EXTRACT_DIR/"

# ------------------------------
# 4) Ajout entrée GRUB autoinstall MCP
# ------------------------------
GRUB_CFG="$EXTRACT_DIR/boot/grub/grub.cfg"
if [ -f "$GRUB_CFG" ]; then
    cp "$GRUB_CFG" "$GRUB_CFG.orig"
    AUTOINSTALL_ENTRY=$(cat <<EOF
menuentry "Autoinstall Ubuntu Server $PROJECT_NAME" {
    set gfxpayload=keep
    linux /casper/vmlinuz autoinstall ds=nocloud;s=/cdrom/autoinstall/ ---
    initrd /casper/initrd
}
EOF
)
    awk -v entry="$AUTOINSTALL_ENTRY" '
    BEGIN {added=0}
    /^menuentry / && added==0 {
        print entry
        added=1
    }
    {print}
    ' "$GRUB_CFG" > "$GRUB_CFG.new"
    mv "$GRUB_CFG.new" "$GRUB_CFG"

    sed -i '/^set default=/d' "$GRUB_CFG"
    sed -i '/^set timeout=/d' "$GRUB_CFG"
    echo "set default=0" >> "$GRUB_CFG"
    echo "set timeout=5" >> "$GRUB_CFG"
fi

# ------------------------------
# 5) Création ISO bootable MCP-ready
# ------------------------------
EFI_BOOT=$(find "$EXTRACT_DIR/EFI" -type f -iname "bootx64.efi" | head -1)
if [ -z "$EFI_BOOT" ]; then
    echo "❌ EFI boot introuvable"
    exit 1
fi
EFI_BOOT="${EFI_BOOT#$EXTRACT_DIR/}"

ISOLINUX_MBR="/usr/lib/ISOLINUX/isohdpfx.bin"
if [ ! -f "$ISOLINUX_MBR" ]; then
    echo "❌ isohdpfx.bin manquant, installer syslinux-utils"
    exit 1
fi

xorriso -as mkisofs \
    -r -V "$LABEL" \
    -o "$OUTPUT_ISO" \
    -J -joliet-long -l \
    -iso-level 3 \
    -isohybrid-mbr "$ISOLINUX_MBR" \
    -partition_offset 16 \
    -c boot.catalog \
    -b boot/grub/i386-pc/eltorito.img \
        -no-emul-boot \
        -boot-load-size 4 \
        -boot-info-table \
    -eltorito-alt-boot \
    -e "$EFI_BOOT" \
        -no-emul-boot \
    -isohybrid-gpt-basdat \
    "$EXTRACT_DIR"

echo "✅ ISO générée : $OUTPUT_ISO (MCP-ready, Ubuntu Server)"
