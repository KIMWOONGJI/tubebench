function info = transferMatrix(ax, tl, opts)
%TRANSFERMATRIX Results view: the transfer matrix T of the specimen (WO-005).
%   info = tim.plots.transferMatrix([axMag axPhase], tl)
%   info = tim.plots.transferMatrix([axMag axPhase], tl, struct('simulation', true))
%   info = tim.plots.transferMatrix([axMag axPhase], [])        empty state
%
%   tl: the result of tim.app.processTwoLoad, [p_front; u_front] = T [p_rear;
%   u_rear]. Elements in tube units so that all four are dimensionless:
%   T11, T12/Zc, Zc T21, T22. Top axes: magnitudes (logarithmic); bottom
%   axes: phases (wrapped, broken at the +-180 deg wraps). The diagonal
%   elements share a colour (T11 solid, T22 dashed: on top of each other for
%   a symmetric specimen), the off-diagonal ones another (T12/Zc solid, Zc T21
%   dashed: Zc T21 = 0 for a thin series element). Masked with tl.valid.valid
%   (grey elsewhere). One load, symmetric specimen: T11 = T22 and det T = 1 by
%   ASSUMPTION - the title and the note say so.
%
%   opts (all optional): band [fMin fMax] (default tl.band), simulation,
%   emptyText.
%
%   info.summary  octave bands: Band [Hz] | |T11| | |T12|/Zc | |Zc T21| | |T22|
%                 (mean over the valid lines of each band, '–' when none)
%   info.note     one-line explanation for the view header ('' when none)
%   info.lines    coloured curves [T11 T12/Zc ZcT21 T22] (legend order)
if nargin < 3, opts = struct(); end
P = tim.gui.palette();
ax1 = ax(1); ax2 = []; if numel(ax) > 1, ax2 = ax(2); end
for axi = ax(:).'
    legend(axi, 'off'); cla(axi); hold(axi, 'on'); set(axi, 'XScale', 'log', 'YDir', 'normal');
    tim.plots.style(axi);
end
set(ax1, 'YScale', 'log');
band = [120 4500];
if isstruct(tl) && isfield(tl, 'band') && numel(tl.band) == 2, band = tl.band; end
if isfield(opts, 'band') && numel(opts.band) == 2, band = opts.band(:).'; end
sim = isfield(opts, 'simulation') && ~isempty(opts.simulation) && opts.simulation;
emptyText = 'No transfer matrix: measure with Method "Two loads" (or "One load, symmetric")';
if isfield(opts, 'emptyText') && ~isempty(opts.emptyText), emptyText = opts.emptyText; end
ylabel(ax1, 'Magnitude [–]');
if isempty(ax2), xlabel(ax1, 'Frequency [Hz]'); else, ylabel(ax2, 'Phase [\circ]'); xlabel(ax2, 'Frequency [Hz]'); end
B = tim.plots.octaveBands(band); centres = B.centres;
names = {'|T_{11}|', '|T_{12}| / Z_c', '|Z_c T_{21}|', '|T_{22}|'};
info = struct('summary', bandSummary(B, repmat({char(8211)}, numel(centres), 4), ''), 'note', '', ...
    'lines', gobjects(0));
if isempty(tl) || ~isstruct(tl)
    title(ax1, char(160));
    tim.plots.fitAxes(ax1, 'XRange', band, 'YRange', [0.1 10]);
    if ~isempty(ax2), tim.plots.fitAxes(ax2, 'XRange', band, 'YRange', [-180 180], 'YStep', 90); end
    tim.plots.emptyState(ax1, emptyText);
    return
end
f = tl.f; ok = tl.valid.valid; Zc = tl.Zc;
E = {tl.T.T11, tl.T.T12 ./ Zc, Zc .* tl.T.T21, tl.T.T22};
col = {P.q.first, P.q.second, P.q.second, P.q.first};
ls = {'-', '-', '--', '--'};
grey = gobjects(0);
for i = 1:4
    y = abs(E{i}); y(y <= 0) = NaN;
    [h, g] = tim.plots.masked(ax1, f, y, ok, col{i}, struct('lineStyle', ls{i}));
    info.lines(i) = h; grey = [grey; g]; %#ok<AGROW>
