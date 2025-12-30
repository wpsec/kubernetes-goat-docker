#!/bin/bash
# Docker + Kubernetes Goat 兼容性快速检查脚本
# 用途: 在部署前验证环境和配置

set -e

echo "================================"
echo "Docker + Kubernetes Goat 兼容性检查"
echo "================================"
echo ""

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 检查计数
PASSED=0
FAILED=0
WARNING=0

# 检查函数
check_command() {
    if command -v $1 &> /dev/null; then
        echo -e "${GREEN}✅${NC} $1 已安装"
        ((PASSED++))
        return 0
    else
        echo -e "${RED}❌${NC} $1 未安装"
        ((FAILED++))
        return 1
    fi
}

check_file() {
    if [ -f "$1" ]; then
        echo -e "${GREEN}✅${NC} $1 存在"
        ((PASSED++))
        return 0
    else
        echo -e "${RED}❌${NC} $1 不存在"
        ((FAILED++))
        return 1
    fi
}

check_socket() {
    if [ -S "$1" ]; then
        echo -e "${GREEN}✅${NC} $1 可访问"
        ((PASSED++))
        return 0
    else
        echo -e "${YELLOW}⚠️${NC} $1 不存在 (可能在 Kubernetes 节点内部可用)"
        ((WARNING++))
        return 1
    fi
}

# ====================
# 1. 检查基础命令
# ====================
echo -e "${BLUE}[1] 检查基础命令${NC}"
check_command "kubectl"
check_command "helm"
check_command "docker"
echo ""

# ====================
# 2. 检查 kubectl 连接
# ====================
echo -e "${BLUE}[2] 检查 Kubernetes 集群${NC}"
if kubectl cluster-info &> /dev/null; then
    echo -e "${GREEN}✅${NC} Kubernetes 集群可访问"
    ((PASSED++))
    
    # 获取节点信息
    NODE_COUNT=$(kubectl get nodes --no-headers 2>/dev/null | wc -l)
    echo -e "${GREEN}✅${NC} 集群节点数: $NODE_COUNT"
    ((PASSED++))
else
    echo -e "${RED}❌${NC} Kubernetes 集群不可访问"
    ((FAILED++))
fi
echo ""

# ====================
# 3. 检查 Docker socket
# ====================
echo -e "${BLUE}[3] 检查 Docker/CRI Docker Socket${NC}"
if [ -S "/var/run/docker.sock" ]; then
    echo -e "${GREEN}✅${NC} /var/run/docker.sock 可访问"
    ((PASSED++))
elif [ -S "/var/run/cri-dockerd.sock" ]; then
    echo -e "${GREEN}✅${NC} /var/run/cri-dockerd.sock (CRI Docker) 可访问"
    ((PASSED++))
else
    echo -e "${YELLOW}⚠️${NC} 未找到 Docker socket"
    echo "   检查路径:"
    echo "   - /var/run/docker.sock (标准 Docker)"
    echo "   - /var/run/cri-dockerd.sock (CRI Docker)"
    echo "   - /run/containerd/containerd.sock (Containerd)"
    ((WARNING++))
fi
echo ""

# ====================
# 4. 检查项目文件
# ====================
echo -e "${BLUE}[4] 检查 Kubernetes Goat 项目文件${NC}"
check_file "setup-kubernetes-goat.sh"
check_file "access-kubernetes-goat.sh"
check_file "teardown-kubernetes-goat.sh"
check_file "scenarios/health-check/deployment.yaml"
check_file "scenarios/docker-bench-security/deployment.yaml"
check_file "scenarios/metadata-db/Chart.yaml"
echo ""

# ====================
# 5. 检查配置文件
# ====================
echo -e "${BLUE}[5] 检查 Docker/CRI Docker 迁移配置${NC}"

# 检查是否配置了 cri-docker socket
if grep -q "/var/run/cri-dockerd.sock" scenarios/health-check/deployment.yaml; then
    echo -e "${GREEN}✅${NC} health-check 已配置为使用 CRI Docker socket"
    ((PASSED++))
elif grep -q "/var/run/docker.sock" scenarios/health-check/deployment.yaml; then
    echo -e "${GREEN}✅${NC} health-check 已配置为使用 Docker socket"
    ((PASSED++))
else
    echo -e "${RED}❌${NC} health-check 未正确配置 socket"
    ((FAILED++))
fi

if grep -q "/var/run/cri-dockerd.sock" scenarios/docker-bench-security/deployment.yaml; then
    echo -e "${GREEN}✅${NC} docker-bench-security 已配置为使用 CRI Docker socket"
    ((PASSED++))
elif grep -q "/var/run/docker.sock" scenarios/docker-bench-security/deployment.yaml; then
    echo -e "${GREEN}✅${NC} docker-bench-security 已配置为使用 Docker socket"
    ((PASSED++))
else
    echo -e "${RED}❌${NC} docker-bench-security 未正确配置 socket"
    ((FAILED++))
