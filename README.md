# 光伏发电站 IEC 60870-5-104 协议模拟器

基于开源 lib60870 库实现的光伏电站 IEC 104 从站模拟器。

> 当前版本已从“写死 30 点位”升级为“CSV 动态点位驱动”，可直接扩展到万级点位用于压测。

## 改造背景

原始实现内置固定点位（3 台逆变器，共 30 个遥测点），适合协议联调，但不适合采集器和平台的高并发压力测试。  
为支持电站场景下的万级/十万级点位扩展，项目新增了 CSV 配置驱动能力：

- 模拟器启动时加载 `sim_rules.csv` 动态建点；
- 通过脚本自动生成 1 万点配置（默认 300 台逆变器）；
- 后续可在不改 C 代码的情况下继续扩容点位规模。

## 项目结构

```
.
├── src/
│   └── pv_simulator.c              # PV 模拟器源码
├── lib/
│   └── lib60870/                   # IEC 60870-5-104 协议库 (GPLv3)
├── docs/
│   ├── PV_SIMULATOR_README.md      # 详细文档
│   ├── POINT_TABLE.md              # 旧版固定点位表与变化规则
│   └── SIM_RULES_SPEC.md           # CSV 点位与仿真规则规范
├── config/
│   └── sim_rules.csv               # 运行时加载的点位配置（可达万级）
├── scripts/
│   ├── build.sh                    # 多平台编译脚本
│   ├── deploy.sh                   # 部署脚本 (本地交叉编译)
│   ├── pv_ctl.sh                   # 服务控制脚本
│   ├── gen_sim_rules_csv.py        # 生成 sim_rules.csv（默认 1 万点）
│   └── export_zdaq_xlsx.py         # 导出 zdaq 可导入 xlsx 模板
├── dist/                           # 编译输出目录
├── Makefile                        # 构建配置
└── README.md                       # 本文件
```

## 功能特性

- **IEC 60870-5-104 从站实现**
  - 支持总召唤 (General Interrogation, COT=20)
  - 支持变化上报 (Spontaneous Transmission, COT=3)
  - 支持遥控命令 (Remote Control)

- **CSV 动态点位配置**
  - 启动时加载 `config/sim_rules.csv`
  - 支持 1 万点及以上规模（受机器资源和网络吞吐影响）
  - 点位字段兼容 zdaq 导入列（前 11 列）并扩展仿真规则列

- **仿真规则引擎（sim_class）**
  - `fixed` / `random_uniform` / `random_walk`
  - `solar_scaled`（太阳系数缩放）
  - `derived_formula`（派生公式）
  - `status_from_control`（控制联动状态）
  - `counter`（累加量）

- **大规模点位生成**
  - 脚本一键生成万级 CSV 配置
  - 默认生成：300 台逆变器 * 30 点 + 电站辅助点补齐到 10000 点

配置规范请参阅 [docs/SIM_RULES_SPEC.md](docs/SIM_RULES_SPEC.md)  
旧版固定点位说明请参阅 [docs/POINT_TABLE.md](docs/POINT_TABLE.md)

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
# 使用默认配置与端口
./pv_simulator

# 指定 CSV 配置文件
./pv_simulator config/sim_rules.csv

# 指定 CSV 配置文件和端口（避免 2404 端口冲突）
./pv_simulator config/sim_rules.csv 2504
```

默认监听 `0.0.0.0:2404`，站地址（CA）由 `address` 字段中的 `CA!TYPE!IOA` 决定。

### 生成 1 万点配置

```bash
# 默认生成 1 万点（300 台逆变器）
python3 scripts/gen_sim_rules_csv.py

# 指定目标点位数和逆变器数量
python3 scripts/gen_sim_rules_csv.py --target-points 10000 --inverters 300 --output config/sim_rules.csv
```

### 导出 zdaq 导入模板

```bash
# 从 sim_rules.csv 导出 zdaq 导入模板（前 11 列）
python3 scripts/export_zdaq_xlsx.py \
  --input config/sim_rules.csv \
  --output scripts/IEC104-tags.generated.xlsx
```

### 测试连接

使用 IEC 104 客户端连接到模拟器端口（默认 `localhost:2404`），发送总召唤命令即可获取当前 CSV 定义的所有读点。

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
export PV_REMOTE_CSV="/opt/pv_simulator/config/sim_rules.csv"  # 默认: $PV_REMOTE_DIR/config/sim_rules.csv
export PV_REMOTE_PORT="2404"                                   # 默认: 2404
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
pv_ctl start /opt/pv_simulator/config/sim_rules.csv 2404
pv_ctl status
pv_ctl log
```

`pv_ctl` 参数说明：

```bash
pv_ctl start [csv_path] [port]
pv_ctl restart [csv_path] [port]
```

### 日志轮转（已启用方案 A）

`deploy.sh init/update` 会自动下发 `logrotate` 配置到远程服务器：

- 配置文件：`/etc/logrotate.d/pv_simulator`
- 日志文件：`/var/log/pv_simulator.log`
- 轮转策略：`size 100M`、保留 `14` 份、`compress`、`copytruncate`

这样模拟器长期运行时日志会自动轮转，避免日志无限增长占满磁盘。

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
- [docs/SIM_RULES_SPEC.md](docs/SIM_RULES_SPEC.md) - CSV 点位与仿真规则规范
- [docs/POINT_TABLE.md](docs/POINT_TABLE.md) - 旧版固定点位表、数据变化规则

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
