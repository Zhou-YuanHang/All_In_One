classdef TestTemplateExport < swbtest.SwbTestBase
    %SWBTEST.TESTTEMPLATEEXPORT 导出 Excel 模板：默认文件名、MATLAB 退化模板、Python 优先路径。
    %   对应旧工具 src/AutoCreateSldd/sldd_gui.m 的「生成模板」按钮，v1.7 恢复。

    methods (Test)
        function testDefaultFileUsesDictionaryFolder(tc)
            d = tc.tmpDir();
            f = swb.TemplateExport.defaultFile(fullfile(d, 'dict.xlsx'));
            tc.verifyEqual(f, fullfile(d, 'MCU_Template.xlsx'));
        end

        function testDefaultFileFallsBackToPwd(tc)
            d = tc.tmpDir();
            old = pwd;
            tc.addTeardown(@() cd(old));
            cd(d);
            tc.verifyEqual(swb.TemplateExport.defaultFile(''), ...
                fullfile(d, 'MCU_Template.xlsx'));
            tc.verifyEqual(swb.TemplateExport.defaultFile(fullfile(d, 'missing', 'dict.xlsx')), ...
                fullfile(d, 'MCU_Template.xlsx'), ...
                '字典目录不存在时应退回当前目录');
            tc.verifyEqual(swb.TemplateExport.defaultFile(fullfile(d, 'note.txt')), ...
                fullfile(d, 'MCU_Template.xlsx'), ...
                '不是工作簿的路径应退回当前目录');
        end

        function testWriteMatlabBasicCreatesAllSchemaSheets(tc)
            out = fullfile(tc.tmpDir(), 'tpl.xlsx');
            ok = swb.TemplateExport.writeMatlabBasic(out, [], '模板导出');
            tc.verifyTrue(ok);
            tc.verifyTrue(isfile(out));
            tc.verifyEqual(reshape(cellstr(sheetnames(out)), 1, []), swb.Schema.DICT_SHEETS, ...
                '退化模板必须含 Schema 定义的 8 张表且顺序一致');
            for k = 1:numel(swb.Schema.DICT_SHEETS)
                sn = swb.Schema.DICT_SHEETS{k};
                tbl = swb.Workbook.readSheetTable(out, sn);
                tc.verifyEqual(tbl.headers, swb.Schema.dictColumns(sn), ...
                    sprintf('%s 表头应与 Schema 列序一致', sn));
            end
        end

        function testWriteMatlabBasicWritesHistoryVersionRow(tc)
            out = fullfile(tc.tmpDir(), 'tpl.xlsx');
            tc.verifyTrue(swb.TemplateExport.writeMatlabBasic(out, [], '模板导出'));
            hist = swb.Workbook.readSheetTable(out, 'History');
            tc.verifyEqual(size(hist.rows, 1), 1, 'History 应有一行版本记录');
            tc.verifyEqual(swb.Workbook.cellText(hist.rows{1, 1}), 'V1.0');
            tc.verifyEqual(swb.Workbook.cellText(hist.rows{1, 3}), 'SimWorkbench');
            tc.verifyEqual(swb.Workbook.cellText(hist.rows{1, 4}), '模板导出');
            tc.verifyEqual(swb.Workbook.cellText(hist.rows{1, 2}), ...
                char(datetime('today', 'Format', 'yyyy-MM-dd')));
        end

        function testWriteMatlabBasicWritesConfigCandidates(tc)
            out = fullfile(tc.tmpDir(), 'tpl.xlsx');
            cfg = swb.Schema.defaultConfig();
            cfg.Package = {'pkgA', 'pkgB'};
            cfg.Unit = {'V'};
            tc.verifyTrue(swb.TemplateExport.writeMatlabBasic(out, cfg, '模板导出'));
            tbl = swb.Workbook.readSheetTable(out, 'Config');
            tc.verifyEqual(tbl.headers, swb.Schema.CONFIG_HEADERS);
            expected = swb.TemplateConfig.normalize(cfg);
            keys = swb.Schema.configKeys();
            maxLen = 0;
            for k = 1:numel(keys)
                maxLen = max(maxLen, numel(expected.(keys{k})));
            end
            tc.verifyEqual(size(tbl.rows, 1), maxLen, 'Config 数据行数应取最长候选值列');
            tc.verifyEqual(swb.Workbook.cellText(tbl.rows{1, 1}), 'pkgA');
            tc.verifyEqual(swb.Workbook.cellText(tbl.rows{2, 1}), 'pkgB');
            tc.verifyEqual(swb.Workbook.cellText(tbl.rows{1, 2}), 'Signal', ...
                '未给出的列应保留内置默认候选值');
            tc.verifyEqual(swb.Workbook.cellText(tbl.rows{1, 5}), 'V');
            tc.verifyEqual(swb.Workbook.cellText(tbl.rows{2, 5}), '', ...
                'Unit 列只有 1 个候选值时其余应为空');
        end

        function testWriteMatlabBasicOverwritesExistingFile(tc)
            out = fullfile(tc.tmpDir(), 'tpl.xlsx');
            tc.verifyTrue(swb.TemplateExport.writeMatlabBasic(out, [], '第一次'));
            tc.verifyTrue(swb.TemplateExport.writeMatlabBasic(out, [], '第二次'));
            hist = swb.Workbook.readSheetTable(out, 'History');
            tc.verifyEqual(size(hist.rows, 1), 1, '重写后不应残留旧行');
            tc.verifyEqual(swb.Workbook.cellText(hist.rows{1, 4}), '第二次');
        end

        function testToWorkbookFallsBackWhenPythonUnavailable(tc)
            out = fullfile(tc.tmpDir(), 'no_python.xlsx');
            r = swb.TemplateExport.toWorkbook(out, struct( ...
                'Empty', true, 'Config', [], ...
                'Exe', fullfile(tc.tmpDir(), 'definitely_missing_python.exe'), 'Log', []));
            tc.verifyTrue(r.ok, r.message);
            tc.verifyTrue(r.usedFallback, 'Python 不可用时应标记为退化模板');
            tc.verifyEqual(r.file, out);
            tc.verifyTrue(isfile(out));
            tc.verifyEqual(reshape(cellstr(sheetnames(out)), 1, []), swb.Schema.DICT_SHEETS);
            tc.verifyNotEmpty(strtrim(r.message));
        end

        function testToWorkbookWithPythonWritesTemplate(tc)
            exe = swbtest.TestTemplateExport.findPython();
            tc.assumeTrue(~isempty(exe), '本机未找到 Python，跳过 Python 模板用例。');
            out = fullfile(tc.tmpDir(), 'py.xlsx');
            r = swb.TemplateExport.toWorkbook(out, struct( ...
                'Empty', false, 'Config', [], 'Exe', exe, 'Log', []));
            tc.verifyTrue(r.ok, r.message);
            tc.verifyFalse(r.usedFallback, '有 Python 时不应退化');
            tc.verifyTrue(isfile(out));
            tc.verifyEqual(reshape(cellstr(sheetnames(out)), 1, []), swb.Schema.DICT_SHEETS);
        end

        function testToWorkbookAppendsXlsxExtension(tc)
            d = tc.tmpDir();
            r = swb.TemplateExport.toWorkbook(fullfile(d, 'plain'), struct( ...
                'Empty', true, 'Config', [], ...
                'Exe', fullfile(d, 'definitely_missing_python.exe'), 'Log', []));
            tc.verifyTrue(r.ok, r.message);
            tc.verifyEqual(r.file, fullfile(d, 'plain.xlsx'));
            tc.verifyTrue(isfile(r.file));
        end

        function testToWorkbookRejectsEmptyAndWrongExtension(tc)
            r = swb.TemplateExport.toWorkbook('', struct());
            tc.verifyFalse(r.ok);
            tc.verifyTrue(contains(r.message, '为空'));

            d = tc.tmpDir();
            r2 = swb.TemplateExport.toWorkbook(fullfile(d, 'tpl.txt'), struct());
            tc.verifyFalse(r2.ok);
            tc.verifyTrue(contains(r2.message, '.xlsx'));
            tc.verifyFalse(isfile(fullfile(d, 'tpl.txt')));
        end

        function testTemplateExportServiceIsRegistered(tc)
            % UI 通过 hasService 探测；类必须能从 app 路径找到
            tc.verifyTrue(exist('swb.TemplateExport', 'class') == 8);
        end
    end

    methods (Static, Access = private)
        function exe = findPython()
            % 与 TestPythonService.findPython 一致：只认显式候选，不做 PATH 搜索
            exe = '';
            cands = {'D:\SoftwareInstallation\Python3147\python.exe', 'python.exe'};
            for k = 1:numel(cands)
                [ok, ~] = swb.PythonService.validate(cands{k});
                if ok
                    exe = swb.PythonService.resolve(struct('PythonPath', cands{k}));
                    return;
                end
            end
        end
    end
end
