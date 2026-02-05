# claude-G

> Claude API 中转服务

## 简介

这是一个自用的 Claude API 中转服务，支持多账户管理、API Key 认证、使用统计等功能。

## 核心功能

- **多账户管理** - 支持添加多个 Claude 账户自动轮换
- **多平台支持** - Claude / Gemini / OpenAI / AWS Bedrock / Azure 等
- **API Key 认证** - 为每个用户分配独立的 API Key
- **使用统计** - 详细记录 Token 使用量和费用
- **智能调度** - 账户故障自动切换，负载均衡
- **Web 管理界面** - 可视化管理和监控
- **一键更新** - 支持在线检查更新和一键升级

## 一键安装（推荐）

```bash
curl -fsSL https://raw.githubusercontent.com/baoyuy/claude-G/main/install.sh | bash
```

安装完成后，运行以下命令初始化管理员账号：

```bash
cd /opt/claude-G && docker compose exec claude-relay npm run setup
```

## 一键更新

```bash
curl -fsSL https://raw.githubusercontent.com/baoyuy/claude-G/main/scripts/update.sh | bash
```

或者在 Web 管理界面 -> 系统设置 -> 系统更新 中点击"检查更新"按钮。

## 手动安装

### 环境要求

- Docker 20.10+
- Docker Compose 2.0+

### 安装步骤

```bash
# 克隆项目
git clone https://github.com/baoyuy/claude-G.git
cd claude-G

# 配置环境变量
cp .env.example .env
# 编辑 .env 文件，设置 JWT_SECRET 和 ENCRYPTION_KEY

# 启动服务
docker compose up -d

# 初始化管理员账号
docker compose exec claude-relay npm run setup
```

## 环境变量

```bash
# 必填（安装脚本会自动生成）
JWT_SECRET=你的JWT密钥（32字符以上）
ENCRYPTION_KEY=加密密钥（必须32字符）

# Redis配置
REDIS_HOST=redis
REDIS_PORT=6379
REDIS_PASSWORD=

# 服务配置
PORT=3000
BIND_HOST=0.0.0.0
```

## 使用方式

### Claude Code

```bash
export ANTHROPIC_BASE_URL="http://你的服务器:3000/api/"
export ANTHROPIC_AUTH_TOKEN="你的API密钥"
claude
```

### Gemini CLI

```bash
export CODE_ASSIST_ENDPOINT="http://你的服务器:3000/gemini"
export GOOGLE_CLOUD_ACCESS_TOKEN="你的API密钥"
export GOOGLE_GENAI_USE_GCA="true"
gemini
```

## 管理界面

访问 `http://你的服务器:3000/web` 进入管理界面

管理员账号信息保存在 `data/init.json`

## 常用命令

```bash
# 查看日志
docker compose logs -f

# 重启服务
docker compose restart

# 停止服务
docker compose down

# 查看服务状态
docker compose ps
```

## 技术栈

- **后端**: Node.js + Express
- **数据库**: Redis
- **前端**: Vue 3 + Vite + Tailwind CSS
- **部署**: Docker + Docker Compose

## License

MIT
