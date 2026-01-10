# 弃用

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
  - containerPort: 30000  # Kubernetes Goat Home (首页)
    hostPort: 1234
  - containerPort: 30001  # Metadata DB
    hostPort: 1230
  - containerPort: 30002  # Health Check
    hostPort: 1231
  - containerPort: 30003  # Build Code
    hostPort: 1232
  - containerPort: 30004  # Poor Registry
    hostPort: 1238
  - containerPort: 30005  # Hunger Check
    hostPort: 1235
  - containerPort: 30006  # Internal Proxy API
    hostPort: 1233
  - containerPort: 30007  # Internal Proxy Info
    hostPort: 1236
  - containerPort: 30008  # System Monitor
    hostPort: 1237
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
======================================================
      摸鱼信安 + 灵镜联合发布 - K8s 安全实验环境 (V3.0)
      欢迎关注：微信公众号：摸鱼信安 + Sec铁匠铺
======================================================
正在启动内部 Docker 守护进程...
加载 KinD 节点镜像...
Loaded image: kindest/node:v1.27.3
No kind clusters found.
创建 K8s 集群...
No kind clusters found.
Creating cluster "kind" ...
 • Ensuring node image (kindest/node:v1.27.3) 🖼  ...
 ✓ Ensuring node image (kindest/node:v1.27.3) 🖼
 • Preparing nodes 📦 📦 📦   ...
 ✓ Preparing nodes 📦 📦 📦
 • Writing configuration 📜  ...
 ✓ Writing configuration 📜
 • Starting control-plane 🕹️  ...
 ✓ Starting control-plane 🕹️
 • Installing CNI 🔌  ...
 ✓ Installing CNI 🔌
 • Installing StorageClass 💾  ...
 ✓ Installing StorageClass 💾
 • Joining worker nodes 🚜  ...
 ✓ Joining worker nodes 🚜
 • Waiting ≤ 5m0s for control-plane = Ready ⏳  ...
 ✓ Waiting ≤ 5m0s for control-plane = Ready ⏳
 • Ready after 1s 💚
Set kubectl context to "kind-kind"
You can now use your cluster with:

kubectl cluster-info --context kind-kind

