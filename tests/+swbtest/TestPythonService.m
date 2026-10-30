classdef TestPythonService < matlab.unittest.TestCase
    %SWB.TEST.PYTHONSERVICE Python 服务测试：探测、模板生成、helper 调用与缺失路径。
    %   本机无 Python 时相关用例用 assumeTrue 跳过，缺失路径用例始终运行。

    properties
        TempDir char
        PythonExe char
    end

    methods (TestMethodSetup)
        function createTempDir(tc)
            tc.TempDir = tempname();
            mkdir(tc.TempDir);
            tc.addTeardown(@() swbtest.TestPythonService.rmDirQuiet(tc.TempDir));
            tc.PythonExe = swbtest.TestPythonService.findPython();
        end
    end

    methods (Test)
        function testValidateRealPython(tc)
            tc.assumeTrue(~isempty(tc.PythonExe), '本机未找到 Python，跳过真实探测用例。');
            [ok, msg] = swb.PythonService.validate(tc.PythonExe);
            tc.verifyTrue(ok, sprintf('Python 探测应成功：%s', msg));
            tc.verifyNotEmpty(strtrim(msg));
        end

        function testResolveExplicitPath(tc)
            tc.assumeTrue(~isempty(tc.PythonExe), '本机未找到 Python，跳过。');
            exe = swb.PythonService.resolve(struct('PythonPath', tc.PythonExe));
            tc.verifyEqual(exe, tc.PythonExe);
        end

        function testValidateMissingExe(tc)
            fake = fullfile(tc.TempDir, 'definitely_missing_interp.exe');
            [ok, msg] = swb.PythonService.validate(fake);
            tc.verifyFalse(ok);
            tc.verifyNotEmpty(strtrim(msg));
            [ok2, msg2] = swb.PythonService.validate('');
            tc.verifyFalse(ok2);
            tc.verifyNotEmpty(strtrim(msg2));
        end

        function testGenerateTemplateEmpty(tc)
            tc.assumeTrue(~isempty(tc.PythonExe), '本机未找到 Python，跳过模板生成用例。');
            out = fullfile(tc.TempDir, 'tpl_empty.xlsx');
            r = swb.PythonService.generateTemplate(out, struct('Empty', true, 'Exe', tc.PythonExe));
            tc.verifyTrue(r.ok, sprintf('模板生成应成功：%s', r.message));
            tc.verifyTrue(isfile(out));
            sheets = cellstr(sheetnames(out));
            tc.verifyTrue(all(ismember(swb.Schema.DICT_SHEETS, sheets)), ...
                '空模板应包含全部 8 张表。');
        end

        function testGenerateTemplateWithConfig(tc)
            tc.assumeTrue(~isempty(tc.PythonExe), '本机未找到 Python，跳过模板生成用例。');
            out = fullfile(tc.TempDir, 'tpl_cfg.xlsx');
            r = swb.PythonService.generateTemplate(out, ...
                struct('Config', swb.Schema.defaultConfig(), 'Exe', tc.PythonExe));
            tc.verifyTrue(r.ok, sprintf('按 Config 生成模板应成功：%s', r.message));
            tc.verifyTrue(isfile(out));
        end

        function testGenerateTemplateWithoutPython(tc)
            out = fullfile(tc.TempDir, 'tpl_none.xlsx');
            fake = fullfile(tc.TempDir, 'no_python_interp.exe');
            r = swb.PythonService.generateTemplate(out, struct('Empty', true, 'Exe', fake));
            tc.verifyFalse(r.ok);
            tc.verifyNotEmpty(strtrim(r.message));
            tc.verifyFalse(isfile(out), '没有 Python 时不应留下模板文件。');
        end

        function testRunReverseHelperMissingJson(tc)
            r = swb.PythonService.runReverseHelper(fullfile(tc.TempDir, 'nope.json'), struct());
            tc.verifyFalse(r.ok);
            tc.verifyTrue(contains(r.message, 'JSON 文件不存在'));
        end

        function testRunReverseHelperWithoutPython(tc)
            jf = fullfile(tc.TempDir, 'payload.json');
            fid = fopen(jf, 'w');
            fwrite(fid, '{}');
            fclose(fid);
            fake = fullfile(tc.TempDir, 'no_python_interp.exe');
            r = swb.PythonService.runReverseHelper(jf, struct('Exe', fake));
            tc.verifyFalse(r.ok);
            tc.verifyNotEmpty(strtrim(r.message));
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
