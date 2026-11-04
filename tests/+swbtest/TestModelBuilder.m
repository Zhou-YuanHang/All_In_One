classdef TestModelBuilder < swbtest.SwbTestBase
    %SWBTEST.TESTMODELBUILDER swb.ModelBuilder 集成测试（需要 Simulink）。
    %   覆盖：连续/离散参数、非法参数、冲突策略（suffix/overwrite+bak/cancel/ask）、
    %         OpenAfterCreate、端口工作簿、数据字典回读、configure。

    properties (Constant)
        P = 'swbTMB_';
    end

    methods (Test)
        function testCreateContinuous(tc)
            d = tc.tmpDir();
            name = [tc.P 'cont'];
            r = swb.ModelBuilder.create(struct('Name', name, 'Folder', d, 'SolverType', 'Continuous'));
            tc.verifyTrue(r.ok, r.errorText);
            tc.verifyEqual(r.modelName, name);
            tc.verifyTrue(isfile(fullfile(d, [name '.slx'])));
            tc.verifyTrue(bdIsLoaded(name));
            tc.verifyEqual(get_param(name, 'SolverType'), 'Variable-step');
            tc.verifyEqual(get_param(name, 'Solver'), 'VariableStepAuto');
            tc.verifyEqual(get_param(name, 'SystemTargetFile'), 'ert.tlc');
            tc.verifyEqual(get_param(name, 'GenCodeOnly'), 'off');
            tc.verifyEqual(r.inputCount, 0);
            tc.verifyEqual(r.outputCount, 0);
            tc.verifyTrue(strcmpi(r.modelPath, fullfile(d, [name '.slx'])));
            tc.verifyFalse(r.cancelled);
        end

        function testCreateDiscrete(tc)
            d = tc.tmpDir();
            name = [tc.P 'disc'];
            r = swb.ModelBuilder.create(struct('Name', name, 'Folder', d, ...
                'SolverType', 'Discrete', 'SampleTime', '0.02'));
            tc.verifyTrue(r.ok, r.errorText);
            tc.verifyEqual(get_param(name, 'SolverType'), 'Fixed-step');
            tc.verifyEqual(get_param(name, 'Solver'), 'FixedStepDiscrete');
            tc.verifyEqual(get_param(name, 'FixedStep'), '0.02');
        end

        function testInvalidParameters(tc)
            d = tc.tmpDir();
            tc.verifyError(@() swb.ModelBuilder.create(struct('Name', '', 'Folder', d)), ...
                'swb:ModelBuilder:emptyName');
            tc.verifyError(@() swb.ModelBuilder.create(struct('Name', '1bad', 'Folder', d)), ...
                'swb:ModelBuilder:badName');
            tc.verifyError(@() swb.ModelBuilder.create(struct('Name', 'bad name', 'Folder', d)), ...
                'swb:ModelBuilder:badName');
            tc.verifyError(@() swb.ModelBuilder.create(struct('Name', [tc.P 'badSolver'], ...
                'Folder', d, 'SolverType', 'Magic')), 'swb:ModelBuilder:badSolverType');
            tc.verifyError(@() swb.ModelBuilder.create(struct('Name', [tc.P 'badSt1'], ...
                'Folder', d, 'SolverType', 'Discrete', 'SampleTime', '-1')), ...
                'swb:ModelBuilder:badSampleTime');
            tc.verifyError(@() swb.ModelBuilder.create(struct('Name', [tc.P 'badSt2'], ...
                'Folder', d, 'SolverType', 'Discrete', 'SampleTime', 'abc')), ...
                'swb:ModelBuilder:badSampleTime');
            tc.verifyError(@() swb.ModelBuilder.create(struct('Name', [tc.P 'badPolicy'], ...
                'Folder', d, 'ConflictPolicy', 'whatever')), 'swb:ModelBuilder:badConflictPolicy');
        end

        function testConflictSuffix(tc)
            d = tc.tmpDir();
            name = [tc.P 'suf'];
            r1 = swb.ModelBuilder.create(struct('Name', name, 'Folder', d, ...
                'OpenAfterCreate', false));
            tc.verifyTrue(r1.ok, r1.errorText);
            r2 = swb.ModelBuilder.create(struct('Name', name, 'Folder', d, ...
                'ConflictPolicy', 'suffix', 'OpenAfterCreate', false));
            tc.verifyTrue(r2.ok, r2.errorText);
            tc.verifyEqual(r2.modelName, [name '1']);
            tc.verifyTrue(isfile(fullfile(d, [name '.slx'])));
            tc.verifyTrue(isfile(fullfile(d, [name '1.slx'])));
            tc.verifyNotEmpty(r2.warnings);
            tc.verifyEqual(r2.backupFile, '', '非覆盖策略不应有备份文件');
        end

        function testConflictOverwriteCreatesBackup(tc)
            d = tc.tmpDir();
            name = [tc.P 'ovr'];
            r1 = swb.ModelBuilder.create(struct('Name', name, 'Folder', d, ...
                'OpenAfterCreate', false));
            tc.verifyTrue(r1.ok, r1.errorText);
            r2 = swb.ModelBuilder.create(struct('Name', name, 'Folder', d, ...
                'ConflictPolicy', 'overwrite', 'OpenAfterCreate', false));
            tc.verifyTrue(r2.ok, r2.errorText);
            bakPath = fullfile(d, [name '.slx.bak']);
            tc.verifyTrue(isfile(bakPath), '覆盖前必须备份为 .slx.bak');
            tc.verifyTrue(isfile(fullfile(d, [name '.slx'])));
            tc.verifyTrue(any(contains(r2.warnings, '备份')));
            % GUI 需要拿到备份文件路径做提示/还原
            tc.verifyEqual(numel(r2.backupFile), numel(bakPath), 'result.backupFile 应暴露备份全路径');
            tc.verifyTrue(strcmpi(r2.backupFile, bakPath), ...
                sprintf('result.backupFile 应为备份路径，实际 "%s"', r2.backupFile));
        end

        function testExternalSameNameModelOnPathNeverTouched(tc)
            % 回归（2026-10-29 实测事故）：搜索路径上存在其它目录的同名模型时，
            % 覆盖策略只允许动目标目录内的文件；绝不能备份/删除外部目录的 .slx。
            dA = tc.tmpDir();
            dB = tc.tmpDir();
            name = [tc.P 'extname'];
            r1 = swb.ModelBuilder.create(struct('Name', name, 'Folder', dA, ...
                'OpenAfterCreate', false));
            tc.verifyTrue(r1.ok, r1.errorText);
            tc.verifyFalse(bdIsLoaded(name));

            oldPath = path;
            addpath(dA);
            cleanupPath = onCleanup(@() path(oldPath));
            r2 = swb.ModelBuilder.create(struct('Name', name, 'Folder', dB, ...
                'ConflictPolicy', 'overwrite', 'OpenAfterCreate', false));
            tc.verifyTrue(r2.ok, r2.errorText);
            tc.verifyTrue(isfile(fullfile(dA, [name '.slx'])), ...
                '外部目录的同名模型必须原样保留');
            tc.verifyFalse(isfile(fullfile(dA, [name '.slx.bak'])), ...
                '不得在外部目录生成 .bak');
            tc.verifyTrue(isfile(fullfile(dB, [name '.slx'])));
            tc.verifyTrue(any(contains(r2.warnings, '另有同名模型')), ...
                '应提示搜索路径上另有同名模型');
            tc.verifyTrue(strcmpi(r2.modelPath, fullfile(dB, [name '.slx'])), ...
                '保存路径必须是目标目录');
        end

        function testConflictCancel(tc)
            d = tc.tmpDir();
            name = [tc.P 'cxl'];
            r1 = swb.ModelBuilder.create(struct('Name', name, 'Folder', d, ...
                'OpenAfterCreate', false));
            tc.verifyTrue(r1.ok, r1.errorText);
            r2 = swb.ModelBuilder.create(struct('Name', name, 'Folder', d, ...
                'ConflictPolicy', 'cancel'));
            tc.verifyFalse(r2.ok);
            tc.verifyTrue(r2.cancelled);
            tc.verifyNotEmpty(r2.errorText);
            tc.verifyTrue(isfile(fullfile(d, [name '.slx'])), '取消后原模型文件必须保留');
        end

        function testConflictAskFcn(tc)
            d = tc.tmpDir();
            name = [tc.P 'ask'];
            r1 = swb.ModelBuilder.create(struct('Name', name, 'Folder', d, ...
                'OpenAfterCreate', false));
            tc.verifyTrue(r1.ok, r1.errorText);

            askCancel = @(kind, msg, options, defaultIdx) 3;
            r2 = swb.ModelBuilder.create(struct('Name', name, 'Folder', d, ...
                'ConflictPolicy', 'ask', 'AskFcn', askCancel, 'OpenAfterCreate', false));
            tc.verifyTrue(r2.cancelled);

            askSuffix = @(kind, msg, options, defaultIdx) 2;
            r3 = swb.ModelBuilder.create(struct('Name', name, 'Folder', d, ...
                'ConflictPolicy', 'ask', 'AskFcn', askSuffix, 'OpenAfterCreate', false));
            tc.verifyTrue(r3.ok, r3.errorText);
            tc.verifyEqual(r3.modelName, [name '1']);
        end

        function testOpenAfterCreateFalse(tc)
            d = tc.tmpDir();
            name = [tc.P 'closed'];
            r = swb.ModelBuilder.create(struct('Name', name, 'Folder', d, ...
                'OpenAfterCreate', false));
            tc.verifyTrue(r.ok, r.errorText);
            tc.verifyFalse(bdIsLoaded(name));
            tc.verifyTrue(isfile(fullfile(d, [name '.slx'])));
        end

        function testPortWorkbookCreatesPorts(tc)
            d = tc.tmpDir();
            name = [tc.P 'ports'];
            inP = tc.makePorts({'speed', 'double'; 'angle', 'single'});
            outP = tc.makePorts({'torque', 'double'});
            tc.createPortModel(d, name, inP, outP);
            tc.verifyEqual(numel(find_system(name, 'SearchDepth', 1, 'BlockType', 'Inport')), 2);
            tc.verifyEqual(numel(find_system(name, 'SearchDepth', 1, 'BlockType', 'Outport')), 1);
            tc.verifyEqual(get_param([name '/speed'], 'OutDataTypeStr'), 'double');
            tc.verifyEqual(get_param([name '/angle'], 'OutDataTypeStr'), 'single');
            tc.verifyEqual(get_param([name '/torque'], 'OutDataTypeStr'), 'double');
            pIn = get_param([name '/speed'], 'Position');
            pIn2 = get_param([name '/angle'], 'Position');
            pOut = get_param([name '/torque'], 'Position');
            tc.verifyEqual(pIn(1), 60);
            tc.verifyEqual(pOut(1), 500);
            tc.verifyGreaterThanOrEqual(pIn2(2) - pIn(2), 40, '输入端口纵向间距应为 50');
        end

        function testDictionaryLink(tc)
            d = tc.tmpDir();
            name = [tc.P 'dict'];
            dictPath = fullfile(d, 'link_dict.sldd');
            dd = Simulink.data.dictionary.create(dictPath);
            dd.close();
            clear dd;
            r = swb.ModelBuilder.create(struct('Name', name, 'Folder', d, ...
                'DictFile', 'link_dict.sldd', 'OpenAfterCreate', true));
            tc.verifyTrue(r.ok, r.errorText);
            tc.verifyEqual(get_param(name, 'DataDictionary'), 'link_dict.sldd');
            tc.verifyTrue(strcmpi(r.dictFile, dictPath));
        end

        function testDictionaryMissingIsWarningOnly(tc)
            d = tc.tmpDir();
            name = [tc.P 'nodict'];
            r = swb.ModelBuilder.create(struct('Name', name, 'Folder', d, ...
                'DictFile', 'not_exist.sldd'));
            tc.verifyTrue(r.ok, r.errorText);
            tc.verifyTrue(any(contains(r.warnings, '数据字典')));
            tc.verifyEqual(get_param(name, 'DataDictionary'), '');
        end

        function testConfigureModel(tc)
            d = tc.tmpDir();
            name = [tc.P 'cfg'];
            r1 = swb.ModelBuilder.create(struct('Name', name, 'Folder', d, ...
                'OpenAfterCreate', true));
            tc.verifyTrue(r1.ok, r1.errorText);
            r2 = swb.ModelBuilder.configure(name, struct('Folder', d, ...
                'SolverType', 'Discrete', 'SampleTime', '0.05', ...
                'GenCodeOnly', true, 'SystemTargetFile', 'ert.tlc'));
            tc.verifyTrue(r2.ok, r2.errorText);
            tc.verifyEqual(get_param(name, 'SolverType'), 'Fixed-step');
            tc.verifyEqual(get_param(name, 'Solver'), 'FixedStepDiscrete');
            tc.verifyEqual(get_param(name, 'FixedStep'), '0.05');
            tc.verifyEqual(get_param(name, 'GenCodeOnly'), 'on');
            tc.verifyEqual(get_param(name, 'SystemTargetFile'), 'ert.tlc');
        end

        function testConfigureLoadsFromFolderAndRestores(tc)
            d = tc.tmpDir();
            name = [tc.P 'cfg2'];
            r1 = swb.ModelBuilder.create(struct('Name', name, 'Folder', d, ...
                'OpenAfterCreate', false));
            tc.verifyTrue(r1.ok, r1.errorText);
            tc.verifyFalse(bdIsLoaded(name));
            r2 = swb.ModelBuilder.configure(name, struct('Folder', d, ...
                'SolverType', 'Discrete', 'SampleTime', '0.1'));
            tc.verifyTrue(r2.ok, r2.errorText);
            tc.verifyFalse(bdIsLoaded(name), 'configure 加载的模型结束后应回到未加载状态');
            load_system(fullfile(d, [name '.slx']));
            tc.verifyEqual(get_param(name, 'FixedStep'), '0.1');
        end
    end
end
