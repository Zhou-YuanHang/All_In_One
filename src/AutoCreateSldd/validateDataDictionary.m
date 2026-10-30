function [isValid, issues] = validateDataDictionary(fullpath, selectedSheets)
% VALIDATEDATADICTIONARY 校验 Excel 数据字典模板的完整性与关键关联关系
%
% 输入参数：
%   fullpath      - Excel 文件完整路径
%   selectedSheets - 参与本次导入的工作表列表（可选）
%
% 输出参数：
%   isValid - 是否通过校验
%   issues  - 校验失败项（cell 数组）
%
% 校验内容：
%   1. 必要列是否存在
%   2. 必填单元格是否为空
%   3. Signal / Parameter 变量名是否重复
%   4. Bus 名称是否重复
%   5. BusElement 是否引用了未定义的 Bus
%   6. Signal / Parameter 的 DataType=Bus:xxx 是否引用了已选择且已定义的 Bus

if nargin < 2 || isempty(selectedSheets)
    selectedSheets = {'Signal', 'Parameter', 'Bus', 'BusElement'};
end

selectedSheets = cellstr(string(selectedSheets));

requiredColumns = struct( ...
    'Signal',     {{'VariableName','Package','Object','CustomStorageClass','DataType'}}, ...
    'Parameter',  {{'VariableName','Package','Object','CustomStorageClass','DataType','InitialValue'}}, ...
    'Bus',        {{'BusName','HeaderFile','Alignment','PreserveElementDimensions','DataScope'}}, ...
    'BusElement', {{'BusName','ElementName','DataType','Dimensions'}} ...
    );

knownSheets = fieldnames(requiredColumns);
selectedSheets = selectedSheets(ismember(selectedSheets, knownSheets));

issues = cell(0, 1);
sheetTables = struct();
sheetColumns = struct();

for i = 1:numel(selectedSheets)
    sheetName = selectedSheets{i};
    [dataTable, readIssue] = readSheetAsStrings(fullpath, sheetName);
    if ~isempty(readIssue)
        issues{end+1,1} = sprintf('工作表 %s 读取失败：%s', sheetName, readIssue); %#ok<AGROW>
        continue;
    end

    columnNames = dataTable.Properties.VariableNames;
    [ok, missing] = checkRequiredColumnsLocal(requiredColumns.(sheetName), columnNames);
    if ~ok
        issues{end+1,1} = sprintf('工作表 %s 缺少必要列：%s', sheetName, strjoin(missing, ', ')); %#ok<AGROW>
        continue;
    end

    issues = [issues; collectRequiredValueIssues(sheetName, dataTable, columnNames, requiredColumns.(sheetName))]; %#ok<AGROW>
    sheetTables.(sheetName) = dataTable;
    sheetColumns.(sheetName) = columnNames;
end

issues = [issues; collectDuplicateVariableIssues(sheetTables)];
issues = [issues; collectDuplicateBusIssues(sheetTables, sheetColumns)];
issues = [issues; collectBusReferenceIssues(sheetTables, sheetColumns, selectedSheets)];
issues = [issues; collectDataTypeBusReferenceIssues(sheetTables, sheetColumns, selectedSheets)];


isValid = isempty(issues);

if nargout == 0
    printValidationSummary(isValid, issues);
end
end


function [dataTable, readIssue] = readSheetAsStrings(fullpath, sheetName)
    try
        opts = detectImportOptions(fullpath, 'Sheet', sheetName);
        opts = setvartype(opts, opts.VariableNames, 'string');
        dataTable = readtable(fullpath, opts);
        readIssue = '';
    catch ME
        dataTable = table();
        readIssue = ME.message;
    end
end


function issues = collectRequiredValueIssues(sheetName, dataTable, columnNames, requiredCols)
    issues = cell(0, 1);

    for i = 1:numel(requiredCols)
        requiredName = requiredCols{i};
        actualName = getActualColumnNameLocal(requiredName, columnNames);
        values = normalizeStringArray(dataTable.(actualName));
        missingRows = find(strlength(values) == 0);
        if isempty(missingRows)
            continue;
        end

        rowTokens = arrayfun(@(n) sprintf('%d', n + 1), missingRows, 'UniformOutput', false);
        rowList = strjoin(rowTokens, ', ');
        issues{end+1,1} = sprintf('工作表 %s 的必填列 %s 在第 %s 行为空。', sheetName, requiredName, rowList); %#ok<AGROW>
    end
end


