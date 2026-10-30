classdef TestDictionary < matlab.unittest.TestCase
    %SWB.TESTDICTIONARY swb.Dictionary 单元测试：写入/增量更新/清理/失败隔离。

    properties (Access = private)
        TempDir
    end

    methods (TestMethodSetup)
        function setupTempDir(testCase)
            testCase.TempDir = tempname();
            mkdir(testCase.TempDir);
            testCase.addTeardown(@() rmDirQuiet(testCase.TempDir));
        end
    end

    methods (Test)
        function testCreateDictionaryAndReadEntries(testCase)
            dictPath = fullfile(testCase.TempDir, 'sample.sldd');
            stats = swb.Dictionary.writeScript(dictPath, sampleScript(0.35, true));

            testCase.verifyTrue(stats.ok, stats.errorText);
            testCase.verifyEqual(stats.added, 3);
            testCase.verifyEqual(stats.updated, 0);
            testCase.verifyEqual(stats.skipped, 0);
            testCase.verifyEqual(stats.failed, 0);
            testCase.verifyTrue(stats.dictCreated);
            testCase.verifyEqual(stats.totalBefore, 0);
            testCase.verifyEqual(stats.totalAfter, 3);
            testCase.verifyTrue(isfile(dictPath));
            testCase.verifyEmpty(stats.verifyMissing);

            entries = swb.Dictionary.readEntries(dictPath);
            testCase.verifyEqual(numel(entries), 3);
            testCase.verifyEqual(sort({entries.Name}), sort({'M_Sig', 'Kp', 'FaultBus'}));
            types = containers.Map({entries.Name}, {entries.Type});
            testCase.verifyEqual(types('M_Sig'), 'Signal');
            testCase.verifyEqual(types('Kp'), 'Parameter');
            testCase.verifyEqual(types('FaultBus'), 'Bus');

            % 脚本在局部工作区执行，不污染基础工作区
            testCase.verifyEqual(evalin('base', 'exist(''M_Sig'', ''var'')'), 0);
            testCase.verifyEqual(evalin('base', 'exist(''Kp'', ''var'')'), 0);
        end

        function testRewriteSameScriptSkips(testCase)
            dictPath = fullfile(testCase.TempDir, 'sample.sldd');
            script = sampleScript(0.35, true);
            first = swb.Dictionary.writeScript(dictPath, script);
            testCase.verifyTrue(first.ok, first.errorText);
            testCase.verifyEqual(first.added, 3);

            second = swb.Dictionary.writeScript(dictPath, script);
            testCase.verifyTrue(second.ok, second.errorText);
            testCase.verifyEqual(second.added, 0);
            testCase.verifyEqual(second.updated, 0);
            testCase.verifyEqual(second.skipped, 3);
            testCase.verifyFalse(second.dictCreated);
            testCase.verifyEqual(second.totalAfter, 3);

            entries = swb.Dictionary.readEntries(dictPath);
            testCase.verifyEqual(numel(entries), 3);
        end

        function testChangedValueUpdates(testCase)
            dictPath = fullfile(testCase.TempDir, 'sample.sldd');
            first = swb.Dictionary.writeScript(dictPath, sampleScript(0.35, true));
            testCase.verifyTrue(first.ok, first.errorText);

            second = swb.Dictionary.writeScript(dictPath, sampleScript(0.5, true));
            testCase.verifyTrue(second.ok, second.errorText);
            testCase.verifyEqual(second.added, 0);
            testCase.verifyEqual(second.updated, 1);
            testCase.verifyEqual(second.skipped, 2);

            entries = swb.Dictionary.readEntries(dictPath);
            kp = entries(strcmp({entries.Name}, 'Kp'));
            testCase.verifyEqual(kp.Value.Value, 0.5, 'AbsTol', 1e-12);
        end

        function testCleanExtraRemovesStaleEntries(testCase)
            dictPath = fullfile(testCase.TempDir, 'sample.sldd');
            first = swb.Dictionary.writeScript(dictPath, sampleScript(0.35, true));
            testCase.verifyTrue(first.ok, first.errorText);
            testCase.verifyEqual(first.added, 3);

            % 第二次脚本不再包含 M_Sig
            smallScript = sampleScript(0.35, false);
            opts = struct('CleanExtra', true, 'ConfirmFcn', @(msg) true);
            second = swb.Dictionary.writeScript(dictPath, smallScript, opts);
            testCase.verifyTrue(second.ok, second.errorText);
            testCase.verifyEqual(second.cleaned, 1);
            testCase.verifyEqual(second.totalAfter, 2);

            entries = swb.Dictionary.readEntries(dictPath);
            testCase.verifyEqual(numel(entries), 2);
            testCase.verifyEmpty(entries(strcmp({entries.Name}, 'M_Sig')));
        end

        function testCleanExtraCanBeCanceled(testCase)
            dictPath = fullfile(testCase.TempDir, 'sample.sldd');
            first = swb.Dictionary.writeScript(dictPath, sampleScript(0.35, true));
            testCase.verifyTrue(first.ok, first.errorText);

            opts = struct('CleanExtra', true, 'ConfirmFcn', @(msg) false);
            second = swb.Dictionary.writeScript(dictPath, sampleScript(0.35, false), opts);
            testCase.verifyTrue(second.ok, second.errorText);
            testCase.verifyEqual(second.cleaned, 0);
            testCase.verifyEqual(second.totalAfter, 3);
        end

        function testBrokenScriptReportsErrorWithoutCreatingDictionary(testCase)
            dictPath = fullfile(testCase.TempDir, 'broken.sldd');
            stats = swb.Dictionary.writeScript(dictPath, ...
                'Bad = NoSuchClassForTest.Signal;');

            testCase.verifyFalse(stats.ok);
            testCase.verifyEqual(stats.failed, 1);
            testCase.verifyNotEmpty(stats.errorText);
            testCase.verifyFalse(isfile(dictPath));
        end

        function testPartialScriptStillWritesGoodObjects(testCase)
            dictPath = fullfile(testCase.TempDir, 'partial.sldd');
            script = [sampleScript(0.35, true), newline, ...
                      'Bad = NoSuchClassForTest.Signal;', newline];
            stats = swb.Dictionary.writeScript(dictPath, script);

            testCase.verifyFalse(stats.ok);
            testCase.verifyEqual(stats.added, 3);
            testCase.verifyEqual(stats.failed, 1);
            testCase.verifyTrue(any(strcmp(stats.failedNames, '<脚本执行中断>')));

            entries = swb.Dictionary.readEntries(dictPath);
            testCase.verifyEqual(numel(entries), 3);
        end

        function testOpenOrCreateAndClose(testCase)
            dictPath = fullfile(testCase.TempDir, 'manual.sldd');
            [dict, isNew] = swb.Dictionary.openOrCreate(dictPath);
            testCase.verifyTrue(isNew);
            swb.Dictionary.close(dict);

            [dict2, isNew2] = swb.Dictionary.openOrCreate(dictPath);
            testCase.verifyFalse(isNew2);
            swb.Dictionary.close(dict2);

            % 重复关闭不应报错
            testCase.verifyWarningFree(@() swb.Dictionary.close(dict2));

            missing = swb.Dictionary.readEntries(fullfile(testCase.TempDir, 'nope.sldd'));
            testCase.verifyEmpty(missing);
            testCase.verifyEqual(numel(fieldnames(missing)), 4);
        end
    end

