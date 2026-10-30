function results = runAll(varargin)
%RUNALL 运行全部 matlab.unittest 测试；适合 matlab -batch "runAll"。
%   用法：results = runAll()  或  results = runAll('Verbosity', 2)
here = fileparts(mfilename('fullpath'));
root = fileparts(here);
addpath(fullfile(root, 'app'));
addpath(here);
if nargin >= 2
    results = runtests(here, 'IncludeSubfolders', true, varargin{1}, varargin{2});
else
    results = runtests(here, 'IncludeSubfolders', true);
end
disp(table(results));
if any([results.Failed])
    error('swb:testFailed', '%d 个测试失败', sum([results.Failed]));
end
end
