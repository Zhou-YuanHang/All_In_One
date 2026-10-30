function cfg = sldd_python_config(configFile)
%SLDD_PYTHON_CONFIG 打开「Python 路径设置」二级对话框（模态）
%
%   cfg = sldd_python_config()               % 默认写脚本同目录 python_config.json
%   cfg = sldd_python_config(configFile)     % 指定配置文件
%
%   手动指定生成模板 / 反向同步时使用的 python 可执行文件（不再自动搜索系统 Python）。
%   点「保存」把路径写回 python_config.json 并返回 struct（字段 PythonPath；
%   清空后保存时 PythonPath = '' 且删除配置文件）；点「取消」或关窗返回 []。

if nargin < 1 || isempty(configFile)
    configFile = python_config_path();
end
configFile = char(string(configFile));

app = struct();
app.cfgFile = configFile;
app.curPath = readJsonPath(configFile);

% ═══ 窗口 ═══
app.fig = figure( ...
    'Name', 'Python 路径设置', ...
    'NumberTitle', 'off', ...
    'MenuBar', 'none', ...
    'ToolBar', 'none', ...
    'Resize', 'off', ...
    'Visible', 'off', ...
    'WindowStyle', 'modal', ...
    'Position', [80, 160, 720, 330], ...
    'Color', [0.94, 0.94, 0.94], ...
    'CloseRequestFcn', @onCancel);

% 构建/初始化期间出错时弹错误框并清理，避免残留空白窗口
try

% --- 顶部说明 ---
uicontrol(app.fig, 'Style', 'text', 'Position', [12, 262, 696, 46], ...
    'String', {'生成模板与反向同步时使用的 Python：请手动指定 python.exe。', ...
               '本程序不再自动搜索系统 Python（pyenv / PATH / 注册表均不查询）。'}, ...
    'HorizontalAlignment', 'left', 'FontWeight', 'bold');

% --- 路径输入行 ---
uicontrol(app.fig, 'Style', 'text', 'Position', [12, 232, 100, 22], ...
    'String', 'Python 路径', 'HorizontalAlignment', 'left', 'FontWeight', 'bold');
app.pathEdit = uicontrol(app.fig, 'Style', 'edit', 'Position', [116, 228, 460, 28], ...
    'String', app.curPath, 'HorizontalAlignment', 'left', 'BackgroundColor', 'white');
uicontrol(app.fig, 'Style', 'pushbutton', 'Position', [586, 226, 116, 32], ...
    'String', '浏览…', 'Callback', @onBrowse);

% --- 测试 ---
uicontrol(app.fig, 'Style', 'pushbutton', 'Position', [12, 186, 100, 30], ...
    'String', '测试', 'Callback', @onTest);
app.statusText = uicontrol(app.fig, 'Style', 'text', 'Position', [120, 150, 582, 66], ...
    'String', '', 'HorizontalAlignment', 'left', ...
    'ForegroundColor', [0.35, 0.35, 0.35]);

% --- 说明 ---
uicontrol(app.fig, 'Style', 'text', 'Position', [12, 106, 690, 40], ...
    'String', {'路径可填 python.exe 完整路径、Python 安装目录，或裸命令名（如 python3）。', ...
               '点「清除设置」并保存可取消已设置的内容。'}, ...
    'HorizontalAlignment', 'left', 'ForegroundColor', [0.45, 0.45, 0.45]);
uicontrol(app.fig, 'Style', 'text', 'Position', [12, 62, 690, 34], ...
    'String', sprintf('配置文件：%s', app.cfgFile), ...
    'HorizontalAlignment', 'left', 'ForegroundColor', [0.45, 0.45, 0.45]);

% --- 底部按钮 ---
uicontrol(app.fig, 'Style', 'pushbutton', 'Position', [12, 10, 110, 32], ...
    'String', '清除设置', 'Callback', @onClear);
uicontrol(app.fig, 'Style', 'pushbutton', 'Position', [496, 10, 90, 34], ...
    'String', '保存', 'Callback', @onSave, 'FontWeight', 'bold');
uicontrol(app.fig, 'Style', 'pushbutton', 'Position', [596, 10, 90, 34], ...
    'String', '取消', 'Callback', @onCancel);

setappdata(app.fig, 'Result', []);

