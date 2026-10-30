function cfg = sldd_template_config(configFile)
%SLDD_TEMPLATE_CONFIG 打开「模板 Config 设置」二级对话框（模态）。
%
%   cfg = sldd_template_config()                % 使用脚本同目录 template_config.json
%   cfg = sldd_template_config(configFile)      % 指定配置文件路径
%
%   返回值 cfg：struct，字段 Package/Object/StorageClass/DataType/Unit/
%               DimensionsMode/Complexity/DataScope（各为 cellstr 候选列表）。
%   点「完成」把配置写回文件；点「取消」或关窗返回 []。
%
%   该配置供 generate_template.py 生成模板时填充 Config sheet 并驱动各
%   sheet 的下拉列表（generate_template.py / sldd_gui.m 会读取该文件）。

% ═══ 常量：列序、表头与内置默认值（与 generate_template.py 保持一致）═══
KEYS   = {'Package', 'Object', 'StorageClass', 'DataType', 'Unit', ...
          'DimensionsMode', 'Complexity', 'DataScope'};
HEADERS = {'Package', 'Object', 'Storage class', 'Data Type', 'Unit', ...
           'DimensionsMode', 'Complexity', 'DataScope'};
DEFAULT = struct( ...
    'Package',        {{'myPackage', 'Simulink'}}, ...
    'Object',         {{'Signal', 'Parameter'}}, ...
    'StorageClass',   {{'YS_SelectRAMSignal', 'YS_SelectRAMPara', 'ExportedGlobal', ...
                        'ImportedExtern', 'ImportedExternPointer', 'Auto'}}, ...
    'DataType',       {{'single', 'double', 'uint8', 'int16', 'uint16', ...
                        'uint32', 'boolean', 'Bus: FaultBus'}}, ...
    'Unit',           {{'-', 'V', 'A', 'N*m', 'm', 'm/s', '℃', 'deg'}}, ...
    'DimensionsMode', {{'Fixed', 'Variable'}}, ...
    'Complexity',     {{'real', 'complex'}}, ...
    'DataScope',      {{'Auto', 'Exported', 'Imported'}});

if nargin < 1 || isempty(configFile)
    try
        cfgFile = fullfile(fileparts(mfilename('fullpath')), 'template_config.json');
    catch
        cfgFile = fullfile(pwd, 'template_config.json');
    end
else
    cfgFile = configFile;
end

cfgData = loadCfgFile(cfgFile, DEFAULT, KEYS);

% ═══ 窗口 ═══
app = struct();
app.cfgFile = cfgFile;
app.keys = KEYS;
app.cfg = cfgData;
app.curKey = KEYS{1};
app.curRow = [];

app.fig = figure( ...
    'Name', '模板 Config 设置', ...
    'NumberTitle', 'off', ...
    'MenuBar', 'none', ...
    'ToolBar', 'none', ...
    'Resize', 'off', ...
    'Visible', 'off', ...
    'WindowStyle', 'modal', ...
    'Position', [80, 120, 780, 470], ...
    'Color', [0.94, 0.94, 0.94], ...
    'CloseRequestFcn', @onCancel);

% 构建/初始化期间出错时弹错误框并清理，避免残留空白窗口
try

% --- 顶部说明 ---
uicontrol(app.fig, 'Style', 'text', 'Position', [12, 438, 756, 24], ...
    'String', '配置生成模板时 Config sheet 的候选值（也是各工作表下拉列表的数据源）。', ...
    'HorizontalAlignment', 'left', 'FontWeight', 'bold');

% --- 左：列选择 ---
app.colPanel = uipanel(app.fig, 'Title', 'Config 列', 'FontWeight', 'bold', ...
    'Units', 'pixels', ...
    'Position', [10, 46, 190, 384]);
