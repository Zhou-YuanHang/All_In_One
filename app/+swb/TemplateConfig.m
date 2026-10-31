classdef TemplateConfig
    %SWB.TEMPLATECONFIG Config 表候选值的规范化、校验与摘要（纯逻辑，无 UI）。
    %   编辑器（swb.ui.TemplateConfigDialog）、generate_template.py 的 --config
    %   以及 Python 不可用时的 MATLAB 退化模板共用这里的规则，
    %   保证"界面里看到的候选值"就是"写进模板的候选值"。
    %
    %   cfg = swb.TemplateConfig.defaults()
    %   cfg = swb.TemplateConfig.normalize(cfgRaw)
    %   [cfg, warnings] = swb.TemplateConfig.prepare(cfgRaw)
    %   [ok, msg] = swb.TemplateConfig.validate(cfg)
    %   txt = swb.TemplateConfig.summary(cfg)

    methods (Static)
        function cfg = defaults()
            %DEFAULTS 内置默认候选值（与旧 template_config.json / generate_template.py 一致）
            cfg = swb.Schema.defaultConfig();
        end

        function cfg = normalize(cfg)
            %NORMALIZE 补齐 8 列，每列去首尾空白、丢空值、按出现顺序去重。
            %   缺字段用内置默认补齐；显式给出的空列表保留为空（表示该列清空下拉）。
            keys = swb.Schema.configKeys();
            d = swb.TemplateConfig.defaults();
            if nargin < 1 || isempty(cfg) || ~isstruct(cfg)
                cfg = d;
                return;
            end
            out = struct();
            for k = 1:numel(keys)
                key = keys{k};
                if isfield(cfg, key)
                    out.(key) = swb.TemplateConfig.cleanList(cfg.(key));
                else
                    out.(key) = d.(key);
                end
            end
            cfg = out;
        end

        function [cfg, warnings] = prepare(raw)
            %PREPARE 规范化并给出人类可读提示（界面保存时显示/写日志）。
            warnings = {};
            keys = swb.Schema.configKeys();
            d = swb.TemplateConfig.defaults();
            if nargin < 1 || isempty(raw) || ~isstruct(raw)
                cfg = d;
                warnings{end+1} = '没有读到任何候选值，已载入内置默认 Config。';
                return;
            end
            cfg = struct();
            for k = 1:numel(keys)
                key = keys{k};
                if ~isfield(raw, key)
                    cfg.(key) = d.(key);
                    continue;
                end
                [v, nDup, nBlank, nTrim] = swb.TemplateConfig.cleanListDetailed(raw.(key));
                cfg.(key) = v;
                if nDup > 0
                    warnings{end+1} = sprintf('%s：去除了 %d 个重复候选值。', key, nDup); %#ok<AGROW>
                end
                if nTrim > 0
                    warnings{end+1} = sprintf('%s：去除了 %d 个候选值的首尾空白。', key, nTrim); %#ok<AGROW>
                end
                if nBlank > 0
                    warnings{end+1} = sprintf('%s：忽略了 %d 个空行。', key, nBlank); %#ok<AGROW>
                end
                if isempty(v)
                    warnings{end+1} = sprintf('%s：该列没有候选值，生成的模板中该列将没有下拉列表。', key); %#ok<AGROW>
                end
            end
            extra = setdiff(fieldnames(raw), keys);
            for k = 1:numel(extra)
                warnings{end+1} = sprintf(['未知列 "%s" 已忽略（只支持 Package / Object / ' ...
                    'StorageClass / DataType / Unit / DimensionsMode / Complexity / DataScope）。'], extra{k}); %#ok<AGROW>
            end
        end

        function [ok, msg] = validate(cfg)
            %VALIDATE 保存前的硬性检查：返回 false 时界面拒绝保存并显示 msg。
            ok = false;
            msg = '';
            if nargin < 1 || isempty(cfg) || ~isstruct(cfg)
                msg = '模板 Config 为空。';
                return;
            end
            keys = swb.Schema.configKeys();
            total = 0;
            for k = 1:numel(keys)
                key = keys{k};
                if ~isfield(cfg, key)
                    msg = sprintf('缺少 %s 列的候选值。', key);
                    return;
                end
                v = cfg.(key);
                if ~iscell(v)
                    msg = sprintf('%s 列的候选值必须是字符串单元格数组。', key);
                    return;
                end
                for i = 1:numel(v)
                    it = v{i};
                    if ~ischar(it)
                        msg = sprintf('%s 列第 %d 个候选值不是字符串。', key, i);
                        return;
                    end
                    if contains(it, newline) || contains(it, char(13))
                        msg = sprintf('%s 列第 %d 个候选值包含换行符：一个候选值只能写在一行里。', key, i);
                        return;
                    end
                    if contains(it, char(9))
                        msg = sprintf('%s 列第 %d 个候选值包含制表符，请改成普通空格。', key, i);
                        return;
                    end
                end
                total = total + numel(v);
            end
            if total == 0
                msg = '所有列的候选值都是空的：生成的模板将没有任何下拉列表。请至少保留一列的候选值。';
                return;
            end
            ok = true;
        end

        function txt = summary(cfg)
            %SUMMARY 一行摘要，用于设置页说明文字与日志。
            cfg = swb.TemplateConfig.normalize(cfg);
            keys = swb.Schema.configKeys();
            n = 0;
            for k = 1:numel(keys)
                n = n + numel(cfg.(keys{k}));
            end
            if isequaln(cfg, swb.TemplateConfig.defaults())
                tag = '内置默认';
            else
                tag = '已自定义';
            end
            txt = sprintf('Config 表候选值：%d 列 / %d 项（%s）', numel(keys), n, tag);
        end
    end

    methods (Static, Access = private)
        function v = cleanList(raw)
            v = swb.TemplateConfig.cleanListDetailed(raw);
        end

        function [v, nDup, nBlank, nTrim] = cleanListDetailed(raw)
            v = {};
            nDup = 0;
            nBlank = 0;
            nTrim = 0;
            if isempty(raw)
                return;
            end
            items = swb.TemplateConfig.toCellstr(raw);
            for i = 1:numel(items)
                it = items{i};
                if isempty(it) || all(isspace(it))
                    nBlank = nBlank + 1;
                    continue;
                end
                trimmed = strtrim(it);
                if ~strcmp(trimmed, it)
                    nTrim = nTrim + 1;
                end
                if any(strcmp(v, trimmed))
                    nDup = nDup + 1;
                    continue;
                end
                v{end+1} = trimmed; %#ok<AGROW>
            end
        end

        function items = toCellstr(raw)
            items = {};
            if ischar(raw)
                items = cellstr(raw);
                return;
            end
            if isstring(raw)
                s = raw(:)';
                items = cell(1, numel(s));
                for i = 1:numel(s)
                    items{i} = swb.TemplateConfig.anyToChar(s(i));
                end
                return;
            end
            if iscell(raw)
                items = cell(1, numel(raw));
                for i = 1:numel(raw)
                    items{i} = swb.TemplateConfig.anyToChar(raw{i});
                end
                return;
            end
            if isnumeric(raw)
                items = arrayfun(@(x) num2str(x), raw(:)', 'UniformOutput', false);
            end
        end

        function s = anyToChar(v)
            s = '';
            if ischar(v)
                s = v;
            elseif isstring(v) && isscalar(v)
                if ismissing(v)
                    s = '';
                else
                    s = char(v);
                end
            elseif isnumeric(v) && isscalar(v) && ~isnan(v)
                s = num2str(v);
            end
        end
    end
end
