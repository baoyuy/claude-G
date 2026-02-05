#!/bin/bash

# claude-G 版本管理脚本
# 用法: ./scripts/version.sh [patch|minor|major]
# 默认: patch (自动递增最后一位)

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
VERSION_FILE="$PROJECT_ROOT/VERSION"

# 读取当前版本
if [ ! -f "$VERSION_FILE" ]; then
    echo "1.0.0" > "$VERSION_FILE"
fi

CURRENT_VERSION=$(cat "$VERSION_FILE" | tr -d '\n\r')

# 解析版本号
IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT_VERSION"

# 默认操作类型
BUMP_TYPE=${1:-patch}

# 更新版本号
case $BUMP_TYPE in
    major)
        MAJOR=$((MAJOR + 1))
        MINOR=0
        PATCH=0
        ;;
    minor)
        MINOR=$((MINOR + 1))
        PATCH=0
        ;;
    patch)
        PATCH=$((PATCH + 1))
        ;;
    *)
        echo -e "${RED}错误: 无效的版本类型 '$BUMP_TYPE'${NC}"
        echo "用法: $0 [patch|minor|major]"
        echo "  patch - 修复bug、小改动 (1.1.268 -> 1.1.269)"
        echo "  minor - 新功能 (1.1.268 -> 1.2.0)"
        echo "  major - 大版本更新 (1.1.268 -> 2.0.0)"
        exit 1
        ;;
esac

NEW_VERSION="$MAJOR.$MINOR.$PATCH"

# 写入新版本
echo "$NEW_VERSION" > "$VERSION_FILE"

echo -e "${GREEN}版本更新: ${YELLOW}$CURRENT_VERSION${NC} -> ${GREEN}$NEW_VERSION${NC}"
echo "$NEW_VERSION"