if isempty(app.curPath)
    app = setStatus(app, '尚未设置 Python 路径，请填写或点「浏览…」选择 python.exe。', false);
else
    app = setStatus(app, sprintf('当前已设置：%s\n点「测试」可验证是否可用。', app.curPath), false);
end

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
        'Python 路径设置');
    cfg = [];
    return;
end

% 全部构建完成后再显示窗口，避免半成品空白闪烁
set(app.fig, 'Visible', 'on');
drawnow;
if ~isempty(app.curPath)
    onTest(); % 打开界面时自动测一次，直接告诉用户当前路径能不能用
end

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

    function onBrowse(varargin)
        cur = strtrim(get(app.pathEdit, 'String'));
        startDir = pwd;
        if ~isempty(cur)
            d = fileparts(cur);
            if ~isempty(d) && exist(d, 'dir') == 7
                startDir = d;
            end
        end
        [fn, fp] = uigetfile( ...
            {'*.exe', 'Python 可执行文件 (*.exe)'; '*.*', '所有文件 (*.*)'}, ...
            '选择 python.exe', startDir);
        if isequal(fn, 0)
            return;
        end
        set(app.pathEdit, 'String', fullfile(fp, fn));
        onTest();
    end

    function onTest(varargin)
        [ok, exe, msg] = check_python_exe(strtrim(get(app.pathEdit, 'String')));
        if ok
            set(app.pathEdit, 'String', exe);
            app = setStatus(app, sprintf('✅ 可用：%s', msg), false);
        else
            app = setStatus(app, sprintf('❌ %s', msg), true);
        end
    end

    function onClear(varargin)
        set(app.pathEdit, 'String', '');
        app = setStatus(app, '已清空，点「保存」后生效（此后不再使用任何 Python）。', false);
    end

    function onSave(varargin)
        raw = strtrim(get(app.pathEdit, 'String'));
        if isempty(raw)
            cfgOut = struct('PythonPath', '');
        else
            [ok, exe, msg] = check_python_exe(raw);
            if ok
                set(app.pathEdit, 'String', exe);
                cfgOut = struct('PythonPath', exe);
            else
                choice = questdlg( ...
                    sprintf('该路径测试未通过：\n%s\n\n仍要保存吗？', msg), ...
                    'Python 路径设置', '仍然保存', '返回修改', '返回修改');
                if ~strcmp(choice, '仍然保存')
                    return;
                end
                cfgOut = struct('PythonPath', raw);
            end
        end

        if ~writeJsonPath(app.cfgFile, cfgOut.PythonPath)
            app = setStatus(app, sprintf('保存失败：无法写入配置文件\n%s', app.cfgFile), true);
            return;
        end
        setappdata(app.fig, 'Result', cfgOut);
        uiresume(app.fig);
    end

    function onCancel(varargin)
        setappdata(app.fig, 'Result', []);
        uiresume(app.fig);
    end
end

% ==================================================================
%  局部辅助
% ==================================================================

function app = setStatus(app, msg, isError)
if isError
    set(app.statusText, 'ForegroundColor', [0.75, 0.15, 0.15]);
else
    set(app.statusText, 'ForegroundColor', [0.15, 0.45, 0.15]);
end
set(app.statusText, 'String', strsplit(char(msg), sprintf('\n')));
end

function p = readJsonPath(configFile)
% 读取现有配置里的 PythonPath；文件缺失/损坏时返回 ''
p = '';
if exist(configFile, 'file') ~= 2
    return;
end
try
    data = jsondecode(fileread(configFile));
catch
    return;
end
if ~isstruct(data) || ~isfield(data, 'PythonPath')
    return;
end
v = data.PythonPath;
if isstring(v)
    v = char(v);
end
if ischar(v)
    p = strtrim(v);
end
end

function ok = writeJsonPath(configFile, pythonPath)
% 写 python_config.json（UTF-8）；路径为空则删除配置文件
ok = false;
try
    if isempty(strtrim(pythonPath))
        if exist(configFile, 'file') == 2
            delete(configFile);
        end
        ok = true;
        return;
    end
    txt = jsonencode(struct('PythonPath', pythonPath));
    fid = fopen(configFile, 'w', 'n', 'UTF-8');
    if fid < 0
        return;
    end
    fwrite(fid, txt, 'char');
    fclose(fid);
    ok = true;
catch
end
end
