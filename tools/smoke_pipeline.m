function smoke_pipeline()
root = 'F:\GithubRepos\All_In_One';
cd(root);
addpath(fullfile(root,'app')); addpath(fullfile(root,'tests'));
tmp = tempname(); mkdir(tmp);
c = onCleanup(@() rmdir(tmp, 's'));
dict = swbfixture.Workbooks.makeDict(tmp);
port = swbfixture.Workbooks.makePort(tmp);
log = swb.Log();
cfg = struct();
cfg.DictWorkbook = dict;
cfg.PortWorkbook = port;
cfg.Sheets = {'Signal','Parameter','Bus','BusElement','Const','Enum'};
cfg.ScriptFile = fullfile(tmp, 'out_objects.m');
cfg.SlddFile = fullfile(tmp, 'out.sldd');
mc = swb.Schema.modelConfigDefaults();
mc.Name = 'pipeline_smoke';
mc.Folder = tmp;
mc.PortWorkbook = port;
mc.OpenAfterCreate = false;
mc.ConflictPolicy = 'overwrite';
mc.ApplyCodeMapping = false;
cfg.Model = mc;
cfg.Log = log;

result = swb.Pipeline.run(cfg);
fprintf('=== SUMMARY ===\n%s\n', result.summary);
fprintf('OK=%d steps=%d warnings=%d\n', result.ok, numel(result.steps), numel(result.warnings));
for k = 1:numel(result.steps)
    st = result.steps(k);
    fprintf('STEP %d: %-8s %s | %s\n', k, st.status, st.name, st.detail);
end
fprintf('files script=%d sldd=%d slx=%d\n', isfile(cfg.ScriptFile), isfile(cfg.SlddFile), isfile(fullfile(tmp,'pipeline_smoke.slx')));
if isstruct(result.dictStats)
    d = result.dictStats;
    fprintf('dict +%d ~%d -%d x%d total=%d\n', d.added, d.updated, d.skipped, d.failed, d.totalAfter);
end

% 第二次运行：幂等性（应 ~0 更新 / -跳过，模型覆盖有备份）
result2 = swb.Pipeline.run(cfg);
fprintf('=== SECOND RUN ===\n%s\n', result2.summary);
fprintf('second ok=%d\n', result2.ok);
fprintf('backup exists=%d\n', isfile(fullfile(tmp,'pipeline_smoke.slx.bak')));
bdclose('all');
fprintf('PIPELINE_SMOKE_DONE\n');
end
