function outFile = make_appinstaller(varargin)
%MAKE_APPINSTALLER 打包成可双击安装的 .mlappinstall（官方 App 打包流程）。
%   outFile = make_appinstaller() 生成 build\SimWorkbench.mlappinstall。
%   outFile = make_appinstaller('Version','1.4') 指定版本号（默认 1.4）。
%
%   原理：MATLAB App 安装包 = OPC(zip) 容器 + 元数据；官方入口：
%     matlab.apputil.create  —— 打开打包对话框生成 .prj（需要桌面）
%     matlab.apputil.package —— 读 .prj 打包（可无头运行）
%     matlab.apputil.install —— 安装
%   本脚本用代码生成与对话框等价的最小 .prj（plugin.apptool / target.mlapps），
%   再调用 matlab.apputil.package，因此在 matlab -batch 中也能构建。
%
%   安装后：App 出现在 MATLAB「Apps」选项卡，点击执行入口 SimWorkbench；
%   +swb 包与 resources 按原目录结构安装到 App 根目录。

p = inputParser;
p.addParameter('Version', '1.4', @(x) ischar(x) || isstring(x));
p.addParameter('OutputFile', '', @(x) ischar(x) || isstring(x));
p.addParameter('Guid', '4963bdd0-a45a-4711-ad54-aa2e96206eef', @(x) ischar(x) || isstring(x));
p.parse(varargin{:});
opt = p.Results;

root = fileparts(fileparts(mfilename('fullpath')));
if isempty(char(opt.OutputFile))
    outFile = fullfile(root, 'build', 'SimWorkbench.mlappinstall');
else
    outFile = char(opt.OutputFile);
end
outDir = fileparts(outFile);
if ~exist(outDir, 'dir'), mkdir(outDir); end

% ---------- 1. 暂存：安装后的 App 根目录结构 ----------
stage = fullfile(root, 'build', 'appstage');
if exist(stage, 'dir'), rmdir(stage, 's'); end
mkdir(stage);
copyfile(fullfile(root, 'app', 'SimWorkbench.m'), stage);
copyfile(fullfile(root, 'app', '+swb'), fullfile(stage, '+swb'));
copyfile(fullfile(root, 'app', 'resources'), fullfile(stage, 'resources'));
if exist(fullfile(root, 'README.md'), 'file')
    copyfile(fullfile(root, 'README.md'), stage);
end
if exist(fullfile(root, 'docs', 'design', 'all-in-one-design.md'), 'file')
    mkdir(fullfile(stage, 'docs'));
    copyfile(fullfile(root, 'docs', 'design', 'all-in-one-design.md'), fullfile(stage, 'docs'));
end

% ---------- 2. 生成打包工程 ----------
prjFile = fullfile(stage, 'SimWorkbench.prj');
writeProject(prjFile, stage, char(opt.Version), char(opt.Guid));

% ---------- 3. 官方打包 ----------
fprintf('make_appinstaller: 打包中（.prj = %s）...\n', prjFile);
matlab.apputil.package(prjFile);

built = fullfile(stage, 'SimWorkbench.mlappinstall');
if ~exist(built, 'file')
    error('swb:makeAppInstaller:noOutput', '打包未生成 mlappinstall：%s', built);
end
if exist(outFile, 'file'), delete(outFile); end
movefile(built, outFile);

fprintf('make_appinstaller: OK → %s（%d 字节）\n', outFile, dir(outFile).bytes);
fprintf('  安装：matlab.apputil.install(''%s'')\n', outFile);
fprintf('  或双击该文件，在 MATLAB「Apps」选项卡启动。\n');
end

% =====================================================================
function writeProject(prjFile, stage, version, guid)
depfun = listFiles(fullfile(stage, '+swb'), stage);
res = listFiles(fullfile(stage, 'resources'), stage);
docs = {};
if exist(fullfile(stage, 'README.md'), 'file')
    docs{end+1} = 'README.md'; %#ok<AGROW>
end
if exist(fullfile(stage, 'docs', 'all-in-one-design.md'), 'file')
    docs{end+1} = fullfile('docs', 'all-in-one-design.md'); %#ok<AGROW>
end

templateFile = fullfile(fileparts(mfilename('fullpath')), 'appinstaller_template.xml');
txt = fileread(templateFile);
txt = strrep(txt, '{{PRJ_FILE}}', prjFile);
txt = strrep(txt, '{{STAGE}}', stage);
txt = strrep(txt, '{{VERSION}}', version);
txt = strrep(txt, '{{GUID}}', guid);
txt = strrep(txt, '{{MAIN_FILES}}', fileXml({'SimWorkbench.m'}));
txt = strrep(txt, '{{DEPFUN_FILES}}', fileXml(depfun));
txt = strrep(txt, '{{RESOURCE_FILES}}', fileXml([res, docs]));

fid = fopen(prjFile, 'w', 'n', 'UTF-8');
if fid < 0
    error('swb:makeAppInstaller:prjWrite', '无法写入 %s', prjFile);
end
c = onCleanup(@() fclose(fid));
fwrite(fid, txt, 'char');
end

function s = fileXml(files)
s = '';
for k = 1:numel(files)
    s = [s, sprintf('      <file>$%s\\%s</file>\n', '{PROJECT_ROOT}', char(files{k}))]; %#ok<AGROW>
end
end

function files = listFiles(folder, root)
files = {};
items = dir(folder);
for k = 1:numel(items)
    if any(strcmp(items(k).name, {'.', '..'})), continue; end
    full = fullfile(folder, items(k).name);
    if items(k).isdir
        files = [files, listFiles(full, root)]; %#ok<AGROW>
    else
        files{end+1} = extractAfter(full, [root filesep]); %#ok<AGROW>
    end
end
end
