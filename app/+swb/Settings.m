classdef Settings < handle
    %SWB.SETTINGS 机器级配置（App 安装目录/simworkbench.json）。
    %   配置文件与 App 一起放在安装目录（MATLAB Add-OnsAppsSimWorkbench，
    %   位于用户 Roaming 下，可写）。首次使用若 App 目录里还没有配置文件，
    %   会自动从旧版位置 prefdir/simworkbench.json 迁移一次。

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
                obj.File = obj.defaultFile();
            end
            obj.migrateFromPrefdir();
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

        function tf = hasPythonPath(obj)
            tf = ~isempty(strtrim(obj.PythonPath));
        end

        function migrateFromPrefdir(obj)
            %MIGRATEFROMPREFDIR 旧版配置在 prefdir，首次运行搬到 App 目录。
            %   只在 App 目录还没有配置文件且 prefdir 里有旧配置时执行一次。
            newFile = obj.File;
            oldFile = fullfile(prefdir, 'simworkbench.json');
            if isfile(newFile) || ~isfile(oldFile)
                return;
            end
            try
                copyfile(oldFile, newFile);
            catch
                % 迁移失败不影响启动：下次保存时会直接写到 App 目录
            end
        end
    end

    methods (Static)
        function f = appRootPublic()
            %APPROOTPUBLIC 供界面显示配置文件位置用。
            f = swb.Settings.appRoot();
        end
    end

    methods (Static, Access = private)
        function f = appRoot()
            %APPROOT App 安装目录（Settings.m 所在 +swb 包的上一级）。
            try
                f = fileparts(fileparts(mfilename('fullpath')));
            catch
                f = pwd;
            end
        end

        function f = defaultFile()
            %DEFAULTFILE App 安装目录下的 simworkbench.json。
            f = fullfile(swb.Settings.appRoot(), 'simworkbench.json');
        end
    end
end
