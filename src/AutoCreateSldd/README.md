# AutoCreateSldd

MATLAB/Simulink **数据字典（.sldd）与 Excel 双向同步工具**。

用 Excel 维护 Signal / Parameter / Const / Enum / Bus / BusElement，一键生成 Simulink 对象并写入 `.sldd`；
也可以把已有 `.sldd` 反向导出回 Excel。全部操作集中在图形界面里，无需手写脚本。

```
Excel 模板  ──►  校验  ──►  生成 objects.m  ──►  执行  ──►  写入 .sldd
   ▲                                                              │
   └────────────────  SLDD → Excel 反向同步  ◄────────────────────┘
```

---

## 1. 环境要求

| 依赖 | 说明 |
|---|---|
| MATLAB | R2024b（工程文件记录版本；需 Simulink，用于 `Simulink.data.dictionary`） |
| Python 3 | 生成 Excel 模板、反向同步时使用 |
| `openpyxl` | Python 依赖，`pip install openpyxl` |

> 从 v2.0 起，Python 路径**不再自动搜索**，必须在界面里手动指定（见 [§5 二级菜单](#5-右键二级菜单)）。
> 未设置时「生成模板」会弹窗引导你去设置，或退回 MATLAB 内置的「基本模板」生成。

## 2. 安装与运行

**方式 A：安装 App（推荐）**

双击 `AutoCreateSldd.mlappinstall` → MATLAB 中安装 → 在 **Apps** 标签页里启动 `AutoCreateSldd`。

**方式 B：源码运行**

把本目录加入 MATLAB 搜索路径，然后执行：

```matlab
>> sldd_gui
```

## 3. 快速开始

1. 点 **生成模板**，选择「含示例数据」或「空模板」，得到一份 8 个 Sheet 的 Excel。
2. 在 Excel 里填写各 Sheet（蓝色表头为必填列，浅蓝色为选填列，下拉列表取自 `Config` 表）。
3. 回到界面：**浏览...** 选中 Excel → **载入工作表**。
4. 勾选要处理的工作表（Signal / Parameter / Bus / BusElement …），可先 **校验所选工作表** 和 **预览所选工作表**。
5. 选「仅生成 objects」只产出 M 脚本；选「完整导入到 SLDD」则生成 → 执行 → 写入数据字典。
6. 需要回写时，点 **↔ SLDD → Excel 反向同步**。默认是增量模式（同名行覆盖、新行追加、旧行保留）；
   若想让 Excel 与 SLDD 完全一致，先勾选参数区的「反向同步时清空Excel旧内容（危险）」，详见 [§8](#8-注意事项)。

## 4. Excel 模板结构

生成的模板包含 8 个 Sheet，**Sheet 名即数据类别**：

| Sheet | 主要列 | 必填列 |
|---|---|---|
| `History` | Version, ChangeDate, Changer, Content | — |
| `Signal` | VariableName, Package, Object, CustomStorageClass, DataType, InitialValue, HeaderFile, DefinitionFile, Description, Min, Max, Unit, Dimensions, Complexity | 前 5 列 |
| `Parameter` | 同 `Signal` | 前 6 列（含 InitialValue） |
| `Const` | Name, Package, CustomStorageClass, Value, DataType, HeaderFile | 前 3 列 |
| `Enum` | EnumName, EnumNumbers, Value, DataType | 全部 |
| `Bus` | BusName, Description, HeaderFile, Alignment, PreserveElementDimensions, DataScope | 除 Description 外 |
| `BusElement` | BusName, ElementName, DataType, Dimensions, Description, Unit | 前 4 列 |
| `Config` | Package, Object, Storage class, Data Type, Unit, DimensionsMode, Complexity, DataScope | — |

- `Config` 表是其他 Sheet 下拉列表的数据源，内容可通过二级菜单「模板 Config 设置…」调整。
- `Enum` 会额外生成独立的 `.m` 类定义文件。
- 校验（`validateDataDictionary`）会检查：必要列是否存在、必填单元格是否为空、Signal/Parameter 变量名重复、Bus 名重复、`BusElement` 是否引用了未定义的 Bus、`DataType=Bus:xxx` 是否引用了已定义的 Bus。

## 5. 右键二级菜单

在主窗口空白处右键：

| 菜单项 | 作用 | 落盘文件 |
|---|---|---|
| **模板 Config 设置…** | 编辑 `Config` 表各列的候选值（也是各 Sheet 下拉列表的数据源），可增删/上下移动/恢复默认 | `template_config.json` |
| **Python 路径设置…** | 手动指定 `python.exe`（支持填完整路径、安装目录或裸命令名），可「测试」验证、可「清除设置」 | `python_config.json` |

两个配置文件都生成在 GUI/App 同目录，且已加入 `.gitignore`（随机器而异，不入库）。
若 Python 路径无效或未设置，生成模板时会提示并可直接打开设置界面。

## 6. 命令行用法（可选）

Python 侧脚本可独立调用：

```bash
python generate_template.py                            # 弹窗选保存路径
python generate_template.py out.xlsx                   # 指定输出
python generate_template.py --empty out.xlsx           # 空模板
python generate_template.py --config cfg.json out.xlsx # 指定 Config 配置
```

MATLAB 侧函数也可直接调用（GUI 内部使用的就是它们）：

```matlab
Excel2Workspace(AllSheets, fullpath, outputFilename, filename, selection)  % Excel → objects.m
[isValid, issues] = validateDataDictionary(excelPath, selectedSheets)      % 数据校验
sldd_to_excel()                                                            % SLDD → Excel（弹窗选文件）
```

## 7. 目录结构

```
AutoCreateSldd/
├─ sldd_gui.m                    GUI 主入口（App 主程序）
├─ Excel2Workspace.m             Excel → Simulink 对象 M 脚本
├─ validateDataDictionary.m      Excel 数据字典校验
├─ sldd_to_excel.m               SLDD → Excel 反向同步（也可单独运行）
├─ sldd_template_config.m        「模板 Config 设置」二级界面
├─ sldd_python_config.m          「Python 路径设置」二级界面
├─ getPythonExe.m                Python 路径唯一来源（只读配置，不自动搜索）
├─ python_config_path.m          python_config.json 位置解析
├─ check_python_exe.m            路径规范化 + 可用性校验
├─ generate_template.py          生成 Excel 模板（openpyxl）
├─ sldd_to_excel_helper.py       把 SLDD 数据写回 Excel（保留格式）
├─ +myPackage/                   自定义存储类包
│   ├─ csc_registration.m        自定义存储类注册（16 个 CSC + 5 个内存段）
│   ├─ @Signal/Signal.m
│   └─ @Parameter/Parameter.m
├─ AutoCreateSldd.prj            打包工程（生成 .mlappinstall）
└─ AutoCreateSldd_resources/     App 图标资源
```

## 8. 注意事项

- **自定义存储类**：`+myPackage/csc_registration.m` 由 Simulink Custom Storage Class Designer 生成，注册了
  16 个存储类（`YS_SelectRAMSignal`、`YS_SelectRAMPara`、`Define`、`Const`、`Volatile`、`ConstVolatile`、
  `ExportToFile`、`ImportFromFile`、`Struct`、`GetSet` …）与 5 个内存段（`YS_RAMSignal`、`YS_RAMPara`、
  `MemConst`、`MemVolatile`、`MemConstVolatile`），由 Simulink 调用（不会被 `.m` 代码直接引用）。
  若要在其他机器上生成代码，需要把 `+myPackage` 目录放在 MATLAB 搜索路径上。
- **反向同步默认是增量模式**：同名行覆盖、新条目追加，不删除 Excel 里已有的行。
- **「反向同步时清空Excel旧内容」**（参数区，危险）：勾选后 Signal / Parameter / Const / Bus / BusElement
  五张表以 SLDD 为准**整表重写**，Excel 中不在 SLDD 里的行会被删除（`History` / `Config` 表不受影响）。
- **「同步时删除 SLDD 中多余的变量」**是危险选项，勾选后会清理字典里不在本次生成列表中的条目，请谨慎使用。
- 打包 App 后，`python_config.json` / `template_config.json` 位于 App 安装目录；换机器需要重新设置 Python 路径。
