#!/bin/bash

# claude-G 一键更新脚本
# 用法: curl -fsSL https://raw.githubusercontent.com/baoyuy/claude-G/main/scripts/update.sh | bash
# 强制更新: curl -fsSL https://raw.githubusercontent.com/baoyuy/claude-G/main/scripts/update.sh | bash -s -- --force

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# 解析参数
FORCE_UPDATE=false
for arg in "$@"; do
    case $arg in
        --force|-f)
            FORCE_UPDATE=true
            ;;
    esac
done

echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║              claude-G 一键更新脚本                         ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# 查找安装目录（支持多种安装路径）
find_install_dir() {
    # 优先使用环境变量
    if [ -n "$INSTALL_DIR" ] && [ -d "$INSTALL_DIR" ]; then
        echo "$INSTALL_DIR"
        return
    fi

    # 检查常见安装路径
    local paths=(
        "/opt/claude-G/claude-relay-service"
        "/opt/claude-G"
        "/root/claude-G/claude-relay-service"
        "/root/claude-G"
        "$HOME/claude-G/claude-relay-service"
        "$HOME/claude-G"
    )

    for p in "${paths[@]}"; do
        if [ -d "$p" ] && [ -f "$p/docker-compose.yml" ]; then
            echo "$p"
            return
        fi
    done

    # 未找到
    echo ""
}

INSTALL_DIR=$(find_install_dir)

if [ -z "$INSTALL_DIR" ]; then
    error "未找到 claude-G 安装目录，请设置 INSTALL_DIR 环境变量\n  例如: INSTALL_DIR=/opt/claude-G/claude-relay-service bash update.sh"
fi

info "安装目录: $INSTALL_DIR"
cd "$INSTALL_DIR"

# 确定项目根目录（可能是 claude-G 或 claude-relay-service）
PROJECT_ROOT="$INSTALL_DIR"
if [ ! -d ".git" ]; then
    # 尝试上级目录
    if [ -d "../.git" ]; then
        PROJECT_ROOT=$(dirname "$INSTALL_DIR")
    else
        error "当前目录不是 git 仓库，无法更新"
    fi
fi

# 获取当前版本和commit
CURRENT_VERSION=$(cat VERSION 2>/dev/null || echo "unknown")
cd "$PROJECT_ROOT"
CURRENT_COMMIT=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
info "当前版本: $CURRENT_VERSION (commit: $CURRENT_COMMIT)"

# 暂存本地修改
info "检查本地修改..."
if [ -n "$(git status --porcelain)" ]; then
    info "暂存本地修改..."
    git stash push -m "Auto stash before update $(date +%Y%m%d_%H%M%S)" 2>/dev/null || true
fi

# 拉取最新代码
info "检查远程更新..."
git fetch origin main

# 获取远程最新commit
REMOTE_COMMIT=$(git rev-parse --short origin/main 2>/dev/null || echo "unknown")

# 比较commit判断是否有更新
if [ "$CURRENT_COMMIT" = "$REMOTE_COMMIT" ] && [ "$FORCE_UPDATE" = false ]; then
    success "当前已是最新版本 ($CURRENT_VERSION, commit: $CURRENT_COMMIT)"
    echo ""
    echo -e "  ${YELLOW}提示:${NC} 如需强制重新部署，请使用 --force 参数"
    echo ""
    exit 0
fi

# 有更新或强制更新
if [ "$CURRENT_COMMIT" != "$REMOTE_COMMIT" ]; then
    info "发现新提交: $CURRENT_COMMIT -> $REMOTE_COMMIT"
else
    info "强制更新模式"
fi

# 拉取最新代码
info "拉取最新代码..."
git reset --hard origin/main

# 获取新版本
cd "$INSTALL_DIR"
NEW_VERSION=$(cat VERSION 2>/dev/null || echo "unknown")
cd "$PROJECT_ROOT"
NEW_COMMIT=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")

if [ "$CURRENT_VERSION" != "$NEW_VERSION" ]; then
    info "版本更新: $CURRENT_VERSION -> $NEW_VERSION"
fi

# 回到服务目录
cd "$INSTALL_DIR"

# 重新部署服务（拉取新镜像并重建）
info "重新部署服务..."
if docker compose version &> /dev/null; then
    docker compose pull
    docker compose up -d --force-recreate
else
    docker-compose pull
    docker-compose up -d --force-recreate
fi

# 等待服务启动
info "等待服务启动..."
SERVICE_OK=false
for i in {1..30}; do
    if curl -s http://localhost:3000/health > /dev/null 2>&1; then
        SERVICE_OK=true
        break
    fi
    sleep 1
done

if [ "$SERVICE_OK" = true ]; then
    success "服务重启成功！"
else
    warn "服务启动超时，请手动检查日志: docker compose logs -f"
fi

echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                    更新完成！                              ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${BLUE}版本:${NC} $CURRENT_VERSION -> $NEW_VERSION"
echo -e "  ${BLUE}提交:${NC} $CURRENT_COMMIT -> $NEW_COMMIT"
echo -e "  ${BLUE}查看日志:${NC} cd $INSTALL_DIR && docker compose logs -f"
echo ""
