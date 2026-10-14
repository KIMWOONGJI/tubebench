function info = twoLoad(ax, tl, opts)
%TWOLOAD Measurement view of the two-load method: how well the loads determine T (WO-005).
%   info = tim.plots.twoLoad([axCond axRepeat], tl)
%   info = tim.plots.twoLoad([axCond axRepeat], tl, struct('simulation', true))
%   info = tim.plots.twoLoad([axCond axRepeat], [])            empty state
%
%   tl: the result of tim.app.processTwoLoad.
%   Top axes: condQ, the condition number of the boundary states of the two
%   loads (columns of unit length; 1 = independent, large = the loads are
%   too similar), black where both loads are valid, grey elsewhere; the limit
%   analysis.condQMax dashed - lines above it are not valid.
%   Bottom axes: the repeat of load A, |T(A,B) - T(A',B)| / |T(A,B)| per
%   line (elements in tube units: T12/Zc, Zc T21), with its tolerance
%   analysis.repeatTol dashed; without a repeat the axes say so.
%   One load (symmetric specimen assumed): no second load, no condQ - both
%   axes say so.
%
%   opts (all optional): band [fMin fMax] (default tl.band), simulation,
%   emptyText, sideBySide (the window: the axes next to each other, short
%   titles; the data title only in the stacked saved figure).
%
%   info.summary  the loads: Load | Termination | Valid | Peak [dB] | T [°C]
%   info.note     one-line explanation for the view header ('' when none)
%   info.lines    coloured curves [condQ limit (repeat tolerance)]
if nargin < 3, opts = struct(); end
P = tim.gui.palette();
ax1 = ax(1); ax2 = []; if numel(ax) > 1, ax2 = ax(2); end
for axi = ax(:).'
    legend(axi, 'off'); cla(axi); hold(axi, 'on'); set(axi, 'XScale', 'log', 'YScale', 'linear', 'YDir', 'normal');
    tim.plots.style(axi);
end
band = [120 4500];
if isstruct(tl) && isfield(tl, 'band') && numel(tl.band) == 2, band = tl.band; end
if isfield(opts, 'band') && numel(opts.band) == 2, band = opts.band(:).'; end
sim = isfield(opts, 'simulation') && ~isempty(opts.simulation) && opts.simulation;
emptyText = 'No two-load measurement yet';
if isfield(opts, 'emptyText') && ~isempty(opts.emptyText), emptyText = opts.emptyText; end
% opts.sideBySide (the Two-load view of the window): the two axes next to each
% other, each with its own short title; the loads table says which data
side = isfield(opts, 'sideBySide') && ~isempty(opts.sideBySide) && opts.sideBySide;
ylabel(ax1, 'cond(Q) [–]');
if isempty(ax2)
    xlabel(ax1, 'Frequency [Hz]');
else
    xlabel(ax2, 'Frequency [Hz]');
    if side
        xlabel(ax1, 'Frequency [Hz]');
        ylabel(ax2, ['Difference of T [' char(8211) ']']);
    else
        ylabel(ax2, ['|T(A,B) ' char(8722) ' T(A' char(8242) ',B)| / |T| [–]']);
    end
end
info = struct('summary', loadTable([]), 'note', '', 'lines', gobjects(0));
if side
    title(ax1, 'Condition number of the two loads', 'FontWeight', 'normal');
    if ~isempty(ax2)
        title(ax2, ['Repeat of load A: |T(A,B) ' char(8722) ' T(A' char(8242) ',B)| / |T|'], 'FontWeight', 'normal');
    end
end
if isempty(tl) || ~isstruct(tl)
    if ~side, title(ax1, char(160)); end
    tim.plots.fitAxes(ax1, 'XRange', band, 'YRange', [0 10], 'YStep', 2);
    if ~isempty(ax2), tim.plots.fitAxes(ax2, 'XRange', band, 'YRange', [0 0.1], 'YStep', 0.02); end
    tim.plots.emptyState(ax1, emptyText);
    return
end
f = tl.f; v = tl.valid;
if ~side, title(ax1, tim.plots.dataTitle(tl, struct('simulation', sim)), 'Interpreter', 'none'); end
info.summary = loadTable(tl);
if strcmp(tl.method, 'oneLoadSymmetric')
    tim.plots.fitAxes(ax1, 'XRange', band, 'YRange', [0 10], 'YStep', 2);
    tim.plots.emptyState(ax1, 'One load (symmetric specimen assumed): no second load, no condition number');
    if ~isempty(ax2)
        tim.plots.fitAxes(ax2, 'XRange', band, 'YRange', [0 0.1], 'YStep', 0.02);
        tim.plots.emptyState(ax2, 'No repeat of a load');
    end
    info.note = 'One load: T assumes a front-to-back symmetric, reciprocal specimen (ASTM E2611 one-load method).';
    return
end
% ---- condQ (clipped at 4 x the limit: the scale stays readable)
cmax = 4 * v.condQMax;
q = min(tl.condQ, cmax);
[hq, gq] = tim.plots.masked(ax1, f, q, v.base, P.q.first);
hl = yline(ax1, v.condQMax, '--', 'Color', P.fail, 'LineWidth', 1);
uistack(gq, 'bottom');
info.lines = [hq hl];
tim.plots.legend(ax1, info.lines, {'cond(Q) (both loads valid)', sprintf('limit (%g)', v.condQMax)}, 'northwest');
tim.plots.fitAxes(ax1, 'XRange', band, 'YRange', [0 max([v.condQMax * 1.2; q(isfinite(q))])], 'YInclude', 0);
% ---- repeat of load A
r = tl.repeat;
if ~isempty(ax2)
    if r.performed
        okR = v.valid & isfinite(r.diff);
        [hr, gr] = tim.plots.masked(ax2, f, r.diff, okR, P.q.third);
        ht = yline(ax2, r.tol, '--', 'Color', P.fail, 'LineWidth', 1);
        uistack(gr, 'bottom');
        info.lines = [info.lines hr ht];
        tim.plots.legend(ax2, [hr ht], {'repeat of load A (valid lines)', sprintf('tolerance (median, %g)', r.tol)}, ...
            'northwest');
        y = r.diff(okR);
        top = r.tol * 2; if ~isempty(y), top = max(top, min(prctile90(y) * 1.5, 1)); end
        set(gr, 'YLimInclude', 'off');
        tim.plots.fitAxes(ax2, 'XRange', band, 'YRange', [0 top]);
    else
        tim.plots.fitAxes(ax2, 'XRange', band, 'YRange', [0 0.1], 'YStep', 0.02);
        tim.plots.emptyState(ax2, 'Load A not repeated (Repeat load A at the end: off)');
    end
end
parts = {};
if ~isempty(tl.checks.errors)
    parts{end + 1} = ['Not combined: ' tl.checks.errors{1}];
elseif v.nValid == 0
    parts{end + 1} = 'No valid frequency line - see Validity.';
end
if r.performed && ~r.ok, parts{end + 1} = 'Load A repeat differs - did the specimen or a microphone move?'; end
if tl.level.warn, parts{end + 1} = sprintf('Load B %+.0f dB above load A', tl.level.stepB_dB); end
if ~isempty(tl.checks.warnings), parts{end + 1} = tl.checks.warnings{1}; end
info.note = joinNotes(parts);
end

% ---------------------------------------------------------------------------
function s = loadTable(tl)
cols = {'Load', 'Termination', 'Valid', 'Peak [dB]', 'T [°C]'};
note = ['Valid: share of the analysis band valid in this load (both microphone pairs). Peak: highest sound ' ...
    'pressure in the tube during the load (peak level).'];
if isempty(tl)
    s = struct('title', 'Loads', 'columns', {cols}, 'data', {cell(0, 5)}, 'note', note);
    return
end
L = tl.loads;
dat = cell(numel(L), 5);
for i = 1:numel(L)
    role = L(i).role;
    switch role
        case 'A2', role = ['A' char(8242)];
        case 'oneLoad', role = '1';
    end
    pk = char(8211); if isfinite(L(i).peakLevel_dB), pk = sprintf('%.1f', L(i).peakLevel_dB); end
    tt = char(8211); if isfinite(L(i).temperature_C), tt = sprintf('%.1f', L(i).temperature_C); end
    dat(i, :) = {role, L(i).label, sprintf('%.0f %%', 100 * L(i).validFraction), pk, tt};
end
n = tl.valid.summary;
if tl.repeat.performed, n = [n '. ' capital(tl.repeat.text)]; end
if ~isempty(tl.level.text), n = [n '. ' capital(tl.level.text)]; end
s = struct('title', 'Loads', 'columns', {cols}, 'data', {dat}, 'note', [n '. ' note]);
end

function s = capital(s)
if ~isempty(s), s(1) = upper(s(1)); end
end

function v = prctile90(x)
x = sort(x(:)); v = x(max(1, ceil(0.9 * numel(x))));
end

function txt = joinNotes(parts)
parts = parts(~cellfun(@isempty, parts));
txt = '';
for i = 1:numel(parts)
    t = parts{i}; if ~isempty(txt), t = [txt '  ·  ' parts{i}]; end
    if isempty(txt) || numel(t) <= 140, txt = t; end
end
end
