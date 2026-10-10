function c = calibrationContext(cal, cfg, current)
%CALIBRATIONCONTEXT Set-up of a calibration vs the set-up of a measurement.
%
%   c = tim.cal.calibrationContext(cal, cfg)
%   c = tim.cal.calibrationContext(cal, cfg, meas)    % a measurement
%   c = tim.cal.calibrationContext(cal, cfg, chain)   % session.acquisitionChain()
%
%   Diagnostic only: C_k = g_k / g_ref (ratio of the chain gains) does not
%   depend on the tube, so nothing is invalidated. Compared:
%   - port distances M1-M2, M2-M3, M3-M4 (hardware: with the empty specimen
%     section mounted during the calibration they are the same as in the
%     measurement; a mismatch means the tube was assembled differently, e.g.
%     the specimen section removed, or the geometry was edited). xFront /
%     xRear may legitimately differ (a thinner specimen in the same section).
%   - temperature (recalibrate above 3 K), mode (simulation vs hardware),
%   - the empty-tube check (Test E) stored with the calibration,
%   - the DAQ input chain (cal.meta.acquisition, tim.cal.acquisitionChain):
%     another acquisition driver, another module (model, serial number) or
%     other input settings (sample rate, range, filter, CCLD) - the chain
%     gains in C_k include the DAQ inputs. The measurement side comes from
%     meas.metadata.daq / acquisition and meas.fs (an opened folder: what was
%     used, not today's settings), from a chain struct, or else from cfg
%     (driver and input settings; module unknown). Unknown on either side
%     gives no warning for that item: a calibration made before 1.2.0 has no
%     meta.acquisition, and measurement metadata saved before 1.2.0 has no
%     driver (model and serial number are compared as text).
%   c.warnings lists the findings as text.

c = struct('known', false, 'specimenSection', '', 'sectionLength_m', NaN, ...
    'portDistances_cal_m', nan(1, 3), 'portDistances_meas_m', nan(1, 3), 'geometryMatch', NaN, ...
    'temperatureDiff_K', NaN, 'modeMatch', true, 'emptyCheckPassed', NaN, ...
    'acquisitionKnown', false, 'acquisitionMatch', NaN, 'acquisitionDifferences', {{}}, 'warnings', {{}});
if isempty(cal), return; end
if nargin < 3, current = []; end
ver = 'unknown'; if isfield(cal, 'version'), ver = cal.version; end
meta = struct(); if isfield(cal, 'meta') && isstruct(cal.meta), meta = cal.meta; end
if isfield(meta, 'mode') && ~strcmp(meta.mode, cfg.mode)
    c.modeMatch = false;
    c.warnings{end+1} = sprintf('Calibration %s was made in %s mode; this measurement is in %s mode.', ver, meta.mode, cfg.mode);
end
if isfield(meta, 'acquisition') && isstruct(meta.acquisition) && isscalar(meta.acquisition)
    c.acquisitionKnown = true;
    d = chainDifferences(tim.cal.acquisitionChain(meta.acquisition, meta.acquisition), measuredChain(cfg, current));
    c.acquisitionDifferences = d;
    c.acquisitionMatch = isempty(d);
    if ~isempty(d)
        c.warnings{end+1} = sprintf(['Calibration %s was made with another acquisition chain: %s. The calibration ' ...
            'factors include the DAQ inputs - recalibrate with this module and these input settings.'], ver, strjoin(d, '; '));
    end
end
if ~isfield(meta, 'tube')
    c.warnings{end+1} = sprintf(['Calibration %s does not record the tube set-up (made before calibration with the ' ...
        'empty specimen section was introduced).'], ver);
    return
end
t = meta.tube; c.known = true;
c.specimenSection = t.specimenSection; c.sectionLength_m = t.sectionLength_m;
xc = t.geometry.micPositions(:).'; xm = cfg.geometry.micPositions(:).';
c.portDistances_cal_m = diff(xc); c.portDistances_meas_m = diff(xm);
if all(isfinite([xc xm]))
    c.geometryMatch = all(abs(diff(xc) - diff(xm)) <= 0.5e-3);
    if ~c.geometryMatch
        c.warnings{end+1} = sprintf(['Port distances M1–M2 / M2–M3 / M3–M4 = %s mm differ from the calibration set-up (%s mm): ' ...
            'tube assembled differently (specimen section removed?) or geometry edited – the empty-tube check (Test E) ' ...
            'of this calibration does not apply.'], ...
            mat2str(round(1e3 * diff(xm), 2)), mat2str(round(1e3 * diff(xc), 2)));
    end
end
if isfield(t, 'environment') && isfield(t.environment, 'temperature_C')
    c.temperatureDiff_K = cfg.environment.temperature_C - t.environment.temperature_C;
    if abs(c.temperatureDiff_K) > 3
        c.warnings{end+1} = sprintf('Temperature differs by %.1f K from calibration %s (more than 3 K): recalibrate.', ...
            c.temperatureDiff_K, ver);
    end
end
if isfield(meta, 'emptyCheck') && isfield(meta.emptyCheck, 'performed') && meta.emptyCheck.performed
    c.emptyCheckPassed = meta.emptyCheck.passed;
    if ~c.emptyCheckPassed
        c.warnings{end+1} = sprintf('The empty-tube check (Test E) of calibration %s failed: check s1, L1 + d + L2 and s2.', ver);
    end
end
end

function b = measuredChain(cfg, current)
% the DAQ chain of the measurement: from a measurement, a chain struct, or cfg
if isstruct(current) && isscalar(current) && isfield(current, 'metadata') && isstruct(current.metadata)
    md = current.metadata;
    daq = []; acq = []; fs = [];
    if isfield(md, 'daq'), daq = md.daq; end
    if isfield(md, 'acquisition'), acq = md.acquisition; end
    if isfield(current, 'fs'), fs = current.fs; end
    b = tim.cal.acquisitionChain(daq, acq, fs);
elseif isstruct(current) && isscalar(current) && all(isfield(current, {'driver', 'model', 'serial', 'range'}))
    b = current;
else
    daq = struct();
    if isfield(cfg, 'daq') && isfield(cfg.daq, 'driver'), daq.driver = cfg.daq.driver; end
    fs = [];
    if isstruct(current) && isfield(current, 'fs'), fs = current.fs; end       % a measurement without metadata
    b = tim.cal.acquisitionChain(daq, cfg.acquisition, fs);
end
end

function d = chainDifferences(a, b)
% items known on both sides that differ, as text ('' / NaN / [] = unknown)
d = {};
items = {'driver', 'acquisition driver'; 'model', 'module model'; 'serial', 'module serial number'; ...
    'range', 'input range'; 'filter', 'high-pass filter'};
for i = 1:size(items, 1)
    x = a.(items{i, 1}); y = b.(items{i, 1});
    if ~isempty(x) && ~isempty(y) && ~strcmp(x, y)
        d{end+1} = sprintf('%s %s (calibration: %s)', items{i, 2}, y, x); %#ok<AGROW>
    end
end
if isfinite(a.sampleRate) && isfinite(b.sampleRate) && abs(a.sampleRate - b.sampleRate) > 1e-9 * a.sampleRate
    d{end+1} = sprintf('sample rate %g S/s (calibration: %g S/s)', b.sampleRate, a.sampleRate);
end
if ~isempty(a.ccld) && ~isempty(b.ccld) && ~isequal(a.ccld, b.ccld)
    d{end+1} = sprintf('CCLD %s (calibration: %s)', mat2str(b.ccld), mat2str(a.ccld));
end
end
