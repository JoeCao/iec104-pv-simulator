#!/bin/bash
#
# 光伏模拟器部署脚本
# 本地交叉编译后上传到服务器
#
# 用法: ./deploy.sh [init|update|status]
#

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
DIST_DIR="$PROJECT_DIR/dist"
BINARY="$DIST_DIR/pv_simulator-linux-x86_64"

# 服务器配置 (可通过环境变量覆盖)
REMOTE_HOST="${PV_REMOTE_HOST:-root@8.140.239.5}"
REMOTE_DIR="${PV_REMOTE_DIR:-/opt/pv_simulator}"
REMOTE_CSV="${PV_REMOTE_CSV:-$REMOTE_DIR/config/sim_rules.csv}"
REMOTE_PORT="${PV_REMOTE_PORT:-2404}"

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

# 安装 logrotate 配置（方案 A）
install_logrotate() {
    log_step "配置日志轮转 (logrotate)..."

    scp "$SCRIPT_DIR/pv_simulator.logrotate" "$REMOTE_HOST:/tmp/pv_simulator.logrotate"
    ssh "$REMOTE_HOST" "
        if [ -d /etc/logrotate.d ]; then
            mv /tmp/pv_simulator.logrotate /etc/logrotate.d/pv_simulator
            chmod 644 /etc/logrotate.d/pv_simulator
            logrotate -d /etc/logrotate.d/pv_simulator >/dev/null 2>&1 || true
            echo 'logrotate 已配置: /etc/logrotate.d/pv_simulator'
        else
            echo '未找到 /etc/logrotate.d，跳过 logrotate 安装'
            rm -f /tmp/pv_simulator.logrotate
        fi
    "
}

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

# 本地交叉编译
do_build() {
    log_step "本地交叉编译 Linux x86_64 版本..."

    if ! command -v zig &>/dev/null; then
        log_error "需要安装 zig: brew install zig"
        exit 1
    fi

    cd "$PROJECT_DIR"
    make linux

    if [ ! -f "$BINARY" ]; then
        log_error "编译失败: $BINARY 不存在"
        exit 1
    fi

    log_info "编译成功: $BINARY"
}

# 首次初始化部署
do_init() {
    log_info "========== 首次部署初始化 =========="
    echo ""

    # 1. 本地编译
    do_build

    check_ssh

    # 2. 创建远程目录
    log_step "创建远程目录..."
    ssh "$REMOTE_HOST" "mkdir -p '$REMOTE_DIR/scripts' '$REMOTE_DIR/config'"

    # 3. 上传二进制文件和脚本
    log_step "上传文件..."
    scp "$BINARY" "$REMOTE_HOST:$REMOTE_DIR/pv_simulator"
    scp "$PROJECT_DIR/docs/PV_SIMULATOR_README.md" "$REMOTE_HOST:$REMOTE_DIR/" 2>/dev/null || true
    scp "$PROJECT_DIR/docs/POINT_TABLE.md" "$REMOTE_HOST:$REMOTE_DIR/" 2>/dev/null || true
    scp "$PROJECT_DIR/docs/SIM_RULES_SPEC.md" "$REMOTE_HOST:$REMOTE_DIR/" 2>/dev/null || true
    scp "$PROJECT_DIR/config/sim_rules.csv" "$REMOTE_HOST:$REMOTE_CSV"
    scp "$SCRIPT_DIR/pv_ctl.sh" "$REMOTE_HOST:$REMOTE_DIR/scripts/"

    # 4. 设置权限和软链接
    log_step "配置权限..."
    ssh "$REMOTE_HOST" "
        chmod +x '$REMOTE_DIR/pv_simulator'
        chmod +x '$REMOTE_DIR/scripts/pv_ctl.sh'
        ln -sf '$REMOTE_DIR/scripts/pv_ctl.sh' /usr/local/bin/pv_ctl
    "

    # 5. 配置日志轮转
    install_logrotate

    # 6. 开放防火墙端口
    log_step "配置防火墙..."
    ssh "$REMOTE_HOST" "ufw allow ${REMOTE_PORT}/tcp 2>/dev/null || iptables -A INPUT -p tcp --dport ${REMOTE_PORT} -j ACCEPT 2>/dev/null || true"

    echo ""
    log_info "========== 初始化完成 =========="
    log_info ""
    log_info "部署目录: $REMOTE_DIR"
    log_info "控制命令: pv_ctl {start|stop|restart|status|log}"
    log_info "CSV 配置: $REMOTE_CSV"
    log_info "监听端口: $REMOTE_PORT"
    log_info ""
    log_info "启动模拟器: ssh $REMOTE_HOST 'pv_ctl start $REMOTE_CSV $REMOTE_PORT'"
}

