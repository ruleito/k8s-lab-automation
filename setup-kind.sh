#!/usr/bin/env bash
set -euo pipefail

CLUSTER_NAME="lab-1"
INGRESS_NAMESPACE="ingress-nginx"

echo "=== 0. checking dependencies ==="

# Проверка minikube
if ! command -v minikube &>/dev/null; then
  echo "minikube не найден. Скачиваем и устанавливаем..."
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

# 1. Выгрузить Corefile в переменную
COREFILE=$(kubectl -n kube-system get configmap coredns -o jsonpath='{.data.Corefile}')

# 2. Проверить, нет ли уже блока для lab-local.minikube (чтобы не дублировать)
if ! echo "$COREFILE" | grep -q 'lab-local\.minikube'; then
  # 3. Добавить блок в конец (перед закрывающей фигурной скобкой `}` сервера `.:53`, или как отдельный блок)
  # Важно: блок должен быть *отдельным*, как у вас — это корректно.
  NEW_BLOCK="lab-local.minikube:53 {
    errors
    cache 30
    forward . $MINIKUBE_IP
}"

  # Добавляем новый блок в конец Corefile (после основного блока)
  COREFILE="$COREFILE
$NEW_BLOCK"
fi

# 4. Применить обновлённый Corefile
kubectl -n kube-system create configmap coredns --from-literal=Corefile="$COREFILE" -o yaml --dry-run=client | kubectl apply -f -

# 5. Рестарт coredns
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
