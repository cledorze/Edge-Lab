# Troubleshooting Guide - Metal3 Demo Deployment

Ce document recense les problèmes rencontrés lors du déploiement et leurs solutions.

## Problèmes et Solutions

### 1. Sushy-tools - Connexion libvirt cassée

**Symptôme** :
```
BMH en état "registration error"
Error: HTTP GET https://192.168.125.1:8000/redfish/v1/Systems/... returned code 500
Base.1.0.GeneralError: internal error: client socket is closed
```

**Cause** : Le container sushy-tools perd sa connexion au socket libvirt de l'hôte après un certain temps ou un redémarrage de libvirtd.

**Diagnostic** :
```bash
# Vérifier que Redfish répond
curl -sk https://192.168.125.1:8000/redfish/v1/Systems/

# Vérifier les logs sushy-tools
sudo podman logs sushy-tools
```

**Solution** :
```bash
sudo podman restart sushy-tools
```

---

### 2. Image-cache container non démarré

**Symptôme** :
```
BMH en état "provisioning error"
Error: HTTPSConnectionPool(host='imagecache.local', port=8443):
Max retries exceeded... ECONNREFUSED
```

**Cause** : Le container image-cache (serveur Apache HTTPD) n'est pas démarré. Ce container sert les images OS aux BMH via HTTPS.

**Diagnostic** :
```bash
# Vérifier si le container existe
sudo podman ps -a | grep image-cache

# Tester l'accès à l'image cache
curl -sk https://192.168.125.1:8443/
```

**Solution** :
```bash
# Démarrer le container image-cache
sudo podman run -d --name image-cache \
  -v /home/tofix/metal3-demo-files/image-cache:/usr/local/apache2/htdocs:Z \
  -v /home/tofix/metal3-demo-files/image-cache-conf/httpd.conf:/usr/local/apache2/conf/httpd.conf:Z \
  -v /home/tofix/metal3-demo-files/image-cache-conf/server.key:/usr/local/apache2/conf/server.key:Z \
  -v /home/tofix/metal3-demo-files/image-cache-conf/server.crt:/usr/local/apache2/conf/server.crt:Z \
  -p 8080:80 -p 8443:443 \
  docker.io/library/httpd:2.4
```

**Note** : Les flags `:Z` sont nécessaires pour SELinux sur openSUSE.

---

### 3. Ironic - Base de données perdue après restart

**Symptôme** :
```
BMH reste en "registration error" même après fix de sushy-tools
Ironic logs: "Node xxx could not be found"
```

**Cause** : Le pod Ironic utilise un stockage éphémère. Après un redémarrage, les nodes enregistrés sont perdus.

**Diagnostic** :
```bash
export KUBECONFIG=./metal3-mgmt.kubeconfig
kubectl logs -n metal3-system deployment/metal3-metal3-ironic -c ironic --tail 30
```

**Solution** :
```bash
# Redémarrer Ironic pour forcer une ré-synchronisation
kubectl rollout restart deployment -n metal3-system metal3-metal3-ironic
kubectl rollout status deployment -n metal3-system metal3-metal3-ironic --timeout=120s
```

---

### 4. BMO Controller - Cache d'état

**Symptôme** :
```
BMH reste en erreur malgré la correction des problèmes sous-jacents
```

**Cause** : Le Baremetal Operator Controller Manager garde en cache l'état des BMH.

**Solution** :
```bash
# Redémarrer le BMO controller
kubectl rollout restart deployment -n metal3-system baremetal-operator-controller-manager
kubectl rollout status deployment -n metal3-system baremetal-operator-controller-manager --timeout=60s
```

---

## Vérifications Post-Déploiement

### Vérifier l'état des BMH
```bash
export KUBECONFIG=./metal3-mgmt.kubeconfig
kubectl get bmh -A
```

États attendus :
- `available` : Prêt à être provisionné
- `provisioning` : En cours de provisionnement
- `provisioned` : Provisionné et en cours d'utilisation

### Vérifier l'état du cluster CAPI
```bash
clusterctl describe cluster sample-cluster
```

Tous les composants doivent être `READY: True`.

### Vérifier les VMs
```bash
sudo virsh list --all
```

VMs attendues :
- `management-cluster` : running
- `controlplane_0` : running (après provisioning)
- `worker_0` : running (après provisioning)

### Vérifier les services critiques
```bash
# Sushy-tools (Virtual BMC)
sudo podman ps | grep sushy-tools
curl -sk -u admin:password https://192.168.125.1:8000/redfish/v1/Systems/

# Image-cache
sudo podman ps | grep image-cache
curl -sk https://192.168.125.1:8443/

# Ironic
kubectl get pods -n metal3-system
```

### Accéder au cluster workload
```bash
# Récupérer le kubeconfig
clusterctl get kubeconfig sample-cluster > /tmp/sample-cluster.kubeconfig

# Vérifier les nodes
KUBECONFIG=/tmp/sample-cluster.kubeconfig kubectl get nodes -o wide
```

---

## Ordre de Redémarrage en Cas de Problème

Si le déploiement échoue, suivre cet ordre :

1. **Redémarrer sushy-tools** (Virtual BMC)
   ```bash
   sudo podman restart sushy-tools
   ```

2. **Vérifier/Démarrer image-cache**
   ```bash
   sudo podman ps | grep image-cache || sudo podman start image-cache
   ```

3. **Redémarrer Ironic**
   ```bash
   kubectl rollout restart deployment -n metal3-system metal3-metal3-ironic
   ```

4. **Redémarrer BMO Controller**
   ```bash
   kubectl rollout restart deployment -n metal3-system baremetal-operator-controller-manager
   ```

5. **Attendre la réconciliation** (~2-3 minutes)
   ```bash
   watch kubectl get bmh -A
   ```

---

## Logs Utiles

```bash
# Sushy-tools
sudo podman logs sushy-tools --tail 50

# Image-cache
sudo podman logs image-cache --tail 50

# Ironic
kubectl logs -n metal3-system deployment/metal3-metal3-ironic -c ironic --tail 50

# BMO Controller
kubectl logs -n metal3-system deployment/baremetal-operator-controller-manager --tail 50

# Events Kubernetes
kubectl get events --sort-by='.lastTimestamp' | tail -30
```

---

## Résumé des Containers Hôte

| Container | Port | Rôle |
|-----------|------|------|
| sushy-tools | 8000 (HTTPS) | Virtual BMC Redfish |
| image-cache | 8443 (HTTPS) | Serveur d'images OS |

## Résumé des Pods Metal3

| Pod | Namespace | Rôle |
|-----|-----------|------|
| metal3-metal3-ironic | metal3-system | Ironic (provisioning) |
| baremetal-operator-controller-manager | metal3-system | BMO Controller |
