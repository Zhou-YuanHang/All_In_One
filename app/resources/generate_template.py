"""
generate_template.py — 生成 SLDD 数据字典 Excel 模板
双击运行即可弹出另存为窗口，默认文件名 MCU_Template.xlsx

特性：
  - 8 个 Sheet 完整复刻（History/Signal/Parameter/Const/Enum/Bus/BusElement/Config）
  - 蓝色/浅蓝表头区分必填/选填列，浅绿数据行底色
  - 下拉列表引用 Config 与 Bus 表作为数据源，方便用户集中管理
  - Config 内容可由 template_config.json 配置（GUI 右键「模板 Config 设置…」生成）
  - 冻结首行、居中格式、宋体 11pt

用法:
  python generate_template.py                       # 弹窗选保存路径（默认配置）
  python generate_template.py <输出.xlsx>           # 指定输出路径
  python generate_template.py --empty <输出.xlsx>   # 空模板（无示例数据）
  python generate_template.py --config cfg.json <输出.xlsx>  # 使用指定 Config 配置
  未传 --config 时自动使用脚本同目录的 template_config.json（存在才生效），
  否则使用内置默认 Config。
"""
import os, sys, json, argparse
from datetime import date
from openpyxl import Workbook
from openpyxl.styles import Font, PatternFill, Alignment, Border, numbers
from openpyxl.worksheet.datavalidation import DataValidation

# ═══ 参数解析 ═══
parser = argparse.ArgumentParser(add_help=False)
parser.add_argument('--empty', action='store_true', help='生成空模板（无示例数据）')
parser.add_argument('--config', default=None, metavar='json', help='Config 配置 json 文件路径')
parser.add_argument('output', nargs='?', default=None, help='输出 xlsx 路径')
try:
    args, _ = parser.parse_known_args()
except SystemExit:
    # 老调用方式（如仅传路径）由 parse_known_args 兼容
    raise
EMPTY = args.empty
CFG_PATH = args.config
OUT_PATH = args.output

if not OUT_PATH:
    import tkinter as tk
    from tkinter import filedialog
    root = tk.Tk()
    root.withdraw()
    root.attributes('-topmost', True)
    OUT_PATH = filedialog.asksaveasfilename(
        title="保存模板文件",
        defaultextension=".xlsx",
        filetypes=[("Excel 工作簿", "*.xlsx"), ("所有文件", "*.*")],
        initialfile="MCU_Template.xlsx"
    )
    root.destroy()
    if not OUT_PATH:
        print("已取消")
        sys.exit(0)

# ═══ Config 默认值（无配置文件时的内置默认，与历史模板一致） ═══
# 键为规范名，顺序即 Config 表从左到右的列序
CFG_COLUMNS = [
    ("Package",        "A", "Package"),
    ("Object",         "B", "Object"),
    ("StorageClass",   "C", "Storage class"),
    ("DataType",       "D", "Data Type"),
    ("Unit",           "E", "Unit"),
    ("DimensionsMode", "F", "DimensionsMode"),
    ("Complexity",     "G", "Complexity"),
    ("DataScope",      "H", "DataScope"),
]
DEFAULT_CONFIG = {
    "Package":        ["myPackage", "Simulink"],
    "Object":         ["Signal", "Parameter"],
    "StorageClass":   ["YS_SelectRAMSignal", "YS_SelectRAMPara", "ExportedGlobal",
                       "ImportedExtern", "ImportedExternPointer", "Auto"],
    "DataType":       ["single", "double", "uint8", "int16", "uint16",
                       "uint32", "boolean", "Bus: FaultBus"],
    "Unit":           ["-", "V", "A", "N*m", "m", "m/s", "℃", "deg"],
    "DimensionsMode": ["Fixed", "Variable"],
    "Complexity":     ["real", "complex"],
    "DataScope":      ["Auto", "Exported", "Imported"],
}
DEFAULT_CFG_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "template_config.json")


