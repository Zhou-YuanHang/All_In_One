classdef NewModelApp < handle
    % NewModelApp - 一键新建 Simulink 模型工具
    %   GUI 界面支持：
    %   - 输入模型名称
    %   - 勾选离散模型，设置时间步长
    %   - 选择 TLC 文件（默认 ert.tlc）
    %   - 勾选仅生成代码
    %   - 关联数据字典（勾选后选择 .sldd 文件）
    %   - 从 Excel 导入端口（勾选后选择 Excel 文件）
    %   - 不勾选导入端口时创建空模型

    properties (Access = public)
        % 主窗口
        UIFigure           matlab.ui.Figure

        % 模式选择
        ModeLabel          matlab.ui.control.Label
        ModeDropDown       matlab.ui.control.DropDown

        % 模型名称
        NameLabel          matlab.ui.control.Label
        NameEditField      matlab.ui.control.EditField
        ModelBrowseButton  matlab.ui.control.Button

        % 离散模型
        DiscreteCheckBox   matlab.ui.control.CheckBox
        SampleTimeLabel    matlab.ui.control.Label
        SampleTimeEditField matlab.ui.control.EditField

        % TLC 文件
        TLCLabel           matlab.ui.control.Label
        TLCEditField       matlab.ui.control.EditField
        TLCBrowseButton    matlab.ui.control.Button

        % 仅生成代码
        GenCodeOnlyCheckBox matlab.ui.control.CheckBox

        % 数据字典
        DictCheckBox       matlab.ui.control.CheckBox
        DictPathLabel      matlab.ui.control.Label
        DictEditField      matlab.ui.control.EditField
        DictBrowseButton   matlab.ui.control.Button

        % Excel 导入
        ExcelCheckBox      matlab.ui.control.CheckBox
        ExcelPathLabel     matlab.ui.control.Label
        ExcelEditField     matlab.ui.control.EditField
        ExcelBrowseButton  matlab.ui.control.Button
        ExcelCodeMapCheckBox matlab.ui.control.CheckBox
        OpenModelCheckBox  matlab.ui.control.CheckBox

        % 按钮
        CreateButton       matlab.ui.control.Button
        ExportPortsButton   matlab.ui.control.Button

        % 状态栏
        StatusLabel        matlab.ui.control.Label
    end

    properties (Access = private)
        % 新建模式专用的控件列表（修改端口模式下隐藏）
        CreationControls   cell
    end

    % =====================================================================
    % 构造 / 析构
    % =====================================================================
    methods
        function app = NewModelApp()
            % 构造 app，创建 UI 组件
            app.createComponents();
        end

        function delete(app)
            % 析构时关闭窗口
            if isvalid(app.UIFigure)
                delete(app.UIFigure);
            end
        end
    end

    % =====================================================================
    % 界面创建
    % =====================================================================
    methods (Access = private)
        function createComponents(app)
            % 创建主窗口
            app.UIFigure = uifigure('Visible', 'off');
            app.UIFigure.Position = [100, 130, 540, 560];
            app.UIFigure.Name = '新建 Simulink 模型';
            app.UIFigure.Resize = 'off';
            app.UIFigure.Scrollable = 'off';

            % ---- 标题 ----
            titleLabel = uilabel(app.UIFigure);
            titleLabel.Position = [10, 525, 520, 30];
            titleLabel.Text = '新建 Simulink 模型';
            titleLabel.FontSize = 20;
            titleLabel.FontWeight = 'bold';
            titleLabel.HorizontalAlignment = 'center';

            % ---- 分隔线 ----
            sep = uilabel(app.UIFigure);
            sep.Position = [10, 508, 520, 2];
            sep.BackgroundColor = [0.7 0.7 0.7];
            sep.Text = '';

            % ---- 模式选择 ----
            app.ModeLabel = uilabel(app.UIFigure);
            app.ModeLabel.Position = [20, 480, 70, 22];
            app.ModeLabel.Text = '工作模式:';
            app.ModeLabel.FontSize = 12;

            app.ModeDropDown = uidropdown(app.UIFigure);
            app.ModeDropDown.Position = [100, 477, 160, 25];
            app.ModeDropDown.Items = {'新建模型', '修改端口'};
            app.ModeDropDown.Value = '新建模型';
            app.ModeDropDown.ValueChangedFcn = @(~, ~) app.onModeChanged();

            % ---- 模型名称 ----
            app.NameLabel = uilabel(app.UIFigure);
            app.NameLabel.Position = [20, 448, 80, 22];
            app.NameLabel.Text = '模型名称:';
            app.NameLabel.FontSize = 12;

            app.NameEditField = uieditfield(app.UIFigure, 'text');
            app.NameEditField.Position = [110, 448, 310, 24];
            app.NameEditField.Value = 'myModel';
            app.NameEditField.Tooltip = '输入有效的 MATLAB 标识符（字母开头，无空格）';

            % ---- 模型文件浏览按钮（修改端口模式专用） ----
            app.ModelBrowseButton = uibutton(app.UIFigure, 'push');
            app.ModelBrowseButton.Position = [430, 444, 90, 24];
            app.ModelBrowseButton.Text = '浏览...';
            app.ModelBrowseButton.FontSize = 11;
            app.ModelBrowseButton.Visible = 'off';
            app.ModelBrowseButton.ButtonPushedFcn = @(~, ~) app.onBrowseModel();

            % ---- 离散模型 ----
            app.DiscreteCheckBox = uicheckbox(app.UIFigure);
            app.DiscreteCheckBox.Position = [20, 413, 200, 22];
            app.DiscreteCheckBox.Text = '离散模型';
            app.DiscreteCheckBox.FontSize = 12;
            app.DiscreteCheckBox.ValueChangedFcn = @(s, ~) app.onDiscreteToggled(s.Value);

            % ---- 时间步长 ----
            app.SampleTimeLabel = uilabel(app.UIFigure);
            app.SampleTimeLabel.Position = [40, 385, 80, 22];
            app.SampleTimeLabel.Text = '时间步长:';
            app.SampleTimeLabel.Enable = 'off';

            app.SampleTimeEditField = uieditfield(app.UIFigure, 'text');
            app.SampleTimeEditField.Position = [130, 385, 100, 22];
            app.SampleTimeEditField.Value = '0.01';
            app.SampleTimeEditField.Enable = 'off';
            app.SampleTimeEditField.Tooltip = '固定步长大小（秒）';

            % ---- TLC 文件 ----
            app.TLCLabel = uilabel(app.UIFigure);
            app.TLCLabel.Position = [20, 353, 80, 22];
            app.TLCLabel.Text = 'TLC 文件:';
            app.TLCLabel.FontSize = 12;

            app.TLCEditField = uieditfield(app.UIFigure, 'text');
            app.TLCEditField.Position = [110, 353, 330, 22];
            app.TLCEditField.Value = 'ert.tlc';
            app.TLCEditField.Tooltip = '代码生成系统目标文件';

            app.TLCBrowseButton = uibutton(app.UIFigure, 'push');
            app.TLCBrowseButton.Position = [450, 353, 70, 22];
            app.TLCBrowseButton.Text = '浏览...';
            app.TLCBrowseButton.ButtonPushedFcn = @(~, ~) app.browseTLC();

            % ---- 仅生成代码 ----
            app.GenCodeOnlyCheckBox = uicheckbox(app.UIFigure);
            app.GenCodeOnlyCheckBox.Position = [20, 320, 200, 22];
            app.GenCodeOnlyCheckBox.Text = '仅生成代码';
            app.GenCodeOnlyCheckBox.FontSize = 12;
            app.GenCodeOnlyCheckBox.Tooltip = '仅生成代码，不编译';

            % ---- 数据字典 ----
            app.DictCheckBox = uicheckbox(app.UIFigure);
            app.DictCheckBox.Position = [20, 287, 250, 22];
            app.DictCheckBox.Text = '关联数据字典';
            app.DictCheckBox.FontSize = 12;
            app.DictCheckBox.ValueChangedFcn = @(s, ~) app.onDictToggled(s.Value);

            app.DictPathLabel = uilabel(app.UIFigure);
            app.DictPathLabel.Position = [40, 259, 80, 22];
            app.DictPathLabel.Text = '字典路径:';
            app.DictPathLabel.Enable = 'off';

            app.DictEditField = uieditfield(app.UIFigure, 'text');
            app.DictEditField.Position = [130, 259, 310, 22];
            app.DictEditField.Enable = 'off';
            app.DictEditField.Tooltip = '选择 .sldd 数据字典文件';

            app.DictBrowseButton = uibutton(app.UIFigure, 'push');
            app.DictBrowseButton.Position = [450, 259, 70, 22];
            app.DictBrowseButton.Text = '浏览...';
            app.DictBrowseButton.Enable = 'off';
            app.DictBrowseButton.ButtonPushedFcn = @(~, ~) app.browseDict();

            % ---- Excel 导入 ----
            app.ExcelCheckBox = uicheckbox(app.UIFigure);
            app.ExcelCheckBox.Position = [20, 227, 250, 22];
            app.ExcelCheckBox.Text = '从 Excel 导入端口';
            app.ExcelCheckBox.FontSize = 12;
            app.ExcelCheckBox.ValueChangedFcn = @(s, ~) app.onExcelToggled(s.Value);

            app.ExcelPathLabel = uilabel(app.UIFigure);
            app.ExcelPathLabel.Position = [40, 199, 80, 22];
            app.ExcelPathLabel.Text = 'Excel 路径:';
            app.ExcelPathLabel.Enable = 'off';

            app.ExcelEditField = uieditfield(app.UIFigure, 'text');
            app.ExcelEditField.Position = [130, 199, 310, 22];
            app.ExcelEditField.Enable = 'off';
            app.ExcelEditField.Tooltip = 'Excel 文件，需包含 Input/Output 工作表或节标题';

            app.ExcelBrowseButton = uibutton(app.UIFigure, 'push');
            app.ExcelBrowseButton.Position = [450, 199, 70, 22];
            app.ExcelBrowseButton.Text = '浏览...';
            app.ExcelBrowseButton.Enable = 'off';
            app.ExcelBrowseButton.ButtonPushedFcn = @(~, ~) app.browseExcel();

            % ---- Code Mapping ----
            app.ExcelCodeMapCheckBox = uicheckbox(app.UIFigure);
            app.ExcelCodeMapCheckBox.Position = [40, 173, 350, 22];
            app.ExcelCodeMapCheckBox.Text = '使用 Code Mapping（设置 StorageClass / Identifier）';
            app.ExcelCodeMapCheckBox.FontSize = 12;
            app.ExcelCodeMapCheckBox.Enable = 'off';
            app.ExcelCodeMapCheckBox.Tooltip = '勾选后，用 Excel 中的 StorageClass 和 Identifier 列通过 Simulink.CodeMapping API 配置端口';

            % ---- 导出端口到 Excel（修改端口模式专用） ----
            app.ExportPortsButton = uibutton(app.UIFigure, 'push');
            app.ExportPortsButton.Position = [280, 148, 140, 22];
            app.ExportPortsButton.Text = '先导出当前端口';
            app.ExportPortsButton.FontSize = 11;
            app.ExportPortsButton.BackgroundColor = [0.9, 0.9, 0.9];
            app.ExportPortsButton.Visible = 'off';
            app.ExportPortsButton.ButtonPushedFcn = @(~, ~) app.onExportPorts();

            % ---- 打开模型 ----
            app.OpenModelCheckBox = uicheckbox(app.UIFigure);
            app.OpenModelCheckBox.Position = [20, 78, 250, 22];
            app.OpenModelCheckBox.Text = '创建后打开模型';
            app.OpenModelCheckBox.FontSize = 12;
            app.OpenModelCheckBox.Value = true;
            app.OpenModelCheckBox.Tooltip = '勾选后创建完模型保持打开状态；不勾选则保存后关闭';

            % ---- 创建 / 更新按钮 ----
            app.CreateButton = uibutton(app.UIFigure, 'push');
            app.CreateButton.Position = [190, 110, 160, 36];
            app.CreateButton.Text = '创建模型';
            app.CreateButton.FontSize = 14;
            app.CreateButton.FontWeight = 'bold';
            app.CreateButton.BackgroundColor = [0.15, 0.55, 0.15];
            app.CreateButton.FontColor = [1, 1, 1];
            app.CreateButton.ButtonPushedFcn = @(~, ~) app.onCreateOrUpdate();

            % ---- 收集新建模式专用控件（修改端口时隐藏） ----
            app.CreationControls = { ...
                app.DiscreteCheckBox, app.SampleTimeLabel, app.SampleTimeEditField, ...
                app.TLCLabel, app.TLCEditField, app.TLCBrowseButton, ...
                app.GenCodeOnlyCheckBox, ...
                app.DictCheckBox, app.DictPathLabel, app.DictEditField, app.DictBrowseButton, ...
                app.OpenModelCheckBox };

            % ---- 状态栏 ----
            app.StatusLabel = uilabel(app.UIFigure);
            app.StatusLabel.Position = [20, 20, 500, 50];
            app.StatusLabel.Text = '就绪';
            app.StatusLabel.HorizontalAlignment = 'center';
            app.StatusLabel.FontColor = [0.4, 0.4, 0.4];
            app.StatusLabel.FontSize = 12;
            app.StatusLabel.WordWrap = 'on';

            % ---- 显示窗口 ----
            movegui(app.UIFigure, 'center');
            app.UIFigure.Visible = 'on';
        end
    end

    % =====================================================================
    % 界面交互回调
    % =====================================================================
    methods (Access = private)
        function onDiscreteToggled(app, isChecked)
            % 离散模型勾选切换
            if isChecked
                app.SampleTimeLabel.Enable = 'on';
                app.SampleTimeEditField.Enable = 'on';
            else
                app.SampleTimeLabel.Enable = 'off';
                app.SampleTimeEditField.Enable = 'off';
            end
        end

        function onDictToggled(app, isChecked)
            % 数据字典勾选切换
            if isChecked
                app.DictPathLabel.Enable = 'on';
                app.DictEditField.Enable = 'on';
                app.DictBrowseButton.Enable = 'on';
            else
                app.DictPathLabel.Enable = 'off';
                app.DictEditField.Enable = 'off';
                app.DictBrowseButton.Enable = 'off';
            end
        end

        function onExcelToggled(app, isChecked)
            % Excel 导入勾选切换
            if isChecked
                app.ExcelPathLabel.Enable = 'on';
                app.ExcelEditField.Enable = 'on';
                app.ExcelBrowseButton.Enable = 'on';
                app.ExcelCodeMapCheckBox.Enable = 'on';
            else
                app.ExcelPathLabel.Enable = 'off';
                app.ExcelEditField.Enable = 'off';
                app.ExcelBrowseButton.Enable = 'off';
                app.ExcelCodeMapCheckBox.Enable = 'off';
            end
        end

        % =============================================================
        % 模式切换 & 调度
        % =============================================================
        function onModeChanged(app)
            % 工作模式切换：新建模型 ↔ 修改端口
            isCreate = strcmp(app.ModeDropDown.Value, '新建模型');

            % 切换按钮外观
            if isCreate
                app.CreateButton.Text = '创建模型';
                app.CreateButton.BackgroundColor = [0.15, 0.55, 0.15];
            else
                app.CreateButton.Text = '更新端口';
                app.CreateButton.BackgroundColor = [0.8, 0.4, 0.1];
            end

            % 显示/隐藏新建模式专用控件
            for i = 1:length(app.CreationControls)
                ctrl = app.CreationControls{i};
                if isvalid(ctrl)
                    if isCreate
                        ctrl.Visible = 'on';
                    else
                        ctrl.Visible = 'off';
                    end
                end
            end

            % 导出端口按钮（仅在修改端口模式显示）
            if isvalid(app.ExportPortsButton)
                if isCreate
                    app.ExportPortsButton.Visible = 'off';
                else
                    app.ExportPortsButton.Visible = 'on';
                end
            end

            % 模型浏览按钮（仅在修改端口模式显示）
            if isvalid(app.ModelBrowseButton)
                if isCreate
                    app.ModelBrowseButton.Visible = 'off';
                else
                    app.ModelBrowseButton.Visible = 'on';
                end
            end

            % 切换时重置状态
            app.StatusLabel.FontColor = [0.4, 0.4, 0.4];
            app.StatusLabel.Text = sprintf('当前模式: %s', app.ModeDropDown.Value);
        end

        function onCreateOrUpdate(app)
            % 根据当前模式调度
            if strcmp(app.ModeDropDown.Value, '新建模型')
                app.createModel();
            else
                app.updatePorts();
            end
        end

        function onBrowseModel(app)
            % 弹出文件选择窗口，选择 .slx 模型文件
            [file, path] = uigetfile({'*.slx', 'Simulink 模型 (*.slx)'; ...
                                       '*.mdl', 'Simulink 模型 (*.mdl)'}, ...
                                       '选择模型文件');
            figure(app.UIFigure);  % 把窗口拉回最前
            if isequal(file, 0)
                return;  % 用户取消
            end

            [~, name, ~] = fileparts(file);
            app.NameEditField.Value = name;
            app.StatusLabel.FontColor = [0.2, 0.5, 0.2];
            app.StatusLabel.Text = sprintf('已选择模型: %s', fullfile(path, file));
        end

        function onExportPorts(app)
            % 导出当前模型端口到 Excel
            modelName = strtrim(app.NameEditField.Value);
            if isempty(modelName)
                app.showError('请先输入模型名称！');
                return;
            end
            if ~isvarname(modelName)
                app.showError('模型名称不是有效的 MATLAB 标识符！');
                return;
            end
            if ~(bdIsLoaded(modelName) || exist([modelName, '.slx'], 'file') == 4 || ...
                    exist([modelName, '.mdl'], 'file') == 4)
                app.showError(sprintf('模型 "%s" 不存在！', modelName));
                return;
            end

            % 加载模型（如未加载）
            wasLoaded = bdIsLoaded(modelName);
            if ~wasLoaded
                try
                    load_system(modelName);
                catch ME
                    app.showError(sprintf('无法加载模型 "%s": %s', modelName, ME.message));
                    return;
                end
            end

            app.exportPortsToExcel(modelName);

            % 如果模型原本未加载，导出后关闭
            if ~wasLoaded && bdIsLoaded(modelName)
                close_system(modelName, 0);
            end
        end

        function browseTLC(app)
            [file, path] = uigetfile( ...
                {'*.tlc', 'TLC 文件 (*.tlc)'; '*.*', '所有文件 (*.*)'}, ...
                '选择系统目标文件');
            if isequal(file, 0); return; end
            app.TLCEditField.Value = fullfile(path, file);
        end

        function browseDict(app)
            [file, path] = uigetfile( ...
                {'*.sldd', '数据字典文件 (*.sldd)'; '*.*', '所有文件 (*.*)'}, ...
                '选择数据字典');
            if isequal(file, 0); return; end
            app.DictEditField.Value = fullfile(path, file);
            % uigetfile 后把 GUI 窗口拉回前台
            figure(app.UIFigure);
        end

        function browseExcel(app)
            [file, path] = uigetfile( ...
                {'*.xlsx;*.xls', 'Excel 文件 (*.xlsx, *.xls)'; '*.*', '所有文件 (*.*)'}, ...
                '选择 Excel 文件');
            if isequal(file, 0); return; end
            app.ExcelEditField.Value = fullfile(path, file);
            % uigetfile 后把 GUI 窗口拉回前台
            figure(app.UIFigure);
        end
    end

    % =====================================================================
    % 核心：创建模型
    % =====================================================================
    methods (Access = private)
        function createModel(app)
            % 主入口：验证输入 → 创建模型 → 配置 → 导入端口 → 保存

            % ---- 状态栏重置 ----
            app.StatusLabel.FontColor = [0.4, 0.4, 0.4];
            app.StatusLabel.Text = '正在创建模型...';
            drawnow;

            % ---- 验证模型名称 ----
            modelName = strtrim(app.NameEditField.Value);
            if isempty(modelName)
                app.showError('请输入模型名称！');
                return;
            end
            if ~isvarname(modelName)
                app.showError('模型名称不是有效的 MATLAB 标识符！\n（需以字母开头，只能包含字母、数字、下划线）');
                return;
            end

            % ---- 检查是否已存在，让用户选择处理方式 ----
            modelExists = bdIsLoaded(modelName) || (exist(modelName, 'file') == 4);

            if modelExists
                if bdIsLoaded(modelName)
                    msg = sprintf('模型 "%s" 已经在工作区中加载。\n请选择处理方式：', modelName);
                else
                    msg = sprintf('模型文件 "%s.slx" 已存在。\n请选择处理方式：', modelName);
                end

                choice = uiconfirm(app.UIFigure, msg, '模型已存在', ...
                    'Options', {'覆盖', '加数字后缀', '取消'}, ...
                    'DefaultOption', 2, ...
                    'CancelOption', 3, ...
                    'Icon', 'question');

                switch choice
                    case '覆盖'
                        % 关闭（不保存）并删除已有模型文件
                        try
                            if bdIsLoaded(modelName)
                                close_system(modelName, 0);
                            end
                            if exist(modelName, 'file') == 4
                                delete([modelName, '.slx']);
                            end
                        catch ME
                            app.showError(sprintf('无法清理已有模型: %s', ME.message));
                            return;
                        end

                    case '加数字后缀'
                        % 查找下一个可用名称：modelName1, modelName2, ...
                        suffix = 1;
                        while true
                            newName = sprintf('%s%d', modelName, suffix);
                            if ~bdIsLoaded(newName) && exist(newName, 'file') ~= 4
                                modelName = newName;
                                break;
                            end
                            suffix = suffix + 1;
                        end
                        % 将新名称回填到输入框
                        app.NameEditField.Value = modelName;

                    otherwise  % '取消' 或直接关闭对话框
                        app.StatusLabel.FontColor = [0.4, 0.4, 0.4];
                        app.StatusLabel.Text = '已取消';
                        return;
                end
            end

            % ---- 开始创建 ----
            try
                % ===== 1. 创建空模型 =====
                app.StatusLabel.Text = sprintf('正在创建模型 "%s"...', modelName);
                drawnow;

                new_system(modelName);
                open_system(modelName);

                % ===== 2. 求解器配置 =====
                if app.DiscreteCheckBox.Value
                    sampleTime = str2double(app.SampleTimeEditField.Value);
                    if isnan(sampleTime) || sampleTime <= 0
                        close_system(modelName, 0);
                        app.showError('请输入有效的时间步长（正数）！');
                        return;
                    end
                    set_param(modelName, ...
                        'SolverType',        'Fixed-step', ...
                        'Solver',            'FixedStepDiscrete', ...
                        'FixedStep',         num2str(sampleTime));
                else
                    set_param(modelName, ...
                        'SolverType',        'Variable-step', ...
                        'Solver',            'VariableStepAuto');
                end

                % ===== 3. 代码生成 - 系统目标文件（TLC） =====
                tlcFile = strtrim(app.TLCEditField.Value);
                if ~isempty(tlcFile)
                    set_param(modelName, 'SystemTargetFile', tlcFile);
                end

                % ===== 4. 仅生成代码 =====
                if app.GenCodeOnlyCheckBox.Value
                    set_param(modelName, 'GenCodeOnly', 'on');
                else
                    set_param(modelName, 'GenCodeOnly', 'off');
                end

                % ===== 5. 关联数据字典 =====
                if app.DictCheckBox.Value
                    dictFile = strtrim(app.DictEditField.Value);
                    if ~isempty(dictFile)
                        [dictDir, dictName, dictExt] = fileparts(dictFile);
                        if isempty(dictExt)
                            fullDictPath = fullfile(dictDir, [dictName, '.sldd']);
                        else
                            fullDictPath = dictFile;
                        end

                        % 直接用 set_param 关联数据字典（只需文件名，不含路径）
                        if exist(fullDictPath, 'file')
                            [~, dictBase, dictExt] = fileparts(fullDictPath);
                            dictFileName = [dictBase, dictExt];
                            try
                                set_param(modelName, 'DataDictionary', dictFileName);
                                app.StatusLabel.FontColor = [0, 0.5, 0];
                                app.StatusLabel.Text = sprintf('✓ 已关联数据字典: %s', dictFileName);
                            catch ME2
                                app.showWarning(sprintf('无法关联数据字典: %s', ME2.message));
                            end
                        else
                            app.showWarning(sprintf('数据字典文件不存在: %s\n请先创建 .sldd 文件后再试。', fullDictPath));
                        end
                    end
                end

                % ===== 6. 从 Excel 导入端口 =====
                importCount = '';
                inputPorts = {};
                outputPorts = {};
                if app.ExcelCheckBox.Value
                    excelFile = strtrim(app.ExcelEditField.Value);
                    if isempty(excelFile)
                        close_system(modelName, 0);
                        app.showError('请选择 Excel 文件或取消「从 Excel 导入端口」勾选');
                        return;
                    end
                    if ~exist(excelFile, 'file')
                        close_system(modelName, 0);
                        app.showError(sprintf('Excel 文件不存在：\n%s', excelFile));
                        return;
                    end

                    try
                        [inputPorts, outputPorts] = app.importPortsFromExcel(modelName, excelFile);
                    catch ME_excel
                        close_system(modelName, 0);
                        app.showError(sprintf('导入端口失败: %s', ME_excel.message));
                        return;
                    end
                    app.createPortBlocks(modelName, inputPorts, outputPorts);
                    nIn = length(inputPorts);
                    nOut = length(outputPorts);
                    importCount = sprintf('（导入 %d 个输入端口，%d 个输出端口）', nIn, nOut);

                    % ===== 6a. 检查端口是否有 Code Mapping 相关列 =====
                    cmApplied = app.ExcelCodeMapCheckBox.Value;
                    if cmApplied
                        hasSC = false;
                        for tmpIdx = 1:length(inputPorts)
                            p = inputPorts{tmpIdx};
                            if ~isempty(p.storageClass) || ~isempty(p.identifier) || ...
                                    ~isempty(p.headerFile) || ~isempty(p.definitionFile)
                                hasSC = true; break;
                            end
                        end
                        if ~hasSC
                            for tmpIdx = 1:length(outputPorts)
                                p = outputPorts{tmpIdx};
                                if ~isempty(p.storageClass) || ~isempty(p.identifier) || ...
                                        ~isempty(p.headerFile) || ~isempty(p.definitionFile)
                                    hasSC = true; break;
                                end
                            end
                        end
                        cmApplied = hasSC;
                    end
                end

                % ===== 7. 保存模型（先保存，后续 Code Mapping 才能生效） =====
                save_system(modelName);

                % ===== 7a. 保存后再执行 Code Mapping =====
                if app.ExcelCodeMapCheckBox.Value && cmApplied
                    try
                        % 重新打开已保存的模型，创建 Code Mapping 对象
                        if ~bdIsLoaded(modelName)
                            load_system(modelName);
                        end
                        cmObj = coder.mapping.utils.create(modelName);

                        inputErrors = {}; outputErrors = {};  % 分别收集 Input/Output 端口级错误

                        % 输入端口（每个端口独立 try-catch，互不干扰）
                        for pIdx = 1:length(inputPorts)
                            p = inputPorts{pIdx};
                            try
                                nvPairs = {};
                                if ~isempty(p.storageClass)
                                    nvPairs = [nvPairs, {'StorageClass', p.storageClass}];
                                else
                                    nvPairs = [nvPairs, {'StorageClass', 'Auto'}];
                                end
                                if ~isempty(p.identifier)
                                    nvPairs = [nvPairs, {'Identifier', p.identifier}];
                                end
                                if ~isempty(p.headerFile)
                                    nvPairs = [nvPairs, {'HeaderFile', p.headerFile}];
                                end
                                if ~isempty(p.definitionFile)
                                    nvPairs = [nvPairs, {'DefinitionFile', p.definitionFile}];
                                end
                                setInport(cmObj, p.name, nvPairs{:});
                            catch ME_port
                                inputErrors{end+1} = p.name; %#ok<AGROW>
                            end
                        end

                        % 输出端口（每个端口独立 try-catch，互不干扰）
                        for pIdx = 1:length(outputPorts)
                            p = outputPorts{pIdx};
                            try
                                nvPairs = {};
                                if ~isempty(p.storageClass)
                                    nvPairs = [nvPairs, {'StorageClass', p.storageClass}];
                                else
                                    nvPairs = [nvPairs, {'StorageClass', 'Auto'}];
                                end
                                if ~isempty(p.identifier)
                                    nvPairs = [nvPairs, {'Identifier', p.identifier}];
                                end
                                if ~isempty(p.headerFile)
                                    nvPairs = [nvPairs, {'HeaderFile', p.headerFile}];
                                end
                                if ~isempty(p.definitionFile)
                                    nvPairs = [nvPairs, {'DefinitionFile', p.definitionFile}];
                                end
                                setOutport(cmObj, p.name, nvPairs{:});
                            catch ME_port
                                outputErrors{end+1} = p.name; %#ok<AGROW>
                            end
                        end

                        % 再次保存以写入 Code Mapping 配置
                        save_system(modelName);
                        importCount = [importCount, ' + Code Mapping'];

                        % 统一报告所有出错的端口
                        errParts = {};
                        if ~isempty(inputErrors)
                            errParts{end+1} = '【Input】'; %#ok<AGROW>
                            for i = 1:length(inputErrors)
                                errParts{end+1} = sprintf('  - %s', inputErrors{i}); %#ok<AGROW>
                            end
                        end
                        if ~isempty(outputErrors)
                            errParts{end+1} = '【Output】'; %#ok<AGROW>
                            for i = 1:length(outputErrors)
                                errParts{end+1} = sprintf('  - %s', outputErrors{i}); %#ok<AGROW>
                            end
                        end
                        if ~isempty(errParts)
                            errMsg = sprintf('Code Mapping 配置失败的端口：\n\n%s', strjoin(errParts, '\n'));
                            uialert(app.UIFigure, errMsg, 'Code Mapping 部分失败', 'Icon', 'warning');
                        end

                    catch ME_cmObj
                        app.showWarning(sprintf('Code Mapping 初始化失败: %s\n端口仍已创建。', ME_cmObj.message));
                    end
                end

                if app.OpenModelCheckBox.Value
                    % 保持打开
                else
                    close_system(modelName);
                end

                % ---- 成功 ----
                app.StatusLabel.FontColor = [0, 0.5, 0];
                app.StatusLabel.Text = sprintf('✓ 模型 "%s" 创建成功%s', modelName, importCount);

            catch ME
                % 出错时清理
                try
                    if bdIsLoaded(modelName)
                        close_system(modelName, 0);
                    end
                catch
                    % 忽略清理错误
                end
                app.showError(sprintf('创建失败：%s', ME.message));
            end
        end
    end

    % =====================================================================
    % 端口增删改（更新已有模型端口）
    % =====================================================================
    methods (Access = private)
        function updatePorts(app)
            % 主入口：验证 → 加载模型 → Excel → 同步端口 → Code Mapping → 保存
            app.StatusLabel.FontColor = [0.4, 0.4, 0.4];
            app.StatusLabel.Text = '正在更新端口...';
            drawnow;

            % ---- 1. 验证模型名称 ----
            modelName = strtrim(app.NameEditField.Value);
            if isempty(modelName)
                app.showError('请输入模型名称！');
                return;
            end
            if ~isvarname(modelName)
                app.showError('模型名称不是有效的 MATLAB 标识符！');
                return;
            end

            % ---- 2. 检查模型文件是否存在 ----
            if ~(bdIsLoaded(modelName) || exist([modelName, '.slx'], 'file') == 4 || ...
                    exist([modelName, '.mdl'], 'file') == 4)
                app.showError(sprintf('模型 "%s" 不存在！\n请先确认模型文件路径。', modelName));
                return;
            end

            % ---- 3. 检查 Excel 文件 ----
            if ~app.ExcelCheckBox.Value
                app.showError('修改端口模式需要勾选「从 Excel 导入端口」并选择 Excel 文件。');
                return;
            end
            excelFile = strtrim(app.ExcelEditField.Value);
            if isempty(excelFile)
                app.showError('请选择 Excel 文件！');
                return;
            end
            if ~exist(excelFile, 'file')
                app.showError(sprintf('Excel 文件不存在：\n%s', excelFile));
                return;
            end

            % ---- 4. 加载模型（如未加载） ----
            wasLoaded = bdIsLoaded(modelName);
            if ~wasLoaded
                try
                    load_system(modelName);
                catch ME
                    app.showError(sprintf('无法加载模型 "%s": %s', modelName, ME.message));
                    return;
                end
            end

            % ---- 5. 读取 Excel 端口定义 ----
            try
                [newInputPorts, newOutputPorts] = app.importPortsFromExcel(modelName, excelFile);
            catch ME
                app.showError(sprintf('导入端口失败: %s', ME.message));
                if ~wasLoaded && bdIsLoaded(modelName)
                    close_system(modelName, 0);
                end
                return;
            end

            nNewIn  = length(newInputPorts);
            nNewOut = length(newOutputPorts);

            % ---- 6. 同步端口（增/删/改） ----
            try
                app.syncPorts(modelName, newInputPorts, newOutputPorts);
            catch ME
                app.showError(sprintf('端口同步失败: %s', ME.message));
                if ~wasLoaded && bdIsLoaded(modelName)
                    close_system(modelName, 0);
                end
                return;
            end

            % ---- 7. 保存模型 ----
            save_system(modelName);
            importReport = sprintf('（%d 个输入, %d 个输出）', nNewIn, nNewOut);

            % ---- 8. Code Mapping（可选） ----
            if app.ExcelCodeMapCheckBox.Value
                try
                    % 判断是否有 Excel 列包含 StorageClass/Identifier/HeaderFile/DefinitionFile
                    hasCM = false;
                    allPorts = [newInputPorts, newOutputPorts];
                    for pIdx = 1:length(allPorts)
                        p = allPorts{pIdx};
                        if ~isempty(p.storageClass) || ~isempty(p.identifier) || ...
                                ~isempty(p.headerFile) || ~isempty(p.definitionFile)
                            hasCM = true;
                            break;
                        end
                    end

                    if hasCM
                        if ~bdIsLoaded(modelName)
                            load_system(modelName);
                        end
                        cmObj = coder.mapping.utils.create(modelName);

                        inputErrors = {}; outputErrors = {};  % 分别收集 Input/Output 端口级错误

                        % 输入端口（每个端口独立 try-catch，互不干扰）
                        for pIdx = 1:length(newInputPorts)
                            p = newInputPorts{pIdx};
                            try
                                nvPairs = {};
                                if ~isempty(p.storageClass)
                                    nvPairs = [nvPairs, {'StorageClass', p.storageClass}];
                                else
                                    nvPairs = [nvPairs, {'StorageClass', 'Auto'}];
                                end
                                if ~isempty(p.identifier)
                                    nvPairs = [nvPairs, {'Identifier', p.identifier}];
                                end
                                if ~isempty(p.headerFile)
                                    nvPairs = [nvPairs, {'HeaderFile', p.headerFile}];
                                end
                                if ~isempty(p.definitionFile)
                                    nvPairs = [nvPairs, {'DefinitionFile', p.definitionFile}];
                                end
                                setInport(cmObj, p.name, nvPairs{:});
                            catch ME_port
                                inputErrors{end+1} = p.name; %#ok<AGROW>
                            end
                        end
                        % 输出端口（每个端口独立 try-catch，互不干扰）
                        for pIdx = 1:length(newOutputPorts)
                            p = newOutputPorts{pIdx};
                            try
                                nvPairs = {};
                                if ~isempty(p.storageClass)
                                    nvPairs = [nvPairs, {'StorageClass', p.storageClass}];
                                else
                                    nvPairs = [nvPairs, {'StorageClass', 'Auto'}];
                                end
                                if ~isempty(p.identifier)
                                    nvPairs = [nvPairs, {'Identifier', p.identifier}];
                                end
                                if ~isempty(p.headerFile)
                                    nvPairs = [nvPairs, {'HeaderFile', p.headerFile}];
                                end
                                if ~isempty(p.definitionFile)
                                    nvPairs = [nvPairs, {'DefinitionFile', p.definitionFile}];
                                end
                                setOutport(cmObj, p.name, nvPairs{:});
                            catch ME_port
                                outputErrors{end+1} = p.name; %#ok<AGROW>
                            end
                        end

                        save_system(modelName);
                        importReport = [importReport, ' + Code Mapping'];

                        % 统一报告所有出错的端口
                        errParts = {};
                        if ~isempty(inputErrors)
                            errParts{end+1} = '【Input】'; %#ok<AGROW>
                            for i = 1:length(inputErrors)
                                errParts{end+1} = sprintf('  - %s', inputErrors{i}); %#ok<AGROW>
                            end
                        end
                        if ~isempty(outputErrors)
                            errParts{end+1} = '【Output】'; %#ok<AGROW>
                            for i = 1:length(outputErrors)
                                errParts{end+1} = sprintf('  - %s', outputErrors{i}); %#ok<AGROW>
                            end
                        end
                        if ~isempty(errParts)
                            errMsg = sprintf('Code Mapping 配置失败的端口：\n\n%s', strjoin(errParts, '\n'));
                            uialert(app.UIFigure, errMsg, 'Code Mapping 部分失败', 'Icon', 'warning');
                        end
                    end
                catch ME_cmObj
                    app.showWarning(sprintf('Code Mapping 初始化失败: %s\n端口已更新。', ME_cmObj.message));
                end
            end

            % ---- 9. 完成 ----
            if ~wasLoaded
                close_system(modelName);
            end

            app.StatusLabel.FontColor = [0, 0.5, 0];
            app.StatusLabel.Text = sprintf('✓ 模型 "%s" 端口已更新%s', modelName, importReport);
        end

        function [inBlocks, outBlocks] = getExistingPorts(app, modelName)
            % 扫描模型中现有的 Inport / Outport 块
            % 返回: inBlocks / outBlocks — cell array of struct {name, dataType, position}
            modelName = char(modelName);  % 确保是 char 类型，兼容 string 输入
            inBlocks  = {};
            outBlocks = {};

            % 查找顶层 Inport
            blks = find_system(modelName, 'SearchDepth', 1, 'BlockType', 'Inport');
            for i = 1:length(blks)
                blkPath = blks{i};
                s.name     = get_param(blkPath, 'Name');
                s.dataType = get_param(blkPath, 'OutDataTypeStr');
                s.position = get_param(blkPath, 'Position');
                inBlocks{end+1} = s; %#ok<AGROW>
            end

            % 查找顶层 Outport
            blks = find_system(modelName, 'SearchDepth', 1, 'BlockType', 'Outport');
            for i = 1:length(blks)
                blkPath = blks{i};
                s.name     = get_param(blkPath, 'Name');
                s.dataType = get_param(blkPath, 'OutDataTypeStr');
                s.position = get_param(blkPath, 'Position');
                outBlocks{end+1} = s; %#ok<AGROW>
            end
        end

        function syncPorts(app, modelName, newInputPorts, newOutputPorts)
            % 增量同步端口：将模型中的 Inport/Outport 与 Excel 定义对齐
            % 策略：按端口名匹配，增/删/改

            % ---- A. 获取模型中现有端口 ----
            [oldIn, oldOut] = app.getExistingPorts(modelName);
            oldInNames  = cellfun(@(s) s.name, oldIn,  'UniformOutput', false);
            oldOutNames = cellfun(@(s) s.name, oldOut, 'UniformOutput', false);
            newInNames  = cellfun(@(s) s.name, newInputPorts,  'UniformOutput', false);
            newOutNames = cellfun(@(s) s.name, newOutputPorts, 'UniformOutput', false);

            % ---- B. 输入端口同步 ----
            % 删除：Excel 中没有的旧端口
            for i = 1:length(oldIn)
                if ~ismember(oldIn{i}.name, newInNames)
                    delete_block(sprintf('%s/%s', modelName, oldIn{i}.name));
                end
            end

            % 新增/更新：Excel 中定义的所有端口
            inY = 80;
            % 如果有保留的旧端口，继续在它们之后排列
            keptOldInY = 80;
            for i = 1:length(oldIn)
                if ismember(oldIn{i}.name, newInNames)
                    keptOldInY = max(keptOldInY, oldIn{i}.position(2) + 50);
                end
            end
            inY = keptOldInY;

            for i = 1:length(newInputPorts)
                p = newInputPorts{i};
                blockPath = sprintf('%s/%s', modelName, p.name);
                if ismember(p.name, oldInNames)
                    % 已存在：先比较属性是否有变化
                    oldIdx = find(strcmp(oldInNames, p.name), 1);
                    oldDataType = oldIn{oldIdx}.dataType;
                    newDataType = p.dataType;
                    if ~isempty(newDataType) && ~strcmp(newDataType, 'Inherit: auto') ...
                            && ~strcmp(newDataType, oldDataType)
                        % 数据类型不同 → 尝试 set_param
                        set_param(blockPath, 'OutDataTypeStr', newDataType);
                        % 验证是否生效
                        actualType = get_param(blockPath, 'OutDataTypeStr');
                        if ~strcmp(actualType, newDataType)
                            % set_param 被 Simulink 缓存忽略 → 删了重建
                            oldPos = get_param(blockPath, 'Position');
                            delete_block(blockPath);
                            add_block('simulink/Sources/In1', blockPath);
                            set_param(blockPath, 'Position', oldPos);
                            set_param(blockPath, 'OutDataTypeStr', newDataType);
                        end
                    end
                else
                    % 新增
                    add_block('simulink/Sources/In1', blockPath);
                    set_param(blockPath, 'Position', [60, inY, 90, inY + 14]);
                    if ~isempty(p.dataType) && ~strcmp(p.dataType, 'Inherit: auto')
                        set_param(blockPath, 'OutDataTypeStr', p.dataType);
                    end
                    inY = inY + 50;
                end
            end

            % ---- C. 输出端口同步 ----
            % 删除
            for i = 1:length(oldOut)
                if ~ismember(oldOut{i}.name, newOutNames)
                    delete_block(sprintf('%s/%s', modelName, oldOut{i}.name));
                end
            end

            % 新增/更新
            outY = 80;
            keptOldOutY = 80;
            for i = 1:length(oldOut)
                if ismember(oldOut{i}.name, newOutNames)
                    keptOldOutY = max(keptOldOutY, oldOut{i}.position(2) + 50);
                end
            end
            outY = keptOldOutY;

            for i = 1:length(newOutputPorts)
                p = newOutputPorts{i};
                blockPath = sprintf('%s/%s', modelName, p.name);
                if ismember(p.name, oldOutNames)
                    % 已存在：先比较属性是否有变化
                    oldIdx = find(strcmp(oldOutNames, p.name), 1);
                    oldDataType = oldOut{oldIdx}.dataType;
                    newDataType = p.dataType;
                    if ~isempty(newDataType) && ~strcmp(newDataType, 'Inherit: auto') ...
                            && ~strcmp(newDataType, oldDataType)
                        % 数据类型不同 → 尝试 set_param
                        set_param(blockPath, 'OutDataTypeStr', newDataType);
                        % 验证是否生效
                        actualType = get_param(blockPath, 'OutDataTypeStr');
                        if ~strcmp(actualType, newDataType)
                            % set_param 被 Simulink 缓存忽略 → 删了重建
                            oldPos = get_param(blockPath, 'Position');
                            delete_block(blockPath);
                            add_block('simulink/Sinks/Out1', blockPath);
                            set_param(blockPath, 'Position', oldPos);
                            set_param(blockPath, 'OutDataTypeStr', newDataType);
                        end
                    end
                else
                    add_block('simulink/Sinks/Out1', blockPath);
                    set_param(blockPath, 'Position', [500, outY, 530, outY + 14]);
                    if ~isempty(p.dataType) && ~strcmp(p.dataType, 'Inherit: auto')
                        set_param(blockPath, 'OutDataTypeStr', p.dataType);
                    end
                    outY = outY + 50;
                end
            end
        end

        function exportPortsToExcel(app, modelName)
            % 将模型中当前端口导出到 Excel 模板（辅助功能）
            % 使用 writecell（不依赖 Excel COM），自动避免多余 Sheet1

            % 默认文件名
            defaultName = sprintf('%s_ports.xlsx', modelName);
            [file, path] = uiputfile( ...
                {'*.xlsx', 'Excel 文件 (*.xlsx)'}, ...
                '导出端口到 Excel', defaultName);
            if isequal(file, 0); return; end
            outFile = fullfile(path, file);

            try
                [inBlocks, outBlocks] = app.getExistingPorts(modelName);

                if isempty(inBlocks) && isempty(outBlocks)
                    app.showWarning('模型中未找到任何 Inport/Outport 端口。');
                    return;
                end

                % 获取 Code Mapping 信息
                % 根据官方文档，getInport/getOutport 是包函数，需要 coder.mapping.api.get
                % 返回的 CodeMapping 对象作为第一个参数传入
                hasCM = false;
                cmObj = [];
                try
                    if bdIsLoaded(modelName)
                        cmObj = coder.mapping.api.get(modelName);
                        if ~isempty(cmObj)
                            hasCM = true;
                        end
                    end
                catch
                    % 模型可能没有 Code Mapping 或缺少 Embedded Coder 许可证
                end
                if hasCM
                    app.StatusLabel.FontColor = [0, 0.5, 0];
                    app.StatusLabel.Text = '正在导出端口及 Code Mapping 配置...';
                    drawnow;
                end

                % 列标题
                headers = {'序号', '端口名称', '数据类型', 'StorageClass', 'Identifier', 'HeaderFile', 'DefinitionFile'};

                % ---- 输入端口 ----
                if ~isempty(inBlocks)
                    inData = cell(length(inBlocks) + 1, 7);
                    inData(1, :) = headers;
                    for i = 1:length(inBlocks)
                        blkName = inBlocks{i}.name;
                        inData{i+1, 1} = i;
                        inData{i+1, 2} = blkName;
                        inData{i+1, 3} = inBlocks{i}.dataType;
                        % 尝试从 Code Mapping 读取属性
                        % getInport 是包函数：getInport(cmObj, block, property)
                        if hasCM
                            try
                                sc = getInport(cmObj, blkName, 'StorageClass');
                                if ~isempty(sc), inData{i+1, 4} = sc; end
                            catch
                            end
                            try
                                id = getInport(cmObj, blkName, 'Identifier');
                                if ~isempty(id), inData{i+1, 5} = id; end
                            catch
                            end
                            try
                                hf = getInport(cmObj, blkName, 'HeaderFile');
                                if ~isempty(hf), inData{i+1, 6} = hf; end
                            catch
                            end
                            try
                                df = getInport(cmObj, blkName, 'DefinitionFile');
                                if ~isempty(df), inData{i+1, 7} = df; end
                            catch
                            end
                        end
                    end
                    writecell(inData, outFile, 'Sheet', 'Inputs');
                end

                % ---- 输出端口 ----
                if ~isempty(outBlocks)
                    outData = cell(length(outBlocks) + 1, 7);
                    outData(1, :) = headers;
                    for i = 1:length(outBlocks)
                        blkName = outBlocks{i}.name;
                        outData{i+1, 1} = i;
                        outData{i+1, 2} = blkName;
                        outData{i+1, 3} = outBlocks{i}.dataType;
                        % 尝试从 Code Mapping 读取属性
                        % getOutport 是包函数：getOutport(cmObj, block, property)
                        if hasCM
                            try
                                sc = getOutport(cmObj, blkName, 'StorageClass');
                                if ~isempty(sc), outData{i+1, 4} = sc; end
                            catch
                            end
                            try
                                id = getOutport(cmObj, blkName, 'Identifier');
                                if ~isempty(id), outData{i+1, 5} = id; end
                            catch
                            end
                            try
                                hf = getOutport(cmObj, blkName, 'HeaderFile');
                                if ~isempty(hf), outData{i+1, 6} = hf; end
                            catch
                            end
                            try
                                df = getOutport(cmObj, blkName, 'DefinitionFile');
                                if ~isempty(df), outData{i+1, 7} = df; end
                            catch
                            end
                        end
                    end
                    writecell(outData, outFile, 'Sheet', 'Outputs');
                end

                % 删除 writecell 自动生成的空白 Sheet1
                try
                    sheets = sheetnames(outFile);
                    if ismember('Sheet1', sheets)
                        Excel = actxserver('Excel.Application');
                        Excel.DisplayAlerts = false;
                        cleanupObj = onCleanup(@() Excel.Quit);
                        Workbook = Excel.Workbooks.Open(outFile);
                        cleanupWB = onCleanup(@() Workbook.Close(false));
                        for s = sheets(:)'
                            if strcmp(s{1}, 'Sheet1')
                                Workbook.Sheets.Item('Sheet1').Delete;
                                break;
                            end
                        end
                        Workbook.Save;
                    end
                catch
                    % 非 Windows 或 Excel 不可用，忽略
                end

                app.StatusLabel.FontColor = [0, 0.5, 0];
                app.StatusLabel.Text = sprintf('✓ 端口已导出到: %s', outFile);
                figure(app.UIFigure);
            catch ME
                app.showError(sprintf('导出失败: %s', ME.message));
            end
        end
    end

    % =====================================================================
    % Excel 端口导入
    % =====================================================================
    methods (Access = private)
        function [inputPorts, outputPorts] = importPortsFromExcel(app, modelName, excelFile)
            % 从 Excel 读取输入/输出端口定义并添加到模型中
            %   格式A：两个工作表 "Input" 和 "Output"
            %   格式B：单个工作表，用 "Input" / "Output" 节标题分隔
            %
            % 每列含义（由 PortExtractor 生成）:
            %   列A: 序号（跳过）
            %   列B: 端口名称（必填）
            %   列C: 数据类型（可选）
            %   列D: StorageClass（可选，用于 Code Mapping）
            %   列E: Identifier（可选，用于 Code Mapping）
            %   列F: HeaderFile（可选，用于 Code Mapping）
            %   列G: DefinitionFile（可选，用于 Code Mapping）
            %
            % 返回: inputPorts, outputPorts — 端口 struct 数组（含 name / dataType / storageClass / identifier / headerFile / definitionFile）



            inputPorts = {};
            outputPorts = {};

            % 获取工作表信息
            sheets = sheetnames(excelFile);

            inputRaw = [];
            outputRaw = [];

            % 匹配多种可能的 sheet 名称
            inSheets  = {'Inputs', 'Input', '输入'};
            outSheets = {'Outputs', 'Output', '输出'};

            inIdx = find(ismember(inSheets, sheets), 1);
            if ~isempty(inIdx)
                inputRaw = readcell(excelFile, 'Sheet', inSheets{inIdx});
            end

            outIdx = find(ismember(outSheets, sheets), 1);
            if ~isempty(outIdx)
                outputRaw = readcell(excelFile, 'Sheet', outSheets{outIdx});
            end

            % 如果都没找到，尝试单工作表单文件
            if isempty(inputRaw) && isempty(outputRaw)
                raw = readcell(excelFile);
                if ~isempty(raw)
                    [inputRaw, outputRaw] = app.splitBySection(raw);
                end
            end

            % ---- 解析端口表 ----
            inputPorts = app.parsePortTable(inputRaw);
            outputPorts = app.parsePortTable(outputRaw);
        end

        function createPortBlocks(app, modelName, inputPorts, outputPorts)
            % 在模型中创建 Inport / Outport 块（仅新建模式使用，不检查冲突）
            inY = 80;
            for i = 1:length(inputPorts)
                p = inputPorts{i};
                blockPath = sprintf('%s/%s', modelName, p.name);
                add_block('simulink/Sources/In1', blockPath);
                set_param(blockPath, 'Position', [60, inY, 90, inY + 14]);
                if ~isempty(p.dataType) && ~strcmp(p.dataType, 'Inherit: auto')
                    set_param(blockPath, 'OutDataTypeStr', p.dataType);
                end
                inY = inY + 50;
            end

            outY = 80;
            for i = 1:length(outputPorts)
                p = outputPorts{i};
                blockPath = sprintf('%s/%s', modelName, p.name);
                add_block('simulink/Sinks/Out1', blockPath);
                set_param(blockPath, 'Position', [500, outY, 530, outY + 14]);
                if ~isempty(p.dataType) && ~strcmp(p.dataType, 'Inherit: auto')
                    set_param(blockPath, 'OutDataTypeStr', p.dataType);
                end
                outY = outY + 50;
            end
        end

        function [inputRaw, outputRaw] = splitBySection(app, raw)
            % 从单个工作表中按 "Input"/"Output" 节标题拆分数据
            inputRaw = {};
            outputRaw = {};
            currentSection = '';
            startRow = 1;

            for i = 1:size(raw, 1)
                row = raw(i, :);
                % 跳过空行
                if all(cellfun(@(c) app.isBlank(c), row))
                    continue;
                end

                firstCell = row{1};
                if ~ischar(firstCell) && ~isstring(firstCell)
                    % 非字符行（数值等），归入当前节
                    if strcmp(currentSection, 'input')
                        inputRaw{end+1} = row; %#ok<AGROW>
                    elseif strcmp(currentSection, 'output')
                        outputRaw{end+1} = row; %#ok<AGROW>
                    end
                    continue;
                end

                cellStr = lower(strtrim(firstCell));
                if any(strcmp(cellStr, {'input', '输入', '输入端口', 'inputs'}))
                    currentSection = 'input';
                    continue;
                elseif any(strcmp(cellStr, {'output', '输出', '输出端口', 'outputs'}))
                    currentSection = 'output';
                    continue;
                end

                % 普通行
                if strcmp(currentSection, 'input')
                    inputRaw{end+1} = row; %#ok<AGROW>
                elseif strcmp(currentSection, 'output')
                    outputRaw{end+1} = row; %#ok<AGROW>
                end
            end

            % 如果没有找到任何节标题，把全部内容当作输入
            if isempty(currentSection) && ~isempty(raw)
                inputRaw = cell(size(raw, 1), 1);
                for i = 1:size(raw, 1)
                    inputRaw{i} = raw(i, :);
                end
            end

            % 转为类似 xlsread 输出的 cell 矩阵
            if ~isempty(inputRaw)
                maxCols = max(cellfun(@(c) length(c), inputRaw));
                padded = cell(length(inputRaw), maxCols);
                for i = 1:length(inputRaw)
                    for j = 1:length(inputRaw{i})
                        padded{i, j} = inputRaw{i}{j};
                    end
                end
                inputRaw = padded;
            end
            if ~isempty(outputRaw)
                maxCols = max(cellfun(@(c) length(c), outputRaw));
                padded = cell(length(outputRaw), maxCols);
                for i = 1:length(outputRaw)
                    for j = 1:length(outputRaw{i})
                        padded{i, j} = outputRaw{i}{j};
                    end
                end
                outputRaw = padded;
            end
        end

        function ports = parsePortTable(app, raw)
            % 解析端口表格数据
            %   raw: cell 矩阵，每行一个端口
            %   格式（由 PortExtractor 生成）:
            %   列A: 序号（跳过）
            %   列B: 端口名称（必填）
            %   列C: 数据类型（可选）
            %   列D: StorageClass（可选，用于 Code Mapping）
            %   列E: Identifier（可选，用于 Code Mapping）
            %   列F: HeaderFile（可选，用于 Code Mapping）
            %   列G: DefinitionFile（可选，用于 Code Mapping）
            ports = {};

            if isempty(raw)
                return;
            end

            % 检测并跳过表头行
            startIdx = 1;
            if size(raw, 1) >= 1 && (ischar(raw{1, 1}) || isstring(raw{1, 1}))
                firstWord = lower(strtrim(raw{1, 1}));
                headerWords = {'port', 'name', '端口', '端口名', '端口名称', ...
                    'portname', 'port_name', '信号名', '信号名称', ...
                    '序号', '序列号', '编号'};
                if any(strcmp(firstWord, headerWords))
                    startIdx = 2;
                end
            end

            for i = startIdx:size(raw, 1)
                row = raw(i, :);
                % 跳过空行
                if length(row) < 2 || app.isBlank(row{2})
                    continue;
                end

                % 列B: 端口名称
                portName = strtrim(char(row{2}));
                portName = regexprep(portName, '[\r\n\t\v\f]', '');  % 去掉不可见控制字符
                portName = strtrim(portName);
                if isempty(portName)
                    continue;
                end

                % 列C: 数据类型
                portDataType = '';
                if length(row) >= 3 && ~app.isBlank(row{3})
                    if ischar(row{3}) || isstring(row{3})
                        portDataType = strtrim(char(row{3}));
                    end
                end

                % 列D: StorageClass
                portStorageClass = '';
                if length(row) >= 4 && ~app.isBlank(row{4})
                    if ischar(row{4}) || isstring(row{4})
                        portStorageClass = strtrim(char(row{4}));
                    end
                end

                % 列E: Identifier
                portIdentifier = '';
                if length(row) >= 5 && ~app.isBlank(row{5})
                    if ischar(row{5}) || isstring(row{5})
                        portIdentifier = strtrim(char(row{5}));
                    end
                end

                % 列F: HeaderFile
                portHeaderFile = '';
                if length(row) >= 6 && ~app.isBlank(row{6})
                    if ischar(row{6}) || isstring(row{6})
                        portHeaderFile = strtrim(char(row{6}));
                    end
                end

                % 列G: DefinitionFile
                portDefinitionFile = '';
                if length(row) >= 7 && ~app.isBlank(row{7})
                    if ischar(row{7}) || isstring(row{7})
                        portDefinitionFile = strtrim(char(row{7}));
                    end
                end

                ports{end+1} = struct( ...
                    'name',           portName, ...
                    'dataType',       portDataType, ...
                    'storageClass',   portStorageClass, ...
                    'identifier',     portIdentifier, ...
                    'headerFile',     portHeaderFile, ...
                    'definitionFile', portDefinitionFile); %#ok<AGROW>
            end
        end
    end

    % =====================================================================
    % 工具方法
    % =====================================================================
    methods (Access = private)
        function tf = isBlank(~, val)
            % 判断单元格是否为空或全空白
            if isempty(val)
                tf = true;
            elseif ischar(val) && all(isspace(val))
                tf = true;
            elseif isstring(val) && (val == "" || strtrim(val) == "")
                tf = true;
            elseif ismissing(val)
                tf = true;
            else
                tf = false;
            end
        end

        function showError(app, msg)
            app.StatusLabel.FontColor = [0.8, 0.1, 0.1];
            app.StatusLabel.Text = ['✗ ', msg];
        end

        function showWarning(app, msg)
            app.StatusLabel.FontColor = [0.8, 0.6, 0];
            app.StatusLabel.Text = ['⚠ ', msg];
        end
    end
end
