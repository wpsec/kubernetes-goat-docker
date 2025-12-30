# kubernetes-goat+docker

因为最近在学习k8s相关内容

考虑到国内绝大部分公司的项目依旧习惯使用docker，所以将kubernetes-goat的Container容器切换为docker



# Kubernetes Goat 
✨ The Kubernetes Goat is designed to be an intentionally vulnerable cluster environment to learn and practice Kubernetes security 🚀 

后续会发布一些关于k8s集群、云原生安全相关内容，欢迎关注公众号

<!-- 这是一张图片，ocr 内容为： -->
![](/Users/eric.sy.wu/Documents/公众号/扫码_搜索联合传播样式-白色版.png)<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2025/png/27875807/1767086980777-389f0fe9-9f2e-4705-810a-08bf4045d2cb.png)



## 自行搭建
自行搭建k8s集群环境～

克隆环境

[https://github.com/wpsec/kubernetes-goat-docker.git](https://github.com/wpsec/kubernetes-goat-docker.git)

镜像问题，所有 node 打上代理，然后进行拉取

```yaml
# node
sudo mkdir -p /etc/systemd/system/docker.service.d

sudo tee /etc/systemd/system/docker.service.d/http-proxy.conf <<EOF
[Service]
Environment="HTTP_PROXY=http://192.168.10.107:7897"
Environment="HTTPS_PROXY=http://192.168.10.107:7897"
Environment="NO_PROXY=localhost,127.0.0.1,.cluster.local,.svc.cluster.local,10.96.0.0/12,192.168.0.0/16,172.17.0.0/16"
EOF

sudo systemctl daemon-reload
sudo systemctl restart docker
sudo systemctl show docker --property=Environment
```



HELM

```yaml

HELM_VER="v3.12.0"
curl -fsSL https://get.helm.sh/helm-${HELM_VER}-linux-amd64.tar.gz -o /tmp/helm.tgz
tar -zxvf /tmp/helm.tgz -C /tmp
mv /tmp/linux-amd64/helm /usr/local/bin/helm
chmod +x /usr/local/bin/helm
helm version

cd /root/kubernetes-goat
helm install metadata-db ./scenarios/metadata-db --namespace default --create-namespace -f ./scenarios/metadata-db/values.yaml
```

启动服务

```yaml
./setup-kubernetes-goat.sh
```

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2025/png/27875807/1764768589433-99b42308-9103-4c9c-88e9-d9b538651767.png)

端口转发

[http://xxxx:1234](http://xxxx:1234)

```yaml
./access-kubernetes-goat.sh
```

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2025/png/27875807/1765165032125-47508835-9950-44c2-b0bb-9bc07095f3ff.png)

如果不用了，删除

```yaml
./teardown-kubernetes-goat.sh
```





## K8s一主两从环境
如果不会想自己搭建，我搭好了，可以直接下载使用

关注公众号，回复：**k8s **获取下载链接

这里没有使用k3s或其它环境，用的一主两从（简化为一主一从，虚拟机大小越35G）的原生k8s，最大化模拟真实环境，因为我后面会在这个环境下做红蓝两个视角的学习研究

镜像是从madhuakula拉的，master和node都是两张网卡，第一张网卡用于集群、固定IP地址、第二张网卡用于桥接、NAT都可以，方便访问。

集群内网IP：

新建一张虚拟网卡，什么模式都可以

网段：192.168.66.200/24（⚠️网关为200）

master：192.168.66.11

Node1：192.168.66.12

账户名/密码

root/toor

<!-- 这是一张图片，ocr 内容为： -->
![](https://cdn.nlark.com/yuque/0/2025/png/27875807/1767086968630-596b52a4-824b-4711-aa3d-e5da48a46f70.png)

### 灵镜
推荐使用灵镜进行搭建（待补充）



### 使用
```bash
# 开启
cd /root/kubernetes-goat/
./setup-kubernetes-goat.sh
kubectl get pod
# 关闭
cd /root/kubernetes-goat/
./teardown-kubernetes-goat.sh

# 端口转发
./access-kubernetes-goat.sh
```



### 摸鱼信安交流群
失效请添加公众号回复：摸鱼群

![](https://cdn.nlark.com/yuque/0/2025/jpeg/27875807/1767087024537-fcc51036-3e41-42bd-9261-e18febd068c4.jpeg)