function issues = collectDuplicateVariableIssues(sheetTables)
    issues = cell(0, 1);
    names = strings(0, 1);
    sources = strings(0, 1);
    rowNumbers = zeros(0, 1);

    targetSheets = {'Signal', 'Parameter'};
    for i = 1:numel(targetSheets)
        sheetName = targetSheets{i};
        if ~isfield(sheetTables, sheetName)
            continue;
        end

        dataTable = sheetTables.(sheetName);
        columnNames = dataTable.Properties.VariableNames;
        actualName = getActualColumnNameLocal('VariableName', columnNames);
        values = normalizeStringArray(dataTable.(actualName));
        validIdx = find(strlength(values) > 0);

        names = [names; lower(values(validIdx))]; %#ok<AGROW>
        sources = [sources; repmat(string(sheetName), numel(validIdx), 1)]; %#ok<AGROW>
        rowNumbers = [rowNumbers; validIdx + 1]; %#ok<AGROW>
    end

    if isempty(names)
        return;
    end

    [uniqueNames, ~, groupIdx] = unique(names);
    for i = 1:numel(uniqueNames)
        duplicateIdx = find(groupIdx == i);
        if numel(duplicateIdx) < 2
            continue;
        end

        locations = arrayfun(@(idx) sprintf('%s 第 %d 行', sources(idx), rowNumbers(idx)), duplicateIdx, 'UniformOutput', false);
        issues{end+1,1} = sprintf('变量名 %s 重复出现：%s。', char(uniqueNames(i)), strjoin(locations, '；')); %#ok<AGROW>
    end
end


function issues = collectDuplicateBusIssues(sheetTables, sheetColumns)
    issues = cell(0, 1);
    if ~isfield(sheetTables, 'Bus')
        return;
    end

    dataTable = sheetTables.Bus;
    columnNames = sheetColumns.Bus;
    actualName = getActualColumnNameLocal('BusName', columnNames);
    values = normalizeStringArray(dataTable.(actualName));
    validIdx = find(strlength(values) > 0);
    values = lower(values(validIdx));
    rowNumbers = validIdx + 1;

    if isempty(values)
        return;
    end

    [uniqueNames, ~, groupIdx] = unique(values);
    for i = 1:numel(uniqueNames)
        duplicateIdx = find(groupIdx == i);
        if numel(duplicateIdx) < 2
            continue;
        end

        rowTokens = arrayfun(@(idx) sprintf('%d', rowNumbers(idx)), duplicateIdx, 'UniformOutput', false);
        issues{end+1,1} = sprintf('Bus 名称 %s 在 Bus 工作表中重复出现：第 %s 行。', char(uniqueNames(i)), strjoin(rowTokens, ', ')); %#ok<AGROW>
    end
end


function issues = collectBusReferenceIssues(sheetTables, sheetColumns, selectedSheets)
    issues = cell(0, 1);
    if ~isfield(sheetTables, 'BusElement')
        return;
    end

    if ~ismember('Bus', selectedSheets) || ~isfield(sheetTables, 'Bus')
        issues{1,1} = '已选择 BusElement，但未同时选择 Bus；请一并勾选 Bus 后再导入。';
        return;
    end

    busTable = sheetTables.Bus;
    busColNames = sheetColumns.Bus;
    busNameCol = getActualColumnNameLocal('BusName', busColNames);
    definedBusNames = lower(normalizeStringArray(busTable.(busNameCol)));
    definedBusNames = unique(definedBusNames(strlength(definedBusNames) > 0));

    busElementTable = sheetTables.BusElement;
    busElementColNames = sheetColumns.BusElement;
    refBusCol = getActualColumnNameLocal('BusName', busElementColNames);
    refBusNames = normalizeStringArray(busElementTable.(refBusCol));
    validIdx = find(strlength(refBusNames) > 0);

    if isempty(validIdx)
        return;
    end

    distinctRefs = unique(lower(refBusNames(validIdx)));
    missingRefs = distinctRefs(~ismember(distinctRefs, definedBusNames));

    for i = 1:numel(missingRefs)
        missingRef = missingRefs(i);
        rowIdx = find(strcmpi(refBusNames, missingRef));
        rowTokens = arrayfun(@(n) sprintf('%d', n + 1), rowIdx, 'UniformOutput', false);
        displayName = refBusNames(rowIdx(1));
        issues{end+1,1} = sprintf('BusElement 引用了未在 Bus 表中定义的 Bus %s：第 %s 行。', char(displayName), strjoin(rowTokens, ', ')); %#ok<AGROW>
    end
end



