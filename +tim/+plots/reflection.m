function info = reflection(ax, res, opts)
%REFLECTION Results view: reflection and transmission of the specimen.
%   info = tim.plots.reflection([axTop axBottom], res)
%   info = tim.plots.reflection([axTop axBottom], res, struct('simulation', true))
%   info = tim.plots.reflection([axTop axBottom], [])          empty state
%
%   Top axes (about 2/3 of the height): |R| at the front face, |tau|
%   (transmitted wave at the rear face / incident wave at the front face)
%   and the dissipated fraction alpha = 1 - |R|^2 - |tau|^2, each masked
%   with its validity mask (|R|: validR; |tau| and alpha: validTau, they
%   need an anechoic termination), plus |R_term| of the termination
%   (dotted; grey where the downstream pair is not trustworthy: outside
%   the band, geometry or quality incl. calibration not OK) and the limit
%   up to which tau counts as anechoic (dashed).
%   Bottom axes: angle of R (wrapped; the line is broken at the +-180 deg
%   wraps). A single axes gets the top part only. Stepped sine: markers;
%   a step without a value (NaN) is marked by a hollow triangle on the
%   x axis so that no step is lost.
%
%   opts (all optional): band [fMin fMax] (default res.analysis.options.fRange,
%   else [120 4500]), simulation, emptyText, stepped (default from res.kind),
%   anechoicRmax (only used when the result does not carry the value of its
%   own validity masks, res.analysis.options.anechoicRmax).
%
%   info.summary  octave bands: Band [Hz] | |R| | |τ| | α  (mean over the
%                 VALID bins of each band, '–' when there is none)
%   info.note     one-line explanation for the view header ('' when none)
%   info.lines    coloured curves [|R| |tau| alpha |R_term| limit] (legend order)
if nargin < 3, opts = struct(); end
P = tim.gui.palette();
o = viewOptions(res, opts);
ax1 = ax(1); ax2 = []; if numel(ax) > 1, ax2 = ax(2); end
for axi = ax(:).'
    legend(axi, 'off'); cla(axi); hold(axi, 'on'); set(axi, 'XScale', 'log', 'YDir', 'normal'); tim.plots.style(axi);   % style after XScale: no minor ticks
end
mn = char(8722);                                      % minus sign
ylabel(ax1, 'Magnitude, energy fraction [–]');
if isempty(ax2), xlabel(ax1, 'Frequency [Hz]'); else, ylabel(ax2, '\angle R [\circ]'); xlabel(ax2, 'Frequency [Hz]'); end
centres = octaveCentres(o.band);
info = struct('summary', [], 'note', '', 'lines', gobjects(0));

if isempty(o.a)                                       % ---- empty state
    title(ax1, char(160));                            % keeps the title line: no jump when data arrive
    tim.plots.fitAxes(ax1, 'XRange', o.band, 'YRange', [0 1], 'YStep', 0.2);
    if ~isempty(ax2), tim.plots.fitAxes(ax2, 'XRange', o.band, 'YRange', [-180 180], 'YStep', 90); end
    tim.plots.emptyState(ax1, o.emptyText);
    info.summary = bandSummary(centres, repmat({char(8211)}, numel(centres), 3));
    return
end

a = o.a; f = a.f; v = a.valid;
mo = struct('stepped', o.stepped);
[hR, gR] = tim.plots.masked(ax1, f, abs(a.R), v.validR, P.q.first, mo);
[hT, gT] = tim.plots.masked(ax1, f, abs(a.tau), v.validTau, P.q.second, mo);
[hA, gA] = tim.plots.masked(ax1, f, a.power.alpha, v.validTau, P.q.third, mo);
% termination diagnostic: trustworthy where the downstream decomposition is
% (in band, geometry and quality OK - incl. the calibration), grey elsewhere
okRt = v.measured & v.geometryOK & v.qualityOK;
[hRt, gRt] = tim.plots.masked(ax1, f, abs(a.Rterm), okRt, P.q.ref, ...
    struct('stepped', o.stepped, 'lineStyle', ':', 'lineWidth', 1.4));
hLim = yline(ax1, o.anechoicRmax, '--', 'Color', P.q.ref, 'LineWidth', 1);
uistack([gRt; gA; gT; gR], 'bottom');                 % all grey curves under all coloured ones
title(ax1, tim.plots.dataTitle(res, struct('simulation', o.simulation)), 'Interpreter', 'none');
info.lines = [hR hT hA hRt hLim];
tim.plots.legend(ax1, info.lines, {'|R|', '|\tau|', ['\alpha = 1 ' mn ' |R|^2 ' mn ' |\tau|^2'], ...
    '|R_{term}|', sprintf('|R_{term}| limit (%g)', o.anechoicRmax)});
