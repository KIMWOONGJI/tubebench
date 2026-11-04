function tl = processTwoLoad(loads, cfg)
%PROCESSTWOLOAD Transfer matrix of the specimen from processed measurements (WO-005).
%
%   tl = tim.app.processTwoLoad(loads, cfg)
%
%   loads  struct array, one element per measurement:
%     role    'A', 'B', 'A2' (the repeat of load A) - two-load method (ASTM
%             E2611 [3]: T from A and B) - or 'oneLoad' (one-load method for a
%             front-to-back symmetric, reciprocal specimen; an ASSUMPTION)
%     res     the result of tim.app.processMeasurement
%     load    the termination (kind, place; tim.app.describeLoad), or [] when
%             unknown (a folder saved before 1.4.0)
%     meas    the raw measurement (peak level), or []
%     cfg     the configuration it was processed with (temperature), or []
%     folder  its data folder ('' when not saved)
%   cfg    analysis.condQMax, reciprocityTol, repeatTol; measurement.
%          maxTemperatureDiff_C, maxMinutesBetween, levelStepWarn_dB
%
%   tl.method        'twoLoad' | 'oneLoadSymmetric';  tl.assumption (text)
%   tl.f, tl.Zc      frequency lines and the characteristic impedance; tl.Z0
%                    = rho c; tl.band (analysis band), tl.kind, tl.timestamp,
%                    tl.calibrationVersion (of load A: titles of the views)
%   tl.T             T11, T12, T21, T22, detT ([p_L; u_L] = T [p_R; u_R])
%   tl.condQ         condition number of the loads (columns of unit length)
%   tl.anechoic      tau, TL_dB, R, alpha (= 1 - |R|^2), dissipation
%                    (1 - |R|^2 - |tau|^2), Zs: the specimen with an anechoic
%                    termination, independent of the actual one
%   tl.hard          R, alpha, Zs: the specimen backed by a rigid wall at its
%                    rear face (u_R = 0: Zs = T11 / T21)
%   tl.thin          Zt = T12 (series impedance), T21Zc = |Zc T21|, T22dev =
%                    |T22 - 1|: a thin element has T21 = 0, T11 = T22 = 1
%   tl.reciprocityError = |det T - 1|,  tl.symmetryError
%   tl.valid         .valid (lines valid in every load used and condQ <=
%                    condQMax), .base, .loadsDiffer, .notReciprocal (a flag,
%                    not a mask), .nValid, .nBand, .summary (text)
%   tl.loads         per load: role, label, folder, timestamp, temperature_C,
%                    peakLevel_dB, validFraction
%   tl.checks        .errors (the loads cannot be combined: nothing computed,
%                    T is NaN) and .warnings
%   tl.repeat        the repeat of load A: T(A,B) against T(A2,B) (decision 5
%                    of WO-005): .performed, .diff (per line, relative to |T|),
%                    .median, .p90, .tol, .ok, .text
%   tl.level         .peak_dB per load, .stepB_dB (B over A), .warn, .text
%   tl.warnings      every warning (checks, level, repeat)

if nargin < 2 || isempty(cfg), cfg = tim.app.defaultConfig(); end
an = cfg.analysis; ms = defaultsOf(cfg);
roles = {loads.role};
oneLoad = numel(loads) == 1 && strcmp(roles{1}, 'oneLoad');
iA = find(strcmp(roles, 'A'), 1); iB = find(strcmp(roles, 'B'), 1); iA2 = find(strcmp(roles, 'A2'), 1);
if ~oneLoad && (isempty(iA) || isempty(iB))
    error('tim:twoload:roles', 'The two-load method needs a load A and a load B (roles ''A'', ''B'' and optionally ''A2'').');
end
first = 1; if ~oneLoad, first = iA; end
a0 = loads(first).res.analysis;
f = a0.f(:); Nf = numel(f); Zc = a0.Zc(:);
tl = struct('method', 'twoLoad', 'assumption', '', 'f', f, 'Zc', Zc);
tl.Z0 = a0.air.Z0;                               % rho c (the normalisation of Zt / rho c)
tl.band = [f(1) f(end)];
if isfield(a0, 'options') && isfield(a0.options, 'fRange') && numel(a0.options.fRange) == 2
    tl.band = a0.options.fRange(:).';
end
r0 = loads(first).res;
tl.kind = r0.kind; tl.timestamp = r0.timestamp; tl.calibrationVersion = r0.calibration.version;
tl.loads = loadSummary(loads, cfg);
tl.checks = pairChecks(loads, ms);
if oneLoad
    tl.method = 'oneLoadSymmetric';
    tl.assumption = ['ASSUMED: the specimen is front-to-back symmetric (T11 = T22) and reciprocal (det T = 1); ' ...
        'one load gives only two equations for the four elements of T (ASTM E2611 one-load method).'];
