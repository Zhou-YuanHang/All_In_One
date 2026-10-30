classdef Workbook
    %SWB.WORKBOOK Excel 工作簿能力探测与工作表读取（只读层）。
    %   统一 readcell 读取、表头归一化、缺失值处理，供校验/脚本生成/反向同步复用。
    %   不写文件、不弹窗。

    methods (Static)
        function info = detect(filePath)
            % 探测工作簿能力：是字典工作簿、端口工作簿，还是两者兼有/都不是
            info = struct('path', char(filePath), 'exists', false, 'sheets', {{}}, ...
                          'dictSheets', {{}}, 'hasDict', false, ...
                          'inputSheets', {{}}, 'outputSheets', {{}}, 'hasPorts', false, ...
                          'warnings', {{}});
            if isempty(filePath) || ~isfile(filePath)
                info.warnings{end+1} = sprintf('文件不存在: %s', char(filePath));
                return;
            end
            try
                sheets = cellstr(sheetnames(char(filePath)));
            catch ME
                info.warnings{end+1} = sprintf('无法读取工作表列表: %s', ME.message);
                return;
            end
            info.exists = true;
            info.sheets = sheets;

            dictSheets = {};
            for k = 1:numel(sheets)
                if swb.Schema.isDictSheet(sheets{k})
                    dictSheets{end+1} = swb.Schema.canonicalSheetName(sheets{k}); %#ok<AGROW>
                end
            end
            if ~isempty(dictSheets)
                [~, ia] = unique(dictSheets, 'stable');
                dictSheets = dictSheets(sort(ia));
            end
            info.dictSheets = dictSheets;
            importable = swb.Schema.importableSheetNames();
            info.hasDict = any(ismember(dictSheets, importable));

            [inS, outS] = swb.Workbook.matchPortSheets(sheets);
            info.inputSheets = inS;
            info.outputSheets = outS;
            info.hasPorts = ~isempty(inS) || ~isempty(outS);

            if ~info.hasDict && ~info.hasPorts
                info.warnings{end+1} = '该工作簿既没有数据字典表（Signal/Parameter/...），也没有端口表（Inputs/Outputs）。';
            end
        end

        function [inSheets, outSheets] = matchPortSheets(sheets)
            % 按别名匹配端口表（忽略大小写），返回命中的原始表名（保持工作簿顺序）
            inSheets = {};
            outSheets = {};
            for k = 1:numel(sheets)
                nm = strtrim(char(sheets{k}));
                if ~isempty(inSheets) && ~isempty(outSheets)
                    break;
                end
                if isempty(inSheets) && swb.Workbook.matchesAlias(nm, swb.Schema.PORT_INPUT_ALIASES)
                    inSheets = {nm};
                    continue;
                end
                if isempty(outSheets) && swb.Workbook.matchesAlias(nm, swb.Schema.PORT_OUTPUT_ALIASES)
                    outSheets = {nm};
                end
            end
        end

        function tf = matchesAlias(sheetName, aliases)
            tf = false;
            lowerName = lower(strtrim(char(sheetName)));
            for k = 1:numel(aliases)
                if strcmp(lowerName, lower(char(aliases{k})))
                    tf = true;
                    return;
                end
            end
        end

        function raw = readRaw(filePath, sheetName)
            % 原样读取（含表头行），缺失值保留为 missing
            if nargin < 2 || isempty(sheetName)
                raw = readcell(char(filePath));
            else
                raw = readcell(char(filePath), 'Sheet', char(sheetName));
            end
        end

        function t = readSheetTable(filePath, sheetName)
            % 读取一张表并做表头映射。返回：
            %   t.sheetName, t.headers(1xN cellstr), t.rows(MxN cell), t.rowNumbers(1xM)
            %   t.columnIndex(struct: 规范列名 -> 列号，0 表示缺失)
            %   t.spec(该表的列规范), t.headersRaw
            sheetName = char(sheetName);
            t = struct('sheetName', sheetName, 'headers', {{}}, 'headersRaw', {{}}, ...
                       'rows', {{}}, 'rowNumbers', [], 'columnIndex', struct(), 'spec', []);
            raw = swb.Workbook.readRaw(filePath, sheetName);
            if isempty(raw)
                return;
            end
            t.headersRaw = raw(1, :);
            headers = cell(1, size(raw, 2));
            for c = 1:size(raw, 2)
                headers{c} = swb.Workbook.cellText(raw{1, c});
            end
            t.headers = headers;
            if size(raw, 1) > 1
                t.rows = raw(2:end, :);
                t.rowNumbers = 2:size(raw, 1);
            else
                t.rows = cell(0, size(raw, 2));
                t.rowNumbers = [];
            end

            if swb.Schema.isDictSheet(sheetName)
                spec = swb.Schema.dictSheetSpec(sheetName);
                t.spec = spec;
                canonCols = spec.columns;
            else
                spec = struct('name', sheetName, 'columns', {{}}, 'required', [], ...
                              'keyColumns', [], 'importable', false);
                t.spec = spec;
                canonCols = {};
            end
            if ~isempty(canonCols)
                idx = swb.Schema.matchColumns(headers, canonCols);
                ci = struct();
                for k = 1:numel(canonCols)
                    field = matlab.lang.makeValidName(canonCols{k});
                    ci.(field) = idx(k);
                end
                t.columnIndex = ci;
            end
        end

        function sheets = listSheets(filePath)
            sheets = cellstr(sheetnames(char(filePath)));
        end

        function txt = cellText(v)
            % 单元格 -> char：missing/空 -> ''，数值 -> 去掉多余空格，逻辑 -> true/false
            if isempty(v)
                txt = '';
            elseif ismissing(v)
                txt = '';
            elseif isstring(v)
                if isscalar(v)
                    txt = char(v);
                else
                    txt = strjoin(cellstr(v), ',');
                end
            elseif ischar(v)
                txt = v;
            elseif islogical(v)
                if isscalar(v)
                    if v, txt = 'true'; else, txt = 'false'; end
                else
                    txt = mat2str(v);
                end
            elseif isnumeric(v)
                if isscalar(v)
                    if isnan(v)
                        txt = '';
                    elseif v == fix(v) && abs(v) < 1e15
                        txt = sprintf('%d', v);
                    else
                        txt = num2str(v, 17);
                    end
                else
                    txt = mat2str(v);
                end
            else
                try
                    txt = char(string(v));
                catch
                    txt = '';
                end
            end
            txt = strtrim(txt);
        end

        function tf = isBlank(v)
            if isempty(v)
                tf = true;
            elseif ismissing(v)
                tf = true;
            elseif ischar(v)
                tf = all(isspace(v));
            elseif isstring(v)
                tf = (strlength(strtrim(v)) == 0);
            else
                tf = false;
            end
        end

        function v = cellValue(rows, r, c)
            % 安全取单元格：越界或空返回 ''
            v = '';
            if isempty(rows) || r < 1 || r > size(rows, 1) || c < 1 || c > size(rows, 2)
                return;
            end
            v = rows{r, c};
        end
    end
end
