function [pyExe, reason] = getPythonExe(configFile)
%GETPYTHONEXE 取用户手动设置的 Python 可执行文件路径
%
%   pyExe = getPythonExe()
%   [pyExe, reason] = getPythonExe()
%   [...] = getPythonExe(configFile)   % 指定配置文件（默认 python_config.json）
%
%   只使用用户在 GUI 二级界面「Python 路径设置…」中手动指定的路径，配置文件
%   python_config.json（字段 PythonPath，见 python_config_path.m）。
%   不做任何自动搜索：pyenv / PATH / 注册表 / 常见安装目录一律不查。
%
%   pyExe  : 可用的 Python 可执行文件路径；未设置或不可用时返回 ''
%   reason : pyExe 为空时说明原因（可直接展示给用户），非空时是版本信息

pyExe = '';
reason = '';

if nargin < 1 || isempty(configFile)
    configFile = python_config_path();
end
configFile = char(string(configFile));

raw = readConfiguredPath(configFile);
if isempty(raw)
    reason = sprintf(['尚未设置 Python 路径。请在主窗口空白处右键 →「Python 路径设置…」' ...
        '手动指定 python.exe（配置文件：%s）。'], configFile);
    return;
end

[ok, exe, msg] = check_python_exe(raw);
if ~ok
    reason = sprintf('已设置的 Python 路径不可用，请重新设置。\n路径：%s\n原因：%s', raw, msg);
    return;
end

pyExe = exe;
reason = msg;
end

% ==================================================================
%  局部辅助
% ==================================================================

function raw = readConfiguredPath(configFile)
% 读取配置文件里的 PythonPath 字段；文件缺失/损坏时返回 ''
raw = '';
if exist(configFile, 'file') ~= 2
    return;
end
try
    data = jsondecode(fileread(configFile));
catch
    return;
end
if ~isstruct(data)
    return;
end

flds = fieldnames(data);
for i = 1:numel(flds)
    if ~strcmpi(flds{i}, 'PythonPath')
        continue;
    end
    v = data.(flds{i});
    if isstring(v)
        v = char(v);
    end
    if ischar(v)
        raw = strtrim(v);
    end
    return;
end
end
