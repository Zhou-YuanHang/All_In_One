# NewModelApp — Model-Creation App: Deep Analysis

Source: `src/NewModelApp/` (repo AutoCreateModel, commit `0cc5db5`). Files: `NewModelApp.m` (1546 lines),
`README.md` (109), `FEATURES.md` (14), `.gitignore` (93). Read-only static analysis (no MATLAB available).

## 1. Purpose & entry points

A single-window MATLAB GUI that creates a new Simulink model (`.slx`) in the **current folder** and configures solver, system
target file (TLC), `GenCodeOnly`, an optional data-dictionary link and optional Inport/Outport blocks imported from an Excel
port table (optionally with Embedded-Coder Code Mapping). A second, **undocumented** mode updates the ports of an existing
model and can export existing ports back to Excel.

- Implementation: one `classdef NewModelApp < handle` (line 1) — not App Designer, no `.mlapp`, no `AppBase`, no `run`/`startupFcn`.
- Entry: run `NewModelApp` (README:8). Constructor 69–72 → `createComponents()` (86–282). No output-argument wrapper, so a bare
  call leaves the object in `ans`; the window *is* the app.
- Packaging: **none** — no `.prj`, no `.mlappinstall`, no icon/resources, no version string (contrast
  `src/AutoCreateSldd/AutoCreateSldd.prj` + `.mlappinstall` + `AutoCreateSldd_resources/`).
- Programmatic API: **none**. All operations are `methods (Access = private)` on the UI class and write into `app.StatusLabel`;
  model creation cannot be invoked without a figure.
- Lifecycle: `delete(app)` (74–79) deletes `UIFigure`; no `CloseRequestFcn`, so a window close is not routed back to `app.delete`
  (harmless today — nothing is buffered).

## 2. File-by-file inventory

| File | Lines | Purpose |
|---|---|---|
| `NewModelApp.m` | 1546 | Whole app: UI handles as class properties, UI construction, callbacks, model creation, port sync, Excel import/export, helpers. |
| `README.md` | 109 | Chinese manual: feature table, ASCII layout, Excel port contract, Code Mapping workflow, collision handling, dependencies. Create mode only. |
| `FEATURES.md` | 14 | Manual test log (9 rows, all ✅) — includes a template generator that does not exist. |
| `.gitignore` | 93 | Generic VS/Xcode/Windows ignores + MATLAB block (80–94): `*.slx, *.sldd, Test.m, Ref, *.xlsx, *.mlappinstall, *.prj`. |

### Symbol map of `NewModelApp.m` (who calls whom)

| Lines | Symbol | Notes |
|---|---|---|
| 1–11 | `classdef NewModelApp < handle` | header comment lists create-mode features only |
| 12–58 | `properties (Access = public)` | 26 typed handles (`matlab.ui.Figure`, `matlab.ui.control.Label/EditField/Button/CheckBox/DropDown`) |
| 60–63 | `CreationControls` | `cell` of 13 handles hidden in "修改端口" mode (filled 263–268) |
| 68–80 | `NewModelApp()` 69–72, `delete(app)` 74–79 | ctor → `createComponents`; dtor deletes the figure |
| 86–282 | `createComponents(app)` | builds all controls, serialises `CreationControls`, `movegui(...,'center')`, `Visible='on'` |
| 289–326 | `onDiscreteToggled` / `onDictToggled` / `onExcelToggled` | enable/disable dependent label+edit+browse groups (Excel toggle also enables `ExcelCodeMapCheckBox`) |
| 331–386 | `onModeChanged` 331–377, `onCreateOrUpdate` 379–386 | create↔update mode switch, then dispatch to `createModel`/`updatePorts` |
| 388–466 | `onBrowseModel` 388–402, `onExportPorts` 404–438, `browseTLC` 440–446, `browseDict` 448–456, `browseExcel` 458–466 | pickers + export trigger; `onBrowseModel` keeps only the basename (398–399) |
| 473–778 | `createModel(app)` | core workflow (see §4.1), called by `onCreateOrUpdate` |
| 785–970 | `updatePorts(app)` | validate → load → parse Excel → `syncPorts` → save → mapping → save → close |
| 972–998 | `[in,out] = getExistingPorts(app, modelName)` | `find_system(...,'SearchDepth',1,'BlockType','Inport'/'Outport')` → `struct('name','dataType','position')` |
| 1000–1114 | `syncPorts(app, modelName, newIn, newOut)` | name-keyed add/delete/modify of top-level ports |
| 1116–1261 | `exportPortsToExcel(app, modelName)` | `uiputfile` → `writecell` Inputs/Outputs + read Code Mapping + Excel-COM `Sheet1` cleanup |
| 1268–1320 | `[in,out] = importPortsFromExcel(app, modelName, excelFile)` | sheet discovery + single-sheet fallback; **`modelName` is an unused/dead parameter** |
| 1322–1347 | `createPortBlocks(app, modelName, in, out)` | `add_block` + position + `OutDataTypeStr` |
| 1349–1420 | `[inputRaw,outputRaw] = splitBySection(app, raw)` | split one sheet on `Input/输入/输入端口/inputs` vs `Output/输出/输出端口/outputs` (column A) |
| 1422–1514 | `ports = parsePortTable(app, raw)` | header-row detection + 7-column parse → cell of structs |
| 1521–1544 | `isBlank` 1521–1534, `showError` 1536–1539, `showWarning` 1541–1544 | utilities; error/warning write the status label only |

