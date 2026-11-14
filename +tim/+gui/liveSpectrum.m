function varargout = liveSpectrum(action, varargin)
%LIVESPECTRUM Live spectrum of the sound pressure (Measurement > Spectrum during an action).
%
%   S = tim.gui.liveSpectrum('prepare', ax, o)   empty live axes before the data stream
%   S = tim.gui.liveSpectrum('update', S, x)     new estimate from the last samples x (rows x C)
%   n = tim.gui.liveSpectrum('samples', fs)      samples of one estimate (the last 1 s)
%   [f, G] = tim.gui.liveSpectrum('psd', x, fs)  the estimate itself (tests)
%   s = tim.gui.liveSpectrum('labels', yl)       the y tick labels of the limits yl (tests)
%
%   Owner request 2026-11-15: during a measurement the Spectrum view shows the
%   spectrum of every channel live, and an action opens it instead of the
%   time signals. The estimate is that of the result view (tim.plots.spectrum,
%   res.pressureSpectrum) over the last 1 s: one-sided Welch PSD, Hann
%   window, nfft = min(8192, 2^floor(log2(N))), 75 % overlap, in
%   dB re (20 µPa)²/Hz, or dB re 1 V²/Hz without a valid sensitivity for every
%   channel.
%
%   The live axes do not move (as the live time signals, 1.6.2-1.6.4): the
%   frequency axis is fixed (octave ticks, 20 Hz to fs/2), the legend and the
%   analysis band lines are drawn once, and the y range only grows during an
%   action, on a 20 dB grid, from -20..100 dB (Pa) or -160..-40 dB (V). The y
%   tick labels all have one width (four places, right-aligned: the digits,
%   the minus sign U+2212 next to them, figure spaces U+2007 in front), so the
%   plot area keeps its place when the range grows. The axes are not "fitted": the ruler callback of
%   tim.plots.fitAxes is made inert (its record removed), see tim.gui.liveAxis.
%
%   o (prepare): .fs, .pa (true: x in Pa, else V), .names (1xC, legend),
%       .colours (Cx3), .band [fMin fMax] (dashed lines), .emptyText
%   S: .ax, .lines, .fs, .pa, .ylim, .level (1xC: level 20 Hz .. fs/2 of the
%       last estimate, dB SPL or dB re 1 V), .f, .L (the curves drawn)

switch action
    case 'prepare', varargout{1} = prepare(varargin{:});
    case 'update', varargout{1} = update(varargin{:});
    case 'samples', varargout{1} = max(256, round(varargin{1}));
    case 'psd', [varargout{1}, varargout{2}] = psd(varargin{:});
    case 'labels', varargout{1} = labels(varargin{1});
    otherwise, error('tim:gui:liveSpectrum', 'Unknown action "%s".', action);
end
end

% ---------------------------------------------------------------------------
function S = prepare(ax, o)
C = numel(o.names);
legend(ax, 'off');
hideRightAxis(ax);                               % the incident level of a swept-sine result
cla(ax); hold(ax, 'on');
ax.XScale = 'log'; ax.YScale = 'linear';
tim.plots.style(ax);
xlabel(ax, 'Frequency [Hz]');
if o.pa
    ylabel(ax, 'PSD [dB re (20 \muPa)^2/Hz]'); yl = [-20 100];
else
    ylabel(ax, 'PSD [dB re 1 V^2/Hz]'); yl = [-160 -40];
end
h = gobjects(1, C);
for c = 1:C
    h(c) = plot(ax, NaN, NaN, '-', 'Color', o.colours(c, :), 'LineWidth', 1.1, 'Tag', sprintf('timLiveSpec%d', c));
