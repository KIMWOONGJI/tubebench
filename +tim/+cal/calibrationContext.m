function c = calibrationContext(cal, cfg)
%CALIBRATIONCONTEXT Set-up of a calibration vs the set-up of a measurement.
%
%   c = tim.cal.calibrationContext(cal, cfg)
%
%   Diagnostic only: C_k = c_k / c_ref does not depend on the tube, so
%   nothing is invalidated. Compared:
%   - port distances M1-M2, M2-M3, M3-M4 (hardware: with the empty section
%     mounted during the calibration they are the same as in the
%     measurement; a mismatch means the tube was assembled differently, e.g.
%     the section taken out, or the geometry was edited). xFront / xRear may
%     legitimately differ (a thinner specimen in the same section).
%   - temperature (re-calibrate above 3 K), mode (simulation vs hardware),
%   - the empty-section check (Test E) stored with the calibration.
%   c.warnings lists the findings as text.

c = struct('known', false, 'specimenSection', '', 'sectionLength_m', NaN, ...
    'portDistances_cal_m', nan(1, 3), 'portDistances_meas_m', nan(1, 3), 'geometryMatch', NaN, ...
    'temperatureDiff_K', NaN, 'modeMatch', true, 'emptyCheckPassed', NaN, 'warnings', {{}});
if isempty(cal), return; end
ver = 'unknown'; if isfield(cal, 'version'), ver = cal.version; end
meta = struct(); if isfield(cal, 'meta') && isstruct(cal.meta), meta = cal.meta; end
if isfield(meta, 'mode') && ~strcmp(meta.mode, cfg.mode)
    c.modeMatch = false;
    c.warnings{end+1} = sprintf('Calibration %s was made in %s mode; this measurement is in %s mode.', ver, meta.mode, cfg.mode);
end
if ~isfield(meta, 'tube')
    c.warnings{end+1} = sprintf('Calibration %s does not record the tube set-up (made before the empty-section procedure).', ver);
    return
end
t = meta.tube; c.known = true;
c.specimenSection = t.specimenSection; c.sectionLength_m = t.sectionLength_m;
xc = t.geometry.micPositions(:).'; xm = cfg.geometry.micPositions(:).';
c.portDistances_cal_m = diff(xc); c.portDistances_meas_m = diff(xm);
if all(isfinite([xc xm]))
    c.geometryMatch = all(abs(diff(xc) - diff(xm)) <= 0.5e-3);
    if ~c.geometryMatch
        c.warnings{end+1} = sprintf(['Port distances M1-M2 / M2-M3 / M3-M4 = %s mm differ from the calibration set-up (%s mm): ' ...
            'tube assembled differently (section taken out?) or geometry edited - the empty-section check does not apply.'], ...
            mat2str(round(1e3 * diff(xm), 2)), mat2str(round(1e3 * diff(xc), 2)));
    end
end
if isfield(t, 'environment') && isfield(t.environment, 'temperature_C')
    c.temperatureDiff_K = cfg.environment.temperature_C - t.environment.temperature_C;
    if abs(c.temperatureDiff_K) > 3
        c.warnings{end+1} = sprintf('Temperature differs by %.1f K from the calibration %s: re-calibrate (> 3 K).', c.temperatureDiff_K, ver);
    end
end
if isfield(meta, 'emptyCheck') && isfield(meta.emptyCheck, 'performed') && meta.emptyCheck.performed
    c.emptyCheckPassed = meta.emptyCheck.passed;
    if ~c.emptyCheckPassed
        c.warnings{end+1} = sprintf('The empty-section check (Test E) of calibration %s FAILED: check the geometry.', ver);
    end
end
end
