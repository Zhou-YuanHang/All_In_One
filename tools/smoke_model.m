function smoke_model()
%SWB 模型侧服务冒烟：ModelBuilder / PortSync / PortExport / CodeMapping。
%   用法：matlab -batch "addpath('tools'); smoke_model"
root = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(root, 'app'));
tmp = tempname();
mkdir(tmp);
cleanup = onCleanup(@() smoke_cleanup(tmp)); %#ok<NASGU>
fprintf('SMOKE_ROOT=%s\nSMOKE_TMP=%s\n', root, tmp);
fprintf('CM_AVAILABLE=%d\n', swb.CodeMapping.available());

%% 1. 端口工作簿
pf = fullfile(tmp, 'ports.xlsx');
inP = [swb.Schema.blankPort(), swb.Schema.blankPort()];
inP(1).name = 'speed'; inP(1).dataType = 'double';
inP(2).name = 'angle'; inP(2).dataType = 'single';
inP(2).storageClass = 'ExportedGlobal'; inP(2).identifier = 'angle_g';
outP = swb.Schema.blankPort();
outP.name = 'torque'; outP.dataType = 'double';
swb.PortTable.write(pf, inP, outP);
fprintf('SECTION1 ports workbook exists=%d\n', isfile(pf));

%% 2. 连续模型 + 端口 + 保存
r1 = struct('ok', false);
try
    r1 = swb.ModelBuilder.create(struct('Name', 'smk_cont', 'Folder', tmp, ...
        'SolverType', 'Continuous', 'PortWorkbook', pf, 'OpenAfterCreate', true));
    fprintf('SECTION2 create-cont ok=%d in=%d out=%d path=%s\n', ...
        r1.ok, r1.inputCount, r1.outputCount, r1.modelPath);
    fprintf('  solverType=%s solver=%s stf=%s genOnly=%s\n', ...
        get_param('smk_cont', 'SolverType'), get_param('smk_cont', 'Solver'), ...
        get_param('smk_cont', 'SystemTargetFile'), get_param('smk_cont', 'GenCodeOnly'));
    fprintf('  loaded=%d file=%d bakDirOk=1\n', bdIsLoaded('smk_cont'), ...
        isfile(fullfile(tmp, 'smk_cont.slx')));
    fprintf('  dtypes speed=%s angle=%s torque=%s\n', ...
        get_param('smk_cont/speed', 'OutDataTypeStr'), ...
        get_param('smk_cont/angle', 'OutDataTypeStr'), ...
        get_param('smk_cont/torque', 'OutDataTypeStr'));
    fprintf('  mapping.initialized=%d initError=%s\n', ...
        r1.mapping.initialized, r1.mapping.initError);
    for i = 1:numel(r1.warnings)
        fprintf('  WARN: %s\n', r1.warnings{i});
    end
catch ME
    fprintf('SECTION2 FAIL: %s\n', ME.message);
end

%% 3. 离散模型
try
    r2 = swb.ModelBuilder.create(struct('Name', 'smk_disc', 'Folder', tmp, ...
        'SolverType', 'Discrete', 'SampleTime', '0.02', 'OpenAfterCreate', true));
    fprintf('SECTION3 create-disc ok=%d solverType=%s solver=%s step=%s\n', ...
        r2.ok, get_param('smk_disc', 'SolverType'), get_param('smk_disc', 'Solver'), ...
        get_param('smk_disc', 'FixedStep'));
    close_system('smk_disc', 0);
catch ME
    fprintf('SECTION3 FAIL: %s\n', ME.message);
end