end
hb = xline(ax, o.band(1), '--', 'Color', [0.45 0.45 0.45], 'LineWidth', 0.9);
xline(ax, o.band(2), '--', 'Color', [0.45 0.45 0.45], 'LineWidth', 0.9);
hold(ax, 'off');
tim.plots.legend(ax, [h hb], [o.names, {sprintf('Analysis band %g – %g Hz', o.band(1), o.band(2))}], 'northoutside');
% the house-style octave ticks once, then no fitted record: the ruler callback
% of fitAxes would take every live limit change for a user zoom (1.6.3)
tim.plots.fitAxes(ax, 'Axis', 'x', 'XRange', [20 o.fs / 2]);
if isappdata(ax, 'timFitAxes'), rmappdata(ax, 'timFitAxes'); end
ax.YAxis(1).Exponent = 0;                        % (a hidden right axis of a result may remain)
setY(ax, yl);
msg = 'Waiting for data ...'; if isfield(o, 'emptyText') && ~isempty(o.emptyText), msg = o.emptyText; end
tim.plots.emptyState(ax, msg);
S = struct('ax', ax, 'lines', h, 'fs', o.fs, 'pa', logical(o.pa), 'ylim', yl, ...
    'level', nan(1, C), 'f', [], 'L', []);
end

function S = update(S, x)
% x: the last samples (Pa or V), rows x C, without NaN rows
x = x(all(isfinite(x), 2), :);
[f, G] = psd(x, S.fs);
if isempty(f), return; end
if S.pa, ref = 2e-5; else, ref = 1; end
keep = f >= 20;
L = 10 * log10(G(keep, :) / ref^2);
L(~isfinite(L)) = NaN;
fk = f(keep);
tim.plots.emptyState(S.ax, '');
for c = 1:min(numel(S.lines), size(L, 2))
    if isgraphics(S.lines(c)), set(S.lines(c), 'XData', fk, 'YData', L(:, c)); end
end
% the y range only grows (20 dB grid): the top 5 dB above the highest value,
% the bottom 5 dB below the 2 % quantile (deep notches do not widen it)
v = sort(L(isfinite(L)));
if ~isempty(v)
    lo = v(max(1, round(0.02 * numel(v)))) - 5;
    hi = v(end) + 5;
    yl = [min(S.ylim(1), 20 * floor(lo / 20)), max(S.ylim(2), 20 * ceil(hi / 20))];
    if ~isequal(yl, S.ylim), S.ylim = yl; setY(S.ax, yl); end
end
df = f(2) - f(1);
S.level = 10 * log10(sum(G(keep, :), 1) * df / ref^2);
S.f = fk; S.L = L;
end

function [f, G] = psd(x, fs)
% one-sided Welch PSD as tim.plots.spectrum / res.pressureSpectrum
f = []; G = [];
N = size(x, 1);
if N < 256, return; end
nfft = min(8192, 2^floor(log2(N)));
x = x - mean(x, 1);
[G, f] = pwelch(x, hann(nfft, 'periodic'), 3 * nfft / 4, nfft, fs);
end

function setY(ax, yl)
t = yl(1):20:yl(2);
ax.YLim = yl; ax.YTick = t;
ax.YTickLabel = labels(yl);
end

function s = labels(yl)
% one width for every label: four places, right-aligned - the digits, the
% minus sign (U+2212, as wide as a digit) next to them, figure spaces in front
fig = char(8199); minus = char(8722);
v = yl(1):20:yl(2);
s = cell(1, numel(v));
for i = 1:numel(v)
    a = sprintf('%d', round(abs(v(i))));
    if v(i) < 0, a = [minus a]; end %#ok<AGROW>
    s{i} = [repmat(fig, 1, max(0, 4 - numel(a))), a];
end
end

function hideRightAxis(ax)
% the right y axis of an earlier result (tim.plots.spectrum): emptied and hidden
if numel(ax.YAxis) < 2, return; end
yyaxis(ax, 'right');
cla(ax); ylabel(ax, '');
if numel(ax.YAxis) > 1
    ax.YAxis(2).Visible = 'off';
    yyaxis(ax, 'left');
end
end
