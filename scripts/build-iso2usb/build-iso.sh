#!/bin/bash
# build-iso.sh – VERSION COMPLETE CORRIGÉE

set -e
clear

# ------------------------------
# Paramètres
# ------------------------------
DEFAULT_UBUNTU_VERSION="24.04.4"

PROJECT_NAME="NeurHomIA"
PROJECT_NAME_LOWER=$(echo "$PROJECT_NAME" | tr '[:upper:]' '[:lower:]')
PROJECT_NAME_UPPER=$(echo "$PROJECT_NAME" | tr '[:lower:]' '[:upper:]')

USERNAME="neurhomia"
DEFAULT_PASSWORD="neurhomia"

# ------------------------------
# Couleurs
# ------------------------------
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# ------------------------------
# 1) Version Ubuntu
# ------------------------------
echo -e "${YELLOW}1) Version Ubuntu (défaut ${DEFAULT_UBUNTU_VERSION})${NC}"
read -p "Version : " USER_VERSION
ISO_VERSION=${USER_VERSION:-$DEFAULT_UBUNTU_VERSION}

# ------------------------------
# Variables
# ------------------------------
ISO_FILENAME="ubuntu-${ISO_VERSION}-live-server-amd64.iso"
ISO_URL="https://releases.ubuntu.com/${ISO_VERSION%.*}/${ISO_FILENAME}"
WORK_DIR="$HOME/${PROJECT_NAME_LOWER}-iso"
EXTRACT_DIR="$WORK_DIR/extracted"
AUTOINSTALL_DIR="$WORK_DIR/autoinstall"
OUTPUT_ISO="$WORK_DIR/${PROJECT_NAME_LOWER}-server-${ISO_VERSION}-auto.iso"
LABEL="${PROJECT_NAME_UPPER}_SRV"

# ------------------------------
# 2) Dépendances
# ------------------------------
echo -e "${YELLOW}2) Vérification dépendances${NC}"
for cmd in wget 7z xorriso openssl mkfs.vfat; do
    command -v $cmd >/dev/null || { echo -e "${RED}$cmd manquant${NC}"; exit 1; }
done
echo -e "${GREEN}OK${NC}"

# ------------------------------
# 3) Préparation
# ------------------------------
echo -e "${YELLOW}3) Préparation${NC}"
mkdir -p "$WORK_DIR"
rm -rf "$EXTRACT_DIR" "$AUTOINSTALL_DIR"
mkdir -p "$EXTRACT_DIR" "$AUTOINSTALL_DIR"

# ------------------------------
# 4) Téléchargement ISO
# ------------------------------
echo -e "${YELLOW}4) Téléchargement ISO${NC}"
if [ ! -f "$WORK_DIR/$ISO_FILENAME" ]; then
    wget -O "$WORK_DIR/$ISO_FILENAME" "$ISO_URL"
fi

# ------------------------------
# 5) Extraction
# ------------------------------
echo -e "${YELLOW}5) Extraction${NC}"
xorriso -osirrox on -indev "$ISO" -extract / "$EXTRACT_DIR"

# ------------------------------
# 6) Autoinstall
# ------------------------------
echo -e "${YELLOW}6) Autoinstall${NC}"
PASSWORD_HASH=$(openssl passwd -6 "$DEFAULT_PASSWORD")

cat > "$AUTOINSTALL_DIR/user-data" <<EOF
#cloud-config
autoinstall:
  version: 1
  identity:
    hostname: ${PROJECT_NAME_LOWER}-box
    username: $USERNAME
    password: "$PASSWORD_HASH"
EOF

touch "$AUTOINSTALL_DIR/meta-data"
cp -r "$AUTOINSTALL_DIR" "$EXTRACT_DIR/"

# ------------------------------
# 7) GRUB
# ------------------------------
echo -e "${YELLOW}7) Modification GRUB${NC}"
GRUB_CFG="$EXTRACT_DIR/boot/grub/grub.cfg"
cp "$GRUB_CFG" "$GRUB_CFG.orig"

AUTOINSTALL_ENTRY=$(cat <<EOF
menuentry "Autoinstall Ubuntu Server $PROJECT_NAME" {
    set gfxpayload=keep
    linux   /casper/vmlinuz autoinstall ds=nocloud;s=/cdrom/autoinstall/ ---
    initrd  /casper/initrd
}
EOF
)

awk -v entry="$AUTOINSTALL_ENTRY" '
BEGIN {added=0}
/^menuentry / && added==0 {print entry; added=1}
{print}
' "$GRUB_CFG" > "$GRUB_CFG.new"

mv "$GRUB_CFG.new" "$GRUB_CFG"

grep -q "^set default=" "$GRUB_CFG" && \
    sed -i 's/^set default=.*/set default=0/' "$GRUB_CFG" || \
    echo "set default=0" >> "$GRUB_CFG"

grep -q "^set timeout=" "$GRUB_CFG" && \
    sed -i 's/^set timeout=.*/set timeout=5/' "$GRUB_CFG" || \
    echo "set timeout=5" >> "$GRUB_CFG"

# ------------------------------
# 8) Création efi.img (FIX UEFI)
# ------------------------------
echo -e "${YELLOW}8) Création efi.img${NC}"

EFI_IMG="$EXTRACT_DIR/boot/grub/efi.img"

TMP_EFI=$(mktemp -d)
mkdir -p "$TMP_EFI/EFI"
cp -r "$EXTRACT_DIR/EFI"/* "$TMP_EFI/EFI/"

dd if=/dev/zero of="$EFI_IMG" bs=1M count=20 status=none
mkfs.vfat "$EFI_IMG" >/dev/null

TMP_MOUNT=$(mktemp -d)
sudo mount "$EFI_IMG" "$TMP_MOUNT"
sudo cp -r "$TMP_EFI/EFI"/* "$TMP_MOUNT/"
sudo umount "$TMP_MOUNT"

rm -rf "$TMP_EFI" "$TMP_MOUNT"

echo -e "${GREEN}efi.img créé${NC}"

# ------------------------------
# 9) Création ISO (FIX BOOT)
# ------------------------------
echo -e "${YELLOW}9) Création ISO${NC}"

if [ ! -f "$EXTRACT_DIR/boot/grub/eltorito.img" ]; then
    echo -e "${RED}eltorito.img manquant${NC}"
    exit 1
fi

xorriso -as mkisofs \
  -r -V "$LABEL" \
  -o "$OUTPUT_ISO" \
  -J -joliet-long -l \
  -iso-level 3 \
  -partition_offset 16 \
  -b boot/grub/eltorito.img \
    -c boot.catalog \
    -no-emul-boot \
    -boot-load-size 4 \
    -boot-info-table \
  -eltorito-alt-boot \
  -e boot/grub/efi.img \
    -no-emul-boot \
  -isohybrid-gpt-basdat \
  "$EXTRACT_DIR"

echo -e "${GREEN}ISO créée : $OUTPUT_ISO${NC}"

# ------------------------------
# 10) Fin
# ------------------------------
echo ""
echo -e "${GREEN}Terminé !${NC}"
echo "Pour graver :"
echo "sudo dd if=$OUTPUT_ISO of=/dev/sdX bs=4M status=progress conv=fsync"
