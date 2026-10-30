function Excel2Workspace(AllSheets, fullpath, outputFilename, filename, selection)
%% Excel2Workspace — 从 Excel 读取数据并生成 Simulink 对象 M 脚本
%  读取 Excel 中的 Signal / Parameter / Const / Bus / BusElement 等 sheet，
%  生成创建 Simulink 对象的 M 脚本。Enum sheet 额外生成独立的 .m 类定义文件。
%
%  用法:
%    Excel2Workspace                                          % 弹出对话框选择文件
%    Excel2Workspace(AllSheets, fullpath, outputFilename, filename)           % 4参数，弹 listdlg
%    Excel2Workspace(AllSheets, fullpath, outputFilename, filename, selection) % 5参数，跳过 listdlg

%% 无参数时自主运行（弹窗选文件）
if nargin == 0
    [filename, filepath] = uigetfile( ...
        {'*.xlsx;*.xls', 'Excel 文件 (*.xlsx, *.xls)'}, ...
        '选择数据字典 Excel 文件');
    if isequal(filename, 0)
        fprintf('已取消\n');
        return;
    end
    fullpath = fullfile(filepath, filename);
    [~, AllSheets] = xlsfinfo(fullpath);
    fprintf('输入文件: %s\n', fullpath);
    fprintf('找到的工作表: %s\n', strjoin(AllSheets, ', '));
    [~, baseName, ~] = fileparts(filename);
    outputFilename = fullfile(filepath, [baseName, '_objects.m']);
end

%% 默认选中 Signal 和 Parameter（按名称匹配，不写死索引）
defaultSel = [];
for i = 1:length(AllSheets)
    if any(strcmpi(AllSheets{i}, {'Signal', 'Parameter'}))
        defaultSel(end+1) = i;
    end
end

%% 让用户选择要处理的 sheet（5参数时跳过 listdlg）
% 确保 selection 是行向量（R2024b 中 cellstr(sheetnames) 可能返回列向量）
if nargin >= 5
    selection = selection(:)';
end
if nargin < 5
    [selection, ok] = listdlg('PromptString', '选择要读取的工作表（可多选）', ...
        'SelectionMode', 'multiple', ...
        'ListString', AllSheets, ...
        'Name', '工作表选择', ...
        'ListSize', [300, 150], ...
        'InitialValue', defaultSel);
    if ~ok
        fprintf('用户取消了选择工作表。\n');
        return;
    end
else
    fprintf('使用传入的工作表选择（跳过 dialog）\n');
end

%% 提取输出目录和基础名
[outDir, baseName, ~] = fileparts(outputFilename);

%% 打开输出文件
fid = fopen(outputFilename, 'w', 'n', 'UTF-8');
if fid == -1
    error('无法创建输出文件: %s', outputFilename);
end

fprintf(fid, '%%%% 自动生成的数据对象文件\n');
fprintf(fid, '%%%% 创建时间: %s\n', datetime('now'));
fprintf(fid, '%%%% 来源 Excel: %s\n', filename);
fprintf(fid, '%%%%\n');
fprintf(fid, '%%%% 在 MATLAB 中运行此脚本即可在工作区创建所有 Simulink 对象\n');

% 收集 Bus 名称用于 BusElement 校验
busNames = {};

%% 一次性读取所有选中的 sheet 到缓存（避免重复 IO 瓶颈）
fprintf('--- 读取选中的工作表到缓存 ---\n');
sheetCache = struct();
for idx = selection
    sheetName = AllSheets{idx};
    sheetCache.(sheetName) = readSheet(fullpath, sheetName);
end

% 从缓存收集 Bus 名称供 BusElement 用
if isfield(sheetCache, 'Bus')
    Tbus = sheetCache.Bus;
    if height(Tbus) > 0
        for r = 1:height(Tbus)
            bn = safeStr(Tbus.BusName(r));
            if ~isempty(bn)
                busNames{end+1} = bn;
            end
        end
    end
end

