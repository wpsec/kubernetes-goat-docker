kubernetes-goat-containerd
注意：使用 kind 部署的 kubernetes-goat 环境 只支持 containerd 容器，所以这套环境是
docker 部署的
docker+kind+kubernetes-goat+containerd 容器运行时
不是
docker+kind+kubernetes-goat+docker 容器运行时

<!-- 这是一张图片，ocr 内容为： -->

![](https://cdn.nlark.com/yuque/0/2026/png/27875807/1767978448644-57f76dd4-ec83-4c53-947b-e94e82744a6f.png)

网络映射

<!-- 这是一个文本绘图，源码为：
digraph K8sGoatV3_Fixed {
    rankdir=LR;
    node [shape=box, style="filled, rounded", fontname="Arial", fontsize=12];
    compound=true;
    nodesep=0.2;
    ranksep=1;

    // --- 外部访问层 ---
    User [label="用户浏览器", shape=ellipse, fillcolor="#F3E5F5", style=filled];

    // --- 宿主机端口层 ---
    subgraph cluster_host {
        label = "宿主机Docker端口映射 (Host Ports)";
        style = dashed;
        color = "#FFA000";

        P1230 [label="Port: 1230", fillcolor="#FFF9C4"];
        P1231 [label="Port: 1231", fillcolor="#FFF9C4"];
        P1233 [label="Port: 1233", fillcolor="#FFF9C4"];
        P1234 [label="Port: 1234 (首页)", fillcolor="#FFECB3", fontcolor="#E65100", penwidth=2];
        P1235 [label="Port: 1235", fillcolor="#FFF9C4"];
        P1236 [label="Port: 1236", fillcolor="#FFF9C4"];
    }

    // --- K8s 内部逻辑层 ---
    subgraph cluster_k8s {
        label = "Kubernetes 集群 四层负载均衡——Pod";
        style = filled;
        color = "#E3F2FD";

        // NodePorts
        NP30001 [label="NodePort: 30001", fillcolor="#BBDEFB"];
        NP30002 [label="NodePort: 30002", fillcolor="#BBDEFB"];
        NP30003 [label="NodePort: 30003", fillcolor="#BBDEFB"];
        NP30004 [label="NodePort: 30004", fillcolor="#BBDEFB"];
        NP30000 [label="NodePort: 30000", fillcolor="#90CAF9", penwidth=2];
        NP30006 [label="NodePort: 30006", fillcolor="#BBDEFB"];

        // 目标 Pods
        Pod_Meta [label="Pod: metadata-db", fillcolor="#C8E6C9"];
        Pod_Health [label="Pod: health-check\n(DIND 逃逸)", fillcolor="#FFAB91", fontcolor="#BF360C"]; // 简体中文注释：强调这是核心漏洞点
        Pod_Build [label="Pod: build-code", fillcolor="#C8E6C9"];
        Pod_Batch [label="Pod: batch-check", fillcolor="#C8E6C9"];
        Pod_Home [label="Pod: kubernetes-goat-home", fillcolor="#A5D6A7", penwidth=2];
        Pod_Proxy [label="Pod: internal-proxy", fillcolor="#C8E6C9"];
    }

    // --- 连线逻辑 (对应你当前的实际 kubectl 输出) ---
    User -> {P1230 P1231 P1233 P1234 P1235 P1236} [color="#BDBDBD"];

    P1230 -> NP30001 -> Pod_Meta;
    P1231 -> NP30002 -> Pod_Health; // 对应你修改后的 1231 -> 30002
    P1232 -> NP30003 -> Pod_Build;
    P1233 -> NP30003 -> Pod_Build; // 根据你 kubectl 输出，build-code 占用了 30003
    P1235 -> NP30004 -> Pod_Batch;
    P1234 -> NP30000 -> Pod_Home [color="#E65100", penwidth=2];
    P1236 -> NP30006 -> Pod_Proxy;
}
-->

![](https://cdn.nlark.com/yuque/__graphviz/cb8d0a6b6dd63f9c33dc5f5abf120e17.svg)

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