else
    tl.assumption = ['Two loads (ASTM E2611): a linear, time-invariant specimen, mounted identically for both loads; ' ...
        'the loads must give independent boundary states (condQ).'];
end

% ---- transfer matrix
T = struct('T11', nan(Nf, 1), 'T12', nan(Nf, 1), 'T21', nan(Nf, 1), 'T22', nan(Nf, 1));
condQ = nan(Nf, 1);
if isempty(tl.checks.errors)
    if oneLoad
        tm = tim.acoustics.transferMatrix('oneLoadSymmetric', a0);
    else
        tm = tim.acoustics.transferMatrix('twoLoad', loads(iA).res.analysis, loads(iB).res.analysis);
        condQ = tm.condQ(:);
    end
    for e = {'T11', 'T12', 'T21', 'T22'}, T.(e{1}) = tm.(e{1})(:); end
end
T.detT = T.T11 .* T.T22 - T.T12 .* T.T21;
tl.T = T; tl.condQ = condQ;

% ---- the specimen with an anechoic termination, and backed by a rigid wall
den = T.T11 + T.T12 ./ Zc + Zc .* T.T21 + T.T22;
tau = 2 ./ den;
Ra = (T.T11 + T.T12 ./ Zc - Zc .* T.T21 - T.T22) ./ den;
tl.anechoic = struct('tau', tau, 'TL_dB', -20 * log10(abs(tau)), 'R', Ra, 'alpha', 1 - abs(Ra).^2, ...
    'dissipation', 1 - abs(Ra).^2 - abs(tau).^2, 'Zs', Zc .* (1 + Ra) ./ (1 - Ra));
Rh = (T.T11 - Zc .* T.T21) ./ (T.T11 + Zc .* T.T21);
tl.hard = struct('R', Rh, 'alpha', 1 - abs(Rh).^2, 'Zs', T.T11 ./ T.T21);
tl.thin = struct('Zt', T.T12, 'T21Zc', abs(Zc .* T.T21), 'T22dev', abs(T.T22 - 1), 'T11dev', abs(T.T11 - 1));
tl.reciprocityError = abs(T.detT - 1);
tl.symmetryError = abs(T.T11 - T.T22) ./ (abs(T.T11) + abs(T.T22));

% ---- validity: every load used valid (both pairs, quality, calibration) and
% loads that differ enough; reciprocity is reported, not a mask
used = first; if ~oneLoad, used = [iA iB]; end
base = true(Nf, 1); band = true(Nf, 1); outCal = false(Nf, 1);
for i = used
    v = loads(i).res.analysis.valid;
    base = base & v.valid(:);
    band = band & ~v.flags.outsideBand(:);
    if isfield(v.flags, 'outsideCalibration'), outCal = outCal | v.flags.outsideCalibration(:); end
end
base = base & isfinite(T.T11) & isfinite(T.T12) & isfinite(T.T21) & isfinite(T.T22);
if oneLoad
    differ = true(Nf, 1);
else
    differ = condQ <= an.condQMax;
end
valid = base & differ;
notRecip = ~oneLoad & tl.reciprocityError > an.reciprocityTol;
tl.valid = struct('valid', valid, 'base', base, 'loadsDiffer', differ, 'notReciprocal', notRecip, ...
    'nValid', nnz(valid), 'nBand', nnz(band), 'condQMax', an.condQMax, 'reciprocityTol', an.reciprocityTol, ...
    'summary', '', 'outsideCalibration', outCal);   % a load outside the calibration range (1.5.1)
if oneLoad
    tl.valid.summary = sprintf('%d of %d lines valid (one load, symmetric specimen assumed)', nnz(valid), nnz(band));
else
    tl.valid.summary = sprintf(['%d of %d lines valid (both loads valid: %d; loads differ, condQ <= %g: %d); ' ...
        '|det T - 1| > %g on %d valid lines'], nnz(valid), nnz(band), nnz(base), an.condQMax, nnz(base & differ), ...
        an.reciprocityTol, nnz(valid & notRecip));
end

% ---- repeat of load A: T(A,B) against T(A2,B) - T does not depend on the
% termination, so a re-packed absorber does not count; a moved specimen does
tl.repeat = struct('performed', false, 'diff', nan(Nf, 1), 'median', NaN, 'p90', NaN, 'tol', an.repeatTol, ...
    'ok', true, 'text', 'load A not repeated');
