# Adaptations et Corrections - Metal3 Demo Deployment

Date: 2026-01-10

## Résumé

Ce document liste les adaptations et corrections apportées au scénario Metal3 Demo
pour assurer un déploiement fonctionnel.

## Fichiers Ajoutés

### 1. `07_health_check.sh`
Script de vérification de santé automatique qui :
- Vérifie et redémarre sushy-tools si nécessaire
- Vérifie et démarre image-cache si manquant
- Vérifie l'état du cluster de management
- Vérifie les pods Metal3 (Ironic, BMO)
- Vérifie l'état des BareMetalHosts
- Vérifie les VMs libvirt
- Vérifie le cluster workload

### 2. `docs/TROUBLESHOOTING.md`
Guide de troubleshooting complet documentant :
- Problème sushy-tools (connexion libvirt perdue)
- Problème image-cache (container non démarré)
- Problème Ironic (base de données éphémère)
- Problème BMO Controller (cache d'état)
- Vérifications post-déploiement
- Ordre de redémarrage recommandé
- Commandes de logs utiles

## Fichiers Modifiés

### 1. `README.md`
Ajouts :
- Section "Health Check & Troubleshooting"
- Tableau des problèmes courants avec solutions rapides
- Section "Accessing the Workload Cluster"
- Mise à jour de la structure de répertoire

## Problèmes Rencontrés et Solutions

### Problème 1: sushy-tools - Connexion libvirt cassée

**Symptôme** :
```
BMH en état "registration error"
Error: internal error: client socket is closed
```

**Cause** : Le container sushy-tools perd sa connexion au socket libvirt après un
certain temps ou après un redémarrage de libvirtd.

**Solution** :
```bash
sudo podman restart sushy-tools
```

---

### Problème 2: image-cache - Container non démarré

**Symptôme** :
```
BMH en état "provisioning error"
Error: ECONNREFUSED sur imagecache.local:8443
```

**Cause** : Le container image-cache (Apache HTTPD servant les images OS) n'est pas
démarré automatiquement après un reboot.

**Solution** :
```bash
sudo podman run -d --name image-cache \
  -v $WORKING_DIR/image-cache:/usr/local/apache2/htdocs:Z \
  -v $WORKING_DIR/image-cache-conf/httpd.conf:/usr/local/apache2/conf/httpd.conf:Z \
  -v $WORKING_DIR/image-cache-conf/server.key:/usr/local/apache2/conf/server.key:Z \
  -v $WORKING_DIR/image-cache-conf/server.crt:/usr/local/apache2/conf/server.crt:Z \
  -p 8080:80 -p 8443:443 \
  docker.io/library/httpd:2.4
```

**Note** : Les flags `:Z` sont requis pour SELinux.

---

### Problème 3: Ironic - Perte de la base de données

**Symptôme** :
```
BMH reste en "registration error"
Ironic logs: "Node xxx could not be found"
```

**Cause** : Le pod Ironic utilise un stockage éphémère. Après un redémarrage,
les nodes enregistrés sont perdus.

**Solution** :
```bash
kubectl rollout restart deployment -n metal3-system metal3-metal3-ironic
kubectl rollout restart deployment -n metal3-system baremetal-operator-controller-manager
```

---

### Problème 4: BMO Controller - Cache d'état

**Symptôme** :
```
BMH reste en erreur malgré la correction des problèmes sous-jacents
```

**Cause** : Le Baremetal Operator Controller Manager garde en cache l'état des BMH.

**Solution** :
```bash
kubectl rollout restart deployment -n metal3-system baremetal-operator-controller-manager
```

## Ordre de Redémarrage Recommandé

En cas de problème après un reboot ou un échec de déploiement :

1. `sudo podman restart sushy-tools`
2. Vérifier/démarrer image-cache
3. `kubectl rollout restart deployment -n metal3-system metal3-metal3-ironic`
4. `kubectl rollout restart deployment -n metal3-system baremetal-operator-controller-manager`
5. Attendre 2-3 minutes pour la réconciliation

## Services Critiques

| Service | Container/Pod | Port | Rôle |
|---------|--------------|------|------|
| sushy-tools | podman container | 8000 (HTTPS) | Virtual BMC Redfish |
| image-cache | podman container | 8443 (HTTPS) | Serveur d'images OS |
| Ironic | metal3-system pod | 6385 | Provisioning bare metal |
| BMO | metal3-system pod | - | Controller K8s pour BMH |

## Résultat Final

Après application des corrections, le déploiement complet fonctionne :

```
$ kubectl get bmh -A
NAMESPACE   NAME             STATE         CONSUMER                            ONLINE   ERROR
default     controlplane-0   provisioned   sample-cluster-controlplane-w7cl6   true
default     worker-0         provisioned   sample-cluster-8p8pj-lj25h          true

$ clusterctl describe cluster sample-cluster
NAME                                                    READY
Cluster/sample-cluster                                  True
├─ClusterInfrastructure - Metal3Cluster/sample-cluster  True
├─ControlPlane - RKE2ControlPlane/sample-cluster        True
│ └─Machine/sample-cluster-7xnlf                        True
└─Workers
  └─MachineDeployment/sample-cluster                    True
    └─Machine/sample-cluster-8p8pj-lj25h                True
```
