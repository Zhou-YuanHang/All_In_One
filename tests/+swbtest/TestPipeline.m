classdef TestPipeline < swbtest.SwbTestBase
    %SWBTEST.TESTPIPELINE 一键流水线编排测试。

    methods (Test)
        function testSchemaDefaultsModelConfigCreatesModel(tc)
            % cfg.Model 直接用 swb.Schema.modelConfigDefaults()（ModelName/ModelFolder）
            % 时应能创建模型；回归 Pipeline 曾误判“未指定模型名称”而跳过建模。
            d = tc.tmpDir();
            dictFile = swbfixture.Workbooks.makeDict(d);
            portFile = swbfixture.Workbooks.makePort(d);

            model = swb.Schema.modelConfigDefaults();
            model.ModelName = 'swbPipeAlias';
            model.ModelFolder = d;
            model.PortWorkbook = portFile;
            model.OpenAfterCreate = false;

            cfg = struct();
            cfg.DictWorkbook = dictFile;
            cfg.PortWorkbook = portFile;
            cfg.SlddFile = fullfile(d, 'swbPipeAlias.sldd');
            cfg.Model = model;
            r = swb.Pipeline.run(cfg);

            tc.verifyTrue(r.ok, sprintf('流水线应成功，实际 errorText=%s', r.errorText));
            names = {r.steps.name};
            idx = find(strcmp(names, '创建模型'), 1);
            tc.verifyNotEmpty(idx, '应有“创建模型”步骤');
            tc.verifyEqual(r.steps(idx).status, 'ok', '建模步骤应成功');
            tc.verifyTrue(isfile(r.artifacts.modelFile), '模型文件应存在');
            tc.verifyEqual(r.modelResult.inputCount, 2);
            tc.verifyEqual(r.modelResult.outputCount, 1);
        end

        function testEmptyModelConfigSkipsModelStep(tc)
            d = tc.tmpDir();
            dictFile = swbfixture.Workbooks.makeDict(d);
            cfg = struct('DictWorkbook', dictFile, 'Model', struct());
            r = swb.Pipeline.run(cfg);
            tc.verifyTrue(r.ok);
            names = {r.steps.name};
            idx = find(strcmp(names, '创建模型'), 1);
            tc.verifyNotEmpty(idx);
            tc.verifyEqual(r.steps(idx).status, 'skipped');
            tc.verifyEmpty(r.artifacts.modelFile);
        end
    end
end
