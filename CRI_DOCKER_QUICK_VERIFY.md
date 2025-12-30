# ✅ CRI Docker 环境快速验证指南

## 🎯 你的环境信息

```
容器运行时: CRI Docker (cri-dockerd)
Socket 地址: /var/run/cri-dockerd.sock
Socket 权限: 0660 (rw for root:docker)
Kubernetes: 已安装并运行
```

---

## 🚀 快速验证步骤 (5 分钟)

### Step 1: 验证 CRI Docker Socket 运行中 (1 分钟)

```bash
# 1️⃣ 检查 socket 文件是否存在
ls -la /var/run/cri-dockerd.sock

# 输出应该显示:
# srw-rw---- 1 root docker ... /var/run/cri-dockerd.sock

# 2️⃣ 检查 cri-docker 服务状态
systemctl status cri-docker.socket

# 输出应该显示:
# Active: active (running)
```

**✅ 验证通过**，继续下一步

### Step 2: 验证 Kubernetes 集群 (1 分钟)

```bash
# 1️⃣ 检查集群信息
kubectl cluster-info

# 输出应该显示:
# Kubernetes master is running at https://...
# CoreDNS is running at ...

# 2️⃣ 查看节点
kubectl get nodes

# 输出应该显示节点列表和 Ready 状态
```

**✅ 验证通过**，继续下一步

### Step 3: 验证项目文件 (1 分钟)

```bash
# 1️⃣ 检查修改是否生效
grep -n "cri-dockerd.sock" scenarios/health-check/deployment.yaml

# 输出应该显示:
# 19:            - mountPath: /var/run/cri-dockerd.sock
# ...

# 2️⃣ 检查 docker-bench-security
grep -n "cri-dockerd.sock" scenarios/docker-bench-security/deployment.yaml

# 输出应该显示:
# 22:    -v /var/run/cri-dockerd.sock:/var/run/cri-dockerd.sock:ro \
# ...
```

**✅ 验证通过**，继续下一步

### Step 4: 运行自动化检查 (1 分钟)

```bash
# 赋予脚本执行权限
chmod +x check-compatibility.sh

# 运行检查脚本
./check-compatibility.sh

# 应该显示: ✅ 通过所有检查
```

**✅ 验证通过**，准备部署

### Step 5: 部署 Kubernetes Goat (1 分钟)

```bash
# 部署
bash setup-kubernetes-goat.sh

# 等待输出完成
```

---

## 📊 部署验证

### 验证 Pod 是否正常运行

```bash
# 实时查看 Pod 状态
kubectl get pods -w

# 等待所有 Pod 状态为 Running (约 30-60 秒)
# 输出应该显示:
# NAME                                  READY   STATUS    RESTARTS   AGE
# build-code-deployment-xxx             1/1     Running   0          1m
# health-check-deployment-xxx           1/1     Running   0          1m
# kubernetes-goat-home-deployment-xxx   1/1     Running   0          1m
# ... etc
```

### 验证 health-check Pod 的 socket 挂载

```bash
# 1️⃣ 获取 Pod 名称
POD_NAME=$(kubectl get pods -l app=health-check -o jsonpath="{.items[0].metadata.name}")

# 2️⃣ 检查 socket 是否正确挂载
kubectl exec -it $POD_NAME -- ls -la /var/run/cri-dockerd.sock

# 输出应该显示:
# srw-rw---- 1 root docker 0 Dec 29 10:00 /var/run/cri-dockerd.sock

# 3️⃣ 测试 CRI Docker API 访问
kubectl exec -it $POD_NAME -- \
  curl --unix-socket /var/run/cri-dockerd.sock http://localhost/containers/json

# 输出应该显示 JSON 格式的容器列表
```

**✅ 验证成功**，socket 访问正常

### 验证 docker-bench-security

