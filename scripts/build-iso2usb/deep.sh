#!/bin/bash
# Script : creer_live_usb_perso.sh
# Description : Personnalise une ISO Ubuntu pour exécuter un script au démarrage,
#               puis crée une clé USB bootable.
# Utilisation : sudo ./creer_live_usb_perso.sh -i <iso> -s <script> [-o <output.iso>] [-d <périphérique>]

set -euo pipefail

rouge='\033[0;31m'
vert='\033[0;32m'
jaune='\033[1;33m'
neutre='\033[0m'

afficher_aide() {
    cat <<EOF
Utilisation : $0 -i <image.iso> -s <script.sh> [-o <fichier.iso>] [-d <périphérique>] [-h]

    -i    Fichier ISO source (Ubuntu Desktop 24.04 de préférence)
    -s    Script à exécuter au démarrage de la session live
    -o    Fichier ISO de sortie (optionnel, par défaut : custom_$(basename "$ISO"))
    -d    Périphérique USB (ex: /dev/sdb) pour flasher directement l'ISO personnalisée
    -h    Affiche cette aide

Exemple : sudo $0 -i ubuntu-24.04.iso -s mon_script.sh -d /dev/sdc
EOF
    exit 0
}

# Vérifier les dépendances
verifier_dependances() {
    local deps=("mount" "umount" "cp" "mkdir" "rm" "chroot" "mksquashfs" "xorriso" "parted" "mkfs.ext4" "dd")
    local missing=()
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            missing+=("$dep")
        fi
    done
    if [ ${#missing[@]} -ne 0 ]; then
        echo -e "${rouge}Dépendances manquantes : ${missing[*]}${neutre}"
        echo "Installez-les avec : sudo apt install squashfs-tools xorriso gdisk"
        exit 1
    fi
}

# Nettoyage en cas d'interruption ou d'erreur
nettoyer() {
    echo -e "${jaune}Nettoyage...${neutre}"
    # Démontage des systèmes de fichiers montés dans le chroot
    if [ -d "$WORK_DIR/squashfs/proc" ]; then
        umount -lf "$WORK_DIR/squashfs/proc" 2>/dev/null || true
    fi
    if [ -d "$WORK_DIR/squashfs/sys" ]; then
        umount -lf "$WORK_DIR/squashfs/sys" 2>/dev/null || true
    fi
    if [ -d "$WORK_DIR/squashfs/dev" ]; then
        umount -lf "$WORK_DIR/squashfs/dev" 2>/dev/null || true
    fi
    if [ -d "$WORK_DIR/squashfs/dev/pts" ]; then
        umount -lf "$WORK_DIR/squashfs/dev/pts" 2>/dev/null || true
    fi
    if [ -d "$WORK_DIR/squashfs/run/dbus" ]; then
        umount -lf "$WORK_DIR/squashfs/run/dbus" 2>/dev/null || true
    fi
    if [ -f "$WORK_DIR/squashfs/etc/resolv.conf" ]; then
        rm -f "$WORK_DIR/squashfs/etc/resolv.conf"
    fi
    if [ -d "$WORK_DIR/iso" ]; then
        umount -lf "$WORK_DIR/iso" 2>/dev/null || true
    fi
    # Suppression du répertoire de travail
    if [ -n "${WORK_DIR:-}" ] && [ -d "$WORK_DIR" ]; then
        rm -rf "$WORK_DIR"
    fi
    exit 1
}

# --- Variables par défaut ---
ISO=""
SCRIPT=""
OUTPUT_ISO=""
USB_DEV=""
WORK_DIR=""

trap nettoyer INT TERM EXIT

# --- Options ---
while getopts "i:s:o:d:h" opt; do
    case "$opt" in
        i) ISO="$OPTARG" ;;
        s) SCRIPT="$OPTARG" ;;
        o) OUTPUT_ISO="$OPTARG" ;;
        d) USB_DEV="$OPTARG" ;;
        h) afficher_aide ;;
        *) afficher_aide ;;
    esac
done

if [ "$EUID" -ne 0 ]; then
    echo -e "${rouge}Ce script doit être exécuté avec sudo.${neutre}"
    exit 1
fi

if [ -z "$ISO" ] || [ -z "$SCRIPT" ]; then
    echo -e "${rouge}Les options -i et -s sont obligatoires.${neutre}"
    afficher_aide
