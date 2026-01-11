#!/usr/bin/env bash
set -euo pipefail

# deploy-kind.sh
# 自动检测环境 - 如果缺少 kubectl/kind/helm，自动启动 DinD 容器进行离线部署
# 支持代理: 设置环境变量 HTTP_PROXY/HTTPS_PROXY 或使用 --proxy 参数

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

CLUSTER_NAME="kind"
KIND_NODE_IMAGE_FILE="kind_node_v1.27.3.tar.gz"
OFFLINE_IMAGES_FILE="k8s_goat_images_offline.tar.gz"
KIND_CONFIG="kind-config.yaml"
HELM_VALUES="./scenarios/metadata-db/values.yaml"

# 代理配置
HTTP_PROXY="${HTTP_PROXY:-}"
HTTPS_PROXY="${HTTPS_PROXY:-}"
NO_PROXY="${NO_PROXY:-}"

# 解析命令行参数
while [[ $# -gt 0 ]]; do
  case $1 in
    --proxy)
      HTTP_PROXY="$2"
      HTTPS_PROXY="$2"
      shift 2
      ;;
    --http-proxy)
      HTTP_PROXY="$2"
      shift 2
      ;;
    --https-proxy)
      HTTPS_PROXY="$2"
      shift 2
      ;;
    --no-proxy)
      NO_PROXY="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

echo "== K8s-Goat 离线部署脚本 =="
echo "ROOT_DIR=$ROOT_DIR"
if [ -n "$HTTP_PROXY" ]; then
  echo "HTTP_PROXY=$HTTP_PROXY"
  echo "HTTPS_PROXY=$HTTPS_PROXY"
fi

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    return 1
  fi
  return 0
}

show_help() {
  cat <<EOF
用法: $0 [选项]

选项:
  --proxy URL           同时设置 HTTP_PROXY 和 HTTPS_PROXY
  --http-proxy URL      设置 HTTP_PROXY
  --https-proxy URL     设置 HTTPS_PROXY
  --no-proxy HOSTS      设置 NO_PROXY（多个主机用逗号分隔）

环境变量:
  HTTP_PROXY           HTTP 代理地址
  HTTPS_PROXY          HTTPS 代理地址
  NO_PROXY             不需要代理的主机列表

示例:
  # 使用代理参数
  bash scripts/deploy-kind.sh --proxy http://192.168.246.76:7897

  # 使用环境变量
  export HTTP_PROXY=http://192.168.246.76:7897
  export HTTPS_PROXY=http://192.168.246.76:7897
  bash scripts/deploy-kind.sh

  # 不使用代理（默认）
  bash scripts/deploy-kind.sh

EOF
}

# 检查是否请求帮助
if [[ "${1:-}" == "-h" ]] || [[ "${1:-}" == "--help" ]]; then
  show_help
  exit 0
fi

# Check docker (required)
if ! require_cmd docker; then
  echo "ERROR: docker is required but not found" >&2
  exit 2
fi

# If kubectl/kind/helm missing, bootstrap DinD
NEED_DIND=0
for cmd in kubectl kind helm; do
  if ! require_cmd "$cmd"; then
    NEED_DIND=1
    break
  fi
done

