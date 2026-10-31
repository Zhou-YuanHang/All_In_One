classdef TestAppUI < swbtest.SwbTestBase
    %SWBTEST.TESTAPPUI 界面层约定：文件对话框统一走 focusGuard，避免选完文件后 App 退到后台。

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
