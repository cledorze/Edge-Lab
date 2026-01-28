# EIB-3.3 - SUSE Edge 3.3 Image Builder

Configuration pour construire des images SUSE Edge 3.3 (SL Micro 6.0).

## Prérequis

### Image de base SL Micro 6.0

Télécharger l'ISO SL Micro 6.0 depuis le portail SUSE et le placer dans `base-images/` :

```
SL-Micro.x86_64-6.0-Base-RT-SelfInstall-GM2.install.iso
```

Un lien symbolique vers `/home/tofix/SL-Micro.x86_64-6.0-Base-RT-SelfInstall-GM2.install.iso` est déjà configuré.

URL de téléchargement : https://www.suse.com/download/sle-micro/

### Podman

```bash
sudo zypper install podman
```

## Utilisation

### Avec le script add-node (recommandé)

Le script `12-add-edge33-node.sh` gère automatiquement la configuration :

```bash
export EIB_33_DIR=/home/tofix/demo/Edge-3.4/EIB-3.3
cd /home/tofix/demo/Edge-3.4/scenario/elemental_dual-site-singlenode
./12-add-edge33-node.sh
```

### Build manuel

```bash
./build-eib-image.sh
```

## Différences avec Edge 3.4

| Composant | Edge 3.3 | Edge 3.4 |
|-----------|----------|----------|
| SL Micro | 6.0 | 6.1 |
| EIB | 1.2.0 | 1.3.0 |
| apiVersion | 1.2 | 1.3 |

## Usage SUC

Les nœuds créés avec cette configuration auront les labels :
- `edge-version: "3.3"`
- `suc-group: edge33`

Ces labels permettent de cibler les nœuds pour les plans SUC d'upgrade vers Edge 3.4.