%% 遍历选中的 sheet
% 先处理 Bus（收集 Bus 名称供 BusElement 用）
busSeen = false;
for idx = selection
    if strcmp(AllSheets{idx}, 'Bus') && isfield(sheetCache, 'Bus')
        busSeen = true;
        fprintf('\n正在处理 sheet: Bus (来自缓存)\n');
        writeBusSection(fid, sheetCache.Bus, 'Bus');
        break;
    end
end

% 再处理其他选中的 sheet（含 BusElement）
for idx = selection
    sheetName = AllSheets{idx};
    if strcmp(sheetName, 'Bus') && busSeen
        continue;  % Bus 已处理过
    end
    T = sheetCache.(sheetName);
    if height(T) == 0
        fprintf('  跳过空白工作表: %s\n', sheetName);
        continue;
    end
    fprintf('\n正在处理 sheet: %s (来自缓存)\n', sheetName);

    switch sheetName
        case 'Bus'
            writeBusSection(fid, T, sheetName);

        case 'BusElement'
            writeBusElementSection(fid, T, busNames);

        case 'Signal'
            writeSignalSection(fid, T, sheetName);

        case 'Parameter'
            writeParameterSection(fid, T, sheetName);

        case 'Const'
            writeConstSection(fid, T, sheetName);

        case 'Enum'
            writeEnumFiles(outDir, T, sheetName);

        otherwise
            fprintf('  跳过未知工作表: %s\n', sheetName);
    end
end

fclose(fid);
fprintf('\n=============== 导入完成 ===============\n');
fprintf('数据对象已保存到文件: %s\n', outputFilename);
fprintf('要使用这些对象，请在 MATLAB 中运行此脚本。\n');
end


%% ================================================================
%  读取 sheet 为 table（统一按字符串读取）
%% ================================================================
function T = readSheet(fullpath, sheetName)
try
    opts = detectImportOptions(fullpath, 'Sheet', sheetName);
    for j = 1:length(opts.VariableNames)
        opts = setvartype(opts, opts.VariableNames{j}, 'string');
    end
    T = readtable(fullpath, opts);
    fprintf('  读取 %s: %d 行 %d 列\n', sheetName, height(T), width(T));
catch ME
    warning('读取 %s 失败: %s', sheetName, ME.message);
    T = table();
end
end


%% ================================================================
%  辅助函数
%% ================================================================
function s = safeStr(val)
if ismissing(val) || isempty(val)
    s = '';
else
    s = strtrim(string(val));
end
end

function s = orDef(val, default)
s = safeStr(val);
if isempty(s), s = default; end
end

function expr = fmtVal(val)
if ismissing(val) || isempty(val)
    expr = '[]'; return;
end
s = strtrim(string(val));
if s.upper == "NONE" || s == ""
    expr = '[]'; return;
end
n = str2double(s);
if ~isnan(n)
    expr = s; return;
end
if startsWith(s, '[') && endsWith(s, ']')
    expr = s; return;
end
if s.upper == "TRUE"
    expr = 'true'; return;
end
if s.upper == "FALSE"
    expr = 'false'; return;
end
expr = "''" + replace(s, "'", "''") + "''";
expr = char(expr);
end

function writeSec(fid, title)
fprintf(fid, '\n%%%% %s %s %s\n\n', ...
    repmat('=', 1, 16), title, repmat('=', 1, 16));
end

function writeCmt(fid, name, label)
if isempty(label)
    fprintf(fid, '%%%% ----- %s -----\n', name);
else
    fprintf(fid, '%%%% ----- %s: %s -----\n', label, name);
end
end

function writeSC(fid, name, sc)
defaultSC = ["Auto","SimulinkGlobal","ExportedGlobal", ...
             "ImportedExtern","ImportedExternPointer"];
if any(strcmpi(sc, defaultSC))
    fprintf(fid, '%s.CoderInfo.StorageClass = ''%s'';\n', name, sc);
else
    fprintf(fid, '%s.CoderInfo.StorageClass = ''Custom'';\n', name);
    fprintf(fid, '%s.CoderInfo.CustomStorageClass = ''%s'';\n', name, sc);
end
end

