## kubernetes-goat-containerd

注意：使用 kind 部署的 kubernetes-goat 环境 只支持 containerd 容器，所以这套环境是
docker 部署的
docker+kind+kubernetes-goat+containerd 容器运行时
不是
docker+kind+kubernetes-goat+docker 容器运行时

<!-- 这是一张图片，ocr 内容为： -->

![](https://cdn.nlark.com/yuque/0/2026/png/27875807/1767978448644-57f76dd4-ec83-4c53-947b-e94e82744a6f.png)

更新镜像

```bash
aquasec/kube-bench:latest
madhuakula/hacker-container:latest
madhuakula/k8s-goat-batch-check:latest
madhuakula/k8s-goat-build-code:latest
madhuakula/k8s-goat-cache-store:latest
madhuakula/k8s-goat-health-check:latest
madhuakula/k8s-goat-hidden-in-layers:latest
madhuakula/k8s-goat-home:latest
madhuakula/k8s-goat-hunger-check:latest
madhuakula/k8s-goat-info-app:latest
madhuakula/k8s-goat-internal-api:latest
madhuakula/k8s-goat-metadata-db:latest
madhuakula/k8s-goat-poor-registry:latest
madhuakula/k8s-goat-system-monitor:latest
madhuakula/k8s-goat-helm-tiller:latest
docker.io/falcosecurity/falco:0.42.1
docker.io/falcosecurity/falco-driver-loader:0.42.1
docker.io/falcosecurity/falcoctl:0.11.4
nginx:latest
alpine:latest
quay.io/cilium/tetragon:v1.6.0
quay.io/cilium/hubble-export-stdout:v1.1.0
quay.io/cilium/tetragon-operator:v1.6.0
reg.kyverno.io/kyverno/kyverno:v1.16.2
reg.kyverno.io/kyverno/background-controller:v1.16.2
reg.kyverno.io/kyverno/cleanup-controller:v1.16.2
reg.kyverno.io/kyverno/reports-controller:v1.16.2
reg.kyverno.io/kyverno/kyverno-cli:v1.16.2
reg.kyverno.io/kyverno/kyvernopre:v1.16.2
curlimages/curl:8.10.1
registry.k8s.io/kubectl:v1.32.7
```

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
    
        P1230 [label="Port: 1230\nbuild-code", fillcolor="#FFF9C4"];
        P1231 [label="Port: 1231\nhealth-check", fillcolor="#FFF9C4"];
        P1232 [label="Port: 1232\ninternal-proxy", fillcolor="#FFF9C4"];
        P1233 [label="Port: 1233\nsystem-monitor", fillcolor="#FFF9C4"];
        P1234 [label="Port: 1234 (首页)", fillcolor="#FFECB3", fontcolor="#E65100", penwidth=2];
        P1235 [label="Port: 1235\npoor-registry", fillcolor="#FFF9C4"];
        P1236 [label="Port: 1236\nhunger-check", fillcolor="#FFF9C4"];
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
    
        // Pods
        Pod_Home [label="Pod: kubernetes-goat-home", fillcolor="#A5D6A7", penwidth=2];
        Pod_Build [label="Pod: build-code", fillcolor="#C8E6C9"];
        Pod_Health [label="Pod: health-check\n(DIND 逃逸)", fillcolor="#FFAB91", fontcolor="#BF360C"];
        Pod_Proxy [label="Pod: internal-proxy", fillcolor="#C8E6C9"];
        Pod_Monitor [label="Pod: system-monitor", fillcolor="#C8E6C9"];
        Pod_Registry [label="Pod: poor-registry", fillcolor="#C8E6C9"];
        Pod_Hunger [label="Pod: hunger-check", fillcolor="#C8E6C9"];
    }
    
    // --- 外部用户访问路径 ---
    User -> {P1230 P1231 P1232 P1233 P1234 P1235 P1236} [color="#BDBDBD"];
    
    // --- HostPort -> NodePort -> Pod 映射 ---
    P1234 -> NP30000 -> Pod_Home;
    P1230 -> NP30001 -> Pod_Build;
    P1231 -> NP30002 -> Pod_Health;
    P1232 -> NP30003 -> Pod_Proxy;
    P1233 -> NP30004 -> Pod_Monitor;
    P1235 -> NP30005 -> Pod_Registry;
    P1236 -> NP30006 -> Pod_Hunger;
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
# 导入镜像
docker load -i kind-k8s-goat-v3.tar
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

