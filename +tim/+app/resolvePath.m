function p = resolvePath(p)
%RESOLVEPATH Absolute paths are returned unchanged; relative paths are
%   resolved against the project root.
if isempty(regexp(p, '^([A-Za-z]:[\\/]|[\\/])', 'once'))
    p = fullfile(tim.app.projectRoot(), p);
end
end
