classdef PortSync
    %SWB.PORTSYNC 模型顶层端口 ↔ 端口表定义的增量同步（按名字增/删/改）。
    %   迁移旧 NewModelApp.syncPorts：按端口名匹配，只协调数据类型；
    %   删除时若端口有连线，连接会随之丢失（warnings 里逐条说明，不静默丢线）。
    %
    %   modelName 可以是模型名（已加载或在搜索路径上），也可以是 .slx/.mdl 文件全路径。
    %
    %   [inPorts, outPorts] = swb.PortSync.existing(modelName)
    %       struct 数组字段：name, dataType, position, blockPath（仅顶层，SearchDepth 1）
    %       模型未加载时临时加载并恢复原状态；返回的是快照，blockPath 在模型再次打开前可能失效。
    %
    %   stats = swb.PortSync.apply(modelName, inPorts, outPorts, opts)
    %       stats：ok, added, removed, updated, unchanged, warnings, errorText
    %       opts.Log（swb.Log）、opts.SaveAfter（默认 true）。
    %       若调用前模型未加载：结束前按 SaveAfter 保存并关闭（恢复原状态）；
    %       若调用前已加载：保持加载，是否保存由调用方决定（与旧 App 一致）。

    methods (Static)
        function [inPorts, outPorts] = existing(modelName)
            [modelName, modelFile] = swb.PortSync.resolveModelRef(modelName);
            inPorts = swb.PortSync.emptyPorts();
            outPorts = swb.PortSync.emptyPorts();
            if isempty(modelName)
                return;
            end
            wasLoaded = bdIsLoaded(modelName);
            if ~wasLoaded
                % 模型不存在 → 不可恢复，向上抛错
                if isempty(modelFile)
                    load_system(modelName);
                else
                    load_system(modelFile);
                end
            end
            try
                inPorts = swb.PortSync.collectSide(modelName, 'Inport');
                outPorts = swb.PortSync.collectSide(modelName, 'Outport');
            catch ME
                if ~wasLoaded && bdIsLoaded(modelName)
                    try
                        close_system(modelName, 0);
                    catch
                    end
                end
                rethrow(ME);
            end
            if ~wasLoaded
                close_system(modelName, 0);
            end
        end

        function stats = apply(modelName, inPorts, outPorts, opts)
            stats = struct('ok', true, 'added', 0, 'removed', 0, 'updated', 0, ...
                           'unchanged', 0, 'warnings', {{}}, 'errorText', '');
            if nargin < 4 || isempty(opts)
                opts = struct();
            end
            if ~isfield(opts, 'Log'), opts.Log = []; end
            if ~isfield(opts, 'SaveAfter'), opts.SaveAfter = true; end
            [modelName, modelFile] = swb.PortSync.resolveModelRef(modelName);
            if isempty(modelName) || ~isvarname(modelName)
                error('swb:PortSync:badModelName', '模型名称 "%s" 不是合法的 MATLAB 标识符。', modelName);
            end
            inPorts = swb.PortSync.normalizePorts(inPorts);
            outPorts = swb.PortSync.normalizePorts(outPorts);
            log = opts.Log;

            wasLoaded = bdIsLoaded(modelName);
            if ~wasLoaded
                try
                    if isempty(modelFile)
                        load_system(modelName);
                    else
                        load_system(modelFile);
                    end
                catch ME
                    stats.ok = false;
                    stats.errorText = sprintf('无法加载模型 "%s": %s', modelName, ME.message);
                    stats.warnings{end+1} = stats.errorText;
                    return;
                end
            end

            changed = 0;
            try
                [oldIn, oldOut] = swb.PortSync.collectBoth(modelName);
                [s, w] = swb.PortSync.syncSide(modelName, oldIn, inPorts, 'Inport');
                stats = swb.PortSync.mergeSide(stats, s, w);
                [s, w] = swb.PortSync.syncSide(modelName, oldOut, outPorts, 'Outport');
                stats = swb.PortSync.mergeSide(stats, s, w);
                changed = stats.added + stats.removed + stats.updated;
            catch ME
                stats.ok = false;
                stats.errorText = sprintf('端口同步失败: %s', ME.message);
                stats.warnings{end+1} = stats.errorText;
            end

            % ---- 恢复调用前状态 ----
            if ~wasLoaded
                try
                    if stats.ok && opts.SaveAfter && changed > 0
                        save_system(modelName);
                    end
                    close_system(modelName, 0);
                catch ME2
                    stats.ok = false;
                    stats.warnings{end+1} = sprintf('同步后保存/关闭模型失败: %s', ME2.message);
                    try
                        if bdIsLoaded(modelName)
                            close_system(modelName, 0);
                        end
                    catch
                    end
                end
            end
            if ~isempty(log)
                log.info('端口同步完成：+%d -%d ~%d =%d。', ...
                    stats.added, stats.removed, stats.updated, stats.unchanged);
            end
        end
    end

    methods (Static, Access = private)
        function [modelName, modelFile] = resolveModelRef(ref)
            % 接受模型名或 .slx/.mdl 文件路径（设计文档风险 #8：其它目录的模型）
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

        function ports = emptyPorts()
            ports = struct('name', {}, 'dataType', {}, 'position', {}, 'blockPath', {});
        end

        function [inPorts, outPorts] = collectBoth(modelName)
            inPorts = swb.PortSync.collectSide(modelName, 'Inport');
            outPorts = swb.PortSync.collectSide(modelName, 'Outport');
        end

        function ports = collectSide(modelName, blockType)
            ports = swb.PortSync.emptyPorts();
            blks = find_system(modelName, 'SearchDepth', 1, 'BlockType', blockType);
            for i = 1:numel(blks)
                b = blks{i};
                try
                    s.name = char(get_param(b, 'Name'));
                    s.dataType = char(get_param(b, 'OutDataTypeStr'));
                    s.position = get_param(b, 'Position');
                    s.blockPath = b;
                catch
                    continue;   % 扫描期间块被删或属性不可读：跳过
                end
                ports(end+1) = s; %#ok<AGROW>
            end
        end

        function ports = normalizePorts(ports)
            % 接受 struct 数组或 cell of struct（兼容旧代码）
            if isempty(ports)
                ports = struct('name', {}, 'dataType', {});
                return;
            end
            if iscell(ports)
                ports = [ports{:}];
            end
            if ~isstruct(ports) || ~isfield(ports, 'name')
                error('swb:PortSync:badPorts', '端口必须是含 name 字段的结构体数组。');
            end
            if ~isfield(ports, 'dataType')
                [ports.dataType] = deal('');
            end
        end

        function stats = mergeSide(stats, s, w)
            stats.added = stats.added + s.added;
            stats.removed = stats.removed + s.removed;
            stats.updated = stats.updated + s.updated;
            stats.unchanged = stats.unchanged + s.unchanged;
            stats.warnings = [stats.warnings, w];
        end

        function [s, warnings] = syncSide(modelName, oldPorts, newPorts, blockType)
            % 单侧（Inport 或 Outport）同步
            s = struct('added', 0, 'removed', 0, 'updated', 0, 'unchanged', 0);
            warnings = {};
            isInput = strcmpi(blockType, 'Inport');
            srcBlock = 'simulink/Sources/In1';
            x = 60;
            if ~isInput
                srcBlock = 'simulink/Sinks/Out1';
                x = 500;
            end

            oldNames = {oldPorts.name};
            newNames = {newPorts.name};

            % ---- 删除：Excel 中已不存在的旧端口 ----
            kept = true(1, numel(oldPorts));
            for i = 1:numel(oldPorts)
                if any(strcmp(oldNames{i}, newNames))
                    continue;
                end
                bp = oldPorts(i).blockPath;
                try
                    if swb.PortSync.hasConnection(bp, isInput)
                        warnings{end+1} = sprintf( ...
                            '端口 "%s" 已从端口表删除，其原有连线随之丢失。', oldNames{i}); %#ok<AGROW>
                    end
                    delete_block(bp);
                    s.removed = s.removed + 1;
                    kept(i) = false;
                catch ME
                    warnings{end+1} = sprintf('删除端口 "%s" 失败: %s', oldNames{i}, ME.message); %#ok<AGROW>
                end
            end

            % ---- 新增端口的起始 y：现有端口最大 y + 50 ----
            y = 80;
            for i = 1:numel(oldPorts)
                if kept(i) && oldPorts(i).position(2) + 50 > y
                    y = oldPorts(i).position(2) + 50;
                end
            end

            % ---- 新增/更新 ----
            for i = 1:numel(newPorts)
                p = newPorts(i);
                name = strtrim(p.name);
                if isempty(name)
                    warnings{end+1} = '端口表中有空端口名，已跳过。'; %#ok<AGROW>
                    continue;
                end
                bp = [modelName '/' name];
                hit = find(strcmp(oldNames, name), 1);
                if ~isempty(hit)
                    % 已存在：只协调数据类型（与旧行为一致）
                    wantType = swb.PortSync.wantedDataType(p);
                    curType = oldPorts(hit).dataType;
                    if isempty(wantType) || strcmp(wantType, curType)
                        s.unchanged = s.unchanged + 1;
                        continue;
                    end
                    try
                        set_param(bp, 'OutDataTypeStr', wantType);
                    catch ME
                        warnings{end+1} = sprintf('端口 "%s" 数据类型更新失败: %s', name, ME.message); %#ok<AGROW>
                        s.unchanged = s.unchanged + 1;
                        continue;
                    end
                    actual = '';
                    try
                        actual = char(get_param(bp, 'OutDataTypeStr'));
                    catch
                    end
                    if strcmp(actual, wantType)
                        s.updated = s.updated + 1;
                        continue;
                    end
                    % set_param 未生效：删块重建并恢复位置（会丢线，已在 warnings 说明）
                    try
                        oldPos = oldPorts(hit).position;
                        if swb.PortSync.hasConnection(bp, isInput)
                            warnings{end+1} = sprintf( ...
                                '端口 "%s" 数据类型更新需删块重建，其原有连线随之丢失。', name); %#ok<AGROW>
                        end
                        delete_block(bp);
                        add_block(srcBlock, bp);
                        set_param(bp, 'Position', oldPos);
                        set_param(bp, 'OutDataTypeStr', wantType);
                        s.updated = s.updated + 1;
                    catch ME2
                        warnings{end+1} = sprintf('端口 "%s" 重建失败: %s', name, ME2.message); %#ok<AGROW>
                    end
                else
                    % 新增
                    try
                        add_block(srcBlock, bp);
                        set_param(bp, 'Position', [x, y, x + 30, y + 14]);
                        wantType = swb.PortSync.wantedDataType(p);
                        if ~isempty(wantType)
                            set_param(bp, 'OutDataTypeStr', wantType);
                        end
                        s.added = s.added + 1;
                        y = y + 50;
                    catch ME
                        warnings{end+1} = sprintf('新增端口 "%s" 失败: %s', name, ME.message); %#ok<AGROW>
                    end
                end
            end
        end

        function tf = hasConnection(blockPath, isInput)
            % 判断块是否已有连线（删块会丢线，需在 warnings 里说明）
            tf = false;
            try
                lh = get_param(blockPath, 'LineHandles');
                if isInput
                    tf = isfield(lh, 'Outport') && any(lh.Outport ~= -1);
                else
                    tf = isfield(lh, 'Inport') && any(lh.Inport ~= -1);
                end
            catch
                tf = false;
            end
        end

        function t = wantedDataType(p)
            % Excel 数据类型 → 需要写入的值；空 / Inherit: auto 表示不改
            t = '';
            if isfield(p, 'dataType')
                t = strtrim(char(p.dataType));
            end
            if strcmpi(t, 'Inherit: auto')
                t = '';
            end
        end
    end
end
