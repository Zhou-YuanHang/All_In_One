classdef ModelBuilder
    %SWB.MODELBUILDER 新建/配置 Simulink 模型（求解器、TLC、GenCodeOnly、数据字典、端口块、Code Mapping）。
    %   严格保留旧 NewModelApp.createModel 的流程顺序：
    %     名称校验 → 冲突处理（覆盖前备份 .slx.bak）→ new_system/open_system →
    %     求解器 → SystemTargetFile → GenCodeOnly → 数据字典（回读校验）→ 端口块 →
    %     Save#1 → Code Mapping → Save#2 → 按需关闭。
    %   服务层无 UI：冲突询问通过 opts.AskFcn 注入，日志通过 opts.Log（swb.Log）。
    %
    %   result = swb.ModelBuilder.create(opts)
    %   result = swb.ModelBuilder.configure(modelName, opts)
    %
    %   opts（均有默认值；同时接受 Schema.modelConfigDefaults 的 ModelName/ModelFolder 别名）：
    %     Name 'myModel', Folder '', SolverType 'Continuous'|'Discrete', SampleTime '0.01',
    %     SystemTargetFile 'ert.tlc', GenCodeOnly false, DictFile '', PortWorkbook '',
    %     ApplyCodeMapping false, OpenAfterCreate true,
    %     ConflictPolicy 'ask'|'overwrite'|'suffix'|'cancel', AskFcn [], Log []
    %     SaveAfter（仅 configure 用，默认 true）
    %
    %   AskFcn 约定：AskFcn('question', msg, {'覆盖','加数字后缀','取消'}, 2)
    %     返回选项下标（1/2/3）或选项文字；未提供 AskFcn 时沿用旧默认（加数字后缀）。
    %
    %   result 字段：ok modelName modelPath inputCount outputCount mapping(struct)
    %                warnings(cellstr) errorText cancelled dictFile systemTargetFile
    %                backupFile（覆盖策略下的 <name>.slx.bak 全路径；未覆盖时为空串）

    methods (Static)
        function d = defaults()
            % 默认选项（模型默认值来自 swb.Schema，保持单一事实来源）
            base = swb.Schema.modelConfigDefaults();
            d = struct( ...
                'Name', base.ModelName, ...
                'Folder', base.ModelFolder, ...
                'SolverType', base.SolverType, ...
                'SampleTime', base.SampleTime, ...
                'SystemTargetFile', base.SystemTargetFile, ...
                'GenCodeOnly', base.GenCodeOnly, ...
                'DictFile', base.DictFile, ...
                'PortWorkbook', '', ...
                'ApplyCodeMapping', base.ApplyCodeMapping, ...
                'OpenAfterCreate', base.OpenAfterCreate, ...
                'ConflictPolicy', base.ConflictPolicy, ...
                'AskFcn', [], ...
                'SaveAfter', true, ...
                'Log', []);
        end

        function result = create(opts)
            % 新建模型。非法参数 error('swb:...')；可恢复问题进 warnings。
            o = swb.ModelBuilder.normalize(opts);
            log = o.Log;
            result = swb.ModelBuilder.blankResult();

            % ---------- 1. 参数校验（非法参数直接 error） ----------
            if isempty(o.Name)
                error('swb:ModelBuilder:emptyName', '模型名称不能为空。');
            end
            if ~isvarname(o.Name)
                error('swb:ModelBuilder:badName', ...
                    '模型名称 "%s" 不是合法的 MATLAB 标识符（需字母开头，仅含字母/数字/下划线）。', o.Name);
            end
            if strcmp(o.SolverType, 'Discrete')
                st = str2double(o.SampleTime);
                if isnan(st) || ~isfinite(st) || st <= 0
                    error('swb:ModelBuilder:badSampleTime', ...
                        'SolverType=Discrete 时 SampleTime 必须是正数，收到 "%s"。', o.SampleTime);
                end
            end

            folder = o.Folder;
            if isempty(folder)
                folder = pwd;
            end
            if ~isfolder(folder)
                try
                    mkdir(folder);
                catch ME
                    error('swb:ModelBuilder:badFolder', '无法创建模型目录 "%s": %s', folder, ME.message);
                end
            end

            % ---------- 2. 名称冲突处理 ----------
            result.modelName = o.Name;
            [modelName, action, backup, cwarn, cancelled] = ...
                swb.ModelBuilder.resolveConflict(o, folder);
            result.warnings = [result.warnings, cwarn];
            % 覆盖策略下暴露备份文件路径（GUI 可据此提示/还原）；其它策略为空串
            if isfield(backup, 'file') && ~isempty(backup.file)
                result.backupFile = backup.file;
            end
            if cancelled
                result.cancelled = true;
                result.errorText = '已取消：模型已存在。';
                result.warnings{end+1} = result.errorText;
                if ~isempty(log)
                    log.info(result.errorText);
                end
                return;
            end
            result.modelName = modelName;
            modelPath = fullfile(folder, [modelName '.slx']);

            try
                % ---------- 3. 创建并打开 ----------
                if bdIsLoaded(modelName)
                    close_system(modelName, 0);
                end
                new_system(modelName);
                try
                    open_system(modelName);
                catch ME
                    result.warnings{end+1} = sprintf('无法打开模型窗口（可能无桌面环境）: %s', ME.message);
                end
                if ~isempty(log)
                    log.info('正在创建模型 "%s"...', modelName);
                end

                % ---------- 4. 求解器 ----------
                swb.ModelBuilder.applySolver(modelName, o);

                % ---------- 5. 系统目标文件（TLC） ----------
                [stf, tw] = swb.ModelBuilder.applyTargetFile(modelName, o.SystemTargetFile);
                result.warnings = [result.warnings, tw];
                result.systemTargetFile = stf;

                % ---------- 6. 仅生成代码（显式 on/off） ----------
                if o.GenCodeOnly
                    set_param(modelName, 'GenCodeOnly', 'on');
                else
                    set_param(modelName, 'GenCodeOnly', 'off');
                end

                % ---------- 7. 关联数据字典（回读校验，失败不致命） ----------
                [dictResolved, dw] = swb.ModelBuilder.linkDictionary(modelName, o.DictFile, folder);
                result.warnings = [result.warnings, dw];
                result.dictFile = dictResolved;

                % ---------- 8. 端口块 ----------
                inPorts = swb.PortTable.emptyPorts();
                outPorts = swb.PortTable.emptyPorts();
                hasCM = false;
                if ~isempty(o.PortWorkbook)
                    if ~isfile(o.PortWorkbook)
                        result.warnings{end+1} = sprintf( ...
                            '端口工作簿不存在，已跳过端口导入: %s', o.PortWorkbook);
                    else
                        [inPorts, outPorts, pinfo] = swb.PortTable.read(o.PortWorkbook);
                        result.warnings = [result.warnings, pinfo.warnings];
                        hasCM = swb.ModelBuilder.hasMappingColumns(inPorts, outPorts);
                        [nIn, nOut, pw] = swb.ModelBuilder.createPortBlocks(modelName, inPorts, outPorts);
                        result.inputCount = nIn;
                        result.outputCount = nOut;
                        result.warnings = [result.warnings, pw];
                        if ~isempty(log)
                            log.info('已创建端口块：%d 输入 / %d 输出。', nIn, nOut);
                        end
                    end
                end

                % ---------- 9. Save #1（Code Mapping 之前必须先落盘） ----------
                save_system(modelName, modelPath);
                savedOnce = true;
                actualPath = swb.ModelBuilder.currentModelPath(modelName, modelPath);
                if ~strcmpi(swb.ModelBuilder.canonicalDir(actualPath), ...
                        swb.ModelBuilder.canonicalDir(modelPath))
                    % 极少数情况下（例如搜索路径上有同名模型）保存目标可能被解析到别的文件，
                    % 后续 Save#2 会把内容写回那个文件——必须立即失败而不是继续。
                    error('swb:ModelBuilder:unexpectedModelFile', ...
                        ['保存后模型文件为 "%s"，与目标 "%s" 不一致。', ...
                         '通常是因为搜索路径上有同名模型，请改用其它模型名称。'], ...
                        actualPath, modelPath);
                end
                modelPath = actualPath;
                result.modelPath = modelPath;
                if ~isempty(log)
                    log.info('模型已保存: %s', modelPath);
                end

                % ---------- 10. Code Mapping（Save#1 之后才生效） ----------
                if o.ApplyCodeMapping
                    if hasCM
                        result.mapping = swb.CodeMapping.apply(modelName, inPorts, outPorts);
                        if ~isempty(result.mapping.initError)
                            result.warnings{end+1} = result.mapping.initError;
                        end
                        if ~isempty(result.mapping.failedInput) || ~isempty(result.mapping.failedOutput)
                            result.warnings{end+1} = sprintf( ...
                                'Code Mapping 失败端口：Input [%s] / Output [%s]。', ...
                                strjoin(result.mapping.failedInput, ', '), ...
                                strjoin(result.mapping.failedOutput, ', '));
                        end
                        % ---------- 11. Save #2 ----------
                        save_system(modelName);
                    else
                        result.mapping = swb.CodeMapping.blankStats();
                        result.mapping.initError = ['端口表没有 Code Mapping 列', ...
                            '（StorageClass/Identifier/HeaderFile/DefinitionFile 全空），已跳过。'];
                        result.warnings{end+1} = result.mapping.initError;
                    end
                end

                % ---------- 12. 按需关闭 ----------
                if ~o.ApplyCodeMapping && isempty(result.mapping.initError)
                    result.mapping.initError = '未请求 Code Mapping（ApplyCodeMapping=false）。';
                end
                if ~o.OpenAfterCreate && bdIsLoaded(modelName)
                    close_system(modelName, 0);
                end

                result.ok = true;
                if ~isempty(log)
                    log.info('模型 "%s" 创建完成：%d 输入 / %d 输出。', ...
                        modelName, result.inputCount, result.outputCount);
                end
            catch ME
                % 失败清理：关模型 → 有备份则恢复，否则删半成品
                result.ok = false;
                result.errorText = ME.message;
                try
                    if bdIsLoaded(modelName)
                        close_system(modelName, 0);
                    end
                catch
                end
                try
                    target = modelPath;
                    if isfield(backup, 'file') && ~isempty(backup.file) && isfile(backup.file)
                        copyfile(backup.file, backup.original);
                        delete(backup.file);
                        if isfile(target) && ~strcmpi(target, backup.original)
                            delete(target);
                        end
                        result.warnings{end+1} = sprintf( ...
                            '创建失败，已从备份恢复原模型 "%s"。', backup.original);
                    elseif ~isempty(target) && isfile(target)
                        delete(target);
                        result.warnings{end+1} = sprintf('创建失败，已删除半成品 "%s"。', target);
                    end
                catch ME2
                    result.warnings{end+1} = sprintf('失败清理未完成: %s', ME2.message);
                end
                if ~isempty(log)
                    log.err('模型创建失败: %s', ME.message);
                end
            end
            if exist('savedOnce', 'var') && savedOnce
                result.modelPath = swb.ModelBuilder.currentModelPath(modelName, result.modelPath);
            end
        end

        function result = configure(modelName, opts)
            % 对已存在模型应用求解器/TLC/GenCodeOnly/字典配置（不改端口）。
            o = swb.ModelBuilder.normalize(opts);
            result = swb.ModelBuilder.blankResult();
            modelName = strtrim(char(modelName));
            result.modelName = modelName;
            if isempty(modelName) || ~isvarname(modelName)
                error('swb:ModelBuilder:badName', ...
                    '模型名称 "%s" 不是合法的 MATLAB 标识符。', modelName);
            end
            if strcmp(o.SolverType, 'Discrete')
                st = str2double(o.SampleTime);
                if isnan(st) || ~isfinite(st) || st <= 0
                    error('swb:ModelBuilder:badSampleTime', ...
                        'SolverType=Discrete 时 SampleTime 必须是正数，收到 "%s"。', o.SampleTime);
                end
            end

            wasLoaded = bdIsLoaded(modelName);
            if ~wasLoaded
                loaded = false;
                loadErr = '';
                % 优先按 opts.Folder 定位模型文件（模型可能不在 MATLAB 搜索路径上）
                if ~isempty(o.Folder)
                    cand = fullfile(o.Folder, [modelName '.slx']);
                    if isfile(cand)
                        try
                            load_system(cand);
                            loaded = true;
                        catch ME
                            loadErr = ME.message;
                        end
                    end
                end
                if ~loaded
                    try
                        load_system(modelName);
                        loaded = true;
                    catch ME
                        loadErr = ME.message;
                    end
                end
                if ~loaded
                    result.ok = false;
                    result.errorText = sprintf('无法加载模型 "%s": %s', modelName, loadErr);
                    result.warnings{end+1} = result.errorText;
                    return;
                end
            end

            try
                folder = '';
                try
                    f = char(get_param(modelName, 'FileName'));
                    if ~isempty(f)
                        folder = fileparts(f);
                    end
                catch
                end
                if isempty(folder)
                    folder = pwd;
                end

                swb.ModelBuilder.applySolver(modelName, o);
                [stf, tw] = swb.ModelBuilder.applyTargetFile(modelName, o.SystemTargetFile);
                result.warnings = [result.warnings, tw];
                result.systemTargetFile = stf;
                if o.GenCodeOnly
                    set_param(modelName, 'GenCodeOnly', 'on');
                else
                    set_param(modelName, 'GenCodeOnly', 'off');
                end
                [dictResolved, dw] = swb.ModelBuilder.linkDictionary(modelName, o.DictFile, folder);
                result.warnings = [result.warnings, dw];
                result.dictFile = dictResolved;
                result.ok = true;
            catch ME
                result.ok = false;
                result.errorText = sprintf('模型配置失败: %s', ME.message);
                result.warnings{end+1} = result.errorText;
            end

            if bdIsLoaded(modelName)
                if result.ok && o.SaveAfter
                    try
                        save_system(modelName);
                        result.modelPath = swb.ModelBuilder.currentModelPath(modelName, '');
                    catch ME2
                        result.ok = false;
                        result.errorText = sprintf('保存模型失败: %s', ME2.message);
                        result.warnings{end+1} = result.errorText;
                    end
                end
                if ~wasLoaded
                    try
                        close_system(modelName, 0);
                    catch
                    end
                end
            end
            if ~isempty(o.Log) && result.ok
                o.Log.info('模型 "%s" 配置已更新。', modelName);
            end
        end
    end

    methods (Static, Access = private)
        % ---------- 选项归一化 ----------
        function o = normalize(opts)
            o = swb.ModelBuilder.defaults();
            if nargin < 1 || isempty(opts)
                return;
            end
            if ~isstruct(opts)
                error('swb:ModelBuilder:badOpts', 'opts 必须是结构体。');
            end
            % 兼容 Schema.modelConfigDefaults 的字段名
            alias = struct('ModelName', 'Name', 'ModelFolder', 'Folder');
            names = fieldnames(opts);
            for k = 1:numel(names)
                f = names{k};
                if isfield(alias, f)
                    f = alias.(f);
                end
                if isfield(o, f)
                    o.(f) = opts.(names{k});
                end
            end
            o.Name = strtrim(char(o.Name));
            o.Folder = strtrim(char(o.Folder));
            o.SampleTime = strtrim(char(o.SampleTime));
            o.SystemTargetFile = strtrim(char(o.SystemTargetFile));
            o.DictFile = strtrim(char(o.DictFile));
            o.PortWorkbook = strtrim(char(o.PortWorkbook));
            o.SolverType = swb.ModelBuilder.normalizeSolverType(o.SolverType);
            o.GenCodeOnly = swb.ModelBuilder.asTF(o.GenCodeOnly);
            o.ApplyCodeMapping = swb.ModelBuilder.asTF(o.ApplyCodeMapping);
            o.OpenAfterCreate = swb.ModelBuilder.asTF(o.OpenAfterCreate);
            o.SaveAfter = swb.ModelBuilder.asTF(o.SaveAfter);
            o.ConflictPolicy = lower(strtrim(char(o.ConflictPolicy)));
            if ~any(strcmp(o.ConflictPolicy, {'ask', 'overwrite', 'suffix', 'cancel'}))
                error('swb:ModelBuilder:badConflictPolicy', ...
                    'ConflictPolicy 只能是 ask/overwrite/suffix/cancel，收到 "%s"。', o.ConflictPolicy);
            end
            if ~isempty(o.Log) && ~isa(o.Log, 'swb.Log')
                error('swb:ModelBuilder:badLog', 'opts.Log 必须是 swb.Log 实例。');
            end
        end

        function t = normalizeSolverType(t)
            t = strtrim(char(t));
            switch lower(t)
                case {'continuous', '连续'}
                    t = 'Continuous';
                case {'discrete', '离散'}
                    t = 'Discrete';
                otherwise
                    error('swb:ModelBuilder:badSolverType', ...
                        'SolverType 只能是 Continuous 或 Discrete，收到 "%s"。', t);
            end
        end

        function tf = asTF(v)
            if islogical(v)
                tf = v;
            elseif isnumeric(v)
                tf = v ~= 0;
            elseif ischar(v) || isstring(v)
                tf = any(strcmpi(strtrim(char(v)), {'on', 'true', 'yes', '1'}));
            else
                tf = false;
            end
        end

        function result = blankResult()
            result = struct('ok', false, 'modelName', '', 'modelPath', '', ...
                            'inputCount', 0, 'outputCount', 0, ...
                            'mapping', swb.CodeMapping.blankStats(), ...
                            'warnings', {{}}, 'errorText', '', 'cancelled', false, ...
                            'dictFile', '', 'systemTargetFile', '', 'backupFile', '');
        end

        % ---------- 冲突处理 ----------
        function [modelName, action, backup, warnings, cancelled] = resolveConflict(o, folder)
            modelName = o.Name;
            action = 'new';
            backup = struct('file', '', 'original', '');
            warnings = {};
            cancelled = false;

            existingFile = swb.ModelBuilder.existingModelFile(folder, modelName);

            % 其它目录/搜索路径上的同名模型只提示、绝不改动（防误删用户工程文件）。
            % 这一段必须在「无冲突」提前 return 之前：目标目录没有文件时也可能有同名外部模型。
            externalFile = swb.ModelBuilder.externalModelFile(folder, modelName);
            if ~isempty(externalFile)
                warnings{end+1} = sprintf( ...
                    '搜索路径上另有同名模型 "%s"；本次不会改动它，新模型只写入目标目录。', externalFile);
            end

            if isempty(existingFile) && ~bdIsLoaded(modelName)
                return;
            end

            policy = o.ConflictPolicy;
            if strcmp(policy, 'ask')
                if ~isempty(o.AskFcn)
                    answer = o.AskFcn('question', ...
                        swb.ModelBuilder.conflictMessage(modelName, existingFile), ...
                        {'覆盖', '加数字后缀', '取消'}, 2);
                    policy = swb.ModelBuilder.answerToPolicy(answer);
                else
                    % 无询问回调（无 UI / 无头流水线）：沿用旧默认 DefaultOption=2
                    policy = 'suffix';
                    warnings{end+1} = sprintf( ...
                        '模型 "%s" 已存在且未提供 AskFcn，按默认策略加数字后缀。', modelName);
                end
            end

            switch policy
                case 'cancel'
                    cancelled = true;
                    action = 'cancel';
                    return;
                case 'overwrite'
                    % 覆盖：先关掉内存中的同名模型，再备份文件（修正旧代码直接删的缺陷）
                    if bdIsLoaded(modelName)
                        close_system(modelName, 0);
                    end
                    existingFile = swb.ModelBuilder.existingModelFile(folder, modelName);
                    if ~isempty(existingFile) && isfile(existingFile)
                        bak = [existingFile '.bak'];
                        try
                            copyfile(existingFile, bak, 'f');
                            backup = struct('file', bak, 'original', existingFile);
                            delete(existingFile);
                        catch ME
                            error('swb:ModelBuilder:backupFailed', ...
                                '覆盖前备份 "%s" 失败: %s', existingFile, ME.message);
                        end
                        warnings{end+1} = sprintf( ...
                            '已存在模型已备份为 "%s"，随后被新模型替换。', bak);
                    end
                    action = 'overwrite';
                case 'suffix'
                    n = 1;
                    while true
                        cand = sprintf('%s%d', o.Name, n);
                        if ~bdIsLoaded(cand) && ...
                                isempty(swb.ModelBuilder.existingModelFile(folder, cand))
                            modelName = cand;
                            break;
                        end
                        n = n + 1;
                        if n > 10000
                            error('swb:ModelBuilder:suffixFailed', '无法为模型 "%s" 找到可用的数字后缀名。', o.Name);
                        end
                    end
                    action = 'suffix';
                    warnings{end+1} = sprintf('模型 "%s" 已存在，已改用 "%s"。', o.Name, modelName);
            end
        end

        function p = existingModelFile(folder, name)
            % 目标目录内是否已有同名模型文件。
            % 注意：这里只能看「目标目录」。绝不能把 pwd / 搜索路径上的同名模型当成
            % 覆盖目标——旧实现会因此把用户其它工程里的同名 .slx 备份后删除（数据丢失）。
            p = '';
            if isempty(folder)
                return;
            end
            exts = {'.slx', '.mdl'};
            for e = 1:numel(exts)
                cand = fullfile(folder, [name exts{e}]);
                if isfile(cand)
                    p = cand;
                    return;
                end
            end
        end

        function w = externalModelFile(folder, name)
            % 搜索路径上（目标目录之外）是否有同名模型文件。只用于提示，绝不改动。
            w = '';
            try
                cand = which(name);
            catch
                return;
            end
            if isempty(cand) || ~isfile(cand)
                return;
            end
            candDir = fileparts(cand);
            if isempty(folder) || ~strcmpi(swb.ModelBuilder.canonicalDir(candDir), ...
                    swb.ModelBuilder.canonicalDir(folder))
                w = char(cand);
            end
        end

        function msg = conflictMessage(modelName, existingFile)
            if ~isempty(existingFile)
                state = sprintf('文件 "%s" 已存在。', existingFile);
            else
                state = '模型已在工作区中加载。';
            end
            msg = sprintf('模型 "%s" %s%s请选择处理方式（覆盖前会自动备份 .bak）。', ...
                modelName, state, newline);
        end

        function policy = answerToPolicy(answer)
            policy = 'cancel';
            if isnumeric(answer) || islogical(answer)
                idx = double(answer);
                opts = {'overwrite', 'suffix', 'cancel'};
                if isscalar(idx) && idx >= 1 && idx <= numel(opts) && idx == fix(idx)
                    policy = opts{idx};
                end
                return;
            end
            if ischar(answer) || isstring(answer)
                switch lower(strtrim(char(answer)))
                    case {'覆盖', 'overwrite'}
                        policy = 'overwrite';
                    case {'加数字后缀', 'suffix'}
                        policy = 'suffix';
                    otherwise
                        policy = 'cancel';
                end
            end
        end

        % ---------- 模型参数 ----------
        function applySolver(modelName, o)
            if strcmp(o.SolverType, 'Discrete')
                st = str2double(o.SampleTime);
                set_param(modelName, 'SolverType', 'Fixed-step', ...
                    'Solver', 'FixedStepDiscrete', 'FixedStep', num2str(st));
            else
                set_param(modelName, 'SolverType', 'Variable-step', ...
                    'Solver', 'VariableStepAuto');
            end
        end

        function [stf, warnings] = applyTargetFile(modelName, tlc)
            % 系统目标文件：全路径先校验存在性并取 basename；失败给明确 warning 并跳过
            warnings = {};
            stf = '';
            if isempty(tlc)
                stf = char(get_param(modelName, 'SystemTargetFile'));
                return;
            end
            [dirPart, base, ext] = fileparts(tlc);
            tlcName = tlc;
            if ~isempty(dirPart)
                fullFile = tlc;
                if isempty(ext)
                    fullFile = [tlc '.tlc'];
                end
                if ~isfile(fullFile)
                    warnings{end+1} = sprintf( ...
                        '系统目标文件不存在，已跳过设置 SystemTargetFile: %s', tlc);
                    return;
                end
                [~, base, ext] = fileparts(fullFile);
                tlcName = [base ext];
            end
            addedPath = '';
            try
                set_param(modelName, 'SystemTargetFile', tlcName);
            catch ME
                % 自定义 TLC 不在搜索路径上：临时加入目录重试一次
                retryOk = false;
                if ~isempty(dirPart) && isfolder(dirPart)
                    try
                        addpath(dirPart);
                        addedPath = dirPart;
                        set_param(modelName, 'SystemTargetFile', tlcName);
                        retryOk = true;
                    catch
                        retryOk = false;
                    end
                end
                if ~retryOk
                    if ~isempty(addedPath)
                        try
                            rmpath(addedPath);
                        catch
                        end
                    end
                    warnings{end+1} = sprintf( ...
                        '设置系统目标文件 "%s" 失败，已跳过: %s', tlcName, ME.message);
                    try
                        stf = char(get_param(modelName, 'SystemTargetFile'));
                    catch
                        stf = '';
                    end
                    return;
                end
            end
            % 自定义 TLC 的目录保留在路径上（后续生成代码时还要用）
            if ~isempty(addedPath)
                warnings{end+1} = sprintf( ...
                    '系统目标文件来自 "%s"，已将其加入 MATLAB 搜索路径。', addedPath);
            end
            try
                stf = char(get_param(modelName, 'SystemTargetFile'));
            catch
                stf = tlcName;
            end
        end

        function [linkedFile, warnings] = linkDictionary(modelName, dictFile, modelFolder)
            % 关联数据字典：解析路径 → 必要时把字典目录加入搜索路径 → set_param → get_param 回读
            linkedFile = '';
            warnings = {};
            if isempty(dictFile)
                return;
            end
            fullDict = swb.ModelBuilder.resolveDictPath(dictFile, modelFolder);
            if isempty(fullDict)
                warnings{end+1} = sprintf('数据字典文件不存在，已跳过关联: %s', dictFile);
                return;
            end
            [dictDir, dictBase, dictExt] = fileparts(fullDict);
            dictName = [dictBase dictExt];

            addedPath = false;
            if ~swb.ModelBuilder.onPath(dictDir)
                try
                    addpath(dictDir);
                    addedPath = true;
                catch
                end
            end
            try
                set_param(modelName, 'DataDictionary', dictName);
            catch ME
                warnings{end+1} = sprintf('关联数据字典 "%s" 失败: %s', dictName, ME.message);
                return;
            end
            actual = '';
            try
                actual = strtrim(char(get_param(modelName, 'DataDictionary')));
            catch
            end
            if strcmp(actual, dictName)
                linkedFile = fullDict;
            else
                warnings{end+1} = sprintf( ...
                    '数据字典关联回读不一致（期望 "%s"，实际 "%s"），请检查模型/字典目录。', ...
                    dictName, actual);
                if ~isempty(actual)
                    linkedFile = fullfile(dictDir, actual);
                end
            end
            % 字典目录就是模型目录时无需保留搜索路径
            if addedPath && strcmp(swb.ModelBuilder.canonicalDir(dictDir), ...
                    swb.ModelBuilder.canonicalDir(modelFolder))
                try
                    rmpath(dictDir);
                catch
                end
            end
        end

        function p = resolveDictPath(dictFile, modelFolder)
            p = '';
            [fd, fn, fe] = fileparts(char(dictFile));
            if isempty(fn)
                return;
            end
            if isempty(fe)
                fe = '.sldd';
            end
            if ~isempty(fd)
                if swb.ModelBuilder.isAbsolute(fd) || isfolder(fd)
                    bases = {fd};
                else
                    bases = {fullfile(modelFolder, fd), fullfile(pwd, fd)};
                end
            else
                bases = {modelFolder, pwd};
            end
            for i = 1:numel(bases)
                cand = fullfile(bases{i}, [fn fe]);
                if isfile(cand)
                    p = cand;
                    return;
                end
            end
        end

        % ---------- 端口块 ----------
        function tf = hasMappingColumns(inPorts, outPorts)
            tf = false;
            all = [inPorts, outPorts];
            for i = 1:numel(all)
                p = all(i);
                if ~isempty(strtrim(p.storageClass)) || ~isempty(strtrim(p.identifier)) || ...
                        ~isempty(strtrim(p.headerFile)) || ~isempty(strtrim(p.definitionFile))
                    tf = true;
                    return;
                end
            end
        end

        function [nIn, nOut, warnings] = createPortBlocks(modelName, inPorts, outPorts)
            % 创建 Inport/Outport 块：x=60/500，y 从 80 起 50 间距；单端口失败只记录不中断
            nIn = 0;
            nOut = 0;
            warnings = {};
            y = 80;
            for i = 1:numel(inPorts)
                p = inPorts(i);
                if isempty(strtrim(p.name))
                    continue;
                end
                bp = [modelName '/' strtrim(p.name)];
                try
                    add_block('simulink/Sources/In1', bp);
                    set_param(bp, 'Position', [60, y, 90, y + 14]);
                    dt = swb.ModelBuilder.portDataType(p);
                    if ~isempty(dt)
                        set_param(bp, 'OutDataTypeStr', dt);
                    end
                    nIn = nIn + 1;
                    y = y + 50;
                catch ME
                    warnings{end+1} = sprintf('输入端口 "%s" 创建失败: %s', p.name, ME.message); %#ok<AGROW>
                end
            end
            y = 80;
            for i = 1:numel(outPorts)
                p = outPorts(i);
                if isempty(strtrim(p.name))
                    continue;
                end
                bp = [modelName '/' strtrim(p.name)];
                try
                    add_block('simulink/Sinks/Out1', bp);
                    set_param(bp, 'Position', [500, y, 530, y + 14]);
                    dt = swb.ModelBuilder.portDataType(p);
                    if ~isempty(dt)
                        set_param(bp, 'OutDataTypeStr', dt);
                    end
                    nOut = nOut + 1;
                    y = y + 50;
                catch ME
                    warnings{end+1} = sprintf('输出端口 "%s" 创建失败: %s', p.name, ME.message); %#ok<AGROW>
                end
            end
        end

        function dt = portDataType(p)
            % 空 / Inherit: auto 表示不显式设置数据类型
            dt = '';
            if isfield(p, 'dataType')
                dt = strtrim(char(p.dataType));
            end
            if strcmpi(dt, 'Inherit: auto')
                dt = '';
            end
        end

        % ---------- 杂项 ----------
        function p = currentModelPath(modelName, fallback)
            p = fallback;
            try
                f = char(get_param(modelName, 'FileName'));
                if ~isempty(f)
                    p = f;
                end
            catch
            end
        end

        function tf = isAbsolute(p)
            tf = false;
            p = char(p);
            if isempty(p)
                return;
            end
            tf = ~isempty(regexp(p, '^[A-Za-z]:[\\/]', 'once')) || ...
                 p(1) == '/' || p(1) == '\';
        end

        function d = canonicalDir(p)
            d = char(p);
            if isempty(d)
                return;
            end
            d = strrep(d, '/', filesep);
            d = strrep(d, '\', filesep);
            while numel(d) > 1 && d(end) == filesep
                d = d(1:end-1);
            end
            if ispc
                d = lower(d);
            end
        end

        function tf = onPath(dirPath)
            tf = false;
            if isempty(dirPath)
                return;
            end
            try
                parts = strsplit(path, pathsep);
                target = swb.ModelBuilder.canonicalDir(dirPath);
                for i = 1:numel(parts)
                    if strcmp(swb.ModelBuilder.canonicalDir(parts{i}), target)
                        tf = true;
                        return;
                    end
                end
            catch
                tf = false;
            end
        end
    end
end