def load_config(explicit_path):
    """读取 Config 配置。
    优先级：--config 指定 > 脚本同目录 template_config.json > 内置默认。
    返回 (cfg, 来源描述)；cfg 为 {key: [str,...]}，缺失列回退默认，
    显式空列表 [] 表示该列清空（不填数据、不加下拉）。
    """
    cfg = {k: list(v) for k, v in DEFAULT_CONFIG.items()}
    path = explicit_path
    if not path:
        if os.path.exists(DEFAULT_CFG_FILE):
            path = DEFAULT_CFG_FILE
    if not path or not os.path.exists(path):
        return cfg, None
    try:
        with open(path, 'r', encoding='utf-8') as f:
            data = json.load(f)
        if not isinstance(data, dict):
            print(f"[CONFIG] 警告: 配置文件格式错误(应为对象)，使用内置默认: {path}")
            return cfg, path
        for key in CFG_KEYS:
            if key not in data:
                continue
            raw = data[key]
            if raw is None:
                cfg[key] = []
                continue
            if not isinstance(raw, list):
                raw = [raw]
            items = []
            for v in raw:
                if v is None:
                    continue
                s = str(v).strip()
                if s == "":
                    continue
                items.append(s)
            cfg[key] = items
        return cfg, path
    except Exception as e:
        print(f"[CONFIG] 警告: 配置文件读取失败，使用内置默认: {e}")
        return cfg, path


CFG_KEYS = [c[0] for c in CFG_COLUMNS]
cfg, cfg_used = load_config(CFG_PATH)
if cfg_used:
    print(f"[CONFIG] 使用模板配置文件: {cfg_used}")
else:
    print("[CONFIG] 未找到模板配置文件，使用内置默认 Config。")
if all(len(cfg[k]) == 0 for k in CFG_KEYS):
    print("[CONFIG] 警告: Config 所有列均为空，生成的模板将没有下拉列表。")

# ═══ 样式 ═══
FONT_DEEP  = Font(name="宋体", size=11, bold=True,  color="FFFFFFFF")
FONT_LIGHT = Font(name="宋体", size=11, bold=True,  color="00000000")
FONT_BLUE  = Font(name="宋体", size=11, bold=True,  color="FFFFFFFF")
FONT_ENUM  = Font(name="宋体", size=11, bold=False, color="00000000")
FONT_DATA  = Font(name="宋体", size=11, bold=False, color="00000000")

FILL_DEEP  = PatternFill(patternType="solid", fgColor="FF1F4E78")
FILL_LIGHT = PatternFill(patternType="solid", fgColor="FFD9E2F3")
FILL_BLUE  = PatternFill(patternType="solid", fgColor="FF5B9BD5")
FILL_GREEN = PatternFill(patternType="solid", fgColor="FFE2F0D9")
FILL_WHITE = PatternFill(patternType="solid", fgColor="FFFFFFFF")

ALIGN  = Alignment(horizontal="center", vertical="center", wrap_text=False)
BORDER = Border()

MAX_ROWS = 500  # 下拉列表覆盖行数


def set_cols(ws, widths):
    for col, w in widths:
        ws.column_dimensions[col].width = w


def freeze(ws, cell):
    ws.freeze_panes = cell


def hdr(ws, headers, fills, fonts):
    for i, (h, fl, fn) in enumerate(zip(headers, fills, fonts), start=1):
        c = ws.cell(row=1, column=i, value=h)
        c.font, c.fill, c.alignment, c.border = fn, fl, ALIGN, BORDER


def drow(ws, row, values, fill=None):
    for i, v in enumerate(values, start=1):
        c = ws.cell(row=row, column=i, value=v)
        c.font, c.alignment, c.border = FONT_DATA, ALIGN, BORDER
        c.number_format = numbers.FORMAT_GENERAL
        if fill:
            c.fill = fill


