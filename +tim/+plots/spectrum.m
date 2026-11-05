function info = spectrum(ax, meas, res, opts)
%SPECTRUM Spectra of the sound pressure (view Measurement > Spectrum).
%   info = tim.plots.spectrum(ax, meas, res)
%   info = tim.plots.spectrum(ax, meas, [])              before processing / background noise
%   info = tim.plots.spectrum(ax, [], [], opts)          empty view
%
%   Swept sine, random noise, background noise: power spectral density of
%   the sound pressure of repetition 1 in dB re (20 µPa)²/Hz (one-sided
%   Welch estimate: Hann window, nfft = min(8192, 2^nextpow2(N)), 50 %
%   overlap - res.pressureSpectrum when res is given, else computed from
%   meas in the same way). The analysis band is marked by two dashed lines.
%   Without a valid sensitivity for every channel: PSD of the voltages in
%   dB re 1 V²/Hz; data in full-scale units (meas.unit 'FS', a driver with an
%   unknown input scale) in dB re 1 FS²/Hz, without sensitivities.
%   Stepped sine: the PSD of the record is a line spectrum (one narrow line
%   per step, each holding 1/nSteps of the energy) and is no level display.
%   Shown instead: the tone level of every step and channel from the sine
%   fit of the settled part (res.toneLevels, markers) and the residual
%   noise in the fit bandwidth (dotted). Before processing the PSD is drawn
%   grey with this explanation. Title: kind and time of the record
%   (tim.plots.dataTitle without the calibration tag - neither the PSD nor
%   the tone levels use the complex calibration).
%   Level at the specimen (1.6.0, WO-006 stage 1; res.levels of a calibrated
%   swept or stepped sine with known faces): the incident wave at the specimen
%   front face in black (lines that are not valid in grey; Tag
%   'timLevelIncident'). Stepped sine: squares on the tone-level axis (dB SPL);
%   swept sine: a curve on a right y axis in dB SPL (the sine-equivalent level
%   of the sweep; the left axis stays the PSD). Nothing is added for a result
%   without it (uncalibrated, faces unknown, noise, older results), and the
%   right axis of an earlier drawing on the same axes is emptied and hidden.
%   Equalized stepped sine (res.equalizer, 1.6.0, WO-006 stage 2): the target
%   as a dashed line (Tag 'timEqTarget') in a light green band of ± the
%   tolerance (Tag 'timEqBand'). Incident pressure: on the tone-level axis,
%   next to the black squares. Face velocity: the particle velocity at the
%   front face (black triangles, Tag 'timLevelVelocity'; grey where not
%   valid) with its target on a right y axis in mm/s. Lines and patches, no
%   ConstantLine (the analysis band lines of the PSD are the only ones).
%
%   opts (all optional): .band [fMin fMax] (default [120 4500]),
%   .simulation, .emptyText, .stepped (default from res.kind / meas.kind).
%   info: .summary  PSD: Channel | Port | Level in the band | Overall level
%                   stepped: Channel | Port | Min / Max tone level | Median SNR
%         .note     explanation for the header of the view
%         .lines    one handle per channel (PSD or tone levels)
%         .levels   level at the specimen: .shown, .axis ('left' | 'right'),
%                   .lines (the black curve)
%         .equalizer  target of an equalized stepped sine: .shown, .mode,
%                   .axis ('left' | 'right'), .lines (band, target line and,
%                   face velocity, the velocity curve)
%         .axes     the axes

if nargin < 4 || isempty(opts), opts = struct(); end
o = defaults(opts, res);
o.dataUnit = dataUnit(meas, res);              % 'V', or 'FS' (input scale unknown)
P = tim.gui.palette();
legend(ax, 'off');
hideRightAxis(ax);                               % the incident level of an earlier sweep
cla(ax); hold(ax, 'on');
ax.XScale = 'log'; ax.YScale = 'linear';         % before style: a log scale switches minor ticks on
tim.plots.style(ax);
hasMeas = ~isempty(meas) && isstruct(meas) && isfield(meas, 'records') && ~isempty(meas.records);
hasRes = ~isempty(res) && isstruct(res);
src = []; if hasRes, src = res; elseif hasMeas, src = meas; end
stepped = o.stepped;
if isempty(stepped), stepped = ~isempty(src) && isfield(src, 'kind') && strcmp(src.kind, 'stepped'); end
info = struct('summary', emptySummary(), 'note', '', 'lines', gobjects(0), ...
    'levels', struct('shown', false, 'axis', '', 'lines', gobjects(0)), ...
    'equalizer', struct('shown', false, 'mode', '', 'axis', '', 'lines', gobjects(0)), 'axes', ax);
