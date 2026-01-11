#!/bin/bash
# 容器启动入口脚本
set -e

echo "启动内部 Docker 守护进程..."
dockerd-entrypoint.sh > /var/log/dockerd.log 2>&1 &

# 等待 Docker 服务启动就绪
until docker info >/dev/null 2>&1; do
    echo "等待 Docker 启动..."
    sleep 2
done

# 调用靶场部署逻辑脚本
bash /usr/local/bin/setup-kubernetes-goat.sh

# 保持容器前台运行
tail -f /dev/null