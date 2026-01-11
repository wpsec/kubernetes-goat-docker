# Kubernetes Goat 端口映射

## 官方 7 个端口靶场

| #   | 场景                         | Pod Label                         | 内部端口 | NodePort | 本地端口 |
| --- | ---------------------------- | --------------------------------- | -------- | -------- | -------- |
| 1   | Sensitive keys in code bases | `app=build-code`                  | 3000     | 30001    | **1230** |
| 2   | DIND Exploitation            | `app=health-check`                | 80       | 30002    | **1231** |
| 3   | SSRF in Kubernetes           | `app=internal-proxy`              | 3000     | 30003    | **1232** |
| 4   | Container Escape             | `app=system-monitor`              | 8080     | 30004    | **1233** |
| 5   | Kubernetes Goat Home         | `app=kubernetes-goat-home`        | 80       | 30000    | **1234** |
| 6   | Attacking Private Registry   | `app=poor-registry`               | 5000     | 30005    | **1235** |
| 7   | DoS / Resource Starvation    | `app=hunger-check` (big-monolith) | 8080     | 30006    | **1236** |

## 无需端口的靶场

| #   | 场景               | 访问方式                      |
| --- | ------------------ | ----------------------------- |
| 1   | RBAC 权限提升      | `insecure-rbac` setup.yaml    |
| 2   | Secrets 泄露       | `batch-check` Job             |
| 3   | 镜像投毒           | `build-code` Deployment       |
| 4   | Namespace 横向移动 | `cache-store` Deployment      |
| 5   | 镜像层隐藏数据     | `hidden-in-layers` Deployment |

## 管理端工具（可选）

| 工具     | 功能                |
| -------- | ------------------- |
| Falco    | 运行时安全监控      |
| Kyverno  | Kubernetes 策略引擎 |
| Tetragon | eBPF 安全观测       |

## 部署验证

```bash
# 端口检查
for p in {1230..1236}; do
  curl -o /dev/null -s -w ":%s -> %{http_code}\n" http://192.168.6.130:$p/
done

# Pod 状态
kubectl get pod -A

# Service 状态
kubectl get svc -A
```