Have a question, bug, or feature request? Let us know! https://kind.sigs.k8s.io/#community 🙂
加载并分发靶场镜像...
Loaded image: madhuakula/k8s-goat-health-check:latest
Loaded image: madhuakula/k8s-goat-system-monitor:latest
Loaded image: madhuakula/k8s-goat-home:latest
Loaded image: madhuakula/k8s-goat-hidden-in-layers:latest
Loaded image: madhuakula/k8s-goat-metadata-db:latest
Loaded image: madhuakula/k8s-goat-info-app:latest
Loaded image: madhuakula/k8s-goat-cache-store:latest
Loaded image: madhuakula/k8s-goat-batch-check:latest
Loaded image: madhuakula/k8s-goat-build-code:latest
Loaded image: madhuakula/k8s-goat-poor-registry:latest
Loaded image: madhuakula/k8s-goat-internal-api:latest
Loaded image: madhuakula/k8s-goat-hunger-check:latest
Image: "madhuakula/k8s-goat-internal-api:latest" with ID "sha256:dcbb865da54d7b92e77cfd1afe2824580416c95f3a825f9634090201e48a5634" not yet present on node "kind-control-plane", loading...
Image: "madhuakula/k8s-goat-internal-api:latest" with ID "sha256:dcbb865da54d7b92e77cfd1afe2824580416c95f3a825f9634090201e48a5634" not yet present on node "kind-worker", loading...
Image: "madhuakula/k8s-goat-internal-api:latest" with ID "sha256:dcbb865da54d7b92e77cfd1afe2824580416c95f3a825f9634090201e48a5634" not yet present on node "kind-worker2", loading...
Image: "madhuakula/k8s-goat-hunger-check:latest" with ID "sha256:cc0a3c5c2b61cbc145683f627e300176a3866f4f54f91fc205eedcef16038632" not yet present on node "kind-control-plane", loading...
Image: "madhuakula/k8s-goat-hunger-check:latest" with ID "sha256:cc0a3c5c2b61cbc145683f627e300176a3866f4f54f91fc205eedcef16038632" not yet present on node "kind-worker", loading...
Image: "madhuakula/k8s-goat-hunger-check:latest" with ID "sha256:cc0a3c5c2b61cbc145683f627e300176a3866f4f54f91fc205eedcef16038632" not yet present on node "kind-worker2", loading...
Image: "madhuakula/k8s-goat-health-check:latest" with ID "sha256:14e2480c8e9fe4bdfa6a7ec4cce3676dbce89012f5a6f5d7fe2a62d51384abb3" not yet present on node "kind-control-plane", loading...
Image: "madhuakula/k8s-goat-health-check:latest" with ID "sha256:14e2480c8e9fe4bdfa6a7ec4cce3676dbce89012f5a6f5d7fe2a62d51384abb3" not yet present on node "kind-worker", loading...
Image: "madhuakula/k8s-goat-health-check:latest" with ID "sha256:14e2480c8e9fe4bdfa6a7ec4cce3676dbce89012f5a6f5d7fe2a62d51384abb3" not yet present on node "kind-worker2", loading...
Image: "madhuakula/k8s-goat-system-monitor:latest" with ID "sha256:7c4493a61a7cfc74da9f1110a68d73e5cac518b99e98af8739670574c66a79af" not yet present on node "kind-control-plane", loading...
Image: "madhuakula/k8s-goat-system-monitor:latest" with ID "sha256:7c4493a61a7cfc74da9f1110a68d73e5cac518b99e98af8739670574c66a79af" not yet present on node "kind-worker", loading...
Image: "madhuakula/k8s-goat-system-monitor:latest" with ID "sha256:7c4493a61a7cfc74da9f1110a68d73e5cac518b99e98af8739670574c66a79af" not yet present on node "kind-worker2", loading...
Image: "madhuakula/k8s-goat-home:latest" with ID "sha256:5e3978d00bbb24b32696b08b1022919f35c7ade4864286a7407ff5166052139e" not yet present on node "kind-control-plane", loading...
Image: "madhuakula/k8s-goat-home:latest" with ID "sha256:5e3978d00bbb24b32696b08b1022919f35c7ade4864286a7407ff5166052139e" not yet present on node "kind-worker", loading...
Image: "madhuakula/k8s-goat-home:latest" with ID "sha256:5e3978d00bbb24b32696b08b1022919f35c7ade4864286a7407ff5166052139e" not yet present on node "kind-worker2", loading...
Image: "madhuakula/k8s-goat-info-app:latest" with ID "sha256:57e24cd7eb27b420e066eb86d8092f43bd1d075b899af2865fca74c658b25f3a" not yet present on node "kind-control-plane", loading...
Image: "madhuakula/k8s-goat-info-app:latest" with ID "sha256:57e24cd7eb27b420e066eb86d8092f43bd1d075b899af2865fca74c658b25f3a" not yet present on node "kind-worker", loading...
Image: "madhuakula/k8s-goat-info-app:latest" with ID "sha256:57e24cd7eb27b420e066eb86d8092f43bd1d075b899af2865fca74c658b25f3a" not yet present on node "kind-worker2", loading...
Image: "madhuakula/k8s-goat-hidden-in-layers:latest" with ID "sha256:285cbdc185fff63b1df260afade65d85fa3be199bba280f8936fdb303f88b14f" not yet present on node "kind-control-plane", loading...
Image: "madhuakula/k8s-goat-hidden-in-layers:latest" with ID "sha256:285cbdc185fff63b1df260afade65d85fa3be199bba280f8936fdb303f88b14f" not yet present on node "kind-worker", loading...
Image: "madhuakula/k8s-goat-hidden-in-layers:latest" with ID "sha256:285cbdc185fff63b1df260afade65d85fa3be199bba280f8936fdb303f88b14f" not yet present on node "kind-worker2", loading...
Image: "madhuakula/k8s-goat-cache-store:latest" with ID "sha256:aa2bf2205b2c25eb78a7b3a5547d0402d0c4111aaef89da54b6785aaa6a6e28d" not yet present on node "kind-control-plane", loading...
Image: "madhuakula/k8s-goat-cache-store:latest" with ID "sha256:aa2bf2205b2c25eb78a7b3a5547d0402d0c4111aaef89da54b6785aaa6a6e28d" not yet present on node "kind-worker", loading...
Image: "madhuakula/k8s-goat-cache-store:latest" with ID "sha256:aa2bf2205b2c25eb78a7b3a5547d0402d0c4111aaef89da54b6785aaa6a6e28d" not yet present on node "kind-worker2", loading...
Image: "madhuakula/k8s-goat-batch-check:latest" with ID "sha256:a79437e72bc1b7f624b294bbe76a41cc570c0d9e2d997b43531821ec19aab5d6" not yet present on node "kind-control-plane", loading...
Image: "madhuakula/k8s-goat-batch-check:latest" with ID "sha256:a79437e72bc1b7f624b294bbe76a41cc570c0d9e2d997b43531821ec19aab5d6" not yet present on node "kind-worker", loading...
Image: "madhuakula/k8s-goat-batch-check:latest" with ID "sha256:a79437e72bc1b7f624b294bbe76a41cc570c0d9e2d997b43531821ec19aab5d6" not yet present on node "kind-worker2", loading...
Image: "madhuakula/k8s-goat-build-code:latest" with ID "sha256:b8973f272a0a12c97ef17d396075104e61b7a2d53c104f7e77344f53d009ec8e" not yet present on node "kind-control-plane", loading...
Image: "madhuakula/k8s-goat-build-code:latest" with ID "sha256:b8973f272a0a12c97ef17d396075104e61b7a2d53c104f7e77344f53d009ec8e" not yet present on node "kind-worker", loading...
Image: "madhuakula/k8s-goat-build-code:latest" with ID "sha256:b8973f272a0a12c97ef17d396075104e61b7a2d53c104f7e77344f53d009ec8e" not yet present on node "kind-worker2", loading...
Image: "madhuakula/k8s-goat-poor-registry:latest" with ID "sha256:003fcd9d9071a5b0d1f8d1336430c1ee01d4dc8b0d575e3798d48a803274126b" not yet present on node "kind-control-plane", loading...
Image: "madhuakula/k8s-goat-poor-registry:latest" with ID "sha256:003fcd9d9071a5b0d1f8d1336430c1ee01d4dc8b0d575e3798d48a803274126b" not yet present on node "kind-worker", loading...
Image: "madhuakula/k8s-goat-poor-registry:latest" with ID "sha256:003fcd9d9071a5b0d1f8d1336430c1ee01d4dc8b0d575e3798d48a803274126b" not yet present on node "kind-worker2", loading...
Image: "madhuakula/k8s-goat-metadata-db:latest" with ID "sha256:0ff4eace8cd5bd0459e7fc568e0b3b0e0885690a85feccbb18b75b462a705253" not yet present on node "kind-control-plane", loading...
Image: "madhuakula/k8s-goat-metadata-db:latest" with ID "sha256:0ff4eace8cd5bd0459e7fc568e0b3b0e0885690a85feccbb18b75b462a705253" not yet present on node "kind-worker", loading...
Image: "madhuakula/k8s-goat-metadata-db:latest" with ID "sha256:0ff4eace8cd5bd0459e7fc568e0b3b0e0885690a85feccbb18b75b462a705253" not yet present on node "kind-worker2", loading...
修复 YAML 中 CRI socket 路径...
清理旧的 Metadata DB 和 Internal Proxy...
部署 Metadata DB...
部署 Internal Proxy...
部署其他靶场...
等待 Pod 就绪...
== K8s-Goat 离线部署脚本 ==
ROOT_DIR=/opt/kubernetes-goat
1) 加载 Kind 节点镜像
  - kind_node_v1.27.3.tar.gz not found, skipping
