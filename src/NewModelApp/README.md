# NewModelApp — Simulink 模型一键新建工具

MATLAB GUI 工具，通过图形界面快速创建 Simulink 模型并配置代码生成参数，支持从 Excel 导入端口定义及 Code Mapping 设置。

## 快速开始

```matlab
NewModelApp
```

## 功能概览

| 功能 | 说明 |
|------|------|
| **模型名称** | 输入模型名，校验合法性；已存在时弹窗选择覆盖 / 加数字后缀 / 取消 |
| **离散模型** | 勾选后启用固定步长离散求解器，可设置时间步长 |
| **TLC 文件** | 选择系统目标文件（默认 `ert.tlc`） |
| **仅生成代码** | 勾选后设置 `GenCodeOnly=on` |
| **数据字典** | 勾选后选择 `.sldd` 文件，通过 `set_param(..., 'DataDictionary', ...)` 关联 |
| **Excel 导入端口** | 从 Excel 读取端口定义自动创建 Inport/Outport 块 |
| **Code Mapping** | 勾选后通过 `coder.mapping.utils.create` 为端口设置 StorageClass / Identifier |
| **创建后打开模型** | 勾选则创建完保持模型打开，不勾选则保存后关闭 |

## 界面布局

```
┌──────────────────────────────────────────────┐
│              新建 Simulink 模型               │
│──────────────────────────────────────────────│
│  模型名称: [myModel______________________]    │
│                                              │
│  ☐ 离散模型                                  │
│     时间步长: [0.01    ]                     │
│                                              │
│  TLC 文件: [ert.tlc________________] [浏览]  │
│  ☐ 仅生成代码                                │
│                                              │
│  ☐ 关联数据字典                              │
│     字典路径: [______________________] [浏览] │
│                                              │
│  ☐ 从 Excel 导入端口                          │
│     Excel 路径: [______________] [浏览]       │
│     ☐ 使用 Code Mapping（StorageClass/ID）   │
│                                              │
│  ☑ 创建后打开模型                            │
│        [ 创 建 模 型 ]                        │
│                                              │
│  状态: ✓ 模型 "myModel" 创建成功              │
└──────────────────────────────────────────────┘
```

## Excel 导入端口格式

Excel 需包含两个工作表 `Inputs`（或 `Input`/`输入`）和 `Outputs`（或 `Output`/`输出`），列定义如下：

| A 序号 | B 端口名称 | C 数据类型 | D StorageClass | E Identifier | F HeaderFile | G DefinitionFile |
|:------:|:----------:|:---------:|:--------------:|:------------:|:-----------:|:---------------:|
| 1 | speed | double | ExportedGlobal | speed_Global | | |
| 2 | angle | double | Auto | | myModel_types.h | myModel.c |
| 3 | enable | boolean | ImportedExtern | ext_enable | ext_types.h | |

- **B 列（端口名称）** — 必填，作为块路径名
- **C 列（数据类型）** — 可选，设为块 `OutDataTypeStr`；为空则继承默认
- **D 列（StorageClass）** — 可选，需勾选 Code Mapping 才生效；为空设为 `Auto`
- **E 列（Identifier）** — 可选，需勾选 Code Mapping 才生效；为空不设置
- **F 列（HeaderFile）** — 可选，需勾选 Code Mapping 才生效；指定生成的变量声明在哪个头文件中
- **G 列（DefinitionFile）** — 可选，需勾选 Code Mapping 才生效；指定生成的变量定义在哪个源文件中

### 端口模板生成

```matlab
createExcelTemplate    % 生成 port_template.xlsx
```

## Code Mapping 工作流

1. 勾选 **从 Excel 导入端口** → 选择 Excel 文件
2. 勾选 **使用 Code Mapping**（设置 StorageClass / Identifier）
3. 点击 **创建模型**

后台流程：`new_system` → 配置求解器/TLC → 导入端口 → **保存模型** → `coder.mapping.utils.create` → `setInport` / `setOutport` 设置 StorageClass/Identifier → 再次保存 → 完成

## 已有模型时

当输入的名称与已有模型（已加载或 `.slx` 文件）冲突时，弹出选择：

| 选项 | 行为 |
|------|------|
| **覆盖** | 关闭已有模型、删除 `.slx` 文件，用原名称重建 |
| **加数字后缀** | 自动查找 `名称1`、`名称2`…… 直到找到空名 |
| **取消** | 不做任何操作 |

## PortExtractor（配套工具）

`ref/Port/` 目录下的端口提取工具，从已有 Simulink 模型中提取端口信息到 Excel：

```matlab
PortExtractorGUI        % 图形界面
PortExtractor('myModel', 1)   % 命令行
```

生成的 Excel 可直接用于 `NewModelApp` 导入。

## 依赖

- MATLAB R2019b 或更高
- Simulink
- （可选）Embedded Coder（用于 Code Mapping）
- （可选）Simulink Data Dictionary（用于数据字典关联）
