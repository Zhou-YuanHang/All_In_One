classdef TestTemplateConfigDialog < swbtest.SwbTestBase
    %SWBTEST.TESTTEMPLATECONFIGDIALOG 模板 Config 模态编辑器：构造、接受、拒绝、取消、恢复默认。

    methods (Test)
        function testConstructsWithAllColumns(tc)
            cfg = swb.TemplateConfig.defaults();
            cfg.Package = {'myPackage', 'Simulink'};
            d = swb.ui.TemplateConfigDialog([], cfg);
            tc.addTeardown(@() delete(d));
            tc.verifyEqual(char(d.Figure.Visible), 'off', '构造后应保持隐藏，由 show() 显示');
            tc.verifyTrue(isa(d.Figure, 'matlab.ui.Figure'));
            tc.verifyEqual(numel(d.Areas), 8);
            tc.verifyEqual(d.Areas{1}.Value(:)', {'myPackage', 'Simulink'});
            tc.verifyTrue(contains(d.CountLabel.Text, '候选值'));
        end

        function testTryAcceptNormalizes(tc)
            d = swb.ui.TemplateConfigDialog([], swb.Schema.defaultConfig());
            tc.addTeardown(@() delete(d));
            d.Areas{1}.Value = {' myPackage ', '', 'Simulink', 'myPackage'};
            [ok, msg] = d.tryAccept();
            tc.verifyTrue(ok, msg);
            tc.verifyEqual(d.Result.Package, {'myPackage', 'Simulink'});
            tc.verifyTrue(any(contains(d.Warnings, '重复')), strjoin(d.Warnings, ' | '));
        end

        function testTryAcceptRejectsAllEmpty(tc)
            d = swb.ui.TemplateConfigDialog([], swb.Schema.defaultConfig());
            tc.addTeardown(@() delete(d));
            for k = 1:numel(d.Keys)
                d.Areas{k}.Value = {''};
            end
            [ok, msg] = d.tryAccept();
            tc.verifyFalse(ok);
            tc.verifyTrue(contains(msg, '没有任何下拉列表'), msg);
            tc.verifyEmpty(d.Result, '校验失败时不应留下部分结果');
        end

        function testCancelLeavesEmptyResult(tc)
            d = swb.ui.TemplateConfigDialog([], swb.Schema.defaultConfig());
            d.Result = {'stale'};
            d.onCancel();
            tc.verifyEmpty(d.Result);
            tc.verifyFalse(isvalid(d.Figure));
        end

        function testResetRestoresDefaults(tc)
            cfg = swb.Schema.defaultConfig();
            cfg.Unit = {'OnlyUnit'};
            d = swb.ui.TemplateConfigDialog([], cfg);
            tc.addTeardown(@() delete(d));
            idx = find(strcmp(d.Keys, 'Unit'));
            tc.verifyEqual(d.Areas{idx}.Value(:)', {'OnlyUnit'});
            d.onReset();
            def = swb.Schema.defaultConfig();
            tc.verifyEqual(d.Areas{idx}.Value(:)', def.Unit(:)');
        end

        function testCollectReturnsAllKeys(tc)
            d = swb.ui.TemplateConfigDialog([], swb.Schema.defaultConfig());
            tc.addTeardown(@() delete(d));
            raw = d.collect();
            keys = swb.Schema.configKeys();
            tc.verifyEqual(sort(fieldnames(raw)), sort(keys(:)));
            def = swb.Schema.defaultConfig();
            tc.verifyEqual(raw.Package(:)', def.Package(:)');
        end
    end
end
