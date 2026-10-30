classdef PortTable
    %SWB.PORTTABLE 端口工作簿（Inputs/Outputs，7 列）读写。
    %   兼容旧 NewModelApp 的三件事：
    %     1) 表名可以是 Inputs/Input/输入、Outputs/Output/输出（忽略大小写）
    %     2) 若没有上述表名，退化为单表按 "Input"/"Output" 分节标题拆分
    %     3) 首行表头自动识别并跳过
    %   解析结果是 struct 数组，字段：name,dataType,storageClass,identifier,
    %   headerFile,definitionFile,row（Excel 行号，用于定位问题）

    methods (Static)
        function [inPorts, outPorts, info] = read(filePath)
            % 读取端口工作簿。info 记录实际使用的表名与读取方式。
            inPorts = swb.PortTable.emptyPorts();
            outPorts = swb.PortTable.emptyPorts();
            info = struct('path', char(filePath), 'inputSheet', '', 'outputSheet', '', ...
                          'mode', '', 'warnings', {{}});
            if isempty(filePath) || ~isfile(filePath)
                info.warnings{end+1} = sprintf('端口工作簿不存在: %s', char(filePath));
                return;
            end
            sheets = cellstr(sheetnames(char(filePath)));
            [inSheet, outSheet] = swb.Workbook.matchPortSheets(sheets);

            if isempty(inSheet) && isempty(outSheet)
                % 退化：单表按分节标题拆
                raw = readcell(char(filePath));
                [inRaw, outRaw] = swb.PortTable.splitSections(raw);
                inPorts = swb.PortTable.parse(inRaw, '');
                outPorts = swb.PortTable.parse(outRaw, '');
                info.mode = 'sections';
                info.warnings{end+1} = '未找到 Inputs/Outputs 工作表，已按单表分节标题解析。';
                return;
            end

            info.mode = 'sheets';
            if ~isempty(inSheet)
                info.inputSheet = inSheet{1};
                raw = readcell(char(filePath), 'Sheet', inSheet{1});
                inPorts = swb.PortTable.parse(raw, inSheet{1});
            end
            if ~isempty(outSheet)
                info.outputSheet = outSheet{1};
                raw = readcell(char(filePath), 'Sheet', outSheet{1});
                outPorts = swb.PortTable.parse(raw, outSheet{1});
            end
        end

        function ports = parse(raw, sheetName)
            % 解析一张端口表（raw 含表头行）
            ports = swb.PortTable.emptyPorts();
            if isempty(raw)
                return;
            end
            startIdx = 1;
            if swb.PortTable.isHeaderRow(raw)
                startIdx = 2;
            end

            for i = startIdx:size(raw, 1)
                name = swb.Workbook.cellText(swb.Workbook.cellValue(raw, i, 2));
                name = regexprep(name, '[\r\n\t\v\f]', '');
                name = strtrim(name);
                if isempty(name)
                    continue;
                end
                p = swb.Schema.blankPort();
                p.name = name;
                p.dataType = swb.PortTable.textAt(raw, i, 3);
                p.storageClass = swb.PortTable.textAt(raw, i, 4);
                p.identifier = swb.PortTable.textAt(raw, i, 5);
                p.headerFile = swb.PortTable.textAt(raw, i, 6);
                p.definitionFile = swb.PortTable.textAt(raw, i, 7);
                p.row = i;   % raw 含表头，行号即 Excel 行号
                ports(end+1) = p; %#ok<AGROW>
            end
            if ~isempty(sheetName)
                % sheetName 仅用于调用方展示，字段里已有行号
            end
        end

        function tf = isHeaderRow(raw)
            tf = false;
            if isempty(raw) || size(raw, 1) < 1
                return;
            end
            first = swb.Workbook.cellText(raw{1, 1});
            if isempty(first)
                return;
            end
            words = {'port','name','端口','端口名','端口名称','portname','port_name', ...
                     '信号名','信号名称','序号','序列号','编号'};
            tf = any(strcmpi(strtrim(first), words));
        end

        function [inRaw, outRaw] = splitSections(raw)
            % 按列 A 的分节标题拆分单表：Input/输入/输入端口/inputs 与 Output/输出/输出端口/outputs
            inRaw = {};
            outRaw = {};
            if isempty(raw)
                return;
            end
            current = '';
            for i = 1:size(raw, 1)
                first = swb.Workbook.cellText(raw{i, 1});
                key = lower(strtrim(first));
                if any(strcmp(key, {'input','输入','输入端口','inputs'}))
                    current = 'input';
                    continue;
                elseif any(strcmp(key, {'output','输出','输出端口','outputs'}))
                    current = 'output';
                    continue;
                end
                if isempty(key)
                    continue;
                end
                if strcmp(current, 'input')
                    inRaw(end+1, :) = raw(i, :); %#ok<AGROW>
                elseif strcmp(current, 'output')
                    outRaw(end+1, :) = raw(i, :); %#ok<AGROW>
                end
            end
            if isempty(current) && ~isempty(raw)
                inRaw = raw;
            end
        end

        function txt = textAt(raw, r, c)
            v = swb.Workbook.cellValue(raw, r, c);
            if ischar(v) || isstring(v)
                txt = strtrim(swb.Workbook.cellText(v));
            else
                txt = '';
            end
        end

        function ports = emptyPorts()
            ports = struct('name', {}, 'dataType', {}, 'storageClass', {}, 'identifier', {}, ...
                           'headerFile', {}, 'definitionFile', {}, 'row', {});
        end

        function write(filePath, inPorts, outPorts)
            % 写入端口工作簿（保持旧工具的 7 列表头，保证可回读）
            headers = swb.Schema.PORT_COLUMNS;
            inData = swb.PortTable.toCells(inPorts, headers);
            outData = swb.PortTable.toCells(outPorts, headers);
            if isfile(char(filePath))
                delete(char(filePath));   % 整本重写，避免旧内容残留
            end
            writecell(inData, char(filePath), 'Sheet', 'Inputs');
            writecell(outData, char(filePath), 'Sheet', 'Outputs');
            swb.PortTable.cleanupDefaultSheet(char(filePath));
        end

        function data = toCells(ports, headers)
            data = cell(numel(ports) + 1, numel(headers));
            data(1, :) = headers;
            for i = 1:numel(ports)
                p = ports(i);
                data{i+1, 1} = i;
                data{i+1, 2} = p.name;
                data{i+1, 3} = p.dataType;
                data{i+1, 4} = p.storageClass;
                data{i+1, 5} = p.identifier;
                data{i+1, 6} = p.headerFile;
                data{i+1, 7} = p.definitionFile;
            end
        end

        function cleanupDefaultSheet(filePath)
            % writecell 首次写文件可能留下空的 Sheet1；仅 Windows + Excel 可用时清理
            try
                sheets = cellstr(sheetnames(filePath));
                if ~any(strcmp(sheets, 'Sheet1'))
                    return;
                end
                if ~ispc
                    return;
                end
                excel = actxserver('Excel.Application');
                c1 = onCleanup(@() excel.Quit);
                excel.DisplayAlerts = false;
                wb = excel.Workbooks.Open(filePath);
                c2 = onCleanup(@() wb.Close(false));
                for s = sheets(:)'
                    if strcmp(s{1}, 'Sheet1')
                        wb.Sheets.Item('Sheet1').Delete;
                        break;
                    end
                end
                wb.Save;
            catch
                % 无 Excel/非 Windows：忽略，不影响主流程
            end
        end

        function issues = validate(inPorts, outPorts)
            % 端口级校验：名称/重复/存储类/C 标识符。返回 swb.Issue 数组
            issues = swb.Issue.empty();
            issues = swb.Issue.concat(issues, swb.PortTable.validateSide(inPorts, 'Inputs'));
            issues = swb.Issue.concat(issues, swb.PortTable.validateSide(outPorts, 'Outputs'));

            % 输入/输出跨方向重名（顶层块名必须唯一）
            for i = 1:numel(inPorts)
                for j = 1:numel(outPorts)
                    if strcmp(inPorts(i).name, outPorts(j).name)
                        issues(end+1) = swb.Issue.make('Inputs', inPorts(i).row, 'B', 'error', ...
                            sprintf('端口名 "%s" 同时出现在 Inputs 和 Outputs，顶层块名必须唯一。', inPorts(i).name)); %#ok<AGROW>
                    end
                end
            end
        end

        function issues = validateSide(ports, sheetName)
            issues = swb.Issue.empty();
            names = {};
            for i = 1:numel(ports)
                p = ports(i);
                if isempty(strtrim(p.name))
                    issues(end+1) = swb.Issue.make(sheetName, p.row, 'B', 'error', '端口名称为空。'); %#ok<AGROW>
                    continue;
                end
                if any(strcmp(names, p.name))
                    issues(end+1) = swb.Issue.make(sheetName, p.row, 'B', 'error', ...
                        sprintf('端口名 "%s" 重复。', p.name)); %#ok<AGROW>
                else
                    names{end+1} = p.name; %#ok<AGROW>
                end
                if contains(p.name, '/')
                    issues(end+1) = swb.Issue.make(sheetName, p.row, 'B', 'error', ...
                        sprintf('端口名 "%s" 含 "/"，不能作为块名。', p.name)); %#ok<AGROW>
                elseif ~isvarname(p.name)
                    issues(end+1) = swb.Issue.make(sheetName, p.row, 'B', 'warning', ...
                        sprintf('端口名 "%s" 不是合法 MATLAB 标识符（Simulink 允许，但 Code Mapping Identifier 需要合法 C 标识符）。', p.name)); %#ok<AGROW>
                end
                if ~isempty(p.storageClass) && ~any(strcmp(p.storageClass, swb.Schema.allStorageClasses()))
                    issues(end+1) = swb.Issue.make(sheetName, p.row, 'D', 'warning', ...
                        sprintf('存储类 "%s" 不在已知列表（内置 5 个 + myPackage 16 个），Code Mapping 可能失败。', p.storageClass)); %#ok<AGROW>
                end
                if ~isempty(p.identifier) && ~swb.PortTable.isCIdentifier(p.identifier)
                    issues(end+1) = swb.Issue.make(sheetName, p.row, 'E', 'error', ...
                        sprintf('Identifier "%s" 不是合法 C 标识符。', p.identifier)); %#ok<AGROW>
                end
            end
        end

        function tf = isCIdentifier(s)
            tf = ~isempty(regexp(char(s), '^[A-Za-z_][A-Za-z0-9_]*$', 'once'));
        end

        function n = total(ports)
            n = numel(ports);
        end
    end
end
