#!/usr/bin/env bash
set -euo pipefail

CLUSTER_NAME="lab-1"
INGRESS_NAMESPACE="ingress-nginx"

echo "=== 0. checking dependencies ==="

if ! command -v minikube &>/dev/null; then
  echo "minikube not find... installing"
  curl -Lo minikube https://github.com/kubernetes/minikube/releases/download/v1.35.0/minikube-darwin-arm64
  chmod +x minikube
  sudo mv minikube /usr/local/bin/
fi

echo "=== 1. starting minikube cluster ==="
minikube start \
  --driver=vfkit \
  --network=vmnet-shared \
  --cpus=2 \
  --memory=4096 \
  --disk-size=10g \
  -p "$CLUSTER_NAME"

MINIKUBE_IP=$(minikube ip -p "$CLUSTER_NAME")
echo "Minikube IP: $MINIKUBE_IP"

echo "=== 2. enabling ingress and ingress-dns ==="
minikube addons enable ingress -p "$CLUSTER_NAME"
minikube addons enable ingress-dns -p "$CLUSTER_NAME"

echo "=== 3. configuring macOS resolver ==="
sudo mkdir -p /etc/resolver
sudo tee /etc/resolver/lab-local.minikube >/dev/null <<EOF
nameserver $MINIKUBE_IP
domain lab-local.minikube
timeout 5
EOF
sudo killall -HUP mDNSResponder || true
echo "DNS ready on host --> *.lab-local.minikube via $MINIKUBE_IP"

echo "=== 4. configuring in-cluster CoreDNS for local domain ==="

COREFILE=$(kubectl -n kube-system get configmap coredns -o jsonpath='{.data.Corefile}')

if ! echo "$COREFILE" | grep -q 'lab-local\.minikube'; then
  NEW_BLOCK="lab-local.minikube:53 {
    errors
    cache 30
    forward . $MINIKUBE_IP
}"

  COREFILE="$COREFILE
$NEW_BLOCK"
fi

kubectl -n kube-system create configmap coredns --from-literal=Corefile="$COREFILE" -o yaml --dry-run=client | kubectl apply -f -

kubectl -n kube-system rollout restart deployment/coredns
kubectl -n kube-system rollout status deployment/coredns --timeout=120s

echo "=== 5. installing ArgoCD ==="
kubectl create namespace argocd || true
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

echo "=== 6. creating ArgoCD ingress ==="
sleep 20
kubectl apply -f ./source/argocd-ingress.yml

echo "=== 7. show ArgoCD credentials ==="
sleep 40
ARGO_PASS=$(kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 --decode)
echo "ArgoCD admin password: $ARGO_PASS"
echo "Access ArgoCD at: https://argocd.lab-local.minikube"

echo "=== 8. test DNS resolution ==="
curl https://argocd.lab-local.minikube -k -I
