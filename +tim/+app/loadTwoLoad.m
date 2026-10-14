function p = loadTwoLoad(folder)
%LOADTWOLOAD Open a two-load pair folder or pair measurement folders (WO-005).
%
%   p = tim.app.loadTwoLoad(pairFolder)
%       A folder written by tim.app.saveTwoLoad: its twoload.json names the
%       load folders (in the same data folder); their raw data and
%       configurations are loaded for reprocessing.
%   p = tim.app.loadTwoLoad({folderA, folderB[, folderA2]})
%       Saved measurement folders combined as loads A, B (and A'), e.g. from
%       File > Combine two saved measurements…; the termination comes from
%       their metadata (1.4.0 and later), else it is unknown.
%
%   p.loads   struct array: role, load ([] = unknown), folder, meas, cfg,
%             res (the saved result, [] if none)
%   p.info    the twoload.json contents ([] for combined folders)
%   p.tl      the saved two-load result ([] for combined folders)
%   p.warnings  e.g. a load folder whose raw.mat changed since the pair
%             folder was written (SHA-256)

p = struct('loads', [], 'info', [], 'tl', [], 'warnings', {{}}, 'folder', '');
if iscell(folder) || isstring(folder)
    fl = reshape(cellstr(folder), 1, []);
    roles = {'A', 'B', 'A2'};
    if numel(fl) < 2 || numel(fl) > 3
        error('tim:twoload:folders', 'Combine two (or three: A, B, A again) measurement folders.');
    end
    refs = struct('role', roles(1:numel(fl)), 'folder', fl, 'rawSha256', '');
else
    folder = char(folder);
    jf = fullfile(folder, 'twoload.json');
    if ~isfile(jf)
        error('tim:twoload:folder', 'No two-load result in %s (twoload.json missing).', folder);
    end
    p.folder = folder;
    p.info = jsondecode(tim.app.readTextUtf8(jf));
    r = p.info.loads;
    root = fileparts(folder);
    refs = struct('role', {r.role}, 'folder', cellfun(@(f) fullfile(root, f), {r.folder}, 'UniformOutput', false), ...
        'rawSha256', {r.rawSha256});
    S = load(fullfile(folder, 'result.mat'), 'tl');
    p.tl = S.tl;
end
loads = struct('role', {}, 'load', {}, 'folder', {}, 'meas', {}, 'cfg', {}, 'res', {});
for i = 1:numel(refs)
    f = refs(i).folder;
    raw = fullfile(f, 'raw.mat');
    if ~isfile(raw)
        error('tim:twoload:missing', 'Load %s: no raw data in %s.', refs(i).role, f);
    end
    if ~isempty(refs(i).rawSha256) && ~strcmp(tim.app.fileSha256(raw), refs(i).rawSha256)
        p.warnings{end+1} = sprintf('load %s: raw.mat in %s changed since the two-load result was saved', ...
            refs(i).role, f);
    end
    S = load(raw, 'meas'); m = S.meas;
    c = tim.app.defaultConfig();
    if isfile(fullfile(f, 'config.json'))
        w = warning('off', 'tim:config:unknownField');
        restore = onCleanup(@() warning(w));
        c = tim.app.loadConfig(fullfile(f, 'config.json'));
        clear restore
    end
    ld = [];
    if isfield(m, 'metadata') && isfield(m.metadata, 'termination')
        t = m.metadata.termination; ld = struct('kind', t.kind, 'place', t.place);
    end
    res = [];
    if isfile(fullfile(f, 'result.mat'))
        S = load(fullfile(f, 'result.mat'), 'res'); res = S.res;
    end
    loads(i) = struct('role', refs(i).role, 'load', ld, 'folder', f, 'meas', m, 'cfg', c, 'res', res);
end
p.loads = loads;
end
