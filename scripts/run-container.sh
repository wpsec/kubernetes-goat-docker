#!/usr/bin/env bash
set -euo pipefail

# run-container.sh
# 仅用于运行已构建的 Docker 镜像
# 不进行镜像构建，假设镜像已经存在

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

# 配置
IMAGE_TAG="kind-k8s-goat-moyusec-lingjing:v3.0"
CONTAINER_NAME="kind-k8s-goat"

# 解析命令行参数
ACTION="start"
while [[ $# -gt 0 ]]; do
  case $1 in
    start)
      ACTION="start"
      shift
      ;;
    stop)
      ACTION="stop"
      shift
      ;;
    restart)
      ACTION="restart"
      shift
      ;;
    logs)
      ACTION="logs"
      shift
      ;;
    shell)
      ACTION="shell"
      shift
      ;;
    -h|--help)
      show_help
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      show_help
      exit 1
      ;;
  esac
done

show_help() {
  cat <<EOF
用法: $0 [命令] [选项]

用途: 运行或管理已构建的 Docker 容器

命令:
  start       启动容器（默认）
  stop        停止容器
  restart     重启容器
  logs        查看容器日志（实时跟踪）
  shell       进入容器 Shell
  -h, --help  显示此帮助信息

示例:
  # 启动容器
  bash scripts/run-container.sh

  # 停止容器
  bash scripts/run-container.sh stop

  # 重启容器
  bash scripts/run-container.sh restart

  # 查看日志
  bash scripts/run-container.sh logs

  # 进入容器 Shell
  bash scripts/run-container.sh shell

EOF
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    return 1
  fi
  return 0
}

# Check docker (required)
if ! require_cmd docker; then
  echo "ERROR: docker is required but not found" >&2
  exit 2
fi

# 检查镜像是否存在
if ! docker image inspect "$IMAGE_TAG" >/dev/null 2>&1; then
  echo "ERROR: Docker image '$IMAGE_TAG' not found" >&2
  echo ""
  echo "请先运行以下命令构建镜像:"
  echo "  bash scripts/build-image.sh"
  exit 1
fi

case "$ACTION" in
  start)
    echo "启动容器 $CONTAINER_NAME..."
    
    # 检查容器是否已存在
    if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
      echo "容器已存在，检查其状态..."
      if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        echo "✓ 容器已在运行中"
        echo ""
        echo "查看日志:"
        echo "  bash scripts/run-container.sh logs"
        exit 0
      else
        echo "容器已停止，正在启动..."
        docker start "$CONTAINER_NAME"
      fi
    else
      echo "创建并启动新容器..."
      docker run --privileged -d --name "$CONTAINER_NAME" \
        --memory="4g" --cpus="4" \
        -p 1230:1230 -p 1231:1231 -p 1232:1232 -p 1233:1233 \
        -p 1234:1234 -p 1235:1235 -p 1236:1236 -p 1237:1237 \
        "$IMAGE_TAG"
    fi
    
    echo ""
    echo "=========================================="
    echo "✅ 容器已启动"
    echo "=========================================="
    echo ""
    echo "容器名称: $CONTAINER_NAME"
    echo "镜像标签: $IMAGE_TAG"
    echo ""
    echo "常用命令:"
    echo "  # 查看日志"
    echo "  bash scripts/run-container.sh logs"
    echo ""
    echo "  # 进入容器"
    echo "  bash scripts/run-container.sh shell"
    echo ""
    echo "  # 停止容器"
    echo "  bash scripts/run-container.sh stop"
    echo ""
    ;;

  stop)
    echo "停止容器 $CONTAINER_NAME..."
    
    if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
      docker stop "$CONTAINER_NAME"
      echo "✓ 容器已停止"
    else
      echo "容器未在运行中"
    fi
    ;;

  restart)
    echo "重启容器 $CONTAINER_NAME..."
    
    if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
      docker restart "$CONTAINER_NAME"
      echo "✓ 容器已重启"
      echo ""
      echo "查看日志:"
      echo "  bash scripts/run-container.sh logs"
    else
      echo "容器不存在，正在创建并启动..."
      docker run --privileged -d --name "$CONTAINER_NAME" \
        --memory="4g" --cpus="4" \
        -p 1230:1230 -p 1231:1231 -p 1232:1232 -p 1233:1233 \
        -p 1234:1234 -p 1235:1235 -p 1236:1236 -p 1237:1237 \
        "$IMAGE_TAG"
      echo "✓ 容器已创建并启动"
    fi
    ;;

  logs)
    echo "显示容器日志（Ctrl+C 退出）..."
    echo ""
    if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
      docker logs -f "$CONTAINER_NAME"
    else
      echo "ERROR: 容器不存在或未运行" >&2
      exit 1
    fi
    ;;

  shell)
    echo "进入容器 Shell..."
    echo ""
    if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
      docker exec -it "$CONTAINER_NAME" /bin/bash
    else
      echo "ERROR: 容器未在运行中，请先启动容器" >&2
      echo ""
      echo "启动容器:"
      echo "  bash scripts/run-container.sh start"
      exit 1
    fi
    ;;

  *)
    echo "Unknown action: $ACTION" >&2
    show_help
    exit 1
    ;;
esac
