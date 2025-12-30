# 快速启动指南

## 🚀 前置条件检查

在部署 Kubernetes Goat 前，请运行兼容性检查脚本：

```bash
# 赋予脚本执行权限
chmod +x check-compatibility.sh

# 运行检查
./check-compatibility.sh
```

该脚本会检查以下内容：

- ✅ kubectl 和 helm 是否已安装
- ✅ Kubernetes 集群是否可访问
- ✅ Docker socket 是否可用
- ✅ 项目文件是否完整
- ✅ Docker 迁移配置是否正确
- ✅ 系统资源是否充足

---

## 📋 快速部署步骤

### 1️⃣ 检查环境

```bash
./check-compatibility.sh
```

如果所有检查通过，继续下一步。

### 2️⃣ 部署 Kubernetes Goat

```bash
chmod +x setup-kubernetes-goat.sh
bash setup-kubernetes-goat.sh
```

部署通常需要 30-60 秒。

### 3️⃣ 等待 Pod 就绪

```bash
# 实时查看 Pod 状态
kubectl get pods -w

# 或者检查特定场景
kubectl get pods -l app=health-check
kubectl get pods -l app=build-code
```

所有 Pod 应该显示为 `Running` 状态。

### 4️⃣ 开启端口转发访问

```bash
chmod +x access-kubernetes-goat.sh
bash access-kubernetes-goat.sh
```

该脚本会在后台启动端口转发。

### 5️⃣ 访问 Kubernetes Goat 主页

```bash
# 在浏览器中访问
http://127.0.0.1:1234

# 或使用命令行
curl http://127.0.0.1:1234
```

---

## 🔍 验证部署状态

### 查看所有 Pod 状态

```bash
kubectl get pods -A

# 输出应该类似:
# NAMESPACE              NAME                                  READY   STATUS    RESTARTS   AGE
# default                build-code-deployment-xxx             1/1     Running   0          2m
# default                health-check-deployment-xxx           1/1     Running   0          2m
# default                system-monitor-deployment-xxx         1/1     Running   0          2m
# kube-system            docker-bench-security-xxx             1/1     Running   0          2m
# secure-middleware      cache-store-deployment-xxx            1/1     Running   0          2m
# big-monolith          hunger-check-deployment-xxx            1/1     Running   0          2m
```

### 检查 Docker Socket 挂载

```bash
# 检查 health-check Pod 是否能访问 Docker socket
POD_NAME=$(kubectl get pods -l app=health-check -o jsonpath="{.items[0].metadata.name}")

# 验证 socket 存在
kubectl exec -it $POD_NAME -- ls -la /var/run/docker.sock

# 输出应该显示:
# srw-rw---- 1 root docker 0 Dec 29 10:00 /var/run/docker.sock
```

### 测试 DIND (Docker-in-Docker)

```bash
POD_NAME=$(kubectl get pods -l app=health-check -o jsonpath="{.items[0].metadata.name}")

# 测试 Docker socket 是否可操作
kubectl exec -it $POD_NAME -- \
  curl --unix-socket /var/run/docker.sock http://localhost/containers/json

# 或检查 docker 命令
kubectl exec -it $POD_NAME -- docker ps
```

### 检查其他场景

#### Build Code 场景 (1230 端口)

```bash
curl http://127.0.0.1:1230
```

#### Internal Proxy 场景 (1232 端口)

```bash
curl http://127.0.0.1:1232
```

#### System Monitor 场景 (1233 端口)

```bash
curl http://127.0.0.1:1233
```

#### Poor Registry 场景 (1235 端口)

```bash
curl http://127.0.0.1:1235
```

---

## 📊 监控和日志

### 查看 Pod 日志

```bash
# 查看特定 Pod 的日志
kubectl logs -l app=health-check

# 实时跟踪日志
kubectl logs -f -l app=health-check

# 查看 docker-bench-security DaemonSet 日志
kubectl logs -l name=docker-bench
```

### 描述 Pod 获取详细信息

```bash
POD_NAME=$(kubectl get pods -l app=health-check -o jsonpath="{.items[0].metadata.name}")
kubectl describe pod $POD_NAME

# 输出会显示:
# - Pod 状态
# - 事件 (Events)
# - 卷挂载 (Mounts)
# - 环境变量 (Environment)
```

### 实时监控资源使用

```bash
# 查看 Pod 资源使用情况
kubectl top pods

# 查看节点资源使用情况
kubectl top nodes
```

---

## ⚠️ 常见问题排查

### 问题 1: Pod 状态为 Pending

**症状**:

```bash
kubectl get pods
# STATUS: Pending
```