function writeStrProp(fid, name, row, col, field, prop)
if nargin < 6, prop = field; end
if ~any(strcmpi(col, field)), return; end
v = safeStr(row.(field));
if isempty(v), return; end
fprintf(fid, '%s.%s = ''%s'';\n', name, prop, v);
end

function writeScalarProp(fid, name, row, col, field)
if ~any(strcmpi(col, field)), return; end
v = row.(field);
if ismissing(v), return; end
e = fmtVal(v);
if ~strcmp(e, '[]')
    fprintf(fid, '%s.%s = %s;\n', name, field, e);
end
end

function writeValProp(fid, name, row, col, field)
if ~any(strcmpi(col, field)), return; end
v = row.(field);
if ismissing(v), return; end
fprintf(fid, '%s.%s = %s;\n', name, field, fmtVal(v));
end


%% ================================================================
%  Signal 写入
%% ================================================================
function writeSignalSection(fid, T, ~)
if height(T) == 0, return; end
col = T.Properties.VariableNames;

writeSec(fid, 'Signal 对象');
for row = 1:height(T)
    r = T(row,:);
    name = safeStr(r.VariableName);
    if isempty(name), continue; end

    pkg  = orDef(r.Package, 'Simulink');

    writeCmt(fid, name, 'Signal');
    fprintf(fid, '%s = %s.Signal;\n', name, pkg);

    sc = safeStr(r.CustomStorageClass);
    if ~isempty(sc), writeSC(fid, name, sc); end

    % CustomAttributes 可能不被自定义包支持，用 try-catch 保护
    if any(strcmpi(col, 'HeaderFile'))
        v = safeStr(r.HeaderFile);
        if ~isempty(v)
            fprintf(fid, 'try %s.CoderInfo.CustomAttributes.HeaderFile = ''%s''; catch, end\n', name, v);
        end
    end
    if any(strcmpi(col, 'DefinitionFile'))
        v = safeStr(r.DefinitionFile);
        if ~isempty(v)
            fprintf(fid, 'try %s.CoderInfo.CustomAttributes.DefinitionFile = ''%s''; catch, end\n', name, v);
        end
    end
    writeStrProp(fid, name, r, col, 'DataType');
    writeStrProp(fid, name, r, col, 'InitialValue');
    writeScalarProp(fid, name, r, col, 'Min');
    writeScalarProp(fid, name, r, col, 'Max');
    writeStrProp(fid, name, r, col, 'Description');
    writeStrProp(fid, name, r, col, 'Unit', 'DocUnits');
    writeValProp(fid, name, r, col, 'Dimensions');
    writeStrProp(fid, name, r, col, 'Complexity');
    fprintf(fid, '\n');
end
fprintf('  完成 Signal 变量处理\n');
end


%% ================================================================
%  Parameter 写入
%% ================================================================
function writeParameterSection(fid, T, ~)
if height(T) == 0, return; end
col = T.Properties.VariableNames;

writeSec(fid, 'Parameter 对象');
for row = 1:height(T)
    r = T(row,:);
    name = safeStr(r.VariableName);
    if isempty(name), continue; end

    pkg  = orDef(r.Package, 'Simulink');

    writeCmt(fid, name, 'Parameter');
    fprintf(fid, '%s = %s.Parameter;\n', name, pkg);

    sc = safeStr(r.CustomStorageClass);
    if ~isempty(sc), writeSC(fid, name, sc); end

    % CustomAttributes 可能不被自定义包支持，用 try-catch 保护
    if any(strcmpi(col, 'HeaderFile'))
        v = safeStr(r.HeaderFile);
        if ~isempty(v)
            fprintf(fid, 'try %s.CoderInfo.CustomAttributes.HeaderFile = ''%s''; catch, end\n', name, v);
        end
    end
    if any(strcmpi(col, 'DefinitionFile'))
        v = safeStr(r.DefinitionFile);
        if ~isempty(v)
            fprintf(fid, 'try %s.CoderInfo.CustomAttributes.DefinitionFile = ''%s''; catch, end\n', name, v);
        end
    end
    writeStrProp(fid, name, r, col, 'DataType');

    % 先设置 Dimensions，再设 Value（Simulink 要求设维度时 Value 为空）
    writeValProp(fid, name, r, col, 'Dimensions');

    % Parameter 用 Value（Excel 列名为 InitialValue）
    if any(strcmpi(col, 'InitialValue'))
        v = r.InitialValue;
        if ~ismissing(v)
            fprintf(fid, '%s.Value = %s;\n', name, fmtVal(v));
        end
    end

    writeScalarProp(fid, name, r, col, 'Min');
    writeScalarProp(fid, name, r, col, 'Max');
    writeStrProp(fid, name, r, col, 'Description');
    writeStrProp(fid, name, r, col, 'Unit', 'DocUnits');
    writeStrProp(fid, name, r, col, 'Complexity');
    fprintf(fid, '\n');