```bash
# 1️⃣ 查看 DaemonSet 状态
kubectl get daemonset docker-bench-security

# 输出应该显示:
# NAME                    DESIRED   CURRENT   READY   UP-TO-DATE   AVAILABLE
# docker-bench-security   1         1         1       1            1

# 2️⃣ 查看 Pod
kubectl get pods -l name=docker-bench

# 应该显示至少一个 Pod 在 Running 状态
```

---

## 🎯 开启访问

一旦所有 Pod 都运行成功：

```bash
# 1️⃣ 开启端口转发
bash access-kubernetes-goat.sh

# 2️⃣ 访问主页 (在浏览器中)
http://127.0.0.1:1234

# 或使用命令行
curl http://127.0.0.1:1234
```

---

## ⚠️ 常见问题快速诊断

### 问题: Pod 状态为 Pending

```bash
# 诊断
kubectl describe pod <pod-name>

# 查看原因
# 通常原因:
# 1. 镜像拉取中 (等待，正常现象)
# 2. 资源不足 (需要更多内存)
# 3. socket 权限问题 (重启 cri-docker)
```

**解决**:

```bash
# 重启 cri-docker
sudo systemctl restart cri-docker.socket
```

### 问题: Socket 文件不存在

```bash
# 诊断
ls -la /var/run/cri-dockerd.sock

# 若不存在，启动 cri-docker
sudo systemctl start cri-docker.socket
sudo systemctl enable cri-docker.socket

# 验证
ls -la /var/run/cri-dockerd.sock
```

### 问题: 权限被拒绝

```bash
# 诊断
stat /var/run/cri-dockerd.sock

# 应该显示:
# Access: (0660/srw-rw----)  Uid: (    0/    root)   Gid: (    5/   docker)

# 若权限不对，重启服务
sudo systemctl restart cri-docker.socket
```

---

## 📝 验证清单

部署前，请确认所有项都是 ✅：

- [ ] CRI Docker socket 存在 (`ls -la /var/run/cri-dockerd.sock`)
- [ ] CRI Docker 服务运行中 (`systemctl status cri-docker.socket`)
- [ ] Socket 权限正确 (rw for root:docker)
- [ ] Kubernetes 集群可访问 (`kubectl cluster-info`)
- [ ] 项目文件已更新为 cri-dockerd.sock
- [ ] 自动化检查通过 (`./check-compatibility.sh`)
- [ ] 足够的系统资源 (4GB+ 内存)

---

## 🔄 完整验证流程 (复制粘贴)

```bash
#!/bin/bash
echo "=== 验证 CRI Docker 环境 ==="

# 1. 检查 socket
echo "✓ 检查 CRI Docker socket..."
ls -la /var/run/cri-dockerd.sock || echo "❌ socket 不存在"

# 2. 检查服务
echo "✓ 检查 cri-docker 服务..."
systemctl status cri-docker.socket | grep Active

# 3. 检查 Kubernetes
echo "✓ 检查 Kubernetes 集群..."
kubectl cluster-info

# 4. 检查项目文件
echo "✓ 检查项目配置..."
grep "cri-dockerd.sock" scenarios/health-check/deployment.yaml && echo "✅ health-check 配置正确"
grep "cri-dockerd.sock" scenarios/docker-bench-security/deployment.yaml && echo "✅ docker-bench-security 配置正确"

# 5. 运行自动化检查
echo "✓ 运行自动化检查..."
./check-compatibility.sh

echo "=== 验证完成 ==="
```

---

## 🚀 立即开始

```bash
# 一键验证和部署
chmod +x check-compatibility.sh
./check-compatibility.sh && \
bash setup-kubernetes-goat.sh && \
kubectl get pods -w
```

---

## 📚 相关文档

- **CRI Docker 配置详解**: CRI_DOCKER_CONFIG.md
- **快速启动指南**: QUICK_START.md
- **完整兼容性报告**: DOCKER_COMPATIBILITY_REPORT.md

---

**你的环境已准备好使用 CRI Docker！** 🎉

**下一步**: 运行上面的验证步骤，确保一切就绪
