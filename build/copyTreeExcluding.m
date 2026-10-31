function copyTreeExcluding(src, dst, excludedNames)
%COPYTREEEXCLUDING 递归复制目录，跳过名字命中 excludedNames 的子项。
%   copyTreeExcluding(src, dst, {'+myPackage'}) 把 src 的内容复制到 dst，
%   但任何层级上名为 '+myPackage' 的文件/目录都不复制。
%   打包脚本用它把本地 CSC 演示包挡在安装包外（见 make_appinstaller /
%   make_toolbox 的 'ExcludeResources' 参数与 README「为什么排除
%   resources/+myPackage」）。
%
%   输入：
%     src            源目录（不存在时直接返回，不报错）
%     dst            目标目录（不存在时创建）
%     excludedNames  cellstr/string，按名字（不含路径）跳过
%
%   见 also PACKAGEHASENTRY

if ~exist(src, 'dir')
    return;
end
if ischar(excludedNames) || isstring(excludedNames) && isscalar(excludedNames)
    excludedNames = {char(excludedNames)};
else
    excludedNames = cellstr(excludedNames);
end
if ~exist(dst, 'dir')
    mkdir(dst);
end
items = dir(src);
for k = 1:numel(items)
    nm = items(k).name;
    if any(strcmp(nm, {'.', '..'}))
        continue;
    end
    if any(strcmp(nm, excludedNames))
        continue;
    end
    s = fullfile(src, nm);
    d = fullfile(dst, nm);
    if items(k).isdir
        copyTreeExcluding(s, d, excludedNames);
    else
        copyfile(s, d);
    end
end
end