end
fprintf('  完成 Parameter 变量处理\n');
end


%% ================================================================
%  Const 写入（Parameter + 可配置存储类）
%% ================================================================
function writeConstSection(fid, T, ~)
if height(T) == 0, return; end
col = T.Properties.VariableNames;

writeSec(fid, 'Const 对象 (Parameter + 存储类)');
for row = 1:height(T)
    r = T(row,:);
    name = safeStr(r.Name);
    if isempty(name), continue; end

    % 读取 Package，默认 Simulink（兼容旧版无 Package 列的模板）
    pkg = 'Simulink';
    if any(strcmpi(col, 'Package'))
        p = orDef(r.Package, 'Simulink');
        if ~isempty(p), pkg = p; end
    end

    writeCmt(fid, name, 'Const');
    fprintf(fid, '%s = %s.Parameter;\n', name, pkg);

    % 读取存储类，默认 Define（兼容旧版无 CustomStorageClass 列的模板）
    sc = 'Define';
    if any(strcmpi(col, 'CustomStorageClass'))
        sc0 = safeStr(r.CustomStorageClass);
        if ~isempty(sc0), sc = sc0; end
    end
    writeSC(fid, name, sc);

    writeStrProp(fid, name, r, col, 'DataType');

    if any(strcmpi(col, 'Value'))
        v = r.Value;
        if ~ismissing(v)
            fprintf(fid, '%s.Value = %s;\n', name, fmtVal(v));
        end
    end

    writeStrProp(fid, name, r, col, 'HeaderFile', 'CoderInfo.CustomAttributes.HeaderFile');
    fprintf(fid, '\n');
end
fprintf('  完成 Const 变量处理\n');
end


%% ================================================================
%  Bus 写入
%% ================================================================
function writeBusSection(fid, T, ~)
if height(T) == 0, return; end
col = T.Properties.VariableNames;

writeSec(fid, 'Bus 对象');
for row = 1:height(T)
    r = T(row,:);
    bn = safeStr(r.BusName);
    if isempty(bn), continue; end

    writeCmt(fid, bn, 'Bus');
    fprintf(fid, '%s = Simulink.Bus;\n', bn);

    writeStrProp(fid, bn, r, col, 'Description');
    writeStrProp(fid, bn, r, col, 'HeaderFile');

    if any(strcmpi(col, 'Alignment'))
        al = r.Alignment;
        if ~ismissing(al)
            fprintf(fid, '%s.Alignment = %s;\n', bn, al);
        end
    end

    if any(strcmpi(col, 'PreserveElementDimensions'))
        ped = safeStr(r.PreserveElementDimensions);
        if ~isempty(ped)
            if upper(ped) == "TRUE" || ped == "1"
                fprintf(fid, '%s.PreserveElementDimensions = true;\n', bn);
            else
                fprintf(fid, '%s.PreserveElementDimensions = false;\n', bn);
            end
        end
    end

    writeStrProp(fid, bn, r, col, 'DataScope');
    fprintf(fid, '\n');
end
fprintf('  完成 Bus 对象处理\n');
end


%% ================================================================
%  BusElement 写入（无中间变量）
%% ================================================================
function writeBusElementSection(fid, T, busNames)
if height(T) == 0, return; end

writeSec(fid, 'BusElement 定义');