xlabel(ax, 'Frequency [Hz]');

% ---- stepped sine, processed: tone level of every step
if stepped && hasRes && isfield(res, 'toneLevels')
    info = steppedLevels(ax, res, meas, o, P, info);
    hold(ax, 'off');
    title(ax, titleOf(meas, res, o));
    return
end

% ---- PSD (sweep / noise / background; stepped before processing in grey)
[f, G, pa, fs] = psd(meas, res, hasMeas, hasRes, o.dataUnit);
if isempty(f)
    ylabel(ax, 'PSD [dB re (20 \muPa)^2/Hz]');
    hb = bandLines(ax, o.band);
    hold(ax, 'off');
    tim.plots.legend(ax, hb, {bandName(o.band)}, 'northeast');
    tim.plots.fitAxes(ax, 'XRange', [20 8192]);
    tim.plots.fitAxes(ax, 'Axis', 'y', 'YRange', [-20 60], 'YSteps', [1 2 5]);
    title(ax, blankTitle(o.simulation));
    msg = 'No measurement yet';
    if hasMeas || hasRes, msg = 'No pressure spectrum available'; end
    if ~isempty(o.emptyText), msg = o.emptyText; end
    tim.plots.emptyState(ax, msg);
    info.summary = psdSummary([], [], [], [], o.band, fs, true, o.dataUnit);
    return
end
if pa
    ref = 2e-5; ylabel(ax, 'PSD [dB re (20 \muPa)^2/Hz]');
else
    ref = 1; ylabel(ax, sprintf('PSD [dB re 1 %s^2/Hz]', o.dataUnit));
end
[ch, port] = channelPorts(meas, res, size(G, 2));
keep = f >= 20;
L = 10 * log10(G(keep, :) / ref^2);
L(~isfinite(L)) = NaN;
h = gobjects(1, size(G, 2));
for c = 1:size(G, 2)
    if stepped, col = P.invalid; else, col = P.ch(ch(c), :); end
    h(c) = plot(ax, f(keep), L(:, c), '-', 'Color', col, 'LineWidth', 1.1);
end
hb = bandLines(ax, o.band);
hold(ax, 'off');
names = arrayfun(@(c) channelName(ch(c), port(c)), 1:numel(ch), 'UniformOutput', false);
itxt = '';                                       % summary text of the level at the specimen
if stepped
    tim.plots.fitAxes(ax, 'XRange', [20 fs / 2]);
    tim.plots.fitAxes(ax, 'Axis', 'y', 'YSteps', [1 2 5], 'YInclude', max(L(:)) + 0.3 * (max(L(:)) - min(L(:))));
    em = tim.plots.emptyState(ax, sprintf(['Stepped sine: the PSD of the record is a line spectrum ' ...
        '(one line per step).\nThe tone level of every step is shown after processing.']));
    em.Position(2) = 0.9;                            % in the headroom above the grey PSD
    em.BackgroundColor = ax.Color;                   % the band lines pass behind the text
    info.note = 'Grey: PSD of the raw stepped record (not a level display); step levels follow after processing.';
else
    tim.plots.fitAxes(ax, 'XRange', [20 fs / 2]);
    tim.plots.fitAxes(ax, 'Axis', 'y', 'YSteps', [1 2 5], 'YInclude', minSpan(L, 40));
    % level at the specimen (swept sine): right axis, after the left one is fitted
    hi = gobjects(0); iname = {};
    if hasRes && pa, [hi, iname, itxt] = specimenCurves(ax, res, P, false); end
    tim.plots.legend(ax, [h hi hb], [names, iname, {bandName(o.band)}]);
    if pa
        info.note = 'One-sided Welch PSD of the sound pressure (repetition 1, whole record); dashed: analysis band.';
        if ~isempty(hi)
            info.note = [info.note ' Black (right axis): incident wave at the front face, sine-equivalent.'];
        end
    elseif strcmp(o.dataUnit, 'V')
        info.note = 'No valid sensitivity for every channel: PSD of the channel voltages; dashed: analysis band.';
    else
        info.note = sprintf(['Data in %s (input scale unknown): PSD of the channel signals, no sound pressure; ' ...
            'dashed: analysis band.'], o.dataUnit);
    end
    info.levels = struct('shown', ~isempty(hi), 'axis', 'right', 'lines', hi);