%% 4. CodeMapping：许可降级 + IgnoreLicense 实验
try
    s1 = swb.CodeMapping.apply('smk_cont', inP, outP);
    fprintf('SECTION4a apply init=%d appliedIn=%d appliedOut=%d failedIn=%d failedOut=%d\n', ...
        s1.initialized, s1.appliedInput, s1.appliedOutput, numel(s1.failedInput), numel(s1.failedOutput));
    fprintf('  initError=%s\n', s1.initError);
    s2 = swb.CodeMapping.apply('smk_cont', inP, outP, struct('IgnoreLicense', true));
    fprintf('SECTION4b apply-ignore init=%d appliedIn=%d appliedOut=%d failedIn=%s\n', ...
        s2.initialized, s2.appliedInput, s2.appliedOutput, strjoin(s2.failedInput, ','));
    fprintf('  initError=%s\n', s2.initError);
    rows = swb.CodeMapping.read('smk_cont');
    fprintf('SECTION4c read rows=%d\n', numel(rows));
    for i = 1:numel(rows)
        fprintf('  row %s sc=%s id=%s\n', rows(i).name, rows(i).storageClass, rows(i).identifier);
    end
catch ME
    fprintf('SECTION4 FAIL: %s\n', ME.message);
end

%% 5. PortSync：existing + apply + 幂等
try
    [ei, eo] = swb.PortSync.existing('smk_cont');
    fprintf('SECTION5a existing in=%s out=%s\n', ...
        strjoin({ei.name}, ','), strjoin({eo.name}, ','));
    newIn = [swb.Schema.blankPort(), swb.Schema.blankPort(), swb.Schema.blankPort()];
    newIn(1).name = 'speed'; newIn(1).dataType = 'single';
    newIn(2).name = 'angle'; newIn(2).dataType = 'single';
    newIn(3).name = 'temp';  newIn(3).dataType = 'uint8';
    newOut = [swb.Schema.blankPort(), swb.Schema.blankPort()];
    newOut(1).name = 'torque'; newOut(1).dataType = 'double';
    newOut(2).name = 'power';  newOut(2).dataType = 'single';
    st = swb.PortSync.apply('smk_cont', newIn, newOut);
    fprintf('SECTION5b apply ok=%d +%d -%d ~%d =%d\n', st.ok, st.added, st.removed, st.updated, st.unchanged);
    fprintf('  speed dt=%s temp dt=%s power dt=%s\n', ...
        get_param('smk_cont/speed', 'OutDataTypeStr'), ...
        get_param('smk_cont/temp', 'OutDataTypeStr'), ...
        get_param('smk_cont/power', 'OutDataTypeStr'));
    st2 = swb.PortSync.apply('smk_cont', newIn, newOut);
    fprintf('SECTION5c idempotent +%d -%d ~%d =%d\n', st2.added, st2.removed, st2.updated, st2.unchanged);
    for i = 1:numel(st.warnings)
        fprintf('  WARN: %s\n', st.warnings{i});
    end
catch ME
    fprintf('SECTION5 FAIL: %s\n', ME.message);
end

%% 6. PortExport
try
    of = fullfile(tmp, 'out_ports.xlsx');
    pr = swb.PortExport.write('smk_cont', of);
    fprintf('SECTION6 export ok=%d in=%d out=%d mappingRead=%d file=%d\n', ...
        pr.ok, pr.inputCount, pr.outputCount, pr.mappingRead, isfile(of));
    [bi, bo] = swb.PortTable.read(of);
    fprintf('  readback in=%s out=%s\n', strjoin({bi.name}, ','), strjoin({bo.name}, ','));
    fprintf('  readback dt=%s\n', strjoin({bi.dataType}, ','));
catch ME
    fprintf('SECTION6 FAIL: %s\n', ME.message);
end

