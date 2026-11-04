function info = validity(ax, res, opts)
%VALIDITY Results view: which criterion passes in which frequency bin.
%   info = tim.plots.validity(ax, res)
%   info = tim.plots.validity(ax, res, struct('simulation', true))
%   info = tim.plots.validity(ax, [])                          empty state
%
%   One row per criterion, the label on the left at the row centre (YTick)
%   and the bins drawn as a band CENTRED on that tick: 'true' dark blue,
%   'false' light grey (neutral colours - not the channel colours).
%   Rows (top to bottom): Measured (in band), Geometry OK, Quality OK,
%   Passive, Valid, Valid R, Valid tau / TL, Valid thin Z_t, Validated
%   (experiment); below a thin separator every rejection flag of
%   res.analysis.valid.flags as 'rejected by <flag>', red where it rejects.
%   Swept sine / noise: contiguous bins are drawn as bands (bin edges at the
%   geometric mid-points). Stepped sine: one square marker per step - EVERY
%   step, also one without a value (light grey with a darker edge, so it
%   stays visible on white).
%
%   opts (all optional): band [fMin fMax] (default res.analysis.options.fRange,
%   else [120 4500]), simulation, emptyText, stepped (default from res.kind),
%   transferMatrix (a result of tim.app.processTwoLoad, WO-005: below a
%   second separator the rows of the transfer matrix - both loads valid,
%   loads differ (condQ), Valid T, reciprocal, the repeat of load A - the
%   last two report only).
%
%   info.summary  Criterion | Passing (bins) | % | Affects (which results
%                 the criterion masks); note = res.analysis.valid.summary +
%                 what '(R: M1/M2)' means. The rows and flags above 'Valid R'
%                 are for BOTH microphone pairs: they mask |τ|, α_d, TL and
%                 Z_t; R needs only the upstream pair M1/M2 (row Valid R) and
%                 is rejected only by their M1/M2 part.
%   info.note     one-line explanation for the view header ('' when none)
%   info.lines    patch / line handles of the rows (top to bottom)
if nargin < 3, opts = struct(); end
P = tim.gui.palette();
o = viewOptions(res, opts);
ax = ax(1);
legend(ax, 'off'); cla(ax); hold(ax, 'on'); ax.XScale = 'log'; tim.plots.style(ax);
cOn = [0.20 0.40 0.80]; cOff = [0.90 0.90 0.90]; cEdge = [0.60 0.60 0.60]; cRej = P.fail;

rows = criteria(o.a, o.tl);
n = numel(rows);
grp = [rows.group];
y = (1:n) + 0.6 * (grp >= 1) + 0.6 * (grp >= 2);     % gaps: criteria | flags | transfer matrix
info = struct('summary', [], 'note', '', 'lines', gobjects(1, 0));
xlabel(ax, 'Frequency [Hz]'); ylabel(ax, '');
% rows are placed here, not by fitAxes: forget fitted y limits of an earlier
% view in this axes (its limit listener would switch the row ticks to auto)
if isappdata(ax, 'timFitAxes'), rmappdata(ax, 'timFitAxes'); end
set(ax, 'YDir', 'reverse', 'YLim', [y(1) - 0.6, y(end) + 0.6], 'YGrid', 'off');
set(ax, 'YTick', y, 'YTickLabel', {rows.label}, 'TickLabelInterpreter', 'tex');
for g = 1:2
    sepY = y(find(grp == g, 1)) - 0.8;
    if ~isempty(sepY)
        plot(ax, [1e-3 1e6], [sepY sepY], '-', 'Color', [0.80 0.80 0.82], 'LineWidth', 0.8, ...
            'XLimInclude', 'off', 'YLimInclude', 'off', 'HitTest', 'off');
    end
end

if isempty(o.a)                                       % ---- empty state
    title(ax, char(160));                             % keeps the title line: no jump when data arrive
    tim.plots.fitAxes(ax, 'Axis', 'x', 'XRange', o.band);
    tim.plots.emptyState(ax, o.emptyText);
    info.summary = summaryTable(rows, 0, rNote());
    return
end