```
NewModelApp() ─ createComponents()
onCreateOrUpdate ─┬─ createModel ─┬─ importPortsFromExcel ─┬─ splitBySection
                  │               │                        └─ parsePortTable
                  │               ├─ createPortBlocks
                  │               └─ coder.mapping.utils.create / setInport / setOutport
                  └─ updatePorts ─┬─ importPortsFromExcel (same)
                                  ├─ syncPorts ─ getExistingPorts
                                  └─ coder.mapping.utils.create / setInport / setOutport
onExportPorts ─ exportPortsToExcel ─┬─ getExistingPorts
                                    ├─ coder.mapping.api.get / getInport / getOutport
                                    └─ writecell / sheetnames / actxserver
```

## 3. UI architecture

Programmatic App-Designer style: `uifigure` + `matlab.ui.control.*` with absolute pixel positions in one fixed-size window.
No `uipanel`, `uitabgroup`, `uigridlayout` or `uimenu`.

```matlab
app.UIFigure = uifigure('Visible', 'off');          % 88
app.UIFigure.Position = [100, 130, 540, 560];       % 89
app.UIFigure.Name = '新建 Simulink 模型';            % 90
app.UIFigure.Resize = 'off';  app.UIFigure.Scrollable = 'off';   % 91-92
app.ModeDropDown = uidropdown(app.UIFigure);
app.ModeDropDown.Items = {'新建模型', '修改端口'};
app.ModeDropDown.ValueChangedFcn = @(~, ~) app.onModeChanged();
```

Layout (540×560, y = bottom): title `uilabel` 525 (local var, 95–100) · grey `sep` label 508 (103–106) · `ModeLabel`+`ModeDropDown`
480/477 (109–118) · `NameLabel`+`NameEditField` 448 (default `'myModel'`) + hidden `ModelBrowseButton` 444 (121–137) ·
`DiscreteCheckBox` 413 + `SampleTimeLabel/EditField` 385 (`'0.01'`, disabled; 140–156) · `TLCLabel/EditField/BrowseButton` 353
(`'ert.tlc'`; 159–172) · `GenCodeOnlyCheckBox` 320 (175–179) · `DictCheckBox` 287 + label/edit/browse 259 (182–202) ·
`ExcelCheckBox` 227 + label/edit/browse 199 + `ExcelCodeMapCheckBox` 173 (205–233) · hidden `ExportPortsButton` 148 (236–242) ·
`CreateButton` 110 (160×36, white on `[0.15 0.55 0.15]`; 253–260) · `OpenModelCheckBox` 78 (default `true`; 245–250) ·
`StatusLabel` 20 (500×50, `WordWrap='on'`, grey; 271–277).