fi
echo ""

# ====================
# 6. 检查镜像可用性
# ====================
echo -e "${BLUE}[6] 检查容器镜像可用性${NC}"

IMAGES=(
    "madhuakula/k8s-goat-health-check"
    "madhuakula/k8s-goat-build-code"
    "madhuakula/k8s-goat-home"
    "madhuakula/hacker-container"
)

for image in "${IMAGES[@]}"; do
    if docker image inspect "$image" &>/dev/null; then
        echo -e "${GREEN}✅${NC} $image 已在本地"
        ((PASSED++))
    else
        echo -e "${YELLOW}⚠️${NC} $image 需要拉取 (运行时会自动拉取)"
        ((WARNING++))
    fi
done
echo ""

# ====================
# 7. 检查资源可用性
# ====================
echo -e "${BLUE}[7] 检查系统资源${NC}"

# Docker 信息
if docker info &>/dev/null; then
    echo -e "${GREEN}✅${NC} Docker 守护进程运行中"
    ((PASSED++))
    
    # 获取可用存储
    STORAGE=$(docker info 2>/dev/null | grep "Storage Driver" | awk '{print $3}')
    echo "   存储驱动: $STORAGE"
else
    echo -e "${RED}❌${NC} Docker 守护进程未运行"
    ((FAILED++))
fi

# Kubernetes 资源
if [ "$NODE_COUNT" -gt 0 ]; then
    echo -e "${GREEN}✅${NC} Kubernetes 集群资源可用"
    ((PASSED++))
fi
echo ""

# ====================
# 8. 检查命名空间
# ====================
echo -e "${BLUE}[8] 检查 Kubernetes 命名空间${NC}"

REQUIRED_NS=("default" "kube-system")
for ns in "${REQUIRED_NS[@]}"; do
    if kubectl get namespace "$ns" &>/dev/null; then
        echo -e "${GREEN}✅${NC} 命名空间 '$ns' 存在"
        ((PASSED++))
    else
        echo -e "${RED}❌${NC} 命名空间 '$ns' 不存在"
        ((FAILED++))
    fi
done
echo ""

# ====================
# 9. 检查 RBAC
# ====================
echo -e "${BLUE}[9] 检查 RBAC 配置${NC}"

if kubectl auth can-i create deployments --as=system:serviceaccount:default:default &>/dev/null; then
    echo -e "${YELLOW}⚠️${NC} 默认 ServiceAccount 有高权限 (符合预期)"
    ((WARNING++))
else
    echo -e "${YELLOW}⚠️${NC} 默认 ServiceAccount 权限受限 (可能影响某些场景)"
    ((WARNING++))
fi
echo ""

# ====================
# 10. 检查目录权限
# ====================
echo -e "${BLUE}[10] 检查目录权限${NC}"

if [ -w . ]; then
    echo -e "${GREEN}✅${NC} 当前目录可写"
    ((PASSED++))
else
    echo -e "${RED}❌${NC} 当前目录不可写"
    ((FAILED++))
fi
echo ""

# ====================
# 总结
# ====================
echo "================================"
echo "检查总结"
echo "================================"
echo -e "${GREEN}通过: $PASSED${NC}"
echo -e "${YELLOW}警告: $WARNING${NC}"
echo -e "${RED}失败: $FAILED${NC}"
echo ""

if [ $FAILED -eq 0 ]; then
    if [ $WARNING -eq 0 ]; then
        echo -e "${GREEN}✅ 所有检查通过！可以开始部署${NC}"
        echo ""
        echo "后续步骤:"
        echo "1. 运行: bash setup-kubernetes-goat.sh"
        echo "2. 等待 Pod 就绪: kubectl get pods -w"
        echo "3. 开启访问: bash access-kubernetes-goat.sh"
        echo "4. 访问: http://127.0.0.1:1234"
        exit 0
    else
        echo -e "${YELLOW}⚠️ 检查通过但有警告。可能需要处理某些问题${NC}"
        exit 1
    fi
else
    echo -e "${RED}❌ 检查失败。请解决上述问题后重试${NC}"
    echo ""
    echo "常见问题解决:"
    echo ""
    echo "1️⃣ kubectl 未安装/配置:"
    echo "   https://kubernetes.io/docs/tasks/tools/install-kubectl/"
    echo ""
    echo "2️⃣ Kubernetes 集群不可用:"
    echo "   请确保 kubeconfig 正确配置"
    echo "   运行: export KUBECONFIG=~/.kube/config"
    echo ""
    echo "3️⃣ Docker socket 不存在:"
    echo "   如果集群使用 Containerd，创建软链接:"
    echo "   sudo ln -s /run/containerd/containerd.sock /var/run/docker.sock"
    echo ""
    echo "4️⃣ Docker 未运行:"
    echo "   启动 Docker: sudo systemctl start docker (Linux)"
    echo "   或启动 Docker Desktop (Mac/Windows)"
    echo ""
    exit 1
fi