end
title(ax, titleOf(meas, res, o));
info.lines = h;
info.summary = psdSummary(f, G, ch, port, o.band, fs, pa, o.dataUnit);
info.summary.note = [info.summary.note itxt];
end

% ---------------------------------------------------------------------------
function t = titleOf(meas, res, o)
% kind and time of the record; no calibration tag: spectra and tone levels use
% only the sensitivities, never the complex calibration
if ~isempty(res) && isstruct(res)
    s = res;
    if isfield(s, 'calibration'), s = rmfield(s, 'calibration'); end
else
    s = meas;
end
t = tim.plots.dataTitle(s, struct('simulation', o.simulation));
end

function o = defaults(opts, res)
o = struct('band', [120 4500], 'simulation', false, 'emptyText', '', 'stepped', []);
if ~isempty(res) && isstruct(res) && isfield(res, 'analysis') && isfield(res.analysis, 'options') && ...
        isfield(res.analysis.options, 'fRange') && numel(res.analysis.options.fRange) == 2
    o.band = res.analysis.options.fRange;           % band of the analysis
end
fn = fieldnames(opts);
for i = 1:numel(fn)
    if ~isempty(opts.(fn{i})) || strcmp(fn{i}, 'emptyText'), o.(fn{i}) = opts.(fn{i}); end
end
end

function [f, G, pa, fs] = psd(meas, res, hasMeas, hasRes, vu)
% one-sided PSD [Pa^2/Hz] from res.pressureSpectrum, else Welch from meas
% (same estimate as tim.app.processMeasurement); volts^2/Hz without sensitivities
f = []; G = []; pa = true; fs = 16384;
if hasMeas, fs = meas.fs; end
if hasRes && isfield(res, 'pressureSpectrum') && isfield(res.pressureSpectrum, 'PSD_Pa2perHz')
    ps = res.pressureSpectrum;
    if any(isfinite(ps.PSD_Pa2perHz(:)) & ps.PSD_Pa2perHz(:) > 0)
        f = ps.f(:); G = ps.PSD_Pa2perHz;
        if ~hasMeas, fs = 2 * max(f); end
        return
    end
end
if ~hasMeas, return; end
x = double(meas.records{1});
x = x - mean(x, 1);
s = nan(1, size(x, 2));
if strcmp(vu, 'V') && isfield(meas, 'mics') && isfield(meas.mics, 'sensitivity_VperPa') && numel(meas.mics) >= size(x, 2)
    s = [meas.mics.sensitivity_VperPa];
    s = s(micIndex(meas.mics, size(x, 2)));         % column c = DAQ channel c
end
pa = all(isfinite(s) & s > 0);
if pa, x = x ./ s; end
nfft = min(8192, 2^nextpow2(size(x, 1)));
[G, f] = pwelch(x, hann(nfft, 'periodic'), nfft / 2, nfft, fs);
end

function info = steppedLevels(ax, res, meas, o, P, info)
% tone level of every step (sine fit) and residual noise in the fit bandwidth
tl = res.toneLevels;
lv = tl.spl_dB; nz = tl.noise_dB; pa = true;
if ~any(isfinite(lv(:)))                          % no sensitivity: dB re 1 V (rms)
    pa = false;
    lv = 20 * log10(tl.amplitude_V / sqrt(2));
    nz = lv - res.spectra.snr_dB;
end
C = size(lv, 2);
[ch, port] = channelPorts(meas, res, C);
fk = tl.f(:);
% the band of an incident-pressure target goes on this axis BEFORE the data, so
% it lies behind them without restacking (uistack fails on the axes of a
% yyaxis drawing, which the window reuses)
hbL = gobjects(0);
e = equalizerOf(res);
if pa && levelsShown(res) && ~isempty(e) && strcmp(e.mode, 'incidentPressure')
    hbL = eqBand(ax, e, res.levels.f(:), P);