2) 创建 Kind 集群
  - kind cluster 'kind' already exists
3) 加载离线镜像
  - k8s_goat_images_offline.tar.gz not found, skipping
4) 修正 CRI socket 路径
    - update ./scenarios/docker-bench-security/deployment.yaml: /var/run/cri-dockerd.sock -> /run/containerd/containerd.sock
    - update ./scenarios/docker-bench-security/deployment.yaml: docker-sock-volume -> containerd-sock-volume
    - update ./scenarios/health-check/deployment.yaml: /var/run/cri-dockerd.sock -> /run/containerd/containerd.sock
    - update ./scenarios/health-check/deployment.yaml: docker-sock-volume -> containerd-sock-volume
5) 清理旧资源
6) 卸载遗留 Helm
7) 部署 Metadata DB
Release "metadata-db" does not exist. Installing it now.
NAME: metadata-db
LAST DEPLOYED: Sat Jan 10 07:58:51 2026
NAMESPACE: default
STATUS: deployed
REVISION: 1
NOTES:
1. Get the application URL by running these commands:
  export NODE_PORT=$(kubectl get --namespace default -o jsonpath="{.spec.ports[0].nodePort}" services metadata-db)
  export NODE_IP=$(kubectl get nodes --namespace default -o jsonpath="{.items[0].status.addresses[0].address}")
  echo http://$NODE_IP:$NODE_PORT
8) 部署 Internal Proxy
deployment.apps/internal-proxy-deployment created
service/internal-proxy-api-service created
9) 部署其他靶场
  - kubectl apply scenarios/insecure-rbac/setup.yaml
serviceaccount/superadmin created
clusterrolebinding.rbac.authorization.k8s.io/superadmin created
  - kubectl apply scenarios/batch-check/job.yaml
job.batch/batch-check-job created
  - kubectl apply scenarios/build-code/deployment.yaml
deployment.apps/build-code-deployment created
service/build-code-service created
  - kubectl apply scenarios/cache-store/deployment.yaml
namespace/secure-middleware created
service/cache-store-service created
deployment.apps/cache-store-deployment created
  - kubectl apply scenarios/health-check/deployment.yaml
deployment.apps/health-check-deployment created
service/health-check-service created
  - kubectl apply scenarios/hunger-check/deployment.yaml
namespace/big-monolith created
role.rbac.authorization.k8s.io/secret-reader created
rolebinding.rbac.authorization.k8s.io/secret-reader-binding created
serviceaccount/big-monolith-sa created
secret/vaultapikey created
secret/webhookapikey created
deployment.apps/hunger-check-deployment created
service/hunger-check-service created
  - kubectl apply scenarios/kubernetes-goat-home/deployment.yaml
deployment.apps/kubernetes-goat-home-deployment created
service/kubernetes-goat-home-service created
  - kubectl apply scenarios/poor-registry/deployment.yaml
deployment.apps/poor-registry-deployment created
service/poor-registry-service created
  - kubectl apply scenarios/system-monitor/deployment.yaml
