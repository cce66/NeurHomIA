#!/bin/bash
# build-iso-server-mcp.sh
# Construction d'une ISO Ubuntu Server autoinstall MCP-ready
# Usage : sudo ./build-iso-server-mcp.sh [-v <version>] [-p <projet>] [-u <github_user>] [-d <usb_device>] [--force]

set -euo pipefail

# ------------------------------
# CONFIGURATION DE BASE
# ------------------------------
DEFAULT_UBUNTU_VERSION="24.04.4"
PROJECT_NAME="NeurHomIA"
USERNAME="neurhomia"
DEFAULT_PASSWORD="neurhomia"
GITHUB_OWNER_NAME="cce66"
FIRSTBOOT_SCRIPT_URL="https://raw.githubusercontent.com/${GITHUB_OWNER_NAME}/${PROJECT_NAME}/main/scripts/build-iso2usb/firstboot-config.sh"

WORK_DIR=$(mktemp -d -t "${PROJECT_NAME}-iso-XXXX")
EXTRACT_DIR="$WORK_DIR/extracted"
AUTOINSTALL_DIR="$WORK_DIR/autoinstall"
OUTPUT_ISO="$WORK_DIR/${PROJECT_NAME}-server-auto.iso"
LABEL=$(echo "$PROJECT_NAME" | tr '[:lower:]' '[:upper:]')
[ ${#LABEL} -gt 32 ] && LABEL="${LABEL:0:32}"

# Dépendances
declare -A DEP_MAP=(
    ["wget"]="wget"
    ["7z"]="p7zip-full"
    ["openssl"]="openssl"
    ["xorriso"]="xorriso"
    ["unsquashfs"]="squashfs-tools"
    ["mksquashfs"]="squashfs-tools"
    ["rsync"]="rsync"
    ["isohybrid"]="syslinux-utils"
)
AUTO_INSTALL_DEPS=true

# ------------------------------
# COULEURS
# ------------------------------
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# ------------------------------
# CHECK DEPENDANCES
# ------------------------------
check_deps() {
    local missing=()
    for cmd in "${!DEP_MAP[@]}"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing+=("${DEP_MAP[$cmd]}")
        fi
    done
    if [ ${#missing[@]} -eq 0 ]; then
        echo -e "${GREEN}Toutes les dépendances sont installées.${NC}"
        return
    fi
    echo -e "${YELLOW}Dépendances manquantes : ${missing[*]}${NC}"
    if [ "$AUTO_INSTALL_DEPS" = true ]; then
        echo -e "${CYAN}Installation automatique...${NC}"
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -y
        apt-get install -y "${missing[@]}"
    else
        echo -e "${RED}Installez-les manuellement : sudo apt install ${missing[*]}${NC}"
        exit 1
    fi
}

check_deps

# ------------------------------
# TELECHARGEMENT ISO
# ------------------------------
ISO_FILENAME="ubuntu-${DEFAULT_UBUNTU_VERSION}-live-server-amd64.iso"
ISO_URL="https://releases.ubuntu.com/${DEFAULT_UBUNTU_VERSION%.*}/$ISO_FILENAME"

if [ ! -f "$WORK_DIR/$ISO_FILENAME" ]; then
    echo -e "${GREEN}Téléchargement ISO ${DEFAULT_UBUNTU_VERSION}...${NC}"
    wget -O "$WORK_DIR/$ISO_FILENAME" "$ISO_URL"
else
    echo -e "${GREEN}ISO déjà présente.${NC}"
fi

# ------------------------------
# EXTRACTION ISO (robuste)
# ------------------------------
echo -e "${YELLOW}[Extraction ISO]${NC}"
mkdir -p /mnt/iso
sudo mount -o loop,ro "$WORK_DIR/$ISO_FILENAME" /mnt/iso
mkdir -p "$EXTRACT_DIR"
rsync -aHAX --exclude=/casper/filesystem.squashfs /mnt/iso/ "$EXTRACT_DIR"
cp /mnt/iso/casper/filesystem.squashfs "$EXTRACT_DIR/casper/"
sudo umount /mnt/iso

# ------------------------------
# HASH MOT DE PASSE
# ------------------------------
PASSWORD_HASH=$(openssl passwd -6 "$DEFAULT_PASSWORD")

# ------------------------------
# AUTOINSTALL MCP
# ------------------------------
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
          optional: true
  storage:
    layout:
      name: lvm
  identity:
    hostname: ${PROJECT_NAME}-box
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
    - whiptail
  late-commands:
    - mkdir -p /target/opt/${PROJECT_NAME}
    - curtin in-target -- wget -O /opt/${PROJECT_NAME}/firstboot.sh $FIRSTBOOT_SCRIPT_URL
    - curtin in-target -- chmod +x /opt/${PROJECT_NAME}/firstboot.sh
    - curtin in-target -- mkdir -p /target/opt/mcp && curtin in-target -- git clone https://github.com/${GITHUB_OWNER_NAME}/mcp-services /opt/mcp
    - curtin in-target -- docker compose -f /opt/mcp/docker-compose.yml up -d
  shutdown: reboot
EOF

touch "$AUTOINSTALL_DIR/meta-data"

# Copier autoinstall dans l’ISO
cp -r "$AUTOINSTALL_DIR" "$EXTRACT_DIR/"

# ------------------------------
# GRUB Autoinstall
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
    awk -v entry="$AUTOINSTALL_ENTRY" 'BEGIN{added=0} /^menuentry / && added==0 {print entry; added=1} {print}' "$GRUB_CFG" > "$GRUB_CFG.new"
    mv "$GRUB_CFG.new" "$GRUB_CFG"
    sed -i '/^set default=/d' "$GRUB_CFG"; echo "set default=0" >> "$GRUB_CFG"
    sed -i '/^set timeout=/d' "$GRUB_CFG"; echo "set timeout=5" >> "$GRUB_CFG"
fi

# ------------------------------
# REBUILD ISO (BIOS + UEFI)
# ------------------------------
EFI_BOOT="$EXTRACT_DIR/EFI/boot/bootx64.efi"
ISOLINUX_MBR="/usr/lib/ISOLINUX/isohdpfx.bin"

echo -e "${GREEN}Création ISO bootable...${NC}"
xorriso -as mkisofs \
  -r -V "$LABEL" \
  -o "$OUTPUT_ISO" \
  -J -joliet-long -l \
  -iso-level 3 \
  -isohybrid-mbr "$ISOLINUX_MBR" \
  -partition_offset 16 \
  -c boot.catalog \
  -b boot/grub/i386-pc/eltorito.img \
    -no-emul-boot -boot-load-size 4 -boot-info-table \
  -eltorito-alt-boot \
  -e "$EFI_BOOT" \
    -no-emul-boot \
  -isohybrid-gpt-basdat \
  "$EXTRACT_DIR"

echo -e "${GREEN}ISO générée : $OUTPUT_ISO${NC}"

# ------------------------------
# OPTIONNEL : gravure sur USB
# ------------------------------
read -p "Voulez-vous graver l'ISO sur clé USB maintenant ? (o/n) " ans
if [[ "$ans" =~ ^[OoYy]$ ]]; then
    read -p "Périphérique USB (ex: /dev/sdb) : " USB_DEV
    sudo dd if="$OUTPUT_ISO" of="$USB_DEV" bs=4M status=progress conv=fsync
    sync
    echo -e "${GREEN}Clé USB prête !${NC}"
fi

echo -e "${GREEN}Build terminé.${NC}"
