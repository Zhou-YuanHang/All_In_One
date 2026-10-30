classdef SwbTestBase < matlab.unittest.TestCase
    %SWBTEST.SWBTESTBASE 模型侧测试基类：项目路径、临时目录、模型清理。
    %   子类用 tc.tmpDir() 创建临时目录，teardown 自动 bdclose('all') 并删除目录。

    properties (Access = protected)
        TempDirs = {}
    end

    methods (TestMethodSetup)
        function addProjectPaths(tc)
            % tests/+swbtest/SwbTestBase.m → 项目根
            root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
            tc.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(root, 'app')));
            tc.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(root, 'tests')));
        end
    end

    methods (TestMethodTeardown)
        function cleanupModelsAndDirs(tc)
            try
                bdclose('all');
            catch
            end
            dirs = tc.TempDirs;
            for i = 1:numel(dirs)
                try
                    if isfolder(dirs{i})
                        rmdir(dirs{i}, 's');
                    end
                catch
                end
            end
            tc.TempDirs = {};
        end
    end

    methods (Access = protected)
        function d = tmpDir(tc)
            % 新建唯一临时目录，测试结束时删除
            d = tempname();
            mkdir(d);
            tc.TempDirs{end+1} = d;
        end

        function p = makePorts(tc, specs)
            % specs: N×2 cellstr {name, dataType} → PortTable 端口结构数组
            p = swb.PortTable.emptyPorts();
            for i = 1:size(specs, 1)
                q = swb.Schema.blankPort();
                q.name = specs{i, 1};
                q.dataType = specs{i, 2};
                p(end+1) = q; %#ok<AGROW>
            end
        end

        function f = writePortWorkbook(tc, dirPath, fileName, inPorts, outPorts)
            % 写端口工作簿并返回路径
            f = fullfile(dirPath, fileName);
            swb.PortTable.write(f, inPorts, outPorts);
        end

        function r = createPortModel(tc, dirPath, modelName, inPorts, outPorts, extra)
            % 用端口工作簿建模型（默认保持打开），返回 ModelBuilder 结果
            if nargin < 6 || isempty(extra)
                extra = struct();
            end
            pf = tc.writePortWorkbook(dirPath, [modelName '_ports.xlsx'], inPorts, outPorts);
            opts = struct('Name', modelName, 'Folder', dirPath, 'PortWorkbook', pf, ...
                'OpenAfterCreate', true);
            fn = fieldnames(extra);
            for i = 1:numel(fn)
                opts.(fn{i}) = extra.(fn{i});
            end
            r = swb.ModelBuilder.create(opts);
            tc.assertTrue(r.ok, r.errorText);
        end
    end
end
