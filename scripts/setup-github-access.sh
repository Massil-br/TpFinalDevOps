#!/usr/bin/env bash
set -euo pipefail

# Genere le kubeconfig a coller dans les GitHub Secrets
# KUBE_CONFIG_STAGING et KUBE_CONFIG_PROD

VPS_IP="${VPS_IP:-$(curl -sf ifconfig.me)}"

if [[ ! -f /etc/rancher/k3s/k3s.yaml ]]; then
  echo "Erreur: k3s non installe. Lance d'abord ./scripts/install-vps.sh"
  exit 1
fi

OUTPUT=$(sudo cat /etc/rancher/k3s/k3s.yaml | sed "s|https://127.0.0.1:6443|https://${VPS_IP}:6443|")

echo ""
echo "==> Kubeconfig genere pour GitHub Actions"
echo "    Copie-colle INTEGRALEMENT le bloc ci-dessous dans :"
echo ""
echo "    GitHub > Settings > Secrets and variables > Actions > New repository secret"
echo ""
echo "    Cree 2 secrets avec le MEME contenu :"
echo "      - KUBE_CONFIG_STAGING"
echo "      - KUBE_CONFIG_PROD"
echo ""
echo "    (Les 2 namespaces sont sur le meme cluster, meme kubeconfig)"
echo ""
echo "================ DEBUT KUBECONFIG ================"
echo "${OUTPUT}"
echo "================= FIN KUBECONFIG ================="
echo ""
echo "==> Autres secrets a creer sur GitHub :"
echo "    DOCKER_USERNAME : ton user Docker Hub"
echo "    DOCKER_PASSWORD : Access Token Docker Hub (pas le mot de passe)"
