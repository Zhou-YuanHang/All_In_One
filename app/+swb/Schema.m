classdef Schema
    %SWB.SCHEMA 工作簿契约的唯一事实来源。
    %   集中定义 8 表数据字典工作簿与 7 列端口工作簿的列序、必填列、表名别名、
    %   Config 候选键、自定义存储类等。校验、脚本生成、反向同步、UI 全部从这里取，
    %   避免旧代码里"三份元数据各自为政"的问题。

    properties (Constant)
        % 数据字典工作簿的 8 张表（顺序即规范顺序）
        DICT_SHEETS = {'History', 'Signal', 'Parameter', 'Const', 'Enum', 'Bus', 'BusElement', 'Config'};
        % 端口工作簿输入/输出表的别名（匹配时忽略大小写）
        PORT_INPUT_ALIASES = {'Inputs', 'Input', '输入'};
        PORT_OUTPUT_ALIASES = {'Outputs', 'Output', '输出'};
        % 端口工作簿的标准列（与旧工具导出格式一致，保证可回读）
        PORT_COLUMNS = {'序号', '端口名称', '数据类型', 'StorageClass', 'Identifier', 'HeaderFile', 'DefinitionFile'};
        % Config 表列定义：canonical key / Excel 列字母 / 表头文字
        CONFIG_KEYS = {'Package', 'Object', 'StorageClass', 'DataType', 'Unit', 'DimensionsMode', 'Complexity', 'DataScope'};
        CONFIG_LETTERS = 'ABCDEFGH';
        CONFIG_HEADERS = {'Package', 'Object', 'Storage class', 'Data Type', 'Unit', 'DimensionsMode', 'Complexity', 'DataScope'};
    end

    methods (Static)
        %% ---------- 数据字典表 ----------
        function tf = isDictSheet(name)
            tf = any(strcmpi(char(name), swb.Schema.DICT_SHEETS));
        end

        function spec = dictSheetSpec(name)
            % 返回 struct: name, columns(1xN cellstr), required(索引), keyColumns(索引), importable
            name = swb.Schema.canonicalSheetName(name);
            switch name
                case 'Signal'
                    columns = {'VariableName','Package','Object','CustomStorageClass','DataType', ...
                               'InitialValue','HeaderFile','DefinitionFile','Description','Min','Max', ...
                               'Unit','Dimensions','Complexity'};
                    required = 1:5;
                    keys = 1;
                    importable = true;
                case 'Parameter'
                    columns = {'VariableName','Package','Object','CustomStorageClass','DataType', ...
                               'InitialValue','HeaderFile','DefinitionFile','Description','Min','Max', ...
                               'Unit','Dimensions','Complexity'};
                    required = 1:6;
                    keys = 1;
                    importable = true;
                case 'Const'
                    columns = {'Name','Package','CustomStorageClass','Value','DataType','HeaderFile'};
                    required = 1:3;
                    keys = 1;
                    importable = true;
                case 'Enum'
                    columns = {'EnumName','EnumNumbers','Value','DataType'};
                    required = 1:4;
                    keys = [1 2];
                    importable = true;
                case 'Bus'
                    columns = {'BusName','Description','HeaderFile','Alignment', ...
                               'PreserveElementDimensions','DataScope'};
                    required = [1 3 4 5 6];
                    keys = 1;
                    importable = true;
                case 'BusElement'
                    columns = {'BusName','ElementName','DataType','Dimensions','Description','Unit'};
                    required = 1:4;
                    keys = [1 2];
                    importable = true;
                case 'Config'
                    columns = swb.Schema.CONFIG_HEADERS;
                    required = [];
                    keys = 1;
                    importable = false;   % Config 只作下拉数据源，不导入
                case 'History'
                    columns = {'Version','ChangeDate','Changer','Content'};
                    required = [];
                    keys = 1;
                    importable = false;
                otherwise
                    error('swb:Schema:unknownSheet', '未知的数据字典工作表: %s', char(name));
            end
            spec = struct('name', name, 'columns', {columns}, 'required', required, ...
                          'keyColumns', keys, 'importable', importable);
        end

        function name = canonicalSheetName(name)
            % 把大小写/空白变体归一到规范表名；未知名原样返回。
            name = strtrim(char(name));
            idx = find(strcmpi(swb.Schema.DICT_SHEETS, name), 1);
            if isempty(idx)
                name = name;
            else
                name = swb.Schema.DICT_SHEETS{idx};
            end
        end

        function names = importableSheetNames()
            all = swb.Schema.DICT_SHEETS;
            names = {};
            for k = 1:numel(all)
                spec = swb.Schema.dictSheetSpec(all{k});
                if spec.importable
                    names{end+1} = all{k}; %#ok<AGROW>
                end
            end
        end

        function cols = dictColumns(name)
            spec = swb.Schema.dictSheetSpec(name);
            cols = spec.columns;
        end

        function req = requiredColumns(name)
            spec = swb.Schema.dictSheetSpec(name);
            req = spec.required;
        end

        %% ---------- Config 表 ----------
        function c = configColumns()
            % struct array: key, letter, header
            c = struct('key', swb.Schema.CONFIG_KEYS, 'letter', num2cell(swb.Schema.CONFIG_LETTERS), ...
                       'header', swb.Schema.CONFIG_HEADERS);
        end

        function cfg = defaultConfig()
            % 与旧 template_config.json 内置默认一致
            cfg = struct( ...
                'Package',        {{'myPackage','Simulink'}}, ...
                'Object',         {{'Signal','Parameter'}}, ...
                'StorageClass',   {{'YS_SelectRAMSignal','YS_SelectRAMPara','ExportedGlobal', ...
                                    'ImportedExtern','ImportedExternPointer','Auto'}}, ...
                'DataType',       {{'single','double','uint8','int16','uint16','uint32','boolean', ...
                                    'Bus: FaultBus','single_T'}}, ...
                'Unit',           {{'-','V','A','N*m','m','m/s','℃','deg'}}, ...
                'DimensionsMode', {{'Fixed','Variable'}}, ...
                'Complexity',     {{'real','complex'}}, ...
                'DataScope',      {{'Auto','Exported','Imported'}});
        end

        function keys = configKeys()
            keys = swb.Schema.CONFIG_KEYS;
        end

        %% ---------- 存储类 ----------
        function names = customStorageClasses()
            % +myPackage/csc_registration.m 注册的 16 个自定义存储类
            names = {'YS_SelectRAMSignal','YS_SelectRAMPara','BitField','Const','Volatile', ...
                     'ConstVolatile','Define','ImportedDefine','ExportToFile','ImportFromFile', ...
                     'FileScope','Localizable','Struct','GetSet','CompilerFlag','Reusable'};
        end

        function names = builtinStorageClasses()
            % Simulink 内置存储类（写入 CoderInfo.StorageClass 的值）
            names = {'Auto','SimulinkGlobal','ExportedGlobal','ImportedExtern','ImportedExternPointer'};
        end

        function names = allStorageClasses()
            names = [swb.Schema.builtinStorageClasses(), swb.Schema.customStorageClasses()];
        end

        function names = memorySections()
            names = {'YS_RAMSignal','YS_RAMPara','MemConst','MemVolatile','MemConstVolatile'};
        end

        function names = packageNames()
            names = {'myPackage','Simulink'};
        end

        function tf = isCustomStorageClass(name)
            tf = any(strcmp(char(name), swb.Schema.customStorageClasses()));
        end

        %% ---------- 端口工作簿 ----------
        function m = portSheetMap()
            m = struct('inputs', {swb.Schema.PORT_INPUT_ALIASES}, ...
                       'outputs', {swb.Schema.PORT_OUTPUT_ALIASES});
        end

        function names = portColumns()
            names = swb.Schema.PORT_COLUMNS;
        end

        function f = portFieldNames()
            % 解析后的端口结构体字段（与列 C..G 对应）
            f = {'name','dataType','storageClass','identifier','headerFile','definitionFile'};
        end

        function s = blankPort()
            s = struct('name','','dataType','','storageClass','','identifier','', ...
                       'headerFile','','definitionFile','','row',NaN);
        end

        %% ---------- 模型默认配置 ----------
        function d = modelConfigDefaults()
            d = struct( ...
                'ModelName', 'myModel', ...
                'ModelFolder', '', ...
                'SolverType', 'Discrete', ...    % Continuous | Discrete
                'SampleTime', '0.01', ...
                'SystemTargetFile', 'ert.tlc', ...
                'GenCodeOnly', false, ...
                'DictFile', '', ...
                'PortWorkbook', '', ...
                'ApplyCodeMapping', false, ...
                'OpenAfterCreate', true, ...
                'ConflictPolicy', 'ask');          % ask | overwrite | suffix | cancel
        end

        %% ---------- 表头归一化 ----------
        function key = normalizeHeader(h)
            % 用于把 Excel 表头映射到规范列名：小写并去掉空格/下划线/连字符等
            key = '';
            if isempty(h)
                return;
            end
            try
                if isnumeric(h) || islogical(h)
                    if ~isscalar(h) || isnan(double(h))
                        return;
                    end
                end
                s = char(string(h));
                if isempty(strtrim(s))
                    return;
                end
                s = lower(s);
                s = regexprep(s, '[\s_\-]+', '');
                s = regexprep(s, '[^a-z0-9]', '');
                key = s;
            catch
                key = '';
            end
        end

        function idx = matchColumns(headers, canonicalColumns)
            % 返回 1xN 列索引，0 表示该规范列在表头中不存在（含大小写/空格变体匹配）
            idx = zeros(1, numel(canonicalColumns));
            normHeaders = cellfun(@swb.Schema.normalizeHeader, headers, 'UniformOutput', false);
            for k = 1:numel(canonicalColumns)
                key = swb.Schema.normalizeHeader(canonicalColumns{k});
                hit = find(strcmp(normHeaders, key), 1);
                if isempty(hit)
                    % 常见别名
                    aliases = swb.Schema.headerAliases(canonicalColumns{k});
                    for a = 1:numel(aliases)
                        hit = find(strcmp(normHeaders, swb.Schema.normalizeHeader(aliases{a})), 1);
                        if ~isempty(hit), break; end
                    end
                end
                if ~isempty(hit), idx(k) = hit; end
            end
        end

        function a = headerAliases(col)
            switch swb.Schema.normalizeHeader(col)
                case 'datatype'
                    a = {'DataType','Data Type','Type'};
                case 'customstorageclass'
                    a = {'CustomStorageClass','Storage class','StorageClass'};
                case 'variablename'
                    a = {'VariableName','Variable Name','Name'};
                case 'busname'
                    a = {'BusName','Bus Name'};
                case 'elementname'
                    a = {'ElementName','Element Name'};
                case 'preserveelementdimensions'
                    a = {'PreserveElementDimensions','Preserve Element Dimensions'};
                otherwise
                    a = {};
            end
        end
    end
end