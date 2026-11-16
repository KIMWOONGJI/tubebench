function varargout = liveSpectrum(action, varargin)
%LIVESPECTRUM Live spectrum of the sound pressure (Measurement > Spectrum during an action).
%
%   S = tim.gui.liveSpectrum('prepare', ax, o)      empty live axes before the data stream
%   S = tim.gui.liveSpectrum('update', S, get, prog) one refresh
%   n = tim.gui.liveSpectrum('samples', fs)         samples of the live estimate (the last 1 s)
%   [f, G] = tim.gui.liveSpectrum('psd', x, fs)     the estimate itself (tests)
%   s = tim.gui.liveSpectrum('labels', yl)          the y tick labels of the limits yl (tests)
%
%   Owner requests 2026-11-15: during a measurement the Spectrum view shows
%   the spectrum live, and an action opens it instead of the time signals;
%   the swept and the stepped sine in dB SPL, each with two kinds of curve
%   in the colour of its channel:
%     - the LIVE curve, light and thin: the last 1 s (stepped sine: 0.25 s, one step);
%     - the RESULT so far, in full colour as the result view draws it: it
%       grows during the measurement and is the result view when it ends.
%   o.kind
%     'sweep'    live: the sine-equivalent level of the last 1 s; result: the
%                same of the Welch average over repetition 1 so far
%                (tim.dsp.sweepSineLevel: PSD x record length x sweep rate),
%                "Level [dB SPL]"
%     'stepped'  live: the power spectrum of the last 0.25 s (one step: a tone's peak = its
%                level, Hann window: PSD x equivalent noise bandwidth); result:
%                the tone level of every step whose measured part has ended
%                (sine fit of that part, mean over the repetitions, markers),
%                "Tone level [dB SPL]"
%     'psd'      the background noise: the PSD of the last 1 s, full colour
%   The estimate is that of the result (tim.plots.spectrum,
%   res.pressureSpectrum): one-sided Welch PSD, Hann window, nfft =
%   min(8192, 2^floor(log2(N))), 75 % overlap; dB re 1 V without a valid
%   sensitivity for every channel. The result so far is computed from the
%   new samples only (the periodograms of the new segments are added), so a
%   refresh costs about as much as the live curve.
%
%   The live axes do not move (as the live time signals, 1.6.2-1.6.4): the
%   frequency axis is fixed, the legend and the analysis band lines are drawn
%   once, and the y range only grows during an action, on a 20 dB grid. The y
%   tick labels all have one width (four places, right-aligned: the digits,
%   the minus sign U+2212 next to them, figure spaces U+2007 in front), so the
%   plot area keeps its place when the range grows. The axes are not
%   "fitted": the ruler callback of tim.plots.fitAxes is made inert (its
%   record removed), see tim.gui.liveAxis.
%
%   o (prepare): .kind, .fs, .pa (true: samples in Pa, else V), .names (1xC),
%       .colours (Cx3), .band [fMin fMax], .emptyText; 'sweep': .sweep
%       (fStart, fStop, duration, spacing); 'stepped': .plan
%       (tim.app.steppedPlan in seconds)
%   update: get = @(n) [x, nTotal]: the last <= n samples (Pa or V, rows x C)
%       and the number received in the running acquisition; prog: the
%       session's Progress (or []): .kind, .pass, .rep, .onSample, .state
%   S: .ax, .kind, .lines (light, live), .result (full colour), .fs, .pa,
%       .ylim, .level (1xC: level 20 Hz .. fs/2 of the last 1 s), .f, .L
%       (live curves drawn), .R (result curves drawn: 'sweep' over the FFT
%       bins from 20 Hz, 'stepped' one row per step), .acc (the result so far)

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
if ~isfield(o, 'kind') || isempty(o.kind), o.kind = 'psd'; end
legend(ax, 'off');
hideRightAxis(ax);                               % the incident level of an older sweep result
cla(ax); hold(ax, 'on');
ax.XScale = 'log'; ax.YScale = 'linear';
tim.plots.style(ax);
xlabel(ax, 'Frequency [Hz]');
if o.pa, u = 'dB SPL'; else, u = 'dB re 1 V'; end
switch o.kind
    case 'sweep'
        ylabel(ax, sprintf('Level [%s]', u)); yl = [0 120];
        f1 = min(o.sweep.fStart, o.sweep.fStop); f2 = max(o.sweep.fStart, o.sweep.fStop);
        xr = [min(f1, o.band(1)), max(f2, o.band(2))];
    case 'stepped'
        ylabel(ax, sprintf('Tone level [%s]', u)); yl = [0 120];
        fk = o.plan.freqs(:);
        xr = [min([fk; o.band(1)]), max([fk; o.band(2)])];
    otherwise
        if o.pa, ylabel(ax, 'PSD [dB re (20 \muPa)^2/Hz]'); else, ylabel(ax, 'PSD [dB re 1 V^2/Hz]'); end
        yl = [-20 100];
        xr = [20 o.fs / 2];
