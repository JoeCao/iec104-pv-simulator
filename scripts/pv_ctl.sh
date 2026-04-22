#!/bin/bash
#
# 光伏模拟器启停控制脚本（CSV 动态点位版）
# 用法: ./pv_ctl.sh {start|stop|restart|status|log} [csv_path] [port]
#

# 自动检测安装目录
if [ -f "/opt/pv_simulator/pv_simulator" ]; then
    # 服务器部署模式
    PV_DIR="/opt/pv_simulator"
    PV_BIN="$PV_DIR/pv_simulator"
else
    # 本地开发模式
    SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
    PV_DIR="$(dirname "$SCRIPT_DIR")"
    PV_BIN="$PV_DIR/pv_simulator"
fi

DEFAULT_CSV="$PV_DIR/config/sim_rules.csv"
DEFAULT_PORT="${PV_PORT:-2404}"
LOG_DIR="/var/log"
RUN_DIR="/var/run"
if [ ! -w "$LOG_DIR" ]; then
    LOG_DIR="$PV_DIR/logs"
fi
if [ ! -w "$RUN_DIR" ]; then
    RUN_DIR="$PV_DIR/run"
fi
mkdir -p "$LOG_DIR" "$RUN_DIR" 2>/dev/null || true

PV_LOG="$LOG_DIR/pv_simulator.log"
PID_FILE="$RUN_DIR/pv_simulator.pid"
SCREEN_NAME="pv_sim"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

get_pid() {
    pgrep -f "$PV_BIN" 2>/dev/null
}

do_start() {
    local csv_path="${1:-${PV_CSV_PATH:-$DEFAULT_CSV}}"
    local port="${2:-$DEFAULT_PORT}"
    local pid=$(get_pid)
    if [ -n "$pid" ]; then
        log_warn "光伏模拟器已在运行 (PID: $pid)"
        return 1
    fi

    if [ ! -x "$PV_BIN" ]; then
        log_error "可执行文件不存在或无执行权限: $PV_BIN"
        return 1
    fi

    if [ ! -f "$csv_path" ]; then
        log_error "CSV 配置文件不存在: $csv_path"
        return 1
    fi

    if ! [[ "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
        log_error "无效端口: $port"
        return 1
    fi

    log_info "启动光伏模拟器..."
    log_info "配置文件: $csv_path"
    log_info "监听端口: $port"

    # 使用 screen 在后台运行
    cd "$(dirname "$PV_BIN")"
    screen -dmS "$SCREEN_NAME" bash -c "'$PV_BIN' '$csv_path' '$port' 2>&1 | tee -a '$PV_LOG'"

    sleep 2
    pid=$(get_pid)
    if [ -n "$pid" ]; then
        echo "$pid" > "$PID_FILE" 2>/dev/null || true
        log_info "光伏模拟器启动成功 (PID: $pid)"
        log_info "监听端口: $port"
        log_info "查看日志: $0 log"
        log_info "进入控制台: screen -r $SCREEN_NAME"
        return 0
    else
        log_error "光伏模拟器启动失败"
        return 1
    fi
}

do_stop() {
    local pid=$(get_pid)
    if [ -z "$pid" ]; then
        log_warn "光伏模拟器未运行"
        return 0
    fi

    log_info "停止光伏模拟器 (PID: $pid)..."
    kill "$pid" 2>/dev/null

    # 等待进程退出
    for i in {1..10}; do
        if [ -z "$(get_pid)" ]; then
            break
        fi
        sleep 1
    done

    # 强制杀死
    pid=$(get_pid)
    if [ -n "$pid" ]; then
        log_warn "进程未响应，强制终止..."
        kill -9 "$pid" 2>/dev/null
    fi

    rm -f "$PID_FILE" 2>/dev/null

    # 清理 screen 会话
    screen -X -S "$SCREEN_NAME" quit 2>/dev/null || true

    log_info "光伏模拟器已停止"
    return 0
}

do_restart() {
    do_stop
    sleep 1
    do_start "$1" "$2"
}

do_status() {
    local pid=$(get_pid)
    local port="${PV_PORT:-$DEFAULT_PORT}"
    if [ -n "$pid" ]; then
        log_info "光伏模拟器运行中 (PID: $pid)"

        # 检查端口
        if netstat -tlnp 2>/dev/null | grep -q ":$port " || \
           ss -tlnp 2>/dev/null | grep -q ":$port " || \
           lsof -i :"$port" 2>/dev/null | grep -q LISTEN; then
            log_info "端口 $port 监听正常"
        else
            log_warn "端口 $port 未监听"
        fi

        # 显示运行时间
        if command -v ps &>/dev/null; then
            local etime=$(ps -p "$pid" -o etime= 2>/dev/null | tr -d ' ')
            if [ -n "$etime" ]; then
                log_info "运行时间: $etime"
            fi
        fi

        return 0
    else
        log_info "光伏模拟器未运行"
        return 1
    fi
}

do_log() {
    if [ -f "$PV_LOG" ]; then
        tail -f "$PV_LOG"
    else
        # 尝试连接 screen 会话
        if screen -list | grep -q "$SCREEN_NAME"; then
            log_info "进入 screen 会话 (按 Ctrl+A D 退出)..."
            screen -r "$SCREEN_NAME"
        else
            log_warn "日志文件不存在: $PV_LOG"
        fi
    fi
}

case "$1" in
    start)
        do_start "$2" "$3"
        ;;
    stop)
        do_stop
        ;;
    restart)
        do_restart "$2" "$3"
        ;;
    status)
        do_status
        ;;
    log)
        do_log
        ;;
    *)
        echo "光伏发电站 IEC 104 模拟器控制脚本"
        echo ""
        echo "用法: $0 {start|stop|restart|status|log} [csv_path] [port]"
        echo ""
        echo "命令:"
        echo "  start   - 启动模拟器（可选 csv_path、port）"
        echo "  stop    - 停止模拟器"
        echo "  restart - 重启模拟器（可选 csv_path、port）"
        echo "  status  - 查看运行状态"
        echo "  log     - 查看实时日志"
        echo ""
        echo "默认配置:"
        echo "  csv:  ${PV_CSV_PATH:-$DEFAULT_CSV}"
        echo "  port: ${PV_PORT:-$DEFAULT_PORT}"
        exit 1
        ;;
esac

exit $?
