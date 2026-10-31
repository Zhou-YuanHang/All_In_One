classdef TestTemplateConfig < swbtest.SwbTestBase
    %SWBTEST.TESTTEMPLATECONFIG Config 表候选值：规范化、校验、摘要与设置落盘。

    methods (Test)
        function testDefaultsMatchSchema(tc)
            cfg = swb.TemplateConfig.defaults();
            d = swb.Schema.defaultConfig();
            keys = swb.Schema.configKeys();
            tc.verifyEqual(numel(keys), 8);
            for k = 1:numel(keys)
                tc.verifyTrue(isfield(cfg, keys{k}), keys{k});
                tc.verifyEqual(cfg.(keys{k}), d.(keys{k}), keys{k});
            end
        end

        function testNormalizeTrimsDropsBlanksAndDedups(tc)
            raw = struct('Package', {{' myPackage ', '', 'myPackage', '  '}});
            cfg = swb.TemplateConfig.normalize(raw);
            tc.verifyEqual(cfg.Package, {'myPackage'});
            % 没给出的列用内置默认补齐
            tc.verifyEqual(cfg.Object, swb.Schema.defaultConfig().Object);
            keys = swb.Schema.configKeys();
            tc.verifyEqual(sort(fieldnames(cfg)), sort(keys(:)));
        end

        function testExplicitEmptyListIsKept(tc)
            % 显式清空某一列 = 生成的模板里该列没有下拉（不能悄悄回落到默认）
            raw = swb.Schema.defaultConfig();
            raw.Unit = {};
            cfg = swb.TemplateConfig.normalize(raw);
            tc.verifyEmpty(cfg.Unit);
            tc.verifyEqual(cfg.Package, swb.Schema.defaultConfig().Package);
        end

        function testNormalizeFallbackOnGarbage(tc)
            cfg = swb.TemplateConfig.normalize('not a struct');
            tc.verifyEqual(cfg, swb.Schema.defaultConfig());
            cfg2 = swb.TemplateConfig.normalize([]);
            tc.verifyEqual(cfg2, swb.Schema.defaultConfig());
        end

        function testPrepareReportsProblems(tc)
            raw = struct();
            raw.Package = {'a', 'a', '', ' b '};
            raw.Mystery = {'x'};
            [cfg, w] = swb.TemplateConfig.prepare(raw);
            tc.verifyEqual(cfg.Package, {'a', 'b'});
            joined = strjoin(w, ' | ');
            tc.verifyTrue(contains(joined, '重复'), joined);
            tc.verifyTrue(contains(joined, '空行'), joined);
            tc.verifyTrue(contains(joined, '首尾空白'), joined);
            tc.verifyTrue(contains(joined, '未知列'), joined);
        end

        function testPrepareWarnsAboutEmptyColumn(tc)
            raw = swb.Schema.defaultConfig();
            raw.Complexity = {};
            [~, w] = swb.TemplateConfig.prepare(raw);
            tc.verifyTrue(any(contains(w, 'Complexity')), strjoin(w, ' | '));
            tc.verifyTrue(any(contains(w, '没有下拉')), strjoin(w, ' | '));
        end

        function testValidateAcceptsDefaults(tc)
            [ok, msg] = swb.TemplateConfig.validate(swb.Schema.defaultConfig());
            tc.verifyTrue(ok, msg);
            tc.verifyEmpty(msg);
        end

        function testValidateRejectsAllEmpty(tc)
            cfg = struct();
            keys = swb.Schema.configKeys();
            for k = 1:numel(keys)
                cfg.(keys{k}) = {};
            end
            [ok, msg] = swb.TemplateConfig.validate(cfg);
            tc.verifyFalse(ok);
            tc.verifyTrue(contains(msg, '没有任何下拉列表'), msg);
        end

        function testValidateRejectsNewlineAndTab(tc)
            cfg = swb.Schema.defaultConfig();
            cfg.Unit{1} = sprintf('a%sb', newline);
            [ok, msg] = swb.TemplateConfig.validate(cfg);
            tc.verifyFalse(ok);
            tc.verifyTrue(contains(msg, '换行'), msg);

            cfg = swb.Schema.defaultConfig();
            cfg.Unit{2} = sprintf('a%sb', char(9));
            [ok, msg] = swb.TemplateConfig.validate(cfg);
            tc.verifyFalse(ok);
            tc.verifyTrue(contains(msg, '制表符'), msg);
        end

        function testValidateRejectsMissingColumn(tc)
            cfg = rmfield(swb.Schema.defaultConfig(), 'Unit');
            [ok, msg] = swb.TemplateConfig.validate(cfg);
            tc.verifyFalse(ok);
            tc.verifyTrue(contains(msg, 'Unit'), msg);
        end

        function testSummaryTagsDefaultAndCustom(tc)
            tc.verifyTrue(contains(swb.TemplateConfig.summary(swb.Schema.defaultConfig()), '内置默认'));
            cfg = swb.Schema.defaultConfig();
            cfg.Unit = {'V', 'A'};
            tc.verifyTrue(contains(swb.TemplateConfig.summary(cfg), '已自定义'));
            tc.verifyTrue(contains(swb.TemplateConfig.summary(cfg), '2 项') || ...
                contains(swb.TemplateConfig.summary(cfg), '项'));
        end

        function testSettingsRoundTrip(tc)
            f = fullfile(tc.tmpDir(), 'simworkbench.json');
            s = swb.Settings(f);
            s.TemplateConfig.Package = {'myPackage', 'Simulink', 'OnlyHere'};
            s.save();
            tc.verifyTrue(isfile(f));

            s2 = swb.Settings(f);
            tc.verifyEqual(s2.TemplateConfig.Package, {'myPackage', 'Simulink', 'OnlyHere'});
            tc.verifyEqual(s2.TemplateConfig.Object, swb.Schema.defaultConfig().Object);
        end
    end
end