secret/goatvault created
deployment.apps/system-monitor-deployment created
service/system-monitor-service created
  - kubectl apply scenarios/hidden-in-layers/deployment.yaml
job.batch/hidden-in-layers created
  - kubectl apply scenarios/docker-bench-security/deployment.yaml
daemonset.apps/docker-bench-security created
  - kubectl apply scenarios/kube-bench-security/node-job.yaml
job.batch/kube-bench-node created
  - kubectl apply scenarios/kube-bench-security/master-job.yaml
job.batch/kube-bench-master created
10) 等待 Pod 就绪
pod/hunger-check-deployment-58f45d489c-r5jm8 condition met
pod/batch-check-job-tsq7k condition met
pod/build-code-deployment-6d699c7bf-8fdtn condition met
timed out waiting for the condition on pods/docker-bench-security-d5mmm
timed out waiting for the condition on pods/docker-bench-security-hrrz2
timed out waiting for the condition on pods/health-check-deployment-69d9775c9-qj9wv
timed out waiting for the condition on pods/hidden-in-layers-pbrfn
timed out waiting for the condition on pods/internal-proxy-deployment-5f798497bf-5qj2c
timed out waiting for the condition on pods/kube-bench-master-hnj9k
timed out waiting for the condition on pods/kube-bench-node-hhvml
timed out waiting for the condition on pods/kubernetes-goat-home-deployment-54786cdcc-9dlgh
timed out waiting for the condition on pods/metadata-db-78c9877b47-ks7cc
timed out waiting for the condition on pods/poor-registry-deployment-54c57f59b9-nhtlw
timed out waiting for the condition on pods/system-monitor-deployment-6d9b4fcdc5-6dshv
timed out waiting for the condition on pods/coredns-5d78c9869d-4h5wt
timed out waiting for the condition on pods/coredns-5d78c9869d-l9dcx
timed out waiting for the condition on pods/etcd-kind-control-plane
timed out waiting for the condition on pods/kindnet-4d2xk
timed out waiting for the condition on pods/kindnet-gzfsr
timed out waiting for the condition on pods/kindnet-lth7d
timed out waiting for the condition on pods/kube-apiserver-kind-control-plane
timed out waiting for the condition on pods/kube-controller-manager-kind-control-plane
timed out waiting for the condition on pods/kube-proxy-lkxmf
timed out waiting for the condition on pods/kube-proxy-qnhn2
timed out waiting for the condition on pods/kube-proxy-vgx5k
timed out waiting for the condition on pods/kube-scheduler-kind-control-plane
timed out waiting for the condition on pods/local-path-provisioner-6bc4bddd6b-rhvcq
timed out waiting for the condition on pods/cache-store-deployment-6df68cdf5b-65mnp

==========================================
✅ 环境部署完成
==========================================
NAMESPACE            NAME                                              READY   STATUS             RESTARTS      AGE
big-monolith         hunger-check-deployment-58f45d489c-r5jm8          1/1     Running            0             5m7s
default              batch-check-job-tsq7k                             1/1     Running            0             5m11s
default              build-code-deployment-6d699c7bf-8fdtn             1/1     Running            0             5m10s
default              docker-bench-security-d5mmm                       0/1     ErrImagePull       0             5m2s
default              docker-bench-security-hrrz2                       0/1     ImagePullBackOff   0             5m2s
default              health-check-deployment-69d9775c9-qj9wv           1/1     Running            0             5m8s
default              hidden-in-layers-pbrfn                            1/1     Running            0             5m3s
default              internal-proxy-deployment-5f798497bf-5qj2c        2/2     Running            0             5m12s
default              kube-bench-master-hnj9k                           0/1     ErrImagePull       0             5m1s
default              kube-bench-node-hhvml                             0/1     ImagePullBackOff   0             5m1s
default              kubernetes-goat-home-deployment-54786cdcc-9dlgh   1/1     Running            0             5m6s
default              metadata-db-78c9877b47-ks7cc                      1/1     Running            0             5m35s
default              poor-registry-deployment-54c57f59b9-nhtlw         1/1     Running            0             5m5s
default              system-monitor-deployment-6d9b4fcdc5-6dshv        1/1     Running            0             5m4s
kube-system          coredns-5d78c9869d-4h5wt                          1/1     Running            0             14m
kube-system          coredns-5d78c9869d-l9dcx                          1/1     Running            0             14m
kube-system          etcd-kind-control-plane                           1/1     Running            0             14m
kube-system          kindnet-4d2xk                                     1/1     Running            0             14m
kube-system          kindnet-gzfsr                                     1/1     Running            1 (14m ago)   14m
kube-system          kindnet-lth7d                                     1/1     Running            0             14m
kube-system          kube-apiserver-kind-control-plane                 1/1     Running            0             14m
kube-system          kube-controller-manager-kind-control-plane        1/1     Running            0             14m
kube-system          kube-proxy-lkxmf                                  1/1     Running            0             14m
kube-system          kube-proxy-qnhn2                                  1/1     Running            0             14m
kube-system          kube-proxy-vgx5k                                  1/1     Running            0             14m
kube-system          kube-scheduler-kind-control-plane                 1/1     Running            0             14m
local-path-storage   local-path-provisioner-6bc4bddd6b-rhvcq           1/1     Running            0             14m
secure-middleware    cache-store-deployment-6df68cdf5b-65mnp           1/1     Running            0             5m9s
NAMESPACE           NAME                           TYPE        CLUSTER-IP       EXTERNAL-IP   PORT(S)                         AGE
big-monolith        hunger-check-service           NodePort    10.102.54.116    <none>        8080:30005/TCP                  5m7s
default             build-code-service             NodePort    10.111.244.3     <none>        3000:30003/TCP                  5m10s
default             health-check-service           NodePort    10.96.101.223    <none>        80:30002/TCP                    5m8s
default             internal-proxy-api-service     NodePort    10.110.10.210    <none>        3000:30006/TCP,5000:30007/TCP   5m12s
default             kubernetes                     ClusterIP   10.96.0.1        <none>        443/TCP                         14m
default             kubernetes-goat-home-service   NodePort    10.106.226.136   <none>        80:30000/TCP                    5m6s
default             metadata-db                    NodePort    10.100.223.2     <none>        80:30001/TCP                    5m35s
default             poor-registry-service          NodePort    10.104.171.60    <none>        5000:30004/TCP                  5m5s
default             system-monitor-service         NodePort    10.109.58.123    <none>        8080:30008/TCP                  5m4s
kube-system         kube-dns                       ClusterIP   10.96.0.10       <none>        53/UDP,53/TCP,9153/TCP          14m
secure-middleware   cache-store-service            ClusterIP   10.99.78.255     <none>        6379/TCP                        5m9s

