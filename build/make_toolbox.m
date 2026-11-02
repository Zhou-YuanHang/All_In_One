function outFile = make_toolbox(varargin)
%MAKE_TOOLBOX 构建 SimWorkbench 工具箱安装包（.mltbx）
%   make_toolbox() 收集 app/ 下的界面与服务层，生成 build/SimWorkbench.mltbx。
%   make_toolbox('Version','1.7.1') 可指定版本号。
%
%   可选参数（Name-Value）：
%     Version           工具箱版本，默认 '1.7.2'
%     OutputFile        输出文件全路径，默认 <repo>/build/SimWorkbench.mltbx
%     IncludeDocs       是否把 docs/design 设计与 README 一起打进包，默认 true
%     ExcludeResources  不随包复制的 resources 子项（按名字），默认 {'+myPackage'}
%
%   工具箱根目录即安装后加入 MATLAB 路径的目录，因此安装完成即可直接
%   运行 SimWorkbench 或调用 swb.* 服务。
%
%   与 .mlappinstall 口径一致：resources/+myPackage 只是本地 CSC 演示包
%   （csc_registration.m + @Signal/@Parameter），从源码树运行足够；随包安装
%   后 swb.Dictionary.ensurePackagePath 会在该目录存在时 addpath，反而遮蔽
%   用户工程自己的 +myPackage。实现见 build/copyTreeExcluding.m，产物复核
%   见 build/packageHasEntry.m。

p = inputParser;
p.addParameter('Version', '1.7.2', @(x) ischar(x) || isstring(x));
p.addParameter('OutputFile', '', @(x) ischar(x) || isstring(x));
p.addParameter('IncludeDocs', true, @(x) islogical(x) || isnumeric(x));
p.addParameter('ExcludeResources', {'+myPackage'}, @(x) iscellstr(x) || isstring(x));
p.parse(varargin{:});
opt = p.Results;
excluded = cellstr(opt.ExcludeResources);

root = fileparts(fileparts(mfilename('fullpath')));
appDir = fullfile(root, 'app');
if ~exist(appDir, 'dir')
    error('make_toolbox:NoApp', '找不到 app 目录：%s', appDir);
end
if isempty(char(opt.OutputFile))
    outFile = fullfile(root, 'build', 'SimWorkbench.mltbx');
else
    outFile = char(opt.OutputFile);
end
buildDir = fileparts(outFile);
if ~exist(buildDir, 'dir'), mkdir(buildDir); end

stage = fullfile(root, 'build', 'stage', 'SimWorkbench');
if exist(stage, 'dir'), rmdir(stage, 's'); end
mkdir(stage);

% 1) 界面与 +swb 服务层：直接放到工具箱根，安装后根目录在路径上
copyfile(fullfile(appDir, 'SimWorkbench.m'), stage);
copyfile(fullfile(appDir, '+swb'), fullfile(stage, '+swb'));
if exist(fullfile(appDir, 'resources'), 'dir')
    copyTreeExcluding(fullfile(appDir, 'resources'), fullfile(stage, 'resources'), excluded);
end
for k = 1:numel(excluded)
    bad = fullfile(stage, 'resources', excluded{k});
    if exist(bad, 'dir') == 7 || exist(bad, 'file') == 2
        error('swb:makeToolbox:excludedResource', ...
            '暂存目录里仍有被排除的资源 %s（工具箱不应包含它）', bad);
    end
end

% 2) 文档
if opt.IncludeDocs
    if exist(fullfile(root, 'README.md'), 'file')
        copyfile(fullfile(root, 'README.md'), fullfile(stage, 'README.md'));
    end
    if exist(fullfile(root, 'docs'), 'dir')
        copyfile(fullfile(root, 'docs'), fullfile(stage, 'docs'));
        % 截图不必进包
        uiDir = fullfile(stage, 'docs', 'ui');
        if exist(uiDir, 'dir'), rmdir(uiDir, 's'); end
    end
end

% 3) Contents.m，供 help 与工具箱列表展示
writeContents(fullfile(stage, 'Contents.m'), char(opt.Version));