end
h = gobjects(1, C);
for c = 1:C
    col = P.ch(ch(c), :);
    plot(ax, fk, nz(:, c), ':', 'Color', col, 'LineWidth', 1.1);
    h(c) = plot(ax, fk, lv(:, c), '-', 'Color', col, 'LineWidth', 1, 'Marker', 'o', ...
        'MarkerSize', 5, 'MarkerFaceColor', col, 'MarkerEdgeColor', col);
end
hn = plot(ax, NaN, NaN, ':', 'Color', [0.35 0.35 0.35], 'LineWidth', 1.1);     % legend entry only
% level at the specimen: on this axis (dB SPL as the tone levels), before the fit
hi = gobjects(0); iname = {}; itxt = '';
if pa, [hi, iname, itxt] = specimenCurves(ax, res, P, true); end
% the target of an equalized stepped sine (1.6.0), with the incident level
he = gobjects(0); ename = {}; etxt = '';
if ~isempty(hi), [he, ename, etxt, info.equalizer] = equalizerTarget(ax, res, P, hbL); end
if pa, ylabel(ax, 'Tone level [dB SPL]'); else, ylabel(ax, sprintf('Tone level [dB re 1 %s]', o.dataUnit)); end
names = arrayfun(@(c) channelName(ch(c), port(c)), 1:C, 'UniformOutput', false);
tim.plots.fitAxes(ax, 'XRange', o.band, 'XInclude', [min(fk) max(fk)]);
tim.plots.fitAxes(ax, 'Axis', 'y', 'YSteps', [1 2 5]);
tim.plots.legend(ax, [h hi he hn], [names, iname, ename, {'Noise in fit bandwidth'}]);
info.lines = h;
info.levels = struct('shown', ~isempty(hi), 'axis', 'left', 'lines', hi);
info.note = sprintf(['Stepped sine, %d steps: tone level of every step from the sine fit of the settled part ' ...
    '(markers); dotted: residual noise in the fit bandwidth.'], numel(fk));
if ~isempty(hi)
    info.note = [info.note ' Black squares: incident wave at the front face.'];
end
if info.equalizer.shown
    if strcmp(info.equalizer.mode, 'faceVelocity')
        info.note = [info.note ' Triangles (right axis): face velocity; dashed in green: its target ± tolerance.'];
    else
        info.note = [info.note ' Dashed in green: the equalizer target ± tolerance.'];
    end
end
itxt = [itxt etxt];
% summary
unit = 'dB SPL'; if ~pa, unit = ['dB re 1 ' o.dataUnit]; end
cols = {'Channel', 'Port', sprintf('Min tone level [%s]', unit), sprintf('Max tone level [%s]', unit), ...
    'Median SNR [dB]'};
D = cell(C, numel(cols));
for c = 1:C
    snr = lv(:, c) - nz(:, c);
    D(c, :) = {sprintf('ch%d', ch(c)), portText(port(c)), num(min(lv(:, c)), '%.1f'), ...
        num(max(lv(:, c)), '%.1f'), num(median(snr, 'omitnan'), '%.1f')};
end
info.summary = struct('title', 'Step levels', 'columns', {cols}, 'data', {D}, ...
    'note', ['SNR = tone level − residual noise in the fit bandwidth (per step, minimum over repetitions).' itxt]);
end

function [h, name, txt] = specimenCurves(ax, res, P, stepped)
% level at the specimen front face (res.levels, 1.6.0, WO-006 stage 1): the
% incident wave in black, the lines that are not valid in grey. Stepped sine:
% squares on the tone-level axis (dB SPL; never Marker 'o' or a dotted line,
% which are the channels and the noise); swept sine: a curve on the right y
% axis (the left one is a PSD), fitted on its own; the left axis stays the
% fitted, active one. Nothing for a result without it (uncalibrated, faces
% unknown, random noise, results before 1.6.0).
h = gobjects(0); name = {}; txt = '';
if ~levelsShown(res), return; end
lv = res.levels;
fk = lv.f(:); y = lv.incident_dB_SPL(:);
ok = lv.valid(:) & isfinite(y);
if stepped
    yv = y; yv(~ok) = NaN;
    plot(ax, fk, y, '-', 'Color', P.invalid, 'LineWidth', 0.6, 'Marker', 's', 'MarkerSize', 6, ...
        'MarkerEdgeColor', P.invalidMarker, 'MarkerFaceColor', 'w', 'Tag', 'timLevelIncidentAll');
    h = plot(ax, fk, yv, '-', 'Color', P.q.first, 'LineWidth', 1.4, 'Marker', 's', 'MarkerSize', 6, ...
        'MarkerEdgeColor', P.q.first, 'MarkerFaceColor', P.q.first, 'Tag', 'timLevelIncident');
    name = {'Incident wave at the front face'};
