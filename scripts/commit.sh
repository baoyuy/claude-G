#!/bin/bash

# claude-G 提交脚本
# 自动更新版本号并提交代码
# 用法: ./scripts/commit.sh "提交信息" [patch|minor|major]

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_ROOT"

# 检查参数
if [ -z "$1" ]; then
    echo -e "${RED}错误: 请提供提交信息${NC}"
    echo ""
    echo "用法: $0 \"提交信息\" [patch|minor|major]"
    echo ""
    echo "示例:"
    echo "  $0 \"fix: 修复登录问题\"           # 默认 patch, 版本 +0.0.1"
    echo "  $0 \"feat: 添加新功能\" minor      # minor, 版本 +0.1.0"
    echo "  $0 \"breaking: 重构架构\" major    # major, 版本 +1.0.0"
    exit 1
fi

COMMIT_MSG="$1"
BUMP_TYPE=${2:-patch}

# 检查是否有改动
if [ -z "$(git status --porcelain)" ]; then
    echo -e "${YELLOW}没有需要提交的改动${NC}"
    exit 0
fi

# 更新版本号
echo -e "${BLUE}[1/4] 更新版本号...${NC}"
bash "$SCRIPT_DIR/version.sh" "$BUMP_TYPE"
NEW_VERSION=$(cat "$PROJECT_ROOT/VERSION")

# 添加所有改动
echo -e "${BLUE}[2/4] 添加文件...${NC}"
git add -A

# 提交
echo -e "${BLUE}[3/4] 提交代码...${NC}"
git commit -m "$COMMIT_MSG

Version: $NEW_VERSION"

# 显示结果
echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                    提交成功！                              ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${BLUE}版本:${NC} $NEW_VERSION"
echo -e "  ${BLUE}信息:${NC} $COMMIT_MSG"
echo ""
echo -e "  ${YELLOW}推送到远程仓库:${NC} git push origin main"
echo ""
