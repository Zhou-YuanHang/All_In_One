classdef CodeMapping
    %SWB.CODEMAPPING 端口 Code Mapping（StorageClass/Identifier/HeaderFile/DefinitionFile）应用与回读。
    %   迁移旧 NewModelApp 的 Code Mapping 映射块，但不弹窗：
    %     每个端口独立 try/catch，失败端口名汇总到 stats，不中断整次创建。
    %   apply 的许可策略是「先尝试、失败再降级」：直接尝试 coder.mapping.utils.create，
    %   成功则正常映射；抛错则返回 initialized=false + initError，绝不抛错，模型照常创建。
    %   若同时缺 Simulink Coder / Embedded Coder 许可证，会在 initError 里补一句许可缺失原因
    %   （实测无 Coder 许可证时 create/setInport 仍可能可用，所以不能靠 license('test') 提前拦截）。
    %
    %   tf    = swb.CodeMapping.available()   % 纯诊断，不参与 apply 决策
    %   stats = swb.CodeMapping.apply(modelName, inPorts, outPorts, opts)
    %   rows  = swb.CodeMapping.read(modelName)
    %
    %   opts.IgnoreLicense：deprecated，仅为兼容旧调用保留；已不再影响主流程（apply 总是先尝试）。
    %
    %   stats 字段：initialized(bool) initError(char) appliedInput appliedOutput
    %               failedInput(cellstr) failedOutput(cellstr)
    %   rows  字段：name storageClass identifier headerFile definitionFile（struct 数组）

    methods (Static)
        function tf = available()
            % 是否具备 Code Mapping 所需的代码生成许可证
            tf = false;
            try
                tf = license('test', 'Simulink_Coder') || license('test', 'Embedded_Coder');
            catch
                tf = false;
            end
        end

        function stats = blankStats()
            % 空统计结构（便于调用方统一初始化 result.mapping）
            stats = struct('initialized', false, 'initError', '', ...
                           'appliedInput', 0, 'appliedOutput', 0, ...
                           'failedInput', {{}}, 'failedOutput', {{}});
        end

        function rows = emptyRows()
            % 空映射行（字段与 read 返回一致）
            rows = struct('name', {}, 'storageClass', {}, 'identifier', {}, ...
                          'headerFile', {}, 'definitionFile', {});
        end

        function stats = apply(modelName, inPorts, outPorts, opts)
            % 把端口表里的映射列写入模型 Code Mapping。
            stats = swb.CodeMapping.blankStats();
            if nargin < 4 || isempty(opts)
                opts = struct();
            end
            % opts.IgnoreLicense 已 deprecated：保留字段解析只为兼容旧调用，不影响下面的流程。
            modelName = strtrim(char(modelName));
            if isempty(modelName)
                stats.initError = '模型名为空，已跳过 Code Mapping。';
                return;
            end
            inPorts = swb.CodeMapping.normalizePorts(inPorts);
            outPorts = swb.CodeMapping.normalizePorts(outPorts);

            % ---- 创建映射对象（Save#1 之后才允许，调用方保证）----
            % 许可策略：先尝试、失败再降级。不能靠 available() 提前拦截——
            % 实测无 Coder 许可证时 coder.mapping.utils.create / setInport 仍可工作。
            try
                cm = coder.mapping.utils.create(modelName);
            catch ME
                stats.initError = sprintf('Code Mapping 初始化失败: %s', ME.message);
                if ~swb.CodeMapping.available()
                    stats.initError = sprintf( ...
                        ['%s（未检测到 Simulink Coder / Embedded Coder 许可证: ', ...
                         'Simulink_Coder=%d, Embedded_Coder=%d）'], ...
                        stats.initError, ...
                        swb.CodeMapping.licenseFlag('Simulink_Coder'), ...
                        swb.CodeMapping.licenseFlag('Embedded_Coder'));
                end
                return;
            end
            if isempty(cm)
                stats.initError = 'Code Mapping 初始化返回空对象，已跳过。';
                return;
            end
            stats.initialized = true;

            % ---- 逐端口应用：单端口失败只记录名字，不中断 ----
            [stats.appliedInput, stats.failedInput] = swb.CodeMapping.applySide(cm, inPorts, 'Input');
            [stats.appliedOutput, stats.failedOutput] = swb.CodeMapping.applySide(cm, outPorts, 'Output');
        end

        function rows = read(modelName)
            % 读回模型当前 Code Mapping（模型未加载时临时加载，结束后恢复状态）。
            rows = swb.CodeMapping.emptyRows();
            [modelName, modelFile] = swb.CodeMapping.resolveModelRef(modelName);
            if isempty(modelName)
                return;
            end
            wasLoaded = bdIsLoaded(modelName);
            if ~wasLoaded
                try
                    if isempty(modelFile)
                        load_system(modelName);
                    else
                        load_system(modelFile);
                    end
                catch
                    return;
                end
            end
            try
                cm = [];
                try
                    cm = coder.mapping.api.get(modelName);
                catch
                    cm = [];
                end
                if ~isempty(cm)
                    rows = swb.CodeMapping.readSide(cm, modelName, 'Inport', 'Input', rows);
                    rows = swb.CodeMapping.readSide(cm, modelName, 'Outport', 'Output', rows);
                end
            catch
                % 读映射是尽力而为：任何失败都返回已收集到的行
            end
            if ~wasLoaded && bdIsLoaded(modelName)
                try
                    close_system(modelName, 0);
                catch
                end
            end
        end
    end

    methods (Static, Access = private)
        function [modelName, modelFile] = resolveModelRef(ref)
            % 接受模型名或 .slx/.mdl 文件路径（模型未加载时按路径加载）
            ref = strtrim(char(ref));
            modelName = ref;
            modelFile = '';
            if isempty(ref)
                return;
            end
            [~, base, ext] = fileparts(ref);
            if any(strcmpi(ext, {'.slx', '.mdl'}))
                modelName = strtrim(base);
                modelFile = ref;
            end
        end

        function tf = licenseFlag(feature)
            try
                tf = license('test', feature);
            catch
                tf = 0;
            end
        end

        function ports = normalizePorts(ports)
            % 接受 struct 数组或 cell of struct（旧代码传 cell）
            if isempty(ports)
                ports = swb.PortTable.emptyPorts();
                return;
            end
            if iscell(ports)
                ports = [ports{:}];
            end
            if ~isstruct(ports) || ~isfield(ports, 'name')
                error('swb:CodeMapping:badPorts', '端口必须是含 name 字段的结构体数组。');
            end
        end

        function [applied, failed] = applySide(cm, ports, direction)
            applied = 0;
            failed = {};
            if isempty(ports)
                return;
            end
            for i = 1:numel(ports)
                p = ports(i);
                try
                    nv = swb.CodeMapping.mappingPairs(p);
                    if strcmpi(direction, 'Input')
                        setInport(cm, p.name, nv{:});
                    else
                        setOutport(cm, p.name, nv{:});
                    end
                    applied = applied + 1;
                catch
                    failed{end+1} = p.name; %#ok<AGROW>
                end
            end
        end

        function nv = mappingPairs(p)
            % 组装 setInport/setOutport 的 name-value 参数：StorageClass 空则 Auto
            sc = '';
            if isfield(p, 'storageClass')
                sc = strtrim(p.storageClass);
            end
            if isempty(sc)
                sc = 'Auto';
            end
            nv = {'StorageClass', sc};
            if isfield(p, 'identifier') && ~isempty(strtrim(p.identifier))
                nv = [nv, {'Identifier', strtrim(p.identifier)}];
            end
            if isfield(p, 'headerFile') && ~isempty(strtrim(p.headerFile))
                nv = [nv, {'HeaderFile', strtrim(p.headerFile)}];
            end
            if isfield(p, 'definitionFile') && ~isempty(strtrim(p.definitionFile))
                nv = [nv, {'DefinitionFile', strtrim(p.definitionFile)}];
            end
        end

        function rows = readSide(cm, modelName, blockType, direction, rows)
            blocks = find_system(modelName, 'SearchDepth', 1, 'BlockType', blockType);
            for i = 1:numel(blocks)
                r = swb.CodeMapping.readOne(cm, blocks{i}, direction);
                if ~isempty(r.name)
                    rows(end+1) = r; %#ok<AGROW>
                end
            end
        end

        function r = readOne(cm, blkPath, direction)
            r = struct('name', '', 'storageClass', '', 'identifier', '', ...
                       'headerFile', '', 'definitionFile', '');
            try
                r.name = char(get_param(blkPath, 'Name'));
            catch
                return;
            end
            props = {'StorageClass', 'storageClass'; 'Identifier', 'identifier'; ...
                     'HeaderFile', 'headerFile'; 'DefinitionFile', 'definitionFile'};
            for k = 1:size(props, 1)
                try
                    if strcmpi(direction, 'Input')
                        v = getInport(cm, r.name, props{k, 1});
                    else
                        v = getOutport(cm, r.name, props{k, 1});
                    end
                    if ischar(v) || isstring(v)
                        r.(props{k, 2}) = char(v);
                    end
                catch
                    % 单个属性读不到就留空
                end
            end
        end
    end
end
