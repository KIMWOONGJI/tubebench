function p = uniqueName(p)
%UNIQUENAME Append _2, _3, ... until the file/folder does not exist (no overwrite).
if ~exist(p, 'file') && ~exist(p, 'dir'), return; end
[d, n, e] = fileparts(p);
k = 2;
while true
    q = fullfile(d, sprintf('%s_%d%s', n, k, e));
    if ~exist(q, 'file') && ~exist(q, 'dir'), p = q; return; end
    k = k + 1;
end
end