访问地址：
  - Goat 首页: http://宿主机IP:1234
  - Metadata DB: http://宿主机IP:1230
  - Health Check: http://宿主机IP:1231
  - Build Code: http://宿主机IP:1232
  - Poor Registry: http://宿主机IP:1238
  - Hunger Check: http://宿主机IP:1235
  - Internal Proxy API: http://宿主机IP:1233
  - Internal Proxy Info: http://宿主机IP:1236
  - System Monitor: http://宿主机IP:1237
  - Internal Proxy API: http://宿主机IP:1233
  - Hunger Check: http://宿主机IP:1235
```

打包流程：

四层负载端口映射配置（kind-config.yaml）：

```bash
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
  extraPortMappings:
  # 首页 (Home)
  - containerPort: 30000
    hostPort: 1234
  # 各类场景端口映射 (1230-1236)
  - containerPort: 30001
    hostPort: 1230
  - containerPort: 30002
    hostPort: 1231
  - containerPort: 30003
    hostPort: 1232
  - containerPort: 30004
    hostPort: 1233
  - containerPort: 30005
    hostPort: 1235
  - containerPort: 30006
    hostPort: 1236
- role: worker
- role: worker

# 2. 离线优化配置
networking:
  # 如果你的宿主机网段冲突，可以在这里改 K8s 内部子网
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

# 简体中文注释：记录起始时间
GLOBAL_START=$(date +%s)

echo "===================================================="
echo "      摸鱼信安 + 灵镜联合发布 - K8s 安全实验环境 (V3.0)   "
echo "      欢迎关注：微信公众号：摸鱼信安 + Sec铁匠铺          "
echo "===================================================="

# 1. 启动内部 Docker
echo "正在启动内部 Docker 守护进程..."
dockerd-entrypoint.sh > /var/log/dockerd.log 2>&1 &
until docker info >/dev/null 2>&1; do sleep 2; done

# 2. 载入节点镜像
if [ -f "/opt/kind_node_v1.27.3.tar.gz" ]; then
    echo "正在加载 KinD 节点镜像 (Step 1/3)..."
    zcat /opt/kind_node_v1.27.3.tar.gz | docker load
fi

# 3. 创建集群
if ! kind get clusters | grep -q "kind"; then
    echo "正在创建 K8s 集群 (Step 2/3)..."
    kind create cluster --config /etc/kind-config.yaml --image kindest/node:v1.27.3 --wait 5m
fi

# 4. 同步靶场镜像
if [ -f "/opt/k8s_goat_images_offline.tar.gz" ]; then
    echo "正在加载并分发靶场镜像 (Step 3/3)..."
    zcat /opt/k8s_goat_images_offline.tar.gz | docker load
    # 简体中文注释：仅同步靶场相关的镜像到 KinD 节点
    for img in $(docker images --format "{{.Repository}}:{{.Tag}}" | grep "k8s-goat"); do
        kind load docker-image "$img"
    done
fi

# 5. 修正 YAML 兼容性并部署
echo "正在执行环境兼容性修复..."
cd /opt/kubernetes-goat/
find ./scenarios -name "*.yaml" -type f -exec sed -i 's|/var/run/cri-dockerd.sock|/run/containerd/containerd.sock|g' {} +
find ./scenarios -name "*.yaml" -type f -exec sed -i 's|docker-sock-volume|containerd-sock-volume|g' {} +

