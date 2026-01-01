#!/usr/bin/env bash
set -euo pipefail

CLUSTER_NAME="lab"
CORE_DNS_CONFIG_PATCH=$(mktemp)
RESOLVER_FILE="/etc/resolver/lab-local.kind"

echo "=== 1. creating kind cluster ==="
kind create cluster --name $CLUSTER_NAME --config ./source/cluster-init.yml

echo "=== 2. patch CoreDNS for lab-local.kind ==="

cat > "$CORE_DNS_CONFIG_PATCH" <<'EOF'
[{"op": "add", "path": "/data/lab-local.kind", "value": "forward . 10.244.0.0/16\nlog\nerrors"}]
EOF

kubectl -n kube-system patch configmap coredns --type=json -p "$(cat $CORE_DNS_CONFIG_PATCH)"
kubectl -n kube-system rollout restart deployment coredns

echo "=== 3. config resolver on macOS ==="

sudo mkdir -p /etc/resolver
sudo tee "$RESOLVER_FILE" >/dev/null <<EOF
nameserver 127.0.0.1
port 15353
EOF

sudo killall -HUP mDNSResponder || true
echo "DNS done --> *.lab-local.kind"

echo "=== 4. applying Ingress Nginx ==="

kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml
# patch for master (only master node at kind can be ingress)
kubectl patch deployment ingress-nginx-controller \
  -n ingress-nginx \
  -p '{"spec":{"template":{"spec":{"nodeSelector":{"kubernetes.io/hostname":"lab-control-plane"}}}}}'

echo "=== 5. applying ArgoCD ==="

kubectl create namespace argocd || true
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

echo "=== 6. create ingress for ArgoCD ==="
kubectl apply -f ./source/argocd-ingress.yml

echo "=== 7. get agro admin pass ==="

echo "Admin password:"
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 --decode
echo
echo "access to  ArgoCD: https://argocd.lab-local.kind (from nginx ingress)"
