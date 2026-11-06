function varargout = progressStrip(ax, prog, prefix)
%PROGRESSSTRIP Draw the progress strip of a stepped or swept sine above the time signals.
%
%   tim.gui.progressStrip(ax, prog)          prog: MeasurementSession.Progress
%   tim.gui.progressStrip(ax, prog, prefix)  label prefix (two loads)
%   tim.gui.progressStrip(ax, [])            clears the strip
%   C = tim.gui.progressStrip('colours')     its colours (struct; C.tint(c) lightens c)
%
%   One rectangle per step and part (settling, measured), or per sweep, its
%   width the planned time (tim.gui.stepProgress). Colours of the window
%   (tim.gui.palette, 1.6.2): done in the slate of the section bars (settling
%   lighter), the equalizer's pre-measurement in a light slate, the running
%   step or sweep filled in the accent blue (lighter while it settles), the
%   rest light grey, light red after a Stop. A dark line marks "now". Under
%   the steps: the octave frequencies (or, where a group is too narrow, its
%   name). Label on the left: pass, step / frequency, phase - dark, green
%   when done, red when stopped; on the right the time in grey.
%
%   1.6.3 (owner report 2026-11-05: the graphs moved during a measurement):
%   everything that takes room - the label, the time on the right, the tick
%   labels - is there from the first drawing to the last, so the strip and
%   the graphs below keep their size; and an update during the measurement
%   only sets the colours, the fill, the "now" line and the two texts: the
%   geometry, the ticks and the static properties are set once per plan.

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
    ax.UserData = [];
    return
end
g = tim.gui.stepProgress(prog, prefix);
C = tim.gui.progressStrip('colours');
key = sprintf('%s|%d|%.6g|%s', prog.kind, size(g.rect, 1), g.T, mat2str(g.groups, 6));
if ~(isstruct(ax.UserData) && isfield(ax.UserData, 'progressKey') && strcmp(ax.UserData.progressKey, key))
    setUp(ax, g, C);
    ax.UserData = struct('progressKey', key);
end
% ---- colours of the rectangles
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
Vf = nan(4, 2); cf = C.track;
if ~isempty(cur) && ~any(strcmp(g.phase, {'done', 'stopped'}))
    Vf = rects([g.rect(cur, 1), g.x], 0, 1);
    if g.part(cur) == 1, cf = C.tint(C.running); else, cf = C.running; end
end
set(findobj(ax, 'Tag', 'timProgressSteps'), 'FaceVertexCData', col);
set(findobj(ax, 'Tag', 'timProgressFill'), 'Vertices', Vf, 'FaceColor', cf);
[nx, ny] = vlines(g.x(~strcmp(g.phase, 'done')), -0.15, 1.15);
set(findobj(ax, 'Tag', 'timProgressNow'), 'XData', nx, 'YData', ny);
% ---- the two texts (only when they change)
switch g.status
    case 'ok', tc = C.ok;
    case 'fail', tc = C.fail;
    otherwise, tc = C.text;
end
if ~strcmp(ax.Title.String, g.label), ax.Title.String = g.label; end
if ~isequal(ax.Title.Color, tc), ax.Title.Color = tc; end
ht = findobj(ax, 'Tag', 'timProgressTime');
if ~strcmp(ht.String, g.right), ht.String = g.right; end
end

function setUp(ax, g, C)
% the geometry, the ticks and the static properties of a plan (once)
delete(findobj(ax, '-regexp', 'Tag', '^timProgress'));
ax.Visible = 'on';
ax.XLim = [0 max(g.T, eps)]; ax.YLim = [0 1];
ax.YTick = []; ax.TickLength = [0 0]; ax.Box = 'off'; ax.YColor = 'none';
ax.XColor = C.text; ax.XGrid = 'off'; ax.YGrid = 'off'; ax.LineWidth = 0.5;
ax.XMinorTick = 'off'; ax.XScale = 'linear'; ax.Color = 'none'; ax.FontSize = 11;
try                                 % (exists once the axes was drawn)
    ax.XAxis.Axle.Visible = 'off';
catch
end
V = rects(g.rect, 0, 1);
F = reshape(1:size(V, 1), 4, []).';
hold(ax, 'on');
patch(ax, 'Vertices', V, 'Faces', F, 'FaceVertexCData', repmat(C.track, size(g.rect, 1), 1), 'FaceColor', 'flat', ...
    'EdgeColor', 'none', 'Tag', 'timProgressSteps', 'HitTest', 'off');
patch(ax, 'Vertices', nan(4, 2), 'Faces', 1:4, 'FaceColor', C.track, 'EdgeColor', 'none', ...
    'Tag', 'timProgressFill', 'HitTest', 'off');
% white separators between the steps (not between the parts of a step), wider between groups
[sx, sy] = vlines(unique(g.rect(g.part == 1, 1)).', -0.02, 1.02);
line(ax, sx, sy, 'Color', 'w', 'LineWidth', 1, 'Tag', 'timProgressSep', 'HitTest', 'off');
[gx, gy] = vlines(g.groups(2:end, 1).', -0.25, 1.25);
line(ax, gx, gy, 'Color', 'w', 'LineWidth', 3, 'Tag', 'timProgressGroup', 'HitTest', 'off');
line(ax, NaN, NaN, 'Color', C.now, 'LineWidth', 1.5, 'Tag', 'timProgressNow', 'HitTest', 'off', 'Clipping', 'off');
hold(ax, 'off');
[tx, tl] = ticks(g, ax);
ax.XTick = tx; ax.XTickLabel = tl;
title(ax, g.label, 'FontWeight', 'normal', 'Color', C.text, 'FontSize', 11, 'Interpreter', 'none');
ax.TitleHorizontalAlignment = 'left';
% the time on the line of the title, right-aligned with the strip's end
yt = ax.Title.Position(2); if ~(isfinite(yt) && yt > 1), yt = 1.3; end
text(ax, ax.XLim(2), yt, g.right, 'HorizontalAlignment', 'right', 'VerticalAlignment', 'bottom', ...
    'Color', C.muted, 'FontSize', 11, 'Tag', 'timProgressTime', 'Interpreter', 'none', 'Clipping', 'off', ...
    'HitTest', 'off');
end

function V = rects(x, y0, y1)
% vertices of rectangles [x0 x1] between y0 and y1 (faces: 4 per rectangle)
n = size(x, 1);
V = zeros(4 * n, 2);
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

function [tx, tl] = ticks(g, ax)
% octave frequencies of every group that is wide enough, otherwise the name
% of the group under its middle
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
        tx = [tx, t0 + g.tickT]; tl = [tl, g.tickLabel]; %#ok<AGROW>
    elseif ~isempty(g.groupName{q})
        tx(end + 1) = mean(g.groups(q, :)); tl{end + 1} = g.groupName{q}; %#ok<AGROW>
    end
end
[tx, i] = unique(tx); tl = tl(i);
end
