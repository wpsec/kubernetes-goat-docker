# Kind 环境不支持的安全工具

## 概述

在 Kubernetes-Goat Docker 的 Kind 部署中，以下三个安全工具 **不再导入镜像也不部署**：

- **Falco** - 实时威胁检测
- **Kyverno** - 策略管理引擎
- **Tetragon** - 实时观测和安全

这些工具在 Kind 环境中无法正常工作，已从自动部署流程中移除。

## 部署变更

### 镜像处理

部署脚本会自动删除这三个工具的镜像，以节省磁盘空间：

```bash
# entrypoint.sh 和 deploy-kind.sh 中自动执行
docker rmi falcosecurity/falco:0.42.1
docker rmi falcosecurity/falco-driver-loader:0.42.1
docker rmi falcosecurity/falcoctl:0.11.4
docker rmi reg.kyverno.io/kyverno/kyverno:v1.16.2
docker rmi reg.kyverno.io/kyverno/background-controller:v1.16.2
docker rmi reg.kyverno.io/kyverno/cleanup-controller:v1.16.2
docker rmi reg.kyverno.io/kyverno/reports-controller:v1.16.2
docker rmi reg.kyverno.io/kyverno/kyverno-cli:v1.16.2
docker rmi reg.kyverno.io/kyverno/kyvernopre:v1.16.2
docker rmi quay.io/cilium/tetragon:v1.6.0
docker rmi quay.io/cilium/tetragon-operator:v1.6.0
docker rmi quay.io/cilium/hubble-export-stdout:v1.1.0
```

### YAML 部署跳过

`kubectl apply` 不再执行以下文件：

- `sesource/falco.yaml` ❌
- `sesource/kyverno.yaml` ❌
- `sesource/tetragon.yaml` ❌

## 为什么不支持

### 1. Falco（必须移除）

**原因**：

- Falco 需要 **Linux 内核驱动** 和 **eBPF 支持**
- Kind 节点本质是 Docker 容器，**无法加载内核模块**
- 即使启用 `--privileged`，eBPF 权限也受限制

**症状**（如果尝试部署会看到）：

```
Pod Status: Init:0/2 (Init 容器启动失败)
falco-driver-loader 无法初始化
ConfigMap 挂载超时
```

**解决方案**：

- 如需 Falco，使用 **真实 VM/物理机** 部署（需要特定内核 >= 4.14）
- 或在 EKS/GKE 等云 Kubernetes 中使用

---

### 2. Kyverno（CRD 版本不兼容）

**原因**：

- `kyverno.yaml` 包含 CRD 定义，使用了 `selectableFields` 字段
- Kubernetes 1.27.3（Kind 使用的版本）**不支持该字段**
- CRD 元数据注释过长，超过 262KB 限制

**错误示例**：

```
Error: CustomResourceDefinition "clusterpolicies.kyverno.io" is invalid:
  spec.versions[1].selectableFields: unknown field
```

**解决方案**：

- 升级 Kind 到 Kubernetes 1.30+（支持该 CRD 版本）
- 或等待 Kyverno 发布兼容 K8s 1.27.3 的版本

---

### 3. Tetragon（暂时移除）

**原因**：

- Tetragon 同样依赖 **eBPF/内核驱动**
- 在 Kind 容器中权限受限
- 虽然可能部分功能运行，但无法完全工作

**解决方案**：

- 需要真实容器运行时和内核支持
- 或在云 Kubernetes（支持 eBPF）中使用

---

## 修改日志

### 脚本变更

**文件**: `scripts/deploy-kind.sh`

#### 变更 1：镜像加载阶段（entrypoint.sh 内）

- ✅ 删除 Falco 镜像（3 个）
- ✅ 新增：删除 Kyverno 镜像（6 个）
- ✅ 新增：删除 Tetragon 镜像（3 个）
- **磁盘节省**: 约 ~1.2GB

#### 变更 2：镜像加载阶段（主脚本）

