classdef SimWorkbench < handle
    %SIMWORKBENCH Simulink 一体化工作台（All-in-One App）主窗口。
    %   单窗口 + 左侧导航：工作流 / 数据字典 / 模型与端口 / 设置 / 日志。
    %   业务逻辑全部在 +swb 服务层；本类只负责布局、状态与调度。
    %
    %   用法：  SimWorkbench

    properties
        UIFigure
        TabGroup
        Settings
        Log
        DictWorkbookPath = ''
        PortWorkbookPath = ''
        AutoScriptFile = ''    % 上次自动推导的对象脚本路径（没被手改过才跟随字典工作簿切换）
        AutoSlddFile = ''      % 上次自动推导的 .sldd 路径
        H = struct()
        Steps = {'读取工作簿','校验数据字典','生成对象脚本','写入数据字典','创建模型与端口','保存并打开'}
    end

    methods
        function app = SimWorkbench(varargin)
            p = inputParser;
            p.addParameter('Visible', 'on');
            p.addParameter('SettingsFile', '');
            p.parse(varargin{:});

            app.Settings = swb.Settings(p.Results.SettingsFile);
            app.Log = swb.Log();
            app.buildUI();
            app.Log.Callback = @(entry) app.onLogEntry(entry);
            app.applySettingsToUI();
            app.refreshSummary();

            app.Log.info('SimWorkbench 启动（MATLAB %s）', version('-release'));
            if app.Settings.hasPythonPath()
                app.Log.info('Python: %s', app.Settings.PythonPath);
            else
                app.Log.warn('尚未配置 Python 路径（设置页可指定；仅模板生成/反向同步需要）。');
            end
            if strcmpi(p.Results.Visible, 'on')
                app.UIFigure.Visible = 'on';
            end
        end

        function delete(app)
            if ~isempty(app.UIFigure) && isvalid(app.UIFigure)
                delete(app.UIFigure);
            end
        end

        function populateDemo(app, dictWorkbook, portWorkbook)
            %POPULATEDEMO 为截图/演示填充真实工作簿（不经过文件选择框）。
            if nargin >= 2 && ~isempty(dictWorkbook)
                app.DictWorkbookPath = dictWorkbook;
                app.H.dictWorkbookEdit.Value = dictWorkbook;
                app.H.dictEdit.Value = dictWorkbook;
            end
            if nargin >= 3 && ~isempty(portWorkbook)
                app.PortWorkbookPath = portWorkbook;
                app.H.portWorkbookEdit.Value = portWorkbook;
                app.H.modelPortEdit.Value = portWorkbook;
            end
            app.onReadWorkbooks();
            if ~isempty(app.DictWorkbookPath) && isfile(app.DictWorkbookPath)
                sheets = app.selectedDictSheets();
                if ~isempty(sheets)
                    app.previewSheet(app.DictWorkbookPath, sheets{1});
                end
            end
        end

        function setTab(app, title)
            %SETTAB 按标题切换标签页（截图与测试用）。
            tabs = app.TabGroup.Children;
            for k = 1:numel(tabs)
                if strcmp(tabs(k).Title, char(title))
                    app.TabGroup.SelectedTab = tabs(k);
                    return;
                end
            end
        end

        function runPipeline(app)
            %RUNPIPELINE 与"一键执行"按钮同一路径（脚本/自动化调用）。
            app.onRunPipeline();
        end

        % ---------------- 常用路径（公共：供测试与脚本驱动） ----------------
        function onFavCellSelected(app, evt)
            % 选中表格行时记录行号并把路径填进输入框，便于查看/复制。
            if isempty(evt.Indices)
                return;
            end
            r = evt.Indices(1);
            app.H.favSelectedRow = r;
            if r <= numel(app.Settings.FavoritePaths)
                app.H.favNewEdit.Value = app.Settings.FavoritePaths{r};
            end
        end

        function onFavGoTo(app)
            p = app.favSelectedPath();
            if isempty(p)
                app.H.favStatus.Text = '请先在上方表格中选择一个路径。';
                return;
            end
            try
                cd(p);
                app.H.favStatus.Text = ['✓ 已切换到 ', p];
                app.Log.info('MATLAB 当前目录已切换: %s', p);
            catch ME
                app.H.favStatus.Text = ['✗ 切换失败: ', ME.message];
                app.Log.warn('切换目录失败 %s: %s', p, ME.message);
            end
        end

        function onFavOpenExplorer(app)
            p = app.favSelectedPath();
            if isempty(p)
                app.H.favStatus.Text = '请先在上方表格中选择一个路径。';
                return;
            end
            try
                winopen(p);
                app.H.favStatus.Text = ['✓ 已在资源管理器打开 ', p];
            catch ME
                app.H.favStatus.Text = ['✗ 打开失败: ', ME.message];
                app.Log.warn('资源管理器打开失败 %s: %s', p, ME.message);
            end
        end

        function onFavBrowseAdd(app)
            d = app.pickFolder(strtrim(app.H.favNewEdit.Value), '选择要添加的常用路径');
            if isequal(d, 0)
                return;
            end
            app.H.favNewEdit.Value = d;
            app.onFavAdd();
        end

        function onFavAdd(app)
            p = strtrim(app.H.favNewEdit.Value);
            if isempty(p)
                app.H.favStatus.Text = '请先输入或浏览一个文件夹路径。';
                return;
            end
            if ~isfolder(p)
                app.H.favStatus.Text = ['✗ 路径不存在或不是文件夹: ', p];
                return;
            end
            app.Settings.addFavoritePath(p);
            app.H.favNewEdit.Value = '';
            app.refreshFavoritePaths();
            app.H.favStatus.Text = ['✓ 已添加 ', p];
            app.Log.info('常用路径已添加: %s', p);
        end

        function onFavRemove(app)
            p = app.favSelectedPath();
            if isempty(p)
                app.H.favStatus.Text = '请先在上方表格中选择要删除的路径。';
                return;
            end
            app.Settings.removeFavoritePath(p);
            app.refreshFavoritePaths();
            app.H.favStatus.Text = ['✓ 已删除 ', p];
            app.Log.info('常用路径已删除: %s', p);
        end

        function refreshFavoritePaths(app)
            if ~isfield(app.H, 'favTable') || ~isvalid(app.H.favTable)
                return;
            end
            data = cell(numel(app.Settings.FavoritePaths), 1);
            for k = 1:numel(data)
                data{k} = app.Settings.FavoritePaths{k};
            end
            app.H.favTable.Data = data;
        end

        function p = favSelectedPath(app)
            % 返回表格中当前选中的常用路径（无选中或越界返回空）。
            p = '';
            r = app.H.favSelectedRow;
            if r < 1 || r > numel(app.Settings.FavoritePaths)
                return;
            end
            p = app.Settings.FavoritePaths{r};
        end
    end

    % =====================================================================
    %  界面搭建
    % =====================================================================
    methods (Access = private)
        function buildUI(app)
            fig = uifigure('Visible', 'off');
            fig.Name = 'SimWorkbench — Simulink 一体化工作台';
            fig.Position = [80, 40, 1280, 840];
            fig.Color = [0.95, 0.95, 0.96];
            fig.CloseRequestFcn = @(~, ~) app.onClose();
            app.UIFigure = fig;

            main = uigridlayout(fig, [2, 1]);
            main.RowHeight = {'1x', 34};
            main.ColumnWidth = {'1x'};
            main.Padding = [6, 6, 6, 6];
            main.RowSpacing = 4;

            app.TabGroup = uitabgroup(main, 'TabLocation', 'left');
            app.TabGroup.Layout.Row = 1;
            app.TabGroup.Layout.Column = 1;

            app.buildWorkflowTab(uitab(app.TabGroup, 'Title', '工作流'));
            app.buildDictTab(uitab(app.TabGroup, 'Title', '数据字典'));
            app.buildModelTab(uitab(app.TabGroup, 'Title', '模型与端口'));
            app.buildSettingsTab(uitab(app.TabGroup, 'Title', '设置'));
            app.buildLogTab(uitab(app.TabGroup, 'Title', '日志'));

            app.buildStatusBar(main);
        end

        function buildStatusBar(app, parent)
            g = uigridlayout(parent, [1, 3]);
            g.Layout.Row = 2;
            g.Layout.Column = 1;
            g.ColumnWidth = {'1x', 120, 180};
            g.Padding = [4, 0, 4, 0];

            app.H.statusLabel = uilabel(g, 'Text', '就绪');
            app.H.statusLabel.Layout.Row = 1;
            app.H.statusLabel.Layout.Column = 1;
            app.H.statusLabel.FontColor = [0.3, 0.3, 0.3];

            app.H.progressLabel = uilabel(g, 'Text', '');
            app.H.progressLabel.Layout.Row = 1;
            app.H.progressLabel.Layout.Column = 2;
            app.H.progressLabel.HorizontalAlignment = 'right';

            app.H.countLabel = uilabel(g, 'Text', '');
            app.H.countLabel.Layout.Row = 1;
            app.H.countLabel.Layout.Column = 3;
            app.H.countLabel.HorizontalAlignment = 'right';
            app.H.countLabel.FontColor = [0.45, 0.45, 0.45];
        end

        % ---------------- 工作流页 ----------------
        function buildWorkflowTab(app, tab)
            g = uigridlayout(tab, [4, 1]);
            g.RowHeight = {'fit', 'fit', '1x', 90};
            g.ColumnWidth = {'1x'};
            g.Padding = [12, 12, 12, 12];
            g.RowSpacing = 8;

            app.pageTitle(g, '工作流', '一份字典工作簿 + 一份端口工作簿 → 校验 → 生成 .sldd → 创建 .slx', 1);

            % 输入文件
            p1 = uipanel(g, 'Title', '输入文件');
            p1.Layout.Row = 2;
            p1.Layout.Column = 1;
            g1 = uigridlayout(p1, [3, 5]);
            g1.RowHeight = {'fit', 'fit', 'fit'};
            g1.ColumnWidth = {110, '1x', 90, 110, 90};
            g1.Padding = [10, 6, 10, 6];
            g1.RowSpacing = 4;

            app.mkLabel(g1, '字典工作簿', 1, 1);
            app.H.dictWorkbookEdit = app.mkEdit(g1, '', 1, 2);
            app.mkButton(g1, '浏览…', 1, 3, @(~, ~) app.onBrowseDictWorkbook());
            app.H.dictDetectLabel = app.mkLabel(g1, '未读取', 1, 4);
            app.H.dictDetectLabel.FontColor = [0.5, 0.5, 0.5];
            app.mkButton(g1, '读取', 1, 5, @(~, ~) app.onReadWorkbooks(), 'FontWeight', 'bold');

            app.mkLabel(g1, '端口工作簿', 2, 1);
            app.H.portWorkbookEdit = app.mkEdit(g1, '', 2, 2);
            app.mkButton(g1, '浏览…', 2, 3, @(~, ~) app.onBrowsePortWorkbook());
            app.H.portDetectLabel = app.mkLabel(g1, '未读取', 2, 4);
            app.H.portDetectLabel.FontColor = [0.5, 0.5, 0.5];
            app.mkButton(g1, '读取', 2, 5, @(~, ~) app.onReadWorkbooks());

            app.H.inputSummary = app.mkLabel(g1, '尚未选择工作簿。', 3, [1, 5], 'FontColor', [0.45, 0.45, 0.45]);

            % 步骤
            p2 = uipanel(g, 'Title', '流水线步骤');
            p2.Layout.Row = 3;
            p2.Layout.Column = 1;
            g2 = uigridlayout(p2, [2, 1]);
            g2.RowHeight = {'1x', 'fit'};
            g2.Padding = [10, 6, 10, 6];
            data = cell(numel(app.Steps), 3);
            for i = 1:numel(app.Steps)
                data{i, 1} = app.Steps{i};
                data{i, 2} = '待执行';
                data{i, 3} = '';
            end
            app.H.stepTable = uitable(g2, 'ColumnName', {'步骤', '状态', '详情'}, 'Data', data, ...
                'ColumnWidth', {180, 90, 'auto'}, 'RowName', []);
            app.H.stepTable.Layout.Row = 1;
            app.H.stepTable.Layout.Column = 1;

            app.H.runButton = app.mkButton(g2, '一键执行', 2, 1, @(~, ~) app.onRunPipeline(), ...
                'FontWeight', 'bold', 'BackgroundColor', [0.15, 0.55, 0.15], 'FontColor', [1, 1, 1]);

            % 摘要
            p3 = uipanel(g, 'Title', '结果摘要');
            p3.Layout.Row = 4;
            p3.Layout.Column = 1;
            g3 = uigridlayout(p3, [1, 2]);
            g3.ColumnWidth = {'1x', 140};
            g3.Padding = [10, 6, 10, 6];
            app.H.summaryArea = uitextarea(g3, 'Editable', 'off', 'Value', {'尚未运行。'});
            app.H.summaryArea.Layout.Row = 1;
            app.H.summaryArea.Layout.Column = 1;
            app.mkButton(g3, '清空摘要', 1, 2, @(~, ~) app.clearSummary());
        end

        % ---------------- 数据字典页 ----------------
        function buildDictTab(app, tab)
            g = uigridlayout(tab, [2, 2]);
            g.RowHeight = {'fit', '1x'};
            g.ColumnWidth = {420, '1x'};
            g.Padding = [12, 12, 12, 12];
            g.RowSpacing = 8;
            g.ColumnSpacing = 10;

            app.pageTitle(g, '数据字典', 'Excel（8 表）↔ .sldd：导出模板、校验、生成对象脚本、写入字典、反向同步', 1, [1, 2]);

            left = uipanel(g, 'Title', '工作簿与操作');
            left.Layout.Row = 2;
            left.Layout.Column = 1;
            gl = uigridlayout(left, [14, 3]);
            gl.ColumnWidth = {96, '1x', 72};
            gl.RowHeight = {'fit','fit',160,'fit','fit','fit','fit','fit','fit','fit','fit','fit','fit','fit'};
            gl.Padding = [10, 8, 10, 8];
            gl.RowSpacing = 6;
            gl.ColumnSpacing = 6;

            app.mkLabel(gl, '字典工作簿', 1, 1);
            app.H.dictEdit = app.mkEdit(gl, '', 1, 2);
            % 在这一页直接改字典工作簿也要生效：同步到工作流页并重新读取。
            app.H.dictEdit.ValueChangedFcn = @(src, ~) app.onDictWorkbookEdited(src.Value);
            app.mkButton(gl, '浏览…', 1, 3, @(~, ~) app.onBrowseDictWorkbook('dict'));

            app.mkLabel(gl, '工作表（可多选）', 2, [1, 3], 'FontWeight', 'bold');
            app.H.sheetList = uilistbox(gl, 'Items', {}, 'Multiselect', 'on', 'Value', {});
            app.H.sheetList.Layout.Row = 3;
            app.H.sheetList.Layout.Column = [1, 3];

            selGrid = uigridlayout(gl, [1, 3]);
            selGrid.Layout.Row = 4;
            selGrid.Layout.Column = [1, 3];
            selGrid.ColumnWidth = {'1x','1x','1x'};
            selGrid.Padding = [0, 0, 0, 0];
            app.mkButton(selGrid, '全选', 1, 1, @(~, ~) app.selectSheets('all'));
            app.mkButton(selGrid, '清空', 1, 2, @(~, ~) app.selectSheets('none'));
            app.mkButton(selGrid, '标准勾选', 1, 3, @(~, ~) app.selectSheets('default'));

            app.H.validateChk = app.mkCheck(gl, '执行前先做数据校验', 5, [1, 3], true);
            app.H.confirmChk = app.mkCheck(gl, '写入字典前弹确认框', 6, [1, 3], true);
            app.H.cleanDictChk = app.mkCheck(gl, '写入时删除 .sldd 中多余变量（危险）', 7, [1, 3], false);
            app.H.cleanExcelChk = app.mkCheck(gl, '反向同步时清空 Excel 旧内容（危险）', 8, [1, 3], false);

            app.mkLabel(gl, '对象脚本', 9, 1);
            app.H.scriptEdit = app.mkEdit(gl, '', 9, 2);
            app.mkButton(gl, '浏览…', 9, 3, @(~, ~) app.onBrowseOutput('script'));

            app.mkLabel(gl, '数据字典', 10, 1);
            app.H.slddEdit = app.mkEdit(gl, '', 10, 2);
            app.mkButton(gl, '浏览…', 10, 3, @(~, ~) app.onBrowseOutput('dict'));

            actions = uigridlayout(gl, [2, 3]);
            actions.Layout.Row = [11, 12];
            actions.Layout.Column = [1, 3];
            actions.RowHeight = {'1x','1x'};
            actions.ColumnWidth = {'1x','1x','1x'};
            actions.Padding = [0, 0, 0, 0];
            app.mkButton(actions, '校验所选表', 1, 1, @(~, ~) app.onDictAction('validate'), 'FontWeight','bold');
            app.mkButton(actions, '预览所选表', 1, 2, @(~, ~) app.onDictAction('preview'));
            app.mkButton(actions, '生成对象脚本', 1, 3, @(~, ~) app.onDictAction('generate'), 'FontWeight','bold');
            app.mkButton(actions, '写入 .sldd', 2, 1, @(~, ~) app.onDictAction('write'), ...
                'FontWeight','bold', 'BackgroundColor', [0.82, 0.90, 0.82]);
            app.mkButton(actions, '↔ SLDD → Excel', 2, [2, 3], @(~, ~) app.onDictAction('reverse'));

            app.mkButton(gl, '导出 Excel 模板…', 13, [1, 3], @(~, ~) app.onDictAction('template'), ...
                'FontWeight', 'bold');
            app.H.dictHint = app.mkLabel(gl, '提示：右侧显示校验问题或工作表预览。', 14, [1, 3], ...
                'FontColor', [0.45, 0.45, 0.45]);

            right = uipanel(g, 'Title', '校验结果 / 预览');
            right.Layout.Row = 2;
            right.Layout.Column = 2;
            gr = uigridlayout(right, [2, 1]);
            gr.RowHeight = {'fit', '1x'};
            gr.Padding = [10, 8, 10, 8];
            app.H.dictResultLabel = app.mkLabel(gr, '尚未校验。', 1, 1, 'FontColor', [0.45,0.45,0.45]);
            app.H.dictTable = uitable(gr, 'ColumnName', {'工作表','行','列','级别','问题'}, ...
                'Data', cell(0, 5), 'RowName', [], 'ColumnWidth', {90, 60, 60, 70, 'auto'});
            app.H.dictTable.Layout.Row = 2;
            app.H.dictTable.Layout.Column = 1;
        end

        % ---------------- 模型与端口页 ----------------
        function buildModelTab(app, tab)
            g = uigridlayout(tab, [2, 2]);
            g.RowHeight = {'fit', '1x'};
            g.ColumnWidth = {480, '1x'};
            g.Padding = [12, 12, 12, 12];
            g.RowSpacing = 8;
            g.ColumnSpacing = 10;

            app.pageTitle(g, '模型与端口', '创建 / 更新 Simulink 模型：求解器、TLC、数据字典、端口与 Code Mapping', 1, [1, 2]);

            left = uipanel(g, 'Title', '模型配置');
            left.Layout.Row = 2;
            left.Layout.Column = 1;
            d = swb.Schema.modelConfigDefaults();
            gl = uigridlayout(left, [15, 3]);
            gl.RowHeight = [repmat({'fit'}, 1, 11), {'fit','fit','fit','fit'}];
            gl.ColumnWidth = {110, '1x', 78};
            gl.Padding = [10, 8, 10, 8];
            gl.RowSpacing = 6;

            app.mkLabel(gl, '模型名称', 1, 1);
            % 可编辑下拉框：既能手写模型名称，也能直接选一个现有模型（已打开或保存目录里的 .slx）。
            app.H.modelNameEdit = uidropdown(gl, 'Editable', 'on', ...
                'Items', {d.ModelName}, 'Value', d.ModelName, ...
                'Tooltip', '直接输入模型名称，或从下拉列表选择已打开 / 保存目录中的现有模型');
            app.H.modelNameEdit.Layout.Row = 1;
            app.H.modelNameEdit.Layout.Column = 2;
            app.H.modelNameEdit.ValueChangedFcn = @(~, ~) app.onModelNameChanged();
            app.H.modelRefreshButton = app.mkButton(gl, '刷新', 1, 3, ...
                @(~, ~) app.refreshModelCandidates(), ...
                'Tooltip', '重新扫描已打开模型和保存目录中的 .slx');
            app.refreshModelCandidates();

            app.mkLabel(gl, '保存目录', 2, 1);
            app.H.modelFolderEdit = app.mkEdit(gl, pwd, 2, 2);
            app.mkButton(gl, '浏览…', 2, 3, @(~, ~) app.onBrowseFolder());

            app.mkLabel(gl, '求解器', 3, 1);
            app.H.solverDrop = uidropdown(gl, 'Items', {'连续（Variable-step）','离散（Fixed-step）'}, ...
                'Value', '离散（Fixed-step）');
            app.H.solverDrop.Layout.Row = 3;
            app.H.solverDrop.Layout.Column = 2;

            app.mkLabel(gl, '时间步长', 4, 1);
            app.H.sampleTimeEdit = app.mkEdit(gl, d.SampleTime, 4, 2);
            app.mkLabel(gl, '(秒，仅离散)', 4, 3, 'FontColor', [0.5,0.5,0.5]);

            app.mkLabel(gl, '系统目标文件', 5, 1);
            app.H.tlcEdit = app.mkEdit(gl, d.SystemTargetFile, 5, 2);
            app.mkButton(gl, '浏览…', 5, 3, @(~, ~) app.onBrowseTlc());

            app.H.genCodeChk = app.mkCheck(gl, '仅生成代码（GenCodeOnly）', 6, [1, 2], d.GenCodeOnly);

            app.mkLabel(gl, '数据字典', 7, 1);
            app.H.modelDictEdit = app.mkEdit(gl, '', 7, 2);
            app.mkButton(gl, '浏览…', 7, 3, @(~, ~) app.onBrowseSldd());

            app.mkLabel(gl, '端口工作簿', 8, 1);
            app.H.modelPortEdit = app.mkEdit(gl, '', 8, 2);
            app.mkButton(gl, '浏览…', 8, 3, @(~, ~) app.onBrowsePortWorkbook('model'));

            app.H.codeMapChk = app.mkCheck(gl, '使用 Code Mapping（StorageClass / Identifier）', 9, [1, 2], d.ApplyCodeMapping);
            app.H.openAfterChk = app.mkCheck(gl, '创建后打开模型', 10, [1, 2], d.OpenAfterCreate);

            app.mkLabel(gl, '名称冲突', 11, 1);
            app.H.conflictDrop = uidropdown(gl, 'Items', {'询问','覆盖','加数字后缀','取消'}, 'Value', '询问');
            app.H.conflictDrop.Layout.Row = 11;
            app.H.conflictDrop.Layout.Column = 2;

            actions = uigridlayout(gl, [2, 3]);
            actions.Layout.Row = [12, 13];
            actions.Layout.Column = [1, 3];
            actions.RowHeight = {'1x','1x'};
            actions.ColumnWidth = {'1x','1x','1x'};
            actions.Padding = [0, 0, 0, 0];
            app.mkButton(actions, '创建模型', 1, 1, @(~, ~) app.onModelAction('create'), ...
                'FontWeight','bold', 'BackgroundColor', [0.15, 0.55, 0.15], 'FontColor', [1,1,1]);
            app.mkButton(actions, '更新端口', 1, 2, @(~, ~) app.onModelAction('update'), 'FontWeight','bold');
            app.mkButton(actions, '导出端口', 1, 3, @(~, ~) app.onModelAction('export'));
            app.H.modelStatusLabel = app.mkLabel(actions, '就绪。', 2, [1, 3], 'FontColor', [0.45,0.45,0.45]);

            right = uipanel(g, 'Title', '端口预览');
            right.Layout.Row = 2;
            right.Layout.Column = 2;
            gr = uigridlayout(right, [2, 1]);
            gr.RowHeight = {'fit', '1x'};
            gr.Padding = [10, 8, 10, 8];
            app.H.portSummaryLabel = app.mkLabel(gr, '尚未读取端口工作簿。', 1, 1, 'FontColor', [0.45,0.45,0.45]);
            app.H.portTable = uitable(gr, 'ColumnName', {'方向','名称','数据类型','StorageClass','Identifier','HeaderFile','DefinitionFile'}, ...
                'Data', cell(0, 7), 'RowName', [], 'ColumnWidth', {60, 100, 80, 130, 110, 110, 110});
            app.H.portTable.Layout.Row = 2;
            app.H.portTable.Layout.Column = 1;
        end

        % ---------------- 设置页 ----------------
        function buildSettingsTab(app, tab)
            g = uigridlayout(tab, [3, 1]);
            g.RowHeight = {'fit', '1x', 'fit'};
            g.Padding = [12, 12, 12, 12];
            g.RowSpacing = 8;
            app.pageTitle(g, '设置', ['机器级配置保存在 App 安装目录下：', swb.Settings.appRootPublic(), filesep, 'simworkbench.json'], 1);

            p = uipanel(g, 'Title', '环境与默认值');
            p.Layout.Row = 2;
            p.Layout.Column = 1;
            gp = uigridlayout(p, [7, 4]);
            gp.RowHeight = repmat({'fit'}, 1, 7);
            gp.ColumnWidth = {130, '1x', 90, 110};
            gp.Padding = [12, 10, 12, 10];
            gp.RowSpacing = 8;

            app.mkLabel(gp, 'Python 路径', 1, 1, 'FontWeight', 'bold');
            app.H.pythonEdit = app.mkEdit(gp, app.Settings.PythonPath, 1, 2);
            app.mkButton(gp, '浏览…', 1, 3, @(~, ~) app.onBrowsePython());
            app.mkButton(gp, '测试', 1, 4, @(~, ~) app.onTestPython());
            app.mkLabel(gp, '用于模板生成与反向同步；不配置也可用（退化为 MATLAB 基本模板）。', 2, [1, 4], ...
                'FontColor', [0.45, 0.45, 0.45]);

            app.mkLabel(gp, '默认 TLC', 3, 1);
            app.H.defaultTlcEdit = app.mkEdit(gp, app.Settings.DefaultTlc, 3, 2);

            app.mkLabel(gp, '默认冲突策略', 4, 1);
            app.H.defaultConflictDrop = uidropdown(gp, 'Items', {'询问','覆盖','加数字后缀','取消'}, 'Value', '询问');
            app.H.defaultConflictDrop.Layout.Row = 4;
            app.H.defaultConflictDrop.Layout.Column = 2;

            app.mkLabel(gp, '模板 Config', 5, 1);
            app.H.templateCfgInfo = app.mkLabel(gp, app.templateConfigSummary(), 5, 2, ...
                'FontColor', [0.45,0.45,0.45], 'WordWrap', 'on');
            app.mkButton(gp, '编辑…', 5, 3, @(~, ~) app.onEditTemplateConfig());

            app.H.settingsStatus = app.mkLabel(gp, '', 6, [1, 4], 'FontColor', [0.45,0.45,0.45]);

            btns = uigridlayout(gp, [1, 2]);
            btns.Layout.Row = 7;
            btns.Layout.Column = [1, 4];
            btns.ColumnWidth = {140, 140};
            btns.Padding = [0, 0, 0, 0];
            app.mkButton(btns, '保存设置', 1, 1, @(~, ~) app.onSaveSettings(), ...
                'FontWeight','bold', 'BackgroundColor', [0.15, 0.55, 0.15], 'FontColor', [1,1,1]);
            app.mkButton(btns, '重新读取', 1, 2, @(~, ~) app.applySettingsToUI());

            app.buildFavoritePathsPanel(g);
        end

        % ---------------- 日志页 ----------------
        function buildLogTab(app, tab)
            g = uigridlayout(tab, [2, 1]);
            g.RowHeight = {'1x', 'fit'};
            g.Padding = [12, 12, 12, 12];
            g.RowSpacing = 8;
            app.H.logArea = uitextarea(g, 'Editable', 'off', 'Value', '', 'FontName', 'Consolas');
            app.H.logArea.Layout.Row = 1;
            app.H.logArea.Layout.Column = 1;

            btns = uigridlayout(g, [1, 4]);
            btns.Layout.Row = 2;
            btns.Layout.Column = 1;
            btns.ColumnWidth = {120, 120, '1x', 120};
            btns.Padding = [0, 0, 0, 0];
            app.mkButton(btns, '清空日志', 1, 1, @(~, ~) app.onClearLog());
            app.mkButton(btns, '复制日志', 1, 2, @(~, ~) app.onCopyLog());
            app.mkButton(btns, '导出日志…', 1, 4, @(~, ~) app.onExportLog());
        end

        % ---------------- 小工具 ----------------
        function pageTitle(app, parent, title, subtitle, row, col)
            if nargin < 6; col = 1; end
            box = uigridlayout(parent, [2, 1]);
            box.Layout.Row = row;
            box.Layout.Column = col;
            box.RowHeight = {'fit', 'fit'};
            box.Padding = [2, 2, 2, 2];
            box.RowSpacing = 2;
            t = uilabel(box, 'Text', title, 'FontSize', 16, 'FontWeight', 'bold');
            t.Layout.Row = 1;
            t.Layout.Column = 1;
            st = uilabel(box, 'Text', subtitle, 'FontColor', [0.45, 0.45, 0.45]);
            st.Layout.Row = 2;
            st.Layout.Column = 1;
        end

        function c = mkLabel(~, parent, text, r, col, varargin)
            c = uilabel(parent, 'Text', text, varargin{:});
            c.Layout.Row = r;
            c.Layout.Column = col;
        end

        function c = mkEdit(~, parent, value, r, col)
            c = uieditfield(parent, 'text', 'Value', value);
            c.Layout.Row = r;
            c.Layout.Column = col;
        end

        function c = mkButton(~, parent, text, r, col, fcn, varargin)
            c = uibutton(parent, 'push', 'Text', text, 'ButtonPushedFcn', fcn, varargin{:});
            c.Layout.Row = r;
            c.Layout.Column = col;
        end

        function c = mkCheck(~, parent, text, r, col, value)
            c = uicheckbox(parent, 'Text', text, 'Value', logical(value));
            c.Layout.Row = r;
            c.Layout.Column = col;
        end

        function fr = fileRow(app, parent, label, row, browseFcn)
            g = uigridlayout(parent, [1, 3]);
            g.Layout.Row = row;
            g.Layout.Column = 1;
            g.ColumnWidth = {90, '1x', 70};
            g.Padding = [0, 0, 0, 0];
            app.mkLabel(g, label, 1, 1);
            fr.edit = uieditfield(g, 'text', 'Value', '');
            fr.edit.Layout.Row = 1;
            fr.edit.Layout.Column = 2;
            app.mkButton(g, '浏览…', 1, 3, browseFcn);
        end

        % ---------------- 常用路径 ----------------
        function buildFavoritePathsPanel(app, parent)
            fp = uipanel(parent, 'Title', '常用路径');
            fp.Layout.Row = 3;
            fp.Layout.Column = 1;
            gf = uigridlayout(fp, [2, 1]);
            gf.RowHeight = {'1x', 'fit'};
            gf.Padding = [10, 8, 10, 8];
            gf.RowSpacing = 6;

            app.H.favSelectedRow = 0;   % 当前选中行（uitable 无可读的选中属性，自行维护）
            app.H.favTable = uitable(gf, 'ColumnName', {'路径'}, 'Data', cell(0, 1), ...
                'RowName', [], 'ColumnWidth', {'auto'}, 'CellSelectionCallback', @(~, evt) app.onFavCellSelected(evt));
            app.H.favTable.Layout.Row = 1;
            app.H.favTable.Layout.Column = 1;

            fb = uigridlayout(gf, [2, 4]);
            fb.Layout.Row = 2;
            fb.Layout.Column = 1;
            fb.RowHeight = {'fit', 'fit'};
            fb.ColumnWidth = {170, 190, '1x', 90};
            fb.Padding = [0, 0, 0, 0];
            fb.RowSpacing = 4;

            app.mkButton(fb, '切换到该文件夹', 1, 1, @(~, ~) app.onFavGoTo());
            app.mkButton(fb, '在资源管理器打开', 1, 2, @(~, ~) app.onFavOpenExplorer());
            app.H.favStatus = app.mkLabel(fb, '', 1, [3, 4], 'FontColor', [0.45, 0.45, 0.45]);

            app.H.favNewEdit = uieditfield(fb, 'text', 'Placeholder', '输入或浏览要添加的文件夹路径…');
            app.H.favNewEdit.Layout.Row = 2;
            app.H.favNewEdit.Layout.Column = [1, 2];
            app.mkButton(fb, '浏览…', 2, 3, @(~, ~) app.onFavBrowseAdd());
            app.mkButton(fb, '删除', 2, 4, @(~, ~) app.onFavRemove(), 'Tooltip', '删除选中的常用路径');
            app.refreshFavoritePaths();
        end

    end

    % =====================================================================
    %  回调与调度
    % =====================================================================
    methods (Access = private)
        function onClose(app)
            delete(app);
        end

        function onLogEntry(app, entry)
            if isfield(app.H, 'logArea') && ~isempty(app.H.logArea) && isvalid(app.H.logArea)
                v = app.H.logArea.Value;
                if ischar(v)
                    v = {v};
                end
                if isempty(v)
                    v = {};
                end
                v{end+1} = sprintf('[%s] %-7s %s', entry.time, upper(entry.level), entry.message);
                if numel(v) > 2000
                    v = v(end-1999:end);
                end
                app.H.logArea.Value = v;
            end
            switch entry.level
                case 'error'
                    app.setStatus(entry.message, 'error');
                case 'warn'
                    app.setStatus(entry.message, 'warn');
                otherwise
                    app.setStatus(entry.message, 'info');
            end
            if isfield(app.H, 'countLabel') && isvalid(app.H.countLabel)
                app.H.countLabel.Text = sprintf('错误 %d · 警告 %d', app.Log.count('error'), app.Log.count('warn'));
            end
        end

        function setStatus(app, msg, level)
            if ~isfield(app.H, 'statusLabel') || isempty(app.H.statusLabel) || ~isvalid(app.H.statusLabel)
                return;
            end
            app.H.statusLabel.Text = char(msg);
            switch level
                case 'error'
                    app.H.statusLabel.FontColor = [0.75, 0.10, 0.10];
                case 'warn'
                    app.H.statusLabel.FontColor = [0.80, 0.50, 0.00];
                case 'ok'
                    app.H.statusLabel.FontColor = [0.10, 0.50, 0.10];
                otherwise
                    app.H.statusLabel.FontColor = [0.30, 0.30, 0.30];
            end
        end

        function tf = hasService(~, name)
            tf = exist(char(name), 'class') == 8;
        end

        function notReady(app, name)
            app.Log.warn('服务 %s 尚未接入（teammate 实现中）。', char(name));
        end

        %% ---------- 工作簿选择与读取 ----------
        function onBrowseDictWorkbook(app, varargin)
            [f, d] = app.pickOpenFile({'*.xlsx;*.xls', 'Excel 工作簿 (*.xlsx, *.xls)'}, '选择数据字典工作簿');
            if isequal(f, 0)
                return;
            end
            app.DictWorkbookPath = fullfile(d, f);
            app.H.dictWorkbookEdit.Value = app.DictWorkbookPath;
            app.syncDictWorkbookEdit();
            app.Settings.LastDictWorkbook = app.DictWorkbookPath;
            app.Settings.save();
            app.onReadWorkbooks();
        end

        function onBrowsePortWorkbook(app, varargin)
            [f, d] = app.pickOpenFile({'*.xlsx;*.xls', 'Excel 工作簿 (*.xlsx, *.xls)'}, '选择端口工作簿');
            if isequal(f, 0)
                return;
            end
            app.PortWorkbookPath = fullfile(d, f);
            app.H.portWorkbookEdit.Value = app.PortWorkbookPath;
            if isfield(app.H, 'modelPortEdit') && isvalid(app.H.modelPortEdit)
                app.H.modelPortEdit.Value = app.PortWorkbookPath;
            end
            app.Settings.LastPortWorkbook = app.PortWorkbookPath;
            app.Settings.save();
            app.onReadWorkbooks();
        end

        function onReadWorkbooks(app)
            app.Log.section('读取工作簿');
            app.DictWorkbookPath = strtrim(app.H.dictWorkbookEdit.Value);
            app.PortWorkbookPath = strtrim(app.H.portWorkbookEdit.Value);
            app.syncDictWorkbookEdit();

            if ~isempty(app.DictWorkbookPath)
                info = swb.Workbook.detect(app.DictWorkbookPath);
                app.H.dictDetectLabel.Text = sprintf('字典表 %d 张', numel(info.dictSheets));
                app.H.dictDetectLabel.FontColor = [0.10, 0.50, 0.10];
                app.Log.info('字典工作簿: %s', app.DictWorkbookPath);
                app.Log.info('  工作表: %s', strjoin(info.sheets, ', '));
                if info.hasDict
                    app.Log.info('  可导入表: %s', strjoin(info.dictSheets, ', '));
                    app.H.sheetList.Items = info.dictSheets;
                    want = {'Signal', 'Parameter', 'Bus', 'BusElement'};
                    sel = intersect(want, info.dictSheets, 'stable');
                    if isempty(sel) && ~isempty(info.dictSheets)
                        sel = info.dictSheets(1);
                    end
                    app.H.sheetList.Value = sel;
                    app.populateDefaultOutputs(app.DictWorkbookPath);
                else
                    app.Log.warn('  该工作簿没有可导入的数据字典表。');
                end
                app.updateStep(1, '完成', sprintf('%d 张表', numel(info.dictSheets)));
            else
                app.H.dictDetectLabel.Text = '未读取';
                app.H.dictDetectLabel.FontColor = [0.5, 0.5, 0.5];
            end

            if ~isempty(app.PortWorkbookPath)
                [inP, outP, pinfo] = swb.PortTable.read(app.PortWorkbookPath);
                app.H.portDetectLabel.Text = sprintf('端口 %d/%d', numel(inP), numel(outP));
                app.H.portDetectLabel.FontColor = [0.10, 0.50, 0.10];
                app.Log.info('端口工作簿: %s（输入 %d，输出 %d，模式 %s）', app.PortWorkbookPath, numel(inP), numel(outP), pinfo.mode);
                app.showPorts(inP, outP);
                app.updateStep(1, '完成', sprintf('端口 %d/%d', numel(inP), numel(outP)));
            else
                app.H.portDetectLabel.Text = '未读取';
                app.H.portDetectLabel.FontColor = [0.5, 0.5, 0.5];
            end

            app.refreshSummary();
        end

        function populateDefaultOutputs(app, dictPath)
            %POPULATEDEFAULTOUTPUTS 按字典工作簿推导默认的对象脚本与 .sldd 路径。
            %   换工作簿时默认名要跟着变；但用户手选过的路径不能冲掉，
            %   所以只在字段为空、或仍等于上次自动填入的值时才覆盖。
            [d, base, ~] = fileparts(dictPath);
            wantScript = fullfile(d, [base, '_objects.m']);
            wantSldd = fullfile(d, [base, '.sldd']);
            if app.followsAutoOutput(app.H.scriptEdit.Value, app.AutoScriptFile)
                app.H.scriptEdit.Value = wantScript;
            end
            if app.followsAutoOutput(app.H.slddEdit.Value, app.AutoSlddFile)
                app.H.slddEdit.Value = wantSldd;
            end
            app.AutoScriptFile = wantScript;
            app.AutoSlddFile = wantSldd;
        end

        function tf = followsAutoOutput(~, currentValue, autoValue)
            %FOLLOWSAUTOOUTPUT 当前值是否还停留在自动填入的状态（未手改）。
            cur = strtrim(currentValue);
            tf = isempty(cur) || strcmp(cur, strtrim(autoValue));
        end

        function syncDictWorkbookEdit(app)
            %SYNCDICTWORKBOOKEDIT 工作流页与数据字典页共用同一份字典工作簿路径。
            if isfield(app.H, 'dictEdit') && isvalid(app.H.dictEdit)
                if ~strcmp(strtrim(app.H.dictEdit.Value), app.DictWorkbookPath)
                    app.H.dictEdit.Value = app.DictWorkbookPath;
                end
            end
        end

        function onDictWorkbookEdited(app, value)
            %ONDICTWORKBOOKEDITED 数据字典页手改工作簿路径后，同步到工作流页并重新读取。
            app.H.dictWorkbookEdit.Value = strtrim(value);
            app.onReadWorkbooks();
        end

        function showPorts(app, inPorts, outPorts)
            data = cell(numel(inPorts) + numel(outPorts), 7);
            r = 0;
            for k = 1:numel(inPorts)
                r = r + 1;
                p = inPorts(k);
                data(r, :) = {'输入', p.name, p.dataType, p.storageClass, p.identifier, p.headerFile, p.definitionFile};
            end
            for k = 1:numel(outPorts)
                r = r + 1;
                p = outPorts(k);
                data(r, :) = {'输出', p.name, p.dataType, p.storageClass, p.identifier, p.headerFile, p.definitionFile};
            end
            app.H.portTable.Data = data;
            app.H.portSummaryLabel.Text = sprintf('输入 %d 个，输出 %d 个。', numel(inPorts), numel(outPorts));
        end

        %% ---------- 数据字典动作 ----------
        function sheets = selectedDictSheets(app)
            sheets = app.H.sheetList.Value;
            if ischar(sheets)
                sheets = {sheets};
            end
        end

        function selectSheets(app, kind)
            switch kind
                case 'all'
                    app.H.sheetList.Value = app.H.sheetList.Items;
                case 'none'
                    app.H.sheetList.Value = {};
                otherwise
                    want = {'Signal', 'Parameter', 'Bus', 'BusElement'};
                    sel = intersect(want, app.H.sheetList.Items, 'stable');
                    app.H.sheetList.Value = sel;
            end
        end

        function onBrowseOutput(app, kind)
            switch kind
                case 'script'
                    [f, d] = app.pickSaveFile({'*.m', 'MATLAB 脚本 (*.m)'}, '对象脚本保存为', 'objects.m');
                otherwise
                    % 选择已有字典用打开对话框；新建字典名可手填或由工作簿自动推导。
                    [f, d] = app.pickOpenFile({'*.sldd', '数据字典 (*.sldd)'}, '选择数据字典');
            end
            if isequal(f, 0)
                return;
            end
            if strcmp(kind, 'script')
                app.H.scriptEdit.Value = fullfile(d, f);
            else
                app.H.slddEdit.Value = fullfile(d, f);
            end
        end

        function onDictAction(app, kind)
            app.Log.section('数据字典 → %s', kind);
            dictPath = strtrim(app.H.dictEdit.Value);
            sheets = app.selectedDictSheets();
            switch kind
                case 'validate'
                    if isempty(dictPath) || ~isfile(dictPath)
                        app.Log.err('请先选择有效的字典工作簿。');
                        return;
                    end
                    if ~app.hasService('swb.Validator')
                        app.notReady('swb.Validator');
                        return;
                    end
                    issues = swb.Validator.run(dictPath, sheets);
                    app.showIssues(issues);
                    app.updateStep(2, app.statusWord(numel(issues)), sprintf('%d 个问题', numel(issues)));
                case 'preview'
                    if isempty(dictPath) || ~isfile(dictPath)
                        app.Log.err('请先选择有效的字典工作簿。');
                        return;
                    end
                    if isempty(sheets)
                        app.Log.warn('请至少选择一张工作表。');
                        return;
                    end
                    app.previewSheet(dictPath, sheets{1});
                case 'generate'
                    if ~app.hasService('swb.ScriptBuilder')
                        app.notReady('swb.ScriptBuilder');
                        return;
                    end
                    outFile = strtrim(app.H.scriptEdit.Value);
                    result = swb.ScriptBuilder.build(dictPath, sheets, outFile);
                    app.Log.info('对象脚本已生成: %d 个对象，%s', numel(result.objects), outFile);
                    if isfield(result, 'enumFiles') && ~isempty(result.enumFiles)
                        app.Log.info('枚举类文件: %s', strjoin(result.enumFiles, ', '));
                    end
                    app.updateStep(3, '完成', sprintf('%d 个对象', numel(result.objects)));
                    app.setSummary(sprintf('对象脚本: %s\n对象数: %d', outFile, numel(result.objects)));
                case 'write'
                    if ~app.hasService('swb.Dictionary') || ~app.hasService('swb.ScriptBuilder')
                        app.notReady('swb.Dictionary / swb.ScriptBuilder');
                        return;
                    end
                    sldd = strtrim(app.H.slddEdit.Value);
                    if isempty(sldd)
                        app.Log.err('请先指定数据字典路径。');
                        return;
                    end
                    res = swb.ScriptBuilder.build(dictPath, sheets, strtrim(app.H.scriptEdit.Value));
                    if app.H.confirmChk.Value
                        choice = app.confirmAndRaise(sprintf('即将把 %d 个对象写入：\n%s', numel(res.objects), sldd), ...
                            '确认写入数据字典', {'写入', '取消'}, 1, 2, 'question');
                        if ~strcmp(choice, '写入')
                            app.Log.info('已取消写入。');
                            return;
                        end
                    end
                    opts = struct('CleanExtra', logical(app.H.cleanDictChk.Value), ...
                                  'ConfirmFcn', [], 'Log', app.Log, 'Verify', true);
                    stats = swb.Dictionary.writeScript(sldd, res.text, opts);
                    app.Log.info('写入字典: +%d ~%d -%d x%d（共 %d 条）', ...
                        stats.added, stats.updated, stats.skipped, stats.failed, stats.totalAfter);
                    app.updateStep(4, app.statusWord(stats.failed), ...
                        sprintf('+%d ~%d -%d x%d', stats.added, stats.updated, stats.skipped, stats.failed));
                case 'reverse'
                    if ~app.hasService('swb.ReverseSync')
                        app.notReady('swb.ReverseSync');
                        return;
                    end
                    sldd = strtrim(app.H.slddEdit.Value);
                    if isempty(dictPath)
                        % Excel 路径为空时，自动命名为与 .sldd 同目录同名（.xlsx）。
                        [slddDir, slddBase] = fileparts(sldd);
                        dictPath = fullfile(slddDir, [slddBase '.xlsx']);
                        app.Log.info('Excel 路径为空，自动导出到：%s', dictPath);
                    end
                    opts = struct('CleanExcel', logical(app.H.cleanExcelChk.Value), ...
                                  'Exe', app.Settings.PythonPath, 'Log', app.Log, ...
                                  'Config', app.Settings.TemplateConfig);
                    result = swb.ReverseSync.toWorkbook(sldd, dictPath, opts);
                    counts = result.rows;
                    if result.ok
                        app.Log.info('SLDD → Excel 导出完成：%s（Signal %d / Parameter %d / Const %d / Bus %d / BusElement %d / Enum %d）。', ...
                            result.workbookPath, counts.Signal, counts.Parameter, counts.Const, ...
                            counts.Bus, counts.BusElement, counts.Enum);
                        app.setStatus(sprintf('导出完成：%s', result.workbookPath), 'ok');
                        app.updateStep(4, '完成', 'SLDD → Excel');
                    else
                        msg = 'SLDD → Excel 导出失败。';
                        if ~isempty(result.errorText)
                            msg = [msg ' ' result.errorText];
                        end
                        app.Log.err('%s', msg);
                        app.setStatus(msg, 'error');
                        app.updateStep(4, '有问题', 'SLDD → Excel');
                    end
                case 'template'
                    if ~app.hasService('swb.TemplateExport')
                        app.notReady('swb.TemplateExport');
                        return;
                    end
                    dictPath = strtrim(app.H.dictEdit.Value);
                    if isempty(dictPath)
                        dictPath = strtrim(app.H.dictWorkbookEdit.Value);
                    end
                    [f, d] = app.pickSaveFile({'*.xlsx', 'Excel 工作簿 (*.xlsx)'}, ...
                        '导出 Excel 模板', swb.TemplateExport.defaultFile(dictPath));
                    if isequal(f, 0)
                        app.Log.info('已取消导出模板。');
                        return;
                    end
                    outFile = fullfile(d, f);
                    choice = app.confirmAndRaise(sprintf( ...
                        ['模板将写到：%s' newline newline ...
                         '含示例数据：写入示例行，并带 Config 下拉列表。' newline ...
                         '空模板：只保留 8 张表的表头与 History 版本行。' newline ...
                         'Python 不可用时自动退化为 MATLAB 基本模板。'], outFile), ...
                        '导出 Excel 模板', {'含示例数据（推荐）', '空模板', '取消'}, 1, 3, 'question');
                    if isempty(choice) || strcmp(choice, '取消')
                        app.Log.info('已取消导出模板。');
                        return;
                    end
                    opts = struct('Empty', strcmp(choice, '空模板'), ...
                                  'Config', app.Settings.TemplateConfig, ...
                                  'Exe', app.Settings.PythonPath, 'Log', app.Log);
                    res = swb.TemplateExport.toWorkbook(outFile, opts);
                    if ~res.ok
                        app.Log.err('模板导出失败：%s', res.message);
                        app.setSummary(sprintf('模板导出失败: %s', res.message));
                        return;
                    end
                    if res.usedFallback
                        how = 'MATLAB 基本模板';
                    else
                        how = 'generate_template.py';
                    end
                    app.Log.info('Excel 模板已导出（%s）：%s', how, res.file);
                    app.updateStep(1, '完成', '模板已导出');
                    app.setSummary(sprintf('Excel 模板: %s\n生成方式: %s', res.file, how));
                    % 新模板就是当前字典工作簿：切过去并读入，省掉再点"浏览…"
                    app.DictWorkbookPath = res.file;
                    app.H.dictWorkbookEdit.Value = res.file;
                    if isfield(app.H, 'dictEdit') && isvalid(app.H.dictEdit)
                        app.H.dictEdit.Value = res.file;
                    end
                    app.Settings.LastDictWorkbook = res.file;
                    app.Settings.save();
                    app.onReadWorkbooks();
                otherwise
                    app.Log.warn('未知操作: %s', kind);
            end
        end

        function previewSheet(app, dictPath, sheetName)
            t = swb.Workbook.readSheetTable(dictPath, sheetName);
            maxRows = min(size(t.rows, 1), 100);
            data = cell(maxRows, numel(t.headers));
            for r = 1:maxRows
                for c = 1:numel(t.headers)
                    data{r, c} = swb.Workbook.cellText(t.rows{r, c});
                end
            end
            app.H.dictTable.ColumnName = t.headers;
            app.H.dictTable.Data = data;
            app.H.dictResultLabel.Text = sprintf('%s：%d 行（显示前 %d 行）', sheetName, size(t.rows, 1), maxRows);
            app.Log.info('预览 %s：%d 行', sheetName, size(t.rows, 1));
        end

        function showIssues(app, issues)
            data = cell(numel(issues), 5);
            for k = 1:numel(issues)
                it = issues(k);
                data(k, :) = {it.sheet, it.row, it.column, it.severity, it.message};
            end
            app.H.dictTable.ColumnName = {'工作表', '行', '列', '级别', '问题'};
            app.H.dictTable.Data = data;
            nErr = swb.Issue.count(issues, 'error');
            nWarn = swb.Issue.count(issues, 'warning');
            if isempty(issues)
                app.H.dictResultLabel.Text = '✓ 校验通过，未发现问题。';
                app.H.dictResultLabel.FontColor = [0.10, 0.50, 0.10];
                app.Log.info('校验通过（0 个问题）。');
            else
                app.H.dictResultLabel.Text = sprintf('发现 %d 个错误、%d 个警告。', nErr, nWarn);
                app.H.dictResultLabel.FontColor = [0.75, 0.10, 0.10];
                app.Log.warn('校验完成：%d 错误 / %d 警告。', nErr, nWarn);
            end
        end

        function w = statusWord(~, nIssue)
            if nIssue == 0
                w = '通过';
            else
                w = '有问题';
            end
        end

        %% ---------- 模型动作 ----------
        function onBrowseFolder(app)
            d = app.pickFolder(strtrim(app.H.modelFolderEdit.Value), '选择模型保存目录');
            if isequal(d, 0)
                return;
            end
            app.H.modelFolderEdit.Value = d;
            app.refreshModelCandidates();
        end

        function onBrowseTlc(app)
            [f, d] = app.pickOpenFile({'*.tlc', 'TLC 文件 (*.tlc)'; '*.*', '所有文件'}, '选择系统目标文件');
            if isequal(f, 0)
                return;
            end
            app.H.tlcEdit.Value = fullfile(d, f);
        end

        function onBrowseSldd(app)
            [f, d] = app.pickOpenFile({'*.sldd', '数据字典 (*.sldd)'}, '选择数据字典');
            if isequal(f, 0)
                return;
            end
            app.H.modelDictEdit.Value = fullfile(d, f);
        end

        function opts = modelOptsFromUI(app)
            opts = swb.Schema.modelConfigDefaults();
            opts.Name = strtrim(app.H.modelNameEdit.Value);
            opts.Folder = strtrim(app.H.modelFolderEdit.Value);
            if isempty(opts.Folder)
                opts.Folder = pwd;
            end
            if contains(app.H.solverDrop.Value, '离散')
                opts.SolverType = 'Discrete';
            else
                opts.SolverType = 'Continuous';
            end
            opts.SampleTime = strtrim(app.H.sampleTimeEdit.Value);
            opts.SystemTargetFile = strtrim(app.H.tlcEdit.Value);
            opts.GenCodeOnly = logical(app.H.genCodeChk.Value);
            opts.DictFile = strtrim(app.H.modelDictEdit.Value);
            opts.PortWorkbook = strtrim(app.H.modelPortEdit.Value);
            opts.ApplyCodeMapping = logical(app.H.codeMapChk.Value);
            opts.OpenAfterCreate = logical(app.H.openAfterChk.Value);
            switch app.H.conflictDrop.Value
                case '覆盖'
                    opts.ConflictPolicy = 'overwrite';
                case '加数字后缀'
                    opts.ConflictPolicy = 'suffix';
                case '取消'
                    opts.ConflictPolicy = 'cancel';
                otherwise
                    opts.ConflictPolicy = 'ask';
            end
            opts.AskFcn = @(msg, options, defaultIdx) app.confirmAndRaise(msg, '模型已存在', ...
                options, defaultIdx, numel(options), 'question');
            opts.Log = app.Log;
        end

        function onModelAction(app, kind)
            app.Log.section('模型 → %s', kind);
            switch kind
                case 'create'
                    if ~app.hasService('swb.ModelBuilder')
                        app.notReady('swb.ModelBuilder');
                        return;
                    end
                    opts = app.modelOptsFromUI();
                    if ~app.confirmModelOverwrite(opts)
                        app.Log.warn('用户取消创建模型。');
                        return;
                    end
                    result = swb.ModelBuilder.create(opts);
                    if result.ok && isfield(result, 'backupFile') && ~isempty(result.backupFile) && isfile(result.backupFile)
                        app.Log.info('原模型已备份: %s', result.backupFile);
                    end
                    if result.ok
                        app.H.modelStatusLabel.Text = sprintf('✓ %s（输入 %d / 输出 %d）', ...
                            result.modelName, result.inputCount, result.outputCount);
                        app.H.modelStatusLabel.FontColor = [0.10, 0.50, 0.10];
                        app.updateStep(5, '完成', result.modelName);
                    else
                        app.H.modelStatusLabel.Text = ['✗ ', result.errorText];
                        app.H.modelStatusLabel.FontColor = [0.75, 0.10, 0.10];
                        app.updateStep(5, '失败', result.errorText);
                    end
                case 'update'
                    if ~app.hasService('swb.PortSync')
                        app.notReady('swb.PortSync');
                        return;
                    end
                    [modelRef, modelPath] = app.modelRefFromUI();
                    if ~isfile(modelPath)
                        app.Log.warn('模型不存在: %s（请先创建模型）', modelPath);
                        app.H.modelStatusLabel.Text = '✗ 模型不存在，请先创建';
                        app.H.modelStatusLabel.FontColor = [0.75, 0.10, 0.10];
                        return;
                    end
                    portWb = strtrim(app.H.modelPortEdit.Value);
                    if isempty(portWb) || ~isfile(portWb)
                        app.Log.warn('未指定有效的端口工作簿，无法更新端口。');
                        app.H.modelStatusLabel.Text = '✗ 需要端口工作簿';
                        app.H.modelStatusLabel.FontColor = [0.75, 0.10, 0.10];
                        return;
                    end
                    [inP, outP] = swb.PortTable.read(portWb);
                    stats = swb.PortSync.apply(modelRef, inP, outP, ...
                        struct('Log', app.Log, 'SaveAfter', true));
                    if stats.ok
                        app.Log.info('端口同步：+%d -%d ~%d =%d', ...
                            stats.added, stats.removed, stats.updated, stats.unchanged);
                        if app.H.codeMapChk.Value && app.hasService('swb.CodeMapping')
                            cm = swb.CodeMapping.apply(modelRef, inP, outP, struct('Log', app.Log));
                            app.Log.info('Code Mapping：输入 %d / 输出 %d 已应用。', ...
                                cm.appliedInput, cm.appliedOutput);
                        end
                        app.H.modelStatusLabel.Text = sprintf('✓ 端口已同步（+%d -%d ~%d）', ...
                            stats.added, stats.removed, stats.updated);
                        app.H.modelStatusLabel.FontColor = [0.10, 0.50, 0.10];
                        app.updateStep(5, '完成', sprintf('端口 +%d -%d ~%d', ...
                            stats.added, stats.removed, stats.updated));
                    else
                        app.Log.err('端口同步失败：%s', stats.errorText);
                        app.H.modelStatusLabel.Text = ['✗ ', stats.errorText];
                        app.H.modelStatusLabel.FontColor = [0.75, 0.10, 0.10];
                    end
                case 'export'
                    if ~app.hasService('swb.PortExport')
                        app.notReady('swb.PortExport');
                        return;
                    end
                    [modelRef, modelPath] = app.modelRefFromUI();
                    if ~isfile(modelPath)
                        app.Log.warn('模型不存在，无法导出: %s', modelPath);
                        return;
                    end
                    % 默认文件名固定为「模型名称_ports」，起始目录就是模型所在目录。
                    folder = strtrim(app.H.modelFolderEdit.Value);
                    if isempty(folder)
                        folder = pwd;
                    end
                    defName = fullfile(folder, swb.PortExport.defaultFileName( ...
                        strtrim(app.H.modelNameEdit.Value)));
                    [f, d] = app.pickSaveFile({'*.xlsx', 'Excel 文件 (*.xlsx)'}, '导出端口到 Excel', defName);
                    if isequal(f, 0)
                        return;
                    end
                    outFile = fullfile(d, f);
                    result = swb.PortExport.write(modelRef, outFile, struct('Log', app.Log));
                    if result.ok
                        app.Log.info('已导出端口 %d 输入 / %d 输出 → %s', ...
                            result.inputCount, result.outputCount, result.file);
                        app.H.modelStatusLabel.Text = sprintf('✓ 端口已导出（%d 输入 / %d 输出）', ...
                            result.inputCount, result.outputCount);
                        app.H.modelStatusLabel.FontColor = [0.10, 0.50, 0.10];
                        % 导出的文件就是当前的端口工作簿：接着点「更新端口」即可把改动写回模型。
                        if isfile(result.file) && isfield(app.H, 'modelPortEdit') ...
                                && isvalid(app.H.modelPortEdit)
                            app.H.modelPortEdit.Value = result.file;
                            app.Log.info('端口工作簿已切换到: %s', result.file);
                        end
                    else
                        app.Log.err('导出失败：%s', result.errorText);
                        app.H.modelStatusLabel.Text = ['✗ ', result.errorText];
                        app.H.modelStatusLabel.FontColor = [0.75, 0.10, 0.10];
                    end
                otherwise
                    app.Log.warn('未知模型操作: %s', kind);
            end
        end

        %% ---------- 一键流水线 ----------
        function onRunPipeline(app)
            app.Log.section('一键流水线');
            if ~app.hasService('swb.Pipeline')
                app.notReady('swb.Pipeline');
                app.setStatus('流水线服务尚未接入。', 'warn');
                return;
            end
            cfg = struct();
            cfg.DictWorkbook = app.DictWorkbookPath;
            cfg.PortWorkbook = app.PortWorkbookPath;
            cfg.Sheets = app.selectedDictSheets();
            cfg.ScriptFile = strtrim(app.H.scriptEdit.Value);
            cfg.SlddFile = strtrim(app.H.slddEdit.Value);
            cfg.Model = app.modelOptsFromUI();
            cfg.ValidateFirst = logical(app.H.validateChk.Value);
            cfg.ConfirmWrite = logical(app.H.confirmChk.Value);
            cfg.CleanExtra = logical(app.H.cleanDictChk.Value);
            cfg.Log = app.Log;
            cfg.ConfirmFcn = @(msg) app.confirmAndRaise(char(msg), '确认写入数据字典', ...
                {'写入', '取消'}, 1, 2, 'question');
            cfg.AskFcn = @(msg, options, defaultIdx) app.confirmAndRaise(char(msg), '模型已存在', ...
                options, defaultIdx, numel(options), 'question');
            result = swb.Pipeline.run(cfg);
            app.setSummary(result.summary);
            for k = 1:numel(result.steps)
                st = result.steps(k);
                idx = app.stepIndexOf(st.name);
                if idx > 0
                    app.updateStep(idx, app.stepWord(st.status), st.detail);
                end
            end
            if ~isempty(result.artifacts.modelFile) && isfile(result.artifacts.modelFile)
                app.updateStep(6, '完成', result.artifacts.modelFile);
                app.H.modelStatusLabel.Text = sprintf('✓ 流水线已创建模型: %s', result.artifacts.modelFile);
                app.H.modelStatusLabel.FontColor = [0.10, 0.50, 0.10];
            elseif ~isempty(result.artifacts.slddFile) && isfile(result.artifacts.slddFile)
                app.updateStep(6, '完成', result.artifacts.slddFile);
            end
            if result.ok
                app.setStatus('✓ 流水线完成', 'ok');
            else
                app.setStatus(['✗ 流水线中断: ', char(result.errorText)], 'error');
            end
        end

        %% ---------- 设置 ----------
        function applySettingsToUI(app)
            if isfield(app.H, 'pythonEdit') && isvalid(app.H.pythonEdit)
                app.H.pythonEdit.Value = app.Settings.PythonPath;
                app.H.defaultTlcEdit.Value = app.Settings.DefaultTlc;
                switch app.Settings.ConflictPolicy
                    case 'overwrite'
                        app.H.defaultConflictDrop.Value = '覆盖';
                    case 'suffix'
                        app.H.defaultConflictDrop.Value = '加数字后缀';
                    case 'cancel'
                        app.H.defaultConflictDrop.Value = '取消';
                    otherwise
                        app.H.defaultConflictDrop.Value = '询问';
                end
                % 用默认冲突策略初始化模型页下拉框（模型页仍可临时改，执行时以模型页为准）。
                if isfield(app.H, 'conflictDrop') && ~isempty(app.H.conflictDrop) && isvalid(app.H.conflictDrop)
                    switch app.Settings.ConflictPolicy
                        case 'overwrite'
                            app.H.conflictDrop.Value = '覆盖';
                        case 'suffix'
                            app.H.conflictDrop.Value = '加数字后缀';
                        case 'cancel'
                            app.H.conflictDrop.Value = '取消';
                        otherwise
                            app.H.conflictDrop.Value = '询问';
                    end
                end
            end
            if isfield(app.H, 'templateCfgInfo') && isvalid(app.H.templateCfgInfo)
                app.H.templateCfgInfo.Text = app.templateConfigSummary();
            end
        end

        function txt = templateConfigSummary(app)
            try
                txt = swb.TemplateConfig.summary(app.Settings.TemplateConfig);
            catch
                txt = 'Config 表候选值（8 列）';
            end
        end

        function onBrowsePython(app)
            [f, d] = app.pickOpenFile({'*.exe', '可执行文件 (*.exe)'}, '选择 python.exe');
            if isequal(f, 0)
                return;
            end
            app.H.pythonEdit.Value = fullfile(d, f);
        end

        function onTestPython(app)
            exe = strtrim(app.H.pythonEdit.Value);
            if app.hasService('swb.PythonService')
                ok = swb.PythonService.validate(exe);
            else
                ok = isfile(exe);
            end
            if ok
                app.Log.info('Python 可用: %s', exe);
                app.H.settingsStatus.Text = '✓ Python 可用';
            else
                app.Log.warn('Python 不可用: %s', exe);
                app.H.settingsStatus.Text = '✗ Python 不可用（可留空，仅影响模板生成/反向同步）';
            end
        end

        function onSaveSettings(app)
            app.Settings.PythonPath = strtrim(app.H.pythonEdit.Value);
            app.Settings.DefaultTlc = strtrim(app.H.defaultTlcEdit.Value);
            switch app.H.defaultConflictDrop.Value
                case '覆盖'
                    app.Settings.ConflictPolicy = 'overwrite';
                case '加数字后缀'
                    app.Settings.ConflictPolicy = 'suffix';
                case '取消'
                    app.Settings.ConflictPolicy = 'cancel';
                otherwise
                    app.Settings.ConflictPolicy = 'ask';
            end
            app.Settings.save();
            app.H.settingsStatus.Text = '✓ 设置已保存';
            app.Log.info('设置已保存: %s', app.Settings.File);
        end

        function onEditTemplateConfig(app)
            try
                dlg = swb.ui.TemplateConfigDialog(app.UIFigure, app.Settings.TemplateConfig);
            catch ME
                app.Log.err('无法打开模板 Config 编辑器: %s', ME.message);
                app.H.settingsStatus.Text = '✗ 无法打开模板 Config 编辑器';
                app.raiseApp();
                return;
            end
            dlg.show();
            if isempty(dlg.Result)
                app.Log.info('模板 Config 编辑已取消（未修改）。');
                app.H.settingsStatus.Text = '模板 Config 未修改。';
            else
                app.Settings.TemplateConfig = dlg.Result;
                app.Settings.save();
                warns = dlg.Warnings;
                for k = 1:numel(warns)
                    app.Log.warn('%s', warns{k});
                end
                app.Log.info('模板 Config 已保存（%s）。', ...
                    swb.TemplateConfig.summary(app.Settings.TemplateConfig));
                app.H.settingsStatus.Text = '✓ 模板 Config 已保存';
                app.applySettingsToUI();
            end
            app.raiseApp();
        end

        %% ---------- 日志 ----------
        function onClearLog(app)
            app.Log.clear();
            if isfield(app.H, 'logArea') && isvalid(app.H.logArea)
                app.H.logArea.Value = '';
            end
            app.H.countLabel.Text = '';
        end

        function onCopyLog(app)
            try
                clipboard('copy', app.Log.text());
                app.Log.info('日志已复制到剪贴板。');
            catch ME
                app.Log.warn('复制失败: %s', ME.message);
            end
        end

        function onExportLog(app)
            [f, d] = app.pickSaveFile({'*.log;*.txt', '日志文件'}, '导出日志', 'simworkbench.log');
            if isequal(f, 0)
                return;
            end
            fid = fopen(fullfile(d, f), 'w', 'n', 'UTF-8');
            if fid < 0
                app.Log.err('无法写入日志文件: %s', fullfile(d, f));
                return;
            end
            c = onCleanup(@() fclose(fid));
            fprintf(fid, '%s\n', app.Log.text());
            app.Log.info('日志已导出: %s', fullfile(d, f));
        end

        %% ---------- 模型/流水线辅助 ----------
        function refreshModelCandidates(app)
            %REFRESHMODELCANDIDATES 刷新「模型名称」下拉：已打开模型 + 保存目录里的 .slx。
            %  下拉框是可编辑的（Editable='on'），刷新不会丢掉用户手写的名称。
            if ~isfield(app.H, 'modelNameEdit') || ~isvalid(app.H.modelNameEdit)
                return;
            end
            folder = '';
            if isfield(app.H, 'modelFolderEdit') && isvalid(app.H.modelFolderEdit)
                folder = strtrim(app.H.modelFolderEdit.Value);
            end
            names = {};
            try
                names = swb.ModelCatalog.names(folder);
            catch ME
                app.Log.debug('扫描现有模型失败: %s', ME.message);
            end
            cur = strtrim(app.H.modelNameEdit.Value);
            if ~isempty(cur) && ~any(strcmp(names, cur))
                names = [{cur}, names];
            end
            if isempty(names)
                names = {'myModel'};
            end
            app.H.modelNameEdit.Items = names;
        end

        function onModelNameChanged(app)
            %ONMODELNAMECHANGED 从下拉里选了现有模型时，把保存目录切到该模型所在目录。
            %   手写名称不受影响：只有当保存目录下没有同名模型时才跟随文件位置。
            name = strtrim(app.H.modelNameEdit.Value);
            if isempty(name) || ~isfield(app.H, 'modelFolderEdit') || ~isvalid(app.H.modelFolderEdit)
                return;
            end
            folder = strtrim(app.H.modelFolderEdit.Value);
            if isempty(folder)
                folder = pwd;
            end
            if isfile(fullfile(folder, [name '.slx'])) || isfile(fullfile(folder, [name '.mdl']))
                return;   % 保存目录里已有这个模型：保持用户选定的目录
            end
            info = [];
            try
                info = swb.ModelCatalog.findByName(name);
            catch ME
                app.Log.debug('解析模型位置失败: %s', ME.message);
                return;
            end
            if isempty(info) || isempty(info.folder) || strcmp(info.folder, folder)
                return;
            end
            app.H.modelFolderEdit.Value = info.folder;
            app.Log.info('模型 "%s" 位于 %s，保存目录已切换。', name, info.folder);
            app.refreshModelCandidates();
        end

        function [modelRef, modelPath] = modelRefFromUI(app)
            name = strtrim(app.H.modelNameEdit.Value);
            folder = strtrim(app.H.modelFolderEdit.Value);
            if isempty(folder)
                folder = pwd;
            end
            modelPath = fullfile(folder, [name '.slx']);
            modelRef = modelPath;
        end

        function tf = confirmModelOverwrite(app, opts)
            tf = true;
            folder = char(opts.Folder);
            if isempty(folder)
                folder = pwd;
            end
            modelPath = fullfile(folder, [char(opts.Name) '.slx']);
            if ~isfile(modelPath) || ~strcmp(char(opts.ConflictPolicy), 'overwrite')
                return;
            end
            answer = app.confirmAndRaise( ...
                sprintf('模型已存在：%s\n\n覆盖前会备份为 %s.bak。', modelPath, modelPath), ...
                '确认覆盖模型', {'覆盖', '取消'}, 2, 2, 'warning');
            tf = strcmp(answer, '覆盖');
            if tf
                app.Log.warn('将覆盖已有模型（保留备份）: %s', modelPath);
            end
        end

        function word = stepWord(~, status)
            switch char(status)
                case 'ok'
                    word = '完成';
                case 'failed'
                    word = '失败';
                case 'skipped'
                    word = '跳过';
                case 'warn'
                    word = '警告';
                otherwise
                    word = char(status);
            end
        end

        function idx = stepIndexOf(~, name)
            switch char(name)
                case '字典工作簿'
                    idx = 1;
                case '校验数据字典'
                    idx = 2;
                case '生成对象脚本'
                    idx = 3;
                case '写入数据字典'
                    idx = 4;
                case '创建模型'
                    idx = 5;
                otherwise
                    idx = 0;
            end
        end

        %% ---------- 状态辅助 ----------
        function updateStep(app, idx, status, detail)
            if ~isfield(app.H, 'stepTable') || isempty(app.H.stepTable) || ~isvalid(app.H.stepTable)
                return;
            end
            data = app.H.stepTable.Data;
            if idx < 1 || idx > size(data, 1)
                return;
            end
            data{idx, 2} = status;
            if nargin >= 4
                data{idx, 3} = detail;
            end
            app.H.stepTable.Data = data;
        end

        function setSummary(app, txt)
            if isfield(app.H, 'summaryArea') && isvalid(app.H.summaryArea)
                if ischar(txt)
                    txt = splitlines(txt);
                end
                app.H.summaryArea.Value = txt;
            end
        end

        function clearSummary(app)
            if isfield(app.H, 'summaryArea') && isvalid(app.H.summaryArea)
                app.H.summaryArea.Value = {'尚未运行。'};
            end
        end

        function refreshSummary(app)
            lines = {};
            if ~isempty(app.DictWorkbookPath) && isfile(app.DictWorkbookPath)
                info = swb.Workbook.detect(app.DictWorkbookPath);
                lines{end+1} = sprintf('字典工作簿: %s', app.DictWorkbookPath);
                lines{end+1} = sprintf('  可导入表: %s', strjoin(info.dictSheets, ', '));
            else
                lines{end+1} = '字典工作簿: 未选择';
            end
            if ~isempty(app.PortWorkbookPath) && isfile(app.PortWorkbookPath)
                lines{end+1} = sprintf('端口工作簿: %s', app.PortWorkbookPath);
            else
                lines{end+1} = '端口工作簿: 未选择';
            end
            if isfield(app.H, 'inputSummary') && isvalid(app.H.inputSummary)
                app.H.inputSummary.Text = strjoin(lines, '    ');
            end
        end

        %% ---------- 文件对话框与窗口焦点 ----------
        %  MATLAB 的文件选择对话框（uigetfile/uiputfile/uigetdir）没有父窗口参数
        %  （R2024b 下把 uifigure 当第一个参数传会被当成 filter 报错），对话框关闭后
        %  Windows 把焦点还给 MATLAB 桌面，uifigure 就退到后台——表现为"选完 Excel
        %  后 App 不再置顶"。focusGuard 用"焦点占位图窗"绕开这个长期 bug：对话框
        %  关闭时焦点先回到占位图窗，再删掉它，DeleteFcn 里把主窗口提回最前。
        function raiseApp(app)
            %RAISEAPP 把主窗口重新提到最前（uifigure 也支持 figure()）。
            try
                fig = app.UIFigure;
                if isempty(fig) || ~isvalid(fig)
                    return;
                end
                figure(fig);
                drawnow;
            catch
                % 无图形环境或窗口已关闭：不能因为置顶失败影响主流程
            end
        end

        function guard = focusGuard(app)
            %FOCUSGUARD 在文件对话框打开前占住焦点，关闭后把主窗口拉回最前。
            %   用法：先调用本方法，再弹出文件对话框，最后 delete(guard)。
            %   无桌面环境、窗口不可见或创建失败时返回 []，调用方 delete([]) 是空操作。
            guard = [];
            try
                fig = app.UIFigure;
                if ~usejava('desktop') || isempty(fig) || ~isvalid(fig) ...
                        || ~strcmp(fig.Visible, 'on')
                    return;
                end
                menuHeight = 0;
                kids = get(fig, 'Children');
                if ~isempty(kids)
                    kinds = get(kids, 'Type');
                    if ischar(kinds)
                        kinds = {kinds};
                    end
                    if any(strcmp(kinds, 'uimenu'))
                        menuHeight = 22;
                    end
                end
                pos = fig.Position;
                guard = figure('Position', pos, 'MenuBar', 'none', 'Resize', 'off', ...
                    'NumberTitle', 'off', 'Visible', 'off', 'HandleVisibility', 'callback', ...
                    'Name', fig.Name, 'DeleteFcn', @(~, ~) app.raiseApp());
                % 占位图窗做成贴在标题栏上方、高度 0 的细条，几乎看不见
                guard.Position(2) = guard.Position(2) + guard.Position(4) + menuHeight;
                guard.Position(4) = 0;
                guard.Visible = 'on';
                drawnow;
                guard.Visible = 'off';
            catch
                guard = [];
            end
        end

        function [f, d] = pickOpenFile(app, filters, title, defname)
            %PICKOPENFILE 打开文件对话框，关闭后把主窗口提回最前。
            guard = app.focusGuard();
            try
                if nargin < 4
                    [f, d] = uigetfile(filters, title);
                else
                    [f, d] = uigetfile(filters, title, defname);
                end
            catch ME
                delete(guard);
                rethrow(ME);
            end
            delete(guard);
            app.raiseApp();
        end

        function [f, d] = pickSaveFile(app, filters, title, defname)
            %PICKSAVEFILE 打开保存对话框，关闭后把主窗口提回最前。
            guard = app.focusGuard();
            try
                if nargin < 4
                    [f, d] = uiputfile(filters, title);
                else
                    [f, d] = uiputfile(filters, title, defname);
                end
            catch ME
                delete(guard);
                rethrow(ME);
            end
            delete(guard);
            app.raiseApp();
        end

        function d = pickFolder(app, startPath, title)
            %PICKFOLDER 打开目录选择对话框，关闭后把主窗口提回最前。
            guard = app.focusGuard();
            try
                d = uigetdir(char(startPath), title);
            catch ME
                delete(guard);
                rethrow(ME);
            end
            delete(guard);
            app.raiseApp();
        end

        function choice = confirmAndRaise(app, msg, title, options, defaultIdx, cancelIdx, icon)
            %CONFIRMANDBRAISE 弹出确认对话框，关闭后把主窗口提回最前。
            guard = app.focusGuard();
            try
                choice = uiconfirm(app.UIFigure, msg, title, 'Options', options, ...
                    'DefaultOption', defaultIdx, 'CancelOption', cancelIdx, 'Icon', icon);
            catch ME
                delete(guard);
                rethrow(ME);
            end
            delete(guard);
            app.raiseApp();
        end
    end
end