end
if ~o.pa, yl = yl - 120; end
light = @(c) 0.35 * c + 0.65;                    % the channel colour mixed with white
win = 1; if strcmp(o.kind, 'stepped'), win = 0.25; end   % [s] of the live curve: a stepped sine one step
h = gobjects(1, C); r = gobjects(1, C);
live = ~strcmp(o.kind, 'psd');
for c = 1:C
    col = o.colours(c, :);
    if live
        h(c) = plot(ax, NaN, NaN, '-', 'Color', light(col), 'LineWidth', 0.8, 'Tag', sprintf('timLiveSpec%d', c));
    else
        h(c) = plot(ax, NaN, NaN, '-', 'Color', col, 'LineWidth', 1.1, 'Tag', sprintf('timLiveSpec%d', c));
    end
end
for c = 1:C                                      % the result so far: in front of the live curves
    col = o.colours(c, :);
    switch o.kind
        case 'sweep'
            r(c) = plot(ax, NaN, NaN, '-', 'Color', col, 'LineWidth', 1.1, 'Tag', sprintf('timLiveResult%d', c));
        case 'stepped'
            r(c) = plot(ax, NaN, NaN, '-', 'Color', col, 'LineWidth', 1, 'Marker', 'o', 'MarkerSize', 5, ...
                'MarkerFaceColor', col, 'MarkerEdgeColor', col, 'Tag', sprintf('timLiveResult%d', c));
    end
end
hb = xline(ax, o.band(1), '--', 'Color', [0.45 0.45 0.45], 'LineWidth', 0.9);
xline(ax, o.band(2), '--', 'Color', [0.45 0.45 0.45], 'LineWidth', 0.9);
bname = sprintf('Analysis band %g – %g Hz', o.band(1), o.band(2));
if live
    hl = plot(ax, NaN, NaN, '-', 'Color', light([0.35 0.35 0.35]), 'LineWidth', 0.8);   % legend entry only
    hold(ax, 'off');
    tim.plots.legend(ax, [r hl hb], [o.names, {sprintf('Last %g s (live)', win), bname}], 'northoutside');
else
    r = gobjects(1, 0);
    hold(ax, 'off');
    tim.plots.legend(ax, [h hb], [o.names, {bname}], 'northoutside');
end
% the house-style octave ticks once, then no fitted record: the ruler callback
% of fitAxes would take every live limit change for a user zoom (1.6.3)
tim.plots.fitAxes(ax, 'Axis', 'x', 'XRange', xr);
if isappdata(ax, 'timFitAxes'), rmappdata(ax, 'timFitAxes'); end
ax.YAxis(1).Exponent = 0;                        % (a hidden right axis of a result may remain)
setY(ax, yl);
msg = 'Waiting for data ...'; if isfield(o, 'emptyText') && ~isempty(o.emptyText), msg = o.emptyText; end
tim.plots.emptyState(ax, msg);
S = struct('ax', ax, 'kind', o.kind, 'lines', h, 'result', r, 'fs', o.fs, 'pa', logical(o.pa), 'ylim', yl, ...
    'level', nan(1, C), 'f', [], 'L', [], 'R', [], 'sweep', [], 'plan', [], 'acc', [], 'window_s', win);
