classdef TestValidator < matlab.unittest.TestCase
    %SWB.TEST.VALIDATOR 数据字典工作簿跨表校验测试。
    %   覆盖：合法工作簿无问题、缺列、必填空、重名、枚举成员/值重复、
    %   Bus 引用、Package/CSC 不匹配、标识符、DataType 识别与选择提示。

    properties
        TempDir char
    end

    methods (TestMethodSetup)
        function createTempDir(tc)
            tc.TempDir = tempname();
            mkdir(tc.TempDir);
            tc.addTeardown(@() swbtest.TestValidator.rmDirQuiet(tc.TempDir));
        end
    end

    methods (Test)
        function testCleanWorkbookHasNoIssues(tc)
            wb = swbfixture.Workbooks.makeDict(tc.TempDir);
            issues = swb.Validator.run(wb, {});
            tc.verifyEmpty(issues, '合法工作簿不应有任何校验问题。');
        end

        function testMissingRequiredColumns(tc)
            wb = swbfixture.Workbooks.makeBadDict(tc.TempDir);
            issues = swb.Validator.run(wb, {'Signal'});
            tc.verifyTrue(swbtest.TestValidator.hasIssue(issues, 'error', ...
                '缺少必需列 "CustomStorageClass"'), '应报告缺少 CustomStorageClass 列。');
            tc.verifyTrue(swbtest.TestValidator.hasIssue(issues, 'error', ...
                '缺少必需列 "DataType"'), '应报告缺少 DataType 列。');
            colIssue = swbtest.TestValidator.findIssue(issues, 'error', '缺少必需列 "DataType"');
            tc.verifyTrue(isnan(colIssue.row), '缺列问题的 row 应为 NaN。');
        end

        function testRequiredCellBlank(tc)
            wb = swbfixture.Workbooks.makeBadDict(tc.TempDir);
            issues = swb.Validator.run(wb, {'Signal'});
            hit = swbtest.TestValidator.findIssue(issues, 'error', '必填列 VariableName 的值为空');
            tc.verifyNotEmpty(hit, '应报告必填单元格为空。');
            tc.verifyEqual(hit.row, 4);
            tc.verifyEqual(hit.column, 'A');
        end

        function testDuplicateVariableNamesAcrossSignalAndParameter(tc)
            wb = swbfixture.Workbooks.makeBadDict(tc.TempDir);
            issues = swb.Validator.run(wb, {});
            hit = swbtest.TestValidator.findIssue(issues, 'error', '变量名 "Dup" 重复出现');
            tc.verifyNotEmpty(hit, '应报告 Signal/Parameter 跨表重名。');
            tc.verifyTrue(contains(hit.message, 'Signal 第 2 行'));
            tc.verifyTrue(contains(hit.message, 'Parameter 第 2 行'));
        end

        function testDuplicateEnumMember(tc)
            wb = swbfixture.Workbooks.makeBadDict(tc.TempDir);
            issues = swb.Validator.run(wb, {});
            tc.verifyTrue(swbtest.TestValidator.hasIssue(issues, 'error', ...
                '枚举成员 "GEAR / H" 重复出现'), '应报告枚举成员重复。');
        end

        function testMissingBusReferenceEvenWithoutBusSheet(tc)
            wb = swbfixture.Workbooks.makeBadDict(tc.TempDir);
            issues = swb.Validator.run(wb, {'BusElement'});
            tc.verifyTrue(swbtest.TestValidator.hasIssue(issues, 'error', ...
                '未定义的 Bus "MissingBus"'), '未选 Bus 表也应报告未定义引用。');
        end

        function testPackageCustomStorageClassMismatch(tc)
            wb = swbfixture.Workbooks.makeDict(tc.TempDir);
            swbtest.TestValidator.setCell(wb, 'Signal', 1, 'Package', 'Simulink');
            swbtest.TestValidator.setCell(wb, 'Signal', 1, 'CustomStorageClass', 'YS_SelectRAMPara');
            issues = swb.Validator.run(wb, {});
            tc.verifyTrue(swbtest.TestValidator.hasIssue(issues, 'error', ...
                'Package=Simulink 时不能使用自定义存储类'), ...
                'Package=Simulink + 自定义 CSC 必须报 error。');
        end

        function testBusDataTypeReference(tc)
            wb = swbfixture.Workbooks.makeDict(tc.TempDir);
            swbtest.TestValidator.setCell(wb, 'Signal', 1, 'DataType', 'Bus: NopeBus');
            issues = swb.Validator.run(wb, {});
            tc.verifyTrue(swbtest.TestValidator.hasIssue(issues, 'error', ...
                'DataType 引用了 Bus 表中未定义的 Bus "NopeBus"'), ...
                'DataType Bus: xxx 未定义应报 error。');
        end

        function testEnumDuplicateValue(tc)
            wb = swbfixture.Workbooks.makeDict(tc.TempDir);
            swbtest.TestValidator.setCell(wb, 'Enum', 2, 'Value', '0');
            issues = swb.Validator.run(wb, {});
            tc.verifyTrue(swbtest.TestValidator.hasIssue(issues, 'error', ...
                '枚举值 "GEAR = 0" 重复出现'), '同一枚举名下的值必须唯一。');
        end

        function testInvalidBusIdentifier(tc)
            wb = swbfixture.Workbooks.makeDict(tc.TempDir);
            swbtest.TestValidator.setCell(wb, 'Bus', 1, 'BusName', 'Bad Name');
            issues = swb.Validator.run(wb, {});
            tc.verifyTrue(swbtest.TestValidator.hasIssue(issues, 'error', ...
                '不是合法的 MATLAB 标识符'), 'Bus 名称必须是合法标识符。');
            tc.verifyTrue(swbtest.TestValidator.hasIssue(issues, 'error', ...
                '未定义的 Bus "FaultBus"'), '改名后 BusElement 引用应失效。');
        end

        function testBusSelectedWithoutBusElementWarns(tc)
            wb = swbfixture.Workbooks.makeDict(tc.TempDir);
            issues = swb.Validator.run(wb, {'Bus'});
            tc.verifyEmpty(issues(strcmp({issues.severity}, 'error')), '不应有 error。');
            tc.verifyTrue(swbtest.TestValidator.hasIssue(issues, 'warning', ...
                '未选择 BusElement'), '选了 Bus 未选 BusElement 应给 warning。');
        end

        function testUnknownDataTypeWarns(tc)
            wb = swbfixture.Workbooks.makeDict(tc.TempDir);
            swbtest.TestValidator.setCell(wb, 'Signal', 1, 'DataType', 'BogusType');
            issues = swb.Validator.run(wb, {});
            tc.verifyEmpty(issues(strcmp({issues.severity}, 'error')), '未知 DataType 只应 warning。');
            tc.verifyTrue(swbtest.TestValidator.hasSheetWarning(issues, 'Signal'), ...
                '未知 DataType 应给 warning。');
        end

        function testNonIntegerEnumDataTypeWarns(tc)
            wb = swbfixture.Workbooks.makeDict(tc.TempDir);
            swbtest.TestValidator.setCell(wb, 'Enum', 1, 'DataType', 'double');
            swbtest.TestValidator.setCell(wb, 'Enum', 2, 'DataType', 'double');
            issues = swb.Validator.run(wb, {});
            tc.verifyEmpty(issues(strcmp({issues.severity}, 'error')), 'Enum 非整数基类只应 warning。');
            tc.verifyTrue(swbtest.TestValidator.hasSheetWarning(issues, 'Enum'), ...
                'Enum DataType 非整数应给 warning。');
        end
    end

    methods (Static)
        function hit = findIssue(issues, severity, needle)
            hit = [];
            for k = 1:numel(issues)
                i = issues(k);
                if strcmpi(i.severity, severity) && contains(i.message, needle)
                    hit = i;
                    return;
                end
            end
        end

        function tf = hasIssue(issues, severity, needle)
            tf = ~isempty(swbtest.TestValidator.findIssue(issues, severity, needle));
        end

        function tf = hasSheetWarning(issues, sheet)
            tf = false;
            for k = 1:numel(issues)
                i = issues(k);
                if strcmpi(i.severity, 'warning') && strcmpi(i.sheet, sheet)
                    tf = true;
                    return;
                end
            end
        end

        function setCell(file, sheet, dataRow, header, value)
            t = swb.Workbook.readSheetTable(file, sheet);
            idx = find(strcmpi(t.headers, header), 1);
            if isempty(idx)
                error('swbtest:TestValidator:noColumn', '表 %s 不存在列 %s', sheet, header);
            end
            excelRow = t.rowNumbers(dataRow);
            writecell({value}, file, 'Sheet', t.sheetName, ...
                'Range', [swbtest.TestValidator.letter(idx) num2str(excelRow)]);
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
