classdef Dictionary
    %SWB.DICTIONARY Simulink 数据字典写入/读取服务（无 UI）。
    %   把 ScriptBuilder 生成的脚本文本写入 .sldd 的 Design Data 段：
    %     stats = swb.Dictionary.writeScript(dictPath, scriptText, opts)
    %       opts: CleanExtra(false), ConfirmFcn([]), Log([]), Verify(true)
    %     [dict, isNew] = swb.Dictionary.openOrCreate(dictPath)
    %     swb.Dictionary.close(dict)
    %     entries = swb.Dictionary.readEntries(dictPath)  % struct(Name,Type,ClassName,Value)
    %
    %   与旧 sldd_gui.doWriteToSldd 的差异：
    %     * 不再 evalin('base')，脚本在局部函数工作区 eval，不污染基础工作区；
    %     * 只接管 Simulink.Signal / Simulink.Parameter / Simulink.Bus 三类对象；
    %     * 每个对象独立 try/catch，坏对象只计数失败，不影响其它对象；
    %     * 字典句柄用 onCleanup 关闭，异常统一转成 stats.errorText。

    methods (Static)
        function stats = writeScript(dictPath, scriptText, opts)
            % 把脚本执行得到的数据对象写入数据字典（增量更新，可选清理多余条目）
            if nargin < 1 || isempty(dictPath)
                error('swb:Dictionary:missingPath', '数据字典路径为空。');
            end
            if nargin < 2 || isempty(scriptText) || ~(ischar(scriptText) || isstring(scriptText))
                error('swb:Dictionary:missingScript', '脚本文本为空或类型不正确。');
            end
            dictPath = char(dictPath);
            scriptText = char(scriptText);
            if nargin < 3 || isempty(opts)
                opts = struct();
            end
            opts = swb.Dictionary.withDefaults(opts, struct( ...
                'CleanExtra', false, 'ConfirmFcn', [], 'Log', [], 'Verify', true));

            stats = swb.Dictionary.emptyStats();
            pathCleaner = []; %#ok<NASGU>
            try
                [pathCleaner, addedPath] = swb.Dictionary.ensurePackagePath(); %#ok<ASGLU>
                if addedPath
                    stats.messages{end+1} = '已临时把 app/resources 加入搜索路径（用于 myPackage 类）。';
                end

                % 1) 先在局部工作区执行脚本，拿到对象（不碰基础工作区）
                [names, values, evalErr] = swb.Dictionary.evalScriptText(scriptText);
                if ~isempty(evalErr)
                    stats.failed = stats.failed + 1;
                    stats.failedNames{end+1, 1} = '<脚本执行中断>';
                    stats.messages{end+1} = sprintf('脚本执行中断：%s', evalErr.message);
                    swb.Dictionary.logWith(opts, 'warn', stats.messages{end});
                    if isempty(names)
                        stats.ok = false;
                        stats.errorText = evalErr.message;
                        return;
                    end
                    stats.messages{end+1} = sprintf( ...
                        '中断前已创建 %d 个对象，继续写入这些对象。', numel(names));
                end
                if isempty(names)
                    stats.ok = true;
                    stats.messages{end+1} = '脚本没有生成任何 Simulink 数据对象，未改动字典。';
                    return;
                end
                stats.messages{end+1} = sprintf('脚本执行成功，共 %d 个数据对象。', numel(names));

                % 2) 打开/创建字典
                [dict, isNew] = swb.Dictionary.openOrCreate(dictPath);
                stats.dictCreated = isNew;
                dictCleaner = onCleanup(@() swb.Dictionary.close(dict)); %#ok<NASGU>
                sect = swb.Dictionary.designDataSection(dict);

                % 3) 清理多余条目（可选）
                if opts.CleanExtra
                    stats = swb.Dictionary.cleanExtraEntries(stats, dictPath, sect, names, opts);
                end

                % 4) 建立现有条目缓存（只取本字典的本地 Simulink 对象）
                existing = swb.Dictionary.localValueMap(sect, dictPath);

                % 5) 逐对象写入
                for k = 1:numel(names)
                    name = names{k};
                    val = values{k};
                    try
                        if isKey(existing, name)
                            old = existing(name);
                            if swb.Dictionary.valuesEqual(old, val)
                                stats.skipped = stats.skipped + 1;
                            else
                                getEntry(sect, name).setValue(val);
                                stats.updated = stats.updated + 1;
                            end
                        else
                            addEntry(sect, name, val);
                            stats.added = stats.added + 1;
                        end
                        existing(name) = val;
                    catch ME
                        stats.failed = stats.failed + 1;
                        stats.failedNames{end+1, 1} = name;
                        stats.messages{end+1} = sprintf('写入 "%s" 失败：%s', name, ME.message);
                        swb.Dictionary.logWith(opts, 'warn', stats.messages{end});
                    end
                end

                % 6) 保存
                if stats.added > 0 || stats.updated > 0 || stats.cleaned > 0
                    saveChanges(dict);
                end
                stats.totalAfter = swb.Dictionary.countLocalObjects(sect, dictPath);

                % 7) 重开校验
                if opts.Verify
                    stats = swb.Dictionary.verifyAfterWrite(stats, dict, dictPath, names, values);
                end

                stats.ok = stats.failed == 0;
            catch ME
                stats.ok = false;
                stats.errorText = ME.message;
                stats.messages{end+1} = sprintf('写入数据字典失败：%s', ME.message);
                swb.Dictionary.logWith(opts, 'err', stats.messages{end});
            end
        end

        function [dict, isNew] = openOrCreate(dictPath)
            % 打开已有 .sldd，不存在则创建（调用方负责 close）
            if nargin < 1 || isempty(dictPath)
                error('swb:Dictionary:missingPath', '数据字典路径为空。');
            end
            dictPath = char(dictPath);
            isNew = false;
            if isfile(dictPath)
                dict = Simulink.data.dictionary.open(dictPath);
            else
                outDir = fileparts(dictPath);
                if ~isempty(outDir) && ~isfolder(outDir)
                    mkdir(outDir);
                end
                dict = Simulink.data.dictionary.create(dictPath);
                isNew = true;
            end
        end

        function close(dict)
            % 安全关闭字典（已关闭/无效句柄不报错）
            try
                if ~isempty(dict) && isvalid(dict)
                    Simulink.data.dictionary.close(dict);
                end
            catch
                try
                    Simulink.data.dictionary.close(dict);
                catch
                end
            end
        end

        function entries = readEntries(dictPath)
            % 读取字典 Design Data 段的本地条目：struct array(Name,Type,ClassName,Value)
            entries = swb.Dictionary.emptyEntries();
            if nargin < 1 || isempty(dictPath) || ~isfile(char(dictPath))
                return;
            end
            dictPath = char(dictPath);
            dict = [];
            try
                dict = Simulink.data.dictionary.open(dictPath);
                sect = getSection(dict, 'Design Data');
                allEntries = find(sect);
                if isempty(allEntries)
                    swb.Dictionary.close(dict);
                    return;
                end
                [~, dictName, dictExt] = fileparts(dictPath);
                sourceName = [dictName dictExt];
                for k = 1:numel(allEntries)
                    e = allEntries(k);
                    if ~strcmp(e.DataSource, sourceName)
                        continue;
                    end
                    val = e.getValue();
                    if ~swb.Dictionary.isManaged(val)
                        continue;
                    end
                    entries(end+1, 1) = struct( ... %#ok<AGROW>
                        'Name', e.Name, ...
                        'Type', swb.Dictionary.objectType(val), ...
                        'ClassName', class(val), ...
                        'Value', val);
                end
                swb.Dictionary.close(dict);
                dict = [];
                if ~isempty(entries)
                    [~, order] = sort({entries.Name});
                    entries = entries(order);
                end
            catch
                if ~isempty(dict)
                    swb.Dictionary.close(dict);
                end
                entries = swb.Dictionary.emptyEntries();
            end
        end
    end

    methods (Static, Access = private)
        function stats = emptyStats()
            stats = struct( ...
                'ok', true, ...
                'added', 0, ...
                'updated', 0, ...
                'skipped', 0, ...
                'failed', 0, ...
                'failedNames', {{}}, ...
                'cleaned', 0, ...
                'totalBefore', 0, ...
                'totalAfter', 0, ...
                'dictCreated', false, ...
                'errorText', '', ...
                'verifyMissing', {{}}, ...
                'messages', {{}});
        end

        function entries = emptyEntries()
            entries = struct('Name', {}, 'Type', {}, 'ClassName', {}, 'Value', {});
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

        function [cleaner, added] = ensurePackagePath()
            % 脚本里可能出现 myPackage.Signal 之类构造，需要 app/resources 在路径上
            cleaner = [];
            added = false;
            try
                if exist('myPackage.Signal', 'class') == 8
                    return;
                end
                here = fileparts(mfilename('fullpath'));
                resPath = fullfile(fileparts(here), 'resources');
                if isfolder(fullfile(resPath, '+myPackage'))
                    try
                        evalc('addpath(resPath)');
                    catch
                        addpath(resPath);
                    end
                    if exist('myPackage.Signal', 'class') == 8
                        added = true;
                        cleaner = onCleanup(@() swb.Dictionary.rmpathQuiet(resPath));
                    else
                        swb.Dictionary.rmpathQuiet(resPath);
                    end
                end
            catch
                cleaner = [];
                added = false;
            end
        end

        function rmpathQuiet(p)
            try
                rmpath(p);
            catch
            end
        end

        function [names, values, evalErr] = evalScriptText(scriptText)
            % 在局部函数工作区执行脚本文本，只回收 Simulink 数据对象。
            % 脚本中途出错时保留已经创建的对象（与旧实现"先跑脚本再写字典"一致）。
            names = {};
            values = {};
            evalErr = [];
            try
                eval(scriptText); %#ok<EVLC>
            catch ME
                evalErr = ME;
            end
            vars = who;
            for k = 1:numel(vars)
                name = vars{k};
                if strcmp(name, 'scriptText')
                    continue;
                end
                val = [];
                try
                    eval(['val = ' name ';']); %#ok<EVLC>
                catch
                    continue;
                end
                if swb.Dictionary.isManaged(val)
                    names{end+1, 1} = name; %#ok<AGROW>
                    values{end+1, 1} = val; %#ok<AGROW>
                end
            end
        end

        function tf = isManaged(val)
            tf = false;
            if isempty(val)
                return;
            end
            tf = isa(val, 'Simulink.Bus') || isa(val, 'Simulink.Signal') || isa(val, 'Simulink.Parameter');
        end

        function t = objectType(val)
            if isa(val, 'Simulink.Bus')
                t = 'Bus';
            elseif isa(val, 'Simulink.Parameter')
                t = 'Parameter';
            elseif isa(val, 'Simulink.Signal')
                t = 'Signal';
            else
                t = class(val);
            end
        end

        function sect = designDataSection(dict)
            sect = getSection(dict, 'Design Data');
        end

        function sourceName = dictSourceName(dictPath)
            [~, n, e] = fileparts(dictPath);
            sourceName = [n e];
        end

        function mask = localMask(entries, dictPath)
            sourceName = swb.Dictionary.dictSourceName(dictPath);
            mask = false(1, numel(entries));
            for k = 1:numel(entries)
                mask(k) = strcmp(entries(k).DataSource, sourceName);
            end
        end

        function m = localValueMap(sect, dictPath)
            % containers.Map: 条目名 -> 对象值（仅本字典本地 Simulink 对象）
            m = containers.Map('KeyType', 'char', 'ValueType', 'any');
            entries = find(sect);
            if isempty(entries)
                return;
            end
            mask = swb.Dictionary.localMask(entries, dictPath);
            entries = entries(mask);
            for k = 1:numel(entries)
                val = entries(k).getValue();
                if swb.Dictionary.isManaged(val)
                    m(entries(k).Name) = val;
                end
            end
        end

        function n = countLocalObjects(sect, dictPath)
            n = 0;
            entries = find(sect);
            if isempty(entries)
                return;
            end
            mask = swb.Dictionary.localMask(entries, dictPath);
            entries = entries(mask);
            for k = 1:numel(entries)
                if swb.Dictionary.isManaged(entries(k).getValue())
                    n = n + 1;
                end
            end
        end

        function tf = valuesEqual(a, b)
            tf = false;
            try
                if ~strcmp(class(a), class(b))
                    return;
                end
                ws = warning('off', 'MATLAB:structOnObject');
                restore = onCleanup(@() warning(ws)); %#ok<NASGU>
                tf = isequal(struct(a), struct(b));
            catch
                tf = false;
            end
        end

        function stats = cleanExtraEntries(stats, dictPath, sect, names, opts)
            entries = find(sect);
            if isempty(entries)
                return;
            end
            mask = swb.Dictionary.localMask(entries, dictPath);
            entries = entries(mask);
            extra = {};
            for k = 1:numel(entries)
                if swb.Dictionary.isManaged(entries(k).getValue()) && ~any(strcmp(names, entries(k).Name))
                    extra{end+1} = entries(k).Name; %#ok<AGROW>
                end
            end
            if isempty(extra)
                return;
            end
            approve = true;
            if ~isempty(opts.ConfirmFcn)
                try
                    approve = logical(opts.ConfirmFcn(sprintf( ...
                        '数据字典中有 %d 个条目不在本次脚本中，是否删除？', numel(extra))));
                catch
                    approve = false;
                end
            end
            if ~approve
                stats.messages{end+1} = sprintf('已跳过清理 %d 个多余条目（用户取消）。', numel(extra));
                return;
            end
            for k = 1:numel(extra)
                try
                    deleteEntry(sect, extra{k});
                    stats.cleaned = stats.cleaned + 1;
                catch ME
                    stats.messages{end+1} = sprintf('删除多余条目 "%s" 失败：%s', extra{k}, ME.message);
                end
            end
            if stats.cleaned > 0
                stats.messages{end+1} = sprintf('已清理 %d 个多余条目。', stats.cleaned);
            end
        end

        function stats = verifyAfterWrite(stats, dict, dictPath, names, values)
            % 关闭后重开，确认条目存在且类一致
            swb.Dictionary.close(dict);
            dict2 = [];
            try
                dict2 = Simulink.data.dictionary.open(dictPath);
                cleaner = onCleanup(@() swb.Dictionary.close(dict2)); %#ok<NASGU>
                sect2 = getSection(dict2, 'Design Data');
                for k = 1:numel(names)
                    name = names{k};
                    try
                        e = getEntry(sect2, name);
                        if ~strcmp(class(e.getValue()), class(values{k}))
                            stats.verifyMissing{end+1, 1} = name; %#ok<AGROW>
                        end
                    catch
                        stats.verifyMissing{end+1, 1} = name; %#ok<AGROW>
                    end
                end
                stats.totalAfter = swb.Dictionary.countLocalObjects(sect2, dictPath);
                if ~isempty(stats.verifyMissing)
                    stats.messages{end+1} = sprintf('校验发现 %d 个条目缺失或类型不符。', numel(stats.verifyMissing));
                end
            catch ME
                stats.messages{end+1} = sprintf('重开校验失败：%s', ME.message);
            end
        end

        function logWith(opts, level, message)
            if isfield(opts, 'Log') && ~isempty(opts.Log)
                try
                    opts.Log.(level)(message);
                catch
                end
            end
        end
    end
end
