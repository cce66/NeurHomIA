# 🚀 NeurHomIA — Construction d'ISO Ubuntu Server

Génération automatisée d'une image ISO Ubuntu Server préconfigurée avec **autoinstall**, **LVM**, **Docker** et un script de première configuration exécuté au boot.

---

## 🏷️ Tags

* Ubuntu 24.04 LTS
* Apache 2.0 License
* BIOS + UEFI
* bash
* xorriso
* systemd

✔️ ❌ ⭐ 💥 🔥 ⚡ 💿 💻🚀⬇️⚠️🏠🦿🔧👩🏻‍🔬🦾⚙️👁‍🗨 🤖 💾 🔐

## Téléchargement et exécution du script build-iso.sh

Ce guide explique comment télécharger le script build-iso.sh depuis GitHub, le rendre exécutable et l'exécuter.
Prérequis


### Prérequis

- Une machine Linux (Ubuntu 20.04/22.04/24.04 recommandée) avec :
  - Connexion Internet (pour télécharger l’ISO Ubuntu et les fichiers GitHub)
  - Au moins 6 Go d’espace disque libre
  - Accès au terminal avec accès `sudo`
  - Outil wget installé, il généralement préinstallé sur la plupart des distributionsn sinon l'installer avec :
    ```bash
    sudo apt update && sudo apt install wget -y
    ```
  - Paquets nécessaires (si un des paquest est absent, le script tente de l'installer automatiquement) :
    `wget`, `p7zip-full`, `openssl`, `xorriso`, `squashfs-tools`, `schroot`, `rsync`, `syslinux-utils`, `isolinux`, `genisoimage`
 
----
### 1. Créer le répertoire NeurHomIA-Key 📁

Créez le répertoire NeurHomIA-Key dans votre dossier utilisateur (home) s'il n'existe pas déjà :
```bash
mkdir -p ~/NeurHomIA-Key
```

----
### 2. Télécharger le script 📶 🔽 

Téléchargez le script build-iso.sh depuis GitHub en utilisant wget :
```bash
wget -O ~/NeurHomIA-Key/build-iso.sh https://raw.githubusercontent.com/cce66//NeurHomIA/main/build-iso.sh
```

💡 Note : Il est important d'utiliser l'URL raw.githubusercontent.com pour obtenir le contenu brut du script, et non la page GitHub standard.

----
### 3. Rendre le script exécutable  🛠️

Donnez les permissions d'exécution au script :
```bash
chmod +x ~/NeurHomIA-Key/build-iso.sh
```

----
### 4. Exécuter le script ▶️

Exécutez le script depuis le répertoire NeurHomIA :
```bash
cd ~/NeurHomIa
```

Le script nécessite des privilèges administrateur, utilisez :
```bash
sudo bash ~/NeurHomIA/build-iso.sh
```
Si le script est lancé sans sudo il demande au démarrage le mot de passe sudo pour certaines commandes.

----
### 5. 🛠️ Exécution du script

Le script demandera :
- La version d’Ubuntu Server (ou Entrée pour la version par défaut)
- Le mot de passe sudo (si le script n'a pas été lancé avec sudo)

Il effectuera ensuite :
1. La validation du script `firstboot.sh` (vérification des sections attendues).
2. L’installation des dépendances manquantes.
3. Le téléchargement de l’ISO Ubuntu (si elle n’est pas déjà présente).
4. L’extraction de l’ISO.
5. La génération du hash du mot de passe par défaut.
6. Le téléchargement des templates autoinstall (`user-data.template`, `meta-data`) depuis GitHub, puis leur personnalisation (remplacement des placeholders).
7. La validation de la syntaxe YAML du fichier `user-data` généré.
8. L’injection des fichiers autoinstall dans l’ISO extraite.
9. Le téléchargement du template GRUB (`grub.cfg.template`) depuis GitHub, sa personnalisation, et son remplacement dans l’ISO.
10. La construction de l’ISO finale (hybride BIOS/UEFI).
11. La validation de l’ISO (montage, vérification du contenu, SHA256).
12. La proposition de graver l’ISO sur une clé USB.

----
### 6. Graver l’ISO sur une clé USB

À la fin du script, vous pouvez choisir d’écrire l’ISO sur une clé USB.  
Le script liste les périphériques détectés et demande confirmation.

Si vous sautez cette étape, vous pouvez le faire manuellement :

```bash
sudo dd if=~/neurhomia-key/neurhomia-server-24.04.4-auto.iso of=/dev/sdX bs=4M status=progress conv=fsync
```

Remplacez `/dev/sdX` par votre périphérique USB (ex. `/dev/sdb`). **Attention – cela effacera toutes les données sur le périphérique.**



----
###  📌 Notes importantes
----

#### 1. 🔒 Sécurité : 
Vérifiez toujours le contenu des scripts téléchargés depuis Internet avant de les exécuter.

#### 2. 📁 Structure du dépôt
```
.
└── build-iso2usb/
    ├── build-iso.sh                     # Script principal de construction
    ├── autoinstall/                     # Fichiers modèles pour l’autoinstall
    │   ├── user-data.template           # Template YAML avec des placeholders
    │   └── meta-data                    # Optionnel (peut être vide)
    ├── boot/                            # Fichiers de boot personnalisés
    │   └── grub/
    │       └── grub.cfg.template        # Template GRUB pour le menu autoinstall
    └── scripts/
        └── firstboot.sh                 # Script de première configuration
```

#### 3. 🔄 Pipeline de construction

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

### 4. 🧩 Placeholders

#### autoinstall (`user-data.template`)

| Placeholder         | Description   |
| ------------------- | ------------- |
| `__HOSTNAME__`      | neurhomia-box |
| `__USERNAME__`      | utilisateur   |
| `__PASSWORD_HASH__` | hash openssl  |
| `__PROJECT_LOWER__` | neurhomia     |
| `__PROJECT_NAME__`  | NeurHomIA     |
| `__FIRSTBOOT_URL__` | script GitHub |

#### GRUB (`grub.cfg.template`)

| Placeholder         | Valeur    |
| ------------------- | --------- |
| `__PROJECT_NAME__`  | NeurHomIA |
| `__PROJECT_LOWER__` | neurhomia |
| `__PROJECT_UPPER__` | NEURHOMIA |

#### Exemple GRUB

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

#### 5. 🚀 Script firstboot

Chemin : `/opt/neurhomia/firstboot.sh`

### Actions typiques

* Fuseau horaire
* Changement mot de passe
* SSH (clés)
* UFW + fail2ban
* Docker
* MQTT

ℹ️ Validation automatique des sections obligatoires.


#### 6. ⚙️ Options CLI

```bash
./build-iso.sh --noforce
```

* `--noforce` : stop si erreur validation


#### 7. 📦 Sortie

```text
~/neurhomia-key/neurhomia-server-<version>-auto.iso
```

SHA256 affiché en fin de build.

----

### 8. 🛠️ Dépannage

#### Dépendances

```bash
sudo apt update
sudo apt install wget p7zip-full openssl xorriso \
  squashfs-tools schroot rsync syslinux-utils isolinux genisoimage
```

#### wget KO

Tester :

```bash
wget -O /tmp/test https://raw.githubusercontent.com/cce66/NeurHomIA/main/build-iso2usb/autoinstall/user-data.template
```

#### YAML

```bash
sudo apt install python3-yaml
```

#### eltorito.img manquant

→ ISO Ubuntu incompatible

#### GRUB non pris en compte

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