app.colList = uicontrol(app.colPanel, 'Style', 'listbox', 'Max', 1, ...
    'Position', [12, 12, 166, 340], 'BackgroundColor', 'white', ...
    'String', HEADERS, 'Value', 1, 'Callback', @onSelectColumn);

% --- 中：候选值表格 ---
app.valPanel = uipanel(app.fig, 'Title', '候选值', 'FontWeight', 'bold', ...
    'Units', 'pixels', ...
    'Position', [210, 46, 390, 384]);
app.valTable = uitable(app.valPanel, 'Position', [12, 12, 366, 340], ...
    'Data', cell(0, 1), 'ColumnName', {'候选值'}, 'ColumnEditable', true, ...
    'RowName', [], 'ColumnWidth', {320}, ...
    'CellEditCallback', @onCellEdited, ...
    'CellSelectionCallback', @onCellSelected);

% --- 中右：行操作按钮 ---
app.addBtn = uicontrol(app.valPanel, 'Style', 'pushbutton', 'Position', [270, 300, 108, 30], ...
    'String', '添加一行', 'Callback', @onAddRow);
app.delBtn = uicontrol(app.valPanel, 'Style', 'pushbutton', 'Position', [270, 262, 108, 30], ...
    'String', '删除选中行', 'Callback', @onDelRow);
app.upBtn  = uicontrol(app.valPanel, 'Style', 'pushbutton', 'Position', [270, 224, 108, 30], ...
    'String', '↑ 上移', 'Callback', @onMoveUp);
app.dnBtn  = uicontrol(app.valPanel, 'Style', 'pushbutton', 'Position', [270, 186, 108, 30], ...
    'String', '↓ 下移', 'Callback', @onMoveDown);

% --- 底部按钮 ---
uicontrol(app.fig, 'Style', 'pushbutton', 'Position', [12, 8, 110, 30], ...
    'String', '恢复默认值', 'Callback', @onRestoreDefault);
uicontrol(app.fig, 'Style', 'pushbutton', 'Position', [130, 8, 110, 30], ...
    'String', '加载配置…', 'Callback', @onLoadFrom);
uicontrol(app.fig, 'Style', 'pushbutton', 'Position', [248, 8, 110, 30], ...
    'String', '另存为…', 'Callback', @onSaveTo);
uicontrol(app.fig, 'Style', 'pushbutton', 'Position', [590, 8, 84, 32], ...
    'String', '完成', 'Callback', @onDone, 'FontWeight', 'bold');
uicontrol(app.fig, 'Style', 'pushbutton', 'Position', [684, 8, 84, 32], ...
    'String', '取消', 'Callback', @onCancel);

app.statusText = uicontrol(app.fig, 'Style', 'text', 'Position', [370, 12, 210, 22], ...
    'String', '', 'HorizontalAlignment', 'center', ...
    'ForegroundColor', [0.45, 0.45, 0.45]);

setappdata(app.fig, 'Result', []);
app = refreshTable(app);
app = updateStatus(app, sprintf('配置文件：%s', app.cfgFile));
catch ME
    % 构建失败：清理半成品窗口并把错误信息交给用户
    if isfield(app, 'fig') && ishandle(app.fig)
        delete(app.fig);
    end
    if isempty(ME.stack)
        loc = ME.identifier;
    else
        loc = sprintf('%s (行 %d)', ME.stack(1).name, ME.stack(1).line);
    end
    errordlg(sprintf('界面初始化失败：\n%s\n\n位置：%s', ME.message, loc), ...
        '模板 Config 设置');
    cfg = [];
    return;
end

% 全部构建完成后再显示窗口，避免半成品空白闪烁
set(app.fig, 'Visible', 'on');
drawnow;

% 模态等待
uiwait(app.fig);
if ishandle(app.fig)
    cfg = getappdata(app.fig, 'Result');
    delete(app.fig);
else
    cfg = [];
end

