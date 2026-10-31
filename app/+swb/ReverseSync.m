classdef ReverseSync
    %SWB.REVERSESYNC 数据字典 .sldd -> Excel 反向同步（MATLAB 侧编排）。
    %   迁移旧 sldd_to_excel.m（原 src/AutoCreateSldd，已移除）：
    %     读 Design Data 本地条目 -> 分类 Signal/Parameter/Const/Bus/BusElement/Enum
    %     -> 组装与旧实现一致的 JSON -> 调用 sldd_to_excel_helper.py 写回 Excel。
    %   目标工作簿不存在时：优先 generate_template.py --empty 生成；Python 不可用时
    %   退化为 MATLAB writecell 的基本模板（表头/列序由 Schema 决定）。
    %
    %   result = swb.ReverseSync.toWorkbook(dictPath, workbookPath, opts)
    %     opts: CleanExcel(false), PythonService/Exe, Log
    %   result: ok, rows(Signal/Parameter/Const/Bus/BusElement/Enum 计数),
    %           workbookCreated(bool), messages(cellstr),
    %           errorText, exitCode, stdout, dictPath, workbookPath

    methods (Static)
        function result = toWorkbook(dictPath, workbookPath, opts)
            if nargin < 1 || isempty(dictPath)
                error('swb:ReverseSync:missingDict', '数据字典路径为空。');
            end
            dictPath = char(dictPath);
            if ~isfile(dictPath)
                error('swb:ReverseSync:missingDict', '数据字典不存在: %s', dictPath);
            end
            if nargin < 2 || isempty(workbookPath)
                error('swb:ReverseSync:missingWorkbook', '目标工作簿路径为空。');
            end
            workbookPath = char(workbookPath);
            [~, ~, we] = fileparts(workbookPath);
            if isempty(we)
                workbookPath = [workbookPath '.xlsx'];
            end
            if nargin < 3 || isempty(opts)
                opts = struct();
            end
            opts = swb.ReverseSync.withDefaults(opts, struct( ...
                'CleanExcel', false, 'Exe', '', 'PythonService', [], 'Log', [], 'Config', []));

            result = struct('ok', false, 'rows', swb.ReverseSync.emptyCounts(), ...
                'workbookCreated', false, 'messages', {{}}, 'errorText', '', ...
                'exitCode', NaN, 'stdout', '', 'dictPath', dictPath, ...
                'workbookPath', workbookPath);

            % 1) 读字典本地条目并分类
            entries = swb.Dictionary.readEntries(dictPath);
            [sheetRows, counts] = swb.ReverseSync.classifyEntries(entries);
            enumRows = swb.ReverseSync.readEnumFiles(fileparts(dictPath));
            sheetRows.Enum = enumRows;
            counts.Enum = size(enumRows, 1);
            result.rows = counts;
            total = sum(structfun(@(v) double(v), counts));
            result = swb.ReverseSync.note(result, opts, sprintf( ...
                '数据字典读取完成：共 %d 条（Signal %d / Parameter %d / Const %d / Bus %d / BusElement %d / Enum %d）。', ...
                total, counts.Signal, counts.Parameter, counts.Const, counts.Bus, counts.BusElement, counts.Enum));

            % 2) 解析 Python 可执行文件（允许为空，后面退化）
            exe = swb.ReverseSync.resolveExe(opts);

            % 3) 目标工作簿不存在则创建
            if ~isfile(workbookPath)
                created = false;
                if ~isempty(exe)
                    tr = swb.PythonService.generateTemplate(workbookPath, ...
                        struct('Empty', true, 'Exe', exe, 'Config', opts.Config));
                    created = tr.ok && isfile(workbookPath);
                    if created
                        result = swb.ReverseSync.note(result, opts, ...
                            '目标工作簿不存在，已用 generate_template.py 生成空模板。');
                    else
                        result = swb.ReverseSync.note(result, opts, sprintf( ...
                            'Python 生成模板失败，改用 MATLAB 基本模板：%s', tr.message));
                    end
                end
                if ~created
                    if swb.ReverseSync.writeMatlabTemplate(workbookPath, opts.Config)
                        created = true;
                        result = swb.ReverseSync.note(result, opts, ...
                            '目标工作簿不存在，已用 MATLAB writecell 生成基本模板。');
                    end
                end
                result.workbookCreated = created;
                if ~created
                    result.ok = false;
                    result.errorText = sprintf('无法创建目标工作簿: %s', workbookPath);
                    result = swb.ReverseSync.note(result, opts, result.errorText);
                    return;
                end
            end

            % 4) 组装 JSON
            jsonData = swb.ReverseSync.buildJson(workbookPath, opts.CleanExcel, sheetRows);
            if isempty(fieldnames(jsonData.sheets))
                result.ok = true;
                result = swb.ReverseSync.note(result, opts, '字典中没有可写回 Excel 的数据。');
                return;
            end

            if isempty(exe)
                result.ok = false;
                result.errorText = ['没有可用的 Python，无法调用 sldd_to_excel_helper.py 写回 Excel。' ...
                    '请在设置中配置 Python 路径，或通过 opts.Exe 传入。'];
                result = swb.ReverseSync.note(result, opts, result.errorText);
                return;
            end

            % 5) 写 JSON 并调用 helper
            jsonFile = [tempname() '.json'];
            cleaner = onCleanup(@() swb.ReverseSync.deleteQuiet(jsonFile)); %#ok<NASGU>
            fid = fopen(jsonFile, 'w', 'n', 'UTF-8');
            if fid < 0
                result.ok = false;
                result.errorText = sprintf('无法创建临时 JSON: %s', jsonFile);
                return;
            end
            fwrite(fid, jsonencode(jsonData), 'char');
            fclose(fid);

            hr = swb.PythonService.runReverseHelper(jsonFile, struct('Exe', exe));
            result.exitCode = hr.exitCode;
            result.stdout = hr.stdout;
            if ~hr.ok
                result.ok = false;
                result.errorText = hr.message;
                result = swb.ReverseSync.note(result, opts, sprintf('Python 写回失败：%s', hr.message));
                return;
            end

            % 6) 回读校验表头/工作表
            [verOk, details] = swb.ReverseSync.verifyWorkbook(workbookPath, ...
                fieldnames(jsonData.sheets)');
            for k = 1:numel(details)
                result = swb.ReverseSync.note(result, opts, details{k});
            end
            result.ok = verOk;
            if ~verOk
                result.errorText = '写回后回读校验未通过，详见 messages。';
            else
                result = swb.ReverseSync.note(result, opts, sprintf( ...
                    '反向同步完成：%s', workbookPath));
            end
        end
    end

    methods (Static, Access = private)
        function c = emptyCounts()
            c = struct('Signal', 0, 'Parameter', 0, 'Const', 0, 'Bus', 0, 'BusElement', 0, 'Enum', 0);
        end

        function opts = withDefaults(opts, defaults)
            if ~isstruct(opts)
                return;
            end
            f = fieldnames(defaults);
            for k = 1:numel(f)
                if ~isfield(opts, f{k})
                    opts.(f{k}) = defaults.(f{k});
                end
            end
        end

        function result = note(result, opts, txt)
            result.messages{end+1, 1} = char(txt);
            if isfield(opts, 'Log') && ~isempty(opts.Log)
                try
                    opts.Log.info('%s', char(txt));
                catch
                end
            end
        end

        function exe = resolveExe(opts)
            exe = '';
            try
                if isfield(opts, 'Exe') && ~isempty(opts.Exe)
                    exe = swb.PythonService.resolve(struct('PythonPath', char(opts.Exe)));
                elseif isfield(opts, 'PythonService') && ~isempty(opts.PythonService)
                    ps = opts.PythonService;
                    if ischar(ps) || isstring(ps)
                        exe = swb.PythonService.resolve(struct('PythonPath', char(ps)));
                    else
                        exe = swb.PythonService.resolve(ps);
                    end
                else
                    exe = swb.PythonService.resolve(swb.Settings());
                end
            catch
                exe = '';
            end
        end

        %% ---------- 条目分类与行构造 ----------
        function [rows, counts] = classifyEntries(entries)
            rows = struct('Signal', {{}}, 'Parameter', {{}}, 'Const', {{}}, ...
                          'Bus', {{}}, 'BusElement', {{}}, 'Enum', {{}});
            counts = swb.ReverseSync.emptyCounts();
            for i = 1:numel(entries)
                e = entries(i);
                v = e.Value;
                if isa(v, 'Simulink.Bus')
                    rows.Bus{end+1, 1} = swb.ReverseSync.busRow(e.Name, v); %#ok<AGROW>
                    counts.Bus = counts.Bus + 1;
                    try
                        elements = v.Elements;
                    catch
                        elements = [];
                    end
                    for j = 1:numel(elements)
                        rows.BusElement{end+1, 1} = ...
                            swb.ReverseSync.busElementRow(e.Name, elements(j)); %#ok<AGROW>
                        counts.BusElement = counts.BusElement + 1;
                    end
                elseif isa(v, 'Simulink.Parameter')
                    sc = swb.ReverseSync.readStorageClass(v);
                    if strcmpi(sc, 'Define')
                        rows.Const{end+1, 1} = swb.ReverseSync.constRow(e.Name, v, sc); %#ok<AGROW>
                        counts.Const = counts.Const + 1;
                    else
                        rows.Parameter{end+1, 1} = swb.ReverseSync.paramRow(e.Name, v, sc); %#ok<AGROW>
                        counts.Parameter = counts.Parameter + 1;
                    end
                elseif isa(v, 'Simulink.Signal')
                    sc = swb.ReverseSync.readStorageClass(v);
                    rows.Signal{end+1, 1} = swb.ReverseSync.signalRow(e.Name, v, sc); %#ok<AGROW>
                    counts.Signal = counts.Signal + 1;
                end
            end
        end

        function s = signalRow(name, v, sc)
            [hf, df] = swb.ReverseSync.customFiles(v);
            s = {name, swb.ReverseSync.packageName(v), 'Signal', sc, ...
                 swb.ReverseSync.txt(v.DataType), swb.ReverseSync.txt(v.InitialValue), ...
                 hf, df, swb.ReverseSync.txt(v.Description), ...
                 swb.ReverseSync.txt(v.Min), swb.ReverseSync.txt(v.Max), ...
                 swb.ReverseSync.txt(v.DocUnits), swb.ReverseSync.txt(v.Dimensions), ...
                 swb.ReverseSync.txt(v.Complexity)};
        end

        function s = paramRow(name, v, sc)
            [hf, df] = swb.ReverseSync.customFiles(v);
            s = {name, swb.ReverseSync.packageName(v), 'Parameter', sc, ...
                 swb.ReverseSync.txt(v.DataType), swb.ReverseSync.txt(v.Value), ...
                 hf, df, swb.ReverseSync.txt(v.Description), ...
                 swb.ReverseSync.txt(v.Min), swb.ReverseSync.txt(v.Max), ...
                 swb.ReverseSync.txt(v.DocUnits), swb.ReverseSync.txt(v.Dimensions), ...
                 swb.ReverseSync.txt(v.Complexity)};
        end

        function s = constRow(name, v, sc)
            hf = swb.ReverseSync.customFiles(v);
            s = {name, swb.ReverseSync.packageName(v), sc, ...
                 swb.ReverseSync.txt(v.Value), swb.ReverseSync.txt(v.DataType), hf};
        end

        function s = busRow(name, v)
            s = {name, swb.ReverseSync.txt(v.Description), swb.ReverseSync.txt(v.HeaderFile), ...
                 swb.ReverseSync.txt(v.Alignment), ...
                 swb.ReverseSync.boolText(v.PreserveElementDimensions), ...
                 swb.ReverseSync.txt(v.DataScope)};
        end

        function s = busElementRow(busName, el)
            s = {busName, swb.ReverseSync.txt(el.Name), swb.ReverseSync.txt(el.DataType), ...
                 swb.ReverseSync.txt(el.Dimensions), swb.ReverseSync.txt(el.Description), ...
                 swb.ReverseSync.txt(el.DocUnits)};
        end

        function [hf, df] = customFiles(v)
            hf = '';
            df = '';
            try
                hf = swb.ReverseSync.txt(v.CoderInfo.CustomAttributes.HeaderFile);
            catch
            end
            try
                df = swb.ReverseSync.txt(v.CoderInfo.CustomAttributes.DefinitionFile);
            catch
            end
        end

        function sc = readStorageClass(v)
            sc = '';
            try
                raw = v.CoderInfo.StorageClass;
                if strcmpi(raw, 'Custom')
                    try
                        sc = v.CoderInfo.CustomStorageClass;
                    catch
                        sc = '';
                    end
                elseif strcmpi(raw, 'Default')
                    sc = '';
                else
                    sc = raw;
                end
            catch
                sc = '';
            end
        end

        function pkg = packageName(v)
            c = class(v);
            dot = strfind(c, '.');
            if isempty(dot)
                pkg = 'Simulink';
            else
                pkg = c(1:dot(1)-1);
            end
        end

        function s = txt(v)
            s = '';
            if isempty(v)
                return;
            end
            if islogical(v)
                if v
                    s = 'True';
                else
                    s = 'False';
                end
            elseif isnumeric(v)
                if numel(v) == 1
                    s = num2str(v);
                else
                    s = mat2str(v);
                end
            elseif isstring(v)
                s = char(v);
            elseif ischar(v)
                s = v;
            else
                try
                    s = char(string(v));
                catch
                    s = '';
                end
            end
            s = strtrim(s);
        end

        function s = boolText(v)
            if isempty(v)
                s = '';
            elseif v
                s = 'True';
            else
                s = 'False';
            end
        end

        %% ---------- Enum 文件解析 ----------
        function rows = readEnumFiles(dirPath)
            rows = cell(0, 4);
            if isempty(dirPath) || ~isfolder(dirPath)
                return;
            end
            files = dir(fullfile(dirPath, '*.m'));
            for i = 1:numel(files)
                fn = files(i).name;
                if swb.ReverseSync.isSkipEnumFile(fn)
                    continue;
                end
                try
                    txt = fileread(fullfile(dirPath, fn));
                catch
                    continue;
                end
                if isempty(regexp(txt, '(?m)^\s*enumeration\s*$', 'once'))
                    continue;
                end
                tk = regexp(txt, 'classdef\s+(\w+)\s*<\s*(\w+)', 'tokens', 'once');
                if isempty(tk)
                    continue;
                end
                className = tk{1};
                baseType = tk{2};
                members = regexp(txt, '^\s+(\w+)\s*\(([^)]+)\)\s*$', 'tokens', 'lineanchors');
                for j = 1:numel(members)
                    label = members{j}{1};
                    valText = strtrim(members{j}{2});
                    num = str2double(valText);
                    if ~isnan(num)
                        valText = num2str(num);
                    end
                    rows(end+1, :) = {className, label, valText, baseType}; %#ok<AGROW>
                end
            end
        end

        function tf = isSkipEnumFile(fileName)
            tf = true;
            if contains(fileName, '_objects.m')
                return;
            end
            skip = {'sldd_to_excel.m', 'sldd_to_excel_helper.m', ...
                    'generate_template.m', 'smoke_dict.m'};
            if any(strcmpi(fileName, skip))
                return;
            end
            tf = false;
        end

        %% ---------- JSON 组装 ----------
        function jsonData = buildJson(workbookPath, cleanExcel, sheetRows)
            jsonData = struct('excelPath', workbookPath, ...
                              'cleanExcel', logical(cleanExcel), ...
                              'sheets', struct());
            list = {'Signal', 'Parameter', 'Const', 'Bus', 'BusElement'};
            for k = 1:numel(list)
                sn = list{k};
                r = sheetRows.(sn);
                if isempty(r) && ~cleanExcel
                    continue;
                end
                jsonData.sheets.(sn) = swb.ReverseSync.sheetPayload(sn, r);
            end
            if ~isempty(sheetRows.Enum)
                jsonData.sheets.Enum = swb.ReverseSync.sheetPayload('Enum', sheetRows.Enum);
            end
        end

        function payload = sheetPayload(sheetName, rows)
            payload = struct();
            payload.headers = swb.Schema.dictColumns(sheetName);
            payload.requiredCols = swb.Schema.requiredColumns(sheetName);
            % rows 有两种形状：
            %   1) cell of rows（每个元素是一行的 1xN cell）——Signal/Parameter/Const/Bus/BusElement；
            %   2) MxN 扁平单元格矩阵——Enum（readEnumFiles 直接按行拼）。
            % 统一转成 cell of rows，避免 jsonencode 把 Enum 的字符拆成单字符行。
            if isempty(rows)
                payload.rows = {};
            elseif iscell(rows) && ~iscell(rows{1})
                wrapped = cell(1, size(rows, 1));
                for i = 1:size(rows, 1)
                    wrapped{i} = rows(i, :);
                end
                payload.rows = wrapped;
            else
                payload.rows = rows(:)';
            end
        end

        %% ---------- MATLAB 基本模板（Python 不可用时的退化路径） ----------
        function ok = writeMatlabTemplate(workbookPath, cfg)
            ok = false;
            try
                outDir = fileparts(workbookPath);
                if ~isempty(outDir) && ~isfolder(outDir)
                    mkdir(outDir);
                end
                if isfile(workbookPath)
                    delete(workbookPath);
                end
                hist = [{'Version', 'ChangeDate', 'Changer', 'Content'}; ...
                        {'V1.0', char(datetime('today', 'Format', 'yyyy-MM-dd')), ...
                         'SimWorkbench', '反向同步创建'}];
                writecell(hist, workbookPath, 'Sheet', 'History');
                list = {'Signal', 'Parameter', 'Const', 'Enum', 'Bus', 'BusElement'};
                for k = 1:numel(list)
                    writecell(swb.Schema.dictColumns(list{k}), workbookPath, 'Sheet', list{k});
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
                writecell(data, workbookPath, 'Sheet', 'Config');
                ok = isfile(workbookPath);
            catch
                ok = false;
            end
        end

        %% ---------- 回读校验 ----------
        function [ok, details] = verifyWorkbook(workbookPath, sheetNames)
            ok = true;
            details = {};
            if ~isfile(workbookPath)
                ok = false;
                details{end+1} = sprintf('目标工作簿不存在：%s', workbookPath);
                return;
            end
            try
                actual = cellstr(sheetnames(workbookPath));
            catch ME
                ok = false;
                details{end+1} = sprintf('无法读取目标工作簿：%s', ME.message);
                return;
            end
            for k = 1:numel(sheetNames)
                sn = sheetNames{k};
                if ~any(strcmpi(actual, sn))
                    ok = false;
                    details{end+1} = sprintf('回读校验：工作表 %s 缺失。', sn);
                    continue;
                end
                try
                    raw = readcell(workbookPath, 'Sheet', sn);
                catch
                    ok = false;
                    details{end+1} = sprintf('回读校验：工作表 %s 无法读取。', sn);
                    continue;
                end
                if isempty(raw)
                    continue;
                end
                headers = cell(1, size(raw, 2));
                for c = 1:size(raw, 2)
                    headers{c} = swb.Workbook.cellText(raw{1, c});
                end
                idx = swb.Schema.matchColumns(headers, swb.Schema.dictColumns(sn));
                if any(idx == 0)
                    ok = false;
                    details{end+1} = sprintf('回读校验：工作表 %s 表头与契约不一致。', sn);
                end
            end
        end

        function deleteQuiet(p)
            try
                if ~isempty(p) && isfile(p)
                    delete(p);
                end
            catch
            end
        end
    end
end