fi

if [ ! -f "$ISO" ]; then
    echo -e "${rouge}Fichier ISO introuvable : $ISO${neutre}"
    exit 1
fi

if [ ! -f "$SCRIPT" ]; then
    echo -e "${rouge}Script introuvable : $SCRIPT${neutre}"
    exit 1
fi

if [ -n "$USB_DEV" ] && [ ! -b "$USB_DEV" ]; then
    echo -e "${rouge}Périphérique USB invalide : $USB_DEV${neutre}"
    exit 1
fi

# Nom de sortie par défaut
if [ -z "$OUTPUT_ISO" ]; then
    OUTPUT_ISO="custom_$(basename "$ISO")"
fi

# Vérifier les dépendances
verifier_dependances

# --- Préparation du répertoire de travail ---
WORK_DIR=$(mktemp -d -t livecd_custom_XXXXXX)
echo -e "${vert}Répertoire de travail : $WORK_DIR${neutre}"
cd "$WORK_DIR"

mkdir -p iso squashfs

# --- Étape 1 : Extraire l'ISO ---
echo -e "${vert}[1/6] Extraction du contenu de l'ISO...${neutre}"
mount -o loop "$ISO" /mnt
cp -av /mnt/. iso/
umount /mnt

# --- Étape 2 : Extraire le squashfs ---
echo -e "${vert}[2/6] Extraction du système de fichiers (squashfs)...${neutre}"
mount -t squashfs -o loop iso/casper/filesystem.squashfs /mnt
cp -av /mnt/. squashfs/
umount /mnt

# --- Étape 3 : Préparer le chroot ---
echo -e "${vert}[3/6] Préparation du chroot...${neutre}"
mount --bind /proc squashfs/proc
mount --bind /sys squashfs/sys
mount --bind /dev squashfs/dev
mount --bind /dev/pts squashfs/dev/pts
mount --bind /run/dbus squashfs/run/dbus 2>/dev/null || true

# Copier la configuration réseau et les dépôts (optionnel)
cp /etc/resolv.conf squashfs/etc/resolv.conf
# cp /etc/apt/sources.list squashfs/etc/apt/sources.list  # Attention : même version d'Ubuntu

# --- Étape 4 : Ajouter le script et le configurer au démarrage ---
echo -e "${vert}[4/6] Ajout du script et configuration du démarrage...${neutre}"

# Copier le script dans le chroot
SCRIPT_NAME=$(basename "$SCRIPT")
cp "$SCRIPT" "squashfs/usr/local/bin/$SCRIPT_NAME"
chmod 755 "squashfs/usr/local/bin/$SCRIPT_NAME"

# Créer un fichier .desktop pour l'autostart (exécution au lancement de la session graphique)
# Utiliser le répertoire /etc/xdg/autostart/ pour démarrer avec l'utilisateur 'ubuntu'
mkdir -p squashfs/etc/xdg/autostart
cat > "squashfs/etc/xdg/autostart/script_perso.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Mon script personnalisé
Exec=/usr/local/bin/$SCRIPT_NAME
X-GNOME-Autostart-enabled=true
NoDisplay=true
EOF

# Option : ajouter un fichier dans /etc/profile.d/ si on veut l'exécuter dans tous les shells (pas seulement graphique)
# Attention : cela s'exécutera aussi en mode console.
cat > "squashfs/etc/profile.d/99-mon_script.sh" <<EOF
#!/bin/bash
/usr/local/bin/$SCRIPT_NAME &
EOF
chmod 755 "squashfs/etc/profile.d/99-mon_script.sh"

# (Facultatif) On peut également ajouter un service systemd si besoin, mais pour un script simple, autostart suffit.

# --- Étape 5 : Mise à jour de l'initrd (si nécessaire) et nettoyage ---
echo -e "${vert}[5/6] Nettoyage du chroot et mise à jour de l'initrd...${neutre}"

# Entrer dans le chroot pour mettre à jour l'initrd (au cas où le noyau aurait changé)
# On le fait même si ce n'est pas indispensable, cela ne pose pas de problème.
chroot squashfs update-initramfs -u -k all

