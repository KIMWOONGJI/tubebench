function [commit, branch] = gitCommit(root)
%GITCOMMIT Commit (40 hex) and branch of a Git working copy, read from .git.
%
%   [commit, branch] = tim.app.gitCommit()         % this project
%   [commit, branch] = tim.app.gitCommit(folder)
%
%   Needs no git.exe (it is not on the PATH of the lab PC). commit =
%   'unknown' without a readable repository (ZIP copy, compiled app);
%   branch = '' for a detached HEAD. Uncommitted changes are NOT detected.

if nargin < 1, root = tim.app.projectRoot(); end
commit = 'unknown'; branch = '';
try
    gd = fullfile(root, '.git');
    if isfile(gd)                                   % worktree / submodule: "gitdir: <path>"
        p = strtrim(regexprep(fileread(gd), '^gitdir:\s*', ''));
        if ~isAbsolute(p), p = fullfile(root, p); end
        gd = p;
    end
    if ~isfolder(gd), return; end
    common = gd;                                    % refs of a worktree live in the common dir
    if isfile(fullfile(gd, 'commondir'))
        p = strtrim(fileread(fullfile(gd, 'commondir')));
        if ~isAbsolute(p), p = fullfile(gd, p); end
        common = p;
    end
    head = strtrim(fileread(fullfile(gd, 'HEAD')));
    c = '';
    if startsWith(head, 'ref:')
        ref = strtrim(extractAfter(head, 'ref:'));
        branch = regexprep(ref, '^refs/heads/', '');
        for d = {gd, common}
            f = fullfile(d{1}, strrep(ref, '/', filesep));
            if isfile(f), c = strtrim(fileread(f)); break; end
        end
        if isempty(c) && isfile(fullfile(common, 'packed-refs'))
            tok = regexp(fileread(fullfile(common, 'packed-refs')), ...
                ['^([0-9a-f]{40}) ' regexptranslate('escape', ref) '\s*$'], 'tokens', 'once', 'lineanchors');
            if ~isempty(tok), c = tok{1}; end
        end
    else
        c = head;                                   % detached HEAD
    end
    if ~isempty(regexp(c, '^[0-9a-f]{40}$', 'once')), commit = c; end
catch
    commit = 'unknown';
end
end

function tf = isAbsolute(p)
tf = ~isempty(regexp(p, '^([A-Za-z]:[\\/]|[\\/]{2}|/)', 'once'));
end
