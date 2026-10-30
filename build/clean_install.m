appsRoot = fullfile(getenv('APPDATA'),'MathWorks','MATLAB Add-Ons','Apps');
fprintf('APPSROOT=%s\n', appsRoot);
d = dir(fullfile(appsRoot,'SimWorkbench*'));
for k=1:numel(d); fprintf('FOUND %s isdir=%d\n', d(k).name, d(k).isdir); end
for k=1:numel(d)
  if d(k).isdir
    p = fullfile(appsRoot, d(k).name);
    [ok,msg] = rmdir(p,'s');
    fprintf('DEL %s ok=%d msg=%s\n', d(k).name, ok, msg);
  end
end
fprintf('EXISTS_AFTER=%d\n', exist(fullfile(appsRoot,'SimWorkbench'),'dir'));
infos = matlab.apputil.getInstalledAppInfo;
fprintf('COUNT_BEFORE_INSTALL=%d\n', numel(infos));
for k=1:numel(infos); fprintf('  PRE %s\n', infos(k).id); end
clear classes
r = matlab.apputil.install('F:\GithubRepos\All_In_One\build\SimWorkbench.mlappinstall');
disp(r);
infos2 = matlab.apputil.getInstalledAppInfo;
fprintf('COUNT_AFTER_INSTALL=%d\n', numel(infos2));
for k=1:numel(infos2); fprintf('  POST %s | %s\n', infos2(k).id, infos2(k).location); end