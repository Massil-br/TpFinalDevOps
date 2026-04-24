# Déploiement automatique sur VPS

## Architecture

```
┌──────────────┐   git push   ┌────────────────┐   kubectl   ┌──────────────┐
│    Laptop    ├─────────────▶│ GitHub Actions ├────────────▶│  VPS (k3s)   │
└──────────────┘  main/tag    │  test→lint→...  │             │              │
                              │  →build→push    │             │  taskflow-   │
                              │  →deploy        │             │  staging     │
                              └────────────────┘             │  taskflow-   │
                                      │                      │  production  │
                                      ▼                      └──────┬───────┘
                              ┌────────────────┐                    │
                              │   Docker Hub   │◀───pull────────────┘
                              └────────────────┘

Sur le VPS en parallele :
┌────────────────────────────────────────────────────────────┐
│  Host VPS                                                  │
│  ├─ k3s (pods backend dans 2 namespaces)                   │
│  └─ docker-compose (Redis, network_mode: host)             │
│     └─ pods k8s joignent Redis via IP du node sur 6379     │
└────────────────────────────────────────────────────────────┘
```

## Flux automatique

| Action | Résultat |
|---|---|
| `git push origin main` | Build image `:latest` → deploy staging sur le VPS |
| `git tag v1.0.1 && git push origin v1.0.1` | Build image `:v1.0.1` → deploy production sur le VPS |

## 1. Préparer le VPS

### Prérequis

| Ressource | Minimum |
|---|---|
| vCPU | 1 |
| RAM | 2 Go |
| OS | Ubuntu 22.04+ / Debian 12 |

### Installation

```bash
# Se connecter au VPS avec un user non-root
ssh deploy@<IP-VPS>

# Cloner le repo
git clone https://github.com/<user>/TpFinalDevOps.git
cd TpFinalDevOps
chmod +x scripts/*.sh

# Installer k3s + Docker + firewall
sudo ./scripts/install-vps.sh
```

Vérification :

```bash
kubectl get nodes
# NAME      STATUS   ROLES                  AGE   VERSION
# vps-xxx   Ready    control-plane,master   1m    v1.30.x
```

## 2. Premier déploiement

```bash
# Exporte ton user Docker Hub (utilise dans la substitution des manifests)
export DOCKER_USERNAME=ton_user

# Lance Redis (docker-compose) + applique les 2 namespaces
./scripts/first-deploy.sh
```

Ce script :
1. Lance Redis via `scripts/docker-compose.vps.yml` (mode host)
2. Détecte l'IP du node k3s (accessible depuis les pods)
3. Remplace `HOST_IP` dans les ConfigMap et `<DOCKER_USERNAME>` dans les Deployment
4. Applique tous les YAML k8s
5. Attend que les pods soient Ready

Test :

```bash
curl http://<IP-VPS>:30001/health
curl http://<IP-VPS>:30002/health
```

## 3. Configurer GitHub pour l'auto-deploy

### Récupérer le kubeconfig du VPS

```bash
# Sur le VPS
./scripts/setup-github-access.sh
```

Le script affiche le kubeconfig à copier.

### Créer les 4 secrets GitHub

Dans **GitHub → Settings → Secrets and variables → Actions → New repository secret** :

| Secret | Valeur |
|---|---|
| `DOCKER_USERNAME` | Ton user Docker Hub |
| `DOCKER_PASSWORD` | Access Token Docker Hub (pas le mot de passe) |
| `KUBE_CONFIG_STAGING` | Le kubeconfig complet du VPS |
| `KUBE_CONFIG_PROD` | Le kubeconfig complet du VPS (même contenu) |

### Docker Hub Access Token

Docker Hub → **Account Settings → Security → New Access Token** (scope : Read, Write, Delete).

## 4. Tester le flux complet

### Push sur main → deploy staging

```bash
git checkout main
git commit --allow-empty -m "test staging auto-deploy"
git push origin main
```

Dans GitHub **Actions** tu verras : `test → lint → audit → build → deploy-staging → smoke-test`.

Sur le VPS :

```bash
kubectl get pods -n taskflow-staging -w
curl http://<IP-VPS>:30001/health
```

### Tag `v*` → deploy production

```bash
git tag -a v1.0.1 -m "Release v1.0.1"
git push origin v1.0.1
```

Workflow : `test → lint → audit → build → deploy-production`.

## 5. Démos à l'oral

### Self-healing (pod tué remonte tout seul)

```bash
kubectl delete pod -l component=backend -n taskflow-staging
kubectl get pods -n taskflow-staging -w
```

### Rolling update sans interruption

Terminal 1 — monitoring :

```bash
while true; do curl -s http://<IP-VPS>:30001/health | head -c 80; echo; sleep 1; done
```

Terminal 2 — changement d'image :

```bash
kubectl set image deployment/taskflow-backend \
  backend=<user>/tpfinal:v1.0.2 \
  -n taskflow-production
kubectl rollout status deployment/taskflow-backend -n taskflow-production
```

### Rollback en une commande

```bash
kubectl rollout undo deployment/taskflow-backend -n taskflow-production
kubectl rollout history deployment/taskflow-backend -n taskflow-production
```

### Persistance Redis après destruction des pods

```bash
# Créer une tâche
curl -X POST http://<IP-VPS>:30001/tasks \
  -H "Content-Type: application/json" \
  -d '{"title":"Test persistence"}'

# Tuer tous les pods backend
kubectl delete deployment taskflow-backend -n taskflow-staging
kubectl apply -f k8s/staging/deployment.yml  # ou via first-deploy.sh

# La tâche est toujours là (Redis dans docker-compose, volume nommé)
curl http://<IP-VPS>:30001/tasks
```

## Dépannage

| Problème | Solution |
|---|---|
| Pod `ImagePullBackOff` | Vérifier `DOCKER_USERNAME` dans les deployment.yml et que l'image est sur Docker Hub |
| Pod `CrashLoopBackOff` + `ENOTFOUND` | Redis non joignable → vérifier `docker compose -f scripts/docker-compose.vps.yml ps` |
| `readinessProbe failed` | `kubectl logs <pod> -n taskflow-staging` → souvent Redis ou port 3001 |
| `connection refused` sur port 3001 | Le bug `require.main === module` dans server.js n'est pas corrigé → serveur démarre pas en prod |
| CI `Unable to connect to server` | Le port 6443 du VPS est-il ouvert ? `sudo ufw status` |
| CI `kubectl not found` | Le workflow utilise `azure/setup-kubectl@v4` — vérifier |

## Ressources utilisées

- **k3s** : Kubernetes allégé sans Traefik, ServiceLB, metrics-server
- **docker-compose** : uniquement pour Redis (persistance + `network_mode: host`)
- **GitHub Actions** : test, lint, audit npm, build, Trivy scan, deploy via kubectl

## Pourquoi cette architecture

| Composant | Rôle | Où |
|---|---|---|
| Dockerfile | Build l'image backend | GitHub Actions |
| Docker Hub | Stocke les images | Cloud |
| k3s | Orchestration (2 namespaces, replicas, rolling update, self-healing) | VPS |
| docker-compose.vps.yml | Redis persistant hors k8s | VPS (host network) |
| docker-compose.yml (racine) | Dev local uniquement | Laptop |
