%SWB.SMOKE_DICT 数据字典侧端到端冒烟：校验 -> 生成脚本 -> 写入 .sldd -> 反向同步回 Excel
function smoke_dict()
root = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(root, 'app'));
addpath(fullfile(root, 'tests'));

d = tempname(); mkdir(d);
cleaner = onCleanup(@() rmQuiet(d));
fails = {};

% 1) 夹具工作簿
wb = swbfixture.Workbooks.makeDict(d);
fprintf('[1] fixture: %s\n', wb);

% 2) 校验
issues = swb.Validator.run(wb, {});
nErr = nnz(strcmp({issues.severity}, 'error'));
nWarn = nnz(strcmp({issues.severity}, 'warning'));
fprintf('[2] validator: error=%d warning=%d\n', nErr, nWarn);
if nErr ~= 0
    fails{end+1} = sprintf('合法工作簿出现 %d 个 error', nErr);
    for k = 1:numel(issues), fprintf('    %s\n', swb.Issue.format(issues(k))); end
end

% 3) 生成脚本（Enum 文件写在同目录）
sldd = fullfile(d, 'sample.sldd');
r = swb.ScriptBuilder.build(wb, {}, fullfile(d, 'objects.m'));
fprintf('[3] scriptbuilder: ok=%d objects=%d enumFiles=%d warnings=%d\n', ...
    r.ok, numel(r.objects), numel(r.enumFiles), numel(r.warnings));
if ~r.ok, fails{end+1} = 'ScriptBuilder.ok=false'; end

% 4) 写字典
stats = swb.Dictionary.writeScript(sldd, r.text);
fprintf('[4] dictionary: ok=%d added=%d updated=%d skipped=%d failed=%d totalAfter=%d\n', ...
    stats.ok, stats.added, stats.updated, stats.skipped, stats.failed, stats.totalAfter);
if ~stats.ok
    fails{end+1} = ['Dictionary.ok=false: ' stats.errorText];
    for k = 1:numel(stats.messages), fprintf('    %s\n', stats.messages{k}); end
end
entries = swb.Dictionary.readEntries(sldd);
fprintf('    entries=%d: %s\n', numel(entries), strjoin({entries.Name}, ', '));

% 5) Python
exe = swb.PythonService.resolve(swb.Settings());
if isempty(exe) && isfile('D:\SoftwareInstallation\Python3147\python.exe')
    exe = 'D:\SoftwareInstallation\Python3147\python.exe';
end
fprintf('[5] python: [%s]\n', exe);
[pyOk, pyMsg] = swb.PythonService.validate(exe);
fprintf('    validate=%d %s\n', pyOk, pyMsg);

% 6) 反向同步到新工作簿
back = fullfile(d, 'reverse', 'back.xlsx');
rs = swb.ReverseSync.toWorkbook(sldd, back, struct('Exe', exe));
fprintf('[6] reverse: ok=%d created=%d rows=[S%d P%d C%d B%d BE%d E%d] err=%s\n', ...
    rs.ok, rs.workbookCreated, rs.rows.Signal, rs.rows.Parameter, rs.rows.Const, ...
    rs.rows.Bus, rs.rows.BusElement, rs.rows.Enum, rs.errorText);
for k = 1:numel(rs.messages), fprintf('    %s\n', rs.messages{k}); end
if ~rs.ok, fails{end+1} = ['ReverseSync: ' rs.errorText]; end
if ~isfile(back), fails{end+1} = '目标工作簿不存在'; end

% 7) 回读工作簿
if isfile(back)
    sheets = cellstr(sheetnames(back));
    fprintf('[7] sheets: %s\n', strjoin(sheets, ', '));
    for sn = {'Signal','Parameter','Const','Bus','BusElement','Enum'}
        t = swb.Workbook.readSheetTable(back, sn{1});
        fprintf('    %-10s rows=%d\n', sn{1}, size(t.rows, 1));
    end
end

fprintf('\n===== SMOKE RESULT: %d failure(s) =====\n', numel(fails));
for k = 1:numel(fails), fprintf('  FAIL: %s\n', fails{k}); end
if ~isempty(fails)
    error('smoke failed');
end
end

function rmQuiet(d)
try, if isfolder(d), rmdir(d, 's'); end, catch, end
end
