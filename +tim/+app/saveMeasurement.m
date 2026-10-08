function folder = saveMeasurement(meas, res, cfg, name, figs)
%SAVEMEASUREMENT Store raw data, results, metadata and exports in a NEW folder.
%
%   folder = tim.app.saveMeasurement(meas, res, cfg, name, figs)
%
%   data/<yyyyMMdd_HHmmss>_<name>/
%       raw.mat          meas (raw volts, settings, events, metadata, raw stream bytes)
%       result.mat       res (spectra, calibration info, analysis, validity)
%       config.json      configuration snapshot
%       metadata.json    instrument/software metadata (human readable)
%       results.csv      per-frequency results incl. validity flags
%       spectra.csv      relative channel responses and quality indicators
%       fig_*.png/.pdf   figures (if figs given and cfg.output.exportFigures)
%   An existing folder is NEVER overwritten: a numeric suffix is added.

if nargin < 4 || isempty(name), name = meas.kind; end
if nargin < 5, figs = []; end
name = regexprep(name, '[^\w\-]', '_');
root = tim.app.outputDir(cfg, 'data');
if ~exist(root, 'dir'), mkdir(root); end
folder = tim.app.uniqueName(fullfile(root, [char(datetime('now'), 'yyyyMMdd_HHmmss') '_' name]));
mkdir(folder);

save(fullfile(folder, 'raw.mat'), 'meas', '-v7.3');
if ~isempty(res)
    save(fullfile(folder, 'result.mat'), 'res', '-v7.3');
end
tim.app.saveConfig(cfg, fullfile(folder, 'config.json'));
md = meas.metadata;
md = rmfield(md, intersect(fieldnames(md), {'config'}));
writeJson(md, fullfile(folder, 'metadata.json'));

if ~isempty(res) && cfg.output.exportCsv
    tim.app.exportCsv(res, folder);
end
if ~isempty(figs) && cfg.output.exportFigures
    tim.app.exportFigures(figs, folder, cfg.output.figureFormats);
end
% read-only marker for raw data (informational; Windows attribute not changed)
fid = fopen(fullfile(folder, 'README.txt'), 'w');
[swv, swi] = tim.app.softwareVersion();
fprintf(fid, 'Measurement %s (%s mode), software %s\nSource: %s (commit %s)\nRaw data in raw.mat must not be modified.\n', ...
    meas.timestamp, cfg.mode, swv, swi.repository, swi.commit);
if strcmp(cfg.mode, 'simulation'), fprintf(fid, 'SIMULATED DATA - not a physical measurement.\n'); end
fclose(fid);
end

function writeJson(s, file)
try
    txt = jsonencode(s, 'PrettyPrint', true);
catch
    txt = jsonencode(struct('error', 'metadata not JSON-encodable'));
end
fid = fopen(file, 'w', 'n', 'UTF-8'); fwrite(fid, unicode2native(txt, 'UTF-8')); fclose(fid);
end
