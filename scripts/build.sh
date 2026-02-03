#!/bin/bash
#
# 光伏模拟器多平台编译脚本
# 支持: macOS (arm64/x86_64), Linux (x86_64/arm64)
#

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
LIB_DIR="$PROJECT_DIR/.."
SRC_FILE="$PROJECT_DIR/pv_simulator_lib60870.c"
OUTPUT_DIR="$PROJECT_DIR/../../../dist"

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

# 检查依赖
check_deps() {
    log_step "检查编译环境..."

    if ! command -v cc &>/dev/null && ! command -v gcc &>/dev/null; then
        log_error "未找到 C 编译器 (cc/gcc)"
        exit 1
    fi

    if [ ! -f "$SRC_FILE" ]; then
        log_error "源文件不存在: $SRC_FILE"
        exit 1
    fi

    log_info "编译环境检查通过"
}

# 编译 lib60870 库
build_lib() {
    local arch=$1
    log_step "编译 lib60870 库 ($arch)..."

    cd "$LIB_DIR"

    # 清理旧编译
    make clean >/dev/null 2>&1 || true

    # 根据架构编译
    if [ "$(uname)" = "Darwin" ]; then
        make CFLAGS="-arch $arch" >/dev/null 2>&1
    else
        make >/dev/null 2>&1
    fi

    if [ ! -f "$LIB_DIR/build/liblib60870.a" ]; then
        log_error "lib60870 编译失败"
        exit 1
    fi

    log_info "lib60870 编译完成"
}

# 编译模拟器
build_simulator() {
    local arch=$1
    local output=$2

    log_step "编译 pv_simulator ($arch)..."

    cd "$LIB_DIR"

    local CC="cc"
    local CFLAGS=""

    if [ "$(uname)" = "Darwin" ]; then
        CFLAGS="-arch $arch"
    fi

    $CC $CFLAGS -o "$output" \
        "$SRC_FILE" \
        -Isrc/inc/api -Isrc/hal/inc \
        -Lbuild -llib60870 \
        -lpthread -lm 2>&1

    if [ -f "$output" ]; then
        chmod +x "$output"
        log_info "编译成功: $output"
        log_info "文件大小: $(ls -lh "$output" | awk '{print $5}')"
    else
        log_error "编译失败"
        return 1
    fi
}

# 编译所有平台
build_all() {
    mkdir -p "$OUTPUT_DIR"

    local os=$(uname)
    local current_arch=$(uname -m)

    log_info "当前系统: $os ($current_arch)"
    log_info "输出目录: $OUTPUT_DIR"
    echo ""

    if [ "$os" = "Darwin" ]; then
        # macOS: 编译 arm64 和 x86_64

        # arm64
        log_info "========== 编译 macOS arm64 =========="
        build_lib "arm64"
        build_simulator "arm64" "$OUTPUT_DIR/pv_simulator-darwin-arm64"
        echo ""

        # x86_64
        log_info "========== 编译 macOS x86_64 =========="
        build_lib "x86_64"
        build_simulator "x86_64" "$OUTPUT_DIR/pv_simulator-darwin-x86_64"
        echo ""

        # 创建通用二进制 (Universal Binary)
        log_step "创建 Universal Binary..."
        if command -v lipo &>/dev/null; then
            lipo -create \
                "$OUTPUT_DIR/pv_simulator-darwin-arm64" \
                "$OUTPUT_DIR/pv_simulator-darwin-x86_64" \
                -output "$OUTPUT_DIR/pv_simulator-darwin-universal"
            log_info "Universal Binary: $OUTPUT_DIR/pv_simulator-darwin-universal"
        fi
        echo ""

    else
        # Linux: 只编译当前架构
        log_info "========== 编译 Linux $current_arch =========="
        build_lib "$current_arch"
        build_simulator "$current_arch" "$OUTPUT_DIR/pv_simulator-linux-$current_arch"
        echo ""
    fi

    # 复制一份到项目根目录
    if [ "$os" = "Darwin" ]; then
        cp "$OUTPUT_DIR/pv_simulator-darwin-arm64" "$LIB_DIR/../pv_simulator" 2>/dev/null || \
        cp "$OUTPUT_DIR/pv_simulator-darwin-x86_64" "$LIB_DIR/../pv_simulator" 2>/dev/null
    else
        cp "$OUTPUT_DIR/pv_simulator-linux-$current_arch" "$LIB_DIR/../pv_simulator" 2>/dev/null
    fi

    log_info "========== 编译完成 =========="
    echo ""
    log_info "输出文件:"
    ls -lh "$OUTPUT_DIR"/pv_simulator-* 2>/dev/null
}

# 清理
clean() {
    log_step "清理编译产物..."
    cd "$LIB_DIR"
    make clean >/dev/null 2>&1 || true
    rm -rf "$OUTPUT_DIR"
    rm -f "$LIB_DIR/../pv_simulator"
    log_info "清理完成"
}

# 主逻辑
case "${1:-all}" in
    all)
        check_deps
        build_all
        ;;
    clean)
        clean
        ;;
    arm64)
        check_deps
        mkdir -p "$OUTPUT_DIR"
        build_lib "arm64"
        build_simulator "arm64" "$OUTPUT_DIR/pv_simulator-darwin-arm64"
        ;;
    x86_64)
        check_deps
        mkdir -p "$OUTPUT_DIR"
        build_lib "x86_64"
        build_simulator "x86_64" "$OUTPUT_DIR/pv_simulator-darwin-x86_64"
        ;;
    *)
        echo "光伏模拟器多平台编译脚本"
        echo ""
        echo "用法: $0 [命令]"
        echo ""
        echo "命令:"
        echo "  all     - 编译所有支持的平台 (默认)"
        echo "  arm64   - 仅编译 macOS arm64"
        echo "  x86_64  - 仅编译 macOS x86_64"
        echo "  clean   - 清理编译产物"
        echo ""
        echo "输出目录: $OUTPUT_DIR"
        exit 1
        ;;
esac
