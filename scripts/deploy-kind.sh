#!/usr/bin/env bash
set -euo pipefail

# deploy-kind.sh
# 统一部署脚本 - 支持三种模式: build (仅构建镜像), run (仅运行容器), all (构建并运行)
# 自动检测环境 - 如果缺少 kubectl/kind/helm，自动启动 DinD 容器进行离线部署
# 支持代理: 设置环境变量 HTTP_PROXY/HTTPS_PROXY 或使用 --proxy 参数

# ========== 计时功能 ==========
SCRIPT_START_TIME=$(date +%s)

format_duration() {
  local seconds=$1
  local hours=$((seconds / 3600))
  local minutes=$(((seconds % 3600) / 60))
  local secs=$((seconds % 60))
  
  if [ $hours -gt 0 ]; then
    printf "%d 小时 %d 分钟 %d 秒" $hours $minutes $secs
  elif [ $minutes -gt 0 ]; then
    printf "%d 分钟 %d 秒" $minutes $secs
  else
    printf "%d 秒" $secs
  fi
}

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

# 运行模式: build (仅构建镜像), run (仅运行容器), all (构建并运行)
MODE="all"

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
    build)
      MODE="build"
      shift
      ;;
    run)
      MODE="run"
      shift
      ;;
    all)
      MODE="all"
      shift
      ;;
    -h|--help)
      show_help
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

echo "== K8s-Goat 离线部署脚本 =="
echo "MODE=$MODE"
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
用法: $0 [命令] [选项]

命令:
  build                 仅构建 Docker 镜像（不运行容器）
  run                   仅运行已构建的镜像（假设镜像已存在）
  all                   构建镜像并运行容器（默认）
  -h, --help           显示此帮助信息

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
  # 构建镜像并运行（一步完成）
  bash scripts/deploy-kind.sh --proxy http://192.168.246.76:7897

  # 仅构建镜像（分两步）
  bash scripts/deploy-kind.sh build --proxy http://192.168.246.76:7897

  # 仅运行容器（假设镜像已存在）
  bash scripts/deploy-kind.sh run

  # 或使用环境变量
  export HTTP_PROXY=http://192.168.246.76:7897
  bash scripts/deploy-kind.sh build

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

# 如果只是运行容器，就不需要检查 kubectl/kind/helm
if [ "$MODE" = "run" ]; then
  echo "运行模式: 仅运行容器（假设镜像已构建）"
  # 跳过 DIND bootstrap，直接调用 run-container.sh
  bash "$ROOT_DIR/scripts/run-container.sh" start
  exit 0
fi

# If kubectl/kind/helm missing, bootstrap DinD (对于 build 和 all 模式)
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
  # 3 个节点：1 control-plane + 2 worker
  if [ ! -f "$ROOT_DIR/kind-config.yaml" ]; then
    cat > "$ROOT_DIR/kind-config.yaml" <<'KINDCFG'
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
  - role: control-plane
    extraPortMappings:
      - containerPort: 30001  # build-code
        hostPort: 1230
      - containerPort: 30002  # health-check
        hostPort: 1231
      - containerPort: 30003  # internal-proxy
        hostPort: 1232
      - containerPort: 30004  # system-monitor
        hostPort: 1233
      - containerPort: 30000  # goat-home
        hostPort: 1234
      - containerPort: 30005  # poor-registry
        hostPort: 1235
      - containerPort: 30006  # hunger-check
        hostPort: 1236
      - containerPort: 30007  # metadata-db
        hostPort: 1237
  - role: worker
  - role: worker

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

# 创建 kind-config.yaml（使用 printf 方式，避免 heredoc 问题，3 个节点：1 control-plane + 2 worker）
RUN mkdir -p /etc && printf 'kind: Cluster\napiVersion: kind.x-k8s.io/v1alpha4\nnodes:\n  - role: control-plane\n    extraPortMappings:\n      - containerPort: 30001\n        hostPort: 1230\n      - containerPort: 30002\n        hostPort: 1231\n      - containerPort: 30003\n        hostPort: 1232\n      - containerPort: 30004\n        hostPort: 1233\n      - containerPort: 30000\n        hostPort: 1234\n      - containerPort: 30005\n        hostPort: 1235\n      - containerPort: 30006\n        hostPort: 1236\n      - containerPort: 30007\n        hostPort: 1237\n  - role: worker\n  - role: worker\n' > /etc/kind-config.yaml

