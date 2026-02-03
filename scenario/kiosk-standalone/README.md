# Kiosk Standalone K3s

Image EIB standalone avec K3s et Firefox kiosk pré-déployé.
Pas de Rancher/Elemental - entièrement autonome.

## Composants

- **OS**: SL Micro 6.1 (SUSE Edge 3.4)
- **Kubernetes**: K3s v1.33.5+k3s1 (singlenode)
- **Workload**: Firefox kiosk (DaemonSet dans namespace `kiosk`)

## Structure

```
EIB-kiosk-standalone/
├── iso-definition.yaml          # Définition EIB
├── build-eib-image.sh           # Script de build
├── base-images/                 # Image SL Micro (lien symbolique)
├── kubernetes/
│   └── manifests/
│       ├── 00-kiosk-namespace.yaml
│       └── 10-kiosk-firefox-daemonset.yaml
└── output/                      # ISO générée

scenario/kiosk-standalone/
├── 01-build-iso.sh             # Build l'image
├── 02-create-vm.sh             # Créer une VM de test
└── 03-cleanup-vm.sh            # Nettoyer la VM
```

## Utilisation

### 1. Build de l'image

```bash
cd scenario/kiosk-standalone
./01-build-iso.sh
```

Ou directement:
```bash
cd EIB-kiosk-standalone
./build-eib-image.sh
```

### 2. Test dans une VM (optionnel)

```bash
./02-create-vm.sh
```

Variables d'environnement disponibles:
- `VM_NAME` - Nom de la VM (défaut: kiosk-standalone)
- `VM_MEMORY` - RAM en MB (défaut: 4096)
- `VM_VCPUS` - vCPUs (défaut: 2)
- `VM_DISK_SIZE` - Disque en GB (défaut: 40)
- `VM_NETWORK` - Réseau libvirt (défaut: default)

### 3. Vérification

Après le boot:

```bash
# Obtenir l'IP de la VM
virsh domifaddr kiosk-standalone

# Vérifier K3s
ssh root@<ip> kubectl get nodes

# Vérifier le kiosk
ssh root@<ip> kubectl get pods -n kiosk
ssh root@<ip> kubectl logs -n kiosk -l app=kiosk-firefox
```

### 4. Nettoyage

```bash
./03-cleanup-vm.sh
```

## Configuration du Kiosk

Le kiosk Firefox affiche par défaut `https://www.suse.com`.

Pour changer l'URL, modifier `kubernetes/manifests/10-kiosk-firefox-daemonset.yaml`:

```yaml
env:
  - name: URL
    value: "https://votre-url.com"
```

Puis reconstruire l'image.

## Images Container

Le kiosk utilise les images opensuse.org officielles:
- `registry.opensuse.org/home/atgracey/wallboardos/15.6/x11:latest`
- `registry.opensuse.org/home/atgracey/wallboardos/15.6/pa:latest`
- `registry.opensuse.org/home/atgracey/wallboardos/15.6/firefox:latest`

## Notes

- L'installation est entièrement automatique sur `/dev/vda`
- K3s démarre automatiquement au premier boot
- Les manifests Kubernetes sont déployés automatiquement par EIB
- SELinux est désactivé pour la compatibilité avec les containers privilégiés
