```markdown
# Construction d'une ISO Ubuntu Server personnalisée avec Autoinstall

Ce projet fournit un script pour générer une ISO d'installation automatisée d'Ubuntu Server.  
Il combine l'**autoinstall** (subiquity) d'Ubuntu avec un script de configuration post‑installation (first‑boot) récupéré depuis GitHub.  
Le résultat est une ISO bootable qui installe Ubuntu Server avec un utilisateur pré‑défini, des paquets spécifiques et un service de première configuration exécuté immédiatement après l’installation.

## Fonctionnalités

- Installation entièrement automatisée d'Ubuntu Server (sans interaction humaine).
- Préconfiguration de :
  - Langue, clavier, réseau (DHCP par défaut)
  - Partitionnement LVM
  - Utilisateur système (avec mot de passe hashé)
  - Serveur SSH (authentification par mot de passe ou clé)
  - Paquets additionnels (Docker, Git, UFW, packs de langue française, …)
- Téléchargement et exécution d’un script de première configuration personnalisé (ex. : fuseau horaire, firewall, fail2ban, identifiants MQTT).
- Création d’un service systemd pour exécuter ce script une fois le réseau disponible.
- Production d’une ISO prête à l’emploi (hybride BIOS + UEFI) pouvant être copiée sur une clé USB.
- Possibilité de graver directement l’ISO sur une clé USB depuis le script.

## Structure du dépôt

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

## Prérequis

- Une machine Linux (Ubuntu 20.04/22.04/24.04 recommandée) avec :
  - Accès `sudo`
  - Connexion Internet (pour télécharger l’ISO Ubuntu et les fichiers GitHub)
  - Au moins 6 Go d’espace disque libre
- Paquets nécessaires (le script tente de les installer automatiquement) :
  - `wget`, `p7zip-full`, `openssl`, `xorriso`, `squashfs-tools`, `schroot`, `rsync`, `syslinux-utils`, `isolinux`, `genisoimage`

## Utilisation

### 1. Cloner le dépôt

```bash
git clone https://github.com/cce66/NeurHomIA.git
cd NeurHomIA
```

### 2. Personnaliser les variables (optionnel)

Éditez le début de `build-iso.sh` pour ajuster les valeurs par défaut :

```bash
PROJECT_NAME="NeurHomIA"                # Nom du projet
GITHUB_OWNER_NAME="cce66"               # Nom d’utilisateur GitHub du dépôt
DEFAULT_UBUNTU_VERSION="24.04.4"        # Version d’Ubuntu à télécharger

# Les URLs sont automatiquement construites à partir de ces variables
# Ne modifiez les lignes suivantes que si vous avez une structure différente
```

### 3. Lancer le script

```bash
chmod +x build-iso.sh
./build-iso.sh
```

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

### 4. Graver l’ISO sur une clé USB

À la fin du script, vous pouvez choisir d’écrire l’ISO sur une clé USB.  
Le script liste les périphériques détectés et demande confirmation.

Si vous sautez cette étape, vous pouvez le faire manuellement :

```bash
sudo dd if=~/neurhomia-key/neurhomia-server-24.04.4-auto.iso of=/dev/sdX bs=4M status=progress conv=fsync
```

Remplacez `/dev/sdX` par votre périphérique USB (ex. `/dev/sdb`). **Attention – cela effacera toutes les données sur le périphérique.**

## Comment ça fonctionne

### Template autoinstall (`autoinstall/user-data.template`)

Le template contient des placeholders qui sont remplacés lors de la construction :

| Placeholder           | Remplacé par                                            |
|-----------------------|---------------------------------------------------------|
| `__HOSTNAME__`        | `neurhomia-box` (nom d’hôte par défaut)                 |
| `__USERNAME__`        | Nom d’utilisateur système                               |
| `__PASSWORD_HASH__`   | Mot de passe hashé (généré par `openssl passwd -6`)     |
| `__PROJECT_LOWER__`   | Nom du projet en minuscules (`neurhomia`)               |
| `__PROJECT_NAME__`    | Nom original du projet (`NeurHomIA`)                    |
| `__FIRSTBOOT_URL__`   | URL du script first‑boot                                |

Le fichier `user-data` final est écrit dans `autoinstall/user-data` et copié dans l’ISO.

### Template GRUB (`boot/grub/grub.cfg.template`)

Le template GRUB remplace complètement le fichier `grub.cfg` original de l’ISO. Il contient une entrée de menu pour lancer l’autoinstall et peut inclure des placeholders personnalisés :

| Placeholder           | Remplacé par                                            |
|-----------------------|---------------------------------------------------------|
| `__PROJECT_NAME__`    | Nom du projet (`NeurHomIA`)                             |
| `__PROJECT_LOWER__`   | Nom du projet en minuscules (`neurhomia`)               |
| `__PROJECT_UPPER__`   | Nom du projet en majuscules (`NEURHOMIA`)               |

Exemple minimal :

```cfg
set default=0
set timeout=10

