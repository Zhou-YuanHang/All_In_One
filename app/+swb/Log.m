classdef Log < handle
    %SWB.LOG 统一日志/状态/进度事件源。
    %   UI 订阅 Callback，测试直接读 Entries。服务层所有输出都走这里，
    %   不再各自写状态栏（旧工具三个 setStatus 实现的问题）。

    properties
        Entries = struct('time', {}, 'level', {}, 'message', {})
        Callback = []          % @(entry) struct('time','level','message')
        MaxEntries = 5000
        Progress = 0           % 0..1
        ProgressMessage = ''
        ProgressCallback = []  % @(fraction, message)
    end

    methods
        function obj = Log(callback)
            if nargin >= 1 && ~isempty(callback)
                obj.Callback = callback;
            end
        end

        function info(obj, fmt, varargin)
            obj.add('info', swb.Log.format(fmt, varargin{:}));
        end

        function warn(obj, fmt, varargin)
            obj.add('warn', swb.Log.format(fmt, varargin{:}));
        end

        function err(obj, fmt, varargin)
            obj.add('error', swb.Log.format(fmt, varargin{:}));
        end

        function debug(obj, fmt, varargin)
            obj.add('debug', swb.Log.format(fmt, varargin{:}));
        end

        function section(obj, fmt, varargin)
            obj.add('section', swb.Log.format(fmt, varargin{:}));
        end

        function add(obj, level, message)
            entry = struct('time', char(datetime('now', 'Format', 'HH:mm:ss')), ...
                           'level', char(level), 'message', char(message));
            obj.Entries(end+1) = entry;
            if numel(obj.Entries) > obj.MaxEntries
                obj.Entries(1:ceil(obj.MaxEntries * 0.1)) = [];
            end
            if ~isempty(obj.Callback)
                try
                    obj.Callback(entry);
                catch
                    % UI 回调异常不能影响业务
                end
            end
        end

        function progress(obj, fraction, fmt, varargin)
            obj.Progress = max(0, min(1, fraction));
            obj.ProgressMessage = swb.Log.format(fmt, varargin{:});
            if ~isempty(obj.ProgressCallback)
                try
                    obj.ProgressCallback(obj.Progress, obj.ProgressMessage);
                catch
                end
            end
        end

        function txt = text(obj)
            if isempty(obj.Entries)
                txt = '';
                return;
            end
            lines = cell(1, numel(obj.Entries));
            for k = 1:numel(obj.Entries)
                e = obj.Entries(k);
                lines{k} = sprintf('[%s] %-7s %s', e.time, upper(e.level), e.message);
            end
            txt = strjoin(lines, newline);
        end

        function clear(obj)
            obj.Entries = struct('time', {}, 'level', {}, 'message', {});
        end

        function n = count(obj, level)
            if isempty(obj.Entries)
                n = 0;
                return;
            end
            n = sum(strcmp({obj.Entries.level}, level));
        end

        function tf = hasErrors(obj)
            tf = obj.count('error') > 0;
        end
    end

    methods (Static)
        function s = format(fmt, varargin)
            if isempty(varargin)
                s = char(fmt);
            else
                s = sprintf(fmt, varargin{:});
            end
        end
    end
end
