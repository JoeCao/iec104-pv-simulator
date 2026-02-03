#!/bin/bash
#
# 光伏模拟器部署脚本
# 用法: ./deploy.sh [init|update|status]
#

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
LIB_DIR="$PROJECT_DIR/.."
DIST_DIR="$PROJECT_DIR/../../../dist"

# 服务器配置 (可通过环境变量覆盖)
REMOTE_HOST="${PV_REMOTE_HOST:-root@8.140.239.5}"
REMOTE_DIR="${PV_REMOTE_DIR:-/opt/pv_simulator}"
REMOTE_LIB60870="${PV_REMOTE_LIB60870:-/root/lib60870}"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "${BLUE}[STEP]${NC} $1"; }

# 检查 SSH 连接
check_ssh() {
    log_step "检查 SSH 连接..."
    if ! ssh -o ConnectTimeout=5 "$REMOTE_HOST" "echo ok" >/dev/null 2>&1; then
        log_error "无法连接到服务器: $REMOTE_HOST"
        log_info "请检查:"
        log_info "  1. SSH 密钥是否配置正确"
        log_info "  2. 服务器是否可达"
        log_info "  3. 环境变量 PV_REMOTE_HOST 是否正确"
        exit 1
    fi
    log_info "SSH 连接正常"
}

# 首次初始化部署
do_init() {
    log_info "========== 首次部署初始化 =========="
    echo ""

    check_ssh

    # 1. 在服务器上安装依赖
    log_step "安装服务器依赖..."
    ssh "$REMOTE_HOST" "apt-get update && apt-get install -y build-essential screen git" || true

    # 2. 克隆 lib60870
    log_step "克隆 lib60870 库..."
    ssh "$REMOTE_HOST" "
        if [ -d '$REMOTE_LIB60870' ]; then
            echo 'lib60870 已存在，更新中...'
            cd '$REMOTE_LIB60870' && git pull
        else
            git clone https://github.com/mz-automation/lib60870.git '$REMOTE_LIB60870'
        fi
    "

    # 3. 编译 lib60870
    log_step "编译 lib60870..."
    ssh "$REMOTE_HOST" "cd '$REMOTE_LIB60870/lib60870-C' && make clean && make"

    # 4. 创建部署目录
    log_step "创建部署目录..."
    ssh "$REMOTE_HOST" "mkdir -p '$REMOTE_DIR/scripts'"

    # 5. 上传源码和脚本
    log_step "上传源码..."
    scp "$PROJECT_DIR/pv_simulator_lib60870.c" "$REMOTE_HOST:$REMOTE_LIB60870/lib60870-C/examples/"
    scp "$PROJECT_DIR/PV_SIMULATOR_README.md" "$REMOTE_HOST:$REMOTE_DIR/"
    scp "$SCRIPT_DIR/pv_ctl.sh" "$REMOTE_HOST:$REMOTE_DIR/scripts/"

    # 6. 编译
    log_step "编译模拟器..."
    ssh "$REMOTE_HOST" "
        cd '$REMOTE_LIB60870/lib60870-C'
        gcc -o '$REMOTE_DIR/pv_simulator' examples/pv_simulator_lib60870.c \
            -Isrc/inc/api -Isrc/hal/inc -Lbuild -llib60870 -lpthread -lm
        chmod +x '$REMOTE_DIR/pv_simulator'
        chmod +x '$REMOTE_DIR/scripts/pv_ctl.sh'
    "

    # 7. 创建软链接
    log_step "创建软链接..."
    ssh "$REMOTE_HOST" "ln -sf '$REMOTE_DIR/scripts/pv_ctl.sh' /usr/local/bin/pv_ctl"

    # 8. 开放防火墙端口
    log_step "配置防火墙..."
    ssh "$REMOTE_HOST" "ufw allow 2404/tcp 2>/dev/null || iptables -A INPUT -p tcp --dport 2404 -j ACCEPT 2>/dev/null || true"

    echo ""
    log_info "========== 初始化完成 =========="
    log_info ""
    log_info "部署目录: $REMOTE_DIR"
    log_info "控制命令: pv_ctl {start|stop|restart|status|log}"
    log_info ""
    log_info "启动模拟器: ssh $REMOTE_HOST 'pv_ctl start'"
}

