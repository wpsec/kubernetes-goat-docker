构建环境：
宿主机：Linux moyusec 5.14.0-570.17.1.el9_6.x86_64 #1 SMP PREEMPT_DYNAMIC Fri May 23 22:47:01 UTC 2025 x86_64 x86_64 x86_64 GNU/Linux；Docker version 29.1.4, build 0e6fee6
Kind：docker:24-dind、kindest/node:v1.27.3
镜像仓库：madhuakula、dockerhub、kindest

打包流程：

四层负载端口映射配置（kind-config.yaml）：

```bash
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
  extraPortMappings:
  - containerPort: 30000  # Goat 首页
    hostPort: 1234
  - containerPort: 30001  # Metadata DB
    hostPort: 1230
  - containerPort: 30002  # Health Check
    hostPort: 1231
  - containerPort: 30003  # Build Code
    hostPort: 1232
  - containerPort: 30006  # Internal Proxy API
    hostPort: 1233
  - containerPort: 30007  # Internal Proxy Info
    hostPort: 1236
  - containerPort: 30005  # Hunger Check
    hostPort: 1235
- role: worker
- role: worker
networking:
  podSubnet: "10.244.0.0/16"
  serviceSubnet: "10.96.0.0/12"

```

```Dockerfile
FROM docker:24-dind

# 1. 换源
RUN sed -i 's/dl-cdn.alpinelinux.org/mirrors.aliyun.com/g' /etc/apk/repositories && \
    apk add --no-cache curl bash openssl git

# 2. 安装 kubectl, KinD, Helm
RUN curl -LO "https://dl.k8s.io/release/v1.28.0/bin/linux/amd64/kubectl" && \
    chmod +x kubectl && mv kubectl /usr/local/bin/ && \
    curl -Lo /usr/local/bin/kind https://kind.sigs.k8s.io/dl/v0.20.0/kind-linux-amd64 && \
    chmod +x /usr/local/bin/kind && \
    curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 && \
    chmod 700 get_helm.sh && ./get_helm.sh && rm get_helm.sh

# 3. 离线资源
RUN git clone https://github.com/wpsec/kubernetes-goat-docker.git /opt/kubernetes-goat
# 拷贝本地离线镜像包和配置文件
COPY kind_node_v1.27.3.tar.gz /opt/kind_node_v1.27.3.tar.gz
COPY k8s_goat_images_offline.tar.gz /opt/k8s_goat_images_offline.tar.gz
COPY kind-config.yaml /etc/kind-config.yaml

# 4. 自动检查
RUN echo 'echo -e "\e[1;36m====================================================\e[0m"' >> /root/.bashrc && \
    echo 'echo -e "\e[1;36m      欢迎使用 K8s 安全实验环境 (V3.0)              \e[0m"' >> /root/.bashrc && \
    echo 'echo -e "\e[1;33m      摸鱼信安 + 灵镜联合发布  欢迎关注：微信公众号：摸鱼信安 + Sec铁匠铺  \e[0m"' >> /root/.bashrc && \
    echo 'echo -e "\e[1;36m====================================================\e[0m"' >> /root/.bashrc && \
    echo 'kubectl get nodes' >> /root/.bashrc

# 5. 入口脚本
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/bin/bash", "/entrypoint.sh"]
```

