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
│   └── PV_SIMULATOR_README.md      # 详细文档
├── scripts/
│   ├── build.sh                    # 多平台编译脚本
│   ├── deploy.sh                   # 部署脚本
│   └── pv_ctl.sh                   # 服务控制脚本
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

### 使用 Makefile

```bash
make              # 编译（默认架构）
make clean        # 清理
make run          # 编译并运行
make install      # 安装到 /usr/local/bin
make help         # 显示帮助
```

### macOS Universal Binary

```bash
make universal    # 编译 arm64 + x86_64 通用二进制
```

### 使用编译脚本

```bash
./scripts/build.sh all      # 编译所有平台
./scripts/build.sh arm64    # 仅编译 arm64
./scripts/build.sh x86_64   # 仅编译 x86_64
./scripts/build.sh clean    # 清理
```

## 详细文档

完整的功能说明、数据点配置、协议交互示例，请参阅：
- [docs/PV_SIMULATOR_README.md](docs/PV_SIMULATOR_README.md)

## 依赖

- **lib60870**: 开源 IEC 60870-5-104 协议库 (GPLv3)
  - 官方仓库: https://github.com/mz-automation/lib60870
  - 本项目包含完整源码，无需单独安装

## 系统要求

- **编译器**: GCC 或 Clang
- **操作系统**: Linux, macOS, BSD
- **依赖库**: pthread, math (标准库)

## 许可证

本项目遵循 **GPLv3** 许可证（与 lib60870 保持一致）。

## 贡献

欢迎提交 Issue 和 Pull Request。

## 参考

- IEC 60870-5-104 协议标准
- lib60870 文档: https://github.com/mz-automation/lib60870