a = o.a; f = a.f(:);
h = 0.30;                                             % half height of a band (row spacing 1)
for i = 1:n
    m = logical(rows(i).mask(:));
    cTrue = cOn; if rows(i).flag, cTrue = cRej; end
    if o.stepped
        fy = f; fy(~m) = NaN;                         % NaN keeps one handle per row
        plot(ax, f, repmat(y(i), numel(f), 1), 's', 'MarkerSize', 8, ...      % every step, 'false' look
            'MarkerFaceColor', cOff, 'MarkerEdgeColor', cEdge, 'LineStyle', 'none');
        info.lines(i) = plot(ax, fy, repmat(y(i), numel(f), 1), 's', 'MarkerSize', 8, ...
            'MarkerFaceColor', cTrue, 'MarkerEdgeColor', cTrue, 'LineStyle', 'none');
    else
        [lo, hi] = binEdges(f);
        patch(ax, [lo(1) hi(end) hi(end) lo(1)], y(i) + [-h -h h h], cOff, 'EdgeColor', 'none', 'HitTest', 'off');
        info.lines(i) = runs(ax, lo, hi, m, y(i), h, cTrue);
    end
end
title(ax, tim.plots.dataTitle(res, struct('simulation', o.simulation)), 'Interpreter', 'none');
xr = o.band;                                         % analysis band; stepped: every step stays visible
if o.stepped, xr = [min([o.band(1); f(:)]) max([o.band(2); f(:)])]; end
tim.plots.fitAxes(ax, 'Axis', 'x', 'XRange', xr);
sn = [a.valid.summary ' ' rNote()];
if ~isempty(o.tl), sn = sprintf('Transfer matrix: %s. Load shown: %s', o.tl.valid.summary, sn); end
info.summary = summaryTable(rows, numel(f), sn);
nR = nnz(a.valid.validR);                             % R: upstream pair only (validityMasks)
if isfield(res, 'calibration') && isfield(res.calibration, 'applied') && ~res.calibration.applied
    info.note = 'No calibration applied: no frequency line is valid. Load or run a calibration and reprocess.';
elseif ~a.boundary.available
    info.note = 'Specimen face positions unknown (L1, d, L2): R, τ, TL and Z_t are not available.';
elseif ~any(a.valid.valid) && nR == 0
    info.note = 'No valid frequency line. The red rows show which criteria reject them.';
elseif ~any(a.valid.valid)
    info.note = sprintf(['No frequency line valid for τ, TL and Z_t (red rows); R valid on %d lines ' ...
        '(upstream pair M1/M2).'], nR);