**Mode switching**: `onModeChanged` (331–377) sets `CreateButton.Text` to "创建模型"/"更新端口" (green/orange), toggles
`Visible` on the 13 `CreationControls` (263–268: discrete, sample time, TLC, GenCodeOnly, dictionary, OpenModel) plus
`ExportPortsButton`/`ModelBrowseButton`, and resets the status. It does not touch the name field, the Excel group or the window
title (always "新建 Simulink 模型").

**State storage**: handles are public class properties of type `matlab.ui.*`. No `app.Data` struct, no `guidata`/`handles`, no
`setappdata`. Values are read directly from the controls at use time (`strtrim(app.NameEditField.Value)`); no form-state model,
no dirty tracking, no persistence.

**Callback wiring**: anonymous closures that drop the event arg —
`...ButtonPushedFcn = @(~, ~) app.onCreateOrUpdate();` (260), `ValueChangedFcn = @(s, ~) app.onDiscreteToggled(s.Value)` (144),
`@(s, ~) app.onDictToggled(s.Value)` (186), `@(s, ~) app.onExcelToggled(s.Value)` (209). No `ValueChangingFcn`/`KeyPressFcn`.

**Modal dialogs**: collision choice via
```matlab
choice = uiconfirm(app.UIFigure, msg, '模型已存在', ...
    'Options', {'覆盖', '加数字后缀', '取消'}, ...
    'DefaultOption', 2, 'CancelOption', 3, 'Icon', 'question');       % 502-506
```
per-port mapping failure via `uialert(app.UIFigure, errMsg, 'Code Mapping 部分失败', 'Icon', 'warning')` (749, 955); pickers via
`uigetfile` filter matrices (390, 441, 449, 459) and `uiputfile('*.xlsx', '导出端口到 Excel', defaultName)` (1122), followed by
`figure(app.UIFigure)` to re-raise the window (393, 455, 465, 1257).

**Status reporting** (heterogeneous, worth normalising): (1) status label only — `showError`/`showWarning` prefix `✗`/`⚠` and
recolour, used for all validation and most failures, non-modal, no detail; (2) modal `uialert` only for per-port mapping
failures; (3) modal `uiconfirm` only for collisions; (4) progress = `StatusLabel.Text = sprintf('正在创建模型 "%s"...', modelName);
drawnow;` (547–548, 477–479, 787–789, 1152–1154) — no progress bar, UI blocks during Simulink calls; (5) messages with `\n` are
assigned to `StatusLabel.Text` (488, 607, 620, 625, 805, 811) although a `uilabel` only wraps, never breaks lines; (6) the final
success write (764–765) overwrites intermediate warnings (e.g. the dictionary status at 601–604 disappears).

## 4. Core algorithms / workflows

### 4.1 `createModel` — exact sequence (473–778)

1. Status "正在创建模型...", `drawnow` (477–479).
2. Validate name: `strtrim` → non-empty → `isvarname(modelName)` (482–490); failures are status-only.
3. Collision: `modelExists = bdIsLoaded(modelName) || (exist(modelName,'file') == 4)` (493) → `uiconfirm` (495–506).
   **覆盖**: `close_system(modelName, 0)` (discard) then `delete([modelName,'.slx'])` (509–521). **加数字后缀**: `while true`,
   `sprintf('%s%d',modelName,suffix)` until `~bdIsLoaded(newName) && exist(newName,'file') ~= 4`, then write the new name back
   into `NameEditField` (523–535). **取消**: status "已取消", return (537–540).
4. `new_system(modelName); open_system(modelName);` (550–551) — no `'ErrorIfShadowed'`.
5. Solver (554–569): discrete → `set_param(mdl,'SolverType','Fixed-step','Solver','FixedStepDiscrete','FixedStep',num2str(sampleTime))`
   (`str2double`, must be >0 else `close_system(mdl,0)` + error); continuous →
   `set_param(mdl,'SolverType','Variable-step','Solver','VariableStepAuto')`.
6. TLC (572–575): `set_param(mdl,'SystemTargetFile', tlcFile)` when non-empty.
7. `set_param(mdl,'GenCodeOnly','on'/'off')` — explicitly off, not skipped (578–582).
8. Data dictionary (585–610): requires the checkbox and non-empty text; extension defaulted to `.sldd` via `fileparts`;
   `exist(fullDictPath,'file')` must hold; then the **path is stripped** and `set_param(mdl,'DataDictionary',dictFileName)`
   (comment 595 "只需文件名，不含路径"). Failure → `showWarning` (604); missing file → warning "请先创建 .sldd 文件" (607).
