classdef TestPortExport < swbtest.SwbTestBase
    %SWBTEST.TESTPORTEXPORT swb.PortExport 测试：7 列工作簿导出、往返读回、加载状态恢复。

    properties (Constant)
        P = 'swbTPE_';
    end

    methods (Test)
        function testExportRoundTrip(tc)
            d = tc.tmpDir();
            name = [tc.P 'rt'];
            inP = tc.makePorts({'speed', 'double'; 'angle', 'single'});
            inP(2).storageClass = 'ExportedGlobal';
            inP(2).identifier = 'angle_g';
            outP = tc.makePorts({'torque', 'double'});
            tc.createPortModel(d, name, inP, outP);

            outFile = fullfile(d, 'exported_ports.xlsx');
            r = swb.PortExport.write(name, outFile);
            tc.verifyTrue(r.ok, r.errorText);
            tc.verifyEqual(r.inputCount, 2);
            tc.verifyEqual(r.outputCount, 1);
            tc.verifyTrue(isfile(outFile));
            tc.verifyTrue(strcmpi(r.file, outFile));
            tc.verifyClass(r.mappingRead, 'logical');

            % 7 列表头
            raw = readcell(outFile, 'Sheet', 'Inputs');
            tc.verifyEqual(size(raw, 2), 7);
            hdr = cellfun(@char, raw(1, :), 'UniformOutput', false);
            tc.verifyEqual(hdr, swb.Schema.PORT_COLUMNS);

            % 端口名/数据类型往返一致
            [bi, bo] = swb.PortTable.read(outFile);
            tc.verifyEqual({bi.name}, {'speed', 'angle'});
            tc.verifyEqual({bo.name}, {'torque'});
            tc.verifyEqual({bi.dataType}, {'double', 'single'});
            tc.verifyEqual({bo.dataType}, {'double'});
        end

        function testExportAddsXlsxExtension(tc)
            d = tc.tmpDir();
            name = [tc.P 'ext'];
            tc.createPortModel(d, name, tc.makePorts({'u1', 'double'}), ...
                tc.makePorts({'y1', 'double'}));
            outFile = fullfile(d, 'no_extension');
            r = swb.PortExport.write(name, outFile);
            tc.verifyTrue(r.ok, r.errorText);
            tc.verifyTrue(isfile([outFile '.xlsx']));
            tc.verifyTrue(strcmpi(r.file, [outFile '.xlsx']));
        end

        function testExportUnloadedModelRestoresState(tc)
            d = tc.tmpDir();
            name = [tc.P 'unloaded'];
            tc.createPortModel(d, name, tc.makePorts({'u1', 'double'}), ...
                tc.makePorts({'y1', 'double'}), struct('OpenAfterCreate', false));
            tc.verifyFalse(bdIsLoaded(name));
            file = fullfile(d, [name '.slx']);
            outFile = fullfile(d, 'unloaded_ports.xlsx');
            r = swb.PortExport.write(file, outFile);
            tc.verifyTrue(r.ok, r.errorText);
            tc.verifyEqual(r.inputCount, 1);
            tc.verifyFalse(bdIsLoaded(name), '导出不应改变模型的加载状态');
        end

        function testExportEmptyModel(tc)
            d = tc.tmpDir();
            name = [tc.P 'empty'];
            r0 = swb.ModelBuilder.create(struct('Name', name, 'Folder', d));
            tc.verifyTrue(r0.ok, r0.errorText);
            outFile = fullfile(d, 'empty_ports.xlsx');
            r = swb.PortExport.write(name, outFile);
            tc.verifyTrue(r.ok, r.errorText);
            tc.verifyEqual(r.inputCount, 0);
            tc.verifyEqual(r.outputCount, 0);
            tc.verifyTrue(isfile(outFile));
            tc.verifyTrue(any(contains(r.warnings, '未找到')));
        end

        function testDefaultFileNameUsesModelName(tc)
            % 导出端口的默认文件名：<模型名称>_ports.xlsx
            tc.verifyEqual(swb.PortExport.defaultFileName('myModel'), 'myModel_ports.xlsx');
            tc.verifyEqual(swb.PortExport.defaultFileName('  myModel  '), 'myModel_ports.xlsx');
            % 非法文件名字符替换成下划线，空格替换成下划线
            tc.verifyEqual(swb.PortExport.defaultFileName('a/b:c*d'), 'a_b_c_d_ports.xlsx');
            tc.verifyEqual(swb.PortExport.defaultFileName('my model'), 'my_model_ports.xlsx');
            % 空名称退回 ports.xlsx
            tc.verifyEqual(swb.PortExport.defaultFileName(''), 'ports.xlsx');
            tc.verifyEqual(swb.PortExport.defaultFileName('   '), 'ports.xlsx');
        end

        function testDefaultFileUsesFolder(tc)
            d = tc.tmpDir();
            f = swb.PortExport.defaultFile('demo', d);
            tc.verifyEqual(f, fullfile(d, 'demo_ports.xlsx'));
            tc.verifyEqual(swb.PortExport.defaultFile('demo', ''), ...
                fullfile(pwd, 'demo_ports.xlsx'));
        end

        function testExportBadArguments(tc)
            d = tc.tmpDir();
            name = [tc.P 'bad'];
            tc.createPortModel(d, name, tc.makePorts({'u1', 'double'}), ...
                tc.makePorts({'y1', 'double'}));
            goodFile = fullfile(d, 'x.xlsx');
            tc.verifyError(@() swb.PortExport.write('', goodFile), ...
                'swb:PortExport:badModelName');
            tc.verifyError(@() swb.PortExport.write('bad-name', goodFile), ...
                'swb:PortExport:badModelName');
            tc.verifyError(@() swb.PortExport.write(name, ''), ...
                'swb:PortExport:noFile');
            tc.verifyError(@() swb.PortExport.write(name, fullfile(d, 'x.txt')), ...
                'swb:PortExport:badExtension');
        end
    end
end