echo "正在部署靶场场景..."
helm upgrade --install metadata-db ./scenarios/metadata-db --namespace default
bash ./setup-kubernetes-goat.sh

# 简体中文注释：计算总耗时
GLOBAL_END=$(date +%s)
ELAPSED=$((GLOBAL_END - GLOBAL_START))
MIN=$((ELAPSED / 60))
SEC=$((ELAPSED % 60))

echo "----------------------------------------------------"
echo " ✅ 环境部署就绪！"
echo " 🕒 本次启动总耗时: ${ELAPSED} 秒 (${MIN} 分 ${SEC} 秒)"
echo " 🔗 访问地址: http://宿主机IP:1234"
echo "----------------------------------------------------"

# 保持容器后台运行
tail -f /dev/null
```

```bash
docker build --no-cache \
  --build-arg http_proxy=http://192.168.246.76:7897 \
  --build-arg https_proxy=http://192.168.246.76:7897 \
  -t k8s-lab:moyusec_lingjingv3.0 .
```

```bash
docker run --privileged -d \
  --name k8s-running-env \
  --memory="4g" \
  --cpus="4" \
  -p 1234:1234 \
  -p 1230:1230 \
  -p 1231:1231 \
  -p 1232:1232 \
  -p 1233:1233 \
  -p 1235:1235 \
  -p 1236:1236 \
  k8s-lab:moyusec_lingjingv3.0
```

因为集群环境些许庞大，导入镜像+部署靶场需要一定时间，建议通过查看日志确认环境是否就绪；本地 x86 的 winvm 环境 4c4g 的机器启动时间在 10 分钟；出现

```bash
====================================================
      摸鱼信安 + 灵镜联合发布 - K8s 安全实验环境 (V3.0)
      欢迎关注：微信公众号：摸鱼信安 + Sec铁匠铺
====================================================
正在启动内部 Docker 守护进程...
正在加载 KinD 节点镜像 (Step 1/3)...
Loaded image: kindest/node:v1.27.3
No kind clusters found.
正在创建 K8s 集群 (Step 2/3)...
Creating cluster "kind" ...
 • Ensuring node image (kindest/node:v1.27.3) 🖼  ...
 ✓ Ensuring node image (kindest/node:v1.27.3) 🖼
 • Preparing nodes 📦 📦 📦   ...
 ✓ Preparing nodes 📦 📦 📦
 • Writing configuration 📜  ...
 ✓ Writing configuration 📜
 • Starting control-plane 🕹️  ...
 ✓ Starting control-plane 🕹️
 • Installing CNI 🔌  ...
 ✓ Installing CNI 🔌
 • Installing StorageClass 💾  ...
 ✓ Installing StorageClass 💾
 • Joining worker nodes 🚜  ...
 ✓ Joining worker nodes 🚜
 • Waiting ≤ 5m0s for control-plane = Ready ⏳  ...
 ✓ Waiting ≤ 5m0s for control-plane = Ready ⏳
 • Ready after 1s 💚
Set kubectl context to "kind-kind"
You can now use your cluster with:

kubectl cluster-info --context kind-kind