nfft = 8192;
switch o.kind
    case 'sweep'
        S.sweep = o.sweep;
        w = hann(nfft, 'periodic');
        S.acc = struct('nfft', nfft, 'hop', nfft / 4, 'w', w, 'U', sum(w.^2), 'sum', zeros(nfft / 2 + 1, C), ...
            'count', 0, 'next', 1, 'last', 0, 'frozen', false);
    case 'stepped'
        S.plan = o.plan;
        n = numel(o.plan.freqs);
        S.acc = struct('pass', NaN, 'rep', NaN, 'nextK', 1, 'sumA', zeros(n, C), 'cnt', zeros(n, 1), ...
            'cur', nan(n, C), 'last', 0);
        S.R = nan(n, C);
end
end

% ---------------------------------------------------------------------------
function S = update(S, get, prog)
if nargin < 3, prog = []; end
[x, nT] = get(round(S.window_s * S.fs));
x = x(all(isfinite(x), 2), :);
[f, G] = psd(x, S.fs);
if isempty(f), return; end
if S.pa, ref = 2e-5; else, ref = 1; end
keep = f >= 20; fk = f(keep);
switch S.kind
    case 'sweep'       % the sine-equivalent level of the last 1 s (its middle at full weight)
        Tw = tim.dsp.welchDuration(size(x, 1), 2 * (numel(f) - 1), S.fs);
        L = 10 * log10(tim.dsp.sweepSineLevel(G(keep, :), fk, Tw, S.sweep) / ref^2);
    case 'stepped'     % the power spectrum: a tone's peak is its level (Hann: ENBW = 1.5 fs / nfft)
        nfft = 2 * (numel(f) - 1);
        L = 10 * log10(G(keep, :) * 1.5 * S.fs / nfft / ref^2);
    otherwise
        L = 10 * log10(G(keep, :) / ref^2);
end
L(~isfinite(L)) = NaN;
tim.plots.emptyState(S.ax, '');
for c = 1:min(numel(S.lines), size(L, 2))
    if isgraphics(S.lines(c)), set(S.lines(c), 'XData', fk, 'YData', L(:, c)); end
end
% the result so far
R = [];
switch S.kind
    case 'sweep'
        S = sweepResult(S, get, nT, prog);
        if S.acc.count > 0
            Gc = S.acc.sum / S.acc.count;
            Tc = S.acc.count * S.acc.hop / S.fs;                       % K hops (tim.dsp.welchDuration)
            fc = (0:S.acc.nfft / 2).' * S.fs / S.acc.nfft;
            kc = fc >= 20;
            R = 10 * log10(tim.dsp.sweepSineLevel(Gc(kc, :), fc(kc), Tc, S.sweep) / ref^2);
            R(~isfinite(R)) = NaN;
            for c = 1:min(numel(S.result), size(R, 2))
                if isgraphics(S.result(c)), set(S.result(c), 'XData', fc(kc), 'YData', R(:, c)); end
            end
        end
    case 'stepped'
        S = steppedResult(S, get, nT, prog);
        a = S.acc; now = ~isnan(a.cur); c0 = a.cur; c0(~now) = 0;
        mA = (a.sumA + c0) ./ (a.cnt + now);                           % mean amplitude [peak]
        mA(~now & a.cnt == 0) = NaN;
        R = 20 * log10(mA / sqrt(2) / ref);
        R(~isfinite(R)) = NaN;
        fs0 = S.plan.freqs(:);
        for c = 1:min(numel(S.result), size(R, 2))
            if isgraphics(S.result(c)), set(S.result(c), 'XData', fs0, 'YData', R(:, c)); end
        end