bootstrap_dind() {
  echo "kubectl/kind/helm not found locally — bootstrapping DinD container..."
  IMAGE_TAG="kind-k8s-goat-moyusec-lingjing:v3.0"
  
  # Write kind-config.yaml (officially aligned port mappings)
  if [ ! -f "$ROOT_DIR/kind-config.yaml" ]; then
    cat > "$ROOT_DIR/kind-config.yaml" <<'KINDCFG'
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
  extraPortMappings:
  - containerPort: 30000
    hostPort: 1234  # kubernetes-goat-home
  - containerPort: 30001
    hostPort: 1230  # build-code
  - containerPort: 30002
    hostPort: 1231  # health-check
  - containerPort: 30003
    hostPort: 1232  # internal-proxy (SSRF)
  - containerPort: 30004
    hostPort: 1233  # system-monitor
  - containerPort: 30005
    hostPort: 1235  # poor-registry
  - containerPort: 30006
    hostPort: 1236  # hunger-check
- role: worker
- role: worker
networking:
  podSubnet: "10.244.0.0/16"
  serviceSubnet: "10.96.0.0/12"
KINDCFG
    echo "  ✓ wrote kind-config.yaml"
  fi

  # Write Dockerfile
  if [ ! -f "$ROOT_DIR/Dockerfile" ]; then
    cat > "$ROOT_DIR/Dockerfile" <<'DOCKERF'
FROM docker:24-dind

# 接收代理参数
ARG HTTP_PROXY=""
ARG HTTPS_PROXY=""
ARG NO_PROXY=""

ENV HTTP_PROXY=$HTTP_PROXY
ENV HTTPS_PROXY=$HTTPS_PROXY
ENV NO_PROXY=$NO_PROXY
ENV http_proxy=$HTTP_PROXY
ENV https_proxy=$HTTPS_PROXY
ENV no_proxy=$NO_PROXY

RUN sed -i 's/dl-cdn.alpinelinux.org/mirrors.aliyun.com/g' /etc/apk/repositories && \
    apk add --no-cache curl bash openssl git

RUN curl -LO "https://dl.k8s.io/release/v1.28.0/bin/linux/amd64/kubectl" && \
    chmod +x kubectl && mv kubectl /usr/local/bin/ && \
    curl -Lo /usr/local/bin/kind https://kind.sigs.k8s.io/dl/v0.20.0/kind-linux-amd64 && \
    chmod +x /usr/local/bin/kind && \
    curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 && \
    chmod 700 get_helm.sh && ./get_helm.sh && rm get_helm.sh

RUN git clone https://github.com/wpsec/kubernetes-goat-docker.git /opt/kubernetes-goat
COPY kind_node_v1.27.3.tar.gz /opt/kind_node_v1.27.3.tar.gz
COPY k8s_goat_images_offline.tar.gz /opt/k8s_goat_images_offline.tar.gz
COPY kind-config.yaml /etc/kind-config.yaml

RUN echo 'kubectl get nodes' >> /root/.bashrc

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/bin/bash", "/entrypoint.sh"]
DOCKERF
    echo "  ✓ wrote Dockerfile"
  fi

  # Write entrypoint.sh
  cat > "$ROOT_DIR/entrypoint.sh" <<'ENTRY'
#!/bin/bash
set -e

echo "======================================================"
echo "      摸鱼信安 + 灵镜联合发布 - K8s 安全实验环境 (V3.0)"
echo "      欢迎关注：微信公众号：摸鱼信安 + Sec铁匠铺"
echo "======================================================"

echo "正在启动内部 Docker 守护进程..."
dockerd-entrypoint.sh > /var/log/dockerd.log 2>&1 &
until docker info >/dev/null 2>&1; do sleep 2; done

echo "加载 KinD 节点镜像..."
if [ -f "/opt/kind_node_v1.27.3.tar.gz" ]; then
  zcat /opt/kind_node_v1.27.3.tar.gz | docker load
fi

echo "No kind clusters found."
echo "创建 K8s 集群..."
if ! kind get clusters | grep -q "^kind$"; then
  kind create cluster --config /etc/kind-config.yaml --image kindest/node:v1.27.3 --wait 5m
fi

echo "加载并分发靶场镜像..."
if [ -f "/opt/k8s_goat_images_offline.tar.gz" ]; then
  zcat /opt/k8s_goat_images_offline.tar.gz | docker load
  for img in $(docker images --format "{{.Repository}}:{{.Tag}}" | grep "k8s-goat"); do
    kind load docker-image "$img"
  done
fi

echo "修复 YAML 中 CRI socket 路径..."
echo "清理旧的 Metadata DB 和 Internal Proxy..."
echo "部署 Metadata DB..."
echo "部署 Internal Proxy..."
echo "部署其他靶场..."
echo "等待 Pod 就绪..."

# Run full deployment script
cd /opt/kubernetes-goat
bash /opt/kubernetes-goat/scripts/deploy-kind.sh

tail -f /dev/null
ENTRY
    chmod +x "$ROOT_DIR/entrypoint.sh"
    echo "  ✓ wrote entrypoint.sh"

  # Load base image if tar file exists
  if [ -f "$ROOT_DIR/docker:24-dind.tar" ]; then
    echo "Loading docker:24-dind base image..."
    BASE_IMAGE_ID=$(docker load -i "$ROOT_DIR/docker:24-dind.tar" | grep "Loaded image ID" | awk '{print $NF}')
    if [ -n "$BASE_IMAGE_ID" ]; then
      echo "  - Loaded image ID: $BASE_IMAGE_ID"
      docker tag "$BASE_IMAGE_ID" "docker:24-dind"
      echo "  - Tagged as docker:24-dind"
    fi
  else
    echo "ERROR: docker:24-dind.tar not found at $ROOT_DIR/docker:24-dind.tar" >&2
    exit 1
  fi

  # Build image
  echo "Building Docker image $IMAGE_TAG..."
  BUILD_ARGS=""
  if [ -n "$HTTP_PROXY" ]; then
    BUILD_ARGS="$BUILD_ARGS --build-arg HTTP_PROXY=$HTTP_PROXY"
    BUILD_ARGS="$BUILD_ARGS --build-arg HTTPS_PROXY=$HTTPS_PROXY"
    if [ -n "$NO_PROXY" ]; then
      BUILD_ARGS="$BUILD_ARGS --build-arg NO_PROXY=$NO_PROXY"
    fi
  fi
  
  # shellcheck disable=SC2086
  docker build --no-cache $BUILD_ARGS -t "$IMAGE_TAG" "$ROOT_DIR"

  # Run container
  if ! docker ps --format '{{.Names}}' | grep -q '^kind-k8s-goat$'; then
    echo "Running container kind-k8s-goat..."
    docker run --privileged -d --name kind-k8s-goat \
      --memory="4g" --cpus="4" \
      -p 1234:1234 -p 1230:1230 -p 1231:1231 -p 1232:1232 \
      -p 1233:1233 -p 1235:1235 -p 1236:1236 -p 1238:1238 -p 1237:1237 \
      "$IMAGE_TAG"
  fi

  echo "Tailing logs from kind-k8s-goat..."
  docker logs -f kind-k8s-goat
  exit 0
}

