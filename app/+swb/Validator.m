classdef Validator
    %SWB.VALIDATOR 数据字典工作簿校验（结构/必填/重名/引用/标识符/存储类/DataType）。
    %   迁移旧 validateDataDictionary 的 4 类跨表检查（必填列、必填值、变量名重复、
    %   Bus 名称重复、Bus 引用、DataType=Bus:xxx 引用），并补齐旧实现完全没有的规则：
    %   Const/Enum 校验、Package 与 CustomStorageClass 合法性与组合、Object 列一致性、
    %   DataType 识别、枚举基类型与重复值、MATLAB/C 标识符。
    %
    %   issues = swb.Validator.run(workbookPath, selectedSheets)
    %     selectedSheets : cellstr，空表示校验工作簿中所有可导入表。
    %     返回 swb.Issue 数组（severity = error | warning | info），不抛错；
    %     只有工作簿路径非法（空/不存在/无法读取）才 error('swb:Validator:*')。

    properties (Constant, Access = private)
        INTEGER_TYPES = {'uint8', 'int8', 'uint16', 'int16', 'uint32', 'int32', 'uint64', 'int64'};
        BUILTIN_TYPES = {'double', 'single', 'uint8', 'int8', 'uint16', 'int16', ...
                         'uint32', 'int32', 'uint64', 'int64', 'boolean', 'string'};
        DATA_TYPE_SHEETS = {'Signal', 'Parameter', 'Const', 'BusElement'};
    end

    methods (Static)
        function issues = run(workbookPath, selectedSheets)
            issues = swb.Issue.empty();
            workbookPath = char(workbookPath);
            if isempty(strtrim(workbookPath)) || ~isfile(workbookPath)
                error('swb:Validator:missingWorkbook', '工作簿不存在: %s', workbookPath);
            end
            try
                fileSheets = cellstr(sheetnames(workbookPath));
            catch ME
                error('swb:Validator:unreadableWorkbook', '无法读取工作簿工作表列表: %s', ME.message);
            end

            importable = swb.Schema.importableSheetNames();
            present = {};
            for k = 1:numel(importable)
                if any(strcmpi(fileSheets, importable{k}))
                    present{end+1} = importable{k}; %#ok<AGROW>
                end
            end

            if nargin < 2 || isempty(selectedSheets)
                selected = present;
                if isempty(selected)
                    issues(end+1) = swb.Issue.make('Workbook', NaN, 'A', 'error', ...
                        '工作簿中没有任何可导入的数据字典表（Signal/Parameter/Const/Enum/Bus/BusElement）。');
                    return;
                end
            else
                selected = {};
                requested = swb.Validator.toCellstr(selectedSheets);
                for k = 1:numel(requested)
                    nm = strtrim(requested{k});
                    if isempty(nm)
                        continue;
                    end
                    if ~swb.Schema.isDictSheet(nm)
                        issues(end+1) = swb.Issue.make(nm, NaN, 'A', 'warning', ... %#ok<AGROW>
                            sprintf('工作表 "%s" 不是数据字典表，已忽略。', nm));
                        continue;
                    end
                    can = swb.Schema.canonicalSheetName(nm);
                    spec = swb.Schema.dictSheetSpec(can);
                    if ~spec.importable
                        issues(end+1) = swb.Issue.make(can, NaN, 'A', 'info', ... %#ok<AGROW>
                            sprintf('工作表 "%s" 不参与导入，已忽略。', can));
                        continue;
                    end
                    if ~any(strcmp(fileSheets, can))
                        issues(end+1) = swb.Issue.make(can, NaN, 'A', 'error', ... %#ok<AGROW>
                            sprintf('工作表 "%s" 在工作簿中不存在。', can));
                        continue;
                    end
                    if ~any(strcmp(selected, can))
                        selected{end+1} = can; %#ok<AGROW>
                    end
                end
                if isempty(selected)
                    issues(end+1) = swb.Issue.make('Workbook', NaN, 'A', 'error', ...
                        '没有可校验的数据字典表。');
                    return;
                end
            end

            % 读取工作簿中所有存在的可导入表：Bus 即使未选中也要读，用于引用检查。
            tables = struct();
            for k = 1:numel(present)
                tables.(present{k}) = swb.Validator.readTableInfo(workbookPath, fileSheets, present{k});
            end

            % Bus 定义是引用解析的必需品，总是纳入结构检查
            checkSet = selected;
            if isfield(tables, 'Bus') && tables.Bus.exists && ~any(strcmp(checkSet, 'Bus'))
                checkSet{end+1} = 'Bus';
            end

            % 1) 结构：必填列
            for k = 1:numel(checkSet)
                t = tables.(checkSet{k});
                if ~t.readOk
                    issues(end+1) = swb.Issue.make(t.name, NaN, 'A', 'error', ... %#ok<AGROW>
                        sprintf('工作表读取失败：%s', t.readError));
                    continue;
                end
                spec = t.spec;
                for c = 1:numel(spec.required)
                    cname = spec.columns{spec.required(c)};
                    if swb.Validator.col(t, cname) == 0
                        issues(end+1) = swb.Issue.make(t.name, NaN, cname, 'error', ... %#ok<AGROW>
                            sprintf('缺少必需列 "%s"。', cname));
                    end
                end
            end

            % 2) 必填单元格非空
            for k = 1:numel(selected)
                t = tables.(selected{k});
                if t.readOk
                    issues = swb.Validator.checkRequiredCells(issues, t);
                end
            end

            % 3) 重名（大小写不敏感）
            issues = swb.Validator.checkDuplicates(issues, tables, selected);

            % 4) 标识符
            issues = swb.Validator.checkIdentifiers(issues, tables, selected);

            % 5) Package / CustomStorageClass
            issues = swb.Validator.checkStorageClasses(issues, tables, selected);

            % 6) Object 列一致性
            issues = swb.Validator.checkObjectColumn(issues, tables, selected);

            % 7) DataType 识别与 Bus 类型引用
            issues = swb.Validator.checkDataTypes(issues, tables, selected);

            % 8) Enum 专项
            issues = swb.Validator.checkEnums(issues, tables, selected);

            % 9) BusElement / Bus 引用
            issues = swb.Validator.checkBusReferences(issues, tables, selected);

            % 10) 选择组合提示
            issues = swb.Validator.checkSelectionWarnings(issues, tables, selected);

            % 11) 单元格级问题统一用 Excel 列字母定位（缺列问题保留列名）
            issues = swb.Validator.normalizeColumns(issues, tables);
            issues = issues(:)';
        end
    end

    methods (Static, Access = private)
        function c = toCellstr(v)
            if ischar(v)
                c = {v};
            elseif isstring(v)
                c = cellstr(v);
            elseif iscell(v)
                c = cellfun(@(x) char(string(x)), v, 'UniformOutput', false);
            else
                c = {};
            end
        end

        function t = readTableInfo(workbookPath, fileSheets, sheetName)
            t = struct('name', sheetName, 'exists', false, 'readOk', false, 'readError', '', ...
                       'headers', {{}}, 'rows', {{}}, 'rowNumbers', [], 'cols', struct(), 'spec', []);
            hit = find(strcmpi(fileSheets, sheetName), 1);
            if isempty(hit)
                return;
            end
            t.exists = true;
            try
                rt = swb.Workbook.readSheetTable(workbookPath, fileSheets{hit});
                t.readOk = true;
                t.headers = rt.headers;
                t.rows = rt.rows;
                t.rowNumbers = rt.rowNumbers;
                t.cols = rt.columnIndex;
                t.spec = rt.spec;
            catch ME
                t.readError = ME.message;
            end
        end

        function idx = col(t, name)
            idx = 0;
            if isstruct(t.cols) && isfield(t.cols, name)
                idx = double(t.cols.(name));
            end
        end

        function n = rowCount(t)
            n = size(t.rows, 1);
        end

        function txt = cellAt(t, r, name)
            txt = '';
            idx = swb.Validator.col(t, name);
            if idx == 0 || r < 1 || r > swb.Validator.rowCount(t)
                return;
            end
            txt = swb.Workbook.cellText(swb.Workbook.cellValue(t.rows, r, idx));
        end

        function tf = isBlank(t, r, name)
            idx = swb.Validator.col(t, name);
            if idx == 0 || r < 1 || r > swb.Validator.rowCount(t)
                tf = true;
                return;
            end
            tf = swb.Workbook.isBlank(swb.Workbook.cellValue(t.rows, r, idx));
        end

        function issues = checkRequiredCells(issues, t)
            if ~t.readOk
                return;
            end
            spec = t.spec;
            for k = 1:numel(spec.required)
                cname = spec.columns{spec.required(k)};
                if swb.Validator.col(t, cname) == 0
                    continue;
                end
                for r = 1:swb.Validator.rowCount(t)
                    if swb.Validator.isBlank(t, r, cname)
                        issues(end+1) = swb.Issue.make(t.name, t.rowNumbers(r), cname, 'error', ... %#ok<AGROW>
                            sprintf('必填列 %s 的值为空。', cname));
                    end
                end
            end
        end

        function issues = checkDuplicates(issues, tables, selected)
            keys = {}; sheets = {}; rows = []; cols = {}; disps = {};
            for k = 1:numel(selected)
                name = selected{k};
                if ~any(strcmp(name, {'Signal', 'Parameter'}))
                    continue;
                end
                t = tables.(name);
                if ~t.readOk || swb.Validator.col(t, 'VariableName') == 0
                    continue;
                end
                for r = 1:swb.Validator.rowCount(t)
                    txt = swb.Validator.cellAt(t, r, 'VariableName');
                    if isempty(txt)
                        continue;
                    end
                    keys{end+1} = lower(txt); %#ok<AGROW>
                    sheets{end+1} = t.name; %#ok<AGROW>
                    rows(end+1) = t.rowNumbers(r); %#ok<AGROW>
                    cols{end+1} = 'VariableName'; %#ok<AGROW>
                    disps{end+1} = txt; %#ok<AGROW>
                end
            end
            issues = swb.Validator.reportDuplicates(issues, keys, sheets, rows, cols, disps, '变量名');

            % Bus
            keys = {}; sheets = {}; rows = []; cols = {}; disps = {};
            if isfield(tables, 'Bus') && tables.Bus.readOk && swb.Validator.col(tables.Bus, 'BusName') > 0
                t = tables.Bus;
                for r = 1:swb.Validator.rowCount(t)
                    txt = swb.Validator.cellAt(t, r, 'BusName');
                    if isempty(txt)
                        continue;
                    end
                    keys{end+1} = lower(txt); %#ok<AGROW>
                    sheets{end+1} = t.name; %#ok<AGROW>
                    rows(end+1) = t.rowNumbers(r); %#ok<AGROW>
                    cols{end+1} = 'BusName'; %#ok<AGROW>
                    disps{end+1} = txt; %#ok<AGROW>
                end
            end
            issues = swb.Validator.reportDuplicates(issues, keys, sheets, rows, cols, disps, 'Bus 名称');

            % Const
            issues = swb.Validator.checkKeyDuplicates(issues, tables, selected, 'Const', 'Name', 'Const 名称');

            % BusElement (BusName, ElementName)
            issues = swb.Validator.checkPairDuplicates(issues, tables, selected, 'BusElement', ...
                {'BusName', 'ElementName'}, 'BusElement 元素');

            % Enum (EnumName, EnumNumbers)
            issues = swb.Validator.checkPairDuplicates(issues, tables, selected, 'Enum', ...
                {'EnumName', 'EnumNumbers'}, '枚举成员');
        end

        function issues = checkKeyDuplicates(issues, tables, selected, sheetName, colName, label)
            if ~any(strcmp(selected, sheetName)) || ~isfield(tables, sheetName)
                return;
            end
            t = tables.(sheetName);
            if ~t.readOk || swb.Validator.col(t, colName) == 0
                return;
            end
            keys = {}; sheets = {}; rows = []; cols = {}; disps = {};
            for r = 1:swb.Validator.rowCount(t)
                txt = swb.Validator.cellAt(t, r, colName);
                if isempty(txt)
                    continue;
                end
                keys{end+1} = lower(txt); %#ok<AGROW>
                sheets{end+1} = t.name; %#ok<AGROW>
                rows(end+1) = t.rowNumbers(r); %#ok<AGROW>
                cols{end+1} = colName; %#ok<AGROW>
                disps{end+1} = txt; %#ok<AGROW>
            end
            issues = swb.Validator.reportDuplicates(issues, keys, sheets, rows, cols, disps, label);
        end

        function issues = checkPairDuplicates(issues, tables, selected, sheetName, colNames, label)
            if ~any(strcmp(selected, sheetName)) || ~isfield(tables, sheetName)
                return;
            end
            t = tables.(sheetName);
            if ~t.readOk
                return;
            end
            for k = 1:numel(colNames)
                if swb.Validator.col(t, colNames{k}) == 0
                    return;
                end
            end
            keys = {}; sheets = {}; rows = []; cols = {}; disps = {};
            for r = 1:swb.Validator.rowCount(t)
                k1 = swb.Validator.cellAt(t, r, colNames{1});
                k2 = swb.Validator.cellAt(t, r, colNames{2});
                if isempty(k1) && isempty(k2)
                    continue;
                end
                keys{end+1} = [lower(k1) '|' lower(k2)]; %#ok<AGROW>
                sheets{end+1} = t.name; %#ok<AGROW>
                rows(end+1) = t.rowNumbers(r); %#ok<AGROW>
                cols{end+1} = colNames{1}; %#ok<AGROW>
                disps{end+1} = sprintf('%s / %s', k1, k2); %#ok<AGROW>
            end
            issues = swb.Validator.reportDuplicates(issues, keys, sheets, rows, cols, disps, label);
        end

        function issues = reportDuplicates(issues, keys, sheets, rows, cols, disps, label)
            if isempty(keys)
                return;
            end
            map = containers.Map();
            groupOf = zeros(1, numel(keys));
            counts = [];
            for i = 1:numel(keys)
                k = keys{i};
                if isKey(map, k)
                    g = map(k);
                else
                    counts(end+1) = 0; %#ok<AGROW>
                    g = numel(counts);
                    map(k) = g;
                end
                counts(g) = counts(g) + 1;
                groupOf(i) = g;
            end
            for g = 1:numel(counts)
                if counts(g) < 2
                    continue;
                end
                idx = find(groupOf == g);
                locs = cell(1, numel(idx));
                for j = 1:numel(idx)
                    locs{j} = sprintf('%s 第 %d 行', sheets{idx(j)}, rows(idx(j)));
                end
                issues(end+1) = swb.Issue.make(sheets{idx(1)}, rows(idx(1)), cols{idx(1)}, 'error', ... %#ok<AGROW>
                    sprintf('%s "%s" 重复出现：%s。', label, disps{idx(1)}, strjoin(locs, '；')));
            end
        end

        function issues = checkIdentifiers(issues, tables, selected)
            targets = struct('sheet', {'Signal', 'Parameter', 'Bus', 'BusElement', 'Const'}, ...
                             'column', {'VariableName', 'VariableName', 'BusName', 'ElementName', 'Name'}, ...
                             'label', {'变量名', '变量名', 'Bus 名称', 'BusElement 元素名', 'Const 名称'});
            for k = 1:numel(selected)
                name = selected{k};
                hit = find(strcmp({targets.sheet}, name), 1);
                if isempty(hit)
                    continue;
                end
                t = tables.(name);
                if ~t.readOk || swb.Validator.col(t, targets(hit).column) == 0
                    continue;
                end
                for r = 1:swb.Validator.rowCount(t)
                    txt = swb.Validator.cellAt(t, r, targets(hit).column);
                    if isempty(txt)
                        continue;
                    end
                    if ~isvarname(txt)
                        issues(end+1) = swb.Issue.make(t.name, t.rowNumbers(r), targets(hit).column, 'error', ... %#ok<AGROW>
                            sprintf('%s "%s" 不是合法的 MATLAB 标识符。', targets(hit).label, txt));
                    end
                end
            end

            % Enum：EnumNumbers 必须为 C 标识符；EnumName 会成为 classdef 名称，给出警告
            if any(strcmp(selected, 'Enum')) && isfield(tables, 'Enum')
                t = tables.Enum;
                if t.readOk
                    for r = 1:swb.Validator.rowCount(t)
                        label = swb.Validator.cellAt(t, r, 'EnumNumbers');
                        if ~isempty(label) && isempty(regexp(label, '^[A-Za-z_][A-Za-z0-9_]*$', 'once'))
                            issues(end+1) = swb.Issue.make(t.name, t.rowNumbers(r), 'EnumNumbers', 'error', ... %#ok<AGROW>
                                sprintf('EnumNumbers "%s" 不是合法的 C 标识符。', label));
                        end
                        en = swb.Validator.cellAt(t, r, 'EnumName');
                        if ~isempty(en) && ~isvarname(en)
                            issues(end+1) = swb.Issue.make(t.name, t.rowNumbers(r), 'EnumName', 'warning', ... %#ok<AGROW>
                                sprintf('枚举名 "%s" 不是合法的 MATLAB 标识符（classdef 名称将无效）。', en));
                        end
                    end
                end
            end
        end

        function issues = checkStorageClasses(issues, tables, selected)
            pkgs = swb.Schema.packageNames();
            classes = swb.Schema.allStorageClasses();
            for k = 1:numel(selected)
                name = selected{k};
                if ~any(strcmp(name, {'Signal', 'Parameter', 'Const'}))
                    continue;
                end
                t = tables.(name);
                if ~t.readOk
                    continue;
                end
                for r = 1:swb.Validator.rowCount(t)
                    pkg = swb.Validator.cellAt(t, r, 'Package');
                    if ~isempty(pkg) && ~any(strcmpi(pkg, pkgs))
                        issues(end+1) = swb.Issue.make(t.name, t.rowNumbers(r), 'Package', 'error', ... %#ok<AGROW>
                            sprintf('Package "%s" 不在允许列表（%s）。', pkg, strjoin(pkgs, ', ')));
                    end
                    sc = swb.Validator.cellAt(t, r, 'CustomStorageClass');
                    if ~isempty(sc) && ~any(strcmpi(sc, classes))
                        issues(end+1) = swb.Issue.make(t.name, t.rowNumbers(r), 'CustomStorageClass', 'error', ... %#ok<AGROW>
                            sprintf('CustomStorageClass "%s" 不在已知存储类列表（内置 5 个 + 自定义 16 个）。', sc));
                    end
                    % Const 表按设计使用 Package=Simulink + Define 等自定义存储类，不报错
                    if any(strcmp(name, {'Signal', 'Parameter'})) && strcmpi(pkg, 'Simulink') && ...
                            ~isempty(sc) && swb.Schema.isCustomStorageClass(sc)
                        issues(end+1) = swb.Issue.make(t.name, t.rowNumbers(r), 'CustomStorageClass', 'error', ... %#ok<AGROW>
                            sprintf('Package=Simulink 时不能使用自定义存储类 "%s"（旧实现会导致整段脚本执行中断）。', sc));
                    end
                end
            end
        end

        function issues = checkObjectColumn(issues, tables, selected)
            expects = struct('sheet', {'Signal', 'Parameter'}, 'value', {'Signal', 'Parameter'});
            for k = 1:numel(selected)
                name = selected{k};
                hit = find(strcmp({expects.sheet}, name), 1);
                if isempty(hit)
                    continue;
                end
                t = tables.(name);
                if ~t.readOk || swb.Validator.col(t, 'Object') == 0
                    continue;
                end
                for r = 1:swb.Validator.rowCount(t)
                    obj = swb.Validator.cellAt(t, r, 'Object');
                    if ~isempty(obj) && ~strcmpi(obj, expects(hit).value)
                        issues(end+1) = swb.Issue.make(t.name, t.rowNumbers(r), 'Object', 'warning', ... %#ok<AGROW>
                            sprintf('Object 列应为 "%s"，实际为 "%s"（写入脚本时以表名为准）。', ...
                                expects(hit).value, obj));
                    end
                end
            end
        end

        function issues = checkDataTypes(issues, tables, selected)
            enumTypes = swb.Validator.enumTypeNames(tables);
            for k = 1:numel(selected)
                name = selected{k};
                if ~any(strcmp(name, swb.Validator.DATA_TYPE_SHEETS))
                    continue;
                end
                t = tables.(name);
                if ~t.readOk || swb.Validator.col(t, 'DataType') == 0
                    continue;
                end
                for r = 1:swb.Validator.rowCount(t)
                    dt = swb.Validator.cellAt(t, r, 'DataType');
                    if isempty(dt)
                        continue;
                    end
                    if ~swb.Validator.isKnownDataType(dt, enumTypes)
                        issues(end+1) = swb.Issue.make(t.name, t.rowNumbers(r), 'DataType', 'warning', ... %#ok<AGROW>
                            sprintf('无法识别的 DataType "%s"（将按原样写入，可能导致脚本执行失败）。', dt));
                    end
                end
            end
        end

        function names = enumTypeNames(tables)
            names = {};
            if ~isfield(tables, 'Enum') || ~tables.Enum.readOk
                return;
            end
            t = tables.Enum;
            if swb.Validator.col(t, 'EnumName') == 0
                return;
            end
            for r = 1:swb.Validator.rowCount(t)
                nm = swb.Validator.cellAt(t, r, 'EnumName');
                if ~isempty(nm) && ~any(strcmpi(names, nm))
                    names{end+1} = nm; %#ok<AGROW>
                end
            end
        end

        function tf = isKnownDataType(dt, enumTypes)
            tf = any(strcmpi(dt, swb.Validator.BUILTIN_TYPES)) || any(strcmpi(dt, enumTypes));
            if tf
                return;
            end
            patterns = {'^bus\s*:\s*.+$', '^fixdt\s*\(.*\)$', '^inherit\s*:.*$', '^enum\s*:\s*.+$'};
            for k = 1:numel(patterns)
                if ~isempty(regexpi(dt, patterns{k}, 'once'))
                    tf = true;
                    return;
                end
            end
        end

        function issues = checkEnums(issues, tables, selected)
            if ~any(strcmp(selected, 'Enum')) || ~isfield(tables, 'Enum')
                return;
            end
            t = tables.Enum;
            if ~t.readOk || swb.Validator.col(t, 'EnumName') == 0
                return;
            end
            hasValue = swb.Validator.col(t, 'Value') > 0;
            hasDT = swb.Validator.col(t, 'DataType') > 0;

            % 基类型必须是整数类型
            if hasDT
                checked = containers.Map();
                for r = 1:swb.Validator.rowCount(t)
                    dt = swb.Validator.cellAt(t, r, 'DataType');
                    if isempty(dt) || isKey(checked, lower(dt))
                        continue;
                    end
                    checked(lower(dt)) = true;
                    if ~any(strcmpi(dt, swb.Validator.INTEGER_TYPES))
                        issues(end+1) = swb.Issue.make(t.name, t.rowNumbers(r), 'DataType', 'warning', ... %#ok<AGROW>
                            sprintf('Enum 的 DataType "%s" 不是整数类型，枚举基类必须为整数类型。', dt));
                    end
                end
            end

            % 同一 EnumName 的 Value 必须唯一
            if hasValue
                keys = {}; sheets = {}; rows = []; cols = {}; disps = {};
                for r = 1:swb.Validator.rowCount(t)
                    en = swb.Validator.cellAt(t, r, 'EnumName');
                    if isempty(en)
                        continue;
                    end
                    val = swb.Validator.cellAt(t, r, 'Value');
                    n = str2double(val);
                    if ~isnan(n)
                        vs = sprintf('%.17g', n);
                    else
                        vs = lower(val);
                    end
                    keys{end+1} = [lower(en) '|' vs]; %#ok<AGROW>
                    sheets{end+1} = t.name; %#ok<AGROW>
                    rows(end+1) = t.rowNumbers(r); %#ok<AGROW>
                    cols{end+1} = 'Value'; %#ok<AGROW>
                    disps{end+1} = sprintf('%s = %s', en, val); %#ok<AGROW>
                end
                issues = swb.Validator.reportDuplicates(issues, keys, sheets, rows, cols, disps, '枚举值');
            end
        end

        function issues = checkBusReferences(issues, tables, selected)
            % Bus 表定义（即使未选中也读取）
            defined = {};
            displayNames = {};
            busReadable = false;
            if isfield(tables, 'Bus') && tables.Bus.readOk && swb.Validator.col(tables.Bus, 'BusName') > 0
                busReadable = true;
                tb = tables.Bus;
                for r = 1:swb.Validator.rowCount(tb)
                    nm = swb.Validator.cellAt(tb, r, 'BusName');
                    if isempty(nm)
                        continue;
                    end
                    if ~any(strcmpi(defined, nm))
                        defined{end+1} = nm; %#ok<AGROW>
                        displayNames{end+1} = nm; %#ok<AGROW>
                    end
                end
            end

            % BusElement.BusName 引用
            if any(strcmp(selected, 'BusElement')) && isfield(tables, 'BusElement')
                t = tables.BusElement;
                if t.readOk && swb.Validator.col(t, 'BusName') > 0
                    for r = 1:swb.Validator.rowCount(t)
                        nm = swb.Validator.cellAt(t, r, 'BusName');
                        if isempty(nm)
                            continue;
                        end
                        if ~busReadable || ~any(strcmpi(defined, nm))
                            issues(end+1) = swb.Issue.make(t.name, t.rowNumbers(r), 'BusName', 'error', ... %#ok<AGROW>
                                sprintf('BusElement 引用了 Bus 表中未定义的 Bus "%s"。', nm));
                        end
                    end
                end
            end

            % DataType = 'Bus: xxx' 引用
            for k = 1:numel(selected)
                name = selected{k};
                if ~any(strcmp(name, swb.Validator.DATA_TYPE_SHEETS)) || ~isfield(tables, name)
                    continue;
                end
                t = tables.(name);
                if ~t.readOk || swb.Validator.col(t, 'DataType') == 0
                    continue;
                end
                for r = 1:swb.Validator.rowCount(t)
                    dt = swb.Validator.cellAt(t, r, 'DataType');
                    tk = regexpi(dt, '^\s*bus\s*:\s*(.+?)\s*$', 'tokens', 'once');
                    if isempty(tk)
                        continue;
                    end
                    busName = strtrim(tk{1});
                    if ~busReadable || ~any(strcmpi(defined, busName))
                        issues(end+1) = swb.Issue.make(t.name, t.rowNumbers(r), 'DataType', 'error', ... %#ok<AGROW>
                            sprintf('DataType 引用了 Bus 表中未定义的 Bus "%s"。', busName));
                    end
                end
            end
        end

        function issues = normalizeColumns(issues, tables)
            % 单元格级 issue 的 column 原本是规范列名，转成 Excel 列字母便于定位；
            % 缺少列（row 为 NaN）的问题保留列名文字（任务要求）。
            for k = 1:numel(issues)
                if isnan(issues(k).row) || isempty(issues(k).column)
                    continue;
                end
                c = issues(k).column;
                if numel(c) == 1 && c >= 'A' && c <= 'Z'
                    continue;
                end
                if ~isfield(tables, issues(k).sheet)
                    continue;
                end
                idx = swb.Validator.col(tables.(issues(k).sheet), c);
                if idx > 0
                    issues(k).column = swb.Validator.indexToLetter(idx);
                end
            end
        end

        function s = indexToLetter(idx)
            s = '';
            n = double(idx);
            while n > 0
                r = mod(n - 1, 26);
                s = [char(65 + r) s]; %#ok<AGROW>
                n = floor((n - 1) / 26);
            end
        end

        function issues = checkSelectionWarnings(issues, tables, selected)
            hasBus = any(strcmp(selected, 'Bus'));
            hasBE = any(strcmp(selected, 'BusElement'));
            if hasBE && ~hasBus
                issues(end+1) = swb.Issue.make('BusElement', NaN, 'A', 'warning', ...
                    '已选择 BusElement 但未选择 Bus；Bus 对象定义不会随脚本导入（可能不完整）。');
            elseif hasBus && ~hasBE && isfield(tables, 'BusElement') && tables.BusElement.exists
                issues(end+1) = swb.Issue.make('Bus', NaN, 'A', 'warning', ...
                    '已选择 Bus 但未选择 BusElement；Bus 的元素不会被生成（Bus 可能不完整）。');
            end
        end
    end
end
