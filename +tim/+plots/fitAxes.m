function fitAxes(ax, opts)
%FITAXES Axis limits half a tick interval beyond the outermost ticks.
%   tim.plots.fitAxes(ax)                         x and y from the plotted data
%   tim.plots.fitAxes(ax, 'XRange', [120 4500])   cover this range (e.g. the analysis band)
%   tim.plots.fitAxes(ax, 'YRange', [0 1], 'YStep', 0.2, 'Axis', 'y')
%
%   House style of every plot (GUI and saved figures): no tick sits on the
%   end of an axis. The ticks t1..tn cover the data and the limits are
%   [t1 - step/2, tn + step/2] (linear axes) or [t1/sqrt(r), tn*sqrt(r)]
%   (logarithmic axes, r = ratio of neighbouring ticks). Logarithmic
%   frequency axes get octave ticks (31.5, 63, 125, ... labelled 1k, 2k, ...).
%   Linear steps are "nice": {1, 2, 2.5, 5} x 10^n, or opts.YSteps / XSteps
%   (e.g. [1 2 5] for dB, [15 30 45 90 180] for degrees with 'Mantissa',
%   false). A zoom / pan by the user switches to automatic ticks; "restore
%   view" brings the fitted limits and ticks back. Every fit forgets the
%   view MATLAB stored at an earlier zoom (the axes are reused for every
%   measurement): "restore view" goes back to the CURRENT data, not to the
%   limits of the data shown at the first zoom.
%
%   Data range: all line / scatter / patch / area / stair / errorbar objects
%   with XLimInclude / YLimInclude 'on' (log axes: positive values only),
%   unless XRange / YRange is given. YInclude adds values that must be
%   inside (e.g. 0). An axis without finite data keeps its current limits.

arguments
    ax
    opts.Axis (1,:) char = 'xy'
    opts.XRange double = []
    opts.YRange double = []
    opts.XInclude double = []
    opts.YInclude double = []
    opts.XStep double = []
    opts.YStep double = []
    opts.XSteps double = [1 2 2.5 5]
    opts.YSteps double = [1 2 2.5 5]
    opts.XMantissa logical = true      % XSteps are mantissas (x 10^n) or absolute steps
    opts.YMantissa logical = true
    opts.MaxTicks double = 9
    opts.MinTicks double = 4
end

S = struct('xl', [], 'yl', [], 'xt', [], 'yt', [], 'xtl', {{}}, 'ytl', {{}});
if any(opts.Axis == 'x')
    r = dataRange(ax, 'X', opts.XRange, opts.XInclude);
    [S.xl, S.xt, S.xtl] = fitOne(r, strcmp(ax.XScale, 'log'), opts.XStep, opts.XSteps, opts.XMantissa, opts);
end
if any(opts.Axis == 'y')
    r = dataRange(ax, 'Y', opts.YRange, opts.YInclude);
    [S.yl, S.yt, S.ytl] = fitOne(r, strcmp(ax.YScale, 'log'), opts.YStep, opts.YSteps, opts.YMantissa, opts);
end
old = getappdata(ax, 'timFitAxes');
if ~isempty(old) && ~any(opts.Axis == 'x') && isequal(ax.XLim, old.xl)   % x untouched, still fitted
    S.xl = old.xl; S.xt = old.xt; S.xtl = old.xtl;
end
if ~isempty(old) && ~any(opts.Axis == 'y') && isequal(ax.YLim, old.yl)
    S.yl = old.yl; S.yt = old.yt; S.ytl = old.ytl;
end
setappdata(ax, 'timFitAxes', S);
apply(ax, S);
% the view stored by the first zoom / pan (resetplotview) belongs to the data
% shown then: without it, "restore view" keeps the fitted limits and the next
% zoom stores the new ones
if isappdata(ax, 'matlab_graphics_resetplotview'), rmappdata(ax, 'matlab_graphics_resetplotview'); end
% limits changed by zoom / pan / restore view: the RULER callback (the toolbar
% "restore view" sets the ruler limits, which fires no XLim / YLim PostSet).
% It runs at the next drawnow, after the caller may have changed the ticks
% (e.g. hidden labels of stacked axes): onLimits touches fitted ticks only
% when they were switched to automatic.
set(ax.XAxis, 'LimitsChangedFcn', @(~, ~) onLimits(ax));
set(ax.YAxis, 'LimitsChangedFcn', @(~, ~) onLimits(ax));
end

% ---------------------------------------------------------------------------
function apply(ax, S)
if ~isempty(S.xl)
    ax.XLim = S.xl; ax.XTick = S.xt;
    if isempty(S.xtl), ax.XTickLabelMode = 'auto'; else, ax.XTickLabel = S.xtl; end
end
if ~isempty(S.yl)
    ax.YLim = S.yl; ax.YTick = S.yt;
    if isempty(S.ytl), ax.YTickLabelMode = 'auto'; else, ax.YTickLabel = S.ytl; end
end
end

function onLimits(ax)
% user zoom / pan -> automatic ticks; back at the fitted limits (restore
% view, zoom out) -> fitted ticks again. Ticks that are still the fitted
% (manual) ones are left alone.
if ~isvalid(ax), return; end
S = getappdata(ax, 'timFitAxes');
if isempty(S), return; end
tol = @(a, b) ~isempty(b) && all(abs(a - b) <= 1e-9 * max(1, max(abs(b))));
if ~isempty(S.xl)
    if ~tol(ax.XLim, S.xl)
        ax.XTickMode = 'auto'; ax.XTickLabelMode = 'auto';
    elseif strcmp(ax.XTickMode, 'auto')
        ax.XTick = S.xt;
        if ~isempty(S.xtl), ax.XTickLabel = S.xtl; end
    end
