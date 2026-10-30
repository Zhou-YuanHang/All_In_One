function preview_ui_run()
% 真实执行一遍一键流水线后导出界面截图（不是摆拍：表格/步骤/日志来自真实运行）
root = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(root, 'app'));
addpath(fullfile(root, 'tests'));
outDir = fullfile(root, 'docs', 'ui');
if ~isfolder(outDir), mkdir(outDir); end

tmp = tempname(); mkdir(tmp);
c = onCleanup(@() rmdir(tmp, 's'));
dictFile = swbfixture.Workbooks.makeDict(tmp);
portFile = swbfixture.Workbooks.makePort(tmp);
fprintf('fixtures: %s | %s\n', dictFile, portFile);

app = SimWorkbench('Visible', 'off', 'SettingsFile', fullfile(tmp, 'settings.json'));
cleanupApp = onCleanup(@() delete(app));
drawnow; pause(0.3);
app.populateDemo(dictFile, portFile);
drawnow; pause(0.3);

% 无人值守：关掉写前确认；模型名/目录指向临时目录，不污染仓库
app.H.confirmChk.Value = false;
app.H.cleanDictChk.Value = false;
app.H.modelNameEdit.Value = 'demo_model';
app.H.modelFolderEdit.Value = tmp;
app.H.modelPortEdit.Value = portFile;
app.H.scriptEdit.Value = fullfile(tmp, 'demo_objects.m');
app.H.slddEdit.Value = fullfile(tmp, 'demo.sldd');

app.runPipeline();
drawnow; pause(0.8);

steps = app.H.stepTable.Data;
for k = 1:size(steps, 1)
    fprintf('STEP %d: %-6s %-12s %s\n', k, steps{k,2}, steps{k,1}, steps{k,3});
end
fprintf('model exists=%d sldd exists=%d script exists=%d\n', ...
    isfile(fullfile(tmp, 'demo_model.slx')), isfile(fullfile(tmp, 'demo.sldd')), isfile(fullfile(tmp, 'demo_objects.m')));

tabs = {'工作流', '模型与端口', '日志'};
names = {'workflow_run', 'model_run', 'log_run'};
for k = 1:numel(tabs)
    app.setTab(tabs{k});
    drawnow; pause(0.4);
    out = fullfile(outDir, ['ui_' names{k} '.png']);
    exportapp(app.UIFigure, out);
    fprintf('saved %s (%d bytes)\n', out, dir(out).bytes);
end
fprintf('status: %s\n', app.H.statusLabel.Text);
fprintf('PREVIEW_RUN_DONE\n');
end
