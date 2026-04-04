#!/bin/bash
set -e

# =========================
# 01 - ASK UBUNTU VERSION
# =========================
01_ask_ubuntu_version() {
    echo "[1] Ubuntu version..."
    UBUNTU_VERSION="22.04.4"
    ISO_NAME="ubuntu-${UBUNTU_VERSION}-live-server-amd64.iso"
    ISO_URL="https://releases.ubuntu.com/22.04/${ISO_NAME}"
}

# =========================
# 🔥 02 - VALIDATE FIRSTBOOT (NEUTRALISÉ)
# =========================
02_validate_firstboot_script() {
    echo "[2] Skip firstboot validation (new model)"
}

# =========================
# 03 - CHECK DEPENDENCIES
# =========================
03_check_dependencies() {
    echo "[3] Check dependencies..."
    for cmd in wget xorriso rsync sed; do
        command -v $cmd >/dev/null || { echo "Missing $cmd"; exit 1; }
    done
}

# =========================
# 04 - PREPARE WORKSPACE
# =========================
04_prepare_workspace() {
    WORKDIR="$(pwd)/build"
    ISO_DIR="$WORKDIR/iso"
    EXTRACT_DIR="$WORKDIR/extract"
    AUTOINSTALL_DIR="$EXTRACT_DIR/nocloud"

    rm -rf "$WORKDIR"
    mkdir -p "$ISO_DIR" "$EXTRACT_DIR"
}

# =========================
# 05 - DOWNLOAD ISO
# =========================
05_download_iso() {
    cd "$ISO_DIR"
    if [ ! -f "$ISO_NAME" ]; then
        wget "$ISO_URL"
    fi
}

# =========================
# 06 - EXTRACT ISO
# =========================
06_extract_iso() {
    sudo mount -o loop "$ISO_DIR/$ISO_NAME" /mnt
    rsync -a /mnt/ "$EXTRACT_DIR"
    sudo umount /mnt
    chmod -R +w "$EXTRACT_DIR"
}

# =========================
# 07 - PREPARE AUTOINSTALL
# =========================
07_prepare_autoinstall_dir() {
    mkdir -p "$AUTOINSTALL_DIR"
}

# =========================
# 🔥 08 - CREATE AUTOINSTALL (MODIFIÉ)
# =========================
08_create_autoinstall_files() {

    echo "[8] Create autoinstall (frontend mode)"

    cat > "$AUTOINSTALL_DIR/user-data" <<EOF
#cloud-config
autoinstall:
  version: 1

  identity:
    hostname: neurhomia
    username: ubuntu
    password: "\$6\$rounds=4096\$xyz\$xyzxyzxyzxyzxyzxyzxyzxyzxyzxyzxyzxyz"

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

echo '[OK] UI disponible sur http://IP:8081'
EOL"

    - curtin in-target --target=/target chmod +x /opt/neurhomia/firstboot.sh
    - curtin in-target --target=/target ln -s /opt/neurhomia/firstboot.sh /etc/rc.local
EOF

    echo "instance-id: iid-local01" > "$AUTOINSTALL_DIR/meta-data"
}

# =========================
# 09 - INTEGRATE AUTOINSTALL
# =========================
09_integrate_autoinstall() {
    echo "[9] Integrate autoinstall (noop, déjà dans extract)"
}

# =========================
# 10 - MODIFY GRUB
# =========================
10_modify_grub_cfg() {
    sed -i 's|---| autoinstall ds=nocloud\\;s=/cdrom/nocloud/ ---|g' \
    "$EXTRACT_DIR/boot/grub/grub.cfg"
}

# =========================
# 11 - CREATE ISO (nom respecté)
# =========================
11_create_iso() {

    CUSTOM_ISO="$WORKDIR/neurhomia-installer.iso"

    cd "$EXTRACT_DIR"

    sudo xorriso -as mkisofs \
      -r -V "NeurHomIA Installer" \
      -o "$CUSTOM_ISO" \
      -J -l \
      -b boot/grub/i386-pc/eltorito.img \
      -c boot.catalog \
      -no-emul-boot -boot-load-size 4 -boot-info-table \
      --grub2-boot-info \
      -eltorito-alt-boot \
      -e EFI/boot/bootx64.efi \
      -no-emul-boot .
}

# =========================
# 12 - VALIDATE ISO
# =========================
12_validate_iso() {
    if [ ! -f "$CUSTOM_ISO" ]; then
        echo "ISO failed"
        exit 1
    fi
}

# =========================
# 13 - BURN ISO
# =========================
13_burn_iso() {
    echo "Burn ISO? (y/n)"
    read -r R

    if [ "$R" != "y" ]; then return; fi

    lsblk
    read -r DISK

    sudo dd if="$CUSTOM_ISO" of="/dev/$DISK" bs=4M status=progress
}

# =========================
# MAIN
# =========================

01_ask_ubuntu_version
02_validate_firstboot_script
03_check_dependencies
04_prepare_workspace
05_download_iso
06_extract_iso
07_prepare_autoinstall_dir
08_create_autoinstall_files
09_integrate_autoinstall
10_modify_grub_cfg
11_create_iso
12_validate_iso
13_burn_iso

echo "[DONE]"