**原因**: 通常是资源不足或镜像拉取中

**解决方案**:

```bash
# 检查事件
kubectl describe pod <pod-name>

# 查看节点状态
kubectl get nodes
kubectl top nodes

# 查看镜像拉取进度
kubectl get events --sort-by='.lastTimestamp'
```

### 问题 2: Docker Socket 无法访问

**症状**:

```bash
kubectl exec -it <pod-name> -- ls /var/run/docker.sock
# ls: cannot access '/var/run/docker.sock': No such file or directory
```

**原因**: Docker socket 未在宿主机上暴露

**解决方案**:

```bash
# 检查宿主机 Docker socket
ls -la /var/run/docker.sock

# 如果使用 Containerd，创建映射
# 在每个 Kubernetes 节点上运行:
ln -s /run/containerd/containerd.sock /var/run/docker.sock

# 或配置 KinD 时，在 kind-config.yaml 中添加:
extraMounts:
  - hostPath: /var/run/docker.sock
    containerPath: /var/run/docker.sock
```

### 问题 3: 镜像拉取失败

**症状**:

```bash
kubectl describe pod <pod-name> | grep -i image
# Failed to pull image "madhuakula/k8s-goat-health-check:latest"
```

**原因**: 网络问题或镜像不存在

**解决方案**:

```bash
# 检查网络连接
ping docker.io

# 手动拉取镜像测试
docker pull madhuakula/k8s-goat-health-check

# 如果无法从公网拉取，使用本地镜像:
# 1. 手动构建或加载镜像
# 2. 修改 deployment.yaml 中的镜像名称
# 3. 使用 imagePullPolicy: Never
```

### 问题 4: 权限被拒绝

**症状**:

```bash
kubectl exec -it <pod-name> -- docker ps
# permission denied while trying to connect to Docker daemon socket
```

**原因**: Pod 内用户无权访问 Docker socket

**解决方案**:

```bash
# 确保 Pod 运行特权模式
kubectl describe pod <pod-name> | grep -i privileged

# 如果没有设置，需要修改 deployment.yaml:
securityContext:
  privileged: true
  allowPrivilegeEscalation: true
```

---

## 🧹 清理资源

### 删除所有 Kubernetes Goat 资源

```bash
bash teardown-kubernetes-goat.sh
```

或手动删除:

```bash
# 删除所有 scenarios
kubectl delete -f scenarios/batch-check/job.yaml
kubectl delete -f scenarios/build-code/deployment.yaml
kubectl delete -f scenarios/cache-store/deployment.yaml
kubectl delete -f scenarios/health-check/deployment.yaml
kubectl delete -f scenarios/hunger-check/deployment.yaml
kubectl delete -f scenarios/internal-proxy/deployment.yaml
kubectl delete -f scenarios/kubernetes-goat-home/deployment.yaml
kubectl delete -f scenarios/poor-registry/deployment.yaml
kubectl delete -f scenarios/system-monitor/deployment.yaml
kubectl delete -f scenarios/hidden-in-layers/deployment.yaml

# 删除 Helm releases
helm uninstall metadata-db

# 删除 RBAC 配置
kubectl delete -f scenarios/insecure-rbac/setup.yaml

# 删除命名空间
kubectl delete namespace big-monolith
kubectl delete namespace secure-middleware
```

### 关闭端口转发

```bash
# 查找并杀死 port-forward 进程
pkill -f "kubectl.*port-forward"

# 或手动关闭
killall kubectl
```

---

## 📚 相关文档

- **Docker 迁移说明**: 查看 `DOCKER_MIGRATION_NOTES.md`
- **兼容性报告**: 查看 `DOCKER_COMPATIBILITY_REPORT.md`
- **官方指南**: https://madhuakula.com/kubernetes-goat

---

## 💡 提示

1. **使用 kubectl proxy** (替代 port-forward):

   ```bash
   kubectl proxy --port=8001 &
   # 访问: http://localhost:8001/api/v1/namespaces/default/pods
   ```

2. **使用 stern** 查看多个 Pod 日志:

   ```bash
   # 安装: brew install stern (Mac) 或 go install github.com/stern/stern@latest
   stern -l app=health-check
   ```

3. **使用 kubectx** 快速切换集群:

   ```bash
   # 安装: brew install kubectx
   kubectx  # 查看和切换集群
   kubens   # 查看和切换命名空间
   ```

4. **定期检查资源使用**:
   ```bash
   watch -n 2 kubectl top pods
   ```

---

**最后修改**: 2025-12-29
**兼容性**: Kubernetes 1.19+, Docker, Helm 3+
