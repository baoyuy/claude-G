#!/bin/bash

# claude-G 一键更新脚本
# 用法: curl -fsSL https://raw.githubusercontent.com/baoyuy/claude-G/main/scripts/update.sh | bash

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

echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║              claude-G 一键更新脚本                         ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# 查找安装目录
INSTALL_DIR=${INSTALL_DIR:-"/opt/claude-G"}

if [ ! -d "$INSTALL_DIR" ]; then
    if [ -d "/root/claude-G" ]; then
        INSTALL_DIR="/root/claude-G"
    elif [ -d "$HOME/claude-G" ]; then
        INSTALL_DIR="$HOME/claude-G"
    else
        error "未找到 claude-G 安装目录，请设置 INSTALL_DIR 环境变量"
    fi
fi

info "安装目录: $INSTALL_DIR"
cd "$INSTALL_DIR"

# 检查是否为git仓库
if [ ! -d ".git" ]; then
    error "当前目录不是 git 仓库，无法更新"
fi

# 获取当前版本
CURRENT_VERSION=$(cat VERSION 2>/dev/null || echo "unknown")
info "当前版本: $CURRENT_VERSION"

# 拉取最新代码
info "拉取最新代码..."
git fetch origin main
git reset --hard origin/main

# 获取新版本
NEW_VERSION=$(cat VERSION 2>/dev/null || echo "unknown")

if [ "$CURRENT_VERSION" = "$NEW_VERSION" ]; then
    success "当前已是最新版本 ($CURRENT_VERSION)"
    echo ""
    exit 0
fi

info "发现新版本: $CURRENT_VERSION -> $NEW_VERSION"

# 检测Docker Compose命令
if docker compose version &> /dev/null; then
    DC="docker compose"
else
    DC="docker-compose"
fi

# 构建前端（在容器内执行）
info "构建前端资源..."
$DC exec -T claude-relay npm run build:web 2>/dev/null || {
    warn "容器内构建失败，尝试重启后构建..."
    $DC up -d --force-recreate
    sleep 5
    $DC exec -T claude-relay npm run build:web 2>/dev/null || warn "前端构建跳过"
}

# 重启服务
info "重启服务..."
$DC restart

# 等待服务启动
info "等待服务启动..."
for i in {1..10}; do
    if curl -s http://localhost:3000/health > /dev/null 2>&1; then
        success "服务重启成功！"
        break
    fi
    sleep 1
done

echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                    更新完成！                              ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${BLUE}版本:${NC} $CURRENT_VERSION -> $NEW_VERSION"
echo -e "  ${BLUE}查看日志:${NC} cd $INSTALL_DIR && docker compose logs -f"
echo ""
