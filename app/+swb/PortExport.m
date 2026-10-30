classdef PortExport
    %SWB.PORTEXPORT 把模型顶层端口（含 Code Mapping 列）导出为 7 列端口工作簿。
    %   迁移旧 NewModelApp.exportPortsToExcel：getExistingPorts + CodeMapping.read →
    %   复用 swb.PortTable.write 写 Inputs/Outputs（自动清理多余 Sheet1）。
    %   模型未加载时临时加载，导出后恢复原状态。
    %
    %   modelName 可以是模型名（已加载或在搜索路径上），也可以是 .slx/.mdl 文件全路径。
    %
    %   result = swb.PortExport.write(modelName, outFile, opts)
    %   result 字段：ok, inputCount, outputCount, mappingRead(bool), file, warnings, errorText

    methods (Static)
        function result = write(modelName, outFile, opts)
            result = struct('ok', false, 'inputCount', 0, 'outputCount', 0, ...
                            'mappingRead', false, 'file', '', ...
                            'warnings', {{}}, 'errorText', '');
            if nargin < 3 || isempty(opts)
                opts = struct();
            end
            if ~isfield(opts, 'Log'), opts.Log = []; end

            [modelName, modelFile] = swb.PortExport.resolveModelRef(modelName);
            if isempty(modelName) || ~isvarname(modelName)
                error('swb:PortExport:badModelName', ...
                    '模型名称 "%s" 不是合法的 MATLAB 标识符。', modelName);
            end
            outFile = strtrim(char(outFile));
            if isempty(outFile)
                error('swb:PortExport:noFile', '导出文件路径不能为空。');
            end
            [outDir, outName, outExt] = fileparts(outFile);
            if isempty(outExt)
                outExt = '.xlsx';
            end
            if ~any(strcmpi(outExt, {'.xlsx', '.xls'}))
                error('swb:PortExport:badExtension', ...
                    '导出文件必须是 .xlsx/.xls，收到 "%s"。', outExt);
            end
            outFile = fullfile(outDir, [outName outExt]);

            wasLoaded = bdIsLoaded(modelName);
            if ~wasLoaded
                try
                    if isempty(modelFile)
                        load_system(modelName);
                    else
                        load_system(modelFile);
                    end
                catch ME
                    result.errorText = sprintf('无法加载模型 "%s": %s', modelName, ME.message);
                    result.warnings{end+1} = result.errorText;
                    return;
                end
            end

            try
                [inPorts, outPorts] = swb.PortSync.existing(modelName);
                result.inputCount = numel(inPorts);
                result.outputCount = numel(outPorts);

                % Code Mapping 读取失败/无许可时降级为只导出端口列
                cmRows = swb.CodeMapping.emptyRows();
                try
                    cmRows = swb.CodeMapping.read(modelName);
                catch
                    cmRows = swb.CodeMapping.emptyRows();
                end
                result.mappingRead = ~isempty(cmRows);

                inTable = swb.PortExport.toTablePorts(inPorts, cmRows);
                outTable = swb.PortExport.toTablePorts(outPorts, cmRows);

                if ~isempty(outDir) && ~isfolder(outDir)
                    mkdir(outDir);
                end
                swb.PortTable.write(outFile, inTable, outTable);
                result.file = outFile;
                result.ok = true;

                if result.inputCount == 0 && result.outputCount == 0
                    result.warnings{end+1} = '模型中未找到任何顶层 Inport/Outport 端口。';
                end
            catch ME
                result.ok = false;
                result.errorText = sprintf('导出端口失败: %s', ME.message);
                result.warnings{end+1} = result.errorText;
            end

            if ~wasLoaded && bdIsLoaded(modelName)
                try
                    close_system(modelName, 0);
                catch
                end
            end
            if isfield(opts, 'Log') && ~isempty(opts.Log) && result.ok
                opts.Log.info('端口已导出到 "%s"：%d 输入 / %d 输出。', ...
                    result.file, result.inputCount, result.outputCount);
            end
        end
    end

    methods (Static, Access = private)
        function [modelName, modelFile] = resolveModelRef(ref)
            % 接受模型名或 .slx/.mdl 文件路径（设计文档风险 #8：其它目录的模型）
            ref = strtrim(char(ref));
            modelName = ref;
            modelFile = '';
            if isempty(ref)
                return;
            end
            [~, base, ext] = fileparts(ref);
            if any(strcmpi(ext, {'.slx', '.mdl'}))
                modelName = strtrim(base);
                modelFile = ref;
            end
        end

        function ports = toTablePorts(existPorts, cmRows)
            % 模型端口 + Code Mapping → PortTable 写盘结构
            ports = swb.PortTable.emptyPorts();
            for i = 1:numel(existPorts)
                p = swb.Schema.blankPort();
                p.name = existPorts(i).name;
                p.dataType = existPorts(i).dataType;
                p.row = i + 1;
                idx = [];
                if ~isempty(cmRows)
                    idx = find(strcmp({cmRows.name}, p.name), 1);
                end
                if ~isempty(idx)
                    p.storageClass = cmRows(idx).storageClass;
                    p.identifier = cmRows(idx).identifier;
                    p.headerFile = cmRows(idx).headerFile;
                    p.definitionFile = cmRows(idx).definitionFile;
                end
                ports(end+1) = p; %#ok<AGROW>
            end
        end
    end
end