if ~oneLoad && ~isempty(iA2) && isempty(tl.checks.errors)
    try
        t2 = tim.acoustics.transferMatrix('twoLoad', loads(iA2).res.analysis, loads(iB).res.analysis);
        n1 = normT(T, Zc); n2 = normT(t2, Zc);
        dd = sqrt(sum(abs(n1 - n2).^2, 2)) ./ sqrt(sum(abs(n1).^2, 2));
        both = valid & loads(iA2).res.analysis.valid.valid(:) & t2.condQ(:) <= an.condQMax;
        tl.repeat.performed = true;
        tl.repeat.diff = dd;
        if any(both)
            x = sort(dd(both));
            tl.repeat.median = median(x); tl.repeat.p90 = x(max(1, ceil(0.9 * numel(x))));
            tl.repeat.ok = tl.repeat.median <= an.repeatTol;
            tl.repeat.text = sprintf(['repeat of load A: T(A,B) and T(A'',B) differ by %.3g (median) / %.3g (90 %%) ' ...
                'of |T| on %d lines - %s (limit %g)'], tl.repeat.median, tl.repeat.p90, nnz(both), ...
                ternary(tl.repeat.ok, 'nothing moved', 'the specimen or a microphone may have moved'), an.repeatTol);
        else
            tl.repeat.ok = false;
            tl.repeat.text = 'repeat of load A: no line valid in all three loads - not evaluated';
        end
    catch err
        tl.repeat.ok = false;
        tl.repeat.text = ['repeat of load A: not evaluated (' err.message ')'];
    end
end

% ---- levels: a rigid cap raises the level at the tube resonances
pk = [tl.loads.peakLevel_dB];
tl.level = struct('peak_dB', pk, 'stepB_dB', NaN, 'warn', false, 'limit_dB', ms.levelStepWarn_dB, 'text', '');
if ~oneLoad && isfinite(pk(iA)) && isfinite(pk(iB))
    tl.level.stepB_dB = pk(iB) - pk(iA);
    tl.level.warn = tl.level.stepB_dB >= ms.levelStepWarn_dB;
    tl.level.text = sprintf('peak level: load A %.1f dB, load B %.1f dB (%+.1f dB)', pk(iA), pk(iB), tl.level.stepB_dB);
    if tl.level.warn
        tl.level.text = [tl.level.text sprintf([' – load B is %.0f dB or more above load A: check that the specimen ' ...
            'is linear at that level (repeat load B at a lower level)'], ms.levelStepWarn_dB)];
    end
end

w = tl.checks.warnings;
if tl.level.warn, w{end+1} = tl.level.text; end
if tl.repeat.performed && ~tl.repeat.ok, w{end+1} = tl.repeat.text; end
tl.warnings = w;
end

function ms = defaultsOf(cfg)
d = tim.app.defaultConfig();
ms = d.measurement;
if isfield(cfg, 'measurement')
    f = fieldnames(cfg.measurement);
    for i = 1:numel(f), ms.(f{i}) = cfg.measurement.(f{i}); end
end
end

function n = normT(T, Zc)
% T in units of the tube: [T11, T12/Zc; Zc T21, T22] as rows of a line
n = [T.T11(:), T.T12(:) ./ Zc, Zc .* T.T21(:), T.T22(:)];
end

function s = loadSummary(loads, cfg)
s = struct('role', {}, 'label', {}, 'folder', {}, 'timestamp', {}, 'temperature_C', {}, 'peakLevel_dB', {}, ...
    'validFraction', {});
for i = 1:numel(loads)
    L = loads(i);
    lab = 'termination not recorded';
    if isfield(L, 'load') && ~isempty(L.load)
        c = cfg; if isfield(L, 'cfg') && ~isempty(L.cfg), c = L.cfg; end
        d = tim.app.describeLoad(L.load, c); lab = d.label;
    end
    T = NaN;
    if isfield(L, 'cfg') && ~isempty(L.cfg), T = L.cfg.environment.temperature_C; end
    pk = NaN;
    if isfield(L, 'meas') && ~isempty(L.meas)
        p = tim.app.peakLevel(L.meas); pk = p.max_dB;
    end
    v = L.res.analysis.valid;
    inBand = ~v.flags.outsideBand(:);
    fr = nnz(v.valid(:) & inBand) / max(1, nnz(inBand));
    fold = ''; if isfield(L, 'folder') && ~isempty(L.folder), fold = L.folder; end
    s(i) = struct('role', L.role, 'label', lab, 'folder', fold, 'timestamp', L.res.timestamp, ...
        'temperature_C', T, 'peakLevel_dB', pk, 'validFraction', fr);
