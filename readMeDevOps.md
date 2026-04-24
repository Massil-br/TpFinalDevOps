# README DevOps - TaskFlow

Ce document regroupe toute la partie DevOps du projet `TaskFlow` :
containerisation, intégration continue, livraison continue, déploiement Kubernetes, supervision et bonnes pratiques d'exploitation.

## 1) Objectifs DevOps

- Standardiser l'exécution de l'application via Docker.
- Automatiser les contrôles qualité (tests + lint) dans une pipeline CI.
- Automatiser la livraison applicative vers un cluster Kubernetes.
- Rendre le service observable (santé applicative, logs, métriques de base).

## 2) Architecture cible

- **Frontend**: fichiers statiques servis par Nginx.
- **Backend**: API Node.js (port `3001`).
- **Base de données**: Redis 7.
- **Orchestration**: Kubernetes (Deployment + Service + Ingress).

## 3) Variables d'environnement

| Variable      | Défaut                   | Description                   |
|---------------|--------------------------|-------------------------------|
| `PORT`        | `3001`                   | Port du backend               |
| `APP_ENV`     | `development`            | Environnement                 |
| `APP_VERSION` | `1.0.0`                  | Version affichée dans /health |
| `REDIS_URL`   | `redis://localhost:6379` | URL de connexion Redis        |

## 4) Exécution locale DevOps

### 4.1 Lancer les services avec Docker Compose

```bash
docker compose up -d
```

Vérification:

```bash
docker ps
```

Arrêt:

```bash
docker compose down
```

### 4.2 Démarrer uniquement le backend (option sans Compose)

```bash
cd backend
npm install
npm start
```

### 4.3 Vérifier le service

```bash
curl http://localhost:3001/health
```

## 5) Stratégie de containerisation

### 5.1 Backend

- Image Node.js légère (idéalement alpine).
- Build reproductible (`npm ci`).
- Exposition du port `3001`.
- Healthcheck basé sur l'endpoint `/health`.

### 5.2 Frontend

- Build statique servi via Nginx.
- Fichier de conf Nginx pour le routage et cache des assets.

### 5.3 Bonnes pratiques

- Utiliser des tags d'image versionnés (`app:vX.Y.Z` + `app:latest`).
- Ne pas embarquer de secrets dans les images.
- Réduire la surface d'attaque (images minimales, utilisateur non-root si possible).

## 6) CI (Intégration Continue)

Pipeline recommandée à chaque Push / Pull Request:

1. Installation des dépendances.
2. Lint (`npm run lint`).
3. Tests unitaires (`npm test`).
4. Build des images Docker.
5. Scan de sécurité (dépendances et image).

Critères de validation:

- Pipeline verte obligatoire avant merge.
- Couverture de tests maintenue ou améliorée.
- Aucun secret détecté dans le code.

## 7) CD (Livraison / Déploiement Continu)

### 7.1 Branche et environnements

- `main` -> déploiement en environnement de production.
- Branche de feature -> déploiement temporaire / revue (optionnel).

### 7.2 Étapes CD

1. Build et push des images vers un registry.
2. Mise à jour des manifests Kubernetes (tag d'image).
3. Déploiement via `kubectl apply` ou Helm.
4. Vérification post-déploiement (`rollout status`, `/health`).

## 8) Déploiement Kubernetes

Ressources minimales:

- `Deployment` pour `backend`
- `Service` pour `backend`
- `Deployment` pour `frontend`
- `Service` pour `frontend`
- `Deployment`/chart Redis (ou service managé)
- `Ingress` pour exposer l'application
- `ConfigMap` et `Secret` pour la configuration

Points de configuration importants:

- Probes:
  - `readinessProbe`: endpoint `/health`
  - `livenessProbe`: endpoint `/health`
- Ressources:
  - requests/limits CPU et mémoire sur chaque conteneur
- Réplicas:
  - minimum 2 pour le backend en production

## 9) Observabilité et exploitation

### 9.1 Logs

- Logs structurés (JSON si possible).
- Corrélation via identifiant de requête.

### 9.2 Supervision

- Vérification de disponibilité via `/health`.
- Alertes sur:
  - erreurs 5xx
  - redémarrages fréquents de pods
  - latence anormale

### 9.3 SLO de base (exemple)

- Disponibilité API: 99.9% mensuel
- Latence p95 < 300ms

## 10) Sécurité DevOps

- Gestion des secrets via `Secret` Kubernetes ou coffre dédié.
- Rotation périodique des credentials.
- Mise à jour régulière des dépendances Node.js.
- Scan de vulnérabilités dans la CI.

## 11) Checklist de mise en prod

- [ ] Tests unitaires et lint OK
- [ ] Images Docker construites et scannées
- [ ] Variables d'environnement validées
- [ ] Secrets présents dans l'environnement cible
- [ ] Déploiement Kubernetes réussi
- [ ] Endpoint `/health` OK après déploiement
- [ ] Monitoring et alerting actifs

## 12) Commandes utiles (runbook)

```bash
# Statut des pods
kubectl get pods -n taskflow

# Logs backend
kubectl logs -f deploy/taskflow-backend -n taskflow

# Statut d'un rollout
kubectl rollout status deploy/taskflow-backend -n taskflow

# Redémarrer un déploiement
kubectl rollout restart deploy/taskflow-backend -n taskflow
```

---

Ce fichier sert de base DevOps pour le projet final: containeriser, automatiser, sécuriser et déployer TaskFlow proprement.