Not sure what to do next? 😅  Check out https://kind.sigs.k8s.io/docs/user/quick-start/
正在加载并分发靶场镜像 (Step 3/3)...
Loaded image: madhuakula/k8s-goat-health-check:latest
Loaded image: madhuakula/k8s-goat-system-monitor:latest
Loaded image: madhuakula/k8s-goat-home:latest
Loaded image: madhuakula/k8s-goat-hidden-in-layers:latest
Loaded image: madhuakula/k8s-goat-metadata-db:latest
Loaded image: madhuakula/k8s-goat-info-app:latest
Loaded image: madhuakula/k8s-goat-cache-store:latest
Loaded image: madhuakula/k8s-goat-batch-check:latest
Loaded image: madhuakula/k8s-goat-build-code:latest
Loaded image: madhuakula/k8s-goat-poor-registry:latest
Loaded image: madhuakula/k8s-goat-internal-api:latest
Loaded image: madhuakula/k8s-goat-hunger-check:latest
Image: "madhuakula/k8s-goat-internal-api:latest" with ID "sha256:dcbb865da54d7b92e77cfd1afe2824580416c95f3a825f9634090201e48a5634" not yet present on node "kind-worker", loading...
Image: "madhuakula/k8s-goat-internal-api:latest" with ID "sha256:dcbb865da54d7b92e77cfd1afe2824580416c95f3a825f9634090201e48a5634" not yet present on node "kind-control-plane", loading...
Image: "madhuakula/k8s-goat-internal-api:latest" with ID "sha256:dcbb865da54d7b92e77cfd1afe2824580416c95f3a825f9634090201e48a5634" not yet present on node "kind-worker2", loading...
Image: "madhuakula/k8s-goat-hunger-check:latest" with ID "sha256:cc0a3c5c2b61cbc145683f627e300176a3866f4f54f91fc205eedcef16038632" not yet present on node "kind-worker", loading...
Image: "madhuakula/k8s-goat-hunger-check:latest" with ID "sha256:cc0a3c5c2b61cbc145683f627e300176a3866f4f54f91fc205eedcef16038632" not yet present on node "kind-control-plane", loading...
Image: "madhuakula/k8s-goat-hunger-check:latest" with ID "sha256:cc0a3c5c2b61cbc145683f627e300176a3866f4f54f91fc205eedcef16038632" not yet present on node "kind-worker2", loading...
Image: "madhuakula/k8s-goat-health-check:latest" with ID "sha256:14e2480c8e9fe4bdfa6a7ec4cce3676dbce89012f5a6f5d7fe2a62d51384abb3" not yet present on node "kind-worker", loading...
Image: "madhuakula/k8s-goat-health-check:latest" with ID "sha256:14e2480c8e9fe4bdfa6a7ec4cce3676dbce89012f5a6f5d7fe2a62d51384abb3" not yet present on node "kind-control-plane", loading...
Image: "madhuakula/k8s-goat-health-check:latest" with ID "sha256:14e2480c8e9fe4bdfa6a7ec4cce3676dbce89012f5a6f5d7fe2a62d51384abb3" not yet present on node "kind-worker2", loading...
Image: "madhuakula/k8s-goat-system-monitor:latest" with ID "sha256:7c4493a61a7cfc74da9f1110a68d73e5cac518b99e98af8739670574c66a79af" not yet present on node "kind-worker", loading...
Image: "madhuakula/k8s-goat-system-monitor:latest" with ID "sha256:7c4493a61a7cfc74da9f1110a68d73e5cac518b99e98af8739670574c66a79af" not yet present on node "kind-control-plane", loading...
Image: "madhuakula/k8s-goat-system-monitor:latest" with ID "sha256:7c4493a61a7cfc74da9f1110a68d73e5cac518b99e98af8739670574c66a79af" not yet present on node "kind-worker2", loading...
Image: "madhuakula/k8s-goat-home:latest" with ID "sha256:5e3978d00bbb24b32696b08b1022919f35c7ade4864286a7407ff5166052139e" not yet present on node "kind-worker", loading...
Image: "madhuakula/k8s-goat-home:latest" with ID "sha256:5e3978d00bbb24b32696b08b1022919f35c7ade4864286a7407ff5166052139e" not yet present on node "kind-control-plane", loading...
Image: "madhuakula/k8s-goat-home:latest" with ID "sha256:5e3978d00bbb24b32696b08b1022919f35c7ade4864286a7407ff5166052139e" not yet present on node "kind-worker2", loading...
Image: "madhuakula/k8s-goat-info-app:latest" with ID "sha256:57e24cd7eb27b420e066eb86d8092f43bd1d075b899af2865fca74c658b25f3a" not yet present on node "kind-worker", loading...
Image: "madhuakula/k8s-goat-info-app:latest" with ID "sha256:57e24cd7eb27b420e066eb86d8092f43bd1d075b899af2865fca74c658b25f3a" not yet present on node "kind-control-plane", loading...
Image: "madhuakula/k8s-goat-info-app:latest" with ID "sha256:57e24cd7eb27b420e066eb86d8092f43bd1d075b899af2865fca74c658b25f3a" not yet present on node "kind-worker2", loading...
Image: "madhuakula/k8s-goat-hidden-in-layers:latest" with ID "sha256:285cbdc185fff63b1df260afade65d85fa3be199bba280f8936fdb303f88b14f" not yet present on node "kind-worker", loading...
Image: "madhuakula/k8s-goat-hidden-in-layers:latest" with ID "sha256:285cbdc185fff63b1df260afade65d85fa3be199bba280f8936fdb303f88b14f" not yet present on node "kind-control-plane", loading...
Image: "madhuakula/k8s-goat-hidden-in-layers:latest" with ID "sha256:285cbdc185fff63b1df260afade65d85fa3be199bba280f8936fdb303f88b14f" not yet present on node "kind-worker2", loading...
Image: "madhuakula/k8s-goat-cache-store:latest" with ID "sha256:aa2bf2205b2c25eb78a7b3a5547d0402d0c4111aaef89da54b6785aaa6a6e28d" not yet present on node "kind-worker", loading...
Image: "madhuakula/k8s-goat-cache-store:latest" with ID "sha256:aa2bf2205b2c25eb78a7b3a5547d0402d0c4111aaef89da54b6785aaa6a6e28d" not yet present on node "kind-control-plane", loading...
Image: "madhuakula/k8s-goat-cache-store:latest" with ID "sha256:aa2bf2205b2c25eb78a7b3a5547d0402d0c4111aaef89da54b6785aaa6a6e28d" not yet present on node "kind-worker2", loading...
Image: "madhuakula/k8s-goat-batch-check:latest" with ID "sha256:a79437e72bc1b7f624b294bbe76a41cc570c0d9e2d997b43531821ec19aab5d6" not yet present on node "kind-worker", loading...
Image: "madhuakula/k8s-goat-batch-check:latest" with ID "sha256:a79437e72bc1b7f624b294bbe76a41cc570c0d9e2d997b43531821ec19aab5d6" not yet present on node "kind-control-plane", loading...
Image: "madhuakula/k8s-goat-batch-check:latest" with ID "sha256:a79437e72bc1b7f624b294bbe76a41cc570c0d9e2d997b43531821ec19aab5d6" not yet present on node "kind-worker2", loading...
Image: "madhuakula/k8s-goat-build-code:latest" with ID "sha256:b8973f272a0a12c97ef17d396075104e61b7a2d53c104f7e77344f53d009ec8e" not yet present on node "kind-worker", loading...
Image: "madhuakula/k8s-goat-build-code:latest" with ID "sha256:b8973f272a0a12c97ef17d396075104e61b7a2d53c104f7e77344f53d009ec8e" not yet present on node "kind-control-plane", loading...
Image: "madhuakula/k8s-goat-build-code:latest" with ID "sha256:b8973f272a0a12c97ef17d396075104e61b7a2d53c104f7e77344f53d009ec8e" not yet present on node "kind-worker2", loading...
Image: "madhuakula/k8s-goat-poor-registry:latest" with ID "sha256:003fcd9d9071a5b0d1f8d1336430c1ee01d4dc8b0d575e3798d48a803274126b" not yet present on node "kind-worker", loading...
Image: "madhuakula/k8s-goat-poor-registry:latest" with ID "sha256:003fcd9d9071a5b0d1f8d1336430c1ee01d4dc8b0d575e3798d48a803274126b" not yet present on node "kind-control-plane", loading...
Image: "madhuakula/k8s-goat-poor-registry:latest" with ID "sha256:003fcd9d9071a5b0d1f8d1336430c1ee01d4dc8b0d575e3798d48a803274126b" not yet present on node "kind-worker2", loading...
Image: "madhuakula/k8s-goat-metadata-db:latest" with ID "sha256:0ff4eace8cd5bd0459e7fc568e0b3b0e0885690a85feccbb18b75b462a705253" not yet present on node "kind-worker", loading...
Image: "madhuakula/k8s-goat-metadata-db:latest" with ID "sha256:0ff4eace8cd5bd0459e7fc568e0b3b0e0885690a85feccbb18b75b462a705253" not yet present on node "kind-control-plane", loading...
Image: "madhuakula/k8s-goat-metadata-db:latest" with ID "sha256:0ff4eace8cd5bd0459e7fc568e0b3b0e0885690a85feccbb18b75b462a705253" not yet present on node "kind-worker2", loading...
正在执行环境兼容性修复...
正在部署靶场场景...
Release "metadata-db" does not exist. Installing it now.
NAME: metadata-db
LAST DEPLOYED: Fri Jan  9 18:49:47 2026
NAMESPACE: default
STATUS: deployed
REVISION: 1
NOTES:
1. Get the application URL by running these commands:
  export POD_NAME=$(kubectl get pods --namespace default -l "app.kubernetes.io/name=metadata-db,app.kubernetes.io/instance=metadata-db" -o jsonpath="{.items[0].metadata.name}")
  echo "Visit http://127.0.0.1:8080 to use your application"
  kubectl port-forward $POD_NAME 8080:80
