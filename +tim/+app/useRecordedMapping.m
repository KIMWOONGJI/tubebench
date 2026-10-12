function [cfg, info] = useRecordedMapping(cfg, mics)
%USERECORDEDMAPPING Configuration with the microphone mapping a measurement was recorded with.
%
%   cfg = tim.app.useRecordedMapping(cfg, meas.mics)
%   [cfg, info] = tim.app.useRecordedMapping(cfg, mics)
%
%   tim.app.processMeasurement reorders the DAQ channels into the ports
%   M1..M4 with cfg.mics. When a saved measurement is reprocessed, the
%   configuration loaded now may assign the channels to other ports than
%   the ones the data were recorded with (re-cabled since, another file
%   loaded); the wave decomposition would then run on swapped microphones.
%   This function returns cfg with the port of every channel set to the
%   recorded one. The other microphone fields (model, serial number,
%   sensitivities) stay as configured.
%
%   mics   the recorded microphones: a struct array with the fields channel
%          and position, e.g. meas.mics of raw.mat, or the mics of the
%          measurement folder's config.json for a file without them.
%   info   recorded, configured   1 x 4: port of channel 1..4
%          differs                 the two mappings differ
%          recordedText, configuredText   e.g. 'ch1 M1, ch2 M2, ch3 M3, ch4 M4'
%
%   Keep the configuration's mapping (do not call this function) only to
%   correct a mapping that was recorded wrongly; processMeasurement then
%   reports the difference in res.diagnostics.warnings. The window offers
%   the same choice when it opens a measurement (File > Open measurement…).
%
%   Example (offline reprocessing, docs/user_guide.md section 11):
%     S = load(fullfile(folder, 'raw.mat'));
%     cfg = tim.app.useRecordedMapping(tim.app.loadConfig('config/user_config.json'), S.meas.mics);
%     res = tim.app.processMeasurement(S.meas, cfg, cal);
%
%   Errors: tim:config:mics when cfg.mics or mics does not assign each
%   channel ch1..ch4 to exactly one port M1..M4.

configured = portOfChannel(cfg.mics, 'configuration');
recorded = portOfChannel(mics, 'recorded microphones');
for i = 1:numel(cfg.mics)
    cfg.mics(i).position = recorded(cfg.mics(i).channel);
end
info = struct('recorded', recorded, 'configured', configured, 'differs', ~isequal(recorded, configured), ...
    'recordedText', mappingText(recorded), 'configuredText', mappingText(configured));
end

function p = portOfChannel(m, what)
% port of channel 1..4 (1 x 4); the list may be in any order
ok = isstruct(m) && numel(m) == 4 && all(isfield(m, {'channel', 'position'}));
if ok
    ch = [m.channel]; pos = [m.position];
    ok = isnumeric(ch) && isnumeric(pos) && isequal(sort(ch), 1:4) && isequal(sort(pos), 1:4);
end
if ~ok
    error('tim:config:mics', 'The %s do not assign each channel ch1-ch4 to exactly one port M1-M4 (mics).', what);
end
p = zeros(1, 4);
p(ch) = pos;
end

function t = mappingText(p)
% the same wording as the mapping warning of tim.app.processMeasurement
t = strjoin(arrayfun(@(c) sprintf('ch%d M%d', c, p(c)), 1:4, 'UniformOutput', false), ', ');
end