else
    S = getappdata(ax, 'timFitAxes');              % limits and ticks of the fitted left axis
    yyaxis(ax, 'right');
    c = ax.XColor;                                 % house style colour of the axes
    ax.YAxis(1).Color = c; ax.YAxis(2).Color = c;   % not the colour order of yyaxis
    ax.YAxis(2).Visible = 'on';
    hold(ax, 'on');
    [h, hAll] = tim.plots.masked(ax, fk, y, ok, P.q.first);
    h.Tag = 'timLevelIncident'; hAll.Tag = 'timLevelIncidentAll';
    ylabel(ax, 'Incident wave at the front face [dB SPL]');
    v = y(isfinite(y));
    tim.plots.fitAxes(ax, 'Axis', 'y', 'YRange', [min(v) max(v)], 'YSteps', [1 2 5]);
    setappdata(ax, 'timFitAxes', S);               % the fit of the left axis stays the reference
    hold(ax, 'off');
    yyaxis(ax, 'left');
    name = {'Incident wave at the front face (sine-equivalent)'};
end
u = lv.faceVelocity_mm_s(ok);
txt = sprintf(' Front face (valid lines): incident %.1f–%.1f dB SPL, particle velocity %.3g–%.3g mm/s.', ...
    min(y(ok)), max(y(ok)), min(u), max(u));
end

function [h, name, txt, q] = equalizerTarget(ax, res, P, hb)
% the target of an equalized stepped sine (res.equalizer, 1.6.0, WO-006 stage
% 2; owner decisions 2026-11-04): a dashed line at the target in a light
% green band of ± the tolerance, drawn behind the data (a missed step is
% reported, never masked). Incident pressure: on the tone-level axis (dB
% SPL) of the black squares; its band hb was drawn by the caller before the
% data. Face velocity: the velocity at the front face (black triangles, grey
% where not valid) and its target on a right y axis in mm/s, fitted on its
% own, the band drawn first on that side; the left axis stays the active
% one. Never uistack: it fails on the axes of a yyaxis drawing. Nothing for
% a result without res.equalizer or with another number of steps.
h = gobjects(0); name = {}; txt = '';
q = struct('shown', false, 'mode', '', 'axis', '', 'lines', gobjects(0));
e = equalizerOf(res);
if isempty(e), return; end
lv = res.levels;
fk = lv.f(:);
xr = [min(fk) / 1.05, max(fk) * 1.05];
t = e.target; tol = e.tolerance_dB;
hv = gobjects(0);
switch e.mode
    case 'incidentPressure'
        band = t + [-tol tol];
        side = 'left';
        name = {sprintf('Target %g dB SPL ± %g dB', t, tol)};
        if isempty(hb), hb = eqBand(ax, e, fk, P); end
    case 'faceVelocity'
        band = t * 10.^([-tol tol] / 20);
        side = 'right';
        name = {'Face velocity at the front face', sprintf('Target %g mm/s ± %g dB', t, tol)};
        S = getappdata(ax, 'timFitAxes');          % the fit of the left axis (if any) stays the reference
        yyaxis(ax, 'right');
        c = ax.XColor;                             % house style colour of the axes, as the sweep's right axis
        ax.YAxis(1).Color = c; ax.YAxis(2).Color = c;
        ax.YAxis(2).Visible = 'on';
        hold(ax, 'on');
        hb = eqBand(ax, e, fk, P);                 % first on this side: behind the data
        u = lv.faceVelocity_mm_s(:);
        ok = lv.valid(:) & isfinite(u);
        uv = u; uv(~ok) = NaN;
        plot(ax, fk, u, '-', 'Color', P.invalid, 'LineWidth', 0.6, 'Marker', '^', 'MarkerSize', 6, ...
            'MarkerEdgeColor', P.invalidMarker, 'MarkerFaceColor', 'w', 'Tag', 'timLevelVelocityAll');
        hv = plot(ax, fk, uv, '-', 'Color', P.q.first, 'LineWidth', 1.4, 'Marker', '^', 'MarkerSize', 6, ...
            'MarkerEdgeColor', P.q.first, 'MarkerFaceColor', P.q.first, 'Tag', 'timLevelVelocity');
        ylabel(ax, 'Face velocity |u_L| [mm/s]');
    otherwise
        name = {};
        return
