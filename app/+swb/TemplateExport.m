classdef TemplateExport
    %SWB.TEMPLATEEXPORT 导出 SLDD 数据字典 Excel 模板（8 张表）。
    %   移植旧工具 src/AutoCreateSldd/sldd_gui.m 的「生成模板」按钮（该目录已移除）：
    %   有可用 Python 时调 app/resources/generate_template.py（含示例数据 / --empty，
    %   并把 Config 候选值经 --config 写入下拉列表）；Python 缺失或失败时退化为
    %   MATLAB writecell 基本模板（8 张表头 + History 版本行 + Config 候选值）。
    %
    %   r = swb.TemplateExport.toWorkbook(outFile, opts)
    %       opts: Empty(false)      只写表头，不写示例数据
    %             Config([])        Config 表候选值（swb.TemplateConfig / Schema.defaultConfig）
    %             Exe('')           Python 可执行文件（空则取配置里的；不可用走退化）
    %             Log([])           可选 swb.Log，写入"用哪条路径生成"的说明
    %       r: ok, file, usedFallback, message, exe, exitCode, stdout, stderr
    %
    %   f   = swb.TemplateExport.defaultFile(dictPath)   默认输出名 <字典目录>/MCU_Template.xlsx
    %   ok  = swb.TemplateExport.writeMatlabBasic(outFile, cfg, content)

    methods (Static)
        function r = toWorkbook(outFile, opts)
            %TOWORKBOOK 生成 8 表模板：优先 Python，失败退化 MATLAB 基本模板。
            r = struct('ok', false, 'file', '', 'usedFallback', false, 'message', '', ...
                       'exe', '', 'exitCode', NaN, 'stdout', '', 'stderr', '');
            if nargin < 2 || isempty(opts) || ~isstruct(opts)
                opts = struct();
            end
            opts = swb.TemplateExport.withDefaults(opts, struct( ...
                'Empty', false, 'Config', [], 'Exe', '', 'Log', []));

            if nargin < 1 || isempty(outFile)
                r.message = '输出文件路径为空。';
                return;
            end
            outFile = char(outFile);
            [~, ~, ext] = fileparts(outFile);
            if isempty(ext)
                outFile = [outFile '.xlsx'];
            elseif ~any(strcmpi(ext, {'.xlsx', '.xls'}))
                r.message = sprintf('模板必须是 .xlsx 工作簿，收到 "%s"。', outFile);
                return;
            end
            r.file = outFile;

            % 1) 首选 Python：与旧工具完全一致的模板（示例数据 + 下拉列表）
            pr = swb.PythonService.generateTemplate(outFile, struct( ...
                'Empty', logical(opts.Empty), 'Config', opts.Config, 'Exe', opts.Exe));
            r.exe = pr.exe;
            r.exitCode = pr.exitCode;
            r.stdout = pr.stdout;
            r.stderr = pr.stderr;
            if pr.ok
                r.ok = true;
                r.message = pr.message;
                r = swb.TemplateExport.note(r, opts, sprintf( ...
                    '已用 generate_template.py 生成%s模板：%s', ...
                    swb.TemplateExport.kindWord(opts.Empty), outFile));
                return;
            end
            r = swb.TemplateExport.note(r, opts, sprintf( ...
                'Python 生成模板不可用，改用 MATLAB 基本模板：%s', pr.message));

            % 2) 退化：MATLAB writecell 基本模板（表头 + Config 候选值）
            if swb.TemplateExport.writeMatlabBasic(outFile, opts.Config, '模板导出')
                r.ok = true;
                r.usedFallback = true;
                r.message = '没有可用的 Python，已用 MATLAB 生成基本模板。';
                r = swb.TemplateExport.note(r, opts, sprintf( ...
                    '已用 MATLAB（writecell）生成基本模板：%s', outFile));
            else
                r.ok = false;
                r.message = sprintf('无法生成模板：%s', outFile);
                r = swb.TemplateExport.note(r, opts, r.message);
            end
        end

        function f = defaultFile(dictPath)
            %DEFAULTFILE 默认模板路径：<字典工作簿所在目录>/MCU_Template.xlsx。
            %   字典路径为空或不是工作簿时退回当前目录；沿用旧工具的默认文件名，
            %   便于已经习惯旧工具的用户。
            f = fullfile(pwd, 'MCU_Template.xlsx');
            if nargin < 1 || isempty(dictPath)
                return;
            end
            dictPath = char(dictPath);
            [d, ~, ext] = fileparts(dictPath);
            if isempty(d) || ~any(strcmpi(ext, {'.xlsx', '.xls'}))
                return;
            end
            if ~isfolder(d)
                return;
            end
            f = fullfile(d, 'MCU_Template.xlsx');
        end

        function ok = writeMatlabBasic(outFile, cfg, content)
            %WRITEMATLABBASIC Python 不可用时的退化模板：History + 6 表头 + Config 候选值。
            %   逐表 writecell 到 outFile（已存在则先删除），列序与表名全部来自
            %   swb.Schema，保证与 Python 模板、校验、反向同步共用同一份契约。
            try
                if nargin < 3 || isempty(content)
                    content = '模板导出';
                end
                outDir = fileparts(outFile);
                if ~isempty(outDir) && ~isfolder(outDir)
                    mkdir(outDir);
                end
                if isfile(outFile)
                    delete(outFile);
                end
                hist = [{'Version', 'ChangeDate', 'Changer', 'Content'}; ...
                        {'V1.0', char(datetime('today', 'Format', 'yyyy-MM-dd')), ...
                         'SimWorkbench', char(content)}];
                writecell(hist, outFile, 'Sheet', 'History');
                list = {'Signal', 'Parameter', 'Const', 'Enum', 'Bus', 'BusElement'};
                for k = 1:numel(list)
                    writecell(swb.Schema.dictColumns(list{k}), outFile, 'Sheet', list{k});
                end
                if nargin < 2 || isempty(cfg)
                    cfg = swb.Schema.defaultConfig();
                end
                cfg = swb.TemplateConfig.normalize(cfg);
                cols = swb.Schema.configColumns();
                maxLen = 0;
                for c = 1:numel(cols)
                    maxLen = max(maxLen, numel(cfg.(cols(c).key)));
                end
                data = cell(maxLen + 1, numel(cols));
                for c = 1:numel(cols)
                    data{1, c} = cols(c).header;
                    vals = cfg.(cols(c).key);
                    for r = 1:numel(vals)
                        data{r + 1, c} = vals{r};
                    end
                end
                writecell(data, outFile, 'Sheet', 'Config');
                ok = isfile(outFile);
            catch
                ok = false;
            end
        end
    end

    methods (Static, Access = private)
        function opts = withDefaults(opts, d)
            % 只补缺失字段，调用方显式给的空值（如 Config=[]）原样保留。
            names = fieldnames(d);
            for k = 1:numel(names)
                if ~isfield(opts, names{k})
                    opts.(names{k}) = d.(names{k});
                end
            end
        end

        function word = kindWord(tfEmpty)
            if logical(tfEmpty)
                word = '空';
            else
                word = '示例数据';
            end
        end

        function r = note(r, opts, msg)
            if isfield(opts, 'Log') && ~isempty(opts.Log)
                try
                    opts.Log.info('%s', msg);
                catch
                end
            end
        end
    end
end