9. Excel ports (616–663): requires a non-empty existing file, else `close_system(mdl,0)` + error; `importPortsFromExcel` (630)
   then `createPortBlocks` (636); counts → `（导入 %d 个输入端口，%d 个输出端口）` (639).
10. Mapping pre-check (642–662): `cmApplied` downgraded to false unless ≥1 port has any of
    `storageClass/identifier/headerFile/definitionFile` non-empty.
11. **Save #1** `save_system(modelName)` (666) — required before `coder.mapping.utils.create` (the model must exist on disk; the
    comment at 671 "重新打开已保存的模型" is misleading: `bdIsLoaded` is already true, so no reload happens).
12. Code Mapping (669–755): `cmObj = coder.mapping.utils.create(modelName)` (675). Per input: NV pairs `StorageClass` (default
    `'Auto'` when blank), optional `Identifier`/`HeaderFile`/`DefinitionFile`, then `setInport(cmObj, p.name, nvPairs{:})` (698);
    same for `setOutport` (723). **Each port has its own try/catch**, collecting only names (700, 725). **Save #2** (730), append
    `' + Code Mapping'` to the status (731), one aggregated `uialert` grouped `【Input】/【Output】` (734–749). If
    `coder.mapping.utils.create` itself fails → `showWarning` "Code Mapping 初始化失败: ...\n端口仍已创建。" (752–754), model kept.
13. Open/close (757–761): keep open when `OpenModelCheckBox.Value`, else `close_system(modelName)` (saves).
14. Success (764–765): green `✓ 模型 "%s" 创建成功%s`.
15. catch (767–777): best-effort `close_system(modelName, 0)` + `showError('创建失败：...')`. A failure after Save #1 leaves the
    half-configured `.slx` on disk (discard only drops the in-memory copy).

### 4.2 Excel import pipeline

`importPortsFromExcel` (1268–1320): `sheets = sheetnames(excelFile)` (1290) → first exact (case-sensitive) `ismember` hit of
`{'Inputs','Input','输入'}` / `{'Outputs','Output','输出'}` → `readcell(excelFile,'Sheet',name)` (1296–1307) → if **both** tables
are empty, `readcell(excelFile)` (first sheet only) + `splitBySection` (1310–1315) → `parsePortTable` twice (1318–1319).

`parsePortTable` (1422–1514): skips row 1 when `raw{1,1}` (lower-cased, trimmed) is in
`{'port','name','端口','端口名','端口名称','portname','port_name','信号名','信号名称','序号','序列号','编号'}` (1441–1449); skips rows
whose column B is blank (1454); strips control chars from the name (`regexprep(portName,'[\r\n\t\v\f]','')`, 1460); reads C–G as
trimmed `char` only when `ischar|isstring` (1466–1504); emits
`struct('name','dataType','storageClass','identifier','headerFile','definitionFile')` (1506–1512). No name validity, duplicate or
data-type checks.

`createPortBlocks` (1322–1347): `add_block('simulink/Sources/In1', sprintf('%s/%s',modelName,p.name))` at `[60,inY,90,inY+14]`,
`inY` += 50; `OutDataTypeStr` set only when non-empty and not `'Inherit: auto'`; outputs via `'simulink/Sinks/Out1'` at x=500.
**There is no `add_line` anywhere in the file** — ports are never wired.

### 4.3 Update-ports mode (`updatePorts` 785–970, `syncPorts` 1000–1114)

Order: name check → model loaded or `<name>.slx/.mdl` exists (803–804) → require `ExcelCheckBox.Value` + valid file (810–822) →
`load_system` if needed, remembering `wasLoaded` (825–833) → parse (837) → `syncPorts` (851) → `save_system` (861) → optional
mapping block (865–961, a near-verbatim copy of 669–755) → close only if previously unloaded (964–966) → green status with
`（%d 个输入, %d 个输出）`.