% 4) 打包
t = matlab.addons.toolbox.ToolboxOptions(stage, 'SimWorkbench');
t.ToolboxName = 'SimWorkbench';
t.ToolboxVersion = char(opt.Version);
t.AuthorName = 'SimWorkbench';
t.Summary = 'All-in-One Simulink 建模工作台：Excel 数据字典、.sldd、模型与端口';
t.Description = sprintf(['把 AutoCreateSldd 与 NewModelApp 的能力整合到一个界面：\n' ...
    'Excel 数据字典 → 校验 → 对象脚本 → .sldd，端口工作簿 → 模型/端口同步/Code Mapping。\n' ...
    '界面入口：SimWorkbench；服务层：+swb 包（无界面调用）。']);
t.ToolboxImageFile = '';
t.OutputFile = outFile;

files = listFiles(stage);
t.ToolboxFiles = files;
t.ToolboxMatlabPath = {fullfile(stage)};  % 安装后把工具箱根加入路径

matlab.addons.toolbox.packageToolbox(t);

% 产物复核：packageToolbox 会重新做依赖分析，仅从暂存目录删掉不保证产物里没有
hit = packageHasEntry(outFile, excluded);
if ~isempty(hit)
    error('swb:makeToolbox:excludedInPackage', ...
        '工具箱内仍包含被排除的资源 %s：%s', strjoin(excluded, '、'), hit);
end

fprintf('make_toolbox: %d 个文件 → %s（%d 字节）\n', numel(files), outFile, dir(outFile).bytes);
fprintf('  已排除资源：%s（不随工具箱打包）\n', strjoin(excluded, ', '));
if nargout == 0
    clear outFile
end
end

function files = listFiles(folder)
files = {};
items = dir(folder);
for k = 1:numel(items)
    name = items(k).name;
    if any(strcmp(name, {'.', '..'})), continue; end
    full = fullfile(folder, name);
    if items(k).isdir
        files = [files, listFiles(full)]; %#ok<AGROW>
    else
        files{end+1} = full; %#ok<AGROW>
    end
end
end

function writeContents(file, version)
fid = fopen(file, 'w', 'n', 'UTF-8');
if fid < 0, return; end
c = onCleanup(@() fclose(fid));
fprintf(fid, '%% SimWorkbench %s\n', version);
fprintf(fid, '%% All-in-One Simulink 建模工作台\n');
fprintf(fid, '%%\n');
fprintf(fid, '%% 界面入口\n');
fprintf(fid, '%%   SimWorkbench            打开工作台界面\n');
fprintf(fid, '%%\n');
fprintf(fid, '%% 服务层（无界面，可脚本化调用）\n');
fprintf(fid, '%%   swb.Pipeline            一键流水线：Excel → 校验 → .sldd → 模型\n');
fprintf(fid, '%%   swb.Validator           数据字典校验\n');
fprintf(fid, '%%   swb.ScriptBuilder       生成对象脚本 objects.m\n');
fprintf(fid, '%%   swb.Dictionary          写入/读取 .sldd\n');
fprintf(fid, '%%   swb.ReverseSync         .sldd → Excel 反向同步\n');
fprintf(fid, '%%   swb.ModelBuilder        创建/配置 Simulink 模型\n');
fprintf(fid, '%%   swb.PortSync            同步模型端口\n');
fprintf(fid, '%%   swb.CodeMapping         应用 Code Mapping\n');
fprintf(fid, '%%   swb.Settings            机器级设置（App 安装目录/simworkbench.json）\n');
fprintf(fid, '%%   swb.TemplateConfig      模板配置（resources/template_config.json）\n');
fprintf(fid, '%%   swb.ModelCatalog        模板模型目录\n');
fprintf(fid, '%%   swb.TemplateExport      模板导出（新模型复制模板/端口）\n');
fprintf(fid, '%%\n');
fprintf(fid, '%% 文档见 docs/design/all-in-one-design.md 与 README.md\n');
end