# 更新部署
do_update() {
    log_info "========== 更新部署 =========="
    echo ""

    # 1. 本地编译
    do_build

    check_ssh

    # 2. 停止运行中的模拟器
    log_step "停止模拟器..."
    # 注意：不要在这里使用 "pkill -f pv_simulator" 字样，老版本 pv_ctl 可能误匹配并中断当前 SSH 会话
    ssh "$REMOTE_HOST" "pv_ctl stop >/dev/null 2>&1 || true"

    # 确保远程目录存在（兼容历史版本部署目录结构）
    ssh "$REMOTE_HOST" "mkdir -p '$REMOTE_DIR/scripts' \"$(dirname "$REMOTE_CSV")\""

    # 3. 上传新二进制文件
    log_step "上传文件..."
    scp "$BINARY" "$REMOTE_HOST:$REMOTE_DIR/pv_simulator"
    scp "$PROJECT_DIR/config/sim_rules.csv" "$REMOTE_HOST:$REMOTE_CSV"
    scp "$SCRIPT_DIR/pv_ctl.sh" "$REMOTE_HOST:$REMOTE_DIR/scripts/"

    # 4. 更新日志轮转配置
    install_logrotate

    # 5. 设置权限
    ssh "$REMOTE_HOST" "chmod +x '$REMOTE_DIR/pv_simulator' '$REMOTE_DIR/scripts/pv_ctl.sh'"

    # 6. 重启模拟器
    log_step "重启模拟器..."
    ssh "$REMOTE_HOST" "pv_ctl start '$REMOTE_CSV' '$REMOTE_PORT'"

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
        netstat -tlnp 2>/dev/null | grep $REMOTE_PORT || ss -tlnp | grep $REMOTE_PORT || echo '端口 $REMOTE_PORT 未监听'
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
    ssh "$REMOTE_HOST" "pv_ctl start '$REMOTE_CSV' '$REMOTE_PORT'"
}

# 远程停止
do_stop() {
    check_ssh
    ssh "$REMOTE_HOST" "pv_ctl stop"
}

# 远程重启
do_restart() {
    check_ssh
    ssh "$REMOTE_HOST" "pv_ctl restart '$REMOTE_CSV' '$REMOTE_PORT'"
}

# 仅编译不上传
do_build_only() {
    do_build
    log_info "编译完成，二进制文件: $BINARY"
}

# 显示帮助
show_help() {
    echo "光伏模拟器部署脚本 (本地交叉编译)"
    echo ""
    echo "用法: $0 <命令>"
    echo ""
    echo "部署命令:"
    echo "  init    - 首次部署 (编译、上传、配置)"
    echo "  update  - 更新部署 (重新编译、上传、重启)"
    echo "  build   - 仅本地编译，不上传"
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
    echo "  PV_REMOTE_CSV   - 远程 CSV 路径 (默认: $REMOTE_CSV)"
    echo "  PV_REMOTE_PORT  - 远程监听端口 (默认: $REMOTE_PORT)"
    echo ""
    echo "示例:"
    echo "  $0 init                           # 首次部署"
    echo "  $0 update                         # 更新代码"
    echo "  $0 build                          # 仅编译"
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
    build)
        do_build_only
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