`syncPorts` diffs by name, In and Out symmetrically: `getExistingPorts` (1005–1009) → delete blocks absent from Excel
(1013–1017) → next free y = `max(80, retained.position(2)+50)` (1020–1028; the `inY=80` at 1020 is dead) → per Excel port:
existing with a changed dtype → `set_param(...,'OutDataTypeStr',newType)` then `get_param` verify (1041–1044); if Simulink ignored
it, `delete_block` + `add_block` + restore `Position` + set again (1046–1051, comment 1045 "set_param 被 Simulink 缓存忽略 → 删了重建");
new → `add_block` + position + dtype. Only `dataType` is reconciled — sample time, dimensions, port numbers and connections are
untouched (deleting a port drops its lines).

### 4.4 Export ports (`exportPortsToExcel` 1116–1261)

`uiputfile` default `sprintf('%s_ports.xlsx',modelName)` (1121–1126) → `getExistingPorts` (1129) → warn if empty (1131–1134) →
`coder.mapping.api.get(modelName)` inside try/catch (1141–1150, tolerant of missing mapping/licence) → build 7-column cells with
headers `{'序号','端口名称','数据类型','StorageClass','Identifier','HeaderFile','DefinitionFile'}` (1158) → per-property
`getInport(cmObj,blkName,'StorageClass'|'Identifier'|'HeaderFile'|'DefinitionFile')` (1171–1192) / `getOutport` (1208–1229), each in
a silent try/catch → `writecell(...,'Sheet','Inputs'|'Outputs')` (1194, 1231) → delete the auto-created `Sheet1` through Excel COM
(`actxserver('Excel.Application')`, 1235–1253, silent catch so non-Windows is fine) → green status + refocus (1255–1257).

### 4.5 APIs used

`uifigure, uidropdown, uieditfield, uicheckbox, uibutton, uilabel, uiconfirm, uialert, uigetfile, uiputfile, movegui, drawnow`;
`new_system, open_system, close_system, save_system, load_system, bdIsLoaded, find_system, add_block, delete_block, set_param, get_param`;
`coder.mapping.utils.create, coder.mapping.api.get, setInport, setOutport, getInport, getOutport`; `sheetnames, readcell, writecell,
actxserver, isvarname, str2double, fileparts, regexprep, strjoin, cellfun, ismember, onCleanup`.
**Not used**: `Simulink.data.dictionary.*` (only `set_param(...,'DataDictionary',...)`), the `Simulink.CodeMapping` class directly,
`sltest`, `add_line`, `Simulink.Bus`, `save_system(...,'SaveAsName',...)`, `addpath`.

## 5. Data formats & schemas

### 5.1 Excel port workbook (README:52–67, code 1268–1514)

Sheet names, first match, case-sensitive: input `Inputs → Input → 输入`; output `Outputs → Output → 输出`. Fallback: one sheet with
section titles in **column A** (`Input/输入/输入端口/inputs` vs `Output/输出/输出端口/outputs`, case-insensitive, trimmed;
1374–1381); with no section title at all every row is treated as input (1392–1397).

| Col | Field | Req. | Semantics | Code |
|---|---|---|---|---|
| A | 序号 | no | ignored except for header detection | 1441–1449 |
| B | port name | **yes** | Simulink block name ⇒ block path `<model>/<name>`; also passed verbatim as the Code-Mapping block argument | 1459–1461 |
| C | data type | no | → `OutDataTypeStr`; empty or `Inherit: auto` = leave default | 1466–1472, 1330, 1342 |
| D | StorageClass | no | mapping `StorageClass`; blank → `'Auto'` when mapping runs | 1474–1480, 684–688 |
| E | Identifier | no | mapping `Identifier`; blank → omitted | 1482–1488, 689–691 |
| F | HeaderFile | no | mapping `HeaderFile`; blank → omitted | 1490–1496, 692–694 |
| G | DefinitionFile | no | mapping `DefinitionFile`; blank → omitted | 1498–1504, 695–697 |

The export writes exactly these 7 columns plus a header row (1158, 1194, 1231), so it round-trips as a valid import template.
No validation of data-type strings, of Simulink block-name legality, or of duplicates (duplicate names ⇒ `add_block` failure late
in the flow).

### 5.2 In-memory schemas (two incompatible variants)

