classdef TestPortSync < swbtest.SwbTestBase
    %SWBTEST.TESTPORTSYNC swb.PortSync 集成测试：已有端口读取、增/删/改同步、幂等、连线告警。

    properties (Constant)
        P = 'swbTPS_';
    end

    methods (Test)
        function testExisting(tc)
            d = tc.tmpDir();
            name = [tc.P 'base'];
            inP = tc.makePorts({'speed', 'double'; 'angle', 'single'});
            outP = tc.makePorts({'torque', 'double'});
            tc.createPortModel(d, name, inP, outP);
            [ei, eo] = swb.PortSync.existing(name);
            tc.verifyEqual(sort({ei.name}), sort({'speed', 'angle'}));
            tc.verifyEqual({eo.name}, {'torque'});
            tc.verifyTrue(isfield(ei, 'dataType'));
            tc.verifyTrue(isfield(ei, 'position'));
            tc.verifyTrue(isfield(ei, 'blockPath'));
            idx = find(strcmp({ei.name}, 'angle'), 1);
            tc.verifyEqual(ei(idx).dataType, 'single');
            tc.verifyEqual(numel(ei(idx).position), 4);
            tc.verifyEqual(ei(idx).blockPath, [name '/angle']);
        end

        function testExistingLoadsAndRestores(tc)
            d = tc.tmpDir();
            name = [tc.P 'load'];
            inP = tc.makePorts({'u1', 'double'});
            outP = tc.makePorts({'y1', 'double'});
            tc.createPortModel(d, name, inP, outP, struct('OpenAfterCreate', false));
            tc.verifyFalse(bdIsLoaded(name));
            file = fullfile(d, [name '.slx']);
            [ei, eo] = swb.PortSync.existing(file);
            tc.verifyEqual({ei.name}, {'u1'});
            tc.verifyEqual({eo.name}, {'y1'});
            tc.verifyFalse(bdIsLoaded(name), 'existing 不应改变模型的加载状态');
        end

        function testApplyAddRemoveUpdate(tc)
            d = tc.tmpDir();
            name = [tc.P 'sync'];
            inP = tc.makePorts({'speed', 'double'; 'angle', 'single'});
            outP = tc.makePorts({'torque', 'double'; 'force', 'double'});
            tc.createPortModel(d, name, inP, outP);

            newIn = tc.makePorts({'speed', 'single'; 'angle', 'single'; 'temp', 'uint8'});
            newOut = tc.makePorts({'torque', 'double'; 'power', 'single'});
            st = swb.PortSync.apply(name, newIn, newOut);
            tc.verifyTrue(st.ok, st.errorText);
            tc.verifyEqual(st.added, 2);
            tc.verifyEqual(st.removed, 1);
            tc.verifyEqual(st.updated, 1);
            tc.verifyEqual(st.unchanged, 2);

            inNames = sort(getBlockNames(tc, name, 'Inport'));
            outNames = sort(getBlockNames(tc, name, 'Outport'));
            tc.verifyEqual(inNames, sort({'speed', 'angle', 'temp'}));
            tc.verifyEqual(outNames, sort({'torque', 'power'}));
            tc.verifyEqual(get_param([name '/speed'], 'OutDataTypeStr'), 'single');
            tc.verifyEqual(get_param([name '/temp'], 'OutDataTypeStr'), 'uint8');
            tc.verifyEqual(get_param([name '/power'], 'OutDataTypeStr'), 'single');
            tc.verifyEmpty(find_system(name, 'SearchDepth', 1, 'BlockType', 'Outport', ...
                'Name', 'force'));
        end

        function testApplyIdempotent(tc)
            d = tc.tmpDir();
            name = [tc.P 'idem'];
            inP = tc.makePorts({'speed', 'double'; 'angle', 'single'});
            outP = tc.makePorts({'torque', 'double'; 'force', 'double'});
            tc.createPortModel(d, name, inP, outP);
            newIn = tc.makePorts({'speed', 'single'; 'angle', 'single'; 'temp', 'uint8'});
            newOut = tc.makePorts({'torque', 'double'; 'power', 'single'});
            st1 = swb.PortSync.apply(name, newIn, newOut);
            tc.verifyTrue(st1.ok, st1.errorText);
            st2 = swb.PortSync.apply(name, newIn, newOut);
            tc.verifyTrue(st2.ok, st2.errorText);
            tc.verifyEqual(st2.added, 0);
            tc.verifyEqual(st2.removed, 0);
            tc.verifyEqual(st2.updated, 0);
            tc.verifyEqual(st2.unchanged, 5);
        end

        function testRemoveConnectedPortWarns(tc)
            d = tc.tmpDir();
            name = [tc.P 'line'];
            inP = tc.makePorts({'u1', 'double'; 'u2', 'double'});
            outP = tc.makePorts({'y1', 'double'});
            tc.createPortModel(d, name, inP, outP);
            add_block('simulink/Math Operations/Gain', [name '/g']);
            set_param([name '/g'], 'Position', [200, 80, 230, 110]);
            add_line(name, 'u2/1', 'g/1');

            st = swb.PortSync.apply(name, tc.makePorts({'u1', 'double'}), ...
                tc.makePorts({'y1', 'double'}));
            tc.verifyTrue(st.ok, st.errorText);
            tc.verifyEqual(st.removed, 1);
            tc.verifyTrue(any(contains(st.warnings, '连线')), ...
                '删除已连线端口必须在 warnings 里说明连线丢失');
            tc.verifyEmpty(find_system(name, 'SearchDepth', 1, 'BlockType', 'Inport', 'Name', 'u2'));
        end

        function testApplyOnUnloadedModelSaves(tc)
            d = tc.tmpDir();
            name = [tc.P 'unloaded'];
            inP = tc.makePorts({'u1', 'double'});
            outP = tc.makePorts({'y1', 'double'});
            tc.createPortModel(d, name, inP, outP, struct('OpenAfterCreate', false));
            tc.verifyFalse(bdIsLoaded(name));
            file = fullfile(d, [name '.slx']);

            newIn = tc.makePorts({'u1', 'double'; 'u2', 'single'});
            st = swb.PortSync.apply(file, newIn, outP);
            tc.verifyTrue(st.ok, st.errorText);
            tc.verifyEqual(st.added, 1);
            tc.verifyFalse(bdIsLoaded(name), '调用前未加载的模型，同步后应关闭');

            load_system(file);
            tc.verifyEqual(numel(find_system(name, 'SearchDepth', 1, 'BlockType', 'Inport')), 2);
            tc.verifyEqual(get_param([name '/u2'], 'OutDataTypeStr'), 'single');
        end

        function testApplyMissingModelReturnsError(tc)
            inP = tc.makePorts({'u1', 'double'});
            outP = tc.makePorts({'y1', 'double'});
            st = swb.PortSync.apply([tc.P 'no_such_model'], inP, outP);
            tc.verifyFalse(st.ok);
            tc.verifyNotEmpty(st.errorText);
            tc.verifyTrue(any(contains(st.warnings, '无法加载模型')));
        end

        function testApplyRemovesAllPorts(tc)
            d = tc.tmpDir();
            name = [tc.P 'empty'];
            inP = tc.makePorts({'u1', 'double'; 'u2', 'double'});
            outP = tc.makePorts({'y1', 'double'});
            tc.createPortModel(d, name, inP, outP);
            st = swb.PortSync.apply(name, swb.PortTable.emptyPorts(), swb.PortTable.emptyPorts());
            tc.verifyTrue(st.ok, st.errorText);
            tc.verifyEqual(st.removed, 3);
            tc.verifyEmpty(find_system(name, 'SearchDepth', 1, 'BlockType', 'Inport'));
            tc.verifyEmpty(find_system(name, 'SearchDepth', 1, 'BlockType', 'Outport'));
        end
    end
end

function names = getBlockNames(tc, modelName, blockType)
blks = find_system(modelName, 'SearchDepth', 1, 'BlockType', blockType);
names = cell(1, numel(blks));
for i = 1:numel(blks)
    names{i} = get_param(blks{i}, 'Name');
end
end