end
uistack(grey, 'bottom');
if any(ok), set(grey, 'YLimInclude', 'off'); end
title(ax1, tim.plots.dataTitle(tl, struct('simulation', sim)), 'Interpreter', 'none');
tim.plots.legend(ax1, info.lines, names);
tim.plots.fitAxes(ax1, 'XRange', band);
if ~isempty(ax2)
    gp = gobjects(0);
    for i = 1:4
        [fp, ph, okp] = breakWraps(f, rad2deg(angle(E{i})), ok);
        [~, g] = tim.plots.masked(ax2, fp, ph, okp, col{i}, struct('lineStyle', ls{i}));
        gp = [gp; g]; %#ok<AGROW>
    end
    uistack(gp, 'bottom');
    linkaxes([ax1 ax2], 'x');
    tim.plots.fitAxes(ax2, 'XRange', band, 'YRange', [-180 180], 'YStep', 90);
end
cells = cell(numel(centres), 4);
for i = 1:4
    [~, ~, t] = tim.plots.bandValues(f, abs(E{i}), ok, centres, '%.3g');
    cells(:, i) = t;
end
parts = {};
if strcmp(tl.method, 'oneLoadSymmetric')
    parts{end + 1} = 'One load: T11 = T22 and det T = 1 are ASSUMED (symmetric, reciprocal specimen)';
else
    if ~isempty(tl.checks.errors), parts{end + 1} = ['Not combined: ' tl.checks.errors{1}]; end
    nv = nnz(ok);
    if nv > 0
        parts{end + 1} = sprintf('|det T %s 1| median %.3g, symmetry error median %.3g (valid lines)', char(8722), ...
            median(tl.reciprocityError(ok)), median(tl.symmetryError(ok)));
    elseif isempty(tl.checks.errors)
        parts{end + 1} = 'No valid frequency line (grey curves) - see Validity';
    end
end
info.summary = bandSummary(B, cells, tl.valid.summary);
info.note = joinNotes(parts);
end

% ---------------------------------------------------------------------------
function s = bandSummary(B, cells, extra)
note = ['Mean over the valid frequency lines of each octave band; ' char(8211) ' = no valid frequency line. ' ...
    'A thin series element has |Z_c T21| = 0 and |T11| = |T22| = 1.'];
if ~isempty(extra), note = [extra '. ' note]; end
if ~isempty(B.note), note = [note ' ' B.note]; end
s = struct('title', 'Octave bands', 'columns', {{'Band [Hz]', '|T11|', '|T12|/Zc', '|Zc T21|', '|T22|'}}, ...
    'data', {[B.labels, cells]}, 'note', note);
end

function [f2, y2, ok2] = breakWraps(f, y, ok)
% insert a NaN point at every +-180 deg wrap so that no vertical line is drawn
f = f(:); y = y(:); ok = logical(ok(:));
jump = [false; abs(diff(y)) > 180];
if ~any(jump), f2 = f; y2 = y; ok2 = ok; return; end
pos = (1:numel(y)).' + cumsum(jump);
n = numel(y) + nnz(jump);
f2 = nan(n, 1); y2 = nan(n, 1); ok2 = false(n, 1);
f2(pos) = f; y2(pos) = y; ok2(pos) = ok;
gap = setdiff((1:n).', pos);
f2(gap) = sqrt(f2(gap - 1) .* f2(gap + 1));
end

function txt = joinNotes(parts)
parts = parts(~cellfun(@isempty, parts));
txt = '';
for i = 1:numel(parts)
    t = parts{i}; if ~isempty(txt), t = [txt '  ·  ' parts{i}]; end
    if isempty(txt) || numel(t) <= 140, txt = t; end
end
end
