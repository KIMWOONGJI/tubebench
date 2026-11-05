function L = liveAxis(ax, Lprev, pk)
%LIVEAXIS Fixed axes of a live time signal (Measurement > Time signals).
%
%   L = tim.gui.liveAxis(ax, Lprev, pk)
%
%   1.6.2 (owner report 2026-11-05): the graphs and the progress strip above
%   them moved while the y limits followed every live update (the tick labels
%   and the exponent changed, and with them the plot areas of the tiled
%   layout). Here the limit L only grows during an action (Lprev: the limit so
%   far, [] at the start), on the 1-2-5 series above 1.15 x the peak pk; the
%   ticks are -L, -L/2, 0, L/2, L with one number format and no exponent; x
%   is fixed to the last 0.5 s. The axes is changed only when L changes.

L = niceLimit(1.15 * pk);
if ~isempty(Lprev) && isfinite(Lprev) && Lprev >= L, L = Lprev; end
if ~isequal(ax.XLim, [-0.5 0]), ax.XLim = [-0.5 0]; end
if isequal(ax.YLim, [-L L]) && isequal(ax.YTick, L * [-1 -0.5 0 0.5 1]), return; end
ax.YLim = [-L L]; ax.YTick = L * [-1 -0.5 0 0.5 1];
ax.YAxis.Exponent = 0;
h = L / 2; d = 0;                        % decimals that show L/2 exactly
while d < 6 && abs(round(h * 10^d) - h * 10^d) > 1e-9 * max(1, h * 10^d), d = d + 1; end
ax.YAxis.TickLabelFormat = sprintf('%%.%df', d);
end

function L = niceLimit(x)
% the smallest value of the 1-2-5 series >= x (1e-3 when there is nothing yet)
if ~(x > 0) || ~isfinite(x), L = 1e-3; return; end
e = 10^floor(log10(x)); s = [1 2 5 10];
L = s(find(s * e >= x * (1 - 1e-12), 1)) * e;
end
