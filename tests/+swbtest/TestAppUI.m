classdef TestAppUI < swbtest.SwbTestBase
    %SWBTEST.TESTAPPUI 界面层约定：文件对话框统一走 focusGuard，避免选完文件后 App 退到后台。

    properties (Constant)
        P = 'swbUI_';
    end

    methods (Test)
        function testFocusGuardHelpersExist(tc)
            % 对话框包装方法与焦点恢复方法必须存在（私有方法，用 metaclass 检查）
            mc = ?SimWorkbench;
            names = {mc.MethodList.Name};
            wants = {'raiseApp', 'focusGuard', 'pickOpenFile', 'pickSaveFile', ...
                     'pickFolder', 'confirmAndRaise'};
            for k = 1:numel(wants)
                tc.verifyTrue(any(strcmp(names, wants{k})), ...
                    sprintf('SimWorkbench 应有私有方法 %s', wants{k}));
            end
        end

        function testDialogsAreCentralized(tc)
            % uigetfile/uiputfile/uigetdir/uiconfirm 只允许出现在包装方法里：
            % 任何一处直接调用都意味着某个对话框没走焦点恢复。
            root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
            src = fileread(fullfile(root, 'app', 'SimWorkbench.m'));
            tc.verifyEqual(numel(strfind(src, 'uigetfile(')), 2, 'uigetfile 只应出现在 pickOpenFile 的两个分支');
            tc.verifyEqual(numel(strfind(src, 'uiputfile(')), 2, 'uiputfile 只应出现在 pickSaveFile 的两个分支');
            tc.verifyEqual(numel(strfind(src, 'uigetdir(')), 1, 'uigetdir 只应出现在 pickFolder');
            tc.verifyEqual(numel(strfind(src, 'uiconfirm(')), 1, 'uiconfirm 只应出现在 confirmAndRaise');
            tc.verifyEqual(numel(strfind(src, 'uiconfirm(app.UIFigure')), 1);

            % 回调里必须全部走包装方法
            tc.verifyGreaterThanOrEqual(numel(strfind(src, 'app.pickOpenFile(')), 5);
            tc.verifyGreaterThanOrEqual(numel(strfind(src, 'app.pickSaveFile(')), 4);
            tc.verifyGreaterThanOrEqual(numel(strfind(src, 'app.pickFolder(')), 1);
            tc.verifyGreaterThanOrEqual(numel(strfind(src, 'app.confirmAndRaise(')), 5);
        end

        function testTemplateConfigEditorIsWired(tc)
            % 「设置 → 模板 Config → 编辑…」必须打开真正的编辑器，
            % 而不是只往日志里写一行 "编辑界面将在后续版本接入" 的占位实现。
            root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
            src = fileread(fullfile(root, 'app', 'SimWorkbench.m'));
            tc.verifyTrue(contains(src, 'swb.ui.TemplateConfigDialog'), ...
                'onEditTemplateConfig 应打开 swb.ui.TemplateConfigDialog');
            tc.verifyFalse(contains(src, '后续版本接入'), ...
                '模板 Config 编辑不应再是占位实现');
            tc.verifyTrue(contains(src, 'app.templateConfigSummary('), ...
                '设置页应显示当前候选值摘要');
        end

        function testModelNameIsEditableDropdown(tc)
            % 「模型与端口」的模型名称要既能手写、也能选现有模型：
            % 必须是可编辑 uidropdown，并带刷新候选与选中后切目录的回调。
            app = SimWorkbench();
            tc.addTeardown(@() delete(app));
            tc.verifyClass(app.H.modelNameEdit, 'matlab.ui.control.DropDown', ...
                '模型名称应为下拉框');
            tc.verifyEqual(char(app.H.modelNameEdit.Editable), 'on', ...
                '模型名称下拉框必须可手写');   % Editable 是 OnOffSwitchState 枚举
            tc.verifyTrue(isfield(app.H, 'modelNameEdit'));
        end

        function testModelNameDropdownListsExistingModels(tc)
            % 刷新按钮要把已打开/目录里的模型放进候选，同时保留手写名称。
            d = tc.tmpDir();
            name = [tc.P 'pick'];
            tc.createPortModel(d, name, tc.makePorts({'u1', 'double'}), ...
                tc.makePorts({'y1', 'double'}));
            app = SimWorkbench();
            tc.addTeardown(@() delete(app));
            app.H.modelFolderEdit.Value = d;
            app.H.modelRefreshButton.ButtonPushedFcn(app.H.modelRefreshButton, []);
            tc.verifyTrue(any(strcmp(app.H.modelNameEdit.Items, name)), ...
                '刷新后候选里应有保存目录中的现有模型');

            % 手写任意名称后刷新，用户输入不能被清掉
            app.H.modelNameEdit.Value = 'handTypedModel';
            app.H.modelRefreshButton.ButtonPushedFcn(app.H.modelRefreshButton, []);
            tc.verifyEqual(app.H.modelNameEdit.Value, 'handTypedModel');
            tc.verifyTrue(any(strcmp(app.H.modelNameEdit.Items, 'handTypedModel')));
        end

        function testSelectingExistingModelSwitchesFolder(tc)
            % 从下拉里选现有模型时，保存目录自动切到该模型所在目录。
            d = tc.tmpDir();
            name = [tc.P 'switch'];
            tc.createPortModel(d, name, tc.makePorts({'u1', 'double'}), ...
                tc.makePorts({'y1', 'double'}));
            other = tc.tmpDir();
            app = SimWorkbench();
            tc.addTeardown(@() delete(app));
            app.H.modelFolderEdit.Value = other;
            app.H.modelNameEdit.Items = [app.H.modelNameEdit.Items, {name}];
            app.H.modelNameEdit.Value = name;
            app.H.modelNameEdit.ValueChangedFcn(app.H.modelNameEdit, []);
            tc.verifyTrue(strcmpi(app.H.modelFolderEdit.Value, d), ...
                '选现有模型后保存目录应切到模型目录');
        end

        function testExportDefaultNameUsesModelNamePorts(tc)
            % 导出端口时默认文件名 = <模型名称>_ports.xlsx
            root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
            src = fileread(fullfile(root, 'app', 'SimWorkbench.m'));
            tc.verifyTrue(contains(src, 'swb.PortExport.defaultFileName('), ...
                '导出回调应使用 PortExport.defaultFileName 作为默认文件名');
            tc.verifyTrue(contains(src, '刷新'), '模型页应有刷新候选的按钮');
            tc.verifyTrue(contains(src, 'swb.ModelCatalog.'), ...
                '候选模型应来自 swb.ModelCatalog');
        end

        function testAppConstructsWithFocusHelpers(tc)
            % 构造函数里不应依赖对话框；构造/销毁应干净（helpers 不改变这一点）
            app = SimWorkbench();
            tc.verifyTrue(isvalid(app));
            tc.verifyTrue(isvalid(app.UIFigure), '应创建主窗口');
            delete(app);
            tc.verifyFalse(isvalid(app));
        end
    end
end