if [ $NEED_DIND -eq 1 ]; then
  bootstrap_dind
fi

# ============ 后续部署代码（在容器内或本机 kind 环境运行）============

sed_inplace() {
  local pattern=$1; shift
  local file=$1; shift
  if sed --version >/dev/null 2>&1; then
    sed -i "$pattern" "$file"
  else
    sed -i '' "$pattern" "$file"
  fi
}

trap 'echo "ERROR: deploy failed at line $LINENO"; exit 1' ERR

echo "1) 加载 Kind 节点镜像"
if [ -f "$KIND_NODE_IMAGE_FILE" ]; then
  echo "  - loading $KIND_NODE_IMAGE_FILE into docker"
  zcat "$KIND_NODE_IMAGE_FILE" | docker load || true
else
  echo "  - $KIND_NODE_IMAGE_FILE not found, skipping"
fi

echo "2) 创建 Kind 集群"
if kind get clusters | grep -q "${CLUSTER_NAME}"; then
  echo "  - kind cluster '${CLUSTER_NAME}' already exists"
else
  if [ -f "$KIND_CONFIG" ]; then
    echo "  - creating kind cluster with config $KIND_CONFIG"
    kind create cluster --name "$CLUSTER_NAME" --config "$KIND_CONFIG" --image kindest/node:v1.27.3 --wait 5m
  else
    echo "  - creating kind cluster with default config"
    kind create cluster --name "$CLUSTER_NAME" --image kindest/node:v1.27.3 --wait 5m
  fi
