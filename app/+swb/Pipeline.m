classdef Pipeline
    %SWB.PIPELINE 一键流水线编排：读取 → 校验 → 生成对象脚本 → 写入 .sldd → 创建/更新 .slx。
    %   只编排，不实现业务；每一步调用 swb 服务层，失败可中止或继续。
    %
    %   result = swb.Pipeline.run(cfg)
    %   cfg 字段（缺省有默认）：
    %     DictWorkbook  数据字典工作簿路径（空 = 跳过字典步骤）
    %     PortWorkbook  端口工作簿路径（空 = 建空模型）
    %     Sheets        cellstr，字典表选择（空 = 全部可导入表）
    %     ScriptFile    对象脚本输出路径（空 = <workbook>_objects.m）
    %     SlddFile      数据字典输出路径（空 = <workbook>.sldd）
    %     Model         swb.Schema.modelConfigDefaults() 结构；也接受 ModelBuilder 的
    %                   Name/Folder 字段名（两种字段名互通，Name 为空 = 跳过建模）
    %     ValidateFirst 校验失败时中止（默认 true）
    %     ConfirmWrite  写字典前调用 ConfirmFcn 确认（默认 false）
    %     ConfirmFcn    @(msg) -> '写入' | '取消'
    %     CleanExtra    写字典时删除多余本地条目（默认 false，危险）
    %     StopOnError   某步失败即中止（默认 true）
    %     Log           swb.Log 实例（默认新建）
    %   result 字段：ok, steps(struct array name/status/detail), issues, dictStats,
    %                modelResult, artifacts(scriptFile/slddFile/modelFile), summary,
    %                warnings, errorText

    methods (Static)
        function result = run(cfg)
            result = swb.Pipeline.blankResult();
            try
                cfg = swb.Pipeline.normalize(cfg);
            catch ME
                result.errorText = ME.message;
                return;
            end
            log = cfg.Log;
            log.section('一键流水线开始');
            ok = true;
            slddWritten = false;
            slddFile = '';
            scriptFile = '';

            dictPath = char(cfg.DictWorkbook);
            if isempty(strtrim(dictPath)) || ~isfile(dictPath)
                result.steps(end+1) = swb.Pipeline.step('字典工作簿', 'skipped', '未提供有效的字典工作簿');
                log.warn('未提供字典工作簿，跳过字典相关步骤。');
            else
                [dictDir, dictBase] = fileparts(dictPath);
                scriptFile = char(cfg.ScriptFile);
                if isempty(strtrim(scriptFile))
                    scriptFile = fullfile(dictDir, [dictBase '_objects.m']);
                end
                slddFile = char(cfg.SlddFile);
                if isempty(strtrim(slddFile))
                    slddFile = fullfile(dictDir, [dictBase '.sldd']);
                end

                % ---- 1. 校验 ----
                if cfg.ValidateFirst
                    try
                        issues = swb.Validator.run(dictPath, cfg.Sheets);
                        result.issues = issues;
                        nErr = swb.Issue.count(issues, 'error');
                        nWarn = swb.Issue.count(issues, 'warning');
                        detail = sprintf('%d 错误 / %d 警告', nErr, nWarn);
                        if nErr > 0
                            result.steps(end+1) = swb.Pipeline.step('校验数据字典', 'failed', detail);
                            log.err('校验未通过：%s', detail);
                            if cfg.StopOnError
                                result = swb.Pipeline.finish(result, cfg, false, '数据字典校验未通过');
                                return;
                            end
                            ok = false;
                        else
                            result.steps(end+1) = swb.Pipeline.step('校验数据字典', 'ok', detail);
                            log.info('校验通过：%s', detail);
                        end
                    catch ME
                        result.steps(end+1) = swb.Pipeline.step('校验数据字典', 'failed', ME.message);
                        log.err('校验异常：%s', ME.message);
                        if cfg.StopOnError
                            result = swb.Pipeline.finish(result, cfg, false, ME.message);
                            return;
                        end
                        ok = false;
                    end
                else
                    result.steps(end+1) = swb.Pipeline.step('校验数据字典', 'skipped', '已关闭执行前校验');
                end

                % ---- 2. 生成对象脚本 ----
                build = [];
                try
                    scriptDir = fileparts(scriptFile);
                    if ~isempty(scriptDir) && ~isfolder(scriptDir)
                        mkdir(scriptDir);
                    end
                    build = swb.ScriptBuilder.build(dictPath, cfg.Sheets, scriptFile);
                    result.artifacts.scriptFile = build.writtenFile;
                    result.steps(end+1) = swb.Pipeline.step('生成对象脚本', 'ok', ...
                        sprintf('%d 个对象 → %s', numel(build.objects), build.writtenFile));
                    log.info('对象脚本：%d 个对象，%d 个枚举文件。', numel(build.objects), numel(build.enumFiles));
                catch ME
                    result.steps(end+1) = swb.Pipeline.step('生成对象脚本', 'failed', ME.message);
                    log.err('生成对象脚本失败：%s', ME.message);
                    if cfg.StopOnError
                        result = swb.Pipeline.finish(result, cfg, false, ME.message);
                        return;
                    end
                    ok = false;
                end

                % ---- 3. 写入 .sldd ----
                if isempty(build) || isempty(strtrim(slddFile))
                    result.steps(end+1) = swb.Pipeline.step('写入数据字典', 'skipped', '缺少脚本或字典路径');
                else
                    cancelled = false;
                    try
                        slddDir = fileparts(slddFile);
                        if ~isempty(slddDir) && ~isfolder(slddDir)
                            mkdir(slddDir);
                        end
                        if cfg.ConfirmWrite && ~isempty(cfg.ConfirmFcn)
                            answer = cfg.ConfirmFcn(sprintf('即将把 %d 个对象写入：\n%s', numel(build.objects), slddFile));
                            if ~strcmp(answer, '写入') && ~strcmp(answer, 'yes')
                                cancelled = true;
                            end
                        end
                    catch ME
                        cancelled = false;
                        log.warn('确认回调异常（继续写入）：%s', ME.message);
                    end
                    if cancelled
                        result.steps(end+1) = swb.Pipeline.step('写入数据字典', 'skipped', '用户取消');
                        log.warn('用户取消写入数据字典。');
                    else
                        try
                            opts = struct('CleanExtra', logical(cfg.CleanExtra), ...
                                          'ConfirmFcn', cfg.ConfirmFcn, 'Log', log, 'Verify', true);
                            stats = swb.Dictionary.writeScript(slddFile, build.text, opts);
                            result.dictStats = stats;
                            result.artifacts.slddFile = slddFile;
                            slddWritten = true;
                            detail = sprintf('+%d ~%d -%d x%d（共 %d 条）', ...
                                stats.added, stats.updated, stats.skipped, stats.failed, stats.totalAfter);
                            if stats.failed > 0
                                result.steps(end+1) = swb.Pipeline.step('写入数据字典', 'warn', detail);
                                log.warn('写入完成但有失败项：%s', detail);
                                ok = false;
                            else
                                result.steps(end+1) = swb.Pipeline.step('写入数据字典', 'ok', detail);
                                log.info('写入数据字典：%s', detail);
                            end
                        catch ME
                            result.steps(end+1) = swb.Pipeline.step('写入数据字典', 'failed', ME.message);
                            log.err('写入数据字典失败：%s', ME.message);
                            if cfg.StopOnError
                                result = swb.Pipeline.finish(result, cfg, false, ME.message);
                                return;
                            end
                            ok = false;
                        end
                    end
                end
            end

            % ---- 4. 创建/更新模型 ----
            modelCfg = cfg.Model;
            % 兼容 swb.Schema.modelConfigDefaults() 的字段名（ModelName/ModelFolder），
            % 与 ModelBuilder 的 opts 规范（Name/Folder）对齐，避免误判“未指定模型名称”。
            if isstruct(modelCfg) && ~isfield(modelCfg, 'Name') && isfield(modelCfg, 'ModelName')
                modelCfg.Name = modelCfg.ModelName;
            end
            if isstruct(modelCfg) && ~isfield(modelCfg, 'Folder') && isfield(modelCfg, 'ModelFolder')
                modelCfg.Folder = modelCfg.ModelFolder;
            end
            modelName = '';
            if isstruct(modelCfg) && isfield(modelCfg, 'Name')
                modelName = strtrim(char(modelCfg.Name));
            end
            if isempty(modelName)
                result.steps(end+1) = swb.Pipeline.step('创建模型', 'skipped', '未指定模型名称');
                log.warn('未指定模型名称，跳过建模步骤。');
            else
                try
                    modelCfg = swb.Pipeline.fillModelDefaults(modelCfg, cfg, slddWritten, slddFile, log);
                    if ~isempty(cfg.PortWorkbook) && isempty(strtrim(char(modelCfg.PortWorkbook)))
                        modelCfg.PortWorkbook = char(cfg.PortWorkbook);
                    end
                    if ~isempty(cfg.AskFcn) && isempty(modelCfg.AskFcn)
                        modelCfg.AskFcn = cfg.AskFcn;
                    end
                    mr = swb.ModelBuilder.create(modelCfg);
                    result.modelResult = mr;
                    if mr.cancelled
                        result.steps(end+1) = swb.Pipeline.step('创建模型', 'skipped', '用户取消');
                        log.warn('用户取消创建模型。');
                    elseif mr.ok
                        result.artifacts.modelFile = mr.modelPath;
                        detail = sprintf('%s（输入 %d / 输出 %d）', mr.modelName, mr.inputCount, mr.outputCount);
                        if isstruct(mr.mapping) && isfield(mr.mapping, 'initialized') && mr.mapping.initialized
                            detail = sprintf('%s + Code Mapping', detail);
                        end
                        result.steps(end+1) = swb.Pipeline.step('创建模型', 'ok', detail);
                        log.info('创建模型：%s', detail);
                    else
                        result.steps(end+1) = swb.Pipeline.step('创建模型', 'failed', mr.errorText);
                        log.err('创建模型失败：%s', mr.errorText);
                        ok = false;
                    end
                    if ~isempty(mr.warnings)
                        result.warnings = [result.warnings, mr.warnings(:)'];
                    end
                catch ME
                    result.steps(end+1) = swb.Pipeline.step('创建模型', 'failed', ME.message);
                    log.err('创建模型异常：%s', ME.message);
                    ok = false;
                end
            end

            if ~isempty(build) && ~isempty(build.warnings)
                result.warnings = [result.warnings, build.warnings(:)'];
            end
            result = swb.Pipeline.finish(result, cfg, ok, '');
        end
    end

    methods (Static, Access = private)
        function result = finish(result, cfg, ok, errorText)
            result.ok = logical(ok) && ~swb.Pipeline.hasFailedStep(result.steps);
            if ~isempty(errorText)
                result.ok = false;
                result.errorText = errorText;
            end
            result.summary = swb.Pipeline.buildSummary(result, cfg);
            if result.ok
                cfg.Log.info('流水线完成。');
            else
                cfg.Log.warn('流水线结束（存在失败/告警）。');
            end
        end

        function tf = hasFailedStep(steps)
            tf = any(strcmp({steps.status}, 'failed'));
        end

        function cfg = normalize(cfg)
            defaults = struct( ...
                'DictWorkbook', '', 'PortWorkbook', '', 'Sheets', {{}}, ...
                'ScriptFile', '', 'SlddFile', '', 'Model', [], ...
                'ValidateFirst', true, 'ConfirmWrite', false, 'ConfirmFcn', [], ...
                'AskFcn', [], 'CleanExtra', false, 'StopOnError', true, 'Log', []);
            if nargin < 1 || isempty(cfg)
                cfg = defaults;
            end
            f = fieldnames(defaults);
            for k = 1:numel(f)
                if ~isfield(cfg, f{k})
                    cfg.(f{k}) = defaults.(f{k});
                end
            end
            if isempty(cfg.Log) || ~isa(cfg.Log, 'swb.Log')
                cfg.Log = swb.Log();
            end
        end

        function mc = fillModelDefaults(mc, cfg, slddWritten, slddFile, log)
            def = swb.Schema.modelConfigDefaults();
            f = fieldnames(def);
            for k = 1:numel(f)
                if ~isfield(mc, f{k})
                    mc.(f{k}) = def.(f{k});
                end
            end
            if isempty(strtrim(char(mc.Folder)))
                if ~isempty(cfg.DictWorkbook)
                    mc.Folder = fileparts(char(cfg.DictWorkbook));
                else
                    mc.Folder = pwd;
                end
            end
            if slddWritten && isempty(strtrim(char(mc.DictFile)))
                mc.DictFile = slddFile;
            end
            if ~isfield(mc, 'Log') || isempty(mc.Log)
                mc.Log = log;
            end
            if ~isfield(mc, 'AskFcn') || isempty(mc.AskFcn)
                mc.AskFcn = cfg.AskFcn;
            end
        end

        function s = step(name, status, detail)
            s = struct('name', char(name), 'status', char(status), 'detail', char(detail));
        end

        function result = blankResult()
            result = struct( ...
                'ok', false, ...
                'steps', struct('name', {}, 'status', {}, 'detail', {}), ...
                'issues', swb.Issue.empty(), ...
                'dictStats', [], ...
                'modelResult', [], ...
                'artifacts', struct('scriptFile', '', 'slddFile', '', 'modelFile', ''), ...
                'summary', '', 'warnings', {{}}, 'errorText', '');
        end

        function txt = buildSummary(result, cfg)
            lines = {};
            lines{end+1} = sprintf('流水线结果：%s', swb.Pipeline.ternary(result.ok, '成功', '未完全成功'));
            if ~isempty(result.steps)
                for k = 1:numel(result.steps)
                    st = result.steps(k);
                    lines{end+1} = sprintf('  [%s] %s — %s', upper(st.status), st.name, st.detail); %#ok<AGROW>
                end
            end
            if ~isempty(result.dictStats)
                d = result.dictStats;
                lines{end+1} = sprintf('字典：+%d ~%d -%d x%d', d.added, d.updated, d.skipped, d.failed);
            end
            if isstruct(result.modelResult)
                mr = result.modelResult;
                lines{end+1} = sprintf('模型：%s（%d 输入 / %d 输出）', char(mr.modelName), mr.inputCount, mr.outputCount);
            end
            if ~isempty(result.artifacts.scriptFile)
                lines{end+1} = sprintf('对象脚本：%s', result.artifacts.scriptFile);
            end
            if ~isempty(result.artifacts.slddFile)
                lines{end+1} = sprintf('数据字典：%s', result.artifacts.slddFile);
            end
            if ~isempty(result.artifacts.modelFile)
                lines{end+1} = sprintf('模型文件：%s', result.artifacts.modelFile);
            end
            if ~isempty(result.warnings)
                lines{end+1} = sprintf('警告 %d 条', numel(result.warnings));
            end
            if ~isempty(result.errorText)
                lines{end+1} = sprintf('错误：%s', result.errorText);
            end
            txt = strjoin(lines, newline);
        end

        function v = ternary(cond, a, b)
            if cond
                v = a;
            else
                v = b;
            end
        end
    end
end