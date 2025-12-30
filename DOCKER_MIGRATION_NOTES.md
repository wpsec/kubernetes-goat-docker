# Docker 迁移说明文档

## 概述

本文档记录了 Kubernetes Goat 项目从 **Containerd** 容器运行时迁移到 **Docker** 的所有修改。

## 修改日期

2025 年 12 月 29 日

## 修改的文件

### 1. `scenarios/health-check/deployment.yaml`

#### 修改内容

将健康检查场景的容器运行时从 Containerd 改为 Docker。

#### 具体变更

| 项目            | 修改前                               | 修改后                 |
| --------------- | ------------------------------------ | ---------------------- |
| Socket 挂载路径 | `/run/containerd/containerd.sock`    | `/var/run/docker.sock` |
| 卷名称          | `containerd-sock-volume`             | `docker-sock-volume`   |
| mountPath       | `/custom/containerd/containerd.sock` | `/var/run/docker.sock` |

#### 影响的功能

- **DIND (Docker-in-Docker) 利用场景**: 现在使用 Docker socket 而不是 Containerd socket
- 允许容器内部访问宿主机的 Docker 守护进程

---

### 2. `scenarios/docker-bench-security/deployment.yaml`

#### 修改内容

移除 Containerd 和 Runc 二进制文件的挂载，仅保留 Docker socket。

#### 具体变更

**移除的卷挂载:**

```yaml
# 已删除
- name: usr-bin-contained-vol
  mountPath: /usr/bin/containerd
  readOnly: true
- name: usr-bin-runc-vol
  mountPath: /usr/bin/runc
  readOnly: true
```

**移除的卷定义:**

```yaml
# 已删除
- name: usr-bin-contained-vol
  hostPath:
    path: /usr/bin/containerd
- name: usr-bin-runc-vol
  hostPath:
    path: /usr/bin/runc
```

**保留的配置:**

- Docker socket 挂载: `/var/run/docker.sock` ✓
- 所有系统相关挂载保持不变（/etc, /lib/systemd/system, /usr/lib/systemd, /var/lib）

#### 影响的功能

- **Docker 安全基准测试场景**: 现在分析 Docker 而不是 Containerd
- 仍然可以访问宿主机的系统文件进行安全审计

---

## 技术细节

### Containerd vs Docker Socket 路径差异

| 容器运行时 | Socket 路径                       | 默认类型    |
| ---------- | --------------------------------- | ----------- |
| Containerd | `/run/containerd/containerd.sock` | Unix Socket |
| Docker     | `/var/run/docker.sock`            | Unix Socket |

### Kubernetes Volume Mount 配置

**Docker Socket (现在使用):**

```yaml
volumeMounts:
  - mountPath: /var/run/docker.sock
    name: docker-sock-volume
volumes:
  - name: docker-sock-volume
    hostPath:
      path: /var/run/docker.sock
      type: Socket
```

---

## 验证修改

### 检查部署状态

```bash
# 查看所有 Pod
kubectl get pods

# 检查 health-check Pod 的卷挂载
kubectl describe pod <health-check-pod-name>

# 检查 docker-bench-security DaemonSet
kubectl describe daemonset docker-bench-security
```

### 测试 Docker Socket 访问

```bash
# 进入 Pod 内部
kubectl exec -it <pod-name> -- /bin/sh

# 列出 Docker 镜像（如果有 docker 命令行工具）
docker ps
docker images

# 或使用 curl 通过 Unix socket 访问 Docker API
curl --unix-socket /var/run/docker.sock http://localhost/containers/json
```

---

## 注意事项

### ✅ 前置条件

- Kubernetes 集群必须使用 Docker 作为容器运行时（或支持 Docker socket）
- `/var/run/docker.sock` 必须在宿主机上可用
- 容器需要 privileged 模式（已在配置中设置）

### ⚠️ 潜在问题

1. **如果集群使用 Containerd**: 需要额外配置以暴露 Docker socket，或保留原始配置
2. **权限问题**: 容器内访问 Docker socket 需要足够的权限
3. **Docker 守护进程依赖**: 某些功能依赖于宿主机的 Docker 运行状态

### 🔄 如何回滚到 Containerd

如需恢复到 Containerd，参考原始配置：

**health-check/deployment.yaml:**

```yaml
volumeMounts:
  - mountPath: /custom/containerd/containerd.sock
    name: containerd-sock-volume
volumes:
  - name: containerd-sock-volume
    hostPath:
      path: /run/containerd/containerd.sock
      type: Socket
```

**docker-bench-security/deployment.yaml:**

```yaml
# 添加回以下卷挂载
- name: usr-bin-contained-vol
  mountPath: /usr/bin/containerd
  readOnly: true
- name: usr-bin-runc-vol
  mountPath: /usr/bin/runc
  readOnly: true

# 在 volumes 中添加
- name: usr-bin-contained-vol
  hostPath:
    path: /usr/bin/containerd
- name: usr-bin-runc-vol
  hostPath:
    path: /usr/bin/runc
```

---

## 相关文档

- [Kubernetes Goat 官方文档](https://madhuakula.com/kubernetes-goat)
- [Docker Socket 访问](https://docs.docker.com/engine/install/linux-postinstall/)
- [Kubernetes Volumes 文档](https://kubernetes.io/docs/concepts/storage/volumes/)

---

## 修改历史

| 日期       | 修改内容                    | 修改人 |
| ---------- | --------------------------- | ------ |
| 2025-12-29 | 从 Containerd 迁移到 Docker | System |
