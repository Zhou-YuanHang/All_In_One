function result = install_app(varargin)
%INSTALL_APP  Cleanly install (or reinstall) the packaged SimWorkbench App.
%
%   result = install_app() installs build\SimWorkbench.mlappinstall.
%
%   matlab.apputil.install is NOT idempotent: if an older copy is already
%   registered, its update branch (matlab.apputil.install line 70,
%   "status.status = 'updated'") throws
%   "此赋值需要标量结构体 / Assignment requires a scalar struct".
%   This helper first deletes previously installed SimWorkbench folders, so
%   repeated runs produce a clean install.
%
%   result = install_app('PackageFile', pkg, 'AppName', 'SimWorkbench')
%
%   See also make_appinstaller, matlab.apputil.install.

repoRoot = fileparts(fileparts(mfilename('fullpath')));
p = inputParser;
addParameter(p, 'PackageFile', fullfile(repoRoot, 'build', 'SimWorkbench.mlappinstall'));
addParameter(p, 'AppName', 'SimWorkbench');
parse(p, varargin{:});
opts = p.Results;

pkg = char(opts.PackageFile);
if exist(pkg, 'file') ~= 2
    error('install_app:missingPackage', ...
        '找不到安装包：%s（先运行 build\\make_appinstaller.m）', pkg);
end

appsRoot = localAppsRoot();
fprintf('App 安装根目录：%s\n', appsRoot);

removed = localRemoveOldInstalls(appsRoot, opts.AppName);
fprintf('已清理 %d 个旧安装目录。\n', numel(removed));

fprintf('安装 %s ...\n', pkg);
result = matlab.apputil.install(pkg);
fprintf('id=%s  name=%s  status=%s\n', result.id, result.name, result.status);
fprintf('安装位置：%s\n', result.location);

fprintf('\n当前已安装的 App：\n');
infos = matlab.apputil.getInstalledAppInfo;
for k = 1:numel(infos)
    fprintf('  %-22s %s\n', infos(k).id, infos(k).location);
end

fprintf('\n提示：在 MATLAB 中直接运行 matlab.apputil.run(''%s'') 或从“App”选项卡启动。\n', result.id);
end

function root = localAppsRoot()
root = '';
try
    root = char(com.mathworks.appmanagement.MlappinstallUtil ...
        .getAppInstallationFolder.getAbsolutePath());
catch
end
if isempty(root) || exist(root, 'dir') ~= 7
    base = getenv('APPDATA');
    if isempty(base)
        base = fullfile(getenv('USERPROFILE'), 'AppData', 'Roaming');
    end
    root = fullfile(base, 'MathWorks', 'MATLAB Add-Ons', 'Apps');
end
end

function removed = localRemoveOldInstalls(appsRoot, appName)
removed = {};
if isempty(appsRoot) || exist(appsRoot, 'dir') ~= 7
    return;
end
esc = regexptranslate('escape', appName);
d = dir(fullfile(appsRoot, [appName '*']));
for k = 1:numel(d)
    if ~d(k).isdir
        continue;
    end
    nm = d(k).name;
    if strcmp(nm, appName) || ~isempty(regexp(nm, ['^' esc ' - \d+$'], 'once'))
        target = fullfile(appsRoot, nm);
        try
            rmdir(target, 's');
            removed{end+1} = nm; %#ok<AGROW>
            fprintf('  已删除 %s\n', target);
        catch ME
            warning('install_app:deleteFailed', '删除 %s 失败：%s', target, ME.message);
        end
    end
end
end
