function [ok, exe, msg] = check_python_exe(rawPath)
%CHECK_PYTHON_EXE 规范化并校验用户手动填写的 Python 路径
%
%   [ok, exe, msg] = check_python_exe(rawPath)
%
%   接受的输入形式：
%     - python.exe 完整路径（允许首尾多余空白或成对引号）
%     - Python 安装目录（自动尝试该目录下的 python.exe / python3.exe / python3 / python）
%     - 裸命令名（如 python、python3，交给系统按 PATH 解析）
%
%   ok  : true 表示该 Python 可以执行
%   exe : 规范化后的路径（ok 为 true 时有效）
%   msg : ok 为 true 时是版本信息，否则是失败原因（可直接展示给用户）

ok = false;
exe = '';
msg = '';

if nargin < 1 || isempty(rawPath)
    msg = '路径为空。';
    return;
end

cand = strtrim(char(string(rawPath)));
cand = stripQuotes(cand);
cand = strtrim(cand);
if isempty(cand)
    msg = '路径为空。';
    return;
end

% 命令拼接安全：下面用 system 以双引号包裹路径，输入里不能再出现引号/换行
if contains(cand, '"') || contains(cand, newline) || contains(cand, char(13))
    msg = '路径中不能包含双引号或换行符，请重新填写。';
    return;
end

[found, resolved] = resolvePythonCandidate(cand);
if ~found
    msg = sprintf('找不到该 Python 可执行文件：%s', cand);
    return;
end

[st, verOut] = system(sprintf('"%s" --version 2>&1', resolved));
verOut = strtrim(verOut);
if st ~= 0
    if isempty(verOut)
        msg = sprintf('无法执行该 Python（退出码 %d）：%s', st, resolved);
    else
        msg = sprintf('无法执行该 Python：%s\n%s', resolved, verOut);
    end
    return;
end

exe = resolved;
ok = true;
if isempty(verOut)
    msg = resolved;
else
    msg = verOut;
end
end

% ==================================================================
%  局部辅助
% ==================================================================

function s = stripQuotes(s)
% 去掉首尾成对的引号（用户常从资源管理器/终端复制带引号的路径）
while numel(s) >= 2 && ...
        ((s(1) == '"' && s(end) == '"') || (s(1) == '''' && s(end) == ''''))
    s = strtrim(s(2:end-1));
end
end

function [found, resolved] = resolvePythonCandidate(cand)
% 把用户输入解析成可执行文件路径；解析不出返回 found = false
found = false;
resolved = cand;

% 1) 本身就是一个文件
if exist(cand, 'file') == 2
    found = true;
    return;
end

% 2) 填的是安装目录 → 找目录下的解释器
if exist(cand, 'dir') == 7
    names = {'python.exe', 'python3.exe', 'python3', 'python'};
    for i = 1:numel(names)
        p = fullfile(cand, names{i});
        if exist(p, 'file') == 2
            resolved = p;
            found = true;
            return;
        end
    end
    return; % 目录存在但没有解释器，按失败处理
end

% 3) Windows 下漏写扩展名
if ispc && exist([cand, '.exe'], 'file') == 2
    resolved = [cand, '.exe'];
    found = true;
    return;
end

% 4) 裸命令名（不含路径分隔符）→ 交给系统按 PATH 解析
if isempty(regexp(cand, '^[A-Za-z0-9_.\-]+$', 'once'))
    return;
end
found = true;
resolved = cand;
end
