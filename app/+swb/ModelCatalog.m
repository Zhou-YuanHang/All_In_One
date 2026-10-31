classdef ModelCatalog
    %SWB.MODELCATALOG 现有模型清单：当前会话已打开的模型 + 指定目录里的 .slx/.mdl。
    %
    %   用于「模型与端口」页的模型名称下拉：既能手写名称，也能直接挑一个现有模型。
    %
    %   items = swb.ModelCatalog.list(folder)   % 结构体数组，按名称排序
    %   info  = swb.ModelCatalog.findByName(name)  % 单个模型（找不到返回 []）
    %
    %   items 字段：
    %       name    模型名称（不含扩展名，可直接作为 Simulink 模型名）
    %       folder  模型文件所在目录（未保存的已打开模型为空）
    %       file    模型文件全路径（未保存的已打开模型为空）
    %       loaded  当前 MATLAB 会话中是否已打开
    %       source  'loaded'（已打开）或 'file'（目录里的文件）

    methods (Static)
        function items = list(folder)
            %LIST 收集可选模型：先已打开（知道真实路径），再目录里的文件；同名只保留第一条。
            if nargin < 1 || isempty(folder)
                folder = pwd;
            end
            folder = char(folder);
            items = swb.ModelCatalog.emptyList();
            items = swb.ModelCatalog.appendUnique(items, swb.ModelCatalog.loaded());
            items = swb.ModelCatalog.appendUnique(items, swb.ModelCatalog.inFolder(folder));
            if ~isempty(items)
                [~, order] = sort(lower({items.name}));
                items = items(order);
            end
        end

        function names = names(folder)
            %NAMES 只要名称列表（下拉框 Items 用）。
            items = swb.ModelCatalog.list(folder);
            names = {items.name};
        end

        function info = findByName(name)
            %FINDBYNAME 按名称解析现有模型：已打开的优先，其次搜索路径上的 .slx/.mdl。
            info = [];
            name = strtrim(char(name));
            if isempty(name) || ~isvarname(name)
                return;
            end
            try
                if bdIsLoaded(name)
                    file = '';
                    try
                        file = char(get_param(name, 'FileName'));
                    catch
                        file = '';
                    end
                    info = swb.ModelCatalog.makeItem(name, file, true, 'loaded');
                    return;
                end
            catch
                % bdIsLoaded 在极端情况下也可能报错：继续走文件查找
            end
            exts = {'.slx', '.mdl'};
            for k = 1:numel(exts)
                f = '';
                try
                    f = which([name exts{k}]);
                catch
                    f = '';
                end
                if ~isempty(f)
                    info = swb.ModelCatalog.makeItem(name, f, false, 'file');
                    return;
                end
            end
        end

        function tf = isFileBacked(info)
            %ISFILEBACKED 该模型是否已有磁盘文件（未保存的新模型返回 false）。
            tf = ~isempty(info) && isfield(info, 'file') && ~isempty(info.file) && isfile(info.file);
        end

        function items = emptyList()
            items = struct('name', {}, 'folder', {}, 'file', {}, ...
                           'loaded', {}, 'source', {});
        end

        function items = loaded()
            %LOADED 当前会话里已打开的 Simulink 模型（不含库）。
            items = swb.ModelCatalog.emptyList();
            try
                found = find_system('type', 'block_diagram');
            catch
                return
            end
            if ischar(found)
                found = {found};
            end
            for k = 1:numel(found)
                name = char(found{k});
                if isempty(name) || ~isvarname(name)
                    continue;
                end
                try
                    if ~strcmp(char(get_param(name, 'BlockDiagramType')), 'model')
                        continue;   % 库文件不能导出端口 / 不能当目标模型
                    end
                    file = char(get_param(name, 'FileName'));
                catch
                    continue;
                end
                item = swb.ModelCatalog.makeItem(name, file, true, 'loaded');
                items = swb.ModelCatalog.appendUnique(items, item);
            end
        end

        function items = inFolder(folder)
            %INFOLDER 目录里的 .slx/.mdl 文件（文件名必须是合法标识符才能当模型名）。
            items = swb.ModelCatalog.emptyList();
            folder = char(folder);
            if isempty(folder) || ~isfolder(folder)
                return;
            end
            patterns = {'*.slx', '*.mdl'};
            for p = 1:numel(patterns)
                d = dir(fullfile(folder, patterns{p}));
                for k = 1:numel(d)
                    [~, base] = fileparts(d(k).name);
                    if isempty(base) || ~isvarname(base)
                        continue;
                    end
                    item = swb.ModelCatalog.makeItem(base, fullfile(folder, d(k).name), false, 'file');
                    items = swb.ModelCatalog.appendUnique(items, item);
                end
            end
        end

        function all = appendUnique(all, add)
            %APPENDUNIQUE 按名称去重合并（先加入的优先）。
            for k = 1:numel(add)
                if any(strcmp({all.name}, add(k).name))
                    continue;
                end
                if isempty(all)
                    all = add(k);
                else
                    all(end+1) = add(k); %#ok<AGROW>
                end
            end
        end

        function item = makeItem(name, file, loaded, source)
            %MAKEITEM 组装一条模型记录。
            file = char(file);
            if isempty(file)
                folder = '';
            else
                folder = fileparts(file);
            end
            item = struct('name', char(name), 'folder', folder, 'file', file, ...
                          'loaded', logical(loaded), 'source', char(source));
        end
    end
end
