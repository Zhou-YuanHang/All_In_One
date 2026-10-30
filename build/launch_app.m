function launch_app()
%LAUNCH_APP 启动已安装的 SimWorkbench（绕过 Apps 选项卡的附加功能注册检查）。
%
%   MATLAB 的 Apps 选项卡点击 App 时会调用 matlab.apputil.run，而它在
%   R2024b 里会先执行 matlab.addons.isAddonEnabled(GUID)；若该 App 没有被
%   注册进附加功能注册表，就会报
%       "找不到具有指定标识符的附加功能"
%   并拒绝启动。用 matlab.apputil.install 在 matlab -batch 里安装时不会写
%   注册表（本机实测：installedAddons 里没有 SimWorkbench，AutoCreate* 有），
%   因此提供这个与注册表无关的启动入口。
%
%   用法（MATLAB 命令行）：
%       addpath('F:\GithubRepos\All_In_One\build'); launch_app
%
%   若 App 尚未安装，则退回仓库内的 app 目录直接启动。
%
%   参见：matlab.apputil.run、appinstall.internal.runapp、build\install_app.m

repoRoot = fileparts(fileparts(mfilename('fullpath')));
installDir = localFindInstalledApp();

if isempty(installDir)
    srcDir = fullfile(repoRoot, 'app');
    if exist(fullfile(srcDir, 'SimWorkbench.m'), 'file') ~= 2
        error('launch_app:notFound', ...
            '未找到已安装的 SimWorkbench，也没有找到 %s', fullfile(srcDir, 'SimWorkbench.m'));
    end
    fprintf('未检测到已安装副本，直接从仓库启动：%s\n', srcDir);
    addpath(srcDir);
    SimWorkbench();
    return;
end

fprintf('启动已安装的 SimWorkbench：%s\n', installDir);
addpath(installDir);
addpath(fullfile(installDir, 'resources'));
try
    SimWorkbench();
catch ME
    % 退回官方内部入口：它只加路径并执行 *App.m 包装类，不查注册表
    wrapper = matlab.internal.apputil.AppUtil.genwrapperfilename(installDir);
    fprintf('直接调用入口失败（%s），改走 appinstall.internal.runapp ...\n', ME.message);
    appinstall.internal.runapp(wrapper, installDir);
end
end

function installDir = localFindInstalledApp()
installDir = '';
appsRoot = '';
try
    appsRoot = char(com.mathworks.appmanagement.MlappinstallUtil ...
        .getAppInstallationFolder.getAbsolutePath());
catch
end
if isempty(appsRoot) || exist(appsRoot, 'dir') ~= 7
    base = getenv('APPDATA');
    if isempty(base)
        base = fullfile(getenv('USERPROFILE'), 'AppData', 'Roaming');
    end
    appsRoot = fullfile(base, 'MathWorks', 'MATLAB Add-Ons', 'Apps');
end
candidates = dir(fullfile(appsRoot, 'SimWorkbench*'));
for k = 1:numel(candidates)
    if ~candidates(k).isdir
        continue;
    end
    if exist(fullfile(appsRoot, candidates(k).name, 'SimWorkbench.m'), 'file') == 2
        installDir = fullfile(appsRoot, candidates(k).name);
        return;
    end
end
end