% ==================================================================
%  回调
% ==================================================================

    function onSelectColumn(~, ~)
        idx = get(app.colList, 'Value');
        app.curKey = app.keys{idx};
        app.curRow = [];
        app = refreshTable(app);
        app = updateStatus(app, '');
    end

    function onCellSelected(~, evt)
        if ~isempty(evt) && ~isempty(evt.Indices)
            app.curRow = evt.Indices(1);
        end
    end

    function onCellEdited(~, evt)
        if isempty(evt) || isempty(evt.Indices)
            return;
        end
        row = evt.Indices(1);
        vals = app.cfg.(app.curKey);
        newVal = cellstrSafe(evt.NewData);
        if row > numel(vals)
            vals{row} = newVal; %#ok<AGROW>
        else
            vals{row} = newVal;
        end
        app.cfg.(app.curKey) = vals;
        app = updateStatus(app, '有未保存的修改…');
    end

    function onAddRow(~, ~)
        vals = app.cfg.(app.curKey);
        vals{end + 1} = ''; %#ok<AGROW>
        app.cfg.(app.curKey) = vals;
        app.curRow = numel(vals);
        app = refreshTable(app);
    end

    function onDelRow(~, ~)
        if isempty(app.curRow)
            app = updateStatus(app, '请先选中要删除的行。');
            return;
        end
        vals = app.cfg.(app.curKey);
        if app.curRow > numel(vals)
            app.curRow = [];
            return;
        end
        vals(app.curRow) = [];
        app.cfg.(app.curKey) = vals;
        app.curRow = min(app.curRow, max(1, numel(vals)));
        app = refreshTable(app);
    end

    function onMoveUp(~, ~)
        vals = app.cfg.(app.curKey);
        n = numel(vals);
        if isempty(app.curRow) || app.curRow <= 1 || app.curRow > n
            app = updateStatus(app, '无法上移：需选中第 2 行及以后的行。');
            return;
        end
        tmp = vals{app.curRow - 1};
        vals{app.curRow - 1} = vals{app.curRow};
        vals{app.curRow} = tmp;
        app.cfg.(app.curKey) = vals;
        app.curRow = app.curRow - 1;
        app = refreshTable(app);
    end

    function onMoveDown(~, ~)
        vals = app.cfg.(app.curKey);
        n = numel(vals);
        if isempty(app.curRow) || app.curRow >= n
            app = updateStatus(app, '无法下移：需选中倒数第 2 行及以前的行。');
            return;
        end
        tmp = vals{app.curRow + 1};
        vals{app.curRow + 1} = vals{app.curRow};
        vals{app.curRow} = tmp;
        app.cfg.(app.curKey) = vals;
        app.curRow = app.curRow + 1;
        app = refreshTable(app);
    end

    function onRestoreDefault(~, ~)
        app.cfg = dupStruct(DEFAULT);
        app.curRow = [];
        app = refreshTable(app);
        app = updateStatus(app, '已恢复默认值（未保存）。');
    end

    function onLoadFrom(~, ~)
        [fn, fp] = uigetfile({'*.json', 'Config 配置 (*.json)'}, '加载模板配置');
        if isequal(fn, 0)
            return;
        end
        loaded = loadCfgFile(fullfile(fp, fn), DEFAULT, KEYS);
        app.cfg = loaded;
        app.curRow = [];
        app = refreshTable(app);
        app = updateStatus(app, sprintf('已加载：%s（完成后将写回 %s）', fn, app.cfgFile));
    end

    function onSaveTo(~, ~)
        [fn, fp] = uiputfile({'*.json', 'Config 配置 (*.json)'}, '保存配置副本', ...
            fullfile(fileparts(app.cfgFile), 'template_config.json'));
        if isequal(fn, 0)
            return;
        end
        outPath = fullfile(fp, fn);
        clean = cleanCfg(app.cfg, KEYS);
        ok = writeJsonFile(outPath, clean);
        if ok
            app = updateStatus(app, sprintf('已保存副本：%s', outPath));
        else
            app = updateStatus(app, '保存失败：无法写入文件。');
        end
    end

    function onDone(~, ~)
        clean = cleanCfg(app.cfg, KEYS);
        ok = writeJsonFile(app.cfgFile, clean);
        if ~ok
            app = updateStatus(app, '保存失败：无法写入配置文件。');
            return;
        end
        setappdata(app.fig, 'Result', clean);
        uiresume(app.fig);
    end

    function onCancel(~, ~)
        setappdata(app.fig, 'Result', []);
        uiresume(app.fig);
    end