menuentry "Autoinstall Ubuntu Server __PROJECT_NAME__" {
    set gfxpayload=keep
    linux /casper/vmlinuz autoinstall "ds=nocloud;s=/cdrom/autoinstall/" debug --- autoinstall
    initrd /casper/initrd
}
```

### Script firstboot (`scripts/firstboot.sh`)

Ce script est téléchargé et stocké dans `/opt/neurhomia/firstboot.sh`.  
Un service systemd (`neurhomia-firstboot.service`) l’exécute une fois après que le réseau soit disponible.  
Les tâches typiques incluent :
- Réglage du fuseau horaire
- Changement du mot de passe par défaut
- Configuration SSH (clés, désactivation du mot de passe)
- Activation d’UFW et fail2ban
- Installation de Docker et d’autres outils
- Mise en place d’identifiants MQTT

Le script est validé lors de la construction de l’ISO : on vérifie la présence de sections obligatoires (comme `BIENVENUE`, `CONFIGURATION RÉSEAU`, etc.) et la construction s’arrête si elles sont manquantes (sauf si l’option `--noforce` est utilisée).

### Étapes de construction détaillées

1. **Demande de la version Ubuntu** – l’utilisateur peut choisir, par défaut 24.04.4.
2. **Validation du script firstboot.sh** – téléchargement et vérification des marqueurs.
3. **Vérification des dépendances** – installation automatique si possible.
4. **Préparation des dossiers** – création de l’espace de travail, sauvegarde de l’ancien autoinstall.
5. **Téléchargement/extraction de l’ISO** – si elle n’est pas déjà présente.
6. **Génération du hash du mot de passe** – avec `openssl`.
7. **Téléchargement et personnalisation des templates autoinstall** – depuis GitHub.
8. **Validation de la syntaxe YAML** – avec Python/yaml.
9. **Intégration de l’autoinstall** – copie dans l’ISO extraite.
10. **Téléchargement et personnalisation du template GRUB** – depuis GitHub, remplacement complet du fichier `grub.cfg`.
11. **Construction de l’ISO** – avec `xorriso` (hybride BIOS/UEFI).
12. **Validation de l’ISO** – vérification des fichiers autoinstall, taille, SHA256.
13. **Gravure sur clé USB** – optionnelle, avec vérification par hash.

## Options de ligne de commande

- `--noforce` – désactive la construction forcée lorsque la validation du script first‑boot échoue (le script s’arrête au lieu de continuer).  
  Sans cette option, le script continuera malgré les sections manquantes (mais affichera un avertissement).

Exemple :

```bash
./build-iso.sh --noforce
```

## Sortie

L’ISO générée est placée dans :

```
~/neurhomia-key/neurhomia-server-<version>-auto.iso
```

Un checksum SHA256 est affiché à la fin pour vérification.

## Dépannage

### Les dépendances ne sont pas installées

Si le script ne peut pas installer automatiquement les dépendances (par exemple parce que vous n’êtes pas root), installez-les manuellement :

```bash
sudo apt update
sudo apt install wget p7zip-full openssl xorriso squashfs-tools schroot rsync syslinux-utils isolinux genisoimage
```

### wget échoue à télécharger les fichiers GitHub

Vérifiez votre connexion Internet et que les URLs du dépôt sont correctes.  
Vous pouvez les tester manuellement :

```bash
wget -O /tmp/test https://raw.githubusercontent.com/cce66/NeurHomIA/main/build-iso2usb/autoinstall/user-data.template
wget -O /tmp/test https://raw.githubusercontent.com/cce66/NeurHomIA/main/build-iso2usb/boot/grub/grub.cfg.template
wget -O /tmp/test https://raw.githubusercontent.com/cce66/NeurHomIA/main/build-iso2usb/scripts/firstboot.sh
```

### La validation YAML échoue

Assurez-vous que `python3-yaml` est installé. Le script tente de l’installer automatiquement, mais si cela échoue, faites-le manuellement :

```bash
sudo apt install python3-yaml
```

### La construction de l’ISO échoue avec « eltorito.img introuvable »

Cette erreur se produit si l’ISO extraite ne contient pas le fichier de boot BIOS attendu.  
Cela peut arriver si Ubuntu a modifié sa structure d’ISO. Le script suppose la disposition standard d’Ubuntu Server. Essayez une autre version d’Ubuntu ou vérifiez le répertoire `boot/grub` dans l’ISO extraite.

### Le template GRUB n’est pas pris en compte

Assurez-vous que le fichier `grub.cfg.template` est bien présent dans votre dépôt à l’emplacement `build-iso2usb/boot/grub/grub.cfg.template`.  
Le script le télécharge et remplace entièrement le fichier GRUB original. Si le template est vide ou mal formé, l’ISO pourrait ne pas démarrer correctement.

## Contribuer

Les suggestions, rapports de bogues et demandes d’amélioration sont les bienvenus.  
Toute documentation est ouverte aux contributions.

## Licence

Ce projet est sous licence [MIT](LICENSE).

## Remerciements

- Ubuntu pour l’ISO de base
- L’équipe OneUptime pour leur [article de blog sur autoinstall](https://oneuptime.com/blog/post/2026-03-02-configure-ubuntu-server-installer-autoinstall)
- La communauté open‑source pour les outils utilisés
```
