classdef TestScriptBuilder < matlab.unittest.TestCase
    %SWB.TEST.SCRIPTBUILDER 数据对象脚本生成测试。
    %   与旧 Excel2Workspace 5 参数模式做 golden 文本对比（忽略时间戳行与行尾空白），
    %   并断言关键行：CoderInfo.CustomAttributes、BusElement saveVarsTmp、枚举 classdef、
    %   Parameter Dimensions 在 Value 之前、坏 CSC 行的 try/catch 包裹。

    properties
        TempDir char
    end

    methods (TestMethodSetup)
        function createTempDir(tc)
            tc.TempDir = tempname();
            mkdir(tc.TempDir);
            tc.addTeardown(@() swbtest.TestScriptBuilder.rmDirQuiet(tc.TempDir));
        end
    end

    methods (Test)
        function testGoldenMatchesLegacy(tc)
            wb = swbfixture.Workbooks.makeDict(tc.TempDir);
            tc.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                swbtest.TestScriptBuilder.legacyDir()));

            oldDir = fullfile(tc.TempDir, 'old');
            newDir = fullfile(tc.TempDir, 'new');
            mkdir(oldDir); mkdir(newDir);
            oldOut = fullfile(oldDir, 'objects.m');
            newOut = fullfile(newDir, 'objects.m');

            allSheets = cellstr(string(sheetnames(wb)));
            imp = swb.Schema.importableSheetNames();
            present = {};
            for k = 1:numel(imp)
                if any(strcmpi(allSheets, imp{k}))
                    present{end+1} = imp{k}; %#ok<AGROW>
                end
            end
            sel = zeros(1, numel(present));
            for k = 1:numel(present)
                sel(k) = find(strcmpi(allSheets, present{k}), 1);
            end

            Excel2Workspace(allSheets, wb, oldOut, 'dict_sample.xlsx', sel);
            r = swb.ScriptBuilder.build(wb, {}, newOut);
            tc.verifyTrue(r.ok, 'ScriptBuilder.build 应成功。');
            tc.verifyTrue(isfile(oldOut) && isfile(newOut));
            tc.verifyEqual(r.writtenFile, newOut);

            oldLines = swbtest.TestScriptBuilder.normLines(oldOut);
            newLines = swbtest.TestScriptBuilder.normLines(newOut);
            tc.verifyEqual(newLines, oldLines, ...
                sprintf('生成脚本文本应与旧实现一致（旧 %d 行 / 新 %d 行）。', ...
                numel(oldLines), numel(newLines)));

            tc.verifyEqual(numel(r.enumFiles), 1);
            oldEnum = fullfile(oldDir, 'GEAR.m');
            newEnum = fullfile(newDir, 'GEAR.m');
            tc.verifyTrue(isfile(oldEnum) && isfile(newEnum), '枚举 classdef 文件应存在。');
            tc.verifyEqual(swbtest.TestScriptBuilder.normLines(newEnum), ...
                swbtest.TestScriptBuilder.normLines(oldEnum), '枚举 classdef 文件应与旧实现一致。');
        end

        function testKeyLines(tc)
            wb = swbfixture.Workbooks.makeDict(tc.TempDir);
            r = swb.ScriptBuilder.build(wb, {}, fullfile(tc.TempDir, 'objects.m'));
            text = r.text;
            tc.verifyTrue(contains(text, ...
                "try M_Sig.CoderInfo.CustomAttributes.HeaderFile = 'MCU.h'; catch, end"));
            tc.verifyTrue(contains(text, ...
                "try Kp.CoderInfo.CustomAttributes.DefinitionFile = 'MCU.c'; catch, end"));
            tc.verifyTrue(contains(text, 'saveVarsTmp{1} = Simulink.BusElement;'));
            tc.verifyTrue(contains(text, "saveVarsTmp{1}.Name = 'IcSensorFault';"));
            tc.verifyTrue(contains(text, 'FaultBus.Elements = saveVarsTmp{1};'));
            tc.verifyTrue(contains(text, 'Mode.CoderInfo.CustomStorageClass = ''Define'';'));

            tc.verifyEqual(numel(r.objects), 4);
            tc.verifyEqual(sort({r.objects.name}), sort({'M_Sig','Kp','Mode','FaultBus'}));
            tc.verifyEqual(sort({r.objects.type}), sort({'Signal','Parameter','Const','Bus'}));
            tc.verifyEqual(numel(r.busElements), 1);
            tc.verifyEqual(r.busElements(1).bus, 'FaultBus');
            tc.verifyEqual(r.busElements(1).name, 'IcSensorFault');

            enumText = fileread(fullfile(tc.TempDir, 'GEAR.m'));
            tc.verifyTrue(contains(enumText, 'classdef GEAR < uint8'));
            tc.verifyTrue(contains(enumText, 'enumeration'));
            tc.verifyTrue(contains(enumText, 'H (0)'));
            tc.verifyTrue(contains(enumText, 'M (1)'));
        end

        function testParameterDimensionsBeforeValue(tc)
            wb = swbfixture.Workbooks.makeDict(tc.TempDir);
            r = swb.ScriptBuilder.build(wb, {}, '');
            lines = regexp(r.text, '\r\n|\n|\r', 'split');
            iDim = find(contains(lines, 'Kp.Dimensions ='), 1);
            iVal = find(contains(lines, 'Kp.Value ='), 1);
            tc.verifyNotEmpty(iDim, '应生成 Dimensions 赋值。');
            tc.verifyNotEmpty(iVal, '应生成 Value 赋值。');
            tc.verifyLessThan(iDim, iVal, 'Dimensions 必须在 Value 之前赋值。');
        end

        function testBadCustomStorageClassWrapped(tc)
            wb = swbfixture.Workbooks.makeDict(tc.TempDir);
            swbtest.TestScriptBuilder.setCell(wb, 'Signal', 1, 'Package', 'Simulink');
            swbtest.TestScriptBuilder.setCell(wb, 'Signal', 1, 'CustomStorageClass', 'YS_SelectRAMSignal');
            r = swb.ScriptBuilder.build(wb, {}, '');
            tc.verifyTrue(contains(r.text, ...
                "try M_Sig.CoderInfo.StorageClass = 'Custom'; catch, end"), ...
                'Package=Simulink 的自定义 CSC 赋值必须包 try/catch。');
            tc.verifyTrue(contains(r.text, ...
                "try M_Sig.CoderInfo.CustomStorageClass = 'YS_SelectRAMSignal'; catch, end"));
        end

        function testEmptyOutFileOnlyReturnsText(tc)
            wb = swbfixture.Workbooks.makeDict(tc.TempDir);
            r = swb.ScriptBuilder.build(wb, {}, '');
            tc.verifyNotEmpty(r.text);
            tc.verifyTrue(isempty(r.writtenFile), 'outFile 为空时不应写文件。');
            tc.verifyTrue(isempty(r.enumFiles) || all(cellfun(@isempty, r.enumFiles)) ...
                || ~isfile(fullfile(tc.TempDir, 'GEAR.m')), ...
                'outFile 为空时不应在临时目录写枚举文件。');
        end

        function testSelectionBusOnly(tc)
            wb = swbfixture.Workbooks.makeDict(tc.TempDir);
            r = swb.ScriptBuilder.build(wb, {'Bus'}, '');
            tc.verifyTrue(contains(r.text, 'FaultBus = Simulink.Bus;'));
            tc.verifyFalse(contains(r.text, 'M_Sig = myPackage.Signal;'));
            tc.verifyEqual({r.objects.name}, {'FaultBus'});
        end
    end

    methods (Static)
        function d = legacyDir()
            % 以本测试文件位置为锚点定位仓库根目录。
            % 不能用 which('swb.Schema')：装了 .mlappinstall 之后，安装副本
            % 一旦在路径上（或排在仓库 app 之前），会解析到
            % "<Apps>\SimWorkbench\+swb\Schema.m"，仓库根目录就算错。
            here = fileparts(mfilename('fullpath'));      % tests\+swbtest
            repoRoot = fileparts(fileparts(here));        % 仓库根目录
            d = fullfile(repoRoot, 'src', 'AutoCreateSldd');
            if ~isfolder(d)                                % 兜底：按 swb 包反推
                appDir = fileparts(fileparts(which('swb.Schema')));
                d = fullfile(fileparts(appDir), 'src', 'AutoCreateSldd');
            end
        end

        function out = normLines(p)
            txt = fileread(p);
            c = regexp(txt, '\r\n|\n|\r', 'split');
            keep = true(size(c));
            for k = 1:numel(c)
                keep(k) = ~contains(c{k}, '创建时间');
                c{k} = regexprep(c{k}, '\s+$', '');
            end
            out = c(keep);
        end

        function setCell(file, sheet, dataRow, header, value)
            t = swb.Workbook.readSheetTable(file, sheet);
            idx = find(strcmpi(t.headers, header), 1);
            if isempty(idx)
                error('swbtest:TestScriptBuilder:noColumn', '表 %s 不存在列 %s', sheet, header);
            end
            writecell({value}, file, 'Sheet', t.sheetName, ...
                'Range', [swbtest.TestScriptBuilder.letter(idx) num2str(t.rowNumbers(dataRow))]);
        end

        function s = letter(idx)
            s = '';
            while idx > 0
                r = mod(idx - 1, 26);
                s = [char(65 + r) s]; %#ok<AGROW>
                idx = floor((idx - 1) / 26);
            end
        end

        function rmDirQuiet(d)
            if isfolder(d)
                try
                    rmdir(d, 's');
                catch
                end
            end
        end
    end
end