end
if ~isempty(S.yl)
    if ~tol(ax.YLim, S.yl)
        ax.YTickMode = 'auto'; ax.YTickLabelMode = 'auto';
    elseif strcmp(ax.YTickMode, 'auto')
        ax.YTick = S.yt;
        if ~isempty(S.ytl), ax.YTickLabel = S.ytl; end
    end
end
end

function r = dataRange(ax, XY, given, include)
% [min max] of the data (or the given range) plus the values to include
isLog = strcmp(ax.([XY 'Scale']), 'log');
if ~isempty(given)
    v = given(:);
else
    v = [];
    obj = findobj(ax, '-depth', inf, 'Type', 'line', '-or', 'Type', 'scatter', '-or', 'Type', 'patch', ...
        '-or', 'Type', 'area', '-or', 'Type', 'stair', '-or', 'Type', 'errorbar', '-or', 'Type', 'surface');
    for i = 1:numel(obj)
        o = obj(i);
        if isprop(o, [XY 'LimInclude']) && strcmp(o.([XY 'LimInclude']), 'off'), continue; end
        d = o.([XY 'Data']);
        if ~isnumeric(d) && ~islogical(d), continue; end
        v = [v; double(d(:))]; %#ok<AGROW>
        if strcmp(XY, 'Y') && isprop(o, 'YNegativeDelta')            % error bars
            v = [v; double(d(:)) - double(o.YNegativeDelta(:)); double(d(:)) + double(o.YPositiveDelta(:))]; %#ok<AGROW>
        end
    end
end
v = [v; include(:)];
v = v(isfinite(v));
if isLog, v = v(v > 0); end
if isempty(v), r = []; else, r = [min(v) max(v)]; end
end

function [lim, ticks, labels] = fitOne(r, isLog, step, steps, mantissa, opts)
lim = []; ticks = []; labels = {};
if isempty(r), return; end
if isLog
    [lim, ticks, labels] = fitLog(r);
else
    [lim, ticks] = fitLinear(r, step, steps, mantissa, opts);
end
end

function [lim, t] = fitLinear(r, step, steps, mantissa, opts)
lo = r(1); hi = r(2);
if hi - lo <= eps(max(abs([lo hi 1]))) * 16           % constant data: open a range around it
    d = max(abs(lo) * 0.1, 1); lo = lo - d; hi = hi + d;
end
if isempty(step)
    step = niceStep(hi - lo, steps, mantissa, opts);
end
t1 = floor((lo + step / 2) / step + 1e-9) * step;      % t1 - step/2 <= lo
tn = ceil((hi - step / 2) / step - 1e-9) * step;       % tn + step/2 >= hi
if tn < t1, tn = t1; end
n = round((tn - t1) / step);
t = t1 + (0:n) * step;
t(abs(t) < step * 1e-9) = 0;                           % no -0 / 1e-17 labels
lim = [t1 - step / 2, tn + step / 2];
end

function s = niceStep(range, steps, mantissa, opts)
% smallest admissible step that gives at most MaxTicks ticks (at least MinTicks if possible)
if mantissa
    e = floor(log10(range / opts.MaxTicks)) + (-1:2);
    cand = sort(reshape(steps(:) * 10.^e, 1, []));
else
    cand = sort(steps(:).');
end
nTicks = floor(range ./ cand) + 1;
ok = find(nTicks <= opts.MaxTicks);
if isempty(ok), s = cand(end); return; end
s = cand(ok(1));
good = ok(nTicks(ok) >= opts.MinTicks);
if ~isempty(good), s = cand(good(1)); end
end

function [lim, t, labels] = fitLog(r)
% octave ticks for frequency-like data (>= 10), otherwise decades
lo = r(1); hi = r(2);
if lo >= 10 && hi <= 64000
    oct = [8 16 31.5 63 125 250 500 1000 2000 4000 8000 16000 31500 63000];   % 8: data from 10 ... 11.3 Hz
    q = sqrt(2);
    i1 = find(oct / q <= lo * (1 + 1e-9), 1, 'last');
    i2 = find(oct * q >= hi * (1 - 1e-9), 1, 'first');
    t = oct(i1:i2);
    if numel(t) > 11                                  % very wide range: every second octave,
        k = i2:-2:i1;                                 % counted from the top (the highest tick stays)
        if oct(k(end)) / 2 > lo * (1 + 1e-9), k(end + 1) = k(end) - 2; end   % and the lowest still covers lo
        t = oct(fliplr(k)); q = 2;
    end
    lim = [t(1) / q, t(end) * q];
    labels = arrayfun(@freqLabel, t, 'UniformOutput', false);
else
    e1 = floor(log10(lo) + 0.5); e2 = ceil(log10(hi) - 0.5);
    if e2 < e1, e2 = e1; end
    t = 10.^(e1:e2);
    lim = [t(1) / sqrt(10), t(end) * sqrt(10)];
    labels = {};
end
end

function s = freqLabel(f)
if f >= 1000, s = sprintf('%gk', f / 1000); else, s = sprintf('%g', f); end
end
