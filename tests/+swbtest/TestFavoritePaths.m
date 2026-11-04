classdef TestFavoritePaths < swbtest.SwbTestBase
    %SWBTEST.TESTFAVORITEPATHS 设置页「常用路径」功能：持久化、增删、切换与打开。

    properties (Constant)
        P = 'swbFav_';
    end

    methods (Test)
        function testSettingsFavoriteRoundTrip(tc)
            % 添加的常用路径要持久化到 JSON 并能重读
            f = fullfile(tc.tmpDir(), 'fav_settings.json');
            s = swb.Settings(f);
            d1 = tc.tmpDir();  % 存活的临时目录（teardown 才删）
            s.addFavoritePath(d1);
            tc.verifyEqual(s.FavoritePaths, {d1});
            s2 = swb.Settings(f);
            tc.verifyEqual(s2.FavoritePaths, {d1});
        end

        function testFavoriteDedupAndRemove(tc)
            % 重复添加去重置顶；删除后不再出现；不存在/空路径被忽略
            f = fullfile(tc.tmpDir(), 'fav2.json');
            s = swb.Settings(f);
            d1 = tc.tmpDir();
            d2 = tc.tmpDir();
            s.addFavoritePath(d1);
            s.addFavoritePath(d2);
            tc.verifyEqual(s.FavoritePaths, {d2, d1});   % 最新在前
            s.addFavoritePath(d1);                       % 重复 → 置顶
            tc.verifyEqual(s.FavoritePaths, {d1, d2});
            s.addFavoritePath(fullfile(d1, 'no_such_sub'));  % 不是文件夹 → 忽略
            s.addFavoritePath('   ');                        % 空 → 忽略
            tc.verifyEqual(s.FavoritePaths, {d1, d2});
            s.removeFavoritePath(d1);
            tc.verifyEqual(s.FavoritePaths, {d2});
            s.removeFavoritePath('D:/never_added');      % 删不存在的也不报错
            tc.verifyEqual(s.FavoritePaths, {d2});
        end

        function testFavoritePanelExists(tc)
            % 应有独立的「常用路径」选项卡，含表格和四个操作按钮
            app = SimWorkbench('Visible', 'off');
            tc.addTeardown(@() delete(app));
            tabObjs = findall(app.TabGroup, 'Type', 'uitab');
            tc.verifyTrue(any(strcmp(arrayfun(@(x) x.Title, tabObjs, 'UniformOutput', false), '常用路径')), '应有常用路径选项卡');
            tc.verifyClass(app.H.favTable, 'matlab.ui.control.Table');
            tc.verifyTrue(all(isfield(app.H, {'favNewEdit', 'favStatus'})));
            src = fileread(which('SimWorkbench'));
            tc.verifyTrue(contains(src, 'onFavGoTo'), '应有切换目录回调');
            tc.verifyTrue(contains(src, 'onFavOpenExplorer'), '应有资源管理器回调');
            tc.verifyTrue(contains(src, 'onFavBrowseAdd'), '应有浏览添加回调');
            tc.verifyTrue(contains(src, 'onFavRemove'), '应有删除回调');
        end

        function testFavoriteTableShowsPaths(tc)
            % Settings 里的路径应显示在表格里；删除回调能同步表格
            f = fullfile(tc.tmpDir(), 'fav3.json');
            d1 = tc.tmpDir();
            app = SimWorkbench('Visible', 'off', 'SettingsFile', f);
            tc.addTeardown(@() delete(app));
            app.Settings.addFavoritePath(d1);
            app.refreshFavoritePaths();
            tc.verifyEqual(numel(app.H.favTable.Data), 1);
            tc.verifyEqual(char(app.H.favTable.Data{1}), char(d1));
            % 模拟选中第 1 行后删除
            app.H.favSelectedRow = 1;
            app.onFavRemove();
            tc.verifyEqual(numel(app.Settings.FavoritePaths), 0);
            tc.verifyEqual(numel(app.H.favTable.Data), 0);
        end

        function testFavGoToSwitchesDir(tc)
            % 「切换到该文件夹」应 cd 到选中路径
            f = fullfile(tc.tmpDir(), 'fav4.json');
            d1 = tc.tmpDir();
            app = SimWorkbench('Visible', 'off', 'SettingsFile', f);
            tc.addTeardown(@() delete(app));
            app.Settings.addFavoritePath(d1);
            app.refreshFavoritePaths();
            oldDir = pwd;
            tc.addTeardown(@() cd(oldDir));
            app.H.favSelectedRow = 1;
            app.onFavGoTo();
            tc.verifyEqual(pwd, d1);
            tc.verifyTrue(contains(char(app.H.favStatus.Text), '已切换'));
        end

        function testFavAddFromEdit(tc)
            % 输入框路径 + onFavAdd 直接添加并刷新表格
            f = fullfile(tc.tmpDir(), 'fav5.json');
            d1 = tc.tmpDir();
            app = SimWorkbench('Visible', 'off', 'SettingsFile', f);
            tc.addTeardown(@() delete(app));
            app.H.favNewEdit.Value = d1;
            app.onFavAdd();
            tc.verifyEqual(app.Settings.FavoritePaths, {d1});
            tc.verifyEqual(numel(app.H.favTable.Data), 1);
            tc.verifyEqual(char(app.H.favNewEdit.Value), '');
            % 无效路径不添加
            app.H.favNewEdit.Value = fullfile(d1, 'missing');
            app.onFavAdd();
            tc.verifyEqual(numel(app.Settings.FavoritePaths), 1);
        end
    end
end