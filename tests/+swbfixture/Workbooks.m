classdef Workbooks
    %SWB.FIXTURE.WORKBOOKS 测试用工作簿构造器。
    %   所有方法只写 tempdir，返回文件路径；调用方负责清理。

    methods (Static)
        function d = tempDir()
            d = tempname();
            mkdir(d);
        end

        function f = makeDict(dirPath, varargin)
            % 生成一份合法的 8 表字典工作簿；name-value: 'SignalRows',N 可加行
            p = inputParser;
            p.addParameter('SignalRows', 1);
            p.addParameter('ParameterRows', 1);
            p.parse(varargin{:});
            f = fullfile(dirPath, 'dict_sample.xlsx');
            if isfile(f), delete(f); end

            hist = [{'Version','ChangeDate','Changer','Content'}; {'V1.0','2026-01-01','test','init'}];
            sigH = swb.Schema.dictColumns('Signal');
            sig = [sigH; {'M_Sig','myPackage','Signal','ExportedGlobal','single','0', ...
                           'MCU.h','MCU.c','signal desc','0','100','m','1','real'}];
            for k = 2:p.Results.SignalRows
                sig(end+1, :) = {sprintf('M_Sig%d', k), 'myPackage', 'Signal', 'Auto', 'double', ...
                                 '0', '', '', '', '', '', '', '1', 'real'}; %#ok<AGROW>
            end
            parH = swb.Schema.dictColumns('Parameter');
            par = [parH; {'Kp','myPackage','Parameter','YS_SelectRAMPara','double','0.35', ...
                           'MCU.h','MCU.c','param desc','0','10','-','1','real'}];
            for k = 2:p.Results.ParameterRows
                par(end+1, :) = {sprintf('Kp%d', k), 'myPackage', 'Parameter', 'Auto', 'double', ...
                                 '0', '', '', '', '', '', '', '1', 'real'}; %#ok<AGROW>
            end
            constH = swb.Schema.dictColumns('Const');
            constRows = [constH; {'Mode','myPackage','Define','1','uint8','Define.h'}];
            enumH = swb.Schema.dictColumns('Enum');
            enumRows = [enumH; {'GEAR','H','0','uint8'}; {'GEAR','M','1','uint8'}];
            busH = swb.Schema.dictColumns('Bus');
            busRows = [busH; {'FaultBus','fault bus','fault.h','-1','False','Auto'}];
            beH = swb.Schema.dictColumns('BusElement');
            beRows = [beH; {'FaultBus','IcSensorFault','uint8','1','current sensor fault','-'}];

            writecell(hist, f, 'Sheet', 'History');
            writecell(sig, f, 'Sheet', 'Signal');
            writecell(par, f, 'Sheet', 'Parameter');
            writecell(constRows, f, 'Sheet', 'Const');
            writecell(enumRows, f, 'Sheet', 'Enum');
            writecell(busRows, f, 'Sheet', 'Bus');
            writecell(beRows, f, 'Sheet', 'BusElement');
            cfg = swb.Schema.defaultConfig();
            cols = swb.Schema.configColumns();
            cfgData = cell(1, numel(cols));
            for c = 1:numel(cols)
                vals = cfg.(cols(c).key);
                for r = 1:numel(vals)
                    cfgData{r, c} = vals{r};
                end
            end
            writecell([swb.Schema.CONFIG_HEADERS; cfgData], f, 'Sheet', 'Config');
        end

        function f = makePort(dirPath)
            f = fullfile(dirPath, 'ports_sample.xlsx');
            if isfile(f), delete(f); end
            [in, out] = swbfixture.Workbooks.WorkbookFixturePorts();
            swb.PortTable.write(f, in, out);
        end

        function [in, out] = WorkbookFixturePorts()
            in = [swb.Schema.blankPort(), swb.Schema.blankPort()];
            in(1).name = 'speed';   in(1).dataType = 'double'; in(1).row = 2;
            in(2).name = 'angle';   in(2).dataType = 'single'; in(2).storageClass = 'ExportedGlobal';
            in(2).identifier = 'angle_g'; in(2).row = 3;
            out = swb.Schema.blankPort();
            out(1).name = 'torque'; out.dataType = 'double'; out.row = 2;
        end

        function f = makeBadDict(dirPath)
            % 故意构造有问题的字典工作簿：缺列、必填空、重名、坏 Bus 引用、Package/CSC 不匹配
            f = fullfile(dirPath, 'dict_bad.xlsx');
            if isfile(f), delete(f); end
            sigH = {'VariableName','Package','Object'};   % 故意缺少 CustomStorageClass/DataType
            sig = [sigH; {'Dup','myPackage','Signal'}; {'Dup','myPackage','Signal'}; ...
                          {'','myPackage','Signal'}];
            writecell(sig, f, 'Sheet', 'Signal');
            parH = swb.Schema.dictColumns('Parameter');
            par = [parH; {'Dup','Simulink','Parameter','YS_SelectRAMSignal','double','1', ...
                          '', '', '', '', '', '', '1', 'real'}];
            writecell(par, f, 'Sheet', 'Parameter');
            busH = swb.Schema.dictColumns('Bus');
            bus = [busH; {'BusA','desc','h.h','-1','False','Auto'}];
            writecell(bus, f, 'Sheet', 'Bus');
            beH = swb.Schema.dictColumns('BusElement');
            be = [beH; {'MissingBus','el','uint8','1','d','-'}];
            writecell(be, f, 'Sheet', 'BusElement');
            enumH = swb.Schema.dictColumns('Enum');
            enumRows = [enumH; {'GEAR','H','0','uint8'; 'GEAR','H','1','uint8'}];
            writecell(enumRows, f, 'Sheet', 'Enum');
        end
    end
end