end

function rmDirQuiet(d)
try
    if isfolder(d)
        rmdir(d, 's');
    end
catch
end
end

function txt = sampleScript(prmValue, includeSignal)
% 构造与 ScriptBuilder 输出同构的脚本文本（只用内置存储类，避免依赖 myPackage）
parts = {};
if includeSignal
    parts{end+1} = [
        'M_Sig = Simulink.Signal;', newline, ...
        'M_Sig.DataType = ''single'';', newline, ...
        'M_Sig.InitialValue = ''0'';', newline, ...
        'M_Sig.Dimensions = 1;', newline, ...
        'M_Sig.Complexity = ''real'';', newline, ...
        'M_Sig.CoderInfo.StorageClass = ''ExportedGlobal'';', newline];
end
parts{end+1} = [
    'Kp = Simulink.Parameter;', newline, ...
    'Kp.DataType = ''double'';', newline, ...
    'Kp.Dimensions = 1;', newline, ...   % 必须先设 Dimensions 再设 Value
    'Kp.Value = ', sprintf('%.15g', prmValue), ';', newline, ...
    'Kp.CoderInfo.StorageClass = ''SimulinkGlobal'';', newline];
parts{end+1} = [
    'FaultBus = Simulink.Bus;', newline, ...
    'FaultBus.Description = ''fault bus'';', newline, ...
    'el = Simulink.BusElement;', newline, ...
    'el.Name = ''IcSensorFault'';', newline, ...
    'el.DataType = ''uint8'';', newline, ...
    'el.Dimensions = 1;', newline, ...
    'FaultBus.Elements = el;', newline, ...
    'clear el;', newline];
txt = strjoin(parts, '');
end