end
S.R = R;
% the y range only grows (20 dB grid): the top 5 dB above the highest value,
% the bottom 5 dB below the 2 % quantile of the live curves (deep notches do
% not widen it)
v = sort(L(isfinite(L)));
if ~isempty(v)
    lo = v(max(1, round(0.02 * numel(v)))) - 5;
    hi = max([v(end); R(isfinite(R))]) + 5;
    yl = [min(S.ylim(1), 20 * floor(lo / 20)), max(S.ylim(2), 20 * ceil(hi / 20))];
    if ~isequal(yl, S.ylim), S.ylim = yl; setY(S.ax, yl); end
end
df = f(2) - f(1);
S.level = 10 * log10(sum(G(keep, :), 1) * df / ref^2);
S.f = fk; S.L = L;
end

function S = sweepResult(S, get, nT, prog)
% Welch average over repetition 1 so far: the periodograms of the new
% segments (Hann, nfft, 75 % overlap, as pwelch) added to the sum
a = S.acc;
if a.frozen, return; end
if ~isempty(prog) && isfield(prog, 'rep') && prog.rep > 1
    a.frozen = true; S.acc = a; return       % repetition 1 is over: the result uses it alone
end
if nT < a.last                               % a new acquisition of repetition 1 (the planning
    a.sum(:) = 0; a.count = 0; a.next = 1;   % pass of a device that plans first): start again
end
a.last = nT;
need = nT - a.next + 1;
if need >= a.nfft
    xx = get(need);
    if size(xx, 1) == need && all(isfinite(xx(:)))
        i = 1;
        while i + a.nfft - 1 <= need
            seg = xx(i:i + a.nfft - 1, :) .* a.w;
            Y = fft(seg);
            P = abs(Y(1:a.nfft / 2 + 1, :)).^2 / (S.fs * a.U);
            P(2:end - 1, :) = 2 * P(2:end - 1, :);
            a.sum = a.sum + P; a.count = a.count + 1;
            i = i + a.hop; a.next = a.next + a.hop;
        end
    end
end
S.acc = a;
end

function S = steppedResult(S, get, nT, prog)
% the tone level of every step whose measured part has ended: sine fit of
% that part at the step frequency (planned schedule from the output on),
% mean amplitude over the repetitions (a.sumA / a.cnt: the repetitions done,
% a.cur: the running one); a new pass (the equalizer's pre-measurement
% before the measurement) starts again, a new acquisition of the same
% repetition (the planning pass of a device that plans first) its steps
a = S.acc;
if isempty(prog) || ~isfield(prog, 'kind') || ~strcmp(prog.kind, 'stepped') || ~isfinite(prog.onSample), return; end
pl = S.plan; fs = S.fs;
if ~isequal(prog.pass, a.pass)
    a.sumA(:) = 0; a.cnt(:) = 0; a.cur(:) = NaN; a.pass = prog.pass; a.rep = prog.rep; a.nextK = 1;
end
if ~isequal(prog.rep, a.rep)                     % the repetition before is done
    done = ~isnan(a.cur);
    a.sumA(done) = a.sumA(done) + a.cur(done);
    a.cnt = a.cnt + all(done, 2);
    a.cur(:) = NaN; a.rep = prog.rep; a.nextK = 1;
end
if nT < a.last, a.cur(:) = NaN; a.nextK = 1; end
a.last = nT;
s0 = [0, cumsum(pl.step_s(1:end - 1))];          % step starts after the output went on
n = numel(pl.freqs);
while a.nextK <= n
    k = a.nextK;
    i1 = prog.onSample + round((s0(k) + pl.settle_s(k)) * fs) + 1;
    i2 = prog.onSample + round((s0(k) + pl.settle_s(k) + pl.record_s(k)) * fs);
    if nT < i2, break; end
    xx = get(nT - i1 + 1);
    seg = xx(1:min(i2 - i1 + 1, size(xx, 1)), :);
    if size(seg, 1) >= 100 && all(isfinite(seg(:)))
        t = (0:size(seg, 1) - 1).' / fs;
        M = [cos(2 * pi * pl.freqs(k) * t), sin(2 * pi * pl.freqs(k) * t), ones(size(t))];
        b = M \ seg;
        a.cur(k, :) = hypot(b(1, :), b(2, :));
    end
    a.nextK = k + 1;
end
S.acc = a;
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
