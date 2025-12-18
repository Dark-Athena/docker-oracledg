#!/bin/bash
# =============================================================================
# Oracle ADG Docker 构建脚本
# 
# 构建策略:
#   1. oracle-adg-base: 缓存 dnf install（只需构建一次）
#   2. oracle-adg: 多阶段构建，减小最终镜像体积
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

image_exists() { docker image inspect "$1" >/dev/null 2>&1; }

# 检查安装包
if [ ! -f "oracle-install/LINUX.X64_193000_db_home.zip" ]; then
    log_error "未找到 Oracle 安装包!"
    log_error "请将 LINUX.X64_193000_db_home.zip 放入 oracle-install/ 目录"
    exit 1
fi

# 构建 base 镜像（如果不存在）
if image_exists "oracle-adg-base:latest"; then
    log_info "oracle-adg-base 已存在，跳过（节省 5-10 分钟）"
else
    log_info "构建 oracle-adg-base（包含 dnf install）..."
    docker-compose build oracle-base
    log_info "oracle-adg-base 构建完成!"
fi

# 构建 installed 镜像（多阶段构建）
log_info "构建 oracle-adg（多阶段构建）..."
log_info "预计需要 10-15 分钟..."
docker-compose build oracle-installed

log_info "构建完成!"
log_info ""
log_info "镜像大小:"
docker images | grep oracle-adg
log_info ""
log_info "下一步:"
log_info "  启动服务: docker-compose up -d oracle-primary oracle-standby"
log_info "  检查状态: ./scripts/check_status.sh"
