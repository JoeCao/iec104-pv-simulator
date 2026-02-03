# 光伏发电站 IEC 60870-5-104 协议模拟器

基于开源 lib60870 库实现的光伏电站 IEC 104 从站模拟器。

## 功能特性

### 1. 总召唤 (General Interrogation)

- **触发方式**: 主站发送 C_IC_NA_1 (TypeID=100) 命令，QOI=20
- **传输原因**: COT=20 (INTERROGATED_BY_STATION)
- **响应流程**:
  1. 收到总召唤命令
  2. 发送 ACT_CON 确认
  3. 发送所有遥测数据 (M_ME_NC_1)
  4. 发送所有遥信数据 (M_SP_NA_1)
  5. 发送 ACT_TERM 结束

### 2. 变化上报 (Spontaneous Transmission)

- **触发方式**: 数据值变化超过阈值时自动上报
- **传输原因**: COT=3 (SPONTANEOUS)
- **变化检测**:
  - 浮点数变化阈值: 1.0 (可配置)
  - 辐照度变化阈值: 50.0 W/m²
  - 电量变化阈值: 10.0 kWh
  - 状态变化: 立即上报
- **上报间隔**: 最小 5 秒 (防止频繁上报)

### 3. 遥控命令 (Remote Control)

- **命令类型**: C_SC_NA_1 (TypeID=45) 单点命令
- **控制点**: IOA 2001-2003 (逆变器启停)
- **响应**: 发送 ACT_CON 确认

## 数据点配置

### 遥测量 (M_ME_NC_1, TypeID=13)

| IOA 范围 | 数量 | 描述 |
|----------|------|------|
| 1-10 | 10 | 逆变器1: DC电压/电流/功率, AC电压ABC/电流ABC/功率 |
| 11-20 | 10 | 逆变器2: 同上 |
| 21-30 | 10 | 逆变器3: 同上 |
| 100-105 | 6 | 环境: 辐照度、环境温度、组件温度、风速、风向、湿度 |
| 200-205 | 6 | 电站: 总功率、无功、功率因数、频率、日发电量、累计发电量 |

#### 逆变器数据点详情

| 偏移 | 名称 | 单位 | 说明 |
|------|------|------|------|
| +0 | DC_Voltage | V | 直流电压 (600-750V) |
| +1 | DC_Current | A | 直流电流 (0-45A) |
| +2 | DC_Power | kW | 直流功率 |
| +3 | AC_Voltage_A | V | 交流A相电压 (~400V) |
| +4 | AC_Voltage_B | V | 交流B相电压 |
| +5 | AC_Voltage_C | V | 交流C相电压 |
| +6 | AC_Current_A | A | 交流A相电流 |
| +7 | AC_Current_B | A | 交流B相电流 |
| +8 | AC_Current_C | A | 交流C相电流 |
| +9 | AC_Power | kW | 交流输出功率 |

#### 环境数据点详情

| IOA | 名称 | 单位 | 范围 |
|-----|------|------|------|
| 100 | Irradiance | W/m² | 0-1200 |
| 101 | Ambient_Temp | °C | -20~50 |
| 102 | Module_Temp | °C | -20~80 |
| 103 | Wind_Speed | m/s | 0-30 |
| 104 | Wind_Direction | ° | 0-360 |
| 105 | Humidity | % | 20-95 |

#### 电站汇总数据点详情

| IOA | 名称 | 单位 | 说明 |
|-----|------|------|------|
| 200 | Total_Active_Power | kW | 总有功功率 |
| 201 | Total_Reactive_Power | kVar | 总无功功率 |
| 202 | Power_Factor | - | 功率因数 (0.96-1.0) |
| 203 | Grid_Frequency | Hz | 电网频率 (~50Hz) |
| 204 | Daily_Energy | kWh | 日发电量 (累计) |
| 205 | Total_Energy | MWh | 累计发电量 |

### 遥信量 (M_SP_NA_1, TypeID=1)

| IOA | 名称 | 说明 |
|-----|------|------|
| 1001 | INV1_Running_Status | 逆变器1运行状态 |
| 1002 | INV2_Running_Status | 逆变器2运行状态 |
| 1003 | INV3_Running_Status | 逆变器3运行状态 |

### 遥控点 (C_SC_NA_1, TypeID=45)

| IOA | 名称 | 说明 |
|-----|------|------|
| 2001 | INV1_Start_Stop | 逆变器1启停控制 (1=启动, 0=停止) |
| 2002 | INV2_Start_Stop | 逆变器2启停控制 |
| 2003 | INV3_Start_Stop | 逆变器3启停控制 |

## 数据模拟特性

### 太阳辐照模拟