function issues = collectDataTypeBusReferenceIssues(sheetTables, sheetColumns, selectedSheets)
    issues = cell(0, 1);
    targetSheets = {'Signal', 'Parameter'};

    hasTargetSheet = any(cellfun(@(sheetName) isfield(sheetTables, sheetName), targetSheets));
    if ~hasTargetSheet
        return;
    end

    hasBusSheet = ismember('Bus', selectedSheets) && isfield(sheetTables, 'Bus');
    definedBusNames = strings(0, 1);
    if hasBusSheet
        busTable = sheetTables.Bus;
        busColNames = sheetColumns.Bus;
        busNameCol = getActualColumnNameLocal('BusName', busColNames);
        definedBusNames = lower(normalizeStringArray(busTable.(busNameCol)));
        definedBusNames = unique(definedBusNames(strlength(definedBusNames) > 0));
    end

    for i = 1:numel(targetSheets)
        sheetName = targetSheets{i};
        if ~isfield(sheetTables, sheetName)
            continue;
        end

        dataTable = sheetTables.(sheetName);
        columnNames = sheetColumns.(sheetName);
        dataTypeCol = getActualColumnNameLocal('DataType', columnNames);
        dataTypeValues = normalizeStringArray(dataTable.(dataTypeCol));
        refBusNames = extractBusTypeNames(dataTypeValues);
        validIdx = find(strlength(refBusNames) > 0);

        if isempty(validIdx)
            continue;
        end

        distinctRefs = unique(lower(refBusNames(validIdx)));
        if ~hasBusSheet
            for j = 1:numel(distinctRefs)
                missingRef = distinctRefs(j);
                rowIdx = find(strcmpi(refBusNames, missingRef));
                rowTokens = arrayfun(@(n) sprintf('%d', n + 1), rowIdx, 'UniformOutput', false);
                displayName = refBusNames(rowIdx(1));
                issues{end+1,1} = sprintf('%s 的 DataType 引用了 Bus %s，但未同时选择 Bus：第 %s 行。', sheetName, char(displayName), strjoin(rowTokens, ', ')); %#ok<AGROW>
            end
            continue;
        end

        missingRefs = distinctRefs(~ismember(distinctRefs, definedBusNames));
        for j = 1:numel(missingRefs)
            missingRef = missingRefs(j);
            rowIdx = find(strcmpi(refBusNames, missingRef));
            rowTokens = arrayfun(@(n) sprintf('%d', n + 1), rowIdx, 'UniformOutput', false);
            displayName = refBusNames(rowIdx(1));
            issues{end+1,1} = sprintf('%s 的 DataType 引用了未在 Bus 表中定义的 Bus %s：第 %s 行。', sheetName, char(displayName), strjoin(rowTokens, ', ')); %#ok<AGROW>
        end
    end
end



function busNames = extractBusTypeNames(dataTypeValues)
    dataTypeValues = normalizeStringArray(dataTypeValues);
    busNames = strings(size(dataTypeValues));

    for i = 1:numel(dataTypeValues)
        tokens = regexpi(char(dataTypeValues(i)), '^\s*bus\s*:\s*(.+?)\s*$', 'tokens', 'once');
        if isempty(tokens)
            continue;
        end

        busNames(i) = strtrim(string(tokens{1}));
    end
end


function [allExist, missingList] = checkRequiredColumnsLocal(requiredCols, columnNames)

    missingList = cell(0, 1);
    for i = 1:numel(requiredCols)
        if ~checkColumnExistsLocal(requiredCols{i}, columnNames)
            missingList{end+1,1} = requiredCols{i}; %#ok<AGROW>
        end
    end
    allExist = isempty(missingList);
end


function exists = checkColumnExistsLocal(colName, columnNames)
    normName = erase(string(colName), ' ');
    normNames = erase(string(columnNames), ' ');
    exists = any(strcmpi(normName, normNames));
end


function actualName = getActualColumnNameLocal(colName, columnNames)
    if any(strcmpi(colName, columnNames))
        actualName = columnNames{find(strcmpi(colName, columnNames), 1, 'first')};
        return;
    end

    normName = erase(string(colName), ' ');
    normNames = erase(string(columnNames), ' ');
    matchIdx = find(strcmpi(normName, normNames), 1, 'first');
    if isempty(matchIdx)
        actualName = colName;
    else
        actualName = columnNames{matchIdx};
    end
end


function values = normalizeStringArray(values)
    if iscell(values)
        values = string(values);
    end

    values = strtrim(string(values));
    values(ismissing(values)) = "";
end


function printValidationSummary(isValid, issues)
    if isValid
        fprintf('\n=============== 校验通过 ===============\n');
        fprintf('模板结构、必填项和关键关联关系均通过检查。\n');
        return;
    end

    fprintf('\n=============== 校验失败 ===============\n');
    for i = 1:numel(issues)
        fprintf('%d) %s\n', i, issues{i});
    end
    fprintf('请修正 Excel 后重新运行。\n');
end
