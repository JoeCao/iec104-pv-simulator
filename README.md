# 光伏发电站 IEC 60870-5-104 协议模拟器

基于开源 lib60870 库实现的光伏电站 IEC 104 从站模拟器。

## 项目结构

```
.
├── src/
│   └── pv_simulator.c              # PV 模拟器源码
├── lib/
│   └── lib60870/                   # IEC 60870-5-104 协议库 (GPLv3)
├── docs/
│   ├── PV_SIMULATOR_README.md      # 详细文档
│   └── POINT_TABLE.md              # 点位表与变化规则
├── scripts/
│   ├── build.sh                    # 多平台编译脚本
│   ├── deploy.sh                   # 部署脚本 (本地交叉编译)
│   └── pv_ctl.sh                   # 服务控制脚本
├── dist/                           # 编译输出目录
├── Makefile                        # 构建配置
└── README.md                       # 本文件
```

## 功能特性

- **IEC 60870-5-104 从站实现**
  - 支持总召唤 (General Interrogation, COT=20)
  - 支持变化上报 (Spontaneous Transmission, COT=3)
  - 支持遥控命令 (Remote Control)

- **光伏电站模拟**
  - 模拟 3 台逆变器（每台 30kW）
  - 真实的太阳辐照曲线（日出 6:00，日落 18:00）
  - 环境监测数据（辐照度、温度、风速等）
  - 电站汇总数据（总功率、发电量等）

- **数据点配置**
  - IOA 1-30: 逆变器 1-3 遥测量（电压、电流、功率）
  - IOA 100-105: 环境监测数据
  - IOA 200-205: 电站汇总数据
  - IOA 1001-1003: 逆变器运行状态
  - IOA 2001-2003: 逆变器控制命令

详细点位表请参阅 [docs/POINT_TABLE.md](docs/POINT_TABLE.md)

## 快速开始

### 编译

```bash
# 使用 Makefile（推荐）
make

# 或使用编译脚本
./scripts/build.sh
```

### 运行

```bash
./pv_simulator
```

服务器将在 `0.0.0.0:2404` 监听，站地址为 1。

### 测试连接

使用 IEC 104 客户端连接到 `localhost:2404`，发送总召唤命令即可获取所有数据点。

## 编译选项

### 本地编译 (macOS/Linux)

```bash
make              # 编译（当前平台）
make clean        # 清理
make run          # 编译并运行
make install      # 安装到 /usr/local/bin
make help         # 显示帮助
```

### macOS Universal Binary

```bash
make universal    # 编译 arm64 + x86_64 通用二进制
```

### 交叉编译 Linux x86_64

在 macOS 上交叉编译 Linux 版本（需要安装 zig）：

```bash
# 安装 zig (仅首次)
brew install zig

# 交叉编译
make linux
```

输出文件: `dist/pv_simulator-linux-x86_64`

### 使用编译脚本

```bash
./scripts/build.sh all      # 编译所有平台
./scripts/build.sh arm64    # 仅编译 arm64
./scripts/build.sh x86_64   # 仅编译 x86_64
./scripts/build.sh clean    # 清理
```

## 部署到服务器

deploy.sh 脚本支持本地交叉编译后直接上传到 Linux 服务器，无需在服务器上安装编译环境。

### 配置

通过环境变量配置目标服务器：

```bash
export PV_REMOTE_HOST="root@your-server-ip"  # 默认: root@8.140.239.5
export PV_REMOTE_DIR="/opt/pv_simulator"     # 默认: /opt/pv_simulator
```

### 部署命令

```bash
# 首次部署 (编译 + 上传 + 配置)
./scripts/deploy.sh init

# 更新部署 (重新编译 + 上传 + 重启)
./scripts/deploy.sh update

# 仅本地编译，不上传
./scripts/deploy.sh build
```

### 远程控制

```bash
./scripts/deploy.sh start    # 启动
./scripts/deploy.sh stop     # 停止
./scripts/deploy.sh restart  # 重启
./scripts/deploy.sh status   # 查看状态
./scripts/deploy.sh log      # 查看日志
```

或者 SSH 到服务器后使用 `pv_ctl` 命令：

```bash
ssh root@your-server
pv_ctl start
pv_ctl status
pv_ctl log
```

## 在 Linux 上编译

本项目可以直接在 Linux 上编译，无需额外配置：

```bash
# 克隆项目
git clone https://github.com/JoeCao/iec104-pv-simulator.git
cd iec104-pv-simulator

# 编译
make

# 运行
./pv_simulator
```

lib60870 的 Makefile 会自动检测操作系统并选择正确的 HAL 实现。

## 详细文档

- [docs/PV_SIMULATOR_README.md](docs/PV_SIMULATOR_README.md) - 功能说明、协议交互示例
- [docs/POINT_TABLE.md](docs/POINT_TABLE.md) - 完整点位表、数据变化规则

## 依赖

- **lib60870**: 开源 IEC 60870-5-104 协议库 (GPLv3)
  - 官方仓库: https://github.com/mz-automation/lib60870
  - 本项目包含完整源码，无需单独安装

## 系统要求

- **编译器**: GCC 或 Clang
- **操作系统**: Linux, macOS, BSD
- **依赖库**: pthread, math (标准库)
- **交叉编译** (可选): zig (`brew install zig`)

## 许可证

本项目遵循 **GPLv3** 许可证（与 lib60870 保持一致）。

## 贡献

欢迎提交 Issue 和 Pull Request。

## 参考

- IEC 60870-5-104 协议标准
- lib60870 文档: https://github.com/mz-automation/lib60870
