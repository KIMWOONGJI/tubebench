function varargout = progressStrip(ax, prog, prefix)
%PROGRESSSTRIP Draw the stepped-sine progress strip above the time signals.
%
%   tim.gui.progressStrip(ax, prog)          prog: MeasurementSession.Progress
%   tim.gui.progressStrip(ax, prog, prefix)  label prefix (two loads)
%   tim.gui.progressStrip(ax, [])            clears the strip
%   C = tim.gui.progressStrip('colours')     its colours (struct; C.tint(c) lightens c)
%
%   One rectangle per step and part (settling, measuring), its width the
%   planned time (tim.gui.stepProgress). Colours of the window (tim.gui.palette,
%   1.6.2: in harmony with the control panel): steps done in the slate of the
%   section bars (settling lighter), the equalizer's pre-measurement in a light
%   slate, the running step filled in the accent blue (lighter while it
%   settles), the steps to come light grey, the steps not played light red
%   after a Stop. A dark line marks "now". Under the steps: the octave
%   frequencies (or, where a group is too narrow, the name of the group).
%   Label on the left (as the titles of the graphs): pass, step, frequency,
%   phase - dark, green when done, red when stopped; on the right the time in
%   grey. Drawn objects are reused (Tag timProgress*), so a live update only
%   sets their data.

P = tim.gui.palette();
if ischar(ax) && strcmp(ax, 'colours')
    tint = @(c) 1 - 0.45 * (1 - c);          % the lighter shade of the settling part
    varargout{1} = struct('done', P.ui.bar, 'pre', 1 - 0.55 * (1 - P.ui.bar), 'running', P.ui.accent, ...
        'track', [0.91 0.92 0.94], 'notPlayed', 1 - 0.25 * (1 - P.fail), 'now', P.ui.text, ...
        'text', [0.20 0.20 0.22], 'muted', P.ui.muted, 'ok', 0.85 * P.ok, 'fail', P.fail, 'tint', tint);
    return
end
if nargin < 3, prefix = ''; end
if isempty(prog)
    delete(findobj(ax, '-regexp', 'Tag', '^timProgress'));
    title(ax, ''); ax.XTick = []; ax.Visible = 'off';
    return
end
g = tim.gui.stepProgress(prog, prefix);
ax.Visible = 'on';
% ---- colours of the rectangles
C = tim.gui.progressStrip('colours');
m = size(g.rect, 1);
col = repmat(C.track, m, 1);
isPre = numel(prog.passes) > 1 & g.pass < numel(prog.passes);   % passes before the last: pre-measurement
base = repmat(C.done, m, 1); base(isPre, :) = repmat(C.pre, nnz(isPre), 1);
done = g.rect(:, 2) <= g.x + 1e-9;
if strcmp(g.phase, 'done'), done(:) = true; end
col(done & g.part == 2, :) = base(done & g.part == 2, :);
col(done & g.part == 1, :) = C.tint(base(done & g.part == 1, :));
if strcmp(g.phase, 'stopped')
    rest = g.rect(:, 1) >= g.x - 1e-9;
    col(rest, :) = repmat(C.notPlayed, nnz(rest), 1);
end
% the running rectangle: filled up to "now" (lighter while it settles)
cur = find(~done & g.rect(:, 1) < g.x, 1);
xf = zeros(0, 2); cf = zeros(0, 3);
if ~isempty(cur) && ~any(strcmp(g.phase, {'done', 'stopped'}))
    xf = [g.rect(cur, 1), g.x];
    if g.part(cur) == 1, cf = C.tint(C.running); else, cf = C.running; end
end
track = C.track;
% ---- geometry
[V, F] = rects(g.rect, 0, 1);
[Vf, Ff] = rects(xf, 0, 1);
hold(ax, 'on');
hp = findobj(ax, 'Tag', 'timProgressSteps');
if isempty(hp)
    patch(ax, 'Vertices', V, 'Faces', F, 'FaceVertexCData', col, 'FaceColor', 'flat', 'EdgeColor', 'none', ...
        'Tag', 'timProgressSteps', 'HitTest', 'off');
else
    set(hp, 'Vertices', V, 'Faces', F, 'FaceVertexCData', col);
end
hf = findobj(ax, 'Tag', 'timProgressFill');
if isempty(Vf), Vf = nan(4, 2); Ff = 1:4; cf = track; end
if isempty(hf)
    patch(ax, 'Vertices', Vf, 'Faces', Ff, 'FaceColor', cf, 'EdgeColor', 'none', 'Tag', 'timProgressFill', ...
        'HitTest', 'off');
else
    set(hf, 'Vertices', Vf, 'Faces', Ff, 'FaceColor', cf);
end
% white separators between the steps (not between the parts of a step), wider between groups
xs = unique(g.rect(g.part == 1, 1)).';
xg = g.groups(2:end, 1).';
hs = findobj(ax, 'Tag', 'timProgressSep');
[sx, sy] = vlines(xs, -0.02, 1.02);
if isempty(hs)
    hs = line(ax, sx, sy, 'Color', 'w', 'LineWidth', 1, 'Tag', 'timProgressSep', 'HitTest', 'off');
