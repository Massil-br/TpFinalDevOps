#!/usr/bin/env bash
set -euo pipefail

# Premier deploiement sur le VPS
# - Lance Redis via docker-compose.vps.yml (network_mode: host)
# - Remplace HOST_IP dans les ConfigMap par l'IP du node k3s
# - Applique les 2 namespaces sur k3s

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPTS_DIR="${REPO_ROOT}/scripts"

if [[ -z "${DOCKER_USERNAME:-}" ]]; then
  echo "Erreur: export DOCKER_USERNAME=<ton_user_dockerhub> avant de lancer ce script"
  exit 1
fi

echo "==> Lancement de Redis via docker-compose"
docker compose -f "${SCRIPTS_DIR}/docker-compose.vps.yml" up -d
sleep 3
docker compose -f "${SCRIPTS_DIR}/docker-compose.vps.yml" ps

echo "==> Detection de l'IP du node k3s (accessible depuis les pods)"
HOST_IP=$(kubectl get node -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
echo "    HOST_IP = ${HOST_IP}"

echo "==> Verification de Redis depuis le node"
if ! redis-cli -h "${HOST_IP}" ping >/dev/null 2>&1; then
  echo "    redis-cli non installe, on saute le test (Redis tourne via docker)"
fi

echo "==> Preparation des manifests (substitution HOST_IP et DOCKER_USERNAME)"
TMP_DIR=$(mktemp -d)
trap "rm -rf ${TMP_DIR}" EXIT

for env in staging production; do
  mkdir -p "${TMP_DIR}/${env}"
  for f in namespace configmap secret deployment service; do
    sed \
      -e "s|HOST_IP|${HOST_IP}|g" \
      -e "s|<DOCKER_USERNAME>|${DOCKER_USERNAME}|g" \
      "${REPO_ROOT}/k8s/${env}/${f}.yml" > "${TMP_DIR}/${env}/${f}.yml"
  done
done

echo "==> Deploiement staging"
kubectl apply -f "${TMP_DIR}/staging/"

echo "==> Deploiement production"
kubectl apply -f "${TMP_DIR}/production/"

echo "==> Attente du rollout"
kubectl rollout status deployment/taskflow-backend -n taskflow-staging    --timeout=180s
kubectl rollout status deployment/taskflow-backend -n taskflow-production --timeout=180s

echo ""
echo "==> Etat des pods"
kubectl get pods -n taskflow-staging
echo "---"
kubectl get pods -n taskflow-production

echo ""
VPS_IP=$(curl -sf ifconfig.me)
echo "==> Deploiement reussi"
echo "    Staging    : http://${VPS_IP}:30001/health"
echo "    Production : http://${VPS_IP}:30002/health"
