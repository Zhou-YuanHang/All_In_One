classdef TestCodeMapping < swbtest.SwbTestBase
    %SWBTEST.TESTCODEMAPPING swb.CodeMapping 测试。
    %   许可策略是「先尝试、失败再降级」：apply 不得靠 available() 提前拦截。
    %   本机 license('test','Simulink_Coder'/'Embedded_Coder')=0，但 create/setInport 实际可用，
    %   因此这里断言"无许可证也能出映射并能回读"；若某天真因许可失败，只要求给出 initError。

    properties (Constant)
        P = 'swbTCM_';
    end

    methods (Test)
        function testAvailableReturnsLogicalScalar(tc)
            tf = swb.CodeMapping.available();
            tc.verifyClass(tf, 'logical');
            tc.verifySize(tf, [1 1]);
        end

        function testBlankStatsHasKnownFields(tc)
            s = swb.CodeMapping.blankStats();
            fields = {'initialized', 'initError', 'appliedInput', 'appliedOutput', ...
                      'failedInput', 'failedOutput'};
            for i = 1:numel(fields)
                tc.verifyTrue(isfield(s, fields{i}), ['缺少字段 ' fields{i}]);
            end
            tc.verifyFalse(s.initialized);
            tc.verifyEqual(s.initError, '');
            tc.verifyEqual(s.appliedInput, 0);
            tc.verifyEqual(s.failedInput, {});
        end

        function testApplyIsNotGatedByLicense(tc)
            % apply 不再有 available() 早退门禁：要么真的映射成功，要么给出 initError（绝不静默跳过）
            d = tc.tmpDir();
            name = [tc.P 'apply'];
            inP = tc.makePorts({'speed', 'double'; 'angle', 'single'});
            inP(2).storageClass = 'ExportedGlobal';
            inP(2).identifier = 'angle_g';
            outP = tc.makePorts({'torque', 'double'});
            tc.createPortModel(d, name, inP, outP);

            s = swb.CodeMapping.apply(name, inP, outP);
            tc.verifyClass(s.initialized, 'logical');
            tc.verifyClass(s.failedInput, 'cell');
            tc.verifyClass(s.failedOutput, 'cell');
            tc.verifyTrue(s.initialized || ~isempty(s.initError), ...
                'apply 不得静默跳过：要么 initialized=true，要么给出 initError');

            if ~s.initialized
                % 真因许可/环境失败时，降级信息至少要能定位原因
                tc.verifyNotEmpty(s.initError);
                tc.verifyTrue(contains(s.initError, 'Code Mapping') || ...
                    contains(s.initError, '许可'));
                return;
            end

            tc.verifyEqual(s.initError, '');
            tc.verifyEqual(s.appliedInput + numel(s.failedInput), 2);
            tc.verifyEqual(s.appliedOutput + numel(s.failedOutput), 1);
            tc.verifyEqual(numel(s.failedInput), 0, ...
                ['本机实测端口映射应全部成功；失败端口名：' strjoin(s.failedInput, ',')]);

            rows = swb.CodeMapping.read(name);
            names = {rows.name};
            tc.verifyTrue(any(strcmp(names, 'speed')));
            tc.verifyTrue(any(strcmp(names, 'torque')));
            idx = find(strcmp(names, 'angle'), 1);
            tc.verifyNotEmpty(idx);
            tc.verifyEqual(rows(idx).storageClass, 'ExportedGlobal');
            tc.verifyEqual(rows(idx).identifier, 'angle_g');
        end

        function testIgnoreLicenseOptionStillAccepted(tc)
            % IgnoreLicense 已 deprecated，但旧调用不能报错、行为与不带该 opts 时一致
            d = tc.tmpDir();
            name = [tc.P 'compat'];
            inP = tc.makePorts({'u1', 'double'});
            outP = tc.makePorts({'y1', 'double'});
            tc.createPortModel(d, name, inP, outP);

            s = swb.CodeMapping.apply(name, inP, outP, struct('IgnoreLicense', true));
            tc.verifyTrue(s.initialized || ~isempty(s.initError));
            tc.verifyClass(s.failedInput, 'cell');
            tc.verifyEqual(s.appliedInput + numel(s.failedInput), 1);
        end

        function testApplyCreateFailureReturnsKnownStructure(tc)
            % 模型不存在 → coder.mapping.utils.create 抛错，必须返回已知结构而不是向外抛
            inP = tc.makePorts({'u1', 'double'});
            outP = tc.makePorts({'y1', 'double'});
            s = swb.CodeMapping.apply([tc.P 'no_such_model'], inP, outP);
            tc.verifyFalse(s.initialized);
            tc.verifyNotEmpty(s.initError);
            tc.verifyTrue(contains(s.initError, 'Code Mapping'));
            tc.verifyClass(s.failedInput, 'cell');
            tc.verifyClass(s.failedOutput, 'cell');
            tc.verifyEqual(s.appliedInput, 0);
            tc.verifyEqual(s.appliedOutput, 0);
        end

        function testReadReturnsKnownStructure(tc)
            d = tc.tmpDir();
            name = [tc.P 'read'];
            tc.createPortModel(d, name, tc.makePorts({'u1', 'double'}), ...
                tc.makePorts({'y1', 'double'}));
            rows = swb.CodeMapping.read(name);
            tc.verifyTrue(isstruct(rows));
            if ~isempty(rows)
                fields = {'name', 'storageClass', 'identifier', 'headerFile', 'definitionFile'};
                for i = 1:numel(fields)
                    tc.verifyTrue(isfield(rows, fields{i}));
                end
            end
        end

        function testReadLoadsAndRestores(tc)
            d = tc.tmpDir();
            name = [tc.P 'readload'];
            tc.createPortModel(d, name, tc.makePorts({'u1', 'double'}), ...
                tc.makePorts({'y1', 'double'}), struct('OpenAfterCreate', false));
            tc.verifyFalse(bdIsLoaded(name));
            file = fullfile(d, [name '.slx']);
            rows = swb.CodeMapping.read(file);
            tc.verifyTrue(isstruct(rows));
            tc.verifyFalse(bdIsLoaded(name), 'read 不应改变模型的加载状态');
        end

        function testReadMissingModelReturnsEmpty(tc)
            rows = swb.CodeMapping.read([tc.P 'no_such_model']);
            tc.verifyTrue(isstruct(rows));
            tc.verifyEmpty(rows);
        end
    end
end