xr = o.band;                                         % analysis band; stepped: every step stays visible
if o.stepped, xr = [min([o.band(1); f(:)]) max([o.band(2); f(:)])]; end
if ~isempty(ax2)
    [fp, ph, okp] = breakWraps(f, rad2deg(angle(a.R)), v.validR);
    tim.plots.masked(ax2, fp, ph, okp, P.q.first, mo);
    linkaxes([ax1 ax2], 'x');
    tim.plots.fitAxes(ax2, 'XRange', xr, 'YRange', [-180 180], 'YStep', 90);
end
tim.plots.fitAxes(ax1, 'XRange', xr, 'YRange', [0 1], 'YStep', 0.2);
miss = o.stepped & ~isfinite(a.R);
markMissing(ax1, f(miss)); if ~isempty(ax2), markMissing(ax2, f(miss)); end

[~, ~, tR] = tim.plots.bandValues(f, abs(a.R), v.validR, centres, '%.2f');
[~, ~, tT] = tim.plots.bandValues(f, abs(a.tau), v.validTau, centres, '%.2f');
[~, ~, tA] = tim.plots.bandValues(f, a.power.alpha, v.validTau, centres, '%.2f');
info.summary = bandSummary(centres, [tR tT tA]);
info.note = resultNote(res, a, f(miss));
end

% ---------------------------------------------------------------------------
function s = bandSummary(centres, cells)
s = struct('title', 'Octave bands', ...
    'columns', {{'Band [Hz]', '|R|', '|τ|', 'α'}}, ...
    'data', {[arrayfun(@(c) sprintf('%g', c), centres(:), 'UniformOutput', false), cells]}, ...
    'note', ['Mean over the valid frequency lines of each octave band (centre/√2 … centre·√2); ' char(8211) ...
             ' = no valid frequency line. |τ| and α need an anechoic termination (|R_term| below the limit).']);
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
o.anechoicRmax = 0.1;
if isfield(opts, 'anechoicRmax') && ~isempty(opts.anechoicRmax), o.anechoicRmax = opts.anechoicRmax; end
if ~isempty(o.a) && isfield(o.a, 'options') && isfield(o.a.options, 'anechoicRmax')
    o.anechoicRmax = o.a.options.anechoicRmax;      % the limit the masks of this result used
end
end

function c = octaveCentres(band)
% octave bands 125 ... 4000 Hz that overlap the analysis band
c = [125 250 500 1000 2000 4000];
c = c(c * sqrt(2) > band(1) & c / sqrt(2) < band(2));
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

function markMissing(ax, fm)
% stepped sine: a step without a value stays visible as a hollow triangle on the x axis
if isempty(fm), return; end
P = tim.gui.palette();
yl = ax.YLim;
plot(ax, fm, repmat(yl(1) + 0.04 * diff(yl), numel(fm), 1), '^', 'MarkerSize', 7, 'LineWidth', 1, ...
    'MarkerEdgeColor', P.invalidMarker, 'MarkerFaceColor', 'w', 'XLimInclude', 'off', ...
    'YLimInclude', 'off', 'Clipping', 'off', 'Tag', 'timMissingStep', 'HitTest', 'off');
end

function txt = resultNote(res, a, fMissing)
% one line for the view header: why nothing / not everything is shown
parts = {};
if isfield(res, 'calibration') && isfield(res.calibration, 'applied') && ~res.calibration.applied
    parts{end + 1} = 'No calibration applied: nothing is valid (grey curves). Load or run a calibration and reprocess.';
elseif ~a.boundary.available
    parts{end + 1} = 'Specimen face positions unknown (L1, d, L2): R and τ are not available.';
elseif ~any(a.valid.validR)
    parts{end + 1} = 'No valid frequency line (grey curves). See Validity for the reasons.';
elseif ~any(a.valid.validTau)
    parts{end + 1} = 'τ and α not valid in any bin (termination not anechoic or quality) - see Validity';
end
if ~isempty(fMissing)
    parts{end + 1} = sprintf('No value at %s Hz (see Validity)', strjoin(arrayfun(@(x) sprintf('%.0f', x), ...
        fMissing(:).', 'UniformOutput', false), ', '));
end
% the header shows ONE line: the most important parts that fit (about 140 characters)
txt = '';
for i = 1:numel(parts)
    t = parts{i}; if ~isempty(txt), t = [txt '  ·  ' parts{i}]; end
    if isempty(txt) || numel(t) <= 140, txt = t; end
end
end
