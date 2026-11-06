function L = liveAxis(ax, Lprev, pk)
%LIVEAXIS Fixed axes of a live time signal (Measurement > Time signals).
%
%   L = tim.gui.liveAxis(ax, Lprev, pk)
%   s = tim.gui.liveAxis('labels', L)      the tick labels of the limit L (tests)
%
%   The live graphs must not move (owner reports 2026-11-05). 1.6.2 let the
%   limit L only grow during an action (Lprev: the limit so far, [] at the
%   start), on the 1-2-5 series above 1.15 x the peak pk, with the ticks -L,
%   -L/2, 0, L/2, L and no exponent; x is the last 0.5 s. 1.6.3: with real
%   levels the limit still grows during a measurement (0.05 -> 20 -> 50 ->
%   100 Pa), and every change of the width of the tick labels (-0.050, -20,
%   -100) moved all graphs of the tiled layout and the progress strip
%   sideways. Now every tick label has the same width: two decimals always,
%   a sign slot (minus, or a figure space) and three integer slots padded with
%   figure spaces (U+2007, the width of a digit), so the plot areas stay where
%   they are up to 999 Pa. The limit starts at 0.1 Pa (noise before the output
%   is on is drawn within ±0.1 Pa). The axes is changed only when L changes.

if ischar(ax) && strcmp(ax, 'labels')
    L = labels(Lprev);
    return
end
% the live axes are not "fitted": tim.plots.fitAxes (the view drawn before)
% left a ruler callback that takes every limit change for a user zoom and
% switches the ticks and labels to automatic at the next drawnow - the graphs
% jumped between the updates (1.6.3 check); without its record it does nothing
if isappdata(ax, 'timFitAxes'), rmappdata(ax, 'timFitAxes'); end
L = niceLimit(max(1.15 * pk, 0.1));
if ~isempty(Lprev) && isfinite(Lprev) && Lprev >= L, L = Lprev; end
if ~isequal(ax.XLim, [-0.5 0]), ax.XLim = [-0.5 0]; end
if isequal(ax.YLim, [-L L]) && isequal(ax.YTick, L * [-1 -0.5 0 0.5 1]) && strcmp(ax.YTickLabelMode, 'manual')
    return
end
ax.YLim = [-L L]; ax.YTick = L * [-1 -0.5 0 0.5 1];
ax.YAxis.Exponent = 0;
ax.YAxis.TickLabelInterpreter = 'none';
ax.YTickLabel = labels(L);
end

function s = labels(L)
% -L, -L/2, 0, L/2, L with two decimals in fixed slots (equal width)
fig = char(8199); minus = char(8722);
v = L * [-1 -0.5 0 0.5 1];
s = cell(1, numel(v));
for i = 1:numel(v)
    a = sprintf('%.2f', abs(v(i)));                       % (3 integer slots below)
    k = strfind(a, '.');
    a = [repmat(fig, 1, max(0, 3 - (k - 1))), a]; %#ok<AGROW> three integer slots
    if v(i) < 0, sgn = minus; else, sgn = fig; end
    s{i} = [sgn a];
end
end

function L = niceLimit(x)
% the smallest value of the 1-2-5 series >= x
e = 10^floor(log10(x)); s = [1 2 5 10];
L = s(find(s * e >= x * (1 - 1e-12), 1)) * e;
end