else
    set(hs, 'XData', sx, 'YData', sy);
end
hg = findobj(ax, 'Tag', 'timProgressGroup');
[gx, gy] = vlines(xg, -0.25, 1.25);
if isempty(hg)
    hg = line(ax, gx, gy, 'Color', 'w', 'LineWidth', 3, 'Tag', 'timProgressGroup', 'HitTest', 'off');
else
    set(hg, 'XData', gx, 'YData', gy);
end
% "now"
hn = findobj(ax, 'Tag', 'timProgressNow');
nowOn = ~any(strcmp(g.phase, {'done'}));
[nx, ny] = vlines(g.x(nowOn), -0.15, 1.15);
if isempty(hn)
    hn = line(ax, nx, ny, 'Color', C.now, 'LineWidth', 1.5, 'Tag', 'timProgressNow', 'HitTest', 'off', ...
        'Clipping', 'off');
else
    set(hn, 'XData', nx, 'YData', ny);
end
uistack([hs hg hn], 'top');
hold(ax, 'off');
% ---- axes, ticks, labels: the font and the text colour of the graphs below
% (tim.plots.style, 11 pt), no axis line, no tick marks
ax.XLim = [0 max(g.T, eps)]; ax.YLim = [0 1];
[tx, tl] = ticks(g, prog, ax);
ax.XTick = tx; ax.XTickLabel = tl;
ax.YTick = []; ax.TickLength = [0 0]; ax.Box = 'off'; ax.YColor = 'none';
ax.XColor = C.text; ax.XGrid = 'off'; ax.YGrid = 'off'; ax.LineWidth = 0.5;
ax.XMinorTick = 'off'; ax.XScale = 'linear'; ax.Color = 'none'; ax.FontSize = 11;
try                                 % (exists once the axes was drawn)
    ax.XAxis.Axle.Visible = 'off';
catch
end
switch g.status
    case 'ok', tc = C.ok;
    case 'fail', tc = C.fail;
    otherwise, tc = C.text;
end
title(ax, g.label, 'FontWeight', 'normal', 'Color', tc, 'FontSize', 11, 'Interpreter', 'none');
ax.TitleHorizontalAlignment = 'left';
ht = findobj(ax, 'Tag', 'timProgressTime');
if isempty(ht)
    ht = text(ax, 0, 0, '', 'HorizontalAlignment', 'right', 'VerticalAlignment', 'bottom', ...
        'Color', C.muted, 'FontSize', 11, 'Tag', 'timProgressTime', 'Interpreter', 'none', ...
        'Clipping', 'off', 'HitTest', 'off');
end
% on the line of the title, right-aligned with the strip's end
yt = ax.Title.Position(2); if ~(isfinite(yt) && yt > 1), yt = 1.3; end
ht.Position = [ax.XLim(2), yt, 0];
ht.String = g.right;
end

function [V, F] = rects(x, y0, y1)
% vertices / faces of rectangles [x0 x1] between y0 and y1
n = size(x, 1);
V = zeros(4 * n, 2); F = reshape(1:4 * n, 4, n).';
for i = 1:n
    V(4 * i - 3:4 * i, :) = [x(i, 1) y0; x(i, 2) y0; x(i, 2) y1; x(i, 1) y1];
end
end

function [x, y] = vlines(xs, y0, y1)
% vertical lines at xs as one line object (NaN separated)
x = reshape([xs; xs; nan(size(xs))], 1, []);
y = reshape(repmat([y0; y1; NaN], 1, numel(xs)), 1, []);
if isempty(xs), x = NaN; y = NaN; end
end

function [tx, tl] = ticks(g, prog, ax)
% octave frequencies under the steps of every group that is wide enough,
% otherwise the name of the group under its middle
pl = prog.plan;
s0 = pl.pre_s + [0, cumsum(pl.step_s(1:end - 1))];
w = 800;
try
    pos = getpixelposition(ax); if pos(3) > 50, w = pos(3); end
catch
end
G = size(g.groups, 1);
tx = []; tl = {};
for q = 1:G
    t0 = g.groups(q, 1);
    wide = (g.groups(q, 2) - g.groups(q, 1)) / g.T * w >= 260;
    if wide
        for f = g.tickF
            [~, k] = min(abs(pl.freqs - f));
            tx(end + 1) = t0 + s0(k) + pl.step_s(k) / 2; %#ok<AGROW>
            if f >= 1000, tl{end + 1} = sprintf('%gk', f / 1000); else, tl{end + 1} = sprintf('%g', f); end %#ok<AGROW>
        end
    elseif ~isempty(g.groupName{q})
        tx(end + 1) = mean(g.groups(q, :)); tl{end + 1} = g.groupName{q}; %#ok<AGROW>
    end
end
[tx, i] = unique(tx); tl = tl(i);
end
