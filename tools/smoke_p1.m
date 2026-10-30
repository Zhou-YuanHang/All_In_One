function smoke_p1()
% P1 基础层冒烟测试：Schema / Log / Settings / Workbook / PortTable
addpath('F:\GithubRepos\All_In_One\app');
fprintf('\n== Schema ==\n');
sp = swb.Schema.dictSheetSpec('Signal');
fprintf('Signal cols=%d required=%s importable=%d\n', numel(sp.columns), mat2str(sp.required), sp.importable);
fprintf('importable=%s\n', strjoin(swb.Schema.importableSheetNames(), ','));
fprintf('cfg keys=%s\n', strjoin(swb.Schema.configKeys(), ','));
fprintf('csc count=%d memsec=%d\n', numel(swb.Schema.customStorageClasses()), numel(swb.Schema.memorySections()));

fprintf('\n== Log ==\n');
log = swb.Log();
log.info('hello %d', 1);
log.warn('warn');
log.progress(0.5, 'half');
fprintf('entries=%d text=%s\n', numel(log.Entries), strrep(log.text(), newline, ' | '));

fprintf('\n== Settings ==\n');
sf = fullfile(tempdir, 'swb_smoke_settings.json');
if isfile(sf), delete(sf); end
st = swb.Settings(sf);
st.PythonPath = 'C:\Python\python.exe';
st.TemplateConfig.Package = {'myPackage'};
st.save();
st2 = swb.Settings(sf);
fprintf('settings roundtrip python=%s pkg=%s\n', st2.PythonPath, strjoin(st2.TemplateConfig.Package, ','));

fprintf('\n== PortTable ==\n');
portFile = fullfile(tempdir, 'swb_smoke_ports.xlsx');
if isfile(portFile), delete(portFile); end
inP = struct('name', {'speed','angle'}, 'dataType', {'double','single'}, ...
             'storageClass', {'', 'ExportedGlobal'}, 'identifier', {'','speed_g'}, ...
             'headerFile', {'','h.h'}, 'definitionFile', {'','d.c'}, 'row', {2,3});
outP = struct('name', {'y'}, 'dataType', {''}, 'storageClass', {''}, ...
              'identifier', {''}, 'headerFile', {''}, 'definitionFile', {''}, 'row', {2});
swb.PortTable.write(portFile, inP, outP);
[ip, op, pinfo] = swb.PortTable.read(portFile);
fprintf('read ports in=%d out=%d mode=%s sheets=%s/%s\n', numel(ip), numel(op), pinfo.mode, pinfo.inputSheet, pinfo.outputSheet);
for k = 1:numel(ip)
    fprintf('  IN %s type=%s sc=%s id=%s row=%d\n', ip(k).name, ip(k).dataType, ip(k).storageClass, ip(k).identifier, ip(k).row);
end
iss = swb.PortTable.validate([ip, struct('name','speed','dataType','','storageClass','','identifier','','headerFile','','definitionFile','','row',9)], op);
fprintf('port issues=%d: %s\n', numel(iss), swb.Issue.format(iss));

fprintf('\n== Workbook (dict) ==\n');
dictFile = fullfile(tempdir, 'swb_smoke_dict.xlsx');
if isfile(dictFile), delete(dictFile); end
writecell({'VariableName','Package','Object','CustomStorageClass','DataType','InitialValue'}, dictFile, 'Sheet', 'Signal');
writecell({'M_Sig','myPackage','Signal','ExportedGlobal','single','0'}, dictFile, 'Sheet', 'Signal', 'Range', 'A2');
writecell({'BusName','Description','HeaderFile','Alignment','PreserveElementDimensions','DataScope'}, dictFile, 'Sheet', 'Bus');
writecell({'FaultBus','desc','fault.h','-1','False','Auto'}, dictFile, 'Sheet', 'Bus', 'Range', 'A2');
info = swb.Workbook.detect(dictFile);
fprintf('detect exists=%d dict=%d sheets=%s\n', info.exists, info.hasDict, strjoin(info.dictSheets, ','));
t = swb.Workbook.readSheetTable(dictFile, 'Signal');
fprintf('Signal headers=%s\n', strjoin(t.headers, ','));
fprintf('  colIndex.VariableName=%d Package=%d DataType=%d\n', t.columnIndex.VariableName, t.columnIndex.Package, t.columnIndex.DataType);
fprintf('  rows=%dx%d first=%s rowNumbers=%s\n', size(t.rows,1), size(t.rows,2), swb.Workbook.cellText(t.rows{1,1}), mat2str(t.rowNumbers));
fprintf('\nSMOKE_DONE\n');
end