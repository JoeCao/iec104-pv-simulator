#!/bin/bash
#
# 本机 macOS 开发控制脚本（轻量版）
# 用法: ./dev_macos_ctl.sh {start|stop|restart|status|log} [csv_path] [port]
#

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
PV_BIN="$PROJECT_DIR/pv_simulator"

DEFAULT_CSV="$PROJECT_DIR/config/sim_rules.csv"
DEFAULT_PORT="${PV_PORT:-2404}"
LOG_DIR="$PROJECT_DIR/logs"
RUN_DIR="$PROJECT_DIR/run"
PID_FILE="$RUN_DIR/dev_macos_pv_simulator.pid"
LOG_FILE="$LOG_DIR/dev_macos_pv_simulator.log"

mkdir -p "$LOG_DIR" "$RUN_DIR"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

get_pid() {
    if [ -f "$PID_FILE" ]; then
        local pid
        pid="$(cat "$PID_FILE" 2>/dev/null || true)"
        if [ -n "$pid" ] && ps -p "$pid" >/dev/null 2>&1; then
            echo "$pid"
            return 0
        fi
    fi

    # 兜底匹配当前项目目录下的 pv_simulator
    pgrep -f "$PROJECT_DIR/pv_simulator( |$)" 2>/dev/null || true
}

ensure_port_free() {
    local port="$1"
    if lsof -nP -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1; then
        log_error "端口 $port 已被占用"
        lsof -nP -iTCP:"$port" -sTCP:LISTEN || true
        exit 1
    fi
}

do_start() {
    local csv_path="${1:-${PV_CSV_PATH:-$DEFAULT_CSV}}"
    local port="${2:-$DEFAULT_PORT}"
    local pid
    pid="$(get_pid)"

    if [ -n "$pid" ]; then
        log_warn "模拟器已运行 (PID: $pid)"
        return 1
    fi

    if [ ! -x "$PV_BIN" ]; then
        log_error "可执行文件不存在: $PV_BIN"
        log_info "请先执行: make"
        exit 1
    fi

    if [ ! -f "$csv_path" ]; then
        log_error "CSV 配置不存在: $csv_path"
        exit 1
    fi

    if ! [[ "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
        log_error "无效端口: $port"
        exit 1
    fi

    ensure_port_free "$port"

    log_info "启动本机模拟器..."
    log_info "配置文件: $csv_path"
    log_info "监听端口: $port"
    log_info "日志文件: $LOG_FILE"

    # 用 nohup 后台运行，避免关闭终端导致进程状态异常
    # 使用 stdbuf 关闭标准输出缓冲，便于实时观察日志
    nohup stdbuf -oL -eL "$PV_BIN" "$csv_path" "$port" >>"$LOG_FILE" 2>&1 &
    pid=$!
    echo "$pid" > "$PID_FILE"
    sleep 1

    if ps -p "$pid" >/dev/null 2>&1; then
        log_info "启动成功 (PID: $pid)"
    else
        log_error "启动失败，请查看日志: $LOG_FILE"
        rm -f "$PID_FILE"
        exit 1
    fi
}

do_stop() {
    local pids
    pids="$(get_pid)"
    if [ -z "$pids" ]; then
        log_warn "模拟器未运行"
        rm -f "$PID_FILE"
        return 0
    fi

    log_info "停止模拟器 (PID: $pids)"
    for p in $pids; do
        kill "$p" 2>/dev/null || true
    done
    sleep 1

    local still
    still="$(get_pid)"
    if [ -n "$still" ]; then
        log_warn "进程未退出，执行强制停止..."
        for p in $still; do
            kill -9 "$p" 2>/dev/null || true
        done
    fi

    rm -f "$PID_FILE"
    log_info "已停止"
}

do_restart() {
    do_stop
    do_start "$1" "$2"
}

do_status() {
    local pids
    pids="$(get_pid)"
    local port="${PV_PORT:-$DEFAULT_PORT}"

    if [ -n "$pids" ]; then
        log_info "模拟器运行中 (PID: $pids)"
    else
        log_info "模拟器未运行"
    fi

    if lsof -nP -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1; then
        log_info "端口 $port 监听正常"
    else
        log_warn "端口 $port 未监听（若使用了其他端口可忽略）"
    fi

    log_info "日志文件: $LOG_FILE"
}

do_log() {
    if [ -f "$LOG_FILE" ]; then
        tail -f "$LOG_FILE"
    else
        log_warn "日志文件不存在: $LOG_FILE"
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
        echo "本机 macOS 模拟器控制脚本"
        echo ""
        echo "用法: $0 {start|stop|restart|status|log} [csv_path] [port]"
        echo ""
        echo "示例:"
        echo "  $0 start"
        echo "  $0 start config/sim_rules.csv 2504"
        echo "  $0 status"
        echo "  $0 stop"
        exit 1
        ;;
esac
