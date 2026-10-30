classdef Settings < handle
    %SWB.SETTINGS 机器级配置（prefdir/simworkbench.json）。
    %   旧工具把 python_config.json / template_config.json 放在 App 目录里，
    %   安装到 Program Files 后不可写；这里统一放到 prefdir，并支持一次性迁移旧配置。

    properties
        File = ''
        PythonPath = ''
        DefaultTlc = 'ert.tlc'
        LastDictWorkbook = ''
        LastPortWorkbook = ''
        LastOutputDir = ''
        ConflictPolicy = 'ask'      % ask | overwrite | suffix | cancel
        TemplateConfig = struct()   % Config 表候选值 {key -> cellstr}
    end

    methods
        function obj = Settings(filePath)
            if nargin >= 1 && ~isempty(filePath)
                obj.File = char(filePath);
            else
                obj.File = fullfile(prefdir, 'simworkbench.json');
            end
            obj.load();
        end

        function load(obj)
            obj.TemplateConfig = swb.Schema.defaultConfig();
            if isempty(obj.File) || ~isfile(obj.File)
                return;
            end
            try
                s = jsondecode(fileread(obj.File));
            catch
                return;
            end
            if ~isstruct(s)
                return;
            end
            strFields = {'PythonPath','DefaultTlc','LastDictWorkbook','LastPortWorkbook', ...
                         'LastOutputDir','ConflictPolicy'};
            for k = 1:numel(strFields)
                f = strFields{k};
                if isfield(s, f) && (ischar(s.(f)) || isstring(s.(f)))
                    obj.(f) = char(s.(f));
                end
            end
            if isfield(s, 'TemplateConfig') && isstruct(s.TemplateConfig)
                cfg = swb.Schema.defaultConfig();
                keys = fieldnames(cfg);
                for k = 1:numel(keys)
                    key = keys{k};
                    if isfield(s.TemplateConfig, key)
                        v = s.TemplateConfig.(key);
                        if ischar(v) || isstring(v)
                            v = cellstr(v);
                        end
                        if iscell(v)
                            v = cellfun(@char, v(:)', 'UniformOutput', false);
                            v = v(~cellfun(@isempty, strtrim(v)));
                            cfg.(key) = v;
                        end
                    end
                end
                obj.TemplateConfig = cfg;
            end
        end

        function save(obj)
            s = struct();
            s.PythonPath = obj.PythonPath;
            s.DefaultTlc = obj.DefaultTlc;
            s.LastDictWorkbook = obj.LastDictWorkbook;
            s.LastPortWorkbook = obj.LastPortWorkbook;
            s.LastOutputDir = obj.LastOutputDir;
            s.ConflictPolicy = obj.ConflictPolicy;
            s.TemplateConfig = obj.TemplateConfig;
            try
                d = fileparts(obj.File);
                if ~isempty(d) && ~isfolder(d)
                    mkdir(d);
                end
                fid = fopen(obj.File, 'w', 'n', 'UTF-8');
                if fid < 0
                    return;
                end
                cleaner = onCleanup(@() fclose(fid));
                fwrite(fid, jsonencode(s), 'char');
            catch
                % 配置写失败不阻断业务
            end
        end

        function ok = migrateLegacy(obj, legacyDir)
            % 从旧 AutoCreateSldd 目录迁移 python_config.json / template_config.json
            ok = false;
            if nargin < 2 || isempty(legacyDir) || ~isfolder(legacyDir)
                return;
            end
            pFile = fullfile(legacyDir, 'python_config.json');
            if isfile(pFile) && isempty(strtrim(obj.PythonPath))
                try
                    s = jsondecode(fileread(pFile));
                    if isfield(s, 'PythonPath') && (ischar(s.PythonPath) || isstring(s.PythonPath))
                        obj.PythonPath = char(s.PythonPath);
                    end
                catch
                end
            end
            tFile = fullfile(legacyDir, 'template_config.json');
            if isfile(tFile)
                try
                    s = jsondecode(fileread(tFile));
                    if isstruct(s)
                        cfg = swb.Schema.defaultConfig();
                        keys = fieldnames(cfg);
                        for k = 1:numel(keys)
                            if isfield(s, keys{k}) && iscell(s.(keys{k}))
                                cfg.(keys{k}) = cellfun(@char, s.(keys{k})(:)', 'UniformOutput', false);
                            end
                        end
                        obj.TemplateConfig = cfg;
                    end
                catch
                end
            end
            obj.save();
            ok = true;
        end

        function tf = hasPythonPath(obj)
            tf = ~isempty(strtrim(obj.PythonPath));
        end
    end
end
