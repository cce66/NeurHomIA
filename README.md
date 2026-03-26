# 🚀 NeurHomIA — Construction d'ISO Ubuntu Server

Génération automatisée d'une image ISO Ubuntu Server préconfigurée avec **autoinstall**, **LVM**, **Docker** et un script de première configuration exécuté au boot.

---

## 🏷️ Tags

* Ubuntu 24.04 LTS
* MIT License
* BIOS + UEFI
* bash
* xorriso
* systemd

---

## 1. ⚙️ Fonctionnalités

* 🤖 **Installation 100 % automatisée**
  Autoinstall subiquity piloté par YAML, sans interaction humaine.

* 💾 **Partitionnement LVM**
  LVM préconfiguré avec DHCP, locale et clavier FR.

* 🔐 **SSH & Sécurité**
  Authentification par mot de passe ou clé + UFW + fail2ban.

* 📦 **Paquets inclus**
  Docker, Git, UFW, langues FR + paquets personnalisés.

* ⚡ **Script first-boot**
  Service systemd exécuté après disponibilité réseau.

* 💿 **ISO hybride**
  Compatible BIOS + UEFI, gravure USB incluse.

---

## 2. 📁 Structure du dépôt

```text
build-iso2usb/
├── build-iso.sh                # Script principal
├── autoinstall/
│   ├── user-data.template      # Template YAML
│   └── meta-data              # Optionnel
├── boot/grub/
│   └── grub.cfg.template      # Template GRUB
└── scripts/
    └── firstboot.sh           # Script post-install
```

---

## 3. 🧰 Prérequis

* Linux (Ubuntu 20.04 / 22.04 / 24.04)
* Accès `sudo`
* Internet
* ~6 Go d'espace disque

### Dépendances

```bash
sudo apt install wget p7zip-full openssl xorriso \
  squashfs-tools schroot rsync syslinux-utils isolinux genisoimage
```

---

## 4. ▶️ Utilisation

### 1. Cloner

```bash
git clone https://github.com/cce66/NeurHomIA.git
cd NeurHomIA
```

### 2. Personnalisation (optionnel)

```bash
PROJECT_NAME="NeurHomIA"
GITHUB_OWNER_NAME="cce66"
DEFAULT_UBUNTU_VERSION="24.04.4"
```

### 3. Lancer

```bash
chmod +x build-iso.sh
./build-iso.sh
```

### 4. Graver sur USB

```bash
sudo dd if=~/neurhomia-key/neurhomia-server-24.04.4-auto.iso \
  of=/dev/sdX bs=4M status=progress conv=fsync
```

⚠️ **Attention :** `/dev/sdX` sera entièrement effacé.

---

## 5. 🔄 Pipeline de construction

1. Choix version Ubuntu
2. Validation `firstboot.sh`
3. Installation dépendances
4. Téléchargement ISO
5. Génération hash mot de passe
6. Templates autoinstall
7. Validation YAML
8. Injection dans ISO
9. Template GRUB
10. Build ISO (xorriso)
11. Vérification SHA256
12. Gravure USB (optionnelle)

---

## 6. 🧩 Placeholders

### autoinstall (`user-data.template`)

| Placeholder         | Description   |
| ------------------- | ------------- |
| `__HOSTNAME__`      | neurhomia-box |
| `__USERNAME__`      | utilisateur   |
| `__PASSWORD_HASH__` | hash openssl  |
| `__PROJECT_LOWER__` | neurhomia     |
| `__PROJECT_NAME__`  | NeurHomIA     |
| `__FIRSTBOOT_URL__` | script GitHub |

### GRUB (`grub.cfg.template`)

| Placeholder         | Valeur    |
| ------------------- | --------- |
| `__PROJECT_NAME__`  | NeurHomIA |
| `__PROJECT_LOWER__` | neurhomia |
| `__PROJECT_UPPER__` | NEURHOMIA |

### Exemple GRUB

```cfg
set default=0
set timeout=10

menuentry "Autoinstall Ubuntu Server __PROJECT_NAME__" {
    set gfxpayload=keep
    linux  /casper/vmlinuz autoinstall \
           "ds=nocloud;s=/cdrom/autoinstall/" debug --- autoinstall
    initrd /casper/initrd
}
```

---

## 7. 🚀 Script firstboot

Chemin : `/opt/neurhomia/firstboot.sh`

### Actions typiques

* Fuseau horaire
* Changement mot de passe
* SSH (clés)
* UFW + fail2ban
* Docker
* MQTT

ℹ️ Validation automatique des sections obligatoires.

---

## 8. ⚙️ Options CLI

```bash
./build-iso.sh --noforce
```

* `--noforce` : stop si erreur validation

---

## 9. 📦 Sortie

```text
~/neurhomia-key/neurhomia-server-<version>-auto.iso
```

SHA256 affiché en fin de build.

---

## 10. 🛠️ Dépannage

### Dépendances

```bash
sudo apt update
sudo apt install wget p7zip-full openssl xorriso \
  squashfs-tools schroot rsync syslinux-utils isolinux genisoimage
```

### wget KO

Tester :

```bash
wget -O /tmp/test https://raw.githubusercontent.com/cce66/NeurHomIA/main/build-iso2usb/autoinstall/user-data.template
```

### YAML

```bash
sudo apt install python3-yaml
```

### eltorito.img manquant

→ ISO Ubuntu incompatible

### GRUB non pris en compte

→ vérifier emplacement template

---

## 📜 Licence

Apache 2.0

---

## 🤝 Crédits

* cce66

---

## 🔗 Liens

* GitHub : [https://github.com/cce66/NeurHomIA](https://github.com/cce66/NeurHomIA)
