classdef TestModelCatalog < swbtest.SwbTestBase
    %SWBTEST.TESTMODELCATALOG swb.ModelCatalog 测试：已打开模型 / 目录文件 / 名称解析。
    %   「模型与端口」页的模型名称下拉靠它列出「既可以手写、也可以选现有」的候选。

    properties (Constant)
        P = 'swbMC_';
    end

    methods (Test)
        function testListsFilesInFolder(tc)
            d = tc.tmpDir();
            name = [tc.P 'folder'];
            tc.createPortModel(d, name, tc.makePorts({'u1', 'double'}), ...
                tc.makePorts({'y1', 'double'}), struct('OpenAfterCreate', false));
            bdclose('all');

            items = swb.ModelCatalog.list(d);
            idx = find(strcmp({items.name}, name), 1);
            tc.assertNotEmpty(idx, '目录里的 .slx 应出现在候选清单中');
            tc.verifyEqual(items(idx).source, 'file');
            tc.verifyTrue(strcmpi(items(idx).folder, d));
            tc.verifyTrue(isfile(items(idx).file));
            tc.verifyFalse(items(idx).loaded);
        end

        function testListsLoadedModelWithRealFolder(tc)
            d = tc.tmpDir();
            name = [tc.P 'loaded'];
            tc.createPortModel(d, name, tc.makePorts({'u1', 'double'}), ...
                tc.makePorts({'y1', 'double'}));
            tc.verifyTrue(bdIsLoaded(name));

            items = swb.ModelCatalog.list(pwd);   % 保存目录故意不是模型目录
            idx = find(strcmp({items.name}, name), 1);
            tc.assertNotEmpty(idx, '已打开的模型应在候选清单里，即使它不在保存目录');
            tc.verifyTrue(items(idx).loaded);
            tc.verifyEqual(items(idx).source, 'loaded');
            tc.verifyTrue(strcmpi(items(idx).folder, d), '已打开模型应带真实文件目录');
        end

        function testNamesAreSortedAndUnique(tc)
            d = tc.tmpDir();
            a = [tc.P 'a'];
            b = [tc.P 'b'];
            tc.createPortModel(d, a, tc.makePorts({'u1', 'double'}), tc.makePorts({'y1', 'double'}));
            tc.createPortModel(d, b, tc.makePorts({'u2', 'double'}), tc.makePorts({'y2', 'double'}));
            names = swb.ModelCatalog.names(d);
            tc.verifyEqual(numel(names), numel(unique(names)), '候选名称不应重复');
            tc.verifyEqual(names, sort(names), '候选名称应按名称排序');
            tc.verifyTrue(any(strcmp(names, a)) && any(strcmp(names, b)));
        end

        function testLibrariesAreExcluded(tc)
            lib = [tc.P 'lib'];
            new_system(lib, 'Library');
            tc.addTeardown(@() bdclose(lib));
            items = swb.ModelCatalog.list(pwd);
            tc.verifyFalse(any(strcmp({items.name}, lib)), '库文件不应出现在模型候选里');
        end

        function testInvalidFileNamesAreIgnored(tc)
            d = tc.tmpDir();
            name = [tc.P 'src'];
            tc.createPortModel(d, name, tc.makePorts({'u1', 'double'}), ...
                tc.makePorts({'y1', 'double'}), struct('OpenAfterCreate', false));
            bdclose('all');
            % 文件名带 '-' 不是合法模型标识符，不能作为模型名候选
            copyfile(fullfile(d, [name '.slx']), fullfile(d, [name '-bad.slx']));
            names = swb.ModelCatalog.names(d);
            tc.verifyTrue(any(strcmp(names, name)));
            tc.verifyFalse(any(strcmp(names, [name '-bad'])), '非法标识符的文件名应被过滤');
        end

        function testFindByNameResolvesLoadedAndFile(tc)
            d = tc.tmpDir();
            loadedName = [tc.P 'findLoaded'];
            tc.createPortModel(d, loadedName, tc.makePorts({'u1', 'double'}), ...
                tc.makePorts({'y1', 'double'}));
            info = swb.ModelCatalog.findByName(loadedName);
            tc.assertNotEmpty(info);
            tc.verifyTrue(info.loaded);
            tc.verifyTrue(strcmpi(info.folder, d));

            % 名称不存在 / 非法时返回 []
            tc.verifyEmpty(swb.ModelCatalog.findByName([tc.P 'nope']));
            tc.verifyEmpty(swb.ModelCatalog.findByName('1bad'));
        end

        function testFindByNameUsesSearchPath(tc)
            d = tc.tmpDir();
            name = [tc.P 'onpath'];
            tc.createPortModel(d, name, tc.makePorts({'u1', 'double'}), ...
                tc.makePorts({'y1', 'double'}), struct('OpenAfterCreate', false));
            bdclose('all');
            tc.applyFixture(matlab.unittest.fixtures.PathFixture(d));
            info = swb.ModelCatalog.findByName(name);
            tc.assertNotEmpty(info);
            tc.verifyFalse(info.loaded);
            tc.verifyTrue(strcmpi(info.folder, d));
            tc.verifyTrue(swb.ModelCatalog.isFileBacked(info));
        end

        function testEmptyFolderReturnsListWithoutError(tc)
            items = swb.ModelCatalog.list(fullfile(tempdir(), 'swb_no_such_dir_xyz'));
            tc.verifyTrue(isstruct(items));
            tc.verifyTrue(isempty(items) || isfield(items, 'name'));
        end
    end
end
