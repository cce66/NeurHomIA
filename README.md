# 🚀 NeurHomIA — Construction d'ISO Ubuntu Server

> 🔥 Génération automatisée d'une ISO Ubuntu Server prête à l’emploi avec **autoinstall**, **LVM**, **Docker** et configuration post-install.

<p align="center">
  <img src="https://img.shields.io/badge/Ubuntu-24.04_LTS-E95420?logo=ubuntu&logoColor=white">
  <img src="https://img.shields.io/badge/License-Apache_2.0-blue">
  <img src="https://img.shields.io/badge/Boot-BIOS%20%2B%20UEFI-green">
  <img src="https://img.shields.io/badge/Automation-100%25-success">
</p>

---

## 📚 Sommaire

* [✨ Fonctionnalités](#-fonctionnalités)
* [⚡ Quick Start](#-quick-start)
* [🧰 Prérequis](#-prérequis)
* [🪜 Installation détaillée](#-installation-détaillée)
* [⚙️ Fonctionnement du script](#-fonctionnement-du-script)
* [💿 Gravure USB](#-gravure-usb)
* [📁 Structure du dépôt](#-structure-du-dépôt)
* [🧩 Placeholders](#-placeholders)
* [🚀 Script firstboot](#-script-firstboot)
* [⚙️ Options CLI](#-options-cli)
* [🛠️ Dépannage](#-dépannage)

---

## ✨ Fonctionnalités

* 🤖 Installation **100% automatisée** via autoinstall
* 💾 Partitionnement **LVM prêt à l’emploi**
* 🔐 Sécurisation automatique (**SSH, UFW, fail2ban**)
* 📦 Installation de **Docker + outils essentiels**
* ⚡ Script **firstboot exécuté via systemd**
* 💿 ISO **hybride BIOS + UEFI**

---

## ⚡ Quick Start

```bash
mkdir -p ~/NeurHomIA-Key
wget -O ~/NeurHomIA-Key/build-iso.sh https://raw.githubusercontent.com/cce66/NeurHomIA/main/build-iso.sh
chmod +x ~/NeurHomIA-Key/build-iso.sh
cd ~/NeurHomIA-Key
sudo bash build-iso.sh
```

---

## 🧰 Prérequis

* 💻 Ubuntu 20.04 / 22.04 / 24.04
* 🌐 Connexion Internet
* 💾 ~6 Go disque
* 🔐 Accès sudo

### 📦 Dépendances

Installées automatiquement si absentes :

```bash
wget p7zip-full openssl xorriso squashfs-tools schroot rsync syslinux-utils isolinux genisoimage
```

---

## 🪜 Installation détaillée

### 1. 📁 Créer le répertoire

```bash
mkdir -p ~/NeurHomIA-Key
```

### 2. 📶 Télécharger le script

```bash
wget -O ~/NeurHomIA-Key/build-iso.sh https://raw.githubusercontent.com/cce66/NeurHomIA/main/build-iso.sh
```

### 3. 🛠️ Rendre exécutable

```bash
chmod +x ~/NeurHomIA-Key/build-iso.sh
```

### 4. ▶️ Exécuter

```bash
cd ~/NeurHomIA-Key
sudo bash build-iso.sh
```

💡 Si lancé sans sudo, le script demandera le mot de passe lorsque nécessaire.

---

## ⚙️ Fonctionnement du script

Le script exécute les étapes suivantes :

1. 🔍 Validation du script `firstboot.sh`
2. 📦 Installation des dépendances
3. 🌐 Téléchargement de l’ISO Ubuntu
4. 📂 Extraction de l’ISO
5. 🔐 Génération du hash mot de passe
6. 🧩 Génération des fichiers autoinstall
7. ✅ Validation YAML
8. 💉 Injection dans l’ISO
9. ⚙️ Configuration GRUB
10. 💿 Construction ISO finale
11. 🔎 Vérification SHA256
12. 💽 Proposition de gravure USB

---

## 💿 Gravure USB

```bash
sudo dd if=~/neurhomia-key/neurhomia-server-24.04.4-auto.iso \
  of=/dev/sdX bs=4M status=progress conv=fsync
```

⚠️ **Attention : destruction complète des données sur le disque cible**

---

## 📁 Structure du dépôt

```text
build-iso2usb/
├── build-iso.sh
├── autoinstall/
│   ├── user-data.template
│   └── meta-data
├── boot/grub/
│   └── grub.cfg.template
└── scripts/
    └── firstboot.sh
```

---

## 🧩 Placeholders

### autoinstall

| Placeholder         | Description   |
| ------------------- | ------------- |
| `__HOSTNAME__`      | neurhomia-box |
| `__USERNAME__`      | utilisateur   |
| `__PASSWORD_HASH__` | hash openssl  |
| `__PROJECT_LOWER__` | neurhomia     |
| `__PROJECT_NAME__`  | NeurHomIA     |
| `__FIRSTBOOT_URL__` | URL script    |

### GRUB

| Placeholder         | Valeur    |
| ------------------- | --------- |
| `__PROJECT_NAME__`  | NeurHomIA |
| `__PROJECT_LOWER__` | neurhomia |
| `__PROJECT_UPPER__` | NEURHOMIA |

---

## 🚀 Script firstboot

📍 `/opt/neurhomia/firstboot.sh`

### Actions exécutées

* 🌍 Configuration timezone
* 🔐 Sécurisation accès
* 🔑 Configuration SSH
* 🔥 UFW + fail2ban
* 🐳 Installation Docker
* 📡 Configuration MQTT

ℹ️ Le script est validé automatiquement lors du build.

---

## ⚙️ Options CLI

```bash
./build-iso.sh --noforce
```

* `--noforce` : stop si validation échoue

---

## 🛠️ Dépannage

### Dépendances

```bash
sudo apt update
sudo apt install wget p7zip-full openssl xorriso
```

### YAML

```bash
sudo apt install python3-yaml
```

### Erreurs fréquentes

* ❌ `eltorito.img` → ISO incompatible
* ❌ GRUB ignoré → vérifier template

---

## 📜 Licence

Apache 2.0

---

## 🤝 Contribuer

PR bienvenues 👍

---

## 🔗 Liens

* GitHub : [https://github.com/cce66/NeurHomIA](https://github.com/cce66/NeurHomIA)