def add_dv_ref(ws, col_letter, ref, prompt=None):
    """为整列添加引用式下拉列表（如 Config!$A$2:$A$3）"""
    if not ref:
        return
    dv = DataValidation(type="list", formula1=ref, allow_blank=True)
    dv.error = "请从下拉列表中选择"
    dv.errorTitle = "无效输入"
    if prompt:
        dv.prompt = prompt
        dv.promptTitle = "提示"
        dv.showPromptMessage = True
    ws.add_data_validation(dv)
    dv.add(f"{col_letter}2:{col_letter}{MAX_ROWS}")


def col_ref(letter, values):
    """Config 某列候选值对应的下拉引用区域；无候选返回 None"""
    n = len(values)
    if n == 0:
        return None
    return f"Config!${letter}$2:${letter}${n + 1}"


def obj_ref(values, name):
    """Object 列(B)引用：优先定位等于 name 的那一行（单格），
    找不到则回退整列候选区；列无候选返回 None"""
    n = len(values)
    if n == 0:
        return None
    for i, v in enumerate(values, start=2):
        if str(v).strip() == name:
            return f"Config!$B${i}:$B${i}"
    return f"Config!$B$2:$B${n + 1}"


def cfg_letters():
    """返回 {key: sheet 列字母} 便于读取候选列表"""
    return {c[0]: c[1] for c in CFG_COLUMNS}


CFG_LETTERS = cfg_letters()


def ref_for(key):
    return col_ref(CFG_LETTERS[key], cfg[key])


def fill_config_sheet(ws):
    """Config 表：逐列填写候选值（列式紧凑布局，互不干扰）。"""
    freeze(ws, "A2")
    set_cols(ws, [
        ("A", 10.375), ("C", 23.75), ("D", 14.875),
        ("E", 5.875), ("F", 17.875), ("G", 12.875), ("H", 11.625),
    ])
    headers = [c[2] for c in CFG_COLUMNS]
    hdr(ws, headers, [FILL_BLUE] * 8, [FONT_BLUE] * 8)
    for key, letter, _ in CFG_COLUMNS:
        for i, v in enumerate(cfg[key], start=2):
            c = ws.cell(row=i, column=ord(letter) - 64, value=v)
            c.font, c.alignment, c.border = FONT_DATA, ALIGN, BORDER
            c.number_format = numbers.FORMAT_GENERAL


wb = Workbook()

# ═══════════════════  Sheet 1: History  ═══════════════════
ws = wb.active
ws.title = "History"
freeze(ws, "A2")
set_cols(ws, [("A", 9.25), ("B", 37.875), ("C", 16.0), ("D", 61.375)])
hdr(ws,
    ["Version", "ChangeDate", "Changer", "Content"],
    [FILL_BLUE]*4, [FONT_BLUE]*4)
# 非空模式写入示例数据，空模板模式也保留版本说明
if not EMPTY:
    drow(ws, 2, ["V1.0", date.today().isoformat(), "AutoCreateSldd", "模板初始化"])
    drow(ws, 3, [
        "说明",
        "蓝色表头为必填列，浅蓝色表头为选填列",
        "",
        "模板已内置示例数据与 Config 下拉列表，可直接改名改值后使用"
    ])
else:
    # 反向同步创建空模板时，至少保留版本历史行
    drow(ws, 2, ["V1.0", date.today().isoformat(), "AutoCreateSldd", "初始版本 (反向同步创建)"])

# ═══════════════════  Sheet 2: Signal  ═══════════════════
ws = wb.create_sheet("Signal")
freeze(ws, "A2")
set_cols(ws, [
    ("A", 19.375), ("B", 10.375), ("C", 8.125), ("D", 22.875),
    ("E", 14.875), ("F", 15.375), ("G", 21.5),
    ("I", 17.125), ("J", 5.375), ("L", 5.875), ("M", 12.875),
])
HD_SIG = ["VariableName","Package","Object","CustomStorageClass",
          "DataType","InitialValue","HeaderFile","DefinitionFile",
          "Description","Min","Max","Unit","Dimensions","Complexity"]
SIG_FILLS = [FILL_DEEP]*5 + [FILL_LIGHT]*9
SIG_FONTS = [FONT_DEEP]*5 + [FONT_LIGHT]*9
hdr(ws, HD_SIG, SIG_FILLS, SIG_FONTS)

