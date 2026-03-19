#!/bin/bash
# build-iso.sh – Construction de l'ISO d'installation automatique d'Ubuntu Server et NeurHomIA
# Utilisation : ./build-iso.sh [--force]

set -e
clear 

# ------------------------------
# Paramètres personnalisables
# ------------------------------
DEFAULT_UBUNTU_VERSION="24.04.4"

PROJECT_NAME="NeurHomIA"                # Nom du projet (utilisé pour hostname, dossier, label)
PROJECT_NAME_LOWER=$(echo "$PROJECT_NAME" | tr '[:upper:]' '[:lower:]')
PROJECT_NAME_UPPER=$(echo "$PROJECT_NAME" | tr '[:lower:]' '[:upper:]')

USERNAME="neurhomia"                    # Nom de l'utilisateur système
DEFAULT_PASSWORD="neurhomia"            # Mot de passe par défaut (sera hashé)

GITHUB_OWNER_NAME="moreau66"            # Propriétaire du github 
FIRSTBOOT_SCRIPT_URL="https://raw.githubusercontent.com/${GITHUB_OWNER_NAME}/${PROJECT_NAME}/main/scripts/build-iso2usb/firstboot-config.sh"  

# ------------------------------
# Couleurs
# ------------------------------
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# ------------------------------
# Option --force
# ------------------------------
FORCE_BUILD=false
if [[ "${1:-}" == "--force" ]]; then
    FORCE_BUILD=true
fi

# ------------------------------
# Déterminer le répertoire de travail (même avec sudo)
# ------------------------------
if [ -n "$SUDO_USER" ]; then
    REAL_USER="$SUDO_USER"
    REAL_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
    WORK_DIR="$REAL_HOME/${PROJECT_NAME_LOWER}-iso"
else
    WORK_DIR="$HOME/${PROJECT_NAME_LOWER}-iso"
fi

# ------------------------------
# 1) Demande interactive de la version d'Ubuntu Server à installer
# ------------------------------
echo -e "${YELLOW}1) Quelle version d'Ubuntu Server souhaitez-vous installer ? (défaut : $DEFAULT_UBUNTU_VERSION)"
echo -e "   Format attendu : X.Y.Z (exemple : 24.04.4)${NC}"
read -p "   Version : " USER_VERSION

if [ -z "$USER_VERSION" ]; then
    ISO_VERSION="$DEFAULT_UBUNTU_VERSION"
    echo -e "${GREEN}   Version par défaut sélectionnée : $ISO_VERSION${NC}"