end
end

function c = pairChecks(loads, ms)
% may these measurements be combined? errors: nothing is computed; warnings
c = struct('errors', {{}}, 'warnings', {{}});
if numel(loads) < 2, return; end
r0 = loads(1).res; a0 = r0.analysis;
for i = 2:numel(loads)
    r = loads(i).res; a = r.analysis; who = sprintf('load %s', loads(i).role);
    if numel(a.f) ~= numel(a0.f) || any(abs(a.f(:) - a0.f(:)) > 1e-9 * max(a0.f))
        c.errors{end+1} = sprintf('%s has another frequency grid (analysis band or line spacing)', who);
    end
    c1 = []; c0 = [];
    if isfield(loads, 'cfg'), c1 = loads(i).cfg; c0 = loads(1).cfg; end
    if ~sameGeometry(a, a0, c1, c0)
        c.errors{end+1} = sprintf('%s was processed with another tube geometry (D, port positions, specimen faces)', who);
    end
    if isfield(r, 'channelOfPosition') && isfield(r0, 'channelOfPosition') && ~isequal(r.channelOfPosition, r0.channelOfPosition)
        c.errors{end+1} = sprintf('%s has another microphone mapping', who);
    end
    if ~strcmp(r.calibration.version, r0.calibration.version)
        c.errors{end+1} = sprintf('%s used calibration %s, load %s used %s', who, r.calibration.version, ...
            loads(1).role, r0.calibration.version);
    end
    if ~strcmp(r.kind, r0.kind)
        c.errors{end+1} = sprintf('%s is a %s measurement, load %s a %s measurement', who, r.kind, loads(1).role, r0.kind);
    end
    if isfield(loads, 'load') && ~isempty(loads(i).load) && ~isempty(loads(1).load) && ...
            ~strcmp(loads(i).role, 'A2') && ~strcmp(loads(1).role, 'A2')
        d1 = tim.app.describeLoad(loads(1).load); d2 = tim.app.describeLoad(loads(i).load);
        if strcmp(d1.tag, d2.tag)
            c.errors{end+1} = sprintf('load %s and %s are both "%s": the two-load method needs different terminations', ...
                loads(1).role, loads(i).role, d1.label);
        end
    end
    T0 = NaN; T1 = NaN;
    if isfield(loads, 'cfg') && ~isempty(loads(1).cfg) && ~isempty(loads(i).cfg)
        T0 = loads(1).cfg.environment.temperature_C; T1 = loads(i).cfg.environment.temperature_C;
    end
    if abs(T1 - T0) > ms.maxTemperatureDiff_C
        c.warnings{end+1} = sprintf('%s was measured at %.1f °C, load %s at %.1f °C (more than %g K apart)', ...
            who, T1, loads(1).role, T0, ms.maxTemperatureDiff_C);
    end
    dt = minutesBetween(r0.timestamp, r.timestamp);
    if dt > ms.maxMinutesBetween
        c.warnings{end+1} = sprintf('%s was measured %.0f min after load %s (more than %g min)', who, dt, ...
            loads(1).role, ms.maxMinutesBetween);
    end
end
end

function tf = sameGeometry(a1, a0, c1, c0)
% port positions and specimen faces of the analyses; the diameter from the
% configurations when both are known
v1 = {a1.geometry.x}; v0 = {a0.geometry.x};
if isfield(a1, 'boundary') && isfield(a0, 'boundary') && isfield(a1.boundary, 'xFront') && isfield(a0.boundary, 'xFront')
    v1 = [v1, {a1.boundary.xFront, a1.boundary.xRear}]; v0 = [v0, {a0.boundary.xFront, a0.boundary.xRear}];
end
if ~isempty(c1) && ~isempty(c0)
    v1{end+1} = c1.geometry.diameter; v0{end+1} = c0.geometry.diameter;
end
tf = true;
for i = 1:numel(v1)
    a = v1{i}; b = v0{i};
    if numel(a) ~= numel(b) || any(abs(a(:) - b(:)) > 1e-7 & ~(isnan(a(:)) & isnan(b(:))))
        tf = false;
    end
end
end

function m = minutesBetween(t0, t1)
m = NaN;
try
    fmt = 'yyyy-MM-dd HH:mm:ss.SSS';
    m = abs(minutes(datetime(t1, 'InputFormat', fmt) - datetime(t0, 'InputFormat', fmt)));
catch
end
end

function v = ternary(c, a, b)
if c, v = a; else, v = b; end
end