Imported ports: `struct('name',char,'dataType',char,'storageClass',char,'identifier',char,'headerFile',char,'definitionFile',char)`
(1506–1512) in a `{1×N} cell`. Existing ports from `getExistingPorts`: `struct('name','dataType','position')` (983–985).

### 5.3 Rules & generated names

Model name: `strtrim` + `isvarname` (letter first, `[A-Za-z0-9_]`, ≤ `namelengthmax`, not a keyword); suffixed names are **not**
re-validated. Port name: no rule at all beyond blank/control-char filtering. Dictionary: `<base>.sldd`, basename only. Files:
`<model>.slx` in pwd; `<model>_ports.xlsx` for export. No JSON/persistent settings — every run starts from the hard-coded defaults
`'myModel'`, `'ert.tlc'`, `'0.01'`, `OpenModelCheckBox=true` (contrast AutoCreateSldd's `python_config.json`/`template_config.json`).

## 6. External dependencies & environment assumptions

- **MATLAB**: README:106 claims R2019b+; the actual floor is driven by `sheetnames`/`readcell`/`writecell` (R2019a), multi-option
  `uiconfirm`, `uifigure.Scrollable` and `uilabel.WordWrap`/`BackgroundColor`. Treat **R2024b** (version recorded in
  `AutoCreateSldd.prj`) as the merged baseline and re-verify the R2019b claim.
- **Products**: Simulink mandatory; *Simulink Coder / Embedded Coder* needed for `GenCodeOnly`, `ert.tlc` generation and every
  `coder.mapping.*`/`setInport`/`setOutport` call. README calls these "optional" — the checkbox depends on them, but failures
  degrade to warnings (752–754, 1141–1150).
- **No Python.** The only non-MATLAB dependency is Excel via COM (`actxserver`, 1238) for `Sheet1` cleanup only, inside a silent
  catch.
- **Windows-specific**: COM automation, deletion of a just-closed `.slx` (file locking), native file dialogs, Chinese UI strings.
  Paths are built with `fullfile`, so separators are portable.
- **Search path**: nothing is added (no `addpath`). Hence (a) the `.sldd` must be in pwd/on the path because its directory is
  stripped (597–600); (b) a browsed `.tlc` full path (445) is fed to `SystemTargetFile`, which expects an STF name on the path —
  likely rejected; (c) a `.slx` is only found by `exist(name,'file')==4` when in pwd/on the path.
- **Working directory**: models are always saved by `save_system(modelName)` (666, 730, 861, 936) into **pwd**; there is no
  output-folder control in the UI.
- **Hard-coded strings** to preserve: `'simulink/Sources/In1'`, `'simulink/Sinks/Out1'`, `'ert.tlc'`, `'FixedStepDiscrete'`,
  `'VariableStepAuto'`, `'Inherit: auto'`, `'Auto'`, mode literals `'新建模型'`/`'修改端口'` (`strcmp` at 333, 381), all dialog texts,
  sheet-name aliases.
- No MEX, no compiled artifacts, no toolbox/licence checks (`license('test',...)` absent).

## 7. Constraints, bugs, gaps, missing files

**Missing (referenced but absent)**
1. `createExcelTemplate.m` — README:71–73 and FEATURES row 9 describe it (4-input/3-output template); it does not exist and is
   **never called** in `NewModelApp.m`, and there is no UI button for it.
2. `ref/Port/PortExtractorGUI.m`, `PortExtractor.m` — README:93–102 "配套工具"; absent. The repo's `.gitignore` excludes `Ref` and
   `*.xlsx`, explaining the loss. The importer still documents its contract as "由 PortExtractor 生成" (1273, 1425).
3. No tests (`Test.m` gitignored, no `matlab.unittest` usage), no packaging metadata, no version string.

**Behavioural bugs / risks (severity-ordered)**
4. ~~**Mapping block path**~~ — **VERIFIED NOT A BUG (Lead, R2024b source).** `setInport`/`getInport` accept
   "Path, handle, or name of root-level inport" (`E:\MATLAB\R2024b\toolbox\coder\simulinkcoder\+coder\+mapping\+api\@CodeMapping\setInport.m:8`),
   so passing the bare root-level port name (`setInport(cmObj, p.name, ...)` at 698, 723, 906, 930) is legal. A full block path is
   only required for ports inside subsystems. Remaining minor nuance: on a *load* both `getInport`/`setInport` resolve the same way,
   so create/export are symmetric. No change needed in the merge.
5. **TLC browse yields a full path** (445) → `set_param` (574) likely aborts `createModel`.
6. **Dictionary path stripped** (595–600) — a `.sldd` outside pwd/path cannot be linked; no verification the link took; no
   `Simulink.data.dictionary` creation (warning at 607 pushes that to the user; the SLDD app can fill this).
7. **Overwrite is destructive and `.slx`-only** (509–521): no backup; an existing `.mdl` makes `delete([modelName,'.slx'])` fail and
   aborts with "无法清理已有模型".
8. **Collision detection is pwd/path-bound** (493) — `.slx` files elsewhere are missed; the suffix loop (523–535) is unbounded,
   never checks `.mdl`, and never re-validates `isvarname` (a 63-char name + suffix becomes invalid).
9. **Browsed model path discarded** (398–399) while `updatePorts` resolves against pwd (803–804) ⇒ browsing a model from another
   folder then 更新端口 fails with "模型不存在".
10. **`open_system` is unconditional** (551) — the model flashes open even when "创建后打开模型" is unchecked; `close_system(modelName)`
    (760) saves again.
11. **Failure after Save #1 leaves a partial `.slx`** (catch 767–777 discards only the in-memory model); together with 覆盖 this can
    leave a broken file and no original.
12. **Code duplication**: mapping block ~90 lines duplicated verbatim (669–755 vs 865–961); mapping-column scan duplicated
    (642–662 vs 868–877); `createPortBlocks` vs the new-port branches of `syncPorts` duplicate add/position/dtype logic
    (1053–1061 vs 1325–1334; 1105–1113 vs 1337–1346).
13. **Dead code**: `inY = 80;` at 1020 overwritten at 1028; unused `modelName` parameter (1268); `importCount = ''` char accumulator
    (613); misleading comment (671); `splitBySection` builds a `cell(size(raw,1),1)` of row vectors (1393) only to re-pad them.
14. **Multi-line messages in a `uilabel`** (488, 607, 620, 625, 805, 811) collapse; the success message overwrites prior warnings.
15. **No duplicate/invalid port-name handling** (5.1) — a bad name fails after `new_system` and triggers the cleanup path.
16. **UI mode undocumented**: "修改端口", `ModelBrowseButton`, `ExportPortsButton` appear nowhere in README/FEATURES; the title and
    Excel labels still say "新建"; `updatePorts` requires `ExcelCheckBox` to be ticked but switching mode never ticks it, so the
    user meets an error first (810–812).
17. **Only `dataType` reconciled** in `syncPorts`; delete/re-add loses connections; no `add_line` exists, so models are unwired by design.
18. **COM cleanup silently skipped** off-Windows/without Excel (1235–1253), leaving a stray `Sheet1`; `readcell` in the fallback
    branch reads only the first sheet (1311).
19. **No figure close hook** — closing the window never calls `delete(app)`; the `ans` handle lingers (harmless now, matters if the
    merged app owns timers/state).

## 8. Merge assessment

**Reusable as-is (after extraction into a service layer)**
- `parsePortTable` (1422–1514) and `splitBySection` (1349–1420): pure cell-in/struct-out, no UI → `ports.readExcelTable(raw)` /
  `ports.splitSections(raw)` (drop `app`).
- `isBlank` (1521–1534): already UI-free (first argument is `~`).
- `importPortsFromExcel` (1268–1320): only coupling is the unused `app` → `[in,out] = ports.readWorkbook(excelFile)`.
- `getExistingPorts` (972–998) → `modelPorts(modelName)`, plus a `blockPath` field to fix issue 4.
- `createPortBlocks` (1322–1347) + the add/modify branch of `syncPorts` (1000–1114) → `report = applyPorts(modelName,in,out,opts)`.
- Solver/TLC/GenCodeOnly/dictionary block (554–610) → `configureModel(modelName,opts)` with
  `opts = struct('isDiscrete',...,'sampleTime',...,'tlc',...,'genCodeOnly',...,'dictFile',...)`.
- Mapping loop (669–755) → `applyCodeMapping(modelName,ports,'Input'|'Output')` returning `struct('ok',{},'failed',{},'initError',...)`,
  keeping per-port try/catch and the `'Auto'` default; call it from both create and update.
- `exportPortsToExcel` (1116–1261): split the `uiputfile`/status UI from `writePortWorkbook(modelName,outFile)` (headless); COM
  cleanup stays optional.

**UI-coupled, must be rewritten**
- `properties (Access = public)` (12–58) and `createComponents` (86–282): absolute positions in a fixed 540×560 `uifigure`; all 26
  handles and pixel coordinates are throw-away in a tabbed single window (the SLDD app is 1380×820).
- All callbacks (289–466) and the mode dispatcher (331–386).
- `createModel` (473–778) / `updatePorts` (785–970): interleaved validation, dialogs, status text, Simulink calls and cleanup —
  rewrite as a workflow returning a result struct / throwing typed errors; keep the step order of §4.1 (save-before-mapping,
  mapping-before-second-save, open/close by checkbox are load-bearing).
- Collision `uiconfirm` (502–506) and per-port `uialert` (749, 955): preserve semantics (3 options, default 2 = suffix, cancel = 3;
  one aggregated failure list grouped Input/Output) but re-render with the merged app's dialog component.
- `StatusLabel` + `showError`/`showWarning` (1536–1544): replace with a shared status/log API, keeping the `✓ / ✗ / ⚠` convention
  and the success shape `✓ 模型 "%s" 创建成功（导入 %d 个输入端口，%d 个输出端口）（+ Code Mapping）`.

**Behaviour a merged app must preserve**
1. Name validation = `strtrim` + `isvarname`; collisions → overwrite / numeric suffix / cancel, suffix written back to the field,
   default = suffix.
2. Models saved to the current folder as `<name>.slx` (add an explicit output folder only as an *extension*).
3. Discrete = `Fixed-step`/`FixedStepDiscrete`/`FixedStep`; continuous = `Variable-step`/`VariableStepAuto`; `GenCodeOnly` set
   explicitly on and off; `SystemTargetFile` default `ert.tlc`.
4. Dictionary link only when the file exists; failure is a warning, never fatal.
5. Port import: sheet aliases, section fallback, 7-column contract, header detection, control-char stripping, `Inherit: auto` =
   leave default, 50-px spacing at x=60/x=500, top level only.
6. Code Mapping optional, only when mapping columns exist, after Save #1 and followed by Save #2, per-port fault tolerant, one
   aggregated failure dialog.
7. "创建后打开模型" default on; unchecked ⇒ save then close.
8. "修改端口": name-keyed sync (add/delete/modify dtype with the verify-then-rebuild fallback), save, optional re-mapping, restore
   the model's original loaded/unloaded state.

**Cross-project merge notes (with AutoCreateSldd)**
- Two UI stacks: model app = `uifigure` + classdef with public handle properties; `sldd_gui` = classic `figure`/`uicontrol` with a
  `struct` of handles inside a function. Adopt the `uifigure` + `uipanel`/`uitabgroup` style and re-host the SLDD controls; porting
  the SLDD app is the larger rewrite.
- Baseline R2024b (from `AutoCreateSldd.prj`); the SLDD side additionally needs Python 3 + `openpyxl`, the model side does not.
- Workbook mismatch: model app = 2-sheet `Inputs`/`Outputs` port book; SLDD app = 8-sheet
  Signal/Parameter/Const/Enum/Bus/BusElement/History/Config book. The merged app needs both readers selected by sheet-name probing.
- Dictionary synergy: the model app can only link an existing `.sldd` ("请先创建 .sldd 文件", 607) — let the SLDD module create and
  validate it first, then link via `Simulink.data.dictionary.open` instead of the path-stripped `set_param`.
- CSC mismatch: the SLDD app registers 16 custom storage classes (`+myPackage/csc_registration.m`); the port importer's
  StorageClass column is free text and should offer those names, or generated port mapping will not match the dictionary.
- Unify reporting: one `report(level,msg)` sink plus one dialog helper so both tabs behave identically.