## kubernetes-goat-containerd

注意：使用 kind 部署的 kubernetes-goat 环境 只支持 containerd 容器，所以这套环境是
docker 部署的
docker+kind+kubernetes-goat+containerd 容器运行时
不是
docker+kind+kubernetes-goat+docker 容器运行时

<!-- 这是一张图片，ocr 内容为： -->

![](https://cdn.nlark.com/yuque/0/2026/png/27875807/1767978448644-57f76dd4-ec83-4c53-947b-e94e82744a6f.png)

<!-- 这是一个文本绘图，源码为：digraph K8sGoatV3_Fixed {
    rankdir=LR;
    node [shape=box, style="filled, rounded", fontname="Arial", fontsize=12];
    compound=true;
    nodesep=0.2;
    ranksep=1;

    // --- 图标题 ---
    label="摸鱼信安 && 灵境 Kubernetes-Goat-Containerd 集群靶场";
    labelloc="t";
    fontsize=16;
    fontcolor="#3E2723";

    // --- 外部访问层 ---
    User [label="用户浏览器", shape=ellipse, fillcolor="#F3E5F5", style=filled];

    // --- 宿主机端口层 ---
    subgraph cluster_host {
        label = "宿主机or虚拟机or灵境 Docker 端口映射 (Host Ports)";
        style = dashed;
        color = "#FFA000";

        P1230 [label="Port: 1230", fillcolor="#FFF9C4"];
        P1231 [label="Port: 1231", fillcolor="#FFF9C4"];
        P1232 [label="Port: 1232", fillcolor="#FFF9C4"];
        P1233 [label="Port: 1233", fillcolor="#FFF9C4"];
        P1234 [label="Port: 1234 (首页)", fillcolor="#FFECB3", fontcolor="#E65100", penwidth=2];
        P1235 [label="Port: 1235", fillcolor="#FFF9C4"];
        P1236 [label="Port: 1236", fillcolor="#FFF9C4"];
        P1237 [label="Port: 1237", fillcolor="#FFF9C4"];
        P1238 [label="Port: 1238", fillcolor="#FFF9C4"];
    }

    // --- Kubernetes 内部 NodePort / Pod ---
    subgraph cluster_k8s {
        label = "Kubernetes 集群 4 层负载均衡 - Pod";
        style = filled;
        color = "#E3F2FD";

        // NodePorts
        NP30000 [label="NodePort: 30000", fillcolor="#90CAF9", penwidth=2];
        NP30001 [label="NodePort: 30001", fillcolor="#BBDEFB"];
        NP30002 [label="NodePort: 30002", fillcolor="#BBDEFB"];
        NP30003 [label="NodePort: 30003", fillcolor="#BBDEFB"];
        NP30004 [label="NodePort: 30004", fillcolor="#BBDEFB"];
        NP30005 [label="NodePort: 30005", fillcolor="#BBDEFB"];
        NP30006 [label="NodePort: 30006", fillcolor="#BBDEFB"];
        NP30007 [label="NodePort: 30007", fillcolor="#BBDEFB"];
        NP30008 [label="NodePort: 30008", fillcolor="#BBDEFB"];

        // Pods
        Pod_Home [label="Pod: kubernetes-goat-home", fillcolor="#A5D6A7", penwidth=2];
        Pod_Meta [label="Pod: metadata-db", fillcolor="#C8E6C9"];
        Pod_Health [label="Pod: health-check\n(DIND 逃逸)", fillcolor="#FFAB91", fontcolor="#BF360C"];
        Pod_Build [label="Pod: build-code", fillcolor="#C8E6C9"];
        Pod_Poor [label="Pod: poor-registry", fillcolor="#C8E6C9"];
        Pod_Hunger [label="Pod: hunger-check", fillcolor="#C8E6C9"];
        Pod_ProxyAPI [label="Pod: internal-proxy API", fillcolor="#C8E6C9"];
        Pod_ProxyInfo [label="Pod: internal-proxy Info", fillcolor="#C8E6C9"];
        Pod_Monitor [label="Pod: system-monitor", fillcolor="#C8E6C9"];
    }

    // --- 外部用户访问路径 ---
    User -> {P1230 P1231 P1232 P1233 P1234 P1235 P1236 P1237 P1238} [color="#BDBDBD"];

    // --- HostPort -> NodePort -> Pod 映射 ---
    P1234 -> NP30000 -> Pod_Home;
    P1230 -> NP30001 -> Pod_Meta;
    P1231 -> NP30002 -> Pod_Health;
    P1232 -> NP30003 -> Pod_Build;
    P1238 -> NP30004 -> Pod_Poor;
    P1235 -> NP30005 -> Pod_Hunger;
    P1233 -> NP30006 -> Pod_ProxyAPI;
    P1236 -> NP30007 -> Pod_ProxyInfo;
    P1237 -> NP30008 -> Pod_Monitor;
}
 -->

## 访问路径

官方标准：只暴露 7 个端口（1230-1236），对应 7 个需要网络访问的靶场

| 宿主机端口 | 场景                              | 容器内端口 | NodePort |
| ---------- | --------------------------------- | ---------- | -------- |
| 1230       | build-code (Sensitive keys)       | 3000       | 30001    |
| 1231       | health-check (DIND)               | 80         | 30002    |
| 1232       | internal-proxy (SSRF)             | 3000       | 30003    |
| 1233       | system-monitor (Container Escape) | 8080       | 30004    |
| 1234       | kubernetes-goat-home (首页)       | 80         | 30000    |
| 1235       | poor-registry (Private Registry)  | 5000       | 30005    |
| 1236       | hunger-check (DoS)                | 8080       | 30006    |

<!-- 这是一张图片，ocr 内容为： -->

![](https://cdn.nlark.com/yuque/0/2026/png/27875807/1768038097304-7debea6e-864a-4b7f-bd7a-7041ae756e27.png)

## 导入镜像

```bash
# 导出已构建的镜像
docker save -o kind-k8s-goat-v3.tar kind-k8s-goat-moyusec-lingjing:v3.0

# 或导入镜像
docker load -i kind-k8s-goat-v3.tar
```

## 构建镜像（如需重新构建）

```bash
# 在 /root/DKinD 目录下执行
cd /root/DKinD

# 确保以下文件/目录存在：
# - docker:24-dind.tar
# - kind_node_v1.27.3.tar.gz
# - k8s_goat_images_offline.tar.gz
# - kind-config.yaml (会由脚本生成)
# - Dockerfile
# - entrypoint.sh

# 方式 1: 使用 deploy-kind.sh 自动构建（推荐）
bash kubernetes-goat-docker/scripts/deploy-kind.sh

# 方式 2: 手动 docker build（需要 scenarios, scripts, sesource 目录）
docker build -t kind-k8s-goat-moyusec-lingjing:v3.0 .
```

## 运行集群

4c4g 启动时间大概在 12 分钟左右，取决于你机器的配置，请耐心等待

```bash
docker run --privileged -d \
  --name kind-k8s-goat \
  --memory="4g" --cpus="4" \
  -p 1230:1230 \
  -p 1231:1231 \
  -p 1232:1232 \
  -p 1233:1233 \
  -p 1234:1234 \
  -p 1235:1235 \
  -p 1236:1236 \
  kind-k8s-goat-moyusec-lingjing:v3.0
```

## 查看日志

```bash
docker logs -f kind-k8s-goat
```

## 进入容器

```bash
docker exec -it kind-k8s-goat bash
```