end

% ==================================================================
%  局部辅助
% ==================================================================

function app = refreshTable(app)
% 用当前列候选值刷新表格并同步列面板标题
vals = app.cfg.(app.curKey);
if isempty(vals)
    set(app.valTable, 'Data', cell(0, 1));
else
    set(app.valTable, 'Data', vals(:));
end
idx = find(strcmp(app.keys, app.curKey));
set(app.colList, 'Value', idx);
if numel(vals) == 0
    titleStr = '候选值（空）';
else
    titleStr = sprintf('候选值（%d 项，该列填 Config 第 2-%d 行）', numel(vals), numel(vals) + 1);
end
set(app.valPanel, 'Title', titleStr);
end

function app = updateStatus(app, msg)
set(app.statusText, 'String', msg);
end

function out = loadCfgFile(path, defaultCfg, keys)
% 读取 json 配置；文件不存在或解析失败时用默认值
out = dupStruct(defaultCfg);
if ~exist(path, 'file')
    return;
end
try
    raw = jsondecode(fileread(path));
    if ~isstruct(raw)
        return;
    end
    flds = fieldnames(raw);
    for i = 1:numel(flds)
        f = flds{i};
        k = find(strcmp(keys, f), 1);
        if isempty(k)
            continue; % 未知字段忽略
        end
        v = raw.(f);
        if isempty(v)
            out.(keys{k}) = {};
            continue;
        end
        if ischar(v) || isstring(v)
            v = {v};
        end
        v = cellstr(string(v));
        v = v(~cellfun(@(s) isempty(strtrim(char(s))), v));
        for j = 1:numel(v)
            v{j} = strtrim(char(v{j}));
        end
        out.(keys{k}) = v;
    end
catch
    % 解析失败 → 使用默认值
end
end

function out = dupStruct(s)
out = struct();
flds = fieldnames(s);
for i = 1:numel(flds)
    v = s.(flds{i});
    out.(flds{i}) = v(:)';
end
end

function out = cleanCfg(cfgIn, keys)
% 清理：空列置 {}，逐项 trim、去空行、保序去重
out = dupStruct(cfgIn);
for i = 1:numel(keys)
    k = keys{i};
    vals = out.(k);
    if ischar(vals) || isstring(vals)
        vals = {vals};
    end
    vals = cellstr(string(vals));
    seen = {};
    keep = {};
    for j = 1:numel(vals)
        s = strtrim(char(vals{j}));
        if isempty(s)
            continue;
        end
        if any(strcmp(seen, s))
            continue;
        end
        seen{end + 1} = s; %#ok<AGROW>
        keep{end + 1} = s; %#ok<AGROW>
    end
    out.(k) = keep;
end
end

function ok = writeJsonFile(path, cfgOut)
% 以 UTF-8 写 json（jsonencode 输出紧凑单行，python json.load 可正常读取）
ok = false;
try
    txt = jsonencode(cfgOut);
    fid = fopen(path, 'w', 'n', 'UTF-8');
    if fid < 0
        return;
    end
    fwrite(fid, txt, 'char');
    fclose(fid);
    ok = true;
catch
end
end

function s = cellstrSafe(v)
if isstring(v)
    s = char(v);
elseif ischar(v)
    s = v;
elseif isnumeric(v) || islogical(v)
    s = num2str(v);
else
    s = char(string(v));
end
end
