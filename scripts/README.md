# 脚本工具集

本目录包含光伏模拟器的管理脚本。

## 脚本列表

| 脚本 | 用途 |
|------|------|
| `build.sh` | 多平台编译脚本 |
| `deploy.sh` | 服务器部署脚本 |
| `pv_ctl.sh` | 启停控制脚本 |

## build.sh - 编译脚本

支持编译多个 CPU 架构的版本。

```bash
# 编译当前平台
./build.sh native

# macOS: 编译 arm64 + x86_64 + universal
./build.sh macos

# Linux: 编译 x86_64
./build.sh linux

# 清理
./build.sh clean
```

编译产物输出到 `../../dist/` 目录:
- `pv_simulator-darwin-arm64` - macOS Apple Silicon
- `pv_simulator-darwin-x86_64` - macOS Intel
- `pv_simulator-darwin-universal` - macOS 通用二进制
- `pv_simulator-linux-x86_64` - Linux x86_64

## deploy.sh - 部署脚本

支持首次部署和更新部署到远程服务器。

```bash
# 首次部署 (创建目录、安装依赖、编译、配置 systemd)
./deploy.sh init

# 更新部署 (上传新代码、重新编译、重启服务)
./deploy.sh update

# 回滚到上一版本
./deploy.sh rollback

# 远程控制
./deploy.sh start    # 启动
./deploy.sh stop     # 停止
./deploy.sh status   # 状态
./deploy.sh log      # 日志
```

### 环境变量

```bash
# 部署到其他服务器
PV_REMOTE_HOST=user@your-server ./deploy.sh init

# 自定义安装目录
PV_REMOTE_DIR=/home/user/pv_sim ./deploy.sh init
```

### 默认配置

- 服务器: `root@8.140.239.5`
- 安装目录: `/opt/pv_simulator`
- 端口: `2404`

## pv_ctl.sh - 启停控制脚本

用于本地或服务器上控制模拟器运行。

```bash
./pv_ctl.sh start    # 启动
./pv_ctl.sh stop     # 停止
./pv_ctl.sh restart  # 重启
./pv_ctl.sh status   # 查看状态
./pv_ctl.sh log      # 查看日志
```

## 典型工作流

### 开发流程

```bash
# 1. 修改源码
vim ../pv_simulator_lib60870.c

# 2. 本地编译测试
./build.sh native
../../pv_simulator

# 3. 部署到服务器
./deploy.sh update
```

### 首次部署新服务器

```bash
# 1. 设置服务器地址
export PV_REMOTE_HOST=root@new-server.com

# 2. 首次部署
./deploy.sh init

# 3. 启动服务
./deploy.sh start

# 4. 设置开机自启 (可选)
ssh $PV_REMOTE_HOST "systemctl enable pv-simulator"
```

### 紧急回滚

```bash
# 发现问题，回滚到上一版本
./deploy.sh rollback
```
