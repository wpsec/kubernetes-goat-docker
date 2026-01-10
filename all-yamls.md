# Kubernetes YAML 汇总

## scenarios/batch-check/job.yaml

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: batch-check-job
spec:
  template:
    metadata:
      name: batch-check-job
    spec:
      # nodeSelector:
      #   kubernetes.io/hostname: k8s-node01
      containers:
        - name: batch-check
          image: madhuakula/k8s-goat-batch-check
          imagePullPolicy: IfNotPresent
          # command:
          #  - "bin/sh"
          #  - "-c"
          #  - "htop"
      restartPolicy: Never
```

## scenarios/build-code/deployment.yaml

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: build-code-deployment
  namespace: default
spec:
  selector:
    matchLabels:
      app: build-code
  template:
    metadata:
      labels:
        app: build-code
    spec:
      # nodeSelector:
      #   kubernetes.io/hostname: k8s-node01
      containers:
        - name: build-code
          image: madhuakula/k8s-goat-build-code
          imagePullPolicy: IfNotPresent
          resources:
            limits:
              memory: "50Mi"
              cpu: "20m"
          ports:
            - containerPort: 3000
---
apiVersion: v1
kind: Service
metadata:
  name: build-code-service
  namespace: default
spec:
  type: NodePort
  ports:
    - protocol: TCP
      port: 3000
      targetPort: 3000
      nodePort: 30003
  selector:
    app: build-code
```

## scenarios/cache-store/deployment.yaml

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: secure-middleware
---
apiVersion: v1
kind: Service
metadata:
  namespace: secure-middleware
  name: cache-store-service
spec:
  ports:
    - protocol: TCP
      port: 6379
      targetPort: 6379
  selector:
    app: cache-store
---
apiVersion: apps/v1
kind: Deployment
metadata:
  namespace: secure-middleware
  name: cache-store-deployment
  labels:
    app: cache-store
spec:
  selector:
    matchLabels:
      app: cache-store
  template:
    metadata:
      labels:
        app: cache-store
    spec:
      # nodeSelector:
      #   kubernetes.io/hostname: k8s-node01
      containers:
        - name: cache-store
          image: madhuakula/k8s-goat-cache-store
          imagePullPolicy: IfNotPresent
          ports:
            - containerPort: 6379
```

## scenarios/health-check/deployment.yaml

```yaml
# 注意：修改为使用 CRI Docker 而非 Containerd
# 将容器运行时 socket 从 containerd 改为 cri-docker
# - 之前的路径: /run/containerd/containerd.sock
# - 当前路径: /var/run/cri-dockerd.sock (CRI Docker socket)
# - 备选路径: /var/run/docker.sock (Docker socket)
apiVersion: apps/v1
kind: Deployment
metadata:
  name: health-check-deployment
spec:
  selector:
    matchLabels:
      app: health-check
  template:
    metadata:
      labels:
        app: health-check
    spec:
      # nodeSelector:
      #   kubernetes.io/hostname: k8s-node01
      containers:
        - name: health-check
          image: madhuakula/k8s-goat-health-check
          imagePullPolicy: IfNotPresent
          resources:
            limits:
              memory: "100Mi"
              cpu: "30m"
          ports:
            - containerPort: 80
          # 自定义配置 - 挂载 CRI Docker socket 用于 DIND (Docker-in-Docker)
          # 已修改: 从 containerd socket 改为 cri-docker socket
          securityContext:
            privileged: true
          volumeMounts:
            # 挂载 CRI Docker socket 而不是 containerd
            - mountPath: /var/run/cri-dockerd.sock
              name: docker-sock-volume
      volumes:
        # 已修改: 从 containerd socket (/run/containerd/containerd.sock)
        # 改为 CRI Docker socket (/var/run/cri-dockerd.sock)
        - name: docker-sock-volume
          hostPath:
            path: /var/run/cri-dockerd.sock
            type: Socket
