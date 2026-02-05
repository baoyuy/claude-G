#!/bin/bash

# claude-G 一键安装脚本
# 用法: curl -fsSL https://raw.githubusercontent.com/baoyuy/claude-G/main/install.sh | bash

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 打印带颜色的消息
info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# 检查命令是否存在
check_command() {
    if ! command -v "$1" &> /dev/null; then
        return 1
    fi
    return 0
}

# 生成随机字符串
generate_random_string() {
    local length=$1
    cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w "$length" | head -n 1
}

echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                                                            ║${NC}"
echo -e "${GREEN}║              claude-G 一键安装脚本                         ║${NC}"
echo -e "${GREEN}║              Claude API 中转服务                           ║${NC}"
echo -e "${GREEN}║                                                            ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# 检查是否为root用户
if [ "$EUID" -ne 0 ]; then
    warn "建议使用 root 用户运行此脚本"
fi

# 检查系统
info "检查系统环境..."
OS=$(uname -s)
if [ "$OS" != "Linux" ]; then
    error "此脚本仅支持 Linux 系统"
fi

# 检查Docker
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

# 检查Docker Compose
info "检查 Docker Compose..."
if ! check_command docker-compose && ! docker compose version &> /dev/null; then
    warn "Docker Compose 未安装，正在安装..."
    # 尝试安装 docker-compose-plugin
    if check_command apt-get; then
        apt-get update && apt-get install -y docker-compose-plugin
    elif check_command yum; then
        yum install -y docker-compose-plugin
    else
        # 手动安装
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

# 创建安装目录
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

# 下载项目
info "下载 claude-G..."
if [ -d ".git" ]; then
    info "检测到已有安装，正在更新..."
    git pull origin main
else
    git clone https://github.com/baoyuy/claude-G.git .
fi
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
    docker compose up -d
else
    docker-compose up -d
fi

# 等待服务启动
info "等待服务启动..."
sleep 10

# 检查服务状态
if curl -s http://localhost:3000/health > /dev/null 2>&1; then
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
echo -e "  ${BLUE}管理界面:${NC} http://${SERVER_IP}:3000/web"
echo -e "  ${BLUE}安装目录:${NC} ${INSTALL_DIR}"
echo ""
echo -e "  ${YELLOW}首次使用请运行以下命令初始化并查看管理员账号密码:${NC}"
echo -e "  cd ${INSTALL_DIR} && docker compose exec claude-relay npm run setup"
echo ""
echo -e "  ${YELLOW}已初始化过？再次运行上述命令即可查看账号密码${NC}"
echo ""
echo -e "  ${YELLOW}常用命令:${NC}"
echo -e "  查看日志: docker compose logs -f"
echo -e "  重启服务: docker compose restart"
echo -e "  停止服务: docker compose down"
echo -e "  更新服务: curl -fsSL https://raw.githubusercontent.com/baoyuy/claude-G/main/scripts/update.sh | bash"
echo ""
