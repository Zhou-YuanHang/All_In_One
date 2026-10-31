classdef TemplateConfigDialog < handle
    %SWB.UI.TEMPLATECONFIGDIALOG 编辑 Config 表下拉候选值的模态对话框。
    %
    %   d = swb.ui.TemplateConfigDialog(parentFigure, settings.TemplateConfig);
    %   d.show();                       % 模态显示，等用户点"保存"或"取消"
    %   if ~isempty(d.Result)           % 用户点了保存
    %       settings.TemplateConfig = d.Result;
    %       settings.save();
    %   end
    %
    %   d.Result   保存后的规范化候选值（用户取消时为 []）
    %   d.Warnings 保存时的提示（去重、空列、未知列等），由调用方写日志

    properties
        Figure
        Keys
        Areas = {}
        Result = []
        Warnings = {}
        CountLabel = []
    end

    properties (Constant, Access = private)
        RowHeight = 64
    end

    methods
        function d = TemplateConfigDialog(parentFig, cfg)
            if nargin < 2 || isempty(cfg)
                cfg = swb.Schema.defaultConfig();
            end
            d.Keys = swb.Schema.configKeys();
            cfg = swb.TemplateConfig.normalize(cfg);
            cols = swb.Schema.configColumns();

            fig = uifigure('Name', '模板 Config — Config 表下拉候选值', ...
                'Visible', 'off', 'WindowStyle', 'modal', ...
                'Color', [0.95, 0.95, 0.96]);
            d.Figure = fig;
            sz = [780, 700];
            d.placeOver(fig, parentFig, sz);
            fig.CloseRequestFcn = @(~, ~) d.onCancel();

            g = uigridlayout(fig, [4, 1]);
            g.RowHeight = {'fit', '1x', 'fit', 'fit'};
            g.ColumnWidth = {'1x'};
            g.Padding = [12, 12, 12, 12];
            g.RowSpacing = 8;

            header = uilabel(g, 'Text', ...
                ['Config 表 8 列的下拉候选值，每行一个。这里的内容会写进生成器的 Config 表，' ...
                 '作为 Signal / Parameter 等表的下拉列表；清空某一列表示该列不提供下拉。'], ...
                'WordWrap', 'on');
            header.Layout.Row = 1;

            hp = uipanel(g, 'Title', '候选值', 'Scrollable', 'on');
            hp.Layout.Row = 2;
            gg = uigridlayout(hp, [numel(d.Keys), 2]);
            gg.RowHeight = repmat({d.RowHeight}, 1, numel(d.Keys));
            gg.ColumnWidth = {190, '1x'};
            gg.Padding = [10, 8, 10, 8];
            gg.RowSpacing = 6;
            for k = 1:numel(d.Keys)
                key = d.Keys{k};
                lab = uilabel(gg, ...
                    'Text', sprintf('%s（Config!%s）', key, cols(k).letter), ...
                    'FontWeight', 'bold');
                lab.Layout.Row = k;
                lab.Layout.Column = 1;
                ta = uitextarea(gg, 'Value', cfg.(key), ...
                    'FontName', 'Consolas', ...
                    'ValueChangedFcn', @(~, ~) d.updateCount());
                ta.Layout.Row = k;
                ta.Layout.Column = 2;
                d.Areas{k} = ta;
            end

            d.CountLabel = uilabel(g, 'Text', '', 'FontColor', [0.45, 0.45, 0.45]);
            d.CountLabel.Layout.Row = 3;

            btns = uigridlayout(g, [1, 4]);
            btns.Layout.Row = 4;
            btns.ColumnWidth = {140, '1x', 110, 110};
            btns.Padding = [0, 0, 0, 0];
            resetBtn = uibutton(btns, 'Text', '恢复默认', ...
                'ButtonPushedFcn', @(~, ~) d.onReset());
            resetBtn.Layout.Row = 1;
            resetBtn.Layout.Column = 1;
            cancelBtn = uibutton(btns, 'Text', '取消', ...
                'ButtonPushedFcn', @(~, ~) d.onCancel());
            cancelBtn.Layout.Row = 1;
            cancelBtn.Layout.Column = 3;
            saveBtn = uibutton(btns, 'Text', '保存', 'FontWeight', 'bold', ...
                'BackgroundColor', [0.15, 0.55, 0.15], 'FontColor', [1, 1, 1], ...
                'ButtonPushedFcn', @(~, ~) d.onSave());
            saveBtn.Layout.Row = 1;
            saveBtn.Layout.Column = 4;

            d.updateCount();
        end

        function show(d)
            %SHOW 模态显示并等待用户关闭。
            if ~d.isAlive(d.Figure)
                return;
            end
            d.Figure.Visible = 'on';
            try
                uiwait(d.Figure);
            catch
                % 无桌面会话时 uiwait 可能不可用：直接返回，调用方按 d.Result 处理。
            end
        end

        function cfg = collect(d)
            %COLLECT 读取 8 个文本框的当前内容（未规范化）。
            cfg = struct();
            for k = 1:numel(d.Keys)
                key = d.Keys{k};
                if numel(d.Areas) >= k && d.isAlive(d.Areas{k})
                    cfg.(key) = d.Areas{k}.Value;
                else
                    cfg.(key) = {};
                end
            end
        end

        function updateCount(d)
            %UPDATECOUNT 更新"当前多少个候选值"提示。
            total = 0;
            for k = 1:numel(d.Keys)
                if numel(d.Areas) >= k && d.isAlive(d.Areas{k})
                    v = cellstr(d.Areas{k}.Value);
                    total = total + sum(~cellfun(@(s) isempty(strtrim(s)), v));
                end
            end
            if d.isAlive(d.CountLabel)
                d.CountLabel.Text = sprintf( ...
                    '当前 %d 个候选值；某列全部删空表示该列在模板中没有下拉列表。', total);
            end
        end

        function [ok, msg] = tryAccept(d)
            %TRYACCEPT 规范化 + 校验，成功时写入 d.Result / d.Warnings。
            ok = false;
            msg = '';
            [cfg, warnings] = swb.TemplateConfig.prepare(d.collect());
            [valid, errText] = swb.TemplateConfig.validate(cfg);
            if ~valid
                msg = errText;
                return;
            end
            d.Result = cfg;
            d.Warnings = warnings;
            ok = true;
        end

        function onSave(d)
            [ok, msg] = d.tryAccept();
            if ok
                d.closeDialog();
                return;
            end
            try
                uialert(d.Figure, msg, '模板 Config 有错误', 'Icon', 'error');
            catch
            end
        end

        function onCancel(d)
            d.Result = [];
            d.closeDialog();
        end

        function onReset(d)
            d0 = swb.Schema.defaultConfig();
            for k = 1:numel(d.Keys)
                if numel(d.Areas) >= k && d.isAlive(d.Areas{k})
                    d.Areas{k}.Value = d0.(d.Keys{k});
                end
            end
            d.updateCount();
        end

        function closeDialog(d)
            if d.isAlive(d.Figure)
                try
                    delete(d.Figure);
                catch
                end
            end
        end

        function delete(d)
            d.closeDialog();
        end
    end

    methods (Access = private)
        function tf = isAlive(~, h)
            tf = ~isempty(h) && isvalid(h);
        end

        function placeOver(d, fig, parentFig, sz)
            x = 120;
            y = 120;
            if nargin >= 3 && ~isempty(parentFig)
                try
                    if isvalid(parentFig)
                        p = parentFig.Position;
                        x = p(1) + max(0, (p(3) - sz(1)) / 2);
                        y = p(2) + max(0, (p(4) - sz(2)) / 2);
                    end
                catch
                end
            end
            fig.Position = [x, y, sz(1), sz(2)];
        end
    end
end
