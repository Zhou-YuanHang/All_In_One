function preview_ui()
% 构造 SimWorkbench，填充示例数据并导出 5 个标签页截图
root = 'F:\GithubRepos\All_In_One';
cd(root);
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
drawnow; pause(0.5);
app.populateDemo(dictFile, portFile);
drawnow; pause(0.5);

tabs = {'工作流', '数据字典', '模型与端口', '设置', '日志'};
names = {'workflow', 'dict', 'model', 'settings', 'log'};
for k = 1:numel(tabs)
    app.setTab(tabs{k});
    drawnow; pause(0.4);
    out = fullfile(outDir, ['ui_' names{k} '.png']);
    exportapp(app.UIFigure, out);
    fprintf('saved %s (%d bytes)\n', out, dir(out).bytes);
end

% 模板 Config 编辑器对话框（v1.5）
app.setTab('设置'); drawnow; pause(0.3);
dlg = swb.ui.TemplateConfigDialog(app.UIFigure, app.Settings.TemplateConfig);
drawnow; pause(0.4);
outDlg = fullfile(outDir, 'ui_template_config.png');
exportapp(dlg.Figure, outDlg);
fprintf('saved %s (%d bytes)\n', outDlg, dir(outDlg).bytes);
delete(dlg.Figure); drawnow;

% 组件完整性检查
fprintf('checks: tabs=%d dictItems=%d portRows=%d logLines=%d\n', ...
    numel(app.TabGroup.Children), numel(app.H.sheetList.Items), size(app.H.portTable.Data, 1), numel(app.H.logArea.Value));
delete(app);
fprintf('PREVIEW_DONE\n');
end