%% 7. 冲突策略：suffix / overwrite(+bak) / cancel / ask
try
    rs = swb.ModelBuilder.create(struct('Name', 'smk_cont', 'Folder', tmp, ...
        'ConflictPolicy', 'suffix', 'OpenAfterCreate', false));
    fprintf('SECTION7a suffix ok=%d name=%s file=%d\n', rs.ok, rs.modelName, ...
        isfile(fullfile(tmp, [rs.modelName '.slx'])));
    ro = swb.ModelBuilder.create(struct('Name', 'smk_cont', 'Folder', tmp, ...
        'ConflictPolicy', 'overwrite', 'OpenAfterCreate', false));
    fprintf('SECTION7b overwrite ok=%d bak=%d\n', ro.ok, isfile(fullfile(tmp, 'smk_cont.slx.bak')));
    rc = swb.ModelBuilder.create(struct('Name', 'smk_cont', 'Folder', tmp, ...
        'ConflictPolicy', 'cancel'));
    fprintf('SECTION7c cancel ok=%d cancelled=%d err=%s\n', rc.ok, rc.cancelled, rc.errorText);
    askFcn = @(kind, msg, options, def) 2; %#ok<INUSD>
    ra = swb.ModelBuilder.create(struct('Name', 'smk_cont', 'Folder', tmp, ...
        'ConflictPolicy', 'ask', 'AskFcn', askFcn, 'OpenAfterCreate', false));
    fprintf('SECTION7d ask-suffix ok=%d name=%s\n', ra.ok, ra.modelName);
catch ME
    fprintf('SECTION7 FAIL: %s\n', ME.message);
end

%% 8. 数据字典关联（同目录 + 跨目录绝对路径）
try
    dictFile = fullfile(tmp, 'smk_dict.sldd');
    d = Simulink.data.dictionary.create(dictFile);
    d.close();
    clear d;
    rd = swb.ModelBuilder.create(struct('Name', 'smk_dict', 'Folder', tmp, ...
        'DictFile', 'smk_dict.sldd', 'OpenAfterCreate', true));
    fprintf('SECTION8a dict ok=%d param=%s dictFile=%s\n', rd.ok, ...
        get_param('smk_dict', 'DataDictionary'), rd.dictFile);
    close_system('smk_dict', 0);
    sub = fullfile(tmp, 'dicts');
    mkdir(sub);
    dict2 = fullfile(sub, 'sub_dict.sldd');
    d2 = Simulink.data.dictionary.create(dict2);
    d2.close();
    clear d2;
    rd2 = swb.ModelBuilder.create(struct('Name', 'smk_dict2', 'Folder', tmp, ...
        'DictFile', dict2, 'OpenAfterCreate', true));
    fprintf('SECTION8b crossdict ok=%d param=%s\n', rd2.ok, get_param('smk_dict2', 'DataDictionary'));
    for i = 1:numel(rd2.warnings)
        fprintf('  WARN: %s\n', rd2.warnings{i});
    end
    close_system('smk_dict2', 0);
catch ME
    fprintf('SECTION8 FAIL: %s\n', ME.message);
end

%% 9. configure
try
    % 说明：模型在 configure 前未加载 -> configure 内部加载配置后会自动关闭。
    rcfg = swb.ModelBuilder.configure('smk_cont', struct('SolverType', 'Discrete', ...
        'SampleTime', '0.05', 'GenCodeOnly', true, 'SystemTargetFile', 'ert.tlc', 'Folder', tmp));
    fprintf('SECTION9 configure ok=%d loadedAfter=%d\n', rcfg.ok, bdIsLoaded('smk_cont'));
    if ~isempty(rcfg.errorText)
        fprintf('  err=%s\n', rcfg.errorText);
    end
    load_system(fullfile(tmp, 'smk_cont.slx'));
    fprintf('  solverType=%s step=%s genOnly=%s stf=%s\n', ...
        get_param('smk_cont', 'SolverType'), get_param('smk_cont', 'FixedStep'), ...
        get_param('smk_cont', 'GenCodeOnly'), get_param('smk_cont', 'SystemTargetFile'));
    close_system('smk_cont', 0);
catch ME
    fprintf('SECTION9 FAIL: %s\n', ME.message);
end

%% 10. 清理
bdclose('all');
fprintf('SMOKE_MODEL_DONE\n');
end

function smoke_cleanup(tmp)
bdclose('all');
% 跨目录数据字典会把字典目录加到搜索路径上（模型重开时需要），
% 清理临时目录前先撤销这些路径，避免 MATLAB 报"删除路径"警告。
try
    rmpath(fullfile(tmp, 'dicts'));
catch
end
try
    if isfolder(tmp)
        rmdir(tmp, 's');
    end
catch
end
end