% 按 BusName 分组
[unames, ~, uidx] = unique(string(T.BusName));
col = T.Properties.VariableNames;

for b = 1:length(unames)
    bn = strtrim(unames(b));
    if ismissing(bn) || strlength(bn) == 0, continue; end

    % 不检查 busNames，始终生成 BusElement 代码
    % （Bus 对象在输出脚本中已由 writeBusSection 先行写入）

    mask = (uidx == b);
    elems = T(mask, :);
    ne = height(elems);
    ecol = elems.Properties.VariableNames;

    writeCmt(fid, sprintf('为 Bus ''%s'' 创建 %d 个元素', bn, ne), '');

    % MATLAB 标准格式：临时变量 saveVarsTmp{1} + 列索引
    fprintf(fid, 'saveVarsTmp{1} = Simulink.BusElement;\n');
    for e = 1:ne
        er = elems(e,:);
        en = safeStr(er.ElementName);
        if isempty(en), continue; end

        if e == 1
            fprintf(fid, 'saveVarsTmp{1}.Name = ''%s'';\n', en);
            writeStrProp(fid, 'saveVarsTmp{1}', er, ecol, 'Description');
            writeStrProp(fid, 'saveVarsTmp{1}', er, ecol, 'DataType');
            writeValProp(fid, 'saveVarsTmp{1}', er, ecol, 'Dimensions');
            writeStrProp(fid, 'saveVarsTmp{1}', er, ecol, 'Unit', 'DocUnits');
        else
            fprintf(fid, 'saveVarsTmp{1}(%d, 1) = Simulink.BusElement;\n', e);
            fprintf(fid, 'saveVarsTmp{1}(%d, 1).Name = ''%s'';\n', e, en);
            writeStrProp(fid, sprintf('saveVarsTmp{1}(%d, 1)', e), er, ecol, 'Description');
            writeStrProp(fid, sprintf('saveVarsTmp{1}(%d, 1)', e), er, ecol, 'DataType');
            writeValProp(fid, sprintf('saveVarsTmp{1}(%d, 1)', e), er, ecol, 'Dimensions');
            writeStrProp(fid, sprintf('saveVarsTmp{1}(%d, 1)', e), er, ecol, 'Unit', 'DocUnits');
        end
    end
    fprintf(fid, '%s.Elements = saveVarsTmp{1};\n', bn);
    fprintf(fid, 'clear saveVarsTmp;\n\n');
end
fprintf('  完成 BusElement 处理\n');
end


%% ================================================================
%  Enum 文件生成（独立 .m 类定义）
%% ================================================================
function writeEnumFiles(outDir, T, ~)
if height(T) == 0, return; end

[enumNames, ~, idx] = unique(string(T.EnumName));
fprintf('  发现 %d 个枚举类型: %s\n', length(enumNames), strjoin(enumNames, ', '));

for e = 1:length(enumNames)
    ename = strtrim(enumNames(e));
    if ismissing(ename) || strlength(ename) == 0, continue; end

    mask = (idx == e);
    members = T(mask, :);

    % 取第一个非空 DataType
    baseType = 'uint8';
    for r = 1:height(members)
        dt = safeStr(members.DataType(r));
        if ~isempty(dt)
            baseType = dt;
            break;
        end
    end

    ePath = fullfile(outDir, sprintf('%s.m', ename));
    efid = fopen(ePath, 'w', 'n', 'UTF-8');
    if efid == -1
        warning('无法创建枚举文件: %s', ePath);
        continue;
    end

    fprintf(efid, 'classdef %s < %s\n', ename, baseType);
    fprintf(efid, '   enumeration\n');
    for r = 1:height(members)
        label = strtrim(string(members.EnumNumbers(r)));
        if ismissing(label) || strlength(label) == 0, continue; end
        fprintf(efid, '      %s (%s)\n', label, fmtVal(members.Value(r)));
    end
    fprintf(efid, '   end\n');
    fprintf(efid, 'end\n');
    fclose(efid);
    fprintf('   [OK] 枚举文件: %s\n', ePath);
end
end
