classdef TestReverseSync < matlab.unittest.TestCase
    %SWB.TEST.REVERSESYNC 反向同步测试：临时 .sldd -> xlsx，校验表头/列序/行数，
    %   以及 Python 缺失时退化为 MATLAB 基本模板、参数非法时报错。

    properties
        TempDir char
        DictPath char
        PythonExe char
    end

    methods (TestMethodSetup)
        function createFixture(tc)
            tc.TempDir = tempname();
            mkdir(tc.TempDir);
            tc.addTeardown(@() swbtest.TestReverseSync.rmDirQuiet(tc.TempDir));
            tc.PythonExe = swbtest.TestReverseSync.findPython();

            wb = swbfixture.Workbooks.makeDict(tc.TempDir);
            build = swb.ScriptBuilder.build(wb, {}, fullfile(tc.TempDir, 'objects.m'));
            tc.assertEqual(build.ok, true);
            tc.DictPath = fullfile(tc.TempDir, 'roundtrip.sldd');
            stats = swb.Dictionary.writeScript(tc.DictPath, build.text, struct());
            tc.assertEqual(stats.ok, true, sprintf('准备测试字典失败：%s', stats.errorText));
        end
    end

    methods (Test)
        function testRoundTripNewWorkbook(tc)
            tc.assumeTrue(~isempty(tc.PythonExe), '本机未找到 Python，跳过 Excel 回写用例。');
            xlsx = fullfile(tc.TempDir, 'roundtrip.xlsx');
            res = swb.ReverseSync.toWorkbook(tc.DictPath, xlsx, struct('Exe', tc.PythonExe));
            tc.verifyTrue(res.ok, sprintf('反向同步应成功：%s', res.errorText));
            tc.verifyTrue(res.workbookCreated);
            tc.verifyTrue(isfile(xlsx));

            tc.verifyEqual(res.rows.Signal, 1);
            tc.verifyEqual(res.rows.Parameter, 1);
            tc.verifyEqual(res.rows.Const, 1);
            tc.verifyEqual(res.rows.Bus, 1);
            tc.verifyEqual(res.rows.BusElement, 1);
            tc.verifyEqual(res.rows.Enum, 2);

            sheets = cellstr(sheetnames(xlsx));
            tc.verifyTrue(all(ismember(swb.Schema.DICT_SHEETS, sheets)), ...
                '目标工作簿应包含全部 8 张表。');

            dataSheets = {'Signal', 'Parameter', 'Const', 'Enum', 'Bus', 'BusElement'};
            expected = [1 1 1 2 1 1];
            for k = 1:numel(dataSheets)
                sn = dataSheets{k};
                t = swb.Workbook.readSheetTable(xlsx, sn);
                cols = swb.Schema.dictColumns(sn);
                m = swb.Schema.matchColumns(t.headers, cols);
                tc.verifyTrue(all(m > 0), sprintf('%s 表头列序不完整。', sn));
                tc.verifyEqual(swbtest.TestReverseSync.nonBlankRows(t), expected(k), ...
                    sprintf('%s 表非空行数不符。', sn));
            end

            % 关键内容抽查：Signal 名称、Bus 元素、枚举成员
            ts = swb.Workbook.readSheetTable(xlsx, 'Signal');
            tc.verifyTrue(any(strcmp(swbtest.TestReverseSync.flatten(ts.rows(:, 1)), 'M_Sig')));
            tb = swb.Workbook.readSheetTable(xlsx, 'Bus');
            tc.verifyTrue(any(strcmp(swbtest.TestReverseSync.flatten(tb.rows(:, 1)), 'FaultBus')));
            te = swb.Workbook.readSheetTable(xlsx, 'Enum');
            members = swbtest.TestReverseSync.flatten(te.rows(:, 2));
            tc.verifyTrue(all(ismember({'H', 'M'}, members)), 'Enum 表应含 H/M 成员。');
        end

        function testExistingWorkbookNotRecreated(tc)
            tc.assumeTrue(~isempty(tc.PythonExe), '本机未找到 Python，跳过。');
            xlsx = fullfile(tc.TempDir, 'roundtrip.xlsx');
            res1 = swb.ReverseSync.toWorkbook(tc.DictPath, xlsx, struct('Exe', tc.PythonExe));
            tc.verifyTrue(res1.ok);
            res2 = swb.ReverseSync.toWorkbook(tc.DictPath, xlsx, struct('Exe', tc.PythonExe));
            tc.verifyTrue(res2.ok, sprintf('对已存在工作簿回写应成功：%s', res2.errorText));
            tc.verifyFalse(res2.workbookCreated);
        end

        function testFallsBackToMatlabTemplateWithoutPython(tc)
            xlsx = fullfile(tc.TempDir, 'fallback.xlsx');
            fake = fullfile(tc.TempDir, 'no_python_interp.exe');
            res = swb.ReverseSync.toWorkbook(tc.DictPath, xlsx, struct('Exe', fake));
            tc.verifyFalse(res.ok, '没有 Python 时 ok 应为 false。');
            tc.verifyTrue(res.workbookCreated, '应退化为 MATLAB 基本模板并创建文件。');
            tc.verifyTrue(isfile(xlsx));
            tc.verifyTrue(contains(res.errorText, 'Python'), ...
                sprintf('errorText 应说明缺少 Python，实际：%s', res.errorText));
            tc.verifyNotEmpty(res.messages);
            sheets = cellstr(sheetnames(xlsx));
            tc.verifyTrue(all(ismember(swb.Schema.DICT_SHEETS, sheets)), ...
                'MATLAB 基本模板也应包含 8 张表。');
        end

        function testMissingDictErrors(tc)
            tc.verifyError(@() swb.ReverseSync.toWorkbook( ...
                fullfile(tc.TempDir, 'nope.sldd'), fullfile(tc.TempDir, 'x.xlsx')), ...
                'swb:ReverseSync:missingDict');
            % v1.7.2 起 Excel 路径为空不再是错误：自动导出为与 .sldd 同目录同名 .xlsx
            res = swb.ReverseSync.toWorkbook(tc.DictPath, '');
            tc.verifyTrue(res.ok, res.errorText);
            tc.verifyEqual(res.workbookPath, fullfile(tc.TempDir, 'roundtrip.xlsx'));
            tc.verifyTrue(isfile(res.workbookPath));
        end
    end

    methods (Static)
        function exe = findPython()
            exe = '';
            try
                exe = swb.PythonService.resolve(swb.Settings());
            catch
                exe = '';
            end
            if ~isempty(exe)
                return;
            end
            cands = {'D:\SoftwareInstallation\Python3147\python.exe', 'python.exe'};
            for k = 1:numel(cands)
                [ok, ~] = swb.PythonService.validate(cands{k});
                if ok
                    exe = swb.PythonService.resolve(struct('PythonPath', cands{k}));
                    return;
                end
            end
        end

        function n = nonBlankRows(t)
            n = 0;
            for i = 1:size(t.rows, 1)
                blank = true;
                for j = 1:size(t.rows, 2)
                    if ~swbtest.TestReverseSync.isBlankCell(t.rows{i, j})
                        blank = false;
                        break;
                    end
                end
                if ~blank
                    n = n + 1;
                end
            end
        end

        function tf = isBlankCell(c)
            try
                s = strtrim(string(c));
                tf = all(strlength(s) == 0);
            catch
                tf = isempty(c);
            end
        end

        function out = flatten(col)
            out = {};
            for k = 1:numel(col)
                s = strtrim(string(col{k}));
                if strlength(s) > 0 && ~isequal(s, "<missing>")
                    out{end+1, 1} = char(s); %#ok<AGROW>
                end
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
