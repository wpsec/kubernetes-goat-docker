# Kubernetes Goat 端口映射（Kind 优化版）

## 官方 7 个端口靶场

通过 Kind 的 `extraPortMappings` 将宿主机端口映射到集群节点的 `NodePort`。

| #   | 场景                              | Pod Label                  | 内部端口 | NodePort  | 本地端口 |
| :-- | :-------------------------------- | :------------------------- | :------- | :-------- | :------- |
| 1   | 敏感信息泄露 (Sensitive keys)     | `app=build-code`           | 3000     | **30001** | **1230** |
| 2   | DIND 漏洞逃逸 (DIND Exploitation) | `app=health-check`         | 80       | **30002** | **1231** |
| 3   | SSRF 漏洞 (SSRF in K8s)           | `app=internal-proxy`       | 3000     | **30003** | **1232** |
| 4   | 容器逃逸 (Container Escape)       | `app=system-monitor`       | 8080     | **30004** | **1233** |
| 5   | 靶场管理首页 (Goat Home)          | `app=kubernetes-goat-home` | 80       | **30000** | **1234** |
| 6   | 私有仓库攻击 (Private Registry)   | `app=poor-registry`        | 5000     | **30005** | **1235** |
| 7   | 资源耗尽 DoS (Hunger Check)       | `app=hunger-check`         | 8080     | **30006** | **1236** |

---

## 无需端口的靶场

这些场景主要通过 `kubectl` 执行、日志分析或容器内渗透完成。

| #   | 场景               | 核心资源 / 访问方式                 | 关键文件                                     |
| :-- | :----------------- | :---------------------------------- | :------------------------------------------- |
| 1   | RBAC 权限提升      | ServiceAccount & ClusterRoleBinding | `insecure-rbac/setup.yaml`                   |
| 2   | Secrets 泄露       | 分析 Job 挂载或环境变量             | `batch-check/job.yaml`                       |
| 3   | 镜像投毒           | 分析 Deployment 镜像来源            | `build-code/deployment.yaml`                 |
| 4   | Namespace 横向移动 | 跨命名空间访问 Redis                | `cache-store/deployment.yaml`                |
| 5   | 镜像层隐藏数据     | 使用工具分析镜像分层                | `hidden-in-layers/deployment.yaml`           |
| 6   | 基线检查 (Docker)  | 运行安全扫描 DaemonSet              | `docker-bench-security/deployment-kind.yaml` |
| 7   | 基线检查 (K8s)     | 运行安全扫描 Job                    | `kube-bench-security/node-job-kind.yaml`     |

---

## 管理端工具（可选）

| 工具         | 功能                                          |
| :----------- | :-------------------------------------------- |
| **Falco**    | 运行时安全监控，检测异常系统调用              |
| **Kyverno**  | 策略管理，如拦截特定 Namespace 的 `exec` 操作 |
| **Tetragon** | 基于 eBPF 的实时安全观测与拦截                |

---

## 部署验证

```bash
# 1. 验证所有 NodePort 服务状态
kubectl get svc -A | grep NodePort

# 2. 端口连通性检查 (请确保已创建 Kind 映射)
for p in {1230..1236}; do
  # 简洁有效的注释：测试宿主机端口连通性及响应码
  curl -o /dev/null -s -w "Port $p -> %{http_code}\n" [http://127.0.0.1](http://127.0.0.1):$p/
done

# 3. 确认核心靶场 Pod 运行状态
kubectl get pod -A -l "app in (build-code, health-check, internal-proxy, system-monitor, kubernetes-goat-home, poor-registry, hunger-check)"
```