## 基于kubernetes-goat的集群内容（红蓝队+甲乙方视角）学习（后续提供）

待更新



## 其它说明

### Falco 在 Kind 环境中无法运行的原因

## 概述

Falco 是一个强大的云原生运行时安全工具，但在 **Kind（Kubernetes in Docker）** 环境中 **无法正常工作**。

---

#### 核心原因：内核驱动限制

#### 1️⃣ Falco 的工作原理

Falco 通过以下方式进行系统监控：

```
应用程序
    ↓
系统调用 (syscall)
    ↓
Falco 内核驱动 / eBPF 探针
    ↓
实时检测和警报
```

**关键依赖**：

- **eBPF（Extended Berkeley Packet Filter）** - 需要 Linux 内核 >= 4.14
- **内核驱动加载** - 需要在运行时动态加载内核模块
- **/sys 和 /proc 访问** - 需要完整的系统接口

---

#### Kind 环境中的限制

#### Kind 是什么？

```
Host OS (macOS / Linux / Windows /灵境)
    ↓
Docker 守护进程
    ↓
Docker 容器 (kindest/node:v1.27.3)
    ↓
Kubernetes 集群 (Kind)
```

**Kind 节点本质上是 Docker 容器**，而不是真实的虚拟机或物理服务器。

#### 限制详解

| 限制项            | 问题                              | 影响                               |
| ----------------- | --------------------------------- | ---------------------------------- |
| **内核驱动加载**  | Docker 容器中无法加载主机内核模块 | Falco 驱动加载失败                 |
| **权限隔离**      | 容器有受限的 Linux 权限           | 无法访问完整的 /sys 接口           |
| **eBPF 限制**     | eBPF 程序需要特殊的内核支持       | eBPF 探针无法挂载                  |
| **/proc 和 /sys** | 容器内的 /proc 和 /sys 是受限视图 | 无法获得准确的系统信息             |
| **内核版本**      | Kind 容器继承宿主机内核           | 若宿主机内核不支持，则完全无法使用 |

---

#### Falco 启动失败的具体症状

#### 错误信息示例

```bash
Events:
  Type     Reason       Age    From               Message
  ----     ------       ----   ----               -------
  Normal   Scheduled    2m52s  default-scheduler  Successfully assigned default/falco-6jgsx to kind-worker2
  Warning  FailedMount  2m51s  kubelet            MountVolume.SetUp failed for volume "falco-yaml" :
           failed to sync configmap cache: timed out waiting for the condition
  Normal   Pulling      2m49s  kubelet            Pulling image "docker.io/falcosecurity/falco-driver-loader:0.42.1"
```

#### Pod 状态

```bash
NAME                 READY   STATUS      RESTARTS   AGE
falco-6jgsx          0/2     Init:0/2    0          2m58s
falco-6sxgc          0/2     Init:0/2    0          2m58s
falco-k7k75          0/2     Init:0/2    0          2m58s
```

**解释**：

- `0/2` - 2 个容器中 0 个就绪
- `Init:0/2` - Init 容器启动失败
- 原因：`falco-driver-loader` 无法加载驱动

---

#### 解决方案

---

#### 方案 ：使用真实虚拟机环境（后续提供）

---

#### Falco 的需求与 Kind 的矛盾

| 需求             | Falco   | Kind      | 可行性 |
| ---------------- | ------- | --------- | ------ |
| 内核驱动加载     | ✅ 必需 | ❌ 不支持 | ❌     |
| eBPF 权限        | ✅ 必需 | ⚠️ 受限   | ⚠️     |
| /sys 完整访问    | ✅ 必需 | ❌ 受限   | ❌     |
| /proc 完整访问   | ✅ 必需 | ⚠️ 受限   | ⚠️     |
| CAP_SYS_RESOURCE | ✅ 必需 | ⚠️ 受限   | ⚠️     |
| 内核版本 >= 4.14 | ✅ 必需 | ✅ 支持   | ✅     |

**结论**：Kind 缺少 Falco 运行的关键条件。
