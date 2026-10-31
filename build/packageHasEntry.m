function hit = packageHasEntry(packageFile, names)
%PACKAGEHASENTRY 解包 zip 容器（.mlappinstall/.mltbx），递归查找同名文件或目录。
%   hit = packageHasEntry(pkg, {'+myPackage'}) 返回第一个命中的绝对路径，
%   未命中返回 ''。
%
%   打包脚本用它做产物复核：apputil.package / packageToolbox 会重新做依赖
%   分析，仅从暂存目录删掉排除项并不保证产物里没有，所以打包后再解包查一遍。
%
%   输入：
%     packageFile  .mlappinstall / .mltbx 全路径
%     names        cellstr/string，按名字（不含路径）匹配
%
%   见 also COPYTREEEXCLUDING

if ischar(names) || (isstring(names) && isscalar(names))
    names = {char(names)};
else
    names = cellstr(names);
end

tmp = [tempname, '_pkgcheck'];
mkdir(tmp);
cleanup = onCleanup(@() rmdir(tmp, 's'));
unzip(packageFile, tmp);

hit = '';
for k = 1:numel(names)
    hit = findEntryIn(tmp, names{k});
    if ~isempty(hit)
        return;
    end
end
end

function hit = findEntryIn(folder, name)
% 递归查找同名目录/文件，未命中返回 ''
hit = '';
items = dir(folder);
for k = 1:numel(items)
    nm = items(k).name;
    if any(strcmp(nm, {'.', '..'}))
        continue;
    end
    p = fullfile(folder, nm);
    if strcmp(nm, name)
        hit = p;
        return;
    end
    if items(k).isdir
        hit = findEntryIn(p, name);
        if ~isempty(hit)
            return;
        end
    end
end
end
