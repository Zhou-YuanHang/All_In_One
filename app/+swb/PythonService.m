classdef PythonService
    %SWB.PYTHONSERVICE Python 定位与调用（模板生成 / 反向同步 helper）。
    %   Python 路径只来自配置（Settings.PythonPath 或调用方显式传入），不做任何
    %   自动搜索（与旧 getPythonExe 的行为一致）；找不到时返回 ok=false + 可读消息，
    %   绝不抛错（只有参数为空/类型错误才 error）。
    %
    %   exe = swb.PythonService.resolve(settings)
    %   [ok, msg] = swb.PythonService.validate(exe)
    %   r = swb.PythonService.generateTemplate(outFile, opts)   % opts: Empty, Config, Exe
    %   r = swb.PythonService.runReverseHelper(jsonFile, opts) % opts: Exe
    %
    %   脚本位置：优先 app/resources/*.py，回退 src/AutoCreateSldd/*.py（绝对路径 + system）。

    methods (Static)
        function exe = resolve(settings)
            % 从 settings（swb.Settings / struct.PythonPath / 路径字符串）解析可用 Python；无则 ''
            exe = '';
            raw = swb.PythonService.configuredPath(settings);
            if isempty(raw)
                return;
            end
            [found, resolved] = swb.PythonService.normalizeExe(raw);
            if ~found
                return;
            end
            [ok, ~] = swb.PythonService.validate(resolved);
            if ok
                exe = resolved;
            end
        end

        function [ok, msg] = validate(exe)
            % 探测 Python 是否可执行：运行 --version（结果按路径缓存）
            ok = false;
            msg = '';
            if nargin < 1 || isempty(exe)
                msg = 'Python 路径为空。';
                return;
            end
            exe = strtrim(char(string(exe)));
            if isempty(exe)
                msg = 'Python 路径为空。';
                return;
            end
            persistent cache
            if isempty(cache)
                cache = containers.Map();
            end
            if isKey(cache, exe)
                entry = cache(exe);
                ok = entry.ok;
                msg = entry.msg;
                return;
            end
            [found, resolved] = swb.PythonService.normalizeExe(exe);
            if ~found
                msg = sprintf('找不到该 Python 可执行文件：%s', exe);
                cache(exe) = struct('ok', false, 'msg', msg);
                return;
            end
            if contains(resolved, '"') || contains(resolved, newline) || contains(resolved, char(13))
                msg = '路径中不能包含双引号或换行符，请重新填写。';
                cache(exe) = struct('ok', false, 'msg', msg);
                return;
            end
            [st, out] = system(sprintf('"%s" --version 2>&1', resolved));
            out = strtrim(out);
            if st ~= 0
                if isempty(out)
                    msg = sprintf('无法执行该 Python（退出码 %d）：%s', st, resolved);
                else
                    msg = sprintf('无法执行该 Python：%s\n%s', resolved, out);
                end
                cache(exe) = struct('ok', false, 'msg', msg);
                return;
            end
            ok = true;
            if isempty(out)
                msg = resolved;
            else
                msg = out;
            end
            cache(exe) = struct('ok', true, 'msg', msg);
        end

        function r = generateTemplate(outFile, opts)
            % 调 generate_template.py 生成 8 表模板
            r = swb.PythonService.emptyResult();
            if nargin < 2 || isempty(opts)
                opts = struct();
            end
            opts = swb.PythonService.withDefaults(opts, struct('Empty', false, 'Config', [], 'Exe', ''));
            if nargin < 1 || isempty(outFile)
                r.message = '输出文件路径为空。';
                return;
            end
            outFile = char(outFile);
            r.outFile = outFile;

            exe = swb.PythonService.pickExe(opts.Exe);
            r.exe = exe;
            if isempty(exe)
                r.message = swb.PythonService.missingPythonMessage(opts.Exe);
                return;
            end
            script = swb.PythonService.scriptPath('generate_template.py');
            r.script = script;
            if isempty(script)
                r.message = '找不到 generate_template.py（app/resources 与 src/AutoCreateSldd 都不存在）。';
                return;
            end
            [outDir, ~, ~] = fileparts(outFile);
            if ~isempty(outDir) && ~isfolder(outDir)
                mkdir(outDir);
            end

            cfgFile = '';
            cleaner = [];
            if isstruct(opts.Config) && ~isempty(fieldnames(opts.Config))
                cfgFile = [tempname() '.json'];
                fid = fopen(cfgFile, 'w', 'n', 'UTF-8');
                if fid >= 0
                    fwrite(fid, jsonencode(opts.Config), 'char');
                    fclose(fid);
                    cleaner = onCleanup(@() swb.PythonService.deleteIfExists(cfgFile)); %#ok<NASGU>
                else
                    cfgFile = '';
                end
            end

            parts = {sprintf('"%s"', exe), sprintf('"%s"', script)};
            if ~isempty(cfgFile)
                parts{end+1} = sprintf('--config "%s"', cfgFile);
            end
            if opts.Empty
                parts{end+1} = '--empty';
            end
            parts{end+1} = sprintf('"%s"', outFile);
            cmd = strjoin(parts, ' ');
            r.cmd = cmd;

            [r.exitCode, r.stdout, r.stderr] = swb.PythonService.runCapture(cmd);
            r.ok = r.exitCode == 0 && isfile(outFile);
            if r.ok
                r.message = strtrim(r.stdout);
            else
                r.message = swb.PythonService.failureMessage(r, '生成模板');
            end
        end

        function r = runReverseHelper(jsonFile, opts)
            % 调 sldd_to_excel_helper.py 把 JSON 写回 Excel
            r = swb.PythonService.emptyResult();
            if nargin < 2 || isempty(opts)
                opts = struct();
            end
            opts = swb.PythonService.withDefaults(opts, struct('Exe', ''));
            if nargin < 1 || isempty(jsonFile) || ~isfile(char(jsonFile))
                r.message = sprintf('JSON 文件不存在: %s', char(jsonFile));
                return;
            end
            jsonFile = char(jsonFile);
            r.jsonFile = jsonFile;

            exe = swb.PythonService.pickExe(opts.Exe);
            r.exe = exe;
            if isempty(exe)
                r.message = swb.PythonService.missingPythonMessage(opts.Exe);
                return;
            end
            script = swb.PythonService.scriptPath('sldd_to_excel_helper.py');
            r.script = script;
            if isempty(script)
                r.message = '找不到 sldd_to_excel_helper.py（app/resources 与 src/AutoCreateSldd 都不存在）。';
                return;
            end
            cmd = sprintf('"%s" "%s" "%s"', exe, script, jsonFile);
            r.cmd = cmd;
            [r.exitCode, r.stdout, r.stderr] = swb.PythonService.runCapture(cmd);
            r.ok = r.exitCode == 0;
            if r.ok
                r.message = strtrim(r.stdout);
            else
                r.message = swb.PythonService.failureMessage(r, '反向同步');
            end
        end

        function p = scriptPath(name)
            % Python 脚本绝对路径：app/resources 优先，回退 src/AutoCreateSldd
            p = '';
            if nargin < 1 || isempty(name)
                return;
            end
            here = fileparts(mfilename('fullpath'));
            appRoot = fileparts(here);
            repoRoot = fileparts(appRoot);
            candidates = {fullfile(appRoot, 'resources', char(name)), ...
                          fullfile(repoRoot, 'src', 'AutoCreateSldd', char(name))};
            for k = 1:numel(candidates)
                if isfile(candidates{k})
                    p = candidates{k};
                    return;
                end
            end
        end
    end

    methods (Static, Access = private)
        function r = emptyResult()
            r = struct('ok', false, 'exe', '', 'script', '', 'outFile', '', 'jsonFile', '', ...
                       'cmd', '', 'exitCode', NaN, 'stdout', '', 'stderr', '', 'message', '');
        end

        function opts = withDefaults(opts, defaults)
            f = fieldnames(defaults);
            for k = 1:numel(f)
                if ~isfield(opts, f{k})
                    opts.(f{k}) = defaults.(f{k});
                end
            end
        end

        function raw = configuredPath(settings)
            raw = '';
            if nargin < 1 || isempty(settings)
                return;
            end
            if isa(settings, 'swb.Settings')
                raw = settings.PythonPath;
            elseif isstruct(settings) && isfield(settings, 'PythonPath')
                raw = settings.PythonPath;
            elseif ischar(settings) || isstring(settings)
                raw = char(settings);
            end
            if isstring(raw) && isscalar(raw) && ~ismissing(raw)
                raw = char(raw);
            end
            if ~ischar(raw)
                raw = '';
            end
            raw = strtrim(raw);
        end

        function exe = pickExe(raw)
            % 显式 Exe 优先；为空时读 Settings；返回已验证的绝对路径或 ''
            exe = '';
            if ~isempty(raw)
                [found, resolved] = swb.PythonService.normalizeExe(raw);
                if found
                    [ok, ~] = swb.PythonService.validate(resolved);
                    if ok
                        exe = resolved;
                    end
                end
                return;
            end
            try
                settings = swb.Settings();
                exe = swb.PythonService.resolve(settings);
            catch
                exe = '';
            end
        end

        function msg = missingPythonMessage(raw)
            if isempty(raw)
                msg = ['未找到可用的 Python。请在「设置 → Python 路径」中指定 python.exe，' ...
                       '或在调用时通过 opts.Exe 传入。'];
            else
                [~, detail] = swb.PythonService.validate(raw);
                msg = sprintf('Python 不可用：%s\n%s', char(raw), detail);
            end
        end

        function msg = failureMessage(r, action)
            if ~isempty(strtrim(r.stderr))
                msg = sprintf('%s失败（exit=%d）：%s', action, r.exitCode, strtrim(r.stderr));
            elseif ~isempty(strtrim(r.stdout))
                msg = sprintf('%s失败（exit=%d）：%s', action, r.exitCode, strtrim(r.stdout));
            else
                msg = sprintf('%s失败（exit=%d）。', action, r.exitCode);
            end
        end

        function [found, resolved] = normalizeExe(raw)
            % 规范化用户填写的 Python 路径：
            %   python.exe 完整路径 / Python 安装目录 / 裸命令名（交给 PATH）
            found = false;
            if isempty(raw)
                return;
            end
            cand = strtrim(char(string(raw)));
            cand = swb.PythonService.stripQuotes(cand);
            cand = strtrim(cand);
            if isempty(cand)
                return;
            end
            resolved = cand;
            if exist(cand, 'file') == 2
                found = true;
                return;
            end
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
                return;
            end
            if ispc && exist([cand, '.exe'], 'file') == 2
                resolved = [cand, '.exe'];
                found = true;
                return;
            end
            if isempty(regexp(cand, '^[A-Za-z0-9_.\-]+$', 'once'))
                return;
            end
            found = true;
            resolved = cand;
        end

        function s = stripQuotes(s)
            while numel(s) >= 2 && ...
                    ((s(1) == '"' && s(end) == '"') || (s(1) == '''' && s(end) == ''''))
                s = strtrim(s(2:end-1));
            end
        end

        function [st, out, err] = runCapture(cmd)
            % system 无法区分 stdout/stderr，这里分别重定向到临时文件再读回
            outF = [tempname() '.out.txt'];
            errF = [tempname() '.err.txt'];
            cleaner = onCleanup(@() swb.PythonService.cleanupFiles({outF, errF})); %#ok<NASGU>
            full = sprintf('%s > "%s" 2> "%s"', cmd, outF, errF);
            st = system(full);
            out = swb.PythonService.readText(outF);
            err = swb.PythonService.readText(errF);
        end

        function txt = readText(p)
            txt = '';
            try
                if isfile(p)
                    txt = fileread(p);
                end
            catch
                txt = '';
            end
        end

        function cleanupFiles(list)
            for k = 1:numel(list)
                swb.PythonService.deleteIfExists(list{k});
            end
        end

        function deleteIfExists(p)
            try
                if ~isempty(p) && isfile(p)
                    delete(p);
                end
            catch
            end
        end
    end
end
