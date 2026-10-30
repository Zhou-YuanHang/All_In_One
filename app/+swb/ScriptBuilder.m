classdef ScriptBuilder
    %SWB.SCRIPTBUILDER Excel 数据字典 -> Simulink 对象 M 脚本（无 UI）。
    %   行为对齐旧 src/AutoCreateSldd/Excel2Workspace.m 的 5 参数模式：
    %     - 输出对象赋值文本（含 StorageClass/自定义存储类/CoderInfo.CustomAttributes）
    %     - BusElement 使用 saveVarsTmp{1} 临时变量写法
    %     - Enum 生成独立的 classdef .m 文件
    %     - Parameter 先 Dimensions 后 Value
    %   改进（修复旧实现会让整段脚本中断的问题）：
    %     - CustomStorageClass 赋值按 Package 预判：Package=Simulink 的自定义存储类
    %       不再生成必崩的行；其余自定义存储类赋值也用 try/catch 包裹。
    %
    %   result = swb.ScriptBuilder.build(workbookPath, selection, outFile)
    %     workbookPath : Excel 路径
    %     selection    : cellstr 表名；空 = 工作簿中所有可导入表（按工作簿顺序）
    %     outFile      : 可选；为空则只返回文本，不写任何文件
    %   result 字段：
    %     ok, text(char), objects(struct array: name,type,constructor,sheet),
    %     busElements(struct array: bus,name,sheet), enumFiles(cellstr),
    %     enumTexts(struct array: name,path,content), writtenFile(char), warnings(cellstr)

    properties (Constant, Access = private)
        DEFAULT_SC = {'Auto', 'SimulinkGlobal', 'ExportedGlobal', ...
                      'ImportedExtern', 'ImportedExternPointer'};
        IMPORTABLE = {'Signal', 'Parameter', 'Const', 'Enum', 'Bus', 'BusElement'};
    end

    methods (Static)
        function result = build(workbookPath, selection, outFile)
            if nargin < 3 || isempty(outFile)
                outFile = '';
            else
                outFile = char(outFile);
            end
            workbookPath = char(workbookPath);
            if isempty(strtrim(workbookPath)) || ~isfile(workbookPath)
                error('swb:ScriptBuilder:missingWorkbook', '工作簿不存在: %s', workbookPath);
            end
            try
                fileSheets = cellstr(sheetnames(workbookPath));
            catch ME
                error('swb:ScriptBuilder:unreadableWorkbook', '无法读取工作簿工作表列表: %s', ME.message);
            end

            result = struct('ok', false, 'text', '', ...
                'objects', struct('name', {}, 'type', {}, 'constructor', {}, 'sheet', {}), ...
                'busElements', struct('bus', {}, 'name', {}, 'sheet', {}), ...
                'enumFiles', {{}}, ...
                'enumTexts', struct('name', {}, 'path', {}, 'content', {}), ...
                'writtenFile', '', 'warnings', {{}});

            importable = swb.ScriptBuilder.IMPORTABLE;
            present = {};
            for k = 1:numel(importable)
                if any(strcmpi(fileSheets, importable{k}))
                    present{end+1} = importable{k}; %#ok<AGROW>
                end
            end

            if nargin < 2 || isempty(selection)
                selected = present;
            else
                requested = swb.ScriptBuilder.toCellstr(selection);
                selected = {};
                for k = 1:numel(requested)
                    nm = strtrim(requested{k});
                    if isempty(nm)
                        continue;
                    end
                    can = swb.Schema.canonicalSheetName(nm);
                    if ~any(strcmp(importable, can))
                        result.warnings{end+1} = sprintf('工作表 "%s" 不参与对象生成，已跳过。', nm); %#ok<AGROW>
                        continue;
                    end
                    if ~any(strcmp(fileSheets, can))
                        result.warnings{end+1} = sprintf('工作表 "%s" 在工作簿中不存在，已跳过。', nm); %#ok<AGROW>
                        continue;
                    end
                    if ~any(strcmp(selected, can))
                        selected{end+1} = can; %#ok<AGROW>
                    end
                end
            end

            % 读取选中表
            tables = struct();
            for k = 1:numel(selected)
                tables.(selected{k}) = swb.ScriptBuilder.readTable(workbookPath, fileSheets, selected{k});
            end

            [~, xlsName, xlsExt] = fileparts(workbookPath);
            lines = swb.ScriptBuilder.headerLines([xlsName xlsExt]);
            objects = swb.ScriptBuilder.emptyObjects();
            busElements = swb.ScriptBuilder.emptyBusElements();
            enumTexts = struct('name', {}, 'path', {}, 'content', {});

            % Bus 必须最先处理（BusElement 依赖它）
            busDone = false;
            if any(strcmp(selected, 'Bus'))
                t = tables.Bus;
                if t.readOk
                    [sec, objs] = swb.ScriptBuilder.busSection(t);
                    lines = [lines, sec]; %#ok<AGROW>
                    objects = [objects, objs]; %#ok<AGROW>
                end
                busDone = true;
            end

            for k = 1:numel(selected)
                name = selected{k};
                t = tables.(name);
                if ~t.readOk
                    result.warnings{end+1} = sprintf('工作表 %s 读取失败，已跳过：%s', name, t.readError); %#ok<AGROW>
                    continue;
                end
                switch name
                    case 'Bus'
                        continue;   % 已处理
                    case 'Signal'
                        [sec, objs] = swb.ScriptBuilder.signalSection(t);
                    case 'Parameter'
                        [sec, objs] = swb.ScriptBuilder.parameterSection(t);
                    case 'Const'
                        [sec, objs] = swb.ScriptBuilder.constSection(t);
                    case 'BusElement'
                        [sec, ~, bes] = swb.ScriptBuilder.busElementSection(t);
                        busElements = [busElements, bes]; %#ok<AGROW>
                        objs = swb.ScriptBuilder.emptyObjects();
                    case 'Enum'
                        enumTexts = swb.ScriptBuilder.enumSection(t);
                        continue;
                    otherwise
                        continue;
                end
                lines = [lines, sec]; %#ok<AGROW>
                objects = [objects, objs]; %#ok<AGROW>
            end

            text = [strjoin(lines, newline), newline];
            result.text = text;
            result.objects = objects;
            result.busElements = busElements;
            result.enumTexts = enumTexts;
            result.ok = true;

            if isempty(outFile)
                return;
            end

            [outDir, ~, ~] = fileparts(outFile);
            if isempty(outDir)
                outDir = pwd;
            end
            if ~isfolder(outDir)
                mkdir(outDir);
            end
            fid = fopen(outFile, 'w', 'n', 'UTF-8');
            if fid < 0
                error('swb:ScriptBuilder:writeFailed', '无法创建输出文件: %s', outFile);
            end
            fwrite(fid, text, 'char');
            fclose(fid);
            result.writtenFile = outFile;

            files = {};
            for e = 1:numel(enumTexts)
                p = fullfile(outDir, [enumTexts(e).name '.m']);
                efid = fopen(p, 'w', 'n', 'UTF-8');
                if efid < 0
                    result.warnings{end+1} = sprintf('无法创建枚举文件: %s', p); %#ok<AGROW>
                    continue;
                end
                fwrite(efid, enumTexts(e).content, 'char');
                fclose(efid);
                enumTexts(e).path = p;
                files{end+1} = p; %#ok<AGROW>
            end
            result.enumTexts = enumTexts;
            result.enumFiles = files;
        end
    end

    methods (Static, Access = private)
        %% ---------- 基础工具 ----------
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

        function t = readTable(workbookPath, fileSheets, sheetName)
            t = struct('name', sheetName, 'readOk', false, 'readError', '', ...
                       'rows', {{}}, 'rowNumbers', [], 'cols', struct());
            hit = find(strcmpi(fileSheets, sheetName), 1);
            if isempty(hit)
                return;
            end
            try
                rt = swb.Workbook.readSheetTable(workbookPath, fileSheets{hit});
                t.readOk = true;
                t.rows = rt.rows;
                t.rowNumbers = rt.rowNumbers;
                t.cols = rt.columnIndex;
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

        function s = valueText(v)
            s = '';
            if isempty(v)
                return;
            end
            if isnumeric(v) || islogical(v)
                if all(isnan(double(v(:))))
                    return;
                end
                if ~isscalar(v)
                    s = mat2str(v);
                elseif islogical(v)
                    if v
                        s = 'true';
                    else
                        s = 'false';
                    end
                else
                    s = char(string(v));
                end
            elseif isstring(v)
                if ~isscalar(v) || ismissing(v)
                    return;
                end
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

        function s = textAt(t, r, name)
            s = '';
            idx = swb.ScriptBuilder.col(t, name);
            if idx == 0 || r < 1 || r > swb.ScriptBuilder.rowCount(t)
                return;
            end
            s = swb.ScriptBuilder.valueText(swb.Workbook.cellValue(t.rows, r, idx));
        end

        function e = fmtVal(v)
            % 与旧实现 fmtVal 等价：数值原样、[..] 原样、TRUE/FALSE 转逻辑、
            % NONE/空 -> []，其余加单引号（内部单引号翻倍）
            s = swb.ScriptBuilder.valueText(v);
            if isempty(s)
                e = '[]';
                return;
            end
            if strcmpi(s, 'NONE')
                e = '[]';
                return;
            end
            n = str2double(s);
            if ~isnan(n) && ~isempty(s)
                e = s;
                return;
            end
            if startsWith(s, '[') && endsWith(s, ']')
                e = s;
                return;
            end
            if strcmpi(s, 'TRUE')
                e = 'true';
                return;
            end
            if strcmpi(s, 'FALSE')
                e = 'false';
                return;
            end
            e = ['''' strrep(s, '''', '''''') ''''];
        end

        function w = quotedProp(name, prop, s)
            w = sprintf('%s.%s = ''%s'';', name, prop, s);
        end

        function lines = scalarProp(lines, name, t, r, field)
            s = swb.ScriptBuilder.textAt(t, r, field);
            if isempty(s)
                return;
            end
            e = swb.ScriptBuilder.fmtVal(s);
            if strcmp(e, '[]')
                return;
            end
            lines{end+1} = sprintf('%s.%s = %s;', name, field, e);
        end

        function lines = valueProp(lines, name, t, r, field, prop)
            if nargin < 6
                prop = field;
            end
            s = swb.ScriptBuilder.textAt(t, r, field);
            if isempty(s)
                return;
            end
            lines{end+1} = sprintf('%s.%s = %s;', name, prop, swb.ScriptBuilder.fmtVal(s));
        end

        function lines = strProp(lines, name, t, r, field, prop)
            if nargin < 6
                prop = field;
            end
            s = swb.ScriptBuilder.textAt(t, r, field);
            if isempty(s)
                return;
            end
            lines{end+1} = sprintf('%s.%s = ''%s'';', name, prop, s);
        end

        function l = scLines(name, sc, wrap)
            % wrap = true 时给自定义存储类赋值加 try/catch：
            % 旧实现里 Package=Simulink + 自定义存储类 会让整段 evalin 中断，
            % 这里按 Package 预判并把风险行包裹起来（其余组合保持旧文本格式）。
            if nargin < 3
                wrap = false;
            end
            if any(strcmpi(sc, swb.ScriptBuilder.DEFAULT_SC))
                l = {sprintf('%s.CoderInfo.StorageClass = ''%s'';', name, sc)};
            elseif wrap
                l = {sprintf('try %s.CoderInfo.StorageClass = ''Custom''; catch, end', name), ...
                     sprintf('try %s.CoderInfo.CustomStorageClass = ''%s''; catch, end', name, sc)};
            else
                l = {sprintf('%s.CoderInfo.StorageClass = ''Custom'';', name), ...
                     sprintf('%s.CoderInfo.CustomStorageClass = ''%s'';', name, sc)};
            end
        end

        function l = objectComment(label, name)
            if isempty(label)
                l = sprintf('%%%% ----- %s -----', name);
            else
                l = sprintf('%%%% ----- %s: %s -----', label, name);
            end
        end

        function l = sectionHeader(title)
            eq = repmat('=', 1, 16);
            l = {'', sprintf('%%%% %s %s %s', eq, title, eq), ''};
        end

        function lines = headerLines(xlsName)
            lines = {'%% 自动生成的数据对象文件', ...
                     sprintf('%%%% 创建时间: %s', char(datetime('now'))), ...
                     sprintf('%%%% 来源 Excel: %s', xlsName), ...
                     '%%', ...
                     '%% 在 MATLAB 中运行此脚本即可在工作区创建所有 Simulink 对象'};
        end

        function o = emptyObjects()
            o = struct('name', {}, 'type', {}, 'constructor', {}, 'sheet', {});
        end

        function o = makeObject(name, type, constructor, sheet)
            o = struct('name', name, 'type', type, 'constructor', constructor, 'sheet', sheet);
        end

        function b = emptyBusElements()
            b = struct('bus', {}, 'name', {}, 'sheet', {});
        end

        %% ---------- 各表 Section ----------
        function [lines, objs] = signalSection(t)
            lines = swb.ScriptBuilder.sectionHeader('Signal 对象');
            objs = swb.ScriptBuilder.emptyObjects();
            for r = 1:swb.ScriptBuilder.rowCount(t)
                name = swb.ScriptBuilder.textAt(t, r, 'VariableName');
                if isempty(name)
                    continue;
                end
                pkg = swb.ScriptBuilder.textAt(t, r, 'Package');
                if isempty(pkg)
                    pkg = 'Simulink';
                end
                lines{end+1} = swb.ScriptBuilder.objectComment('Signal', name);
                lines{end+1} = sprintf('%s = %s.Signal;', name, pkg);
                sc = swb.ScriptBuilder.textAt(t, r, 'CustomStorageClass');
                if ~isempty(sc)
                    wrap = strcmpi(pkg, 'Simulink') && swb.Schema.isCustomStorageClass(sc);
                    lines = [lines, swb.ScriptBuilder.scLines(name, sc, wrap)];
                end
                hf = swb.ScriptBuilder.textAt(t, r, 'HeaderFile');
                if ~isempty(hf)
                    lines{end+1} = sprintf('try %s.CoderInfo.CustomAttributes.HeaderFile = ''%s''; catch, end', name, hf);
                end
                df = swb.ScriptBuilder.textAt(t, r, 'DefinitionFile');
                if ~isempty(df)
                    lines{end+1} = sprintf('try %s.CoderInfo.CustomAttributes.DefinitionFile = ''%s''; catch, end', name, df);
                end
                lines = swb.ScriptBuilder.strProp(lines, name, t, r, 'DataType');
                lines = swb.ScriptBuilder.strProp(lines, name, t, r, 'InitialValue');
                lines = swb.ScriptBuilder.scalarProp(lines, name, t, r, 'Min');
                lines = swb.ScriptBuilder.scalarProp(lines, name, t, r, 'Max');
                lines = swb.ScriptBuilder.strProp(lines, name, t, r, 'Description');
                lines = swb.ScriptBuilder.strProp(lines, name, t, r, 'Unit', 'DocUnits');
                lines = swb.ScriptBuilder.valueProp(lines, name, t, r, 'Dimensions');
                lines = swb.ScriptBuilder.strProp(lines, name, t, r, 'Complexity');
                lines{end+1} = '';
                objs(end+1) = swb.ScriptBuilder.makeObject(name, 'Signal', [pkg '.Signal'], t.name); %#ok<AGROW>
            end
        end

        function [lines, objs] = parameterSection(t)
            lines = swb.ScriptBuilder.sectionHeader('Parameter 对象');
            objs = swb.ScriptBuilder.emptyObjects();
            for r = 1:swb.ScriptBuilder.rowCount(t)
                name = swb.ScriptBuilder.textAt(t, r, 'VariableName');
                if isempty(name)
                    continue;
                end
                pkg = swb.ScriptBuilder.textAt(t, r, 'Package');
                if isempty(pkg)
                    pkg = 'Simulink';
                end
                lines{end+1} = swb.ScriptBuilder.objectComment('Parameter', name);
                lines{end+1} = sprintf('%s = %s.Parameter;', name, pkg);
                sc = swb.ScriptBuilder.textAt(t, r, 'CustomStorageClass');
                if ~isempty(sc)
                    wrap = strcmpi(pkg, 'Simulink') && swb.Schema.isCustomStorageClass(sc);
                    lines = [lines, swb.ScriptBuilder.scLines(name, sc, wrap)];
                end
                hf = swb.ScriptBuilder.textAt(t, r, 'HeaderFile');
                if ~isempty(hf)
                    lines{end+1} = sprintf('try %s.CoderInfo.CustomAttributes.HeaderFile = ''%s''; catch, end', name, hf);
                end
                df = swb.ScriptBuilder.textAt(t, r, 'DefinitionFile');
                if ~isempty(df)
                    lines{end+1} = sprintf('try %s.CoderInfo.CustomAttributes.DefinitionFile = ''%s''; catch, end', name, df);
                end
                lines = swb.ScriptBuilder.strProp(lines, name, t, r, 'DataType');
                % 先 Dimensions 再 Value（Simulink 要求设维度时 Value 为空）
                lines = swb.ScriptBuilder.valueProp(lines, name, t, r, 'Dimensions');
                lines = swb.ScriptBuilder.valueProp(lines, name, t, r, 'InitialValue', 'Value');
                lines = swb.ScriptBuilder.scalarProp(lines, name, t, r, 'Min');
                lines = swb.ScriptBuilder.scalarProp(lines, name, t, r, 'Max');
                lines = swb.ScriptBuilder.strProp(lines, name, t, r, 'Description');
                lines = swb.ScriptBuilder.strProp(lines, name, t, r, 'Unit', 'DocUnits');
                lines = swb.ScriptBuilder.strProp(lines, name, t, r, 'Complexity');
                lines{end+1} = '';
                objs(end+1) = swb.ScriptBuilder.makeObject(name, 'Parameter', [pkg '.Parameter'], t.name); %#ok<AGROW>
            end
        end

        function [lines, objs] = constSection(t)
            lines = swb.ScriptBuilder.sectionHeader('Const 对象 (Parameter + 存储类)');
            objs = swb.ScriptBuilder.emptyObjects();
            for r = 1:swb.ScriptBuilder.rowCount(t)
                name = swb.ScriptBuilder.textAt(t, r, 'Name');
                if isempty(name)
                    continue;
                end
                pkg = 'Simulink';
                p = swb.ScriptBuilder.textAt(t, r, 'Package');
                if ~isempty(p)
                    pkg = p;
                end
                sc = 'Define';
                s0 = swb.ScriptBuilder.textAt(t, r, 'CustomStorageClass');
                if ~isempty(s0)
                    sc = s0;
                end
                lines{end+1} = swb.ScriptBuilder.objectComment('Const', name);
                lines{end+1} = sprintf('%s = %s.Parameter;', name, pkg);
                % Const 表按设计使用 Define 等自定义存储类，保持旧文本格式
                lines = [lines, swb.ScriptBuilder.scLines(name, sc, false)]; %#ok<AGROW>
                lines = swb.ScriptBuilder.strProp(lines, name, t, r, 'DataType');
                lines = swb.ScriptBuilder.valueProp(lines, name, t, r, 'Value');
                hf = swb.ScriptBuilder.textAt(t, r, 'HeaderFile');
                if ~isempty(hf)
                    lines{end+1} = sprintf('%s.CoderInfo.CustomAttributes.HeaderFile = ''%s'';', name, hf);
                end
                lines{end+1} = '';
                objs(end+1) = swb.ScriptBuilder.makeObject(name, 'Const', [pkg '.Parameter'], t.name); %#ok<AGROW>
            end
        end

        function [lines, objs] = busSection(t)
            lines = swb.ScriptBuilder.sectionHeader('Bus 对象');
            objs = swb.ScriptBuilder.emptyObjects();
            for r = 1:swb.ScriptBuilder.rowCount(t)
                bn = swb.ScriptBuilder.textAt(t, r, 'BusName');
                if isempty(bn)
                    continue;
                end
                lines{end+1} = swb.ScriptBuilder.objectComment('Bus', bn);
                lines{end+1} = sprintf('%s = Simulink.Bus;', bn);
                lines = swb.ScriptBuilder.strProp(lines, bn, t, r, 'Description');
                lines = swb.ScriptBuilder.strProp(lines, bn, t, r, 'HeaderFile');
                al = swb.ScriptBuilder.textAt(t, r, 'Alignment');
                if ~isempty(al)
                    lines{end+1} = sprintf('%s.Alignment = %s;', bn, al);
                end
                ped = swb.ScriptBuilder.textAt(t, r, 'PreserveElementDimensions');
                if ~isempty(ped)
                    if strcmpi(ped, 'TRUE') || strcmp(ped, '1')
                        lines{end+1} = sprintf('%s.PreserveElementDimensions = true;', bn);
                    else
                        lines{end+1} = sprintf('%s.PreserveElementDimensions = false;', bn);
                    end
                end
                lines = swb.ScriptBuilder.strProp(lines, bn, t, r, 'DataScope');
                lines{end+1} = '';
                objs(end+1) = swb.ScriptBuilder.makeObject(bn, 'Bus', 'Simulink.Bus', t.name); %#ok<AGROW>
            end
        end

        function [lines, objs, bes] = busElementSection(t)
            lines = swb.ScriptBuilder.sectionHeader('BusElement 定义');
            objs = swb.ScriptBuilder.emptyObjects();
            bes = swb.ScriptBuilder.emptyBusElements();
            if swb.ScriptBuilder.rowCount(t) == 0
                return;
            end
            names = cell(1, swb.ScriptBuilder.rowCount(t));
            for r = 1:swb.ScriptBuilder.rowCount(t)
                names{r} = swb.ScriptBuilder.textAt(t, r, 'BusName');
            end
            unames = unique(names);
            for b = 1:numel(unames)
                bn = unames{b};
                if isempty(bn)
                    continue;
                end
                mask = strcmp(names, bn);
                rows = find(mask);
                ne = numel(rows);
                lines{end+1} = swb.ScriptBuilder.objectComment('', ...
                    sprintf('为 Bus ''%s'' 创建 %d 个元素', bn, ne));
                lines{end+1} = 'saveVarsTmp{1} = Simulink.BusElement;';
                for e = 1:ne
                    r = rows(e);
                    en = swb.ScriptBuilder.textAt(t, r, 'ElementName');
                    if isempty(en)
                        continue;
                    end
                    if e == 1
                        target = 'saveVarsTmp{1}';
                    else
                        lines{end+1} = sprintf('saveVarsTmp{1}(%d, 1) = Simulink.BusElement;', e); %#ok<AGROW>
                        target = sprintf('saveVarsTmp{1}(%d, 1)', e);
                    end
                    lines{end+1} = sprintf('%s.Name = ''%s'';', target, en); %#ok<AGROW>
                    lines = swb.ScriptBuilder.strProp(lines, target, t, r, 'Description');
                    lines = swb.ScriptBuilder.strProp(lines, target, t, r, 'DataType');
                    lines = swb.ScriptBuilder.valueProp(lines, target, t, r, 'Dimensions');
                    lines = swb.ScriptBuilder.strProp(lines, target, t, r, 'Unit', 'DocUnits');
                    bes(end+1) = struct('bus', bn, 'name', en, 'sheet', t.name); %#ok<AGROW>
                end
                lines{end+1} = sprintf('%s.Elements = saveVarsTmp{1};', bn); %#ok<AGROW>
                lines{end+1} = 'clear saveVarsTmp;'; %#ok<AGROW>
                lines{end+1} = ''; %#ok<AGROW>
            end
        end

        function et = enumSection(t)
            et = struct('name', {}, 'path', {}, 'content', {});
            if swb.ScriptBuilder.rowCount(t) == 0
                return;
            end
            names = cell(1, swb.ScriptBuilder.rowCount(t));
            for r = 1:swb.ScriptBuilder.rowCount(t)
                names{r} = swb.ScriptBuilder.textAt(t, r, 'EnumName');
            end
            unames = unique(names);
            for e = 1:numel(unames)
                ename = unames{e};
                if isempty(ename)
                    continue;
                end
                rows = find(strcmp(names, ename));
                baseType = 'uint8';
                for j = 1:numel(rows)
                    dt = swb.ScriptBuilder.textAt(t, rows(j), 'DataType');
                    if ~isempty(dt)
                        baseType = dt;
                        break;
                    end
                end
                c = {sprintf('classdef %s < %s', ename, baseType), '   enumeration'};
                for j = 1:numel(rows)
                    label = swb.ScriptBuilder.textAt(t, rows(j), 'EnumNumbers');
                    if isempty(label)
                        continue;
                    end
                    c{end+1} = sprintf('      %s (%s)', label, ...
                        swb.ScriptBuilder.fmtVal(swb.ScriptBuilder.textAt(t, rows(j), 'Value'))); %#ok<AGROW>
                end
                c = [c, {'   end', 'end'}]; %#ok<AGROW>
                content = [strjoin(c, newline), newline];
                et(end+1) = struct('name', ename, 'path', '', 'content', content); %#ok<AGROW>
            end
        end
    end
end
