#!/usr/bin/env bash
# 摸鱼信安 + 灵镜联合发布 - K8s 安全实验环境 (V3.0)
set -euo pipefail

# 自动获取根目录 (适配 /root/DKinD)
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

CLUSTER_NAME="kind"
KIND_NODE_IMAGE_FILE="kind_node_v1.27.3.tar.gz"
OFFLINE_IMAGES_FILE="k8s_goat_images_offline.tar.gz"
KIND_CONFIG="kind-config.yaml"
HELM_VALUES="./kubernetes-goat-docker/scenarios/metadata-db/values.yaml"

# 代理配置
HTTP_PROXY="${HTTP_PROXY:-}"
HTTPS_PROXY="${HTTPS_PROXY:-}"

# 解析参数
while [[ $# -gt 0 ]]; do
  case $1 in
    --proxy) HTTP_PROXY="$2"; HTTPS_PROXY="$2"; shift 2 ;;
    *) echo "未知选项: $1"; exit 1 ;;
  esac
done

require_cmd() { command -v "$1" >/dev/null 2>&1; }

# 环境检查：如果缺少 kubectl/kind/helm，则执行镜像封装逻辑
if ! require_cmd kubectl || ! require_cmd kind || ! require_cmd helm; then
  echo "== 检测到缺少工具，正在构建全离线 DinD 镜像 =="
  
  # 1. 预先加载基础 Docker 镜像 (防止联网拉取 docker:24-dind)
  if [ -f "docker:24-dind.tar" ]; then
    echo "加载基础镜像 docker:24-dind.tar..."
    docker load -i "docker:24-dind.tar"
  fi

  # 2. 写入全离线 Dockerfile
  cat > "$ROOT_DIR/Dockerfile" <<DOCKERF
FROM docker:24-dind
# 设置代理用于构建阶段下载工具
ARG HTTP_PROXY=""
ARG HTTPS_PROXY=""
ENV HTTP_PROXY=\$HTTP_PROXY HTTPS_PROXY=\$HTTPS_PROXY
RUN sed -i 's/dl-cdn.alpinelinux.org/mirrors.aliyun.com/g' /etc/apk/repositories && \\
    apk add --no-cache curl bash openssl git
# 安装 K8s 工具链
RUN curl -LO "https://dl.k8s.io/release/v1.28.0/bin/linux/amd64/kubectl" && \\
    chmod +x kubectl && mv kubectl /usr/local/bin/ && \\
    curl -Lo /usr/local/bin/kind https://kind.sigs.k8s.io/dl/v0.20.0/kind-linux-amd64 && \\
    chmod +x /usr/local/bin/kind && \\
    curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 && \\
    chmod 700 get_helm.sh && ./get_helm.sh && rm get_helm.sh

# 【核心：物理封装】将当前目录下所有文件全部拷贝进镜像
RUN mkdir -p /opt/kubernetes-goat
COPY . /opt/kubernetes-goat/
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh /opt/kubernetes-goat/scripts/deploy-kind.sh

ENTRYPOINT ["/bin/bash", "/entrypoint.sh"]
DOCKERF

  # 3. 写入 entrypoint.sh
  cat > "$ROOT_DIR/entrypoint.sh" <<'ENTRY'
#!/bin/bash
set -e
echo "启动内部 Docker 守护进程..."
dockerd-entrypoint.sh > /var/log/dockerd.log 2>&1 &
until docker info >/dev/null 2>&1; do sleep 2; done
# 进入目录执行原脚本逻辑
cd /opt/kubernetes-goat
bash scripts/deploy-kind.sh
tail -f /dev/null
ENTRY
  chmod +x "$ROOT_DIR/entrypoint.sh"

  # 4. 执行镜像构建
  docker build --build-arg HTTP_PROXY="$HTTP_PROXY" -t kind-k8s-goat:v3.0 "$ROOT_DIR"
  echo "✅ 镜像构建成功：kind-k8s-goat:v3.0"
  exit 0
fi

# ============ 部署逻辑 (第 1-11 步，在容器内完全离线执行) ============

sed_inplace() { sed -i "$1" "$2"; }
trap 'echo "错误: 部署在第 $LINENO 行失败"; exit 1' ERR

echo "1) 加载 Kind 节点镜像"
[ -f "$KIND_NODE_IMAGE_FILE" ] && docker load -i "$KIND_NODE_IMAGE_FILE"

echo "2) 创建 Kind 集群 (使用离线镜像)"
if ! kind get clusters | grep -q "${CLUSTER_NAME}"; then
  # 自动创建 kind-config.yaml 如果不存在
  if [ ! -f "$KIND_CONFIG" ]; then
    cat > "$KIND_CONFIG" <<KINDCFG
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
  - role: control-plane
    extraPortMappings:
      - containerPort: 30000; hostPort: 1234
      - containerPort: 30003; hostPort: 1232
KINDCFG
  fi
  kind create cluster --name "$CLUSTER_NAME" --config "$KIND_CONFIG" --image kindest/node:v1.27.3 --wait 5m
fi

echo "3) 加载靶场离线镜像"
if [ -f "$OFFLINE_IMAGES_FILE" ]; then
  docker load -i "$OFFLINE_IMAGES_FILE"
  mapfile -t imgs < <(docker images --format "{{.Repository}}:{{.Tag}}" | grep "k8s-goat" || true)
  for img in "${imgs[@]}"; do
    kind load docker-image --name "$CLUSTER_NAME" "$img"
  done
fi

echo "4) 修正 CRI socket 路径"
# 注意：基于你提供的目录结构，路径应在 kubernetes-goat-docker 内
find ./kubernetes-goat-docker/scenarios -name "*.yaml" -type f -exec sed -i "s|/var/run/cri-dockerd.sock|/run/containerd/containerd.sock|g" {} +
find ./kubernetes-goat-docker/scenarios -name "*.yaml" -type f -exec sed -i "s|docker-sock-volume|containerd-sock-volume|g" {} +

echo "5-7) 部署数据库 (Helm)"
kubectl delete deployment metadata-db --ignore-not-found || true
cd kubernetes-goat-docker
helm upgrade --install metadata-db ./scenarios/metadata-db \
  --namespace default --set service.type=NodePort --set service.nodePort=30007 --wait --atomic

echo "8-10) 部署全场景靶场"
kubectl apply -f scenarios/internal-proxy/deployment.yaml
# 遍历 scenarios 目录下的所有 yaml (根据你的脚本原逻辑)
for manifest in $(find scenarios -maxdepth 2 -name "*.yaml"); do
  kubectl apply -f "$manifest" || true
done

echo "11) 等待 Pod 就绪"
kubectl wait --for=condition=Ready pod --all --all-namespaces --timeout=300s || true
echo "✅ 离线环境部署完成"