classdef TestSoftwareInfo < matlab.unittest.TestCase
    %TESTSOFTWAREINFO Software version, repository URL and Git commit (no git.exe needed).

    properties
        tmp
    end

    methods (TestMethodSetup)
        function setup(tc)
            f = tc.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            tc.tmp = f.Folder;
        end
    end

    methods (Test)
        function repositoryAddress(tc)
            tc.verifyEqual(tim.app.repositoryUrl(), 'https://github.com/kimwoongji/tubebench');
            [v, info] = tim.app.softwareVersion();
            tc.verifyClass(v, 'char');
            tc.verifySubstring(v, 'tubebench');   % program name (until 2026-10-10: transfer-impedance-tube-measurement)
            tc.verifyEqual(info.name, 'tubebench');
            tc.verifyEqual(tim.app.defaultConfig().projectName, 'tubebench');
            tc.verifyEqual(info.repository, tim.app.repositoryUrl());
            if strcmp(info.commit, 'unknown')
                tc.verifyEmpty(strfind(v, 'commit'));
            else
                tc.verifyMatches(info.commit, '^[0-9a-f]{40}$');
                tc.verifySubstring(v, ['commit ' info.commit(1:7)]);
            end
        end

        function launchersAndProjectName(tc)
            % user decision 2026-10-10: program renamed to tubebench; tubebench.m /
            % start_tubebench.bat start it. 2026-10-11: the old names (tubeapp,
            % start_tubeapp.bat, class tim.gui.TubeApp) removed
            root = tim.app.projectRoot();
            tc.verifyEqual(which('tubebench'), fullfile(root, 'tubebench.m'));
            tc.verifyEqual(exist(fullfile(root, '+tim', '+gui', 'Tubebench.m'), 'file'), 2);
            for old = {'tubeapp.m', 'start_tubeapp.bat', fullfile('+tim', '+gui', 'TubeApp.m')}
                tc.verifyFalse(isfile(fullfile(root, old{1})), ['old name removed: ' old{1}]);
            end
            tc.verifyError(@() tubebench('no_such_config.json'), 'tubebench:config');
            bat = tim.app.readTextUtf8(fullfile(root, 'start_tubebench.bat'));
            tc.verifySubstring(bat, '-r "tubebench(''%MODE%'')"');
            % user choice 2026-10-10 ("D"): MATLAB without its desktop (faster start);
            % MATLAB is not quit automatically (no exit after tubebench)
            tc.verifySubstring(bat, '-nodesktop -nosplash -sd "%ROOT%"');
            tc.verifyFalse(contains(regexp(bat, '-r "[^"]*"', 'match', 'once'), 'exit'), ...
                'MATLAB keeps running after the program is closed');
            for f = {'user_config.json', 'example_config.json', 'sim_thin_screen.json'}
                cfg = jsondecode(tim.app.readTextUtf8(fullfile(root, 'config', f{1})));
                tc.verifyEqual(cfg.projectName, 'tubebench', f{1});
            end
        end

        function commitFromLooseRef(tc)
            h = repmat('a1', 1, 20);
            mk(tc.tmp, '.git/HEAD', sprintf('ref: refs/heads/main\n'));
            mk(tc.tmp, '.git/refs/heads/main', sprintf('%s\n', h));
            [c, b] = tim.app.gitCommit(tc.tmp);
            tc.verifyEqual(c, h); tc.verifyEqual(b, 'main');
        end

        function commitFromPackedRefs(tc)
            h = repmat('b2', 1, 20);
            mk(tc.tmp, '.git/HEAD', sprintf('ref: refs/heads/dev\n'));
            mk(tc.tmp, '.git/packed-refs', sprintf('# pack-refs with: peeled fully-peeled sorted\n%s refs/heads/dev\n%s refs/heads/main\n', ...
                h, repmat('c3', 1, 20)));
            [c, b] = tim.app.gitCommit(tc.tmp);
            tc.verifyEqual(c, h); tc.verifyEqual(b, 'dev');
        end

        function detachedHeadAndWorktree(tc)
            h = repmat('d4', 1, 20);
            mk(tc.tmp, 'repo/.git/HEAD', sprintf('%s\n', h));
            [c, b] = tim.app.gitCommit(fullfile(tc.tmp, 'repo'));
            tc.verifyEqual(c, h); tc.verifyEqual(b, '');
            % worktree: .git is a file pointing to .git/worktrees/wt, refs in the common dir
            common = fullfile(tc.tmp, 'main', '.git');
            mk(tc.tmp, 'main/.git/refs/heads/feature', sprintf('%s\n', repmat('e5', 1, 20)));
            mk(tc.tmp, 'main/.git/worktrees/wt/HEAD', sprintf('ref: refs/heads/feature\n'));
            mk(tc.tmp, 'main/.git/worktrees/wt/commondir', sprintf('../..\n'));
            mk(tc.tmp, 'wt/.git', sprintf('gitdir: %s\n', fullfile(common, 'worktrees', 'wt')));
            [c, b] = tim.app.gitCommit(fullfile(tc.tmp, 'wt'));
            tc.verifyEqual(c, repmat('e5', 1, 20)); tc.verifyEqual(b, 'feature');
        end

        function noRepositoryIsUnknown(tc)
            [c, b] = tim.app.gitCommit(tc.tmp);              % empty folder (ZIP copy)
            tc.verifyEqual(c, 'unknown'); tc.verifyEqual(b, '');
            mk(tc.tmp, 'bad/.git/HEAD', sprintf('ref: refs/heads/missing\n'));
            tc.verifyEqual(tim.app.gitCommit(fullfile(tc.tmp, 'bad')), 'unknown');
        end
    end
end

function mk(root, rel, txt)
f = fullfile(root, strrep(rel, '/', filesep));
if ~isfolder(fileparts(f)), mkdir(fileparts(f)); end
fid = fopen(f, 'w'); fwrite(fid, txt); fclose(fid);
end
