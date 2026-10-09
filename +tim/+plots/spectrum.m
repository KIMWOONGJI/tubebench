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
%   dB re 1 V²/Hz.
%   Stepped sine: the PSD of the record is a line spectrum (one narrow line
%   per step, each holding 1/nSteps of the energy) and is no level display.
%   Shown instead: the tone level of every step and channel from the sine
%   fit of the settled part (res.toneLevels, markers) and the residual
%   noise in the fit bandwidth (dotted). Before processing the PSD is drawn
%   grey with this explanation. Title: kind and time of the record
%   (tim.plots.dataTitle without the calibration tag - neither the PSD nor
%   the tone levels use the complex calibration).
%
%   opts (all optional): .band [fMin fMax] (default [120 4500]),
%   .simulation, .emptyText, .stepped (default from res.kind / meas.kind).
%   info: .summary  PSD: Channel | Port | Level in the band | Overall level
%                   stepped: Channel | Port | Min / Max tone level | Median SNR
%         .note     explanation for the header of the view
%         .lines    one handle per channel (PSD or tone levels)
%         .axes     the axes

if nargin < 4 || isempty(opts), opts = struct(); end
o = defaults(opts, res);
P = tim.gui.palette();
legend(ax, 'off');
cla(ax); hold(ax, 'on');
ax.XScale = 'log'; ax.YScale = 'linear';         % before style: a log scale switches minor ticks on
tim.plots.style(ax);
hasMeas = ~isempty(meas) && isstruct(meas) && isfield(meas, 'records') && ~isempty(meas.records);
hasRes = ~isempty(res) && isstruct(res);
src = []; if hasRes, src = res; elseif hasMeas, src = meas; end
stepped = o.stepped;
if isempty(stepped), stepped = ~isempty(src) && isfield(src, 'kind') && strcmp(src.kind, 'stepped'); end
info = struct('summary', emptySummary(), 'note', '', 'lines', gobjects(0), 'axes', ax);
xlabel(ax, 'Frequency [Hz]');

% ---- stepped sine, processed: tone level of every step
if stepped && hasRes && isfield(res, 'toneLevels')
    info = steppedLevels(ax, res, meas, o, P, info);
    hold(ax, 'off');
    title(ax, titleOf(meas, res, o));
    return
end

% ---- PSD (sweep / noise / background; stepped before processing in grey)
[f, G, pa, fs] = psd(meas, res, hasMeas, hasRes);
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
    info.summary = psdSummary([], [], [], [], o.band, fs, true);
    return
end
if pa
    ref = 2e-5; ylabel(ax, 'PSD [dB re (20 \muPa)^2/Hz]');
else
    ref = 1; ylabel(ax, 'PSD [dB re 1 V^2/Hz]');
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
    tim.plots.legend(ax, [h hb], [names, {bandName(o.band)}]);
    if pa
        info.note = 'One-sided Welch PSD of the sound pressure (repetition 1, whole record); dashed: analysis band.';
    else
        info.note = 'No valid sensitivity for every channel: PSD of the channel voltages; dashed: analysis band.';
    end
end
title(ax, titleOf(meas, res, o));
info.lines = h;
info.summary = psdSummary(f, G, ch, port, o.band, fs, pa);
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

function [f, G, pa, fs] = psd(meas, res, hasMeas, hasRes)
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
if isfield(meas, 'mics') && isfield(meas.mics, 'sensitivity_VperPa') && numel(meas.mics) >= size(x, 2)
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
h = gobjects(1, C);
for c = 1:C
    col = P.ch(ch(c), :);
    plot(ax, fk, nz(:, c), ':', 'Color', col, 'LineWidth', 1.1);
    h(c) = plot(ax, fk, lv(:, c), '-', 'Color', col, 'LineWidth', 1, 'Marker', 'o', ...
        'MarkerSize', 5, 'MarkerFaceColor', col, 'MarkerEdgeColor', col);
end
hn = plot(ax, NaN, NaN, ':', 'Color', [0.35 0.35 0.35], 'LineWidth', 1.1);     % legend entry only
if pa, ylabel(ax, 'Tone level [dB SPL]'); else, ylabel(ax, 'Tone level [dB re 1 V]'); end
names = arrayfun(@(c) channelName(ch(c), port(c)), 1:C, 'UniformOutput', false);
tim.plots.fitAxes(ax, 'XRange', o.band, 'XInclude', [min(fk) max(fk)]);
tim.plots.fitAxes(ax, 'Axis', 'y', 'YSteps', [1 2 5]);
tim.plots.legend(ax, [h hn], [names, {'Noise in fit bandwidth'}]);
info.lines = h;
info.note = sprintf(['Stepped sine, %d steps: tone level of every step from the sine fit of the settled part ' ...
    '(markers); dotted: residual noise in the fit bandwidth.'], numel(fk));
% summary
unit = 'dB SPL'; if ~pa, unit = 'dB re 1 V'; end
cols = {'Channel', 'Port', sprintf('Min tone level [%s]', unit), sprintf('Max tone level [%s]', unit), ...
    'Median SNR [dB]'};
D = cell(C, numel(cols));
for c = 1:C
    snr = lv(:, c) - nz(:, c);
    D(c, :) = {sprintf('ch%d', ch(c)), portText(port(c)), num(min(lv(:, c)), '%.1f'), ...
        num(max(lv(:, c)), '%.1f'), num(median(snr, 'omitnan'), '%.1f')};
end
info.summary = struct('title', 'Step levels', 'columns', {cols}, 'data', {D}, ...
    'note', 'SNR = tone level − residual noise in the fit bandwidth (per step, minimum over repetitions).');
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

function S = psdSummary(f, G, ch, port, band, fs, pa)
% band level = 10 log10(sum(PSD) df / p0^2): integral of the PSD over the band
unit = 'dB SPL'; if ~pa, unit = 'dB re 1 V'; end
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
