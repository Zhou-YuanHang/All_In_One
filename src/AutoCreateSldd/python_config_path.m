function cfgPath = python_config_path()
%PYTHON_CONFIG_PATH Python 路径配置文件（python_config.json）的默认位置
%   默认与 GUI / 脚本同目录；取不到脚本目录时退回当前工作目录。
%
%   cfgPath = python_config_path()
%
%   该文件由 GUI 二级界面「Python 路径设置…」(sldd_python_config.m) 写入，
%   由 getPythonExe.m 读取 —— 它是本程序 Python 路径的唯一来源。

try
    here = fileparts(mfilename('fullpath'));
catch
    here = '';
end
if isempty(here)
    here = pwd;
end

cfgPath = fullfile(here, 'python_config.json');
end
