#!/bin/bash

# claude-G 一键安装脚本
# 用法: curl -fsSL https://raw.githubusercontent.com/baoyuy/claude-G/main/install.sh | bash

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

check_command() {
    command -v "$1" &> /dev/null
}

generate_random_string() {
    local length=$1
    cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w "$length" | head -n 1
}

echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║              claude-G 一键安装脚本                         ║${NC}"
echo -e "${GREEN}║              Claude API 中转服务                           ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# 检查系统
info "检查系统环境..."
OS=$(uname -s)
if [ "$OS" != "Linux" ]; then
    error "此脚本仅支持 Linux 系统"
fi

# 检查 Git
info "检查 Git..."
if ! check_command git; then
    warn "Git 未安装，正在安装..."
    if check_command apt-get; then
        apt-get update && apt-get install -y git
    elif check_command yum; then
        yum install -y git
    elif check_command dnf; then
        dnf install -y git
    else
        error "无法自动安装 Git，请手动安装后重试"
    fi
    success "Git 安装完成"
else
    success "Git 已安装: $(git --version)"
fi

# 检查 Docker
info "检查 Docker..."
if ! check_command docker; then
    warn "Docker 未安装，正在安装..."
    curl -fsSL https://get.docker.com | sh
    systemctl start docker
    systemctl enable docker
    success "Docker 安装完成"
else
    success "Docker 已安装: $(docker --version)"
fi

# 检查 Docker Compose
info "检查 Docker Compose..."
if ! check_command docker-compose && ! docker compose version &> /dev/null; then
    warn "Docker Compose 未安装，正在安装..."
    if check_command apt-get; then
        apt-get update && apt-get install -y docker-compose-plugin
    elif check_command yum; then
        yum install -y docker-compose-plugin
    else
        COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep 'tag_name' | cut -d\" -f4)
        curl -L "https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
        chmod +x /usr/local/bin/docker-compose
    fi
    success "Docker Compose 安装完成"
else
    success "Docker Compose 已安装"
fi

# 设置安装目录
INSTALL_DIR=${INSTALL_DIR:-"/opt/claude-G"}
info "安装目录: $INSTALL_DIR"

# 克隆或更新项目
if [ -d "$INSTALL_DIR/.git" ]; then
    info "检测到已有安装，正在更新..."
    cd "$INSTALL_DIR"
    git fetch origin main
    git reset --hard origin/main
else
    info "下载 claude-G..."
    rm -rf "$INSTALL_DIR"
    git clone https://github.com/baoyuy/claude-G.git "$INSTALL_DIR"
    cd "$INSTALL_DIR"
fi

# 进入服务目录
cd "$INSTALL_DIR/claude-relay-service"
success "项目下载完成"

# 生成环境变量
info "配置环境变量..."
if [ ! -f ".env" ]; then
    JWT_SECRET=$(generate_random_string 64)
    ENCRYPTION_KEY=$(generate_random_string 32)

    cat > .env << EOF
# claude-G 环境配置
# 生成时间: $(date)

# 安全配置（自动生成，请勿泄露）
JWT_SECRET=${JWT_SECRET}
ENCRYPTION_KEY=${ENCRYPTION_KEY}

# 服务配置
PORT=3000
BIND_HOST=0.0.0.0

# Redis配置
REDIS_PASSWORD=

# 日志级别
LOG_LEVEL=info
EOF
    success "环境变量配置完成"
else
    warn ".env 文件已存在，跳过配置"
fi

# 创建数据目录
mkdir -p data logs redis_data

# 启动服务
info "启动服务..."
if docker compose version &> /dev/null; then
    docker compose pull
    docker compose up -d
else
    docker-compose pull
    docker-compose up -d
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
    success "服务启动成功！"
else
    warn "服务可能还在启动中，请稍后检查"
fi

# 获取服务器IP
SERVER_IP=$(curl -s ifconfig.me 2>/dev/null || curl -s ip.sb 2>/dev/null || echo "YOUR_SERVER_IP")

echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                    安装完成！                              ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${BLUE}管理界面:${NC} http://${SERVER_IP}:3000/admin-next/"
echo -e "  ${BLUE}安装目录:${NC} ${INSTALL_DIR}/claude-relay-service"
echo ""
echo -e "  ${YELLOW}首次使用请运行以下命令初始化并查看管理员账号密码:${NC}"
echo -e "  cd ${INSTALL_DIR}/claude-relay-service && docker compose exec claude-relay npm run setup"
echo ""
echo -e "  ${YELLOW}已初始化过？再次运行上述命令即可查看账号密码${NC}"
echo ""
echo -e "  ${YELLOW}常用命令:${NC}"
echo -e "  查看日志: cd ${INSTALL_DIR}/claude-relay-service && docker compose logs -f"
echo -e "  重启服务: cd ${INSTALL_DIR}/claude-relay-service && docker compose restart"
echo -e "  停止服务: cd ${INSTALL_DIR}/claude-relay-service && docker compose down"
echo -e "  更新服务: curl -fsSL https://raw.githubusercontent.com/baoyuy/claude-G/main/scripts/update.sh | bash"
echo ""