end
ht = plot(ax, xr, [t t], '--', 'Color', P.q.ref, 'LineWidth', 1, 'XLimInclude', 'off', 'Tag', 'timEqTarget');
if strcmp(side, 'right')
    v = [u(isfinite(u)); band(:)];
    tim.plots.fitAxes(ax, 'Axis', 'y', 'YRange', [min(v) max(v)], 'YSteps', [1 2 5]);
    setappdata(ax, 'timFitAxes', S);
    hold(ax, 'off');
    yyaxis(ax, 'left');
    hold(ax, 'on');                                % (the caller draws on)
end
h = [hv ht];
q = struct('shown', true, 'mode', e.mode, 'axis', side, 'lines', [hb ht hv]);
nMax = nnz(strcmp(e.limited, 'max'));
vMax = max(e.vpp);
if isfield(e, 'plan') && isstruct(e.plan) && isfield(e.plan, 'maxVpp'), vMax = e.plan.maxVpp; end
txt = sprintf(' Equalizer: target %g %s ± %g dB, %d of %d steps within (%d capped at the maximum %.3g Vpk).', ...
    t, e.unit, tol, nnz(e.reached), numel(e.reached), nMax, vMax / 2);
end

function e = equalizerOf(res)
% res.equalizer of an equalized stepped sine with one value per level line, else []
e = [];
if isfield(res, 'equalizer') && isstruct(res.equalizer) && isscalar(res.equalizer) && ...
        isfield(res.equalizer, 'reached') && isfield(res, 'levels') && isfield(res.levels, 'f') && ...
        numel(res.equalizer.reached) == numel(res.levels.f)
    e = res.equalizer;
end
end

function tf = levelsShown(res)
% the level at the specimen is drawn (res.levels available with a valid line)
tf = isfield(res, 'levels') && isstruct(res.levels) && isfield(res.levels, 'available') && ...
    res.levels.available && any(res.levels.valid);
end

function hb = eqBand(ax, e, fk, P)
% the light green band of ± the tolerance around the target, on the active
% side of the axes; drawn before the data of that side, so it lies behind them
xr = [min(fk) / 1.05, max(fk) * 1.05];
t = e.target; tol = e.tolerance_dB;
if strcmp(e.mode, 'faceVelocity'), band = t * 10.^([-tol tol] / 20); else, band = t + [-tol tol]; end
hb = patch(ax, xr([1 2 2 1]), band([1 1 2 2]), P.ok, 'FaceAlpha', 0.12, 'EdgeColor', 'none', ...
    'HitTest', 'off', 'XLimInclude', 'off', 'Tag', 'timEqBand');
end

function hideRightAxis(ax)
% the right y axis of an earlier drawing on these axes (the incident level of a
% swept sine, the face velocity of an equalized stepped sine) is emptied and
% hidden; never cla(ax, 'reset'), which would also
% remove the axes toolbar of the window (tim.gui.ViewPage). Ends on the left axis.
if numel(ax.YAxis) < 2, return; end
yyaxis(ax, 'right');
cla(ax);                                         % the active (right) side only
ylabel(ax, '');
if numel(ax.YAxis) > 1
    ax.YAxis(2).Visible = 'off';
    yyaxis(ax, 'left');
end
end

function y = minSpan(L, span)
% at least 'span' dB on the y axis (centred on the data): a flat noise floor
% then looks flat instead of filling the axes with its ±4 dB estimation scatter
v = L(isfinite(L));
y = [];
if isempty(v), return; end
lo = min(v); hi = max(v);
if hi - lo < span, c = (hi + lo) / 2; y = c + span / 2 * [-1 1]; end
end

function hb = bandLines(ax, band)
% analysis band: two light dashed lines (ConstantLine: not part of the limits)
hb = xline(ax, band(1), '--', 'Color', [0.45 0.45 0.45], 'LineWidth', 0.9);
xline(ax, band(2), '--', 'Color', [0.45 0.45 0.45], 'LineWidth', 0.9);
end

