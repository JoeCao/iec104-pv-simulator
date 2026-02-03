# 光伏发电站 IEC 60870-5-104 协议模拟器 Makefile

# 项目目录
PROJECT_DIR := $(shell pwd)
SRC_DIR := $(PROJECT_DIR)/src
LIB_DIR := $(PROJECT_DIR)/lib/lib60870/lib60870-C
BUILD_DIR := $(PROJECT_DIR)/build
DIST_DIR := $(PROJECT_DIR)/dist

# 源文件
SRC_FILE := $(SRC_DIR)/pv_simulator.c
TARGET := pv_simulator

# 编译器和标志
CC := gcc
CFLAGS := -Wall -O2
INCLUDES := -I$(LIB_DIR)/src/inc/api -I$(LIB_DIR)/src/hal/inc
LDFLAGS := -L$(LIB_DIR)/build -llib60870 -lpthread -lm

# 检测操作系统和架构
UNAME_S := $(shell uname -s)
UNAME_M := $(shell uname -m)

ifeq ($(UNAME_S),Darwin)
    # macOS
    ifeq ($(ARCH),)
        ARCH := $(UNAME_M)
    endif
    CFLAGS += -arch $(ARCH)
    TARGET_SUFFIX := -darwin-$(ARCH)
else
    # Linux
    TARGET_SUFFIX := -linux-$(UNAME_M)
endif

# 默认目标
.PHONY: all
all: lib simulator

# 编译 lib60870 库
.PHONY: lib
lib:
	@echo "编译 lib60870 库..."
	@cd $(LIB_DIR) && $(MAKE) clean > /dev/null 2>&1 || true
	@cd $(LIB_DIR) && $(MAKE) CFLAGS="$(CFLAGS)"
	@echo "lib60870 编译完成"

# 编译模拟器
.PHONY: simulator
simulator: lib
	@echo "编译 PV 模拟器..."
	@mkdir -p $(DIST_DIR)
	$(CC) $(CFLAGS) -o $(DIST_DIR)/$(TARGET)$(TARGET_SUFFIX) \
		$(SRC_FILE) $(INCLUDES) $(LDFLAGS)
	@cp $(DIST_DIR)/$(TARGET)$(TARGET_SUFFIX) $(PROJECT_DIR)/$(TARGET)
	@chmod +x $(PROJECT_DIR)/$(TARGET)
	@echo "编译完成: $(PROJECT_DIR)/$(TARGET)"
	@ls -lh $(PROJECT_DIR)/$(TARGET)

# macOS: 编译 Universal Binary
.PHONY: universal
universal:
	@echo "编译 macOS Universal Binary..."
	@$(MAKE) clean
	@$(MAKE) ARCH=arm64
	@mv $(PROJECT_DIR)/$(TARGET) $(DIST_DIR)/$(TARGET)-darwin-arm64
	@$(MAKE) clean
	@$(MAKE) ARCH=x86_64
	@mv $(PROJECT_DIR)/$(TARGET) $(DIST_DIR)/$(TARGET)-darwin-x86_64
	@lipo -create \
		$(DIST_DIR)/$(TARGET)-darwin-arm64 \
		$(DIST_DIR)/$(TARGET)-darwin-x86_64 \
		-output $(PROJECT_DIR)/$(TARGET)
	@echo "Universal Binary 创建完成: $(PROJECT_DIR)/$(TARGET)"
	@file $(PROJECT_DIR)/$(TARGET)

# 清理
.PHONY: clean
clean:
	@echo "清理编译产物..."
	@cd $(LIB_DIR) && $(MAKE) clean > /dev/null 2>&1 || true
	@rm -rf $(BUILD_DIR) $(DIST_DIR)
	@rm -f $(PROJECT_DIR)/$(TARGET)
	@echo "清理完成"

# 安装（复制到 /usr/local/bin）
.PHONY: install
install: all
	@echo "安装到 /usr/local/bin..."
	@sudo cp $(PROJECT_DIR)/$(TARGET) /usr/local/bin/
	@echo "安装完成"

# 卸载
.PHONY: uninstall
uninstall:
	@echo "卸载..."
	@sudo rm -f /usr/local/bin/$(TARGET)
	@echo "卸载完成"

# 运行
.PHONY: run
run: all
	@echo "启动 PV 模拟器..."
	@$(PROJECT_DIR)/$(TARGET)

# 帮助
.PHONY: help
help:
	@echo "光伏发电站 IEC 60870-5-104 协议模拟器 Makefile"
	@echo ""
	@echo "用法: make [目标]"
	@echo ""
	@echo "目标:"
	@echo "  all        - 编译库和模拟器 (默认)"
	@echo "  lib        - 仅编译 lib60870 库"
	@echo "  simulator  - 仅编译模拟器"
	@echo "  universal  - 编译 macOS Universal Binary (arm64 + x86_64)"
	@echo "  clean      - 清理编译产物"
	@echo "  install    - 安装到 /usr/local/bin"
	@echo "  uninstall  - 从 /usr/local/bin 卸载"
	@echo "  run        - 编译并运行"
	@echo "  help       - 显示此帮助信息"
	@echo ""
	@echo "示例:"
	@echo "  make              # 编译"
	@echo "  make ARCH=arm64   # 指定架构编译 (macOS)"
	@echo "  make universal    # 编译 Universal Binary"
	@echo "  make run          # 编译并运行"