# 复制本地项目文件（包括所有 scenarios, scripts 等）
COPY . /opt/kubernetes-goat/

# 尝试复制可选的离线镜像文件（如果存在）
RUN if [ -f "/opt/kubernetes-goat/kind_node_v1.27.3.tar.gz" ]; then \
      mv /opt/kubernetes-goat/kind_node_v1.27.3.tar.gz /opt/; \
    fi && \
    if [ -f "/opt/kubernetes-goat/k8s_goat_images_offline.tar.gz" ]; then \
      mv /opt/kubernetes-goat/k8s_goat_images_offline.tar.gz /opt/; \
    fi

# 如果没有 scenarios 目录，从 github 克隆
RUN if [ ! -d "/opt/kubernetes-goat/scenarios" ]; then \
      git clone https://github.com/wpsec/kubernetes-goat-docker.git /tmp/k8s-goat-clone && \
      cp -r /tmp/k8s-goat-clone/* /opt/kubernetes-goat/ && \
      rm -rf /tmp/k8s-goat-clone; \
    fi

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
DOCKER_PID=$!
until docker info >/dev/null 2>&1; do sleep 2; done

echo "加载 KinD 节点镜像..."
if [ -f "/opt/kind_node_v1.27.3.tar.gz" ]; then
  zcat /opt/kind_node_v1.27.3.tar.gz | docker load
fi

echo "创建 K8s 集群..."
echo "  - 检查 kind-config.yaml 是否存在..."
if [ ! -f "/etc/kind-config.yaml" ]; then
  echo "  ERROR: /etc/kind-config.yaml 文件不存在!"
  exit 1
fi

if ! kind get clusters | grep -q "^kind$"; then
  echo "  - 使用 kind-config.yaml 创建集群..."
  kind create cluster --config /etc/kind-config.yaml --image kindest/node:v1.27.3 --wait 5m
else
  echo "  - K8s 集群已存在"
fi

echo "移除 control-plane 的 taint，允许调度普通 Pod..."
kubectl taint nodes kind-control-plane node-role.kubernetes.io/control-plane:NoSchedule- 2>/dev/null || true

echo "加载并分发靶场镜像..."
if [ -f "/opt/k8s_goat_images_offline.tar.gz" ]; then
  echo "  - 解压离线镜像包..."
  zcat /opt/k8s_goat_images_offline.tar.gz | docker load
  
  echo "  - 删除不需要的 Falco 镜像..."
  docker rmi falcosecurity/falco:0.42.1 2>/dev/null || true
  docker rmi falcosecurity/falco-driver-loader:0.42.1 2>/dev/null || true
  docker rmi falcosecurity/falcoctl:0.11.4 2>/dev/null || true
  
  echo "  - 等待 Docker 完全就绪..."
  sleep 3
  
  echo "  - 分发关键镜像到 Kind 集群节点..."
  # 只加载关键镜像到节点，减少磁盘占用
  CRITICAL_IMAGES=(
    "madhuakula/k8s-goat-health-check:latest"
    "madhuakula/k8s-goat-metadata-db:latest"
    "madhuakula/k8s-goat-internal-api:latest"
    "madhuakula/k8s-goat-build-code:latest"
    "madhuakula/k8s-goat-home:latest"
    "madhuakula/k8s-goat-cache-store:latest"
    "madhuakula/k8s-goat-batch-check:latest"
  )
  
  echo "    找到 ${#CRITICAL_IMAGES[@]} 个关键镜像，开始加载..."
  for img in "${CRITICAL_IMAGES[@]}"; do
    if docker image inspect "$img" > /dev/null 2>&1; then
      echo "    - kind load docker-image: $img"
      kind load docker-image "$img" 2>&1 | grep -v "^Image ID:" || true
    fi
  done
  
  echo "  - 验证镜像加载完成..."
  sleep 2
  echo "  - 关键镜像加载完毕"
fi

# ===== 以下逻辑复制自 deploy-kind.sh 的主要部分 =====

ROOT_DIR="/opt/kubernetes-goat"
CLUSTER_NAME="kind"
OFFLINE_IMAGES_FILE="/opt/k8s_goat_images_offline.tar.gz"
HELM_VALUES="./scenarios/metadata-db/values.yaml"

sed_inplace() {
  local pattern=$1; shift
  local file=$1; shift
  if sed --version >/dev/null 2>&1; then
    sed -i "$pattern" "$file"
  else
    sed -i '' "$pattern" "$file"
  fi
}

cd "$ROOT_DIR"

echo "修复 CRI socket 路径..."
find ./scenarios -name "*.yaml" -type f -print0 | while IFS= read -r -d '' f; do
  if grep -qE "/var/run/cri-dockerd.sock|/custom/containerd/containerd.sock" "$f"; then
    echo "  - update $f: socket path -> /run/containerd/containerd.sock"
    sed_inplace "s|/var/run/cri-dockerd.sock|/run/containerd/containerd.sock|g" "$f"
    sed_inplace "s|/custom/containerd/containerd.sock|/run/containerd/containerd.sock|g" "$f"
  fi
  if grep -q "docker-sock-volume" "$f"; then
    sed_inplace "s|docker-sock-volume|containerd-sock-volume|g" "$f"
  fi
done

echo "清理旧资源..."
kubectl delete deployment metadata-db --ignore-not-found || true
kubectl delete service metadata-db --ignore-not-found || true
kubectl delete deployment internal-proxy-deployment --ignore-not-found || true
kubectl delete service internal-proxy-api-service --ignore-not-found || true

echo "卸载遗留 Helm..."
if helm list -n default 2>/dev/null | awk 'NR>1 {print $1}' | grep -q "^metadata-db$" >/dev/null 2>&1; then
  helm uninstall metadata-db --namespace default || true
fi

echo "部署 Metadata DB..."
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
    --wait --atomic || true
fi

echo "部署 Internal Proxy..."
kubectl apply -f scenarios/internal-proxy/deployment.yaml || true

echo "部署其他靶场..."
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
  "scenarios/kyverno-namespace-exec-block/deployment.yaml"
do
  if [ -f "$manifest" ]; then
    echo "  - kubectl apply $manifest"
    kubectl apply -f "$manifest" || true
  fi
done

echo "部署安全监控和策略工具..."
# Falco 跳过（在 Kind 环境中因为内核驱动限制无法运行）
echo "  - skip sesource/falco.yaml (不支持 Kind 环境 - 需要内核驱动)"

echo "  - kubectl apply sesource/kyverno.yaml"
kubectl apply -f sesource/kyverno.yaml || true

echo "  - kubectl apply sesource/tetragon.yaml"
kubectl apply -f sesource/tetragon.yaml || true

echo "等待 Pod 就绪..."
kubectl wait --for=condition=Ready pod --all --all-namespaces --timeout=300s || true

echo ""
echo "=========================================="
echo "✅ 环境部署完成"
echo "=========================================="
kubectl get pods -A
echo ""

# 显示欢迎信息
show_welcome_banner() {
  clear
  echo "======================================================"
  echo "      摸鱼信安 + 灵镜联合发布 - K8s 安全实验环境 (V3.0)"
  echo "      欢迎关注：微信公众号：摸鱼信安 + Sec铁匠铺"
  echo "======================================================"
  echo ""
  echo "kubectl 集群状态："
  kubectl get nodes
  echo ""
  echo "可用靶场服务（通过 NodePort 访问）："
  echo "  - Build Code: http://localhost:1230 (NodePort: 30001)"
  echo "  - Health Check: http://localhost:1231 (NodePort: 30002)"
  echo "  - Internal Proxy: http://localhost:1232 (NodePort: 30003)"
  echo "  - System Monitor: http://localhost:1233 (NodePort: 30004)"
  echo "  - Kubernetes Goat Home: http://localhost:1234 (NodePort: 30000)"
  echo "  - Poor Registry: http://localhost:1235 (NodePort: 30005)"
  echo "  - Hunger Check: http://localhost:1236 (NodePort: 30006)"
  echo "  - Metadata DB: http://localhost:1237 (NodePort: 30007)"
  echo ""
  echo "常用命令："
  echo "  kubectl get pods -A                    # 查看所有 Pod 状态"
  echo "  kubectl get svc -A                     # 查看所有服务"
  echo "  kubectl logs -f <pod-name>              # 查看 Pod 日志"
  echo "  kubectl exec -it <pod-name> bash       # 进入 Pod 容器"
  echo ""
  echo "注意："
  echo "  - Falco 在 Kind 环境中可能无法正常运行（需要特殊内核驱动支持）"
  echo "  - Kyverno 和 Tetragon 已部署用于安全策略管理"
  echo ""
}

# 显示欢迎信息
show_welcome_banner

# 创建欢迎信息脚本
cat > /usr/local/bin/show-welcome <<'WELCOME'
#!/bin/bash
clear
echo "======================================================"
echo "      摸鱼信安 + 灵镜联合发布 - K8s 安全实验环境 (V3.0)"
echo "      欢迎关注：微信公众号：摸鱼信安 + Sec铁匠铺"
echo "======================================================"
echo ""
echo "kubectl 集群状态："
kubectl get nodes 2>/dev/null || true
echo ""
echo "可用靶场服务（通过 NodePort 访问）："
echo "  - Build Code: http://localhost:1230 (NodePort: 30001)"
echo "  - Health Check: http://localhost:1231 (NodePort: 30002)"
echo "  - Internal Proxy: http://localhost:1232 (NodePort: 30003)"
echo "  - System Monitor: http://localhost:1233 (NodePort: 30004)"
echo "  - Kubernetes Goat Home: http://localhost:1234 (NodePort: 30000)"
echo "  - Poor Registry: http://localhost:1235 (NodePort: 30005)"
echo "  - Hunger Check: http://localhost:1236 (NodePort: 30006)"
echo "  - Metadata DB: http://localhost:1237 (NodePort: 30007)"
echo ""
echo "常用命令："
echo "  kubectl get pods -A                    # 查看所有 Pod 状态"
echo "  kubectl get svc -A                     # 查看所有服务"
echo "  kubectl logs -f <pod-name>              # 查看 Pod 日志"
echo "  kubectl exec -it <pod-name> bash       # 进入 Pod 容器"
echo ""
echo "进入 bash 后看不到欢迎信息？使用："
echo "  /usr/local/bin/show-welcome            # 手动显示欢迎信息"
echo "  docker exec -it <容器ID> /bin/bash -l  # 以登录 shell 进入（显示欢迎）"
echo ""
echo "注意："
echo "  - Falco 在 Kind 环境中可能无法正常运行（需要特殊内核驱动支持）"
echo "  - Kyverno 和 Tetragon 已部署用于安全策略管理"
echo ""
WELCOME
chmod +x /usr/local/bin/show-welcome

# 设置 bash 配置文件以支持登录 shell 和非登录 shell 显示欢迎信息
cat > /root/.bashrc <<'BASHRC'
# 欢迎信息（仅显示一次，兼容登录和非登录 shell）
if [ -z "$WELCOME_SHOWN" ] && [ -t 0 ]; then
  /usr/local/bin/show-welcome
  export WELCOME_SHOWN=1
fi
BASHRC

echo "保持容器运行中..."
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
  
  echo "  - Building from directory: $ROOT_DIR"
  echo "  - Build arguments: $BUILD_ARGS"
  
  # shellcheck disable=SC2086
  docker build --no-cache $BUILD_ARGS -t "$IMAGE_TAG" -f "$ROOT_DIR/Dockerfile" "$ROOT_DIR"
  
  if [ $? -ne 0 ]; then
    echo "ERROR: Docker build failed" >&2
    exit 1
  fi

  echo ""
  echo "=========================================="
  echo "✅ 镜像构建成功!"
  echo "=========================================="
  echo ""
  
  # 根据 MODE 决定是否启动容器
  if [ "$MODE" = "build" ]; then
    echo "模式: build - 仅构建镜像，不启动容器"
    echo ""
    echo "后续使用以下命令运行容器:"
    echo "  bash scripts/run-container.sh start"
    echo "或"
    echo "  bash scripts/deploy-kind.sh run"
    exit 0
  elif [ "$MODE" = "all" ]; then
    echo "模式: all - 即将启动容器..."
    echo ""
    
    # Run container
    # 检查容器是否存在（运行中或已停止）
    if docker ps -a --format '{{.Names}}' | grep -q '^kind-k8s-goat$'; then
      echo "容器 kind-k8s-goat 已存在，删除旧容器..."
      docker rm -f kind-k8s-goat || true
      # 等待容器完全删除
      sleep 2
    fi
    
    echo "Running container kind-k8s-goat..."
    if docker run --privileged -d --name kind-k8s-goat \
      --memory="4g" --cpus="4" \
      -p 1230:1230 -p 1231:1231 -p 1232:1232 -p 1233:1233 \
      -p 1234:1234 -p 1235:1235 -p 1236:1236 -p 1237:1237 \
      "$IMAGE_TAG"; then
      
      # 等待容器启动
      sleep 2
      
      echo "Tailing logs from kind-k8s-goat..."
      docker logs -f kind-k8s-goat
      exit 0
    else
      echo "ERROR: Failed to run container" >&2
      exit 1
    fi
  fi
}

if [ $NEED_DIND -eq 1 ]; then
  bootstrap_dind
fi

# ============ 后续部署代码============

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

  echo "  - 删除不需要的 Falco 镜像..."
  docker rmi falcosecurity/falco:0.42.1 2>/dev/null || true
  docker rmi falcosecurity/falco-driver-loader:0.42.1 2>/dev/null || true
  docker rmi falcosecurity/falcoctl:0.11.4 2>/dev/null || true

  echo "  - distributing images to kind nodes (仅加载到 control-plane，worker 自动拉取)"
  # 优化：只加载关键镜像到节点，减少磁盘占用
  # 关键镜像列表（必须在节点上可用的）
  CRITICAL_IMAGES=(
    "madhuakula/k8s-goat-health-check:latest"
    "madhuakula/k8s-goat-metadata-db:latest"
    "madhuakula/k8s-goat-internal-api:latest"
    "madhuakula/k8s-goat-build-code:latest"
    "madhuakula/k8s-goat-home:latest"
    "madhuakula/k8s-goat-cache-store:latest"
    "madhuakula/k8s-goat-batch-check:latest"
  )
  
  echo "  - loading ${#CRITICAL_IMAGES[@]} critical images to control-plane node only..."
  for img in "${CRITICAL_IMAGES[@]}"; do
    if docker image inspect "$img" > /dev/null 2>&1; then
      echo "    - kind load docker-image: $img"
      kind load docker-image --name "$CLUSTER_NAME" "$img" 2>&1 | grep -v "^Image ID:" || true
    fi
  done
  
  echo "  - 其他镜像将自动从节点本地 containerd 拉取（如果存在）或从网络拉取"
else
  echo "  - $OFFLINE_IMAGES_FILE not found, skipping"
fi

echo "4) 修正 CRI socket 路径"
find ./scenarios -name "*.yaml" -type f -print0 | while IFS= read -r -d '' f; do
  # 简洁有效的注释：兼容处理原版路径和你手动修改过的 /custom/ 路径
  if grep -qE "/var/run/cri-dockerd.sock|/custom/containerd/containerd.sock" "$f"; then
    echo "    - update $f: socket path -> /run/containerd/containerd.sock"
    sed_inplace "s|/var/run/cri-dockerd.sock|/run/containerd/containerd.sock|g" "$f"
    sed_inplace "s|/custom/containerd/containerd.sock|/run/containerd/containerd.sock|g" "$f"
  fi
  if grep -q "docker-sock-volume" "$f"; then
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

echo "9) 部署其他靶场 (官方 10 个靶场 + 扩展)"
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
  "scenarios/kyverno-namespace-exec-block/deployment.yaml"
do
  if [ -f "$manifest" ]; then
    echo "  - kubectl apply $manifest"
    kubectl apply -f "$manifest" || true
  else
    echo "  - skip $manifest (not found)"
  fi
done

echo "10) 部署安全监控和策略工具"
# Falco 跳过（在 Kind 环境中因为内核驱动限制无法运行）
echo "  - skip sesource/falco.yaml (不支持 Kind 环境 - 需要内核驱动)"

for manifest in \
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

# ========== 显示总耗时 ==========
SCRIPT_END_TIME=$(date +%s)
TOTAL_TIME=$((SCRIPT_END_TIME - SCRIPT_START_TIME))
DURATION=$(format_duration $TOTAL_TIME)
echo ""
echo "=========================================="
echo "⏱️  总耗时：$DURATION"
echo "=========================================="