function s = bandName(band)
s = sprintf('Analysis band %s – %s Hz', freqText(band(1)), freqText(band(2)));
end

function s = freqText(f)
s = sprintf('%g', f);
end

function S = psdSummary(f, G, ch, port, band, fs, pa, vu)
% band level = 10 log10(sum(PSD) df / p0^2): integral of the PSD over the band
unit = 'dB SPL'; if ~pa, unit = ['dB re 1 ' vu]; end
cols = {'Channel', 'Port', sprintf('Level %g–%g Hz [%s]', band(1), band(2), unit), ...
    sprintf('Overall %g Hz – %.4g kHz [%s]', 20, fs / 2000, unit)};
if isempty(f)
    D = [arrayfun(@(c) sprintf('ch%d', c), (1:4).', 'UniformOutput', false), repmat({'–'}, 4, 3)];
    S = struct('title', 'Levels', 'columns', {cols}, 'data', {D}, 'note', '');
    return
end
if pa, ref = 2e-5; else, ref = 1; end
df = f(2) - f(1);
inBand = f >= band(1) & f <= band(2);
all20 = f >= 20;
C = size(G, 2);
D = cell(C, numel(cols));
for c = 1:C
    D(c, :) = {sprintf('ch%d', ch(c)), portText(port(c)), ...
        num(10 * log10(sum(G(inBand, c)) * df / ref^2), '%.1f'), ...
        num(10 * log10(sum(G(all20, c)) * df / ref^2), '%.1f')};
end
S = struct('title', 'Levels', 'columns', {cols}, 'data', {D}, ...
    'note', 'Level = PSD integrated over the frequency range (mean over the whole record, incl. pre- and post-roll).');
end

function u = dataUnit(meas, res)
% unit of the recorded data: 'V', or 'FS' from a driver with an unknown input
% scale (meas.unit; a result keeps it in toneLevels / pressureSpectrum)
u = 'V';
if ~isempty(meas) && isstruct(meas) && isfield(meas, 'unit') && ~isempty(meas.unit)
    u = char(meas.unit);
elseif ~isempty(res) && isstruct(res)
    if isfield(res, 'pressureSpectrum') && isfield(res.pressureSpectrum, 'unit')
        u = char(res.pressureSpectrum.unit);
    elseif isfield(res, 'toneLevels') && isfield(res.toneLevels, 'unit')
        u = char(res.toneLevels.unit);
    end
end
end

function S = emptySummary()
S = struct('title', '', 'columns', {{}}, 'data', {{}}, 'note', '');
end

function [ch, port] = channelPorts(meas, res, C)
% column c = DAQ channel c (as res.spectra / res.Hchannel in tim.app.processMeasurement);
% its tube port from res.channelOfPosition, else from the microphone on channel c
ch = 1:C; port = nan(1, C);
if ~isempty(meas) && isstruct(meas) && isfield(meas, 'mics') && isfield(meas.mics, 'position')
    k = micIndex(meas.mics, C);
    for c = 1:C
        if k(c) <= numel(meas.mics) && ~isempty(meas.mics(k(c)).position), port(c) = meas.mics(k(c)).position; end
    end
end
if ~isempty(res) && isstruct(res) && isfield(res, 'channelOfPosition')
    for c = 1:C
        m = find(res.channelOfPosition == c, 1);
        if ~isempty(m), port(c) = m; end
    end
end
end

function k = micIndex(mics, n)
% k(c) = index of the microphone on DAQ channel c (mics(k).channel == c)
k = 1:n;
if isempty(mics) || ~isfield(mics, 'channel'), return; end
chs = [mics.channel];
for c = 1:n
    i = find(chs == c, 1);
    if ~isempty(i), k(c) = i; end
end
end

function s = channelName(ch, port)
if isfinite(port), s = sprintf('ch%d (M%d)', ch, port); else, s = sprintf('ch%d', ch); end
end

function s = portText(port)
if isfinite(port), s = sprintf('M%d', port); else, s = '–'; end
end

function s = num(v, fmt)
if isempty(v) || ~isfinite(v), s = '–'; else, s = sprintf(fmt, v); end
end

function s = blankTitle(sim)
if sim, s = 'SIMULATION'; else, s = ' '; end
end