```sh
#!/bin/bash
set -e

# 记录起始时间
GLOBAL_START=$(date +%s)

echo "===================================================="
echo "      摸鱼信安 + 灵镜联合发布 - K8s 安全实验环境 (V3.0)   "
echo "      欢迎关注：微信公众号：摸鱼信安 + Sec铁匠铺          "
echo "===================================================="

# 1. 启动内部 Docker
echo "正在启动内部 Docker 守护进程..."
dockerd-entrypoint.sh > /var/log/dockerd.log 2>&1 &
until docker info >/dev/null 2>&1; do sleep 2; done

# 2. 载入 Kind 节点镜像
if [ -f "/opt/kind_node_v1.27.3.tar.gz" ]; then
    echo "加载 KinD 节点镜像..."
    zcat /opt/kind_node_v1.27.3.tar.gz | docker load
fi

# 3. 创建集群
if ! kind get clusters | grep -q "kind"; then
    echo "创建 K8s 集群..."
    kind create cluster --config /etc/kind-config.yaml --image kindest/node:v1.27.3 --wait 5m
fi

# 4. 加载靶场镜像
if [ -f "/opt/k8s_goat_images_offline.tar.gz" ]; then
    echo "加载并分发靶场镜像..."
    zcat /opt/k8s_goat_images_offline.tar.gz | docker load
    for img in $(docker images --format "{{.Repository}}:{{.Tag}}" | grep "k8s-goat"); do
        kind load docker-image "$img"
    done
fi

# 5. 修正 YAML 兼容性
echo "修复 YAML 中 CRI socket 路径..."
cd /opt/kubernetes-goat/
find ./scenarios -name "*.yaml" -type f -exec sed -i 's|/var/run/cri-dockerd.sock|/run/containerd/containerd.sock|g' {} +
find ./scenarios -name "*.yaml" -type f -exec sed -i 's|docker-sock-volume|containerd-sock-volume|g' {} +

# 6. 清理残留资源
echo "清理旧的 Metadata DB 和 Internal Proxy..."
kubectl delete deployment metadata-db --ignore-not-found
kubectl delete service metadata-db --ignore-not-found
kubectl delete deployment internal-proxy-deployment --ignore-not-found
kubectl delete service internal-proxy-api-service --ignore-not-found

# 7. 部署 Metadata DB（全离线，指定 NodePort）
echo "部署 Metadata DB..."
HELM_VALUES="/opt/kubernetes-goat/scenarios/metadata-db/values.yaml"
# 如果之前存在遗留的 Helm release，先卸载以免资源冲突
helm uninstall metadata-db --namespace default || true
helm upgrade --install metadata-db ./scenarios/metadata-db \
  --namespace default \
  -f "$HELM_VALUES" \
  --set service.type=NodePort \
  --set service.nodePort=30001 \
  --wait --atomic

# 8. 部署 Internal Proxy（使用清单直接部署，nodePort 已在清单中配置为 30006/30007）
echo "部署 Internal Proxy..."
kubectl apply -f scenarios/internal-proxy/deployment.yaml

# 9. 其他场景部署
echo "部署其他靶场场景..."
kubectl apply -f scenarios/insecure-rbac/setup.yaml
kubectl apply -f scenarios/batch-check/job.yaml
kubectl apply -f scenarios/build-code/deployment.yaml
kubectl apply -f scenarios/cache-store/deployment.yaml
kubectl apply -f scenarios/health-check/deployment.yaml
kubectl apply -f scenarios/hunger-check/deployment.yaml
kubectl apply -f scenarios/kubernetes-goat-home/deployment.yaml
kubectl apply -f scenarios/poor-registry/deployment.yaml
kubectl apply -f scenarios/system-monitor/deployment.yaml
kubectl apply -f scenarios/hidden-in-layers/deployment.yaml

# 10. 等待 Pod 就绪
echo "等待所有 Pod 就绪..."
kubectl wait --for=condition=Ready pod --all --all-namespaces --timeout=300s

# 11. 计算耗时
GLOBAL_END=$(date +%s)
ELAPSED=$((GLOBAL_END - GLOBAL_START))
MIN=$((ELAPSED / 60))
SEC=$((ELAPSED % 60))

# 12. 打印访问清单
echo "----------------------------------------------------"
echo " ✅ 环境部署完成！"
echo " 🕒 总耗时: ${ELAPSED} 秒 (${MIN} 分 ${SEC} 秒)"
echo " 🔗 访问地址清单:"
echo "    - Goat 首页: http://宿主机IP:1234"
echo "    - Metadata DB: http://宿主机IP:1230"
echo "    - Health Check: http://宿主机IP:1231"
echo "    - Build Code: http://宿主机IP:1232"
echo "    - Internal Proxy API: http://宿主机IP:1233"
echo "    - Hunger Check: http://宿主机IP:1235"
echo "----------------------------------------------------"

# 13. 容器保持运行
tail -f /dev/null
```

```bash
docker build --no-cache \
  --build-arg http_proxy=http://192.168.246.76:7897 \
  --build-arg https_proxy=http://192.168.246.76:7897 \
  -t kind-k8s-goat-moyusec-lingjing:v3.0 .
```

```bash
docker run --privileged -d \
  --name kind-k8s-goat \
  --memory="4g" \
  --cpus="4" \
  -p 1234:1234 \
  -p 1230:1230 \
  -p 1231:1231 \
  -p 1232:1232 \
  -p 1233:1233 \
  -p 1235:1235 \
  -p 1236:1236 \
kind-k8s-goat-moyusec-lingjing:v3.0
```

因为集群环境些许庞大，导入镜像+部署靶场需要一定时间，建议通过查看日志确认环境是否就绪；本地 x86 的 winvm 环境 4c4g 的机器启动时间在 10 分钟；出现

```bash
[root@moyusec DKinD]# docker logs  -f kind-k8s-goat
```