# 下拉列表（引用 Config 数据源，引用范围随配置行数动态变化）
add_dv_ref(ws, "B", ref_for("Package"),      "选择包名")
add_dv_ref(ws, "C", obj_ref(cfg["Object"], "Signal"), "选择 Signal")
add_dv_ref(ws, "D", ref_for("StorageClass"), "选择存储类")
add_dv_ref(ws, "E", ref_for("DataType"),     "选择数据类型")
add_dv_ref(ws, "L", ref_for("Unit"),         "选择单位")
add_dv_ref(ws, "N", ref_for("Complexity"),   "real 或 complex")

if not EMPTY:
    drow(ws, 2, ["M_Fault_StatusBus","myPackage","Signal","YS_SelectRAMSignal",
         "Bus: FaultBus","None","MCU_Fault_Signals.h","MCU_Fault_Signals.c",
         "故障状态信号总线","None","None","-","1","real"], FILL_GREEN)
    drow(ws, 3, ["M_Ctrl_Position_m","myPackage","Signal","ExportedGlobal",
         "single","None","MCU_Ctrl_Signals.h","MCU_Ctrl_Signals.c",
         "位置反馈信号","0","100","m","1","real"], FILL_GREEN)

# ═══════════════════  Sheet 3: Parameter  ═══════════════════
ws = wb.create_sheet("Parameter")
freeze(ws, "A2")
set_cols(ws, [
    ("A", 21.5), ("B", 10.375), ("D", 22.875),
    ("E", 10.375), ("F", 15.375), ("G", 19.375),
    ("I", 20.25), ("J", 4.75), ("K", 5.375), ("L", 5.875), ("M", 12.875),
])
PAR_FILLS = [FILL_DEEP]*6 + [FILL_LIGHT]*8
PAR_FONTS = [FONT_DEEP]*6 + [FONT_LIGHT]*8
hdr(ws, HD_SIG, PAR_FILLS, PAR_FONTS)

# 下拉列表（引用 Config 数据源）
add_dv_ref(ws, "B", ref_for("Package"),      "选择包名")
add_dv_ref(ws, "C", obj_ref(cfg["Object"], "Parameter"), "选择 Parameter")
add_dv_ref(ws, "D", ref_for("StorageClass"), "选择存储类")
add_dv_ref(ws, "E", ref_for("DataType"),     "选择数据类型")
add_dv_ref(ws, "L", ref_for("Unit"),         "选择单位")
add_dv_ref(ws, "N", ref_for("Complexity"),   "real 或 complex")

if not EMPTY:
    drow(ws, 2, ["C_Fault_IaLimit_s32","myPackage","Parameter","YS_SelectRAMPara",
         "single","600","MCU_Fault_Paras.h","MCU_Fault_Paras.c",
         "A相电流故障限值设置","0","1000","A","1","real"], FILL_GREEN)
    drow(ws, 3, ["Kp_SpdLoop","myPackage","Parameter","ExportedGlobal",
         "double","0.35","MCU_Ctrl_Paras.h","MCU_Ctrl_Paras.c",
         "速度环比例系数","0","10","-","1","real"], FILL_GREEN)

# ═══════════════════  Sheet 4: Const  ═══════════════════
ws = wb.create_sheet("Const")
freeze(ws, "A2")
set_cols(ws, [
    ("A", 9.375), ("B", 10.375), ("C", 19.375), ("D", 6.375),
    ("E", 10.375), ("F", 12.875),
])
hdr(ws,
    ["Name", "Package", "CustomStorageClass", "Value", "DataType", "HeaderFile"],
    [FILL_DEEP]*3 + [FILL_LIGHT]*3, [FONT_DEEP]*3 + [FONT_LIGHT]*3)

add_dv_ref(ws, "B", ref_for("Package"),      "选择包名")
add_dv_ref(ws, "C", ref_for("StorageClass"), "选择存储类")
add_dv_ref(ws, "E", ref_for("DataType"),     "选择数据类型")

