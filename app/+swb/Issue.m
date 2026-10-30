classdef Issue
    %SWB.ISSUE 统一问题条目（校验/端口/流程共用）。
    %   struct 数组字段：sheet, row, column, severity('error'|'warning'|'info'), message

    methods (Static)
        function s = empty()
            s = struct('sheet', {}, 'row', {}, 'column', {}, 'severity', {}, 'message', {});
        end

        function s = make(sheet, row, column, severity, message)
            s = struct('sheet', char(sheet), 'row', row, 'column', char(column), ...
                       'severity', char(severity), 'message', char(message));
        end

        function all = concat(a, b)
            all = [a(:); b(:)]';
        end

        function n = count(list, severity)
            if isempty(list)
                n = 0;
            else
                n = sum(strcmp({list.severity}, severity));
            end
        end

        function tf = hasErrors(list)
            tf = swb.Issue.count(list, 'error') > 0;
        end

        function txt = format(list)
            if isempty(list)
                txt = '';
                return;
            end
            lines = cell(1, numel(list));
            for k = 1:numel(list)
                it = list(k);
                if isnan(it.row)
                    loc = it.sheet;
                else
                    loc = sprintf('%s!%s%d', it.sheet, it.column, it.row);
                end
                lines{k} = sprintf('[%s] %s: %s', upper(it.severity), loc, it.message);
            end
            txt = strjoin(lines, newline);
        end
    end
end