# 更新部署
do_update() {
    log_info "========== 更新部署 =========="
    echo ""

    check_ssh

    # 1. 停止运行中的模拟器
    log_step "停止模拟器..."
    ssh "$REMOTE_HOST" "pv_ctl stop 2>/dev/null || pkill -f pv_simulator || true"

    # 2. 上传新源码
    log_step "上传源码..."
    scp "$PROJECT_DIR/pv_simulator_lib60870.c" "$REMOTE_HOST:$REMOTE_LIB60870/lib60870-C/examples/"
    scp "$PROJECT_DIR/PV_SIMULATOR_README.md" "$REMOTE_HOST:$REMOTE_DIR/" 2>/dev/null || true
    scp "$SCRIPT_DIR/pv_ctl.sh" "$REMOTE_HOST:$REMOTE_DIR/scripts/"

    # 3. 重新编译
    log_step "重新编译..."
    ssh "$REMOTE_HOST" "
        cd '$REMOTE_LIB60870/lib60870-C'
        gcc -o '$REMOTE_DIR/pv_simulator' examples/pv_simulator_lib60870.c \
            -Isrc/inc/api -Isrc/hal/inc -Lbuild -llib60870 -lpthread -lm
        chmod +x '$REMOTE_DIR/pv_simulator'
        chmod +x '$REMOTE_DIR/scripts/pv_ctl.sh'
    "

    # 4. 重启模拟器
    log_step "重启模拟器..."
    ssh "$REMOTE_HOST" "pv_ctl start"

    echo ""
    log_info "========== 更新完成 =========="
}

# 查看服务器状态
do_status() {
    log_info "========== 服务器状态 =========="
    echo ""

    check_ssh

    ssh "$REMOTE_HOST" "
        echo '--- 模拟器状态 ---'
        pv_ctl status 2>/dev/null || (pgrep -f pv_simulator && echo '运行中' || echo '未运行')
        echo ''
        echo '--- 端口监听 ---'
        netstat -tlnp 2>/dev/null | grep 2404 || ss -tlnp | grep 2404 || echo '端口 2404 未监听'
        echo ''
        echo '--- 磁盘空间 ---'
        df -h '$REMOTE_DIR' 2>/dev/null || df -h /
    "
}

# 查看远程日志
do_log() {
    check_ssh
    log_info "连接到服务器查看日志 (Ctrl+C 退出)..."
    ssh "$REMOTE_HOST" "pv_ctl log" || ssh -t "$REMOTE_HOST" "screen -r pv_sim"
}

# 远程启动
do_start() {
    check_ssh
    ssh "$REMOTE_HOST" "pv_ctl start"
}

# 远程停止
do_stop() {
    check_ssh
    ssh "$REMOTE_HOST" "pv_ctl stop"
}

# 远程重启
do_restart() {
    check_ssh
    ssh "$REMOTE_HOST" "pv_ctl restart"
}

# 显示帮助
show_help() {
    echo "光伏模拟器部署脚本"
    echo ""
    echo "用法: $0 <命令>"
    echo ""
    echo "部署命令:"
    echo "  init    - 首次部署 (克隆库、编译、配置)"
    echo "  update  - 更新部署 (上传新代码、重新编译)"
    echo ""
    echo "远程控制:"
    echo "  start   - 启动远程模拟器"
    echo "  stop    - 停止远程模拟器"
    echo "  restart - 重启远程模拟器"
    echo "  status  - 查看远程状态"
    echo "  log     - 查看远程日志"
    echo ""
    echo "环境变量:"
    echo "  PV_REMOTE_HOST  - 远程服务器 (默认: $REMOTE_HOST)"
    echo "  PV_REMOTE_DIR   - 远程部署目录 (默认: $REMOTE_DIR)"
    echo ""
    echo "示例:"
    echo "  $0 init                           # 首次部署"
    echo "  $0 update                         # 更新代码"
    echo "  PV_REMOTE_HOST=user@host $0 init  # 部署到其他服务器"
}

# 主逻辑
case "$1" in
    init)
        do_init
        ;;
    update)
        do_update
        ;;
    status)
        do_status
        ;;
    log)
        do_log
        ;;
    start)
        do_start
        ;;
    stop)
        do_stop
        ;;
    restart)
        do_restart
        ;;
    -h|--help|help)
        show_help
        ;;
    *)
        show_help
        exit 1
        ;;
esac