- ✅ 同步删除所有三个工具的镜像

#### 变更 3：部署阶段

- ✅ 跳过 `sesource/falco.yaml` 部署
- ✅ 跳过 `sesource/kyverno.yaml` 部署
- ✅ 跳过 `sesource/tetragon.yaml` 部署

#### 变更 4：欢迎信息更新

- ✅ 更新说明文本
- 现在显示：`Falco、Kyverno、Tetragon 未在 Kind 环境部署`

---

## 磁盘空间影响

### 删除的镜像

| 工具     | 镜像数量 | 镜像名称示例                   | 磁盘占用   |
| -------- | -------- | ------------------------------ | ---------- |
| Falco    | 3        | falcosecurity/falco:0.42.1     | ~290MB     |
| Kyverno  | 6        | reg.kyverno.io/kyverno:v1.16.2 | ~600MB     |
| Tetragon | 3        | quay.io/cilium/tetragon:v1.6.0 | ~310MB     |
| **总计** | **12**   | -                              | **~1.2GB** |

### 原始方案 vs 优化方案

```
原始方案（加载所有 31 个镜像到 3 个节点）：
  - 磁盘占用：~50GB+

优化方案（只加载 7 个关键镜像，移除安全工具）：
  - 关键镜像到节点：7 × 3 = 21 个
  - 节省空间：~15-20GB
  - 预期总占用：~20-25GB

进一步优化（移除 falco/kyverno/tetragon）：
  - 额外节省：~1.2GB
  - 新预期：~19-24GB ✅
```

---

## 使用建议

### 如果需要实时安全监控

**可选方案**：

1. **生产环境**：

   ```bash
   # 在真实 EKS/GKE/AKS 上部署
   kubectl apply -f sesource/falco.yaml      # 完整支持
   kubectl apply -f sesource/kyverno.yaml    # 需要 K8s 1.30+
   ```

2. **本地开发**：

   - 使用 **Kyverno CLI** 进行本地策略验证
   - 使用 **OPA/Gatekeeper** 作为轻量级替代
   - 使用 **kubewarden** 作为 Rust 编写的策略引擎

3. **临时监控**：
   ```bash
   # 在节点上直接运行（Host 网络）
   docker run --net=host --privileged \
     quay.io/cilium/tetragon:v1.6.0
   ```

---

## 更新历史

| 版本 | 日期       | 变更                                  |
| ---- | ---------- | ------------------------------------- |
| 3.0  | 2026-01-12 | 移除 falco/kyverno/tetragon，节省空间 |
| 2.9  | 2026-01-11 | 保留所有工具，磁盘占用 50GB+          |

---

## 常见问题

**Q: 如何在生产环境使用这些工具？**
A: 这些工具在真实 Kubernetes 集群（云或自建 VM）中完全支持。Kind 只是本地开发工具，不是生产环境。

**Q: 能否在 Kind 中启用 eBPF？**
A: 不能。Kind 容器的内核是宿主机内核的只读视图，无法加载模块。即使使用 `--privileged`，权限仍受限制。

**Q: 如何升级 Kubernetes 版本以支持新 Kyverno？**
A: 在 `kind-config.yaml` 中修改：

```yaml
nodes:
  - role: control-plane
    image: kindest/node:v1.30.0 # 升级到 1.30.0+
```

**Q: 这会影响靶场学习吗？**
A: 不会。这三个工具是安全加固组件，不是核心靶场。核心 8 个靶场完全不受影响：

- build-code ✅
- health-check ✅
- internal-proxy ✅
- system-monitor ✅
- kubernetes-goat-home ✅
- poor-registry ✅
- hunger-check ✅
- metadata-db ✅

---

## 反馈与支持

如需在真实环境中使用安全工具，请参考官方文档：

- Falco: https://falco.org/docs/
- Kyverno: https://kyverno.io/docs/
- Tetragon: https://tetragon.cilium.io/