end
nm = ~a.valid.measured;
if o.stepped && any(nm)                               % a step that was not evaluated at all
    t = sprintf('Step %s Hz not evaluated (outside the analysis band or no value)', ...
        strjoin(arrayfun(@(x) sprintf('%.0f', x), f(nm).', 'UniformOutput', false), ', '));
    if isempty(info.note), info.note = t; elseif numel(info.note) + numel(t) < 135, info.note = [info.note '  ·  ' t]; end
end
end

% ---------------------------------------------------------------------------
function rows = criteria(a, tl)
% rows of the view: label (TeX), plain name, mask, flag row?, what it affects,
% group (0 criteria, 1 rejection flags, 2 transfer matrix, WO-005).
% Both-pair criteria mask τ, α_d, TL and Z_t; R (validR = upstream.valid) has
% its own pair-1 version of them: '(R: M1/M2)', see rNote
if nargin < 2, tl = []; end
both = ['|τ|, α_d, TL, Z_t ' rOnly()];
S = {'Measured (in band)',            'Measured (in band)',          'measured',    both
     'Geometry OK',                   'Geometry OK',                 'geometryOK',  both
     'Quality OK (coherence, SNR, cal.)', 'Quality OK (coherence, SNR, cal.)', 'qualityOK', both
     'Passive',                       'Passive',                     '~nonPassive', '|τ|, α_d, TL, Z_t (R: |R| > 1)'
     '\bfValid',                      'Valid',                       'valid',       '|τ|, α_d, TL, Z_t'
     'Valid R',                       'Valid R',                     'validR',      '|R|, ∠R'
     'Valid \tau / TL',               'Valid τ / TL',                'validTau',    '|τ|, α_d, TL'
     'Valid thin Z_t',                'Valid thin Z_t',              'validThinZt', 'Z_t, TL from Z_t'
     'Validated (experiment)',        'Validated (experiment)',      'validated',   'report only'};
flags = {'outsideBand', 'belowSpacingLimit', 'aboveSpacingLimit', 'aboveModeCutOn', 'nearSingularity', ...
    'illConditioned', 'phaseSensitive', 'lowCoherence', 'lowSNR', 'calInvalid', 'outsideCalibration', 'nonPassive', ...
    'velocityMismatch', 'terminationNotAnechoic'};
if ~isempty(a) && isfield(a.valid, 'flags')
    flags = [flags(ismember(flags, fieldnames(a.valid.flags))), ...
        setdiff(fieldnames(a.valid.flags).', flags, 'stable')];   % known order, then any new flag
end
nF = 0; if ~isempty(a), nF = numel(a.f); end
rows = struct('label', {}, 'name', {}, 'mask', {}, 'flag', {}, 'affects', {}, 'group', {});
for i = 1:size(S, 1)
    m = false(nF, 1);
    if ~isempty(a)
        if strcmp(S{i, 3}, '~nonPassive'), m = ~a.valid.flags.nonPassive; else, m = a.valid.(S{i, 3}); end
    end
    rows(end + 1) = struct('label', S{i, 1}, 'name', S{i, 2}, 'mask', m, 'flag', false, 'affects', S{i, 4}, ...
        'group', 0); %#ok<AGROW>
end
for i = 1:numel(flags)
    m = false(nF, 1);
    if ~isempty(a), m = a.valid.flags.(flags{i}); end
    rows(end + 1) = struct('label', ['Rejected: ' flagName(flags{i})], 'name', ['Rejected: ' flagName(flags{i})], ...
        'mask', m, 'flag', true, 'affects', flagAffects(flags{i}), 'group', 1); %#ok<AGROW>
end
if isempty(tl) || isempty(a) || numel(tl.f) ~= nF, return; end
% ---- transfer matrix (two loads, or one load of a symmetric specimen)
v = tl.valid; aff = 'T, TL, R_a, α';
if strcmp(tl.method, 'oneLoadSymmetric')
    T = {'Load valid (symmetric assumed)', v.base, aff
         '\bfValid T', v.valid, aff};
else
    T = {'Both loads valid', v.base, aff
         sprintf('Loads differ (cond(Q) %s %g)', char(8804), v.condQMax), v.loadsDiffer & isfinite(tl.condQ), aff
         '\bfValid T', v.valid, aff
         sprintf('Reciprocal (|det T %s 1| %s %g)', char(8722), char(8804), v.reciprocityTol), ~v.notReciprocal, ...
            'report only (a quality indicator)'};
    if tl.repeat.performed
        T(end + 1, :) = {sprintf('Load A repeat (%s %g)', char(8804), tl.repeat.tol), tl.repeat.diff <= tl.repeat.tol, ...
            'report only (median decides)'};
    end
end
for i = 1:size(T, 1)
    nm = strrep(strrep(T{i, 1}, '\bf', ''), '\tau', 'τ');
    rows(end + 1) = struct('label', T{i, 1}, 'name', nm, 'mask', logical(T{i, 2}(:)), 'flag', false, ...
        'affects', T{i, 3}, 'group', 2); %#ok<AGROW>
end
end

function t = flagName(name)
% operator name of a rejection flag (no internal identifiers in the GUI)
switch name
    case 'outsideBand', t = 'outside the analysis band';
    case 'belowSpacingLimit', t = 'below the spacing limit';
    case 'aboveSpacingLimit', t = 'above the spacing limit';
    case 'aboveModeCutOn', t = 'above the (1,1) cut-on';
    case 'nearSingularity', t = 'near the spacing singularity';
    case 'illConditioned', t = 'ill-conditioned';
    case 'phaseSensitive', t = 'phase sensitivity';
    case 'lowCoherence', t = 'low coherence';
    case 'lowSNR', t = 'low SNR';
    case 'calInvalid', t = 'no valid calibration';
    case 'outsideCalibration', t = 'outside the calibration range';
    case 'nonPassive', t = 'not passive';
    case 'velocityMismatch', t = 'velocity mismatch';
    case 'terminationNotAnechoic', t = 'termination not anechoic';
    otherwise, t = lower(regexprep(name, '([a-z])([A-Z])', '$1 $2'));
end
end

function t = flagAffects(name)
% the both-pair flags reject R only through their pair-1 (M1/M2) part
% (tim.acoustics.validityMasks, v.upstream.flags; R needs only the calibration
% of the channels in M1 / M2); the mode cut-on is the same for both pairs
switch name
    case 'aboveModeCutOn', t = 'all results';
    case {'outsideBand', 'belowSpacingLimit', 'aboveSpacingLimit', 'nearSingularity', ...
            'illConditioned', 'phaseSensitive', 'lowCoherence', 'lowSNR', 'calInvalid', 'outsideCalibration'}, t = ['|τ|, α_d, TL, Z_t ' rOnly()];
    case 'nonPassive', t = '|τ|, α_d, TL, Z_t (R: |R| > 1)';
    case 'velocityMismatch', t = 'Z_t, TL from Z_t';
    case 'terminationNotAnechoic', t = '|τ|, α_d, TL';
    otherwise, t = 'see Valid';
end
end

function t = rOnly()
t = '(R: M1/M2)';
end

function t = rNote()
% the table note: what '(R: M1/M2)' in the Affects column means
t = sprintf(['%s = R needs only the upstream pair: it is rejected only where the criterion fails at ' ...
    'M1/M2 (row Valid R).'], rOnly());
end

function s = summaryTable(rows, nBins, note)
d = cell(numel(rows), 4);
for i = 1:numel(rows)
    pass = nnz(rows(i).mask); if rows(i).flag, pass = nBins - nnz(rows(i).mask); end
    d{i, 1} = rows(i).name;
    if nBins == 0
        d{i, 2} = char(8211); d{i, 3} = char(8211);
    else
        d{i, 2} = pass; d{i, 3} = sprintf('%.0f', 100 * pass / nBins);
    end
    d{i, 4} = rows(i).affects;
end
s = struct('title', 'Validity criteria', 'columns', {{'Criterion', 'Passing', '%', 'Affects'}}, ...
    'data', {d}, 'note', note);
end

function [lo, hi] = binEdges(f)
% bin edges on a logarithmic axis: geometric mid-points between neighbours
if numel(f) == 1, lo = f / 1.02; hi = f * 1.02; return; end
e = sqrt(f(1:end - 1) .* f(2:end));
lo = [f(1)^2 / e(1); e];
hi = [e; f(end)^2 / e(end)];
end

function hp = runs(ax, lo, hi, m, y, h, c)
% one patch with a face per run of contiguous true bins (edge in the face
% colour: a single bin stays at least one pixel wide)
d = diff([false; m; false]);
s = find(d == 1); e = find(d == -1) - 1;
X = [lo(s) hi(e) hi(e) lo(s)].';
Y = repmat(y + [-h; -h; h; h], 1, numel(s));
if isempty(s), X = nan(4, 1); Y = nan(4, 1); end
hp = patch(ax, X, Y, c, 'EdgeColor', c, 'LineWidth', 0.5, 'HitTest', 'off');
end

function o = viewOptions(res, opts)
% options of a result view: explicit opts first, then the values of the result
o.a = [];
if isstruct(res) && isfield(res, 'analysis') && isstruct(res.analysis), o.a = res.analysis; end
o.band = [120 4500];
if ~isempty(o.a) && isfield(o.a, 'options') && isfield(o.a.options, 'fRange') && numel(o.a.options.fRange) == 2
    o.band = o.a.options.fRange(:).';
end
if isfield(opts, 'band') && numel(opts.band) == 2, o.band = opts.band(:).'; end
o.simulation = isfield(opts, 'simulation') && ~isempty(opts.simulation) && opts.simulation;
o.emptyText = 'No measurement yet';
if isfield(opts, 'emptyText') && ~isempty(opts.emptyText), o.emptyText = opts.emptyText; end
o.stepped = isstruct(res) && isfield(res, 'kind') && strcmp(res.kind, 'stepped');
if isfield(opts, 'stepped') && ~isempty(opts.stepped), o.stepped = logical(opts.stepped); end
o.tl = [];                                            % transfer-matrix result (tim.app.processTwoLoad)
if isfield(opts, 'transferMatrix') && isstruct(opts.transferMatrix) && ~isempty(opts.transferMatrix)
    o.tl = opts.transferMatrix;
end
end