else
    if [[ "$USER_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        ISO_VERSION="$USER_VERSION"
        echo -e "${GREEN}   Version sélectionnée : $ISO_VERSION${NC}"
    else
        echo -e "${RED}   Format de version invalide. Utilisation de la version par défaut $DEFAULT_UBUNTU_VERSION.${NC}"
        ISO_VERSION="$DEFAULT_UBUNTU_VERSION"
    fi
fi

# ------------------------------
# Configuration basée sur la version
# ------------------------------
ISO_FILENAME="ubuntu-${ISO_VERSION}-live-server-amd64.iso"
ISO_URL="https://releases.ubuntu.com/${ISO_VERSION%.*}/ubuntu-${ISO_VERSION}-live-server-amd64.iso"
EXTRACT_DIR="$WORK_DIR/extracted"
AUTOINSTALL_DIR="$WORK_DIR/autoinstall"
OUTPUT_ISO="$WORK_DIR/${PROJECT_NAME_LOWER}-server-${ISO_VERSION}-auto.iso"
LABEL="${PROJECT_NAME_UPPER}_SRV"
# Troncature si le label dépasse 32 caractères (norme ISO)
if [ ${#LABEL} -gt 32 ]; then
    LABEL="${LABEL:0:32}"
fi

# ------------------------------
# 2) Validation de firstboot-config.sh (sections requises)
# ------------------------------
echo ""
echo -e "${YELLOW}2) Validation de firstboot-config.sh...${NC}"

FIRSTBOOT_TMP=$(mktemp /tmp/firstboot-check.XXXXXX)
if wget -q -O "$FIRSTBOOT_TMP" "$FIRSTBOOT_SCRIPT_URL" 2>/dev/null; then
    declare -A SECTIONS=(
        ["01-Bienvenue"]="BIENVENUE"
        ["02-Configuration réseau"]="CONFIGURATION RÉSEAU"
        ["03-Fuseau horaire"]="FUSEAU HORAIRE"
        ["04-Mot de passe"]="MOT DE PASSE"
        ["05-Configuration SSH"]="CONFIGURATION SSH"
        ["06-Pare-feu UFW"]="PARE-FEU UFW"
        ["07-Fail2ban"]="FAIL2BAN"
        ["08-Mises à jour automatiques"]="MISES À JOUR AUTOMATIQUES"
        ["09-Mot de passe MQTT"]="MOT DE PASSE MQTT"
        ["10-Installation Docker"]="INSTALLATION"
        ["11-Utilitaires CLI"]="UTILITAIRES CLI"
        ["12-Finalisation"]="FINALISATION"
    )

    MISSING=0
    for key in $(echo "${!SECTIONS[@]}" | tr ' ' '\n' | sort); do
        section="${key#*-}"
        marker="${SECTIONS[$key]}"
        if grep -qi "$marker" "$FIRSTBOOT_TMP" 2>/dev/null; then
            echo -e "   ${GREEN}✔ $section${NC}"
        else
            echo -e "   ${RED}✘ $section (marqueur '$marker' absent)${NC}"
            MISSING=$((MISSING + 1))
        fi
    done

    if [ "$MISSING" -gt 0 ]; then
        echo ""
        echo -e "   ${RED}⚠ $MISSING section(s) manquante(s) dans firstboot-config.sh${NC}"
        if [ "$FORCE_BUILD" = true ]; then
            echo -e "   ${YELLOW}--force activé : construction forcée malgré les sections manquantes.${NC}"
        else
            echo -e "   ${RED}Build annulé. Utilisez --force pour passer outre.${NC}"
            rm -f "$FIRSTBOOT_TMP"
            exit 1
        fi
    else
        echo -e "   ${GREEN}✅ Toutes les sections requises sont présentes (12/12)${NC}"
    fi
else
    echo -e "   ${YELLOW}⚠ Impossible de télécharger firstboot-config.sh pour validation.${NC}"
    echo -e "   ${YELLOW}  URL : $FIRSTBOOT_SCRIPT_URL${NC}"
    if [ "$FORCE_BUILD" = false ]; then
        echo -e "   ${RED}Build annulé. Utilisez --force pour passer outre.${NC}"
        rm -f "$FIRSTBOOT_TMP"
        exit 1
    fi
fi
rm -f "$FIRSTBOOT_TMP"

# ------------------------------
# 3) Vérification des dépendances
# ------------------------------
echo ""
echo -e "${YELLOW}3) Vérification des dépendances...${NC}"
command -v wget >/dev/null 2>&1 || { echo -e "${RED}   wget est requis. Installez-le avec : sudo apt install wget${NC}"; exit 1; }
command -v 7z >/dev/null 2>&1 || { echo -e "${RED}   p7zip-full est requis. Installez-le avec : sudo apt install p7zip-full${NC}"; exit 1; }
command -v openssl >/dev/null 2>&1 || { echo -e "${RED}   openssl est requis. Installez-le avec : sudo apt install openssl${NC}"; exit 1; }
command -v xorriso >/dev/null 2>&1 || { echo -e "${RED}   xorriso est requis. Installez-le avec : sudo apt install xorriso${NC}"; exit 1; }
echo -e "${GREEN}   Dépendances OK${NC}"

# ------------------------------
# 4) Préparation des dossiers avec sauvegarde de l'ancien autoinstall
# ------------------------------
echo ""
echo -e "${YELLOW}4) Préparation de l'espace de travail...${NC}"
mkdir -p "$WORK_DIR"

# Sauvegarde de l'ancien dossier autoinstall s'il existe
if [ -d "$AUTOINSTALL_DIR" ]; then
    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    BACKUP_AUTOINSTALL="${AUTOINSTALL_DIR}_${TIMESTAMP}"
    mv "$AUTOINSTALL_DIR" "$BACKUP_AUTOINSTALL"
    echo -e "${GREEN}   Ancien dossier autoinstall sauvegardé sous : $BACKUP_AUTOINSTALL${NC}"
fi

rm -rf "$EXTRACT_DIR"
mkdir -p "$EXTRACT_DIR" "$AUTOINSTALL_DIR"

# ------------------------------
# 5) Téléchargement de l'ISO (si non existante)
# ------------------------------
echo ""
if [ ! -f "$WORK_DIR/$ISO_FILENAME" ]; then
    echo -e "${GREEN}5) Téléchargement de l'ISO Ubuntu Server ${ISO_VERSION}...${NC}"
    wget -O "$WORK_DIR/$ISO_FILENAME" "$ISO_URL"
else
    echo -e "${GREEN}5) L'ISO $ISO_FILENAME existe déjà dans $WORK_DIR. Utilisation de la copie locale.${NC}"
fi

# ------------------------------
# 6) Extraction de l'ISO
# ------------------------------
echo ""
echo -e "${YELLOW}6) Extraction de l'ISO Ubuntu Server ${ISO_VERSION}...${NC}"
7z x "$WORK_DIR/$ISO_FILENAME" -o"$EXTRACT_DIR"

# ------------------------------
# 7) Génération du hash du mot de passe
# ------------------------------
echo ""
echo -e "${YELLOW}7) Génération du hash du mot de passe par défaut...${NC}"
PASSWORD_HASH=$(openssl passwd -6 "$DEFAULT_PASSWORD")
echo -e "${GREEN}   Hash généré.${NC}"

# ------------------------------
# 8) Création du fichier user-data
# ------------------------------
echo ""
echo -e "${YELLOW}8) Création du fichier user-data...${NC}"
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
    hostname: ${PROJECT_NAME_LOWER}-box
    username: $USERNAME
    password: "$PASSWORD_HASH"
  ssh:
    install-server: true
    allow-pw: true
  packages:
    - docker.io
    - docker-compose-plugin
    - ufw
    - git
    - whiptail
    - curl
    - language-pack-fr          # Paquet de langue français
    - language-pack-fr-base      # Paquet de base pour le français
    - wfrench                    # Dictionnaire français (optionnel)
  late-commands:
    - mkdir -p /target/opt/${PROJECT_NAME_LOWER}
    - curtin in-target -- wget -O /opt/${PROJECT_NAME_LOWER}/firstboot.sh $FIRSTBOOT_SCRIPT_URL
    - curtin in-target -- chmod +x /opt/${PROJECT_NAME_LOWER}/firstboot.sh
    - |
      cat <<'SERV' > /target/etc/systemd/system/${PROJECT_NAME_LOWER}-firstboot.service
      [Unit]
      Description=${PROJECT_NAME} First Boot Configuration
      After=network-online.target
      Wants=network-online.target

      [Service]
      Type=oneshot
      RemainAfterExit=yes
      ExecStart=/opt/${PROJECT_NAME_LOWER}/firstboot.sh
      StandardOutput=journal+console

      [Install]
      WantedBy=multi-user.target
      SERV
    - curtin in-target -- systemctl enable ${PROJECT_NAME_LOWER}-firstboot.service
  shutdown: reboot
EOF

touch "$AUTOINSTALL_DIR/meta-data"

# Vérification que les fichiers ont bien été créés
if [ ! -f "$AUTOINSTALL_DIR/user-data" ] || [ ! -f "$AUTOINSTALL_DIR/meta-data" ]; then
    echo -e "${RED}   Erreur : les fichiers d'autoinstall n'ont pas été créés correctement.${NC}"
    exit 1
fi
echo -e "${GREEN}   Fichiers d'autoinstall créés avec succès.${NC}"

# ------------------------------
# 9) Intégration de l'autoinstall
# ------------------------------
cp -r "$AUTOINSTALL_DIR" "$EXTRACT_DIR/"

# ------------------------------
# 10) Modification du fichier grub.cfg pour forcer l'autoinstall
# ------------------------------
echo ""
echo -e "${YELLOW}10) Modification du fichier grub.cfg pour forcer l'autoinstall...${NC}"
GRUB_CFG="$EXTRACT_DIR/boot/grub/grub.cfg"
if [ -f "$GRUB_CFG" ]; then
    # Sauvegarde du fichier original
    cp "$GRUB_CFG" "$GRUB_CFG.orig"
    # Ajout des paramètres autoinstall à chaque entrée linux
    sudo sed -i 's|linux /casper/vmlinuz|linux /casper/vmlinuz autoinstall ds=nocloud\;s=/cdrom/autoinstall/|g' "$GRUB_CFG"
    
    if grep -q "autoinstall" "$GRUB_CFG"; then
        echo -e "${GREEN}   Fichier grub.cfg modifié avec succès.${NC}"
      else
        echo -e "ERREUR : la modification de grub.cfg a échoué"
        exit 1
    fi
    
  else
    echo -e "${RED}   Fichier grub.cfg introuvable ! L'autoinstall pourrait ne pas fonctionner.${NC}"
    exit 1
fi

# ------------------------------
# 11) Création de l'ISO avec xorriso (détection automatique)
# ------------------------------
echo ""
echo -e "${YELLOW}11) Création de la nouvelle ISO (avec xorriso)...${NC}"

# Vérification du fichier de boot BIOS
if [ ! -f "$EXTRACT_DIR/boot/grub/i386-pc/eltorito.img" ]; then
    echo -e "${RED}   Erreur : fichier 'boot/grub/i386-pc/eltorito.img' introuvable. Vérifiez la structure de l'ISO extraite.${NC}"
    exit 1
fi

# Détection du fichier de boot UEFI
EFI_PATH=""
if [ -f "$EXTRACT_DIR/boot/grub/efi.img" ]; then
    EFI_PATH="boot/grub/efi.img"
else
    # Recherche insensible à la casse d'un fichier .efi dans le dossier EFI/
    EFI_FILE=$(find "$EXTRACT_DIR/EFI" -type f -iname "*.efi" 2>/dev/null | head -n1)
    if [ -n "$EFI_FILE" ]; then
        EFI_PATH="${EFI_FILE#$EXTRACT_DIR/}"
        echo -e "${GREEN}   Fichier EFI détecté : $EFI_PATH${NC}"
    else
        echo -e "${RED}   Erreur : aucun fichier de boot EFI trouvé (ni efi.img, ni .efi).${NC}"
        exit 1
    fi
fi

# Sauvegarde de l'ancienne ISO si elle existe
if [ -f "$OUTPUT_ISO" ]; then
    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    BACKUP_ISO="${OUTPUT_ISO%.*}_${TIMESTAMP}.${OUTPUT_ISO##*.}"
    mv "$OUTPUT_ISO" "$BACKUP_ISO"
    echo ""
    echo -e "${GREEN}   Ancienne ISO sauvegardée sous : $BACKUP_ISO${NC}"
fi

# Création de l'ISO hybride (BIOS + UEFI)
echo ""
echo -e "${GREEN}   Création de l'ISO...${NC}"
xorriso -as mkisofs -r -V "$LABEL" -J -joliet-long -l \
    -iso-level 3 -no-emul-boot -boot-load-size 4 -boot-info-table \
    -b boot/grub/i386-pc/eltorito.img -c boot.catalog \
    -eltorito-alt-boot -e "$EFI_PATH" -no-emul-boot \
    -isohybrid-gpt-basdat -isohybrid-apm-hfsplus \
    -o "$OUTPUT_ISO" "$EXTRACT_DIR"

if [ $? -eq 0 ]; then
    echo -e "${GREEN}   ISO créée avec succès : $OUTPUT_ISO${NC}"
else
    echo -e "${RED}   Échec de la création de l'ISO. Vérifiez les messages ci-dessus.${NC}"
    exit 1
fi

# ------------------------------
# 12) Validation de l'ISO générée
# ------------------------------
validate_iso() {
    local iso_path="$1"
    local mount_dir="/tmp/${PROJECT_NAME_LOWER}-iso-check"
    local checks_passed=0
    local checks_failed=0

    echo ""
    echo -e "${YELLOW}12) Validation de l'ISO générée...${NC}"
    echo ""

    # Montage de l'ISO
    mkdir -p "$mount_dir"
    if ! mount -o loop,ro "$iso_path" "$mount_dir" 2>/dev/null; then
        # Fallback : essayer avec sudo
        if ! sudo mount -o loop,ro "$iso_path" "$mount_dir" 2>/dev/null; then
            echo -e "  ${YELLOW}⚠ Impossible de monter l'ISO pour validation (droits insuffisants).${NC}"
            echo -e "  ${YELLOW}  Vérification par taille et checksum uniquement.${NC}"
            
            # Vérification taille minimale (> 1 Go = 1073741824 octets)
            local iso_bytes=$(stat -c%s "$iso_path" 2>/dev/null || stat -f%z "$iso_path" 2>/dev/null)
            if [ -n "$iso_bytes" ] && [ "$iso_bytes" -gt 1073741824 ]; then
                echo -e "  ${GREEN}✔ Taille cohérente ($iso_bytes octets > 1 Go)${NC}"
            else
                echo -e "  ${RED}✘ Taille suspecte ($iso_bytes octets < 1 Go)${NC}"
            fi

            # SHA256
            local sha256=$(sha256sum "$iso_path" | cut -d' ' -f1)
            echo -e "  ${CYAN}🔑 SHA256 : $sha256${NC}"
            echo ""
            return
        fi
    fi

    # 1. Vérifier autoinstall/user-data
    if [ -f "$mount_dir/autoinstall/user-data" ]; then
        echo -e "  ${GREEN}✔ autoinstall/user-data présent${NC}"
        checks_passed=$((checks_passed + 1))
    else
        echo -e "  ${RED}✘ autoinstall/user-data MANQUANT${NC}"
        checks_failed=$((checks_failed + 1))
    fi

    # 2. Vérifier autoinstall/meta-data
    if [ -f "$mount_dir/autoinstall/meta-data" ]; then
        echo -e "  ${GREEN}✔ autoinstall/meta-data présent${NC}"
        checks_passed=$((checks_passed + 1))
    else
        echo -e "  ${RED}✘ autoinstall/meta-data MANQUANT${NC}"
        checks_failed=$((checks_failed + 1))
    fi

    # 3. Vérifier que firstboot.sh est référencé dans user-data
    if grep -q "firstboot.sh" "$mount_dir/autoinstall/user-data" 2>/dev/null; then
        echo -e "  ${GREEN}✔ firstboot.sh référencé dans user-data${NC}"
        checks_passed=$((checks_passed + 1))
    else
        echo -e "  ${RED}✘ firstboot.sh NON référencé dans user-data${NC}"
        checks_failed=$((checks_failed + 1))
    fi

    # 4. Vérifier structure boot UEFI
    if [ -d "$mount_dir/EFI" ] || [ -f "$mount_dir/boot/grub/efi.img" ]; then
        echo -e "  ${GREEN}✔ Structure boot UEFI présente${NC}"
        checks_passed=$((checks_passed + 1))
    else
        echo -e "  ${RED}✘ Structure boot UEFI MANQUANTE${NC}"
        checks_failed=$((checks_failed + 1))
    fi

    # 5. Vérifier structure boot BIOS
    if [ -d "$mount_dir/boot/grub/i386-pc" ] || [ -d "$mount_dir/isolinux" ] || [ -f "$mount_dir/boot/grub/i386-pc/eltorito.img" ]; then
        echo -e "  ${GREEN}✔ Structure boot BIOS présente${NC}"
        checks_passed=$((checks_passed + 1))
    else
        echo -e "  ${YELLOW}⚠ Structure boot BIOS absente (UEFI uniquement)${NC}"
    fi

    # 6. Vérification taille minimale
    local iso_bytes=$(stat -c%s "$iso_path" 2>/dev/null || stat -f%z "$iso_path" 2>/dev/null)
    if [ -n "$iso_bytes" ] && [ "$iso_bytes" -gt 1073741824 ]; then
        echo -e "  ${GREEN}✔ Taille cohérente ($(du -h "$iso_path" | cut -f1) > 1 Go)${NC}"
        checks_passed=$((checks_passed + 1))
    else
        echo -e "  ${RED}✘ Taille suspecte ($(du -h "$iso_path" | cut -f1) < 1 Go attendu)${NC}"
        checks_failed=$((checks_failed + 1))
    fi

    # Démontage
    umount "$mount_dir" 2>/dev/null || sudo umount "$mount_dir" 2>/dev/null || true
    rmdir "$mount_dir" 2>/dev/null || true

    # 7. SHA256
    echo ""
    local sha256=$(sha256sum "$iso_path" | cut -d' ' -f1)
    echo -e "  ${CYAN}🔑 SHA256 : $sha256${NC}"

    # Résumé
    echo ""
    if [ "$checks_failed" -eq 0 ]; then
        echo -e "  ${GREEN}✅ Validation réussie ($checks_passed/$checks_passed vérifications OK)${NC}"
    else
        echo -e "  ${RED}⚠ Validation partielle ($checks_passed OK, $checks_failed échouée(s))${NC}"
        echo -e "  ${RED}  L'ISO peut ne pas fonctionner correctement.${NC}"
    fi
    echo ""
}

# Appel de la fonction de validation
validate_iso "$OUTPUT_ISO"

# ------------------------------
# 13) Demande de gravure sur clé USB
# ------------------------------
burn_iso() {
    local iso_path="$1"
    echo ""
    echo -e "${YELLOW}13) Voulez-vous graver cette ISO sur une clé USB ? (o/n)${NC}"
    read -r answer
    if [[ ! "$answer" =~ ^[OoYy]$ ]]; then
        echo -e "${GREEN}   Vous pourrez graver l'ISO plus tard avec la commande :${NC}"
        echo -e "  sudo dd if=$iso_path of=/dev/sdX bs=4M status=progress conv=fsync"
        return
    fi

    # Vérifier les droits sudo
    if ! sudo -v &>/dev/null; then
        echo -e "${RED}   Vous devez avoir les droits sudo pour graver une clé USB.${NC}"
        return
    fi

    # Calculer un hash de vérification (SHA256 des 10 premiers Mo de l'ISO)
    echo ""
    echo -e "${GREEN}   Calcul de l'empreinte de vérification de l'ISO...${NC}"
    local iso_hash=$(dd if="$iso_path" bs=1M count=10 2>/dev/null | sha256sum | awk '{print $1}')
    echo -e "${GREEN}   Empreinte (10 premiers Mo) : $iso_hash"

    while true; do
        echo ""
        echo -e "${YELLOW}   Recherche des périphériques USB...${NC}"
        
        # Liste des périphériques de type disk, avec transport USB, et taille < 64 Go
        mapfile -t devices < <(lsblk -d -o NAME,SIZE,TYPE,TRAN -n -l 2>/dev/null | grep -E 'disk.*usb' | awk '$2 ~ /^[0-9.]+[GM]?/ { if ($2 ~ /G/ && $2+0 < 64) print; else if ($2 ~ /M/ && $2+0 < 64000) print }')
        
        # Si pas de périphérique USB détecté, élargir à tout disk de taille < 64G
        if [ ${#devices[@]} -eq 0 ]; then
            mapfile -t devices < <(lsblk -d -o NAME,SIZE,TYPE -n -l 2>/dev/null | grep disk | awk '$2 ~ /^[0-9.]+[GM]?/ { if ($2 ~ /G/ && $2+0 < 64) print; else if ($2 ~ /M/ && $2+0 < 64000) print }')
        fi

        if [ ${#devices[@]} -eq 0 ]; then
            echo -e "${RED}   Aucune clé USB détectée.${NC}"
            echo -e "${YELLOW}  Insérez une clé USB, puis appuyez sur Entrée pour réessayer, ou tapez 'q' pour quitter.${NC}"
            read -r retry
            if [[ "$retry" == "q" ]]; then
                echo -e "${GREEN}   Gravure annulée.${NC}"
                return
            fi
            continue
        fi

        # Afficher les périphériques trouvés
        echo -e "${GREEN}   Périphériques détectés :"
        local i=1
        for dev in "${devices[@]}"; do
            name=$(echo "$dev" | awk '{print $1}')
            size=$(echo "$dev" | awk '{print $2}')
            echo "   $i) /dev/$name ($size)"
            ((i++))
        done
        echo -e "${YELLOW}   Choisissez le numéro du périphérique à utiliser, ou 'q' pour annuler :${NC}"
        read -r choice
        if [[ "$choice" == "q" ]]; then
            echo -e "${GREEN}   Gravure annulée.${NC}"
            return
        fi
        if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt ${#devices[@]} ]; then
            echo -e "${RED}   Choix invalide.${NC}"
            continue
        fi

        selected_dev="/dev/$(echo "${devices[$((choice-1))]}" | awk '{print $1}')"

        # Vérifier que le périphérique existe toujours
        if [ ! -e "$selected_dev" ]; then
            echo -e "${RED}   Le périphérique $selected_dev n'existe plus. Il a peut-être été retiré.${NC}"
            continue
        fi

        # Vérifier la taille de la clé par rapport à l'ISO via sysfs
        iso_size=$(stat -c%s "$iso_path")
        devname=$(basename "$selected_dev")
        if [ -e "/sys/block/$devname/size" ]; then
            sectors=$(cat "/sys/block/$devname/size")
            dev_size=$((sectors * 512))
        else
            echo -e "${RED}   Impossible de déterminer la taille du périphérique $selected_dev.${NC}"
            continue
        fi

        if [ "$iso_size" -gt "$dev_size" ]; then
            echo -e "${RED}   L'ISO ($(numfmt --to=iec $iso_size)) est plus grande que la clé ($(numfmt --to=iec $dev_size)). Impossible de graver.${NC}"
            continue
        fi

        # Vérifier si le périphérique a des partitions montées
        mounted_partitions=$(lsblk -no NAME,MOUNTPOINT "$selected_dev" 2>/dev/null | awk '$2 {print $1, $2}')
        if [ -n "$mounted_partitions" ]; then
            echo -e "${RED}  Le périphérique $selected_dev a des partitions montées :${NC}"
            echo "$mounted_partitions"
            echo -e "${YELLOW}  Voulez-vous démonter automatiquement ces partitions ? (o/N)${NC}"
            read -r unmount_answer
            if [[ "$unmount_answer" =~ ^[OoYy]$ ]]; then
                mount_points=$(echo "$mounted_partitions" | awk '{print $2}')
                for mp in $mount_points; do
                    echo -e "   Démontage de $mp..."
                    sudo umount "$mp" || {
                        echo -e "${RED}   Échec du démontage de $mp. Vérifiez que le point de montage n'est pas utilisé.${NC}"
                        continue 2
                    }
                done
            else
                echo -e "${RED}   Veuillez démonter manuellement les partitions avant de continuer.${NC}"
                continue
            fi
        fi

        echo -e "${RED}   Attention : vous allez écraser toutes les données sur $selected_dev.${NC}"
        echo -e "${YELLOW}   Êtes-vous sûr de vouloir continuer ? (o/n)${NC}"
        read -r confirm
        if [[ ! "$confirm" =~ ^[OoYy]([Ee][Ss]?)?$ ]]; then
            echo -e "${GREEN}   Gravure annulée.${NC}"
            return
        fi

        # Exécuter la gravure
        echo ""
        echo -e "${YELLOW}   Gravure de l'ISO sur $selected_dev...${NC}"
        sudo dd if="$iso_path" of="$selected_dev" bs=4M status=progress conv=fsync

        if [ $? -ne 0 ]; then
            echo -e "${RED}   Erreur lors de la gravure. Vérifiez que vous avez les droits sudo et que le périphérique n'est pas monté.${NC}"
            continue
        fi

        # Vider les caches et forcer l'écriture
        sync
        sudo blockdev --flushbufs "$selected_dev" 2>/dev/null || true  # Ignorer si échec

        # Vérification par hash (10 premiers Mo)
        echo ""
        echo -e "${YELLOW}   Vérification de l'écriture par comparaison d'empreinte...${NC}"
        local dev_hash=$(sudo dd if="$selected_dev" bs=1M count=10 2>/dev/null | sha256sum | awk '{print $1}')
        if [ "$dev_hash" = "$iso_hash" ]; then
            echo -e "${GREEN}   Vérification réussie : l'empreinte correspond. La gravure est valide."
            echo -e "   Vous pouvez maintenant installer Ubuntu Server sur votre mini-PC avec cette clé.${NC}"
        else
            echo -e "${RED}   Échec de la vérification : l'empreinte ne correspond pas."
            echo -e "   ISO hash   : $iso_hash"
            echo -e "   Clé hash   : $dev_hash"
            echo -e "${YELLOW}   Voulez-vous réessayer la gravure sur le même périphérique ? (o/n)${NC}"
            read -r retry_write
            if [[ "$retry_write" =~ ^[OoYy]$ ]]; then
                continue
            else
                echo -e "${GREEN}   Gravure annulée.${NC}"
            fi
        fi
        break
    done
}

# Appel de la fonction de gravure
burn_iso "$OUTPUT_ISO"

# Conseils pour vérification manuelle (optionnel)
echo -e "${YELLOW}"
echo -e "========================================"
echo -e "Pour vérifier la présence du dossier autoinstall sur la clé, vous pouvez monter sa première partition avec la commande :"
echo -e " sudo mount /dev/sdX1 /mnt && ls /mnt/autoinstall"
echo -e "(Remplacez 'sdX' par le périphérique de votre clé, par exemple sdb)"
echo -e "========================================${NC}"

# ------------------------------
# Finalisation
# ------------------------------
echo -e "${GREEN}"
echo -e "========================================"
echo -e "Processus terminé."
echo -e "ISO disponible : $OUTPUT_ISO"
echo -e "========================================${NC}"
echo ""
