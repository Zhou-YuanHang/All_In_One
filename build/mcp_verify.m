function out = mcp_verify(varargin)
%MCP_VERIFY 在可见桌面 MATLAB 会话中（经 MCP 调用）跑一遍流水线冒烟 + 全量回归。
%   报告写入 build/mcp_verify_report.txt（UTF-8），并在命令窗口打印 ASCII 标记。
%   out = mcp_verify()  或  out = mcp_verify('SkipTests', true)

p = inputParser;
p.addParameter('SkipTests', false);
p.parse(varargin{:});

root = fileparts(fileparts(mfilename('fullpath')));
if isempty(root) || ~isfolder(fullfile(root, 'app'))
    root = 'F:\GithubRepos\All_In_One';
end
addpath(fullfile(root, 'app'));
addpath(fullfile(root, 'tests'));

reportFile = fullfile(root, 'build', 'mcp_verify_report.txt');
fid = fopen(reportFile, 'w', 'n', 'UTF-8');
cleanup = onCleanup(@() fclose(fid));

    function say(fmt, varargin)
        fprintf(fmt, varargin{:});
        fprintf(fid, fmt, varargin{:});
    end

out = struct('pipelineOk', false, 'testTotal', 0, 'testPassed', 0, ...
             'testFailed', 0, 'testIncomplete', 0, 'seconds', 0);

say('=== MCP verify ===\n');
say('TIME=%s\n', datestr(now, 'yyyy-mm-dd HH:MM:SS'));
say('MATLAB=%s\n', version);
say('DESKTOP=%d\n', usejava('desktop'));
say('ROOT=%s\n', root);

% ---- 1. 一键流水线冒烟 ----
tmp = tempname();
mkdir(tmp);
try
    dictFile = swbfixture.Workbooks.makeDict(tmp);
    portFile = swbfixture.Workbooks.makePort(tmp);
    cfg = struct();
    cfg.DictWorkbook = dictFile;
    cfg.PortWorkbook = portFile;
    cfg.SlddFile = fullfile(tmp, 'mcp_smoke.sldd');
    model = swb.Schema.modelConfigDefaults();
    model.ModelName = 'mcp_smoke';
    model.ModelFolder = tmp;
    model.DictFile = cfg.SlddFile;
    model.PortWorkbook = portFile;
    model.OpenAfterCreate = false;
    cfg.Model = model;
    r = swb.Pipeline.run(cfg);
    out.pipelineOk = logical(r.ok);
    nSteps = numel(r.steps);
    say('PIPELINE_OK=%d STEPS=%d\n', out.pipelineOk, nSteps);
    for k = 1:nSteps
        say('  STEP[%d] %s -> %s %s\n', k, r.steps(k).name, r.steps(k).status, r.steps(k).detail);
    end
    if isfield(r, 'summary') && ~isempty(r.summary)
        say('PIPELINE_SUMMARY=%s\n', strrep(r.summary, newline, ' | '));
    end
catch ME
    say('PIPELINE_EXCEPTION=%s\n', ME.message);
    for k = 1:numel(ME.stack)
        say('  at %s:%d\n', ME.stack(k).name, ME.stack(k).line);
    end
end

% ---- 2. 全量回归 ----
if ~p.Results.SkipTests
    t0 = tic;
    try
        res = runtests(fullfile(root, 'tests'), 'IncludeSubfolders', true);
        out.seconds = toc(t0);
        out.testTotal = numel(res);
        out.testPassed = sum([res.Passed]);
        out.testFailed = sum([res.Failed]);
        out.testIncomplete = sum([res.Incomplete]);
        say('TEST_TOTAL=%d PASSED=%d FAILED=%d INCOMPLETE=0->%d SECONDS=%.2f\n', ...
            out.testTotal, out.testPassed, out.testFailed, out.testIncomplete, out.seconds);
        if out.testFailed > 0
            for k = 1:numel(res)
                if res(k).Failed
                    say('FAILED_TEST=%s\n', res(k).Name);
                end
            end
        end
    catch ME
        out.seconds = toc(t0);
        say('TEST_EXCEPTION=%s\n', ME.message);
    end
else
    say('TESTS_SKIPPED=1\n');
end

% ---- 3. GUI 冒烟（不打开窗口，只验证构造与销毁） ----
try
    app = SimWorkbench();
    say('APP_CONSTRUCT_OK=1 CLASS=%s\n', class(app));
    delete(app);
    say('APP_DELETE_OK=1\n');
catch ME
    say('APP_EXCEPTION=%s\n', ME.message);
end

say('REPORT=%s\n', reportFile);
say('=== done ===\n');
end
