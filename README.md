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

## 技术栈

- **后端**: Node.js + Express
- **数据库**: Redis
- **前端**: Vue 3 + Vite + Tailwind CSS

## 快速开始

```bash
# 安装依赖
npm install

# 复制配置文件
cp config/config.example.js config/config.js
cp .env.example .env

# 初始化（生成管理员账号）
npm run setup

# 安装前端依赖并构建
npm run install:web
npm run build:web

# 启动服务
npm run service:start:daemon
```

## 环境变量

```bash
# 必填
JWT_SECRET=你的JWT密钥（32字符以上）
ENCRYPTION_KEY=加密密钥（必须32字符）

# Redis配置
REDIS_HOST=localhost
REDIS_PORT=6379
REDIS_PASSWORD=
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

## License

MIT