kubectl setup looks good.
deploying insecure super admin scenario
serviceaccount/superadmin created
clusterrolebinding.rbac.authorization.k8s.io/superadmin created
deploying helm chart metadata-db scenario
Error: INSTALLATION FAILED: cannot re-use a name that is still in use
deploying the vulnerable scenarios manifests
job.batch/batch-check-job created
deployment.apps/build-code-deployment created
service/build-code-service created
namespace/secure-middleware created
service/cache-store-service created
deployment.apps/cache-store-deployment created
deployment.apps/health-check-deployment created
service/health-check-service created
namespace/big-monolith created
role.rbac.authorization.k8s.io/secret-reader created
rolebinding.rbac.authorization.k8s.io/secret-reader-binding created
serviceaccount/big-monolith-sa created
secret/vaultapikey created
secret/webhookapikey created
deployment.apps/hunger-check-deployment created
service/hunger-check-service created
deployment.apps/internal-proxy-deployment created
service/internal-proxy-api-service created
service/internal-proxy-info-app-service created
deployment.apps/kubernetes-goat-home-deployment created
service/kubernetes-goat-home-service created
deployment.apps/poor-registry-deployment created
service/poor-registry-service created
secret/goatvault created
deployment.apps/system-monitor-deployment created
service/system-monitor-service created
job.batch/hidden-in-layers created
Successfully deployed Kubernetes Goat. Have fun learning Kubernetes Security!
Ensure pods are in running status before running access-kubernetes-goat.sh script
Now run the bash access-kubernetes-goat.sh to access the Kubernetes Goat environment.
----------------------------------------------------
 ✅ 环境部署就绪！
 🕒 本次启动总耗时: 608 秒 (10 分 8 秒)
 🔗 访问地址: http://宿主机IP:1234
----------------------------------------------------
```
