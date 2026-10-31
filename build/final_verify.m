function final_verify(varargin)
%FINAL_VERIFY 最终验收：打包 v1.6 → 干净安装 → 启动冒烟 → 全量回归。
%  用法（无头）：
%    matlab -batch "cd('F:\GithubRepos\All_In_One'); addpath('build'); final_verify"
%  报告写到 build\final_report.txt（UTF-8，避免 GBK 控制台乱码），
%  控制台只打印 ASCII 标记便于脚本抓取。
%
%  顺序说明（实测坑）：同一个 MATLAB 进程里先跑 runtests 再调
%  matlab.apputil.package，打包服务的 Java 端会静默退出（进程 exit 1，
%  无错误信息、不产出 .mlappinstall）。因此本脚本把打包/安装放在测试之前。

p = inputParser;
p.addParameter('Version', '1.6', @(x) ischar(x) || isstring(x));
p.addParameter('SkipTests', false, @(x) islogical(x) || isnumeric(x));
p.parse(varargin{:});
opt = p.Results;

root = fileparts(fileparts(mfilename('fullpath')));
reportFile = fullfile(root, 'build', 'final_report.txt');
fid = fopen(reportFile, 'w', 'n', 'UTF-8');
if fid < 0
    error('final_verify:report', '无法写入 %s', reportFile);
end
closeReport = onCleanup(@() fclose(fid));

addpath(fullfile(root, 'app'));
addpath(fullfile(root, 'tests'));
addpath(fullfile(root, 'tools'));
addpath(fullfile(root, 'build'));

% ---------- 1. 重新打包 ----------
% 注意：matlab.apputil.package 需要在 base 工作区执行（函数工作区里曾出现
% 静默不产出文件），故用 evalin('base', ...) 包一层。
fprintf('STEP=PACKAGE\n');
assignin('base', 'swbPkgVersion', char(opt.Version));
assignin('base', 'swbRepoRoot', root);
evalin('base', 'addpath(fullfile(swbRepoRoot, ''build'')); pkg = make_appinstaller(''Version'', swbPkgVersion);');
pkg = evalin('base', 'pkg');
pkgBytes = dir(pkg).bytes;
fprintf('PACKAGE_BYTES=%d\n', pkgBytes);
fprintf(fid, '== 打包 ==\n%s（%d 字节，版本 %s）\n', pkg, pkgBytes, char(opt.Version));

% ---------- 2. 干净安装 ----------
fprintf('STEP=INSTALL\n');
evalin('base', 'addpath(fullfile(swbRepoRoot, ''build'')); inst = install_app();');
inst = evalin('base', 'inst');
fprintf('INSTALL_ID=%s STATUS=%s\n', inst.id, inst.status);
fprintf(fid, '\n== 安装 ==\nid=%s name=%s status=%s\nlocation=%s\n', ...
    inst.id, inst.name, inst.status, inst.location);

% ---------- 3. 启动冒烟（安装副本） ----------
fprintf('STEP=LAUNCH\n');
addpath(inst.location);
figsBefore = numel(findall(0, 'Type', 'figure'));
launchOk = false;
appClass = '<none>';
try
    appObj = SimWorkbenchApp();
    appClass = class(appObj.AppHandle);
    drawnow; pause(1); drawnow;
    figsAfter = numel(findall(0, 'Type', 'figure'));
    launchOk = figsAfter > figsBefore || strcmp(appClass, 'SimWorkbench');
    fprintf('LAUNCH_OK=%d APP_CLASS=%s FIGS=%d\n', launchOk, appClass, figsAfter - figsBefore);
catch ME
    fprintf('LAUNCH_ERR=%s\n', ME.message);
    fprintf(fid, '\n启动失败：%s\n', ME.message);
end
close all force;
fprintf(fid, '\n== 启动冒烟（安装副本）==\n成功=%d 入口类型=%s\n', launchOk, appClass);

% ---------- 4. 安装副本是否含两处修复 ----------
mb = fullfile(inst.location, '+swb', 'ModelBuilder.m');
txt = fileread(mb);
hasExt = contains(txt, 'externalModelFile');
hasGuard = contains(txt, 'unexpectedModelFile');
fprintf('INSTALLED_HAS_FIXES external=%d guard=%d\n', hasExt, hasGuard);
fprintf(fid, '\n安装副本 ModelBuilder 含外部同名检测=%d，含保存后校验=%d\n', hasExt, hasGuard);

% ---------- 5. 全量回归 ----------
fprintf('STEP=TEST\n');
t0 = tic;
if opt.SkipTests
    res = matlab.unittest.TestResult.empty;
else
    res = runtests(fullfile(root, 'tests'), 'IncludeSubfolders', true);
end
elapsed = toc(t0);
total = numel(res);
passed = nnz([res.Passed]);
failed = nnz([res.Failed]);
incomplete = nnz([res.Incomplete]);
fprintf('TEST_TOTAL=%d PASSED=%d FAILED=%d INCOMPLETE=%d SECONDS=%.2f\n', ...
    total, passed, failed, incomplete, elapsed);
fprintf(fid, '\n== 全量回归 ==\n%d 个测试：通过 %d / 失败 %d / 未完成 %d，耗时 %.2f s\n', ...
    total, passed, failed, incomplete, elapsed);

names = string({res.Name});
if total > 0
    classes = extractBefore(names, '/');
    uniq = unique(classes, 'stable');
    fprintf(fid, '\n各类方法数：\n');
    for k = 1:numel(uniq)
        n = nnz(classes == uniq(k));
        fprintf(fid, '  %-28s %d\n', uniq(k), n);
        fprintf('CLASS %s=%d\n', uniq(k), n);
    end
    if failed > 0
        bad = names([res.Failed]);
        fprintf(fid, '\n失败用例：\n%s\n', strjoin(cellstr(bad), '\n'));
    end
end

fprintf(fid, '\nOK\n');
fprintf('DONE\n');
end
