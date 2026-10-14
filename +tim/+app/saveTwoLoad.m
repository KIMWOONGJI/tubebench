function folder = saveTwoLoad(tl, loads, cfg, specimen, figs)
%SAVETWOLOAD Save a two-load result in a NEW pair folder (WO-005).
%
%   folder = tim.app.saveTwoLoad(tl, loads, cfg, specimen, figs)
%
%   data/<yyyyMMdd_HHmmss>_twoload[_<specimen>]/
%       twoload.json   method, specimen, the loads (role, termination, the
%                      name of their measurement folder in the same data
%                      folder and the SHA-256 of its raw.mat), the limits, the
%                      summary, the checks and the warnings
%       result.mat     tl (tim.app.processTwoLoad) and the same references
%       results.csv    per frequency line: T, condQ, TL, the anechoic and the
%                      hard-backed values, the thin-element check, the masks
%       fig_*.png      figures (if figs given and cfg.output.exportFigures)
%       README.txt
%   loads: struct array with role, load, folder (the load folders written by
%   tim.app.runTwoLoad or opened from disk). The load folders are not touched;
%   File > Open measurement on the pair folder reprocesses them.
%   An existing folder is NEVER overwritten.

if nargin < 4, specimen = ''; end
if nargin < 5, figs = []; end
name = 'twoload';
specimen = strtrim(char(specimen));
if ~isempty(specimen) && ~strcmp(specimen, 'unnamed specimen')
    name = [name '_' regexprep(specimen, '[^\w\-]', '_')];
end
root = tim.app.outputDir(cfg, 'data');
if ~exist(root, 'dir'), mkdir(root); end
folder = tim.app.uniqueName(fullfile(root, [char(datetime('now'), 'yyyyMMdd_HHmmss') '_' name]));
mkdir(folder);

refs = struct('role', {}, 'termination', {}, 'kind', {}, 'place', {}, 'folder', {}, 'rawSha256', {});
for i = 1:numel(loads)
    L = loads(i);
    lab = 'not recorded'; kd = ''; pl = '';
    if ~isempty(L.load)
        d = tim.app.describeLoad(L.load, cfg); lab = d.label; kd = d.kind; pl = d.place;
    end
    [~, fn, fe] = fileparts(L.folder);
    sha = '';
    raw = fullfile(L.folder, 'raw.mat');
    if ~isempty(L.folder) && isfile(raw), sha = tim.app.fileSha256(raw); end
    refs(i) = struct('role', L.role, 'termination', lab, 'kind', kd, 'place', pl, 'folder', [fn fe], ...
        'rawSha256', sha);
end
[swv, swi] = tim.app.softwareVersion();
info = struct('formatVersion', 1, 'method', tl.method, 'specimen', specimen, 'loads', refs, ...
    'limits', struct('condQMax', tl.valid.condQMax, 'reciprocityTol', tl.valid.reciprocityTol, ...
    'repeatTol', tl.repeat.tol), 'summary', tl.valid.summary, 'repeat', tl.repeat.text, 'level', tl.level.text, ...
    'errors', {tl.checks.errors}, 'warnings', {tl.warnings}, 'assumption', tl.assumption, 'mode', cfg.mode, ...
    'software', swv, 'commit', swi.commit);
fid = fopen(fullfile(folder, 'twoload.json'), 'w', 'n', 'UTF-8');
fwrite(fid, unicode2native(jsonencode(info, 'PrettyPrint', true), 'UTF-8'));
fclose(fid);
save(fullfile(folder, 'result.mat'), 'tl', 'info', '-v7.3');
if cfg.output.exportCsv
    writetable(resultsTable(tl), fullfile(folder, 'results.csv'));
end
if ~isempty(figs) && cfg.output.exportFigures
    tim.app.exportFigures(figs, folder, cfg.output.figureFormats);
end
fid = fopen(fullfile(folder, 'README.txt'), 'w');
fprintf(fid, ['Two-load result (%s), software %s\nSource: %s (commit %s)\nThe raw data are in the load ' ...
    'folders named in twoload.json; File > Open measurement on this folder reprocesses them.\n'], ...
    tl.method, swv, swi.repository, swi.commit);
if strcmp(cfg.mode, 'simulation'), fprintf(fid, 'SIMULATED DATA - not a physical measurement.\n'); end
fclose(fid);
end

function T = resultsTable(tl)
f = tl.f(:);
T = table(f, 'VariableNames', {'f_Hz'});
for e = {'T11', 'T12', 'T21', 'T22'}
    T.([e{1} '_re']) = real(tl.T.(e{1})); T.([e{1} '_im']) = imag(tl.T.(e{1}));
end
T.condQ = tl.condQ;
T.TL_dB = tl.anechoic.TL_dB;
T.tau_abs = abs(tl.anechoic.tau); T.tau_phase_deg = rad2deg(angle(tl.anechoic.tau));
T.Ra_abs = abs(tl.anechoic.R); T.Ra_phase_deg = rad2deg(angle(tl.anechoic.R));
T.alpha_anechoic = tl.anechoic.alpha; T.dissipation = tl.anechoic.dissipation;
T.Rh_abs = abs(tl.hard.R); T.Rh_phase_deg = rad2deg(angle(tl.hard.R));
T.alpha_hardBacked = tl.hard.alpha;
T.Zt_re = real(tl.thin.Zt); T.Zt_im = imag(tl.thin.Zt);
T.ZcT21_abs = tl.thin.T21Zc; T.T22_minus_1_abs = tl.thin.T22dev;
T.reciprocityError = tl.reciprocityError; T.symmetryError = tl.symmetryError;
T.repeatDiff = tl.repeat.diff;
T.valid = tl.valid.valid; T.bothLoadsValid = tl.valid.base; T.loadsDiffer = tl.valid.loadsDiffer;
T.notReciprocal = tl.valid.notReciprocal;
end
