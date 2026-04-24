#!/usr/bin/env bash
set -euo pipefail

# Installation k3s sur un petit VPS + firewall + Docker
# A executer une fois sur le VPS (sudo requis)

VPS_IP="${VPS_IP:-$(curl -sf ifconfig.me)}"

echo "==> IP publique detectee: ${VPS_IP}"

echo "==> Installation Docker (pour docker-compose Redis)"
if ! command -v docker >/dev/null 2>&1; then
  curl -fsSL https://get.docker.com | sh
  sudo usermod -aG docker "$USER"
fi

echo "==> Installation k3s (sans Traefik, ServiceLB, metrics-server)"
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="\
  --disable traefik \
  --disable servicelb \
  --disable metrics-server \
  --write-kubeconfig-mode 644 \
  --tls-san ${VPS_IP}" sh -

echo "==> Attente du demarrage de k3s"
until sudo kubectl get nodes >/dev/null 2>&1; do sleep 2; done

echo "==> Configuration kubectl pour l'utilisateur courant"
mkdir -p "$HOME/.kube"
sudo cp /etc/rancher/k3s/k3s.yaml "$HOME/.kube/config"
sudo chown "$(id -u):$(id -g)" "$HOME/.kube/config"
chmod 600 "$HOME/.kube/config"

if ! grep -q "KUBECONFIG" "$HOME/.bashrc"; then
  echo 'export KUBECONFIG=$HOME/.kube/config' >> "$HOME/.bashrc"
fi
export KUBECONFIG="$HOME/.kube/config"

echo "==> Configuration firewall (ufw)"
if command -v ufw >/dev/null 2>&1; then
  sudo ufw allow 22/tcp    || true
  sudo ufw allow 6443/tcp  || true
  sudo ufw allow 30001/tcp || true
  sudo ufw allow 30002/tcp || true
  sudo ufw deny  6379/tcp  || true
  sudo ufw --force enable  || true
  sudo ufw status
fi

echo ""
kubectl get nodes
echo ""
echo "==> Installation terminee"
echo "    IP VPS         : ${VPS_IP}"
echo "    API k8s        : https://${VPS_IP}:6443"
echo "    Staging URL    : http://${VPS_IP}:30001/health"
echo "    Production URL : http://${VPS_IP}:30002/health"
echo ""
echo "==> Etapes suivantes :"
echo "    1. ./scripts/first-deploy.sh"
echo "    2. ./scripts/setup-github-access.sh (pour recuperer le kubeconfig GitHub)"
