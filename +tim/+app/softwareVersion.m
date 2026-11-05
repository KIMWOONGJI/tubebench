function [v, info] = softwareVersion()
%SOFTWAREVERSION Version of this measurement software (tubebench).
%
%   v = tim.app.softwareVersion()
%     'tubebench 1.2.1 (2026-10-12) commit b9a3dca'
%     (no commit part when the code is not a Git working copy)
%   [v, info] = tim.app.softwareVersion()
%     info.name, .version, .released, .repository (GitHub URL),
%     .commit (40 hex or 'unknown'), .branch - stored with every measurement.

name = 'tubebench';                     % until 2026-10-10: transfer-impedance-tube-measurement
number = '1.6.2'; released = '2026-11-05';
[commit, branch] = tim.app.gitCommit();
v = sprintf('%s %s (%s)', name, number, released);
if ~strcmp(commit, 'unknown'), v = sprintf('%s commit %s', v, commit(1:7)); end
info = struct('name', name, 'version', number, 'released', released, ...
    'repository', tim.app.repositoryUrl(), 'commit', commit, 'branch', branch);
end