# Sortir du chroot et démonter
exit 0 # pour quitter le shell temporaire
# On redémonte
umount -lf squashfs/proc
umount -lf squashfs/sys
umount -lf squashfs/dev/pts
umount -lf squashfs/dev
umount -lf squashfs/run/dbus 2>/dev/null || true
rm -f squashfs/etc/resolv.conf

# --- Étape 6 : Reconstruire le squashfs et l'ISO ---
echo -e "${vert}[6/6] Reconstruction du squashfs et de l'ISO...${neutre}"

# Régénérer le manifest
chmod a+w iso/casper/filesystem.manifest
chroot squashfs dpkg-query -W --showformat='${Package}  ${Version}\n' > iso/casper/filesystem.manifest
chmod go-w iso/casper/filesystem.manifest

# Supprimer l'ancien squashfs
rm -f iso/casper/filesystem.squashfs

# Créer le nouveau squashfs (compression zstd, niveau 22, progress)
cd squashfs
mksquashfs . ../iso/casper/filesystem.squashfs -comp zstd -Xcompression-level 22 -progress
cd ..

# Mettre à jour les fichiers noyau si besoin (si le noyau a changé dans le squashfs)
# On prend le premier vmlinuz trouvé (attention au nom exact)
if ls squashfs/boot/vmlinuz-* 1>/dev/null 2>&1; then
    KERNEL=$(ls squashfs/boot/vmlinuz-* | head -1)
    INITRD=$(ls squashfs/boot/initrd.img-* | head -1)
    if [ -f "$KERNEL" ] && [ -f "$INITRD" ]; then
        cp "$KERNEL" iso/casper/vmlinuz
        cp "$INITRD" iso/casper/initrd.lz
    fi
fi

# Recalculer les sommes MD5
cd iso
find . -path ./isolinux -prune -o -type f -not -name md5sum.txt -print0 | xargs -0 md5sum | tee md5sum.txt

# Télécharger les fichiers boot nécessaires (si absents)
cd "$WORK_DIR"
if [ ! -f boot_hybrid.img ] || [ ! -f efi.img ]; then
    wget -q https://archive.org/download/boot_ubuntu_gpt.tar/boot_ubuntu_gpt.tar.gz
    gunzip boot_ubuntu_gpt.tar.gz
    tar -xf boot_ubuntu_gpt.tar
    rm -f boot_ubuntu_gpt.tar
fi

# Construire l'ISO avec xorriso
xorriso -as mkisofs -r \
    -V "Ubuntu custom" \
    -o "$OUTPUT_ISO" \
    --grub2-mbr boot_hybrid.img \
    -partition_offset 16 \
    --mbr-force-bootable \
    -append_partition 2 28732ac11ff8d211ba4b00a0c93ec93b efi.img \
    -appended_as_gpt \
    -iso_mbr_part_type a2a0d0ebe5b9334487c068b6b72699c7 \
    -c '/boot.catalog' \
    -b '/boot/grub/i386-pc/eltorito.img' \
        -no-emul-boot -boot-load-size 4 -boot-info-table --grub2-boot-info \
    -eltorito-alt-boot \
    -e '--interval:appended_partition_2:::' \
        -no-emul-boot \
    iso/

# Rendre l'ISO hybride (pour clé USB)
if command -v isohybrid >/dev/null 2>&1; then
    isohybrid "$OUTPUT_ISO"
fi

echo -e "${vert}ISO personnalisée créée : $OUTPUT_ISO${neutre}"

# --- Étape 7 : Flasher sur USB si demandé ---
if [ -n "$USB_DEV" ]; then
    echo -e "${vert}Flash de l'ISO sur $USB_DEV...${neutre}"
    # Vérifier que le périphérique n'est pas monté
    mount | grep "^$USB_DEV" && umount "$USB_DEV"* 2>/dev/null || true
    # Utiliser dd
    if command -v pv >/dev/null 2>&1; then
        pv "$OUTPUT_ISO" | dd of="$USB_DEV" bs=4M status=none oflag=sync
    else
        dd if="$OUTPUT_ISO" of="$USB_DEV" bs=4M status=progress oflag=sync
    fi
    sync
    echo -e "${vert}Clé USB prête.${neutre}"
fi

# Supprimer le répertoire de travail (sauf si on veut le garder pour debug)
trap - EXIT
nettoyer
echo -e "${vert}Terminé.${neutre}"
