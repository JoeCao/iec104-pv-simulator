# sim-rules 规范（CSV 主配置）

## 目标

使用一份 `CSV` 作为点位与仿真规则的唯一数据源（Single Source of Truth）：

- 模拟器直接加载该 `CSV` 运行；
- 通过脚本将该 `CSV` 导出为 `xlsx`（`IEC104-tags.xlsx` 格式）供 zdaq 导入；
- 避免维护两套配置导致的不一致。

---

## 文件约定

- **主配置文件**：`config/sim_rules.csv`
- **编码**：UTF-8（无 BOM）
- **分隔符**：英文逗号 `,`
- **首行**：必须为表头
- **数值格式**：小数点使用 `.`，不使用千分位

---

## 列定义（v1）

为兼容 zdaq，前 11 列保持与 `IEC104-tags.xlsx` 一致；后续列为模拟器扩展列。

| 列名 | 必填 | 示例 | 说明 |
|---|---|---|---|
| group | 是 | IEC104 | 采集组名，导出 xlsx 时原样输出 |
| interval | 是 | 1000 | 采集周期（ms） |
| name | 是 | 逆变器1直流电压 | 点位显示名 |
| address | 是 | 1!M_ME_NC!1 | IEC104 地址，格式 `CA!TYPE!IOA` |
| attribute | 是 | Read | `Read` 或 `Write` |
| type | 是 | FLOAT | 数据类型，`FLOAT` / `BIT` |
| description | 否 | 逆变器1直流电压 | 描述 |
| decimal | 否 | 0 | 小数位（保持与现有导入约定一致） |
| precision | 否 | 2 | 精度展示 |
| bias | 否 | 0 | 偏移量 |
| identity | 是 | INV1_DC_Voltage | 业务唯一标识（推荐全局唯一） |
| sim_class | 是 | solar_scaled | 仿真模型类型（见下文） |
| min | 条件 | 600 | 最小值（FLOAT 常用） |
| max | 条件 | 750 | 最大值（FLOAT 常用） |
| noise | 否 | 10 | 随机扰动幅值（绝对值） |
| deadband | 否 | 1.0 | 变化上报死区 |
| update_ms | 否 | 1000 | 该点更新周期（ms） |
| formula | 条件 | dc_v * dc_i / 1000 | 公式（`derived_formula` 必填） |
| depends_on | 否 | INV1_DC_Voltage;INV1_DC_Current | 依赖点列表，分号分隔 |
| init_value | 否 | 0 | 初始值 |
| control_ref | 条件 | INV1_Control | 控制关联点（状态/遥控场景） |
| enabled | 否 | 1 | `1`=启用，`0`=忽略 |

> 说明：`min/max/formula/control_ref` 为条件必填，取决于 `sim_class`。

---

## sim_class 定义

| sim_class | 适用 type | 含义 | 关键字段 |
|---|---|---|---|
| fixed | FLOAT/BIT | 固定值 | `init_value` |
| random_uniform | FLOAT | 区间均匀随机 | `min,max[,noise]` |
| random_walk | FLOAT | 随机游走（有边界） | `min,max[,noise]` |
| solar_scaled | FLOAT | 按太阳系数缩放 | `min,max[,noise]` |
| derived_formula | FLOAT/BIT | 由公式计算 | `formula[,depends_on]` |
| status_from_control | BIT | 状态由控制点驱动 | `control_ref` |
| counter | FLOAT | 单调累加量（如电量） | `init_value[,noise]` |

---

## 校验规则

## 1) 唯一性

- `identity` 必须唯一；
- `address` 推荐唯一（至少在同一 `attribute` 与同一实例内唯一）。

## 2) 地址格式

- `address` 必须匹配：`^\d+![A-Z0-9_]+!\d+$`
- `CA`（Common Address）建议范围：`1~65535`
- `IOA` 建议范围：`1~16777215`（IEC104 三字节地址）

## 3) 类型一致性

- `type=BIT` 时，值域应为 `0/1`；
- `type=FLOAT` 时，`min/max/init_value/noise/deadband` 必须可解析为浮点数。

## 4) 区间合法性

- 若给定 `min,max`，必须满足 `min <= max`；
- `noise >= 0`，`deadband >= 0`，`update_ms > 0`。

## 5) 写点规则

- `attribute=Write` 的点，建议 `sim_class=fixed`（仅用于接收控制）；
- 若是控制量（如 `C_SC_NA`），建议同时存在对应 `status_from_control` 的状态点。

---

## 推荐分层

- **主数据层**：`sim_rules.csv`（唯一维护入口）
- **导出层**：`scripts/export_zdaq_xlsx.py` 生成 `scripts/IEC104-tags.xlsx`
- **运行层**：模拟器加载 `sim_rules.csv`（可附加启动参数筛选启用点）

---

## 最小示例

```csv
group,interval,name,address,attribute,type,description,decimal,precision,bias,identity,sim_class,min,max,noise,deadband,update_ms,formula,depends_on,init_value,control_ref,enabled
IEC104,1000,逆变器1直流电压,1!M_ME_NC!1,Read,FLOAT,逆变器1直流电压,0,2,0,INV1_DC_Voltage,solar_scaled,600,750,10,1,1000,,,0,,1
IEC104,1000,逆变器1直流电流,1!M_ME_NC!2,Read,FLOAT,逆变器1直流电流,0,2,0,INV1_DC_Current,solar_scaled,0,45,2,1,1000,,,0,,1
IEC104,1000,逆变器1直流功率,1!M_ME_NC!3,Read,FLOAT,逆变器1直流功率,0,2,0,INV1_DC_Power,derived_formula,,,,1,1000,INV1_DC_Voltage*INV1_DC_Current/1000,INV1_DC_Voltage;INV1_DC_Current,0,,1
IEC104,1000,逆变器1运行状态,1!M_SP_NA!1001,Read,BIT,逆变器1运行状态,0,0,0,INV1_Status,status_from_control,,,,0,200,,,1,INV1_Control,1
IEC104,1000,逆变器1启停控制,1!C_SC_NA!2001,Write,BIT,逆变器1启停控制,0,0,0,INV1_Control,fixed,,,,0,0,,,1,,1
```

---

## 与 zdaq 的兼容约定

- 导出脚本默认仅导出前 11 列到 `IEC104-tags.xlsx`：
  `group,interval,name,address,attribute,type,description,decimal,precision,bias,identity`
- 仿真扩展列仅供模拟器使用，不写入 zdaq 导入表；
- 如需审计，可在 xlsx 增加第二个 sheet（例如 `sim-rules`）保存全量列（可选）。

---

## 版本管理

- 当前版本：`sim-rules-spec v1`
- 后续新增列时，要求：
  - 保持前 11 列语义不变（兼容 zdaq）；
  - 新列只能追加在末尾，避免破坏旧脚本。