fi

echo "3) 加载离线镜像"
if [ -f "$OFFLINE_IMAGES_FILE" ]; then
  echo "  - loading $OFFLINE_IMAGES_FILE into docker"
  zcat "$OFFLINE_IMAGES_FILE" | docker load

  echo "  - distributing images to kind nodes"
  mapfile -t imgs < <(docker images --format "{{.Repository}}:{{.Tag}}" | grep "k8s-goat" || true)
  if [ ${#imgs[@]} -eq 0 ]; then
    echo "  - warning: no k8s-goat images found"
  else
    for img in "${imgs[@]}"; do
      echo "    - kind loading image: $img"
      kind load docker-image --name "$CLUSTER_NAME" "$img"
    done
  fi
else
  echo "  - $OFFLINE_IMAGES_FILE not found, skipping"
fi

echo "4) 修正 CRI socket 路径"
find ./scenarios -name "*.yaml" -type f -print0 | while IFS= read -r -d '' f; do
  if grep -q "/var/run/cri-dockerd.sock" "$f" >/dev/null 2>&1; then
    echo "    - update $f: /var/run/cri-dockerd.sock -> /run/containerd/containerd.sock"
    sed_inplace "s|/var/run/cri-dockerd.sock|/run/containerd/containerd.sock|g" "$f"
  fi
  if grep -q "docker-sock-volume" "$f" >/dev/null 2>&1; then
    echo "    - update $f: docker-sock-volume -> containerd-sock-volume"
    sed_inplace "s|docker-sock-volume|containerd-sock-volume|g" "$f"
  fi
done

echo "5) 清理旧资源"
kubectl delete deployment metadata-db --ignore-not-found || true
kubectl delete service metadata-db --ignore-not-found || true
kubectl delete deployment internal-proxy-deployment --ignore-not-found || true
kubectl delete service internal-proxy-api-service --ignore-not-found || true

echo "6) 卸载遗留 Helm"
if helm list -n default | awk 'NR>1 {print $1}' | grep -q "^metadata-db$" >/dev/null 2>&1; then
  echo "  - uninstalling previous release metadata-db"
  helm uninstall metadata-db --namespace default || true
fi

echo "7) 部署 Metadata DB"
if [ -f "$HELM_VALUES" ]; then
  helm upgrade --install metadata-db ./scenarios/metadata-db \
    --namespace default -f "$HELM_VALUES" \
    --set service.type=NodePort --set service.nodePort=30001 \
    --wait --atomic
else
  echo "  - warning: $HELM_VALUES not found, installing with defaults"
  helm upgrade --install metadata-db ./scenarios/metadata-db \
    --namespace default \
    --set service.type=NodePort --set service.nodePort=30001 \
    --wait --atomic
fi

echo "8) 部署 Internal Proxy"
kubectl apply -f scenarios/internal-proxy/deployment.yaml

echo "9) 部署其他靶场 (官方 10 个靶场)"
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
  "scenarios/hidden-in-layers/deployment.yaml"
do
  if [ -f "$manifest" ]; then
    echo "  - kubectl apply $manifest"
    kubectl apply -f "$manifest" || true
  else
    echo "  - skip $manifest (not found)"
  fi
done

echo "10) 部署安全监控和策略工具"
for manifest in \
  "sesource/falco.yaml" \
  "sesource/kyverno.yaml" \
  "sesource/tetragon.yaml"
do
  if [ -f "$manifest" ]; then
    echo "  - kubectl apply $manifest (安全工具)"
    kubectl apply -f "$manifest" || true
  else
    echo "  - skip $manifest (not found)"
  fi
done

echo "11) 等待 Pod 就绪"
kubectl wait --for=condition=Ready pod --all --all-namespaces --timeout=300s || true

echo ""
echo "=========================================="
echo "✅ 环境部署完成"
echo "=========================================="
kubectl get pods -A
kubectl get svc -A
