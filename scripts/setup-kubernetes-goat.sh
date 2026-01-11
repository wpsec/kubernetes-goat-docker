#!/usr/bin/env bash
# 靶场环境自动部署脚本 - 仅在容器内部运行
set -euo pipefail

# 定义容器内部路径变量
CLUSTER_NAME="kind"
KIND_NODE_IMAGE="/opt/kind_node_v1.27.3.tar.gz"
GOAT_IMAGES_OFFLINE="/opt/k8s_goat_images_offline.tar.gz"
KIND_CONFIG="/etc/kind-config.yaml"

cd /opt/kubernetes-goat

echo "1) 加载 KinD 节点镜像..."
if [ -f "$KIND_NODE_IMAGE" ]; then
    zcat "$KIND_NODE_IMAGE" | docker load || true
fi

echo "2) 启动 KinD 集群..."
if ! kind get clusters | grep -q "^${CLUSTER_NAME}$"; then
    kind create cluster --name "$CLUSTER_NAME" --config "$KIND_CONFIG" --image kindest/node:v1.27.3 --wait 5m
fi

echo "3) 加载并分发靶场镜像..."
if [ -f "$GOAT_IMAGES_OFFLINE" ]; then
    zcat "$GOAT_IMAGES_OFFLINE" | docker load
    # 获取所有靶场镜像并加载到集群节点
    mapfile -t imgs < <(docker images --format "{{.Repository}}:{{.Tag}}" | grep "k8s-goat" || true)
    for img in "${imgs[@]}"; do
        kind load docker-image --name "$CLUSTER_NAME" "$img"
    done
fi

echo "4) 修正 Containerd Socket 路径兼容性..."
# 修改 YAML 路径以适配 KinD 内部环境
find ./scenarios -name "*.yaml" -type f -exec sed -i "s|/var/run/cri-dockerd.sock|/run/containerd/containerd.sock|g" {} +
find ./scenarios -name "*.yaml" -type f -exec sed -i "s|docker-sock-volume|containerd-sock-volume|g" {} +

echo "5) 部署数据库基础服务 (Helm)..."
helm upgrade --install metadata-db ./scenarios/metadata-db \
    --namespace default --set service.type=NodePort --set service.nodePort=30007 --wait --atomic

echo "6) 部署靶场场景..."
# 提前创建必要的命名空间
kubectl create ns big-monolith --dry-run=client -o yaml | kubectl apply -f -
kubectl create ns secure-middleware --dry-run=client -o yaml | kubectl apply -f -

# 部署 Internal Proxy (对应宿主 1232 端口)
kubectl apply -f scenarios/internal-proxy/deployment.yaml

# 遍历部署所有靶场 YAML
for manifest in \
  "scenarios/insecure-rbac/setup.yaml" \
  "scenarios/batch-check/job.yaml" \
  "scenarios/build-code/deployment.yaml" \
  "scenarios/cache-store/deployment.yaml" \
  "scenarios/health-check/deployment.yaml" \
  "scenarios/hunger-check/deployment.yaml" \
  "scenarios/kubernetes-goat-home/deployment.yaml" \
  "scenarios/poor-registry/deployment.yaml" \
  "scenarios/system-monitor/deployment.yaml" \
  "scenarios/hidden-in-layers/deployment.yaml" \
  "scenarios/docker-bench-security/deployment.yaml" \
  "scenarios/privileged-container/deployment.yaml"
do
    [ -f "$manifest" ] && kubectl apply -f "$manifest" || echo "跳过 $manifest"
done

echo "7) 部署安全工具 (Falco/Kyverno/Tetragon)..."
kubectl apply -f sesource/ || true

echo "8) 等待所有服务就绪..."
kubectl wait --for=condition=Ready pod --all --all-namespaces --timeout=300s || true

echo "✅ 环境部署成功！访问 http://127.0.0.1:1234 开始练习"