---
apiVersion: v1
kind: Service
metadata:
  name: health-check-service
spec:
  type: NodePort
  ports:
    - protocol: TCP
      port: 80
      targetPort: 80
      nodePort: 30002
  selector:
    app: health-check
```

## scenarios/hunger-check/deployment.yaml

```yaml
---
apiVersion: v1
kind: Namespace
metadata:
  name: big-monolith
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  namespace: big-monolith
  name: secret-reader
rules:
  - apiGroups: [""] # "" indicates the core API group
    resources: ["*"] # all the resources
    verbs: ["get", "watch", "list"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: secret-reader-binding
  namespace: big-monolith
subjects:
  # Kubernetes service account
  - kind: ServiceAccount
    name: big-monolith-sa
roleRef:
  kind: Role
  name: secret-reader
  apiGroup: rbac.authorization.k8s.io
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: big-monolith-sa
  namespace: big-monolith
---
apiVersion: v1
kind: Secret
metadata:
  name: vaultapikey
  namespace: big-monolith
type: Opaque
data:
  k8svaultapikey: azhzLWdvYXQtODUwNTc4NDZhODA0NmEyNWIzNWYzOGYzYTI2NDlkY2U=
---
apiVersion: v1
kind: Secret
metadata:
  name: webhookapikey
  namespace: big-monolith
type: Opaque
data:
  k8swebhookapikey: azhzLWdvYXQtZGZjZjYzMDUzOTU1M2VjZjk1ODZmZGZkYTE5NjhmZWM=
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: hunger-check-deployment
  namespace: big-monolith
spec:
  selector:
    matchLabels:
      app: hunger-check
  template:
    metadata:
      labels:
        app: hunger-check
    spec:
      # nodeSelector:
      #   kubernetes.io/hostname: k8s-node01
      serviceAccountName: big-monolith-sa
      containers:
        - name: hunger-check
          image: madhuakula/k8s-goat-hunger-check
          imagePullPolicy: IfNotPresent
          # resources:
          #   limits:
          #     memory: "1000Gi"
          #   requests:
          #     memory: "1000Gi"
          # command: ["stress-ng"]
          # args: ["--vm", "1", "--vm-bytes", "500M", "--vm-hang", "1", "-v"]
          ports:
            - containerPort: 8080
---
apiVersion: v1
kind: Service
metadata:
  name: hunger-check-service
  namespace: big-monolith
spec:
  type: NodePort
  ports:
    - protocol: TCP
      port: 8080
      targetPort: 8080
      nodePort: 30005
  selector:
    app: hunger-check
```

## scenarios/internal-proxy/deployment.yaml

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: internal-proxy-deployment
  namespace: default
  labels:
    app: internal-proxy
spec:
  selector:
    matchLabels:
      app: internal-proxy
  template:
    metadata:
      labels:
        app: internal-proxy
    spec:
      containers:
        - name: internal-api
          image: madhuakula/k8s-goat-internal-api
          imagePullPolicy: IfNotPresent
          resources:
            limits:
              cpu: 50m
              memory: 60Mi
          ports:
            - containerPort: 3000 # 对应内网 API 服务
        - name: info-app
          image: madhuakula/k8s-goat-info-app
          imagePullPolicy: IfNotPresent
          resources:
            limits:
              cpu: 30m
              memory: 50Mi
          ports:
            - containerPort: 5000 # 对应信息展示应用
---
apiVersion: v1
kind: Service
metadata:
  name: internal-proxy-api-service
  namespace: default
spec:
  type: NodePort
  selector:
    app: internal-proxy
  ports:
    - name: api-port
      protocol: TCP
      port: 3000
      targetPort: 3000
      nodePort: 30004 # 对应宿主机 1233
    - name: info-port
      protocol: TCP
      port: 5000
      targetPort: 5000
      # nodePort: 30007 # 如需开启第二个端口可取消注释
```

## scenarios/kubernetes-goat-home/deployment.yaml

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: kubernetes-goat-home-deployment
  namespace: default
spec:
  selector:
    matchLabels:
      app: kubernetes-goat-home
  template:
    metadata:
      labels:
        app: kubernetes-goat-home
    spec:
      containers:
        - name: kubernetes-goat-home
          image: madhuakula/k8s-goat-home
          # 简体中文注释：修正 1 - 强制使用本地镜像
          imagePullPolicy: IfNotPresent
          resources:
            limits:
              memory: "100Mi" # 稍微调大一点防止 OOM
              cpu: "50m"
          ports:
            - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: kubernetes-goat-home-service
  namespace: default
spec:
  # 简体中文注释：修正 2 - 开启 NodePort 供宿主机访问
  type: NodePort
  ports:
    - protocol: TCP
      port: 80
      targetPort: 80
      nodePort: 30000 # 必须对应 kind-config.yaml 里的 containerPort
  selector:
    app: kubernetes-goat-home
```

## scenarios/poor-registry/deployment.yaml

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: poor-registry-deployment
  namespace: default
spec:
  selector:
    matchLabels:
      app: poor-registry
  template:
    metadata:
      labels:
        app: poor-registry
    spec:
      # nodeSelector:
      #   kubernetes.io/hostname: k8s-node01
      containers:
        - name: poor-registry
          image: madhuakula/k8s-goat-poor-registry
          imagePullPolicy: IfNotPresent
          resources:
            limits:
              memory: "50Mi"
              cpu: "30m"
          ports:
            - containerPort: 5000
---
apiVersion: v1
kind: Service
metadata:
  name: poor-registry-service
  namespace: default
spec:
  ports:
    - protocol: TCP
      port: 5000
      targetPort: 5000
  selector:
    app: poor-registry
```

## scenarios/system-monitor/deployment.yaml

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: goatvault
  namespace: default
type: Opaque
data:
  k8sgoatvaultkey: azhzLWdvYXQtY2QyZGEyNzIyNDU5MWRhMmI0OGVmODM4MjZhOGE2YzM=

---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: system-monitor-deployment
  namespace: default
spec:
  selector:
    matchLabels:
      app: system-monitor
  template:
    metadata:
      labels:
        app: system-monitor
    spec:
      hostPID: true
      hostIPC: true
      #hostNetwork: true
      # nodeSelector:
      #   kubernetes.io/hostname: k8s-node01
      volumes:
        - name: host-filesystem
          hostPath:
            path: /
      containers:
        - name: system-monitor
          image: madhuakula/k8s-goat-system-monitor
          imagePullPolicy: IfNotPresent
          resources:
            limits:
              memory: "50Mi"
              cpu: "20m"
          securityContext:
            allowPrivilegeEscalation: true
            privileged: true
          ports:
            - containerPort: 8080
          volumeMounts:
            - name: host-filesystem
              mountPath: /host-system
          env:
            - name: K8S_GOAT_VAULT_KEY
              valueFrom:
                secretKeyRef:
                  name: goatvault
                  key: k8sgoatvaultkey
---
apiVersion: v1
kind: Service
metadata:
  name: system-monitor-service
  namespace: default
spec:
  ports:
    - protocol: TCP
      port: 8080
      targetPort: 8080
  selector:
    app: system-monitor
```

## scenarios/hidden-in-layers/deployment.yaml

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: hidden-in-layers
spec:
  template:
    metadata:
      name: hidden-in-layers
    spec:
      # nodeSelector:
      #   kubernetes.io/hostname: k8s-node01
      containers:
        - name: hidden-in-layers
          image: madhuakula/k8s-goat-hidden-in-layers
          imagePullPolicy: IfNotPresent
          # command:
          #  - "bin/sh"
          #  - "-c"
          #  - "htop"
      restartPolicy: Never
```