- 6:00 日出，18:00 日落
- 12:00 达到峰值 (~1000 W/m²)
- 使用正弦曲线模拟
- 随机云层遮挡效应 (±15%)

### 功率计算

```
DC功率 = DC电压 × DC电流
AC功率 = DC功率 × 效率(97%)
总功率 = Σ(各逆变器AC功率)
```

### 发电量累计

```
日发电量 += 总功率 × Δt / 3600  (kWh)
累计发电量 += 总功率 × Δt / 3600000  (MWh)
```

## 连接参数

| 参数 | 值 |
|------|-----|
| 监听地址 | 0.0.0.0 |
| 端口 | 2404 |
| 站地址 (CA) | 1 |
| k 参数 | 10 |
| w 参数 | 10 |

## 编译方法

### macOS (Apple Silicon)

```bash
cd lib60870/lib60870-C
make clean
make CFLAGS="-arch arm64"
cc -arch arm64 -o pv_simulator examples/pv_simulator_lib60870.c \
   -Isrc/inc/api -Isrc/hal/inc -Lbuild -llib60870 -lpthread
```

### Linux (x86_64)

```bash
cd lib60870/lib60870-C
make
gcc -o pv_simulator examples/pv_simulator_lib60870.c \
   -Isrc/inc/api -Isrc/hal/inc -Lbuild -llib60870 -lpthread -lm
```

## 运行方法

```bash
./pv_simulator
```

输出示例:
```
======================================================================
       光伏发电站 IEC 60870-5-104 协议模拟器 (开源版)
       基于 lib60870 开源库
======================================================================

数据点配置:
  IOA 1-30:      逆变器1-3 模拟量 (M_ME_NC_1, TypeID=13)
  IOA 100-105:   环境监测数据 (M_ME_NC_1, TypeID=13)
  IOA 200-205:   电站汇总数据 (M_ME_NC_1, TypeID=13)
  IOA 1001-1003: 逆变器状态 (M_SP_NA_1, TypeID=1)
  IOA 2001-2003: 逆变器控制 (C_SC_NA_1, TypeID=45)

支持功能:
  - 总召唤 (General Interrogation, COT=20)
  - 变化上报 (Spontaneous, COT=3)
  - 遥控命令 (Single Command)

服务器启动成功
监听地址: 0.0.0.0:2404
站地址 (Common Address): 1

======================================================================
服务器运行中... 按 Ctrl+C 停止
======================================================================

[10:30:00] 太阳系数: 0.87 | 总功率: 98.5kW | 日发电量: 245.3kWh
  逆变器1: 运行 | 功率: 32.8kW
  逆变器2: 运行 | 功率: 33.1kW
  逆变器3: 运行 | 功率: 32.6kW

[变化上报] IOA=200 (Total_Active_Power) 值=99.12
[变化上报] IOA=100 (Irradiance) 值=872.50
```

## 协议交互示例

### 总召唤流程

```
主站 -> 从站: C_IC_NA_1 (TypeID=100, COT=6, QOI=20)
从站 -> 主站: C_IC_NA_1 (TypeID=100, COT=7)  [ACT_CON]
从站 -> 主站: M_ME_NC_1 (TypeID=13, COT=20)  [逆变器数据]
从站 -> 主站: M_ME_NC_1 (TypeID=13, COT=20)  [环境数据]
从站 -> 主站: M_ME_NC_1 (TypeID=13, COT=20)  [电站数据]
从站 -> 主站: M_SP_NA_1 (TypeID=1, COT=20)   [状态数据]
从站 -> 主站: C_IC_NA_1 (TypeID=100, COT=10) [ACT_TERM]
```

### 变化上报流程

```
从站 -> 主站: M_ME_NC_1 (TypeID=13, COT=3, IOA=200, Value=98.5)
从站 -> 主站: M_SP_NA_1 (TypeID=1, COT=3, IOA=1001, Value=0)
```

### 遥控流程

```
主站 -> 从站: C_SC_NA_1 (TypeID=45, COT=6, IOA=2001, Value=0)
从站 -> 主站: C_SC_NA_1 (TypeID=45, COT=7)  [ACT_CON]
从站 -> 主站: M_SP_NA_1 (TypeID=1, COT=3, IOA=1001, Value=0)  [状态变化上报]
```

## 配置修改

如需修改变化检测阈值，编辑源码中的宏定义:

```c
#define FLOAT_CHANGE_THRESHOLD 1.0    // 浮点数变化阈值
#define SPONTANEOUS_INTERVAL 5        // 变化上报最小间隔(秒)
```

## 依赖

- [lib60870](https://github.com/mz-automation/lib60870) - 开源 IEC 60870-5-104 协议库 (GPLv3)

## 许可证

本模拟器代码遵循 GPLv3 许可证（与 lib60870 保持一致）。