if not EMPTY:
    drow(ws, 2, ["Mode", "Simulink", "Define", 1, "uint8", "Define.h"], FILL_GREEN)

# ═══════════════════  Sheet 5: Enum  ═══════════════════
ws = wb.create_sheet("Enum")
set_cols(ws, [("A", 9.375), ("B", 12.625), ("C", 6.375), ("D", 9.375)])
hdr(ws,
    ["EnumName", "EnumNumbers", "Value", "DataType"],
    [FILL_DEEP]*4, [FONT_ENUM]*4)

# DataType 下拉引用 Config D 列（可配置后不再内联写死）
add_dv_ref(ws, "D", ref_for("DataType"), "选择数据类型")

if not EMPTY:
    drow(ws, 2, ["GEAR", "H", 0, "uint8"])
    drow(ws, 3, ["GEAR", "M", 1, "uint8"])
    drow(ws, 4, ["GEAR", "L", 2, "uint8"])

# ═══════════════════  Sheet 6: Bus  ═══════════════════
ws = wb.create_sheet("Bus")
freeze(ws, "A2")
set_cols(ws, [
    ("A", 9.375), ("B", 14.125), ("C", 12.875),
    ("D", 11.625), ("E", 31.625), ("F", 11.625),
])
hdr(ws,
    ["BusName","Description","HeaderFile","Alignment",
     "PreserveElementDimensions","DataScope"],
    [FILL_DEEP, FILL_LIGHT, FILL_DEEP, FILL_DEEP, FILL_DEEP, FILL_DEEP],
    [FONT_DEEP, FONT_LIGHT, FONT_DEEP, FONT_DEEP, FONT_DEEP, FONT_DEEP])

add_dv_ref(ws, "F", ref_for("DataScope"), "Auto / Exported / Imported")

if not EMPTY:
    drow(ws, 2, ["FaultBus","故障状态总线","fault_bus.h","-1","False","Auto"], FILL_GREEN)
    drow(ws, 3, ["CtrlBus","控制总线","ctrl_bus.h","-1","False","Exported"], FILL_GREEN)

# ═══════════════════  Sheet 7: BusElement  ═══════════════════
ws = wb.create_sheet("BusElement")
freeze(ws, "A2")
set_cols(ws, [
    ("A", 9.375), ("B", 14.875), ("C", 10.375),
    ("D", 12.875), ("E", 19.125), ("F", 5.875),
])
BE_FILLS = [FILL_DEEP]*4 + [FILL_LIGHT]*2
BE_FONTS = [FONT_DEEP]*4 + [FONT_LIGHT]*2
hdr(ws,
    ["BusName","ElementName","DataType","Dimensions","Description","Unit"],
    BE_FILLS, BE_FONTS)

# 下拉列表
add_dv_ref(ws, "A", "Bus!$A$2:$A$1000", "选择总线名")
add_dv_ref(ws, "C", ref_for("DataType"), "选择数据类型")
add_dv_ref(ws, "F", ref_for("Unit"),     "选择单位")

if not EMPTY:
    drow(ws, 2, ["FaultBus","IcSensorFault","uint8","1","电流传感器故障标志","-"], FILL_GREEN)
    drow(ws, 3, ["FaultBus","VoltageFault","boolean","1","母线电压故障标志","-"], FILL_GREEN)
    drow(ws, 4, ["CtrlBus","Position","double","[3,1]","位置矢量","m"], FILL_GREEN)
    drow(ws, 5, ["CtrlBus","Velocity","double","[3,1]","速度矢量","m/s"], FILL_GREEN)

# ═══════════════════  Sheet 8: Config  ═══════════════════
ws = wb.create_sheet("Config")
# Config 表不设下拉列表——它本身就是其他表的数据源
# Config 是其他 sheet 下拉列表的数据源，内容随配置（template_config.json）变化
fill_config_sheet(ws)

# ═══ 保存 ═══
wb.save(OUT_PATH)
print(f"[OK] 模板已生成: {OUT_PATH}")
