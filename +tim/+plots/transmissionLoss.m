function info = transmissionLoss(ax, res, opts)
%TRANSMISSIONLOSS Results view: transmission loss of the specimen.
%   info = tim.plots.transmissionLoss(ax, res)
%   info = tim.plots.transmissionLoss(ax, res, struct('simulation', true))
%   info = tim.plots.transmissionLoss(ax, [])                  empty state
%
%   TL = -20 log10|tau| from the measured transmission coefficient (needs an
%   anechoic termination: masked with validTau; solid, first quantity
%   colour). Thin specimen only: TL from the thin-element transfer impedance,
%   TL = 20 log10|1 + Z_t/(2 Z_c)|, Z_c = characteristic impedance of the
%   tube-loss model (|Z_c/rho c - 1| <= 0.5 %; res.analysis.thin.TL_dB,
%   masked with validThinZt; dashed, second quantity colour). Thick specimen
%   (tim.plots.thickSpecimen, k*d > 1): the Z_t curve is not drawn and
%   info.note says why. Face positions unknown (L1, d, L2): no curve, the
%   axes show an explanatory empty state with the default limits. Stepped
%   sine: markers; a step without a value is marked by a hollow triangle on
%   the x axis.
%
%   opts (all optional): band [fMin fMax] (default res.analysis.options.fRange,
%   else [120 4500]), simulation, emptyText, stepped (default from res.kind).
%
%   info.summary  octave bands: Band [Hz] | TL [dB] (| TL from Z_t [dB]),
%                 energy mean over the VALID frequency lines of each band:
%                 TL_band = -10 log10(mean |tau|^2), '–' when there is none;
%                 bands of tim.plots.octaveBands ('*' = only partly inside
%                 the analysis band)
%   info.note     one-line explanation for the view header ('' when none)
%   info.lines    coloured curves [TL from tau (, TL from Z_t)] (legend order)
if nargin < 3, opts = struct(); end
P = tim.gui.palette();
o = viewOptions(res, opts);
ax = ax(1);
legend(ax, 'off'); cla(ax); hold(ax, 'on'); set(ax, 'XScale', 'log', 'YDir', 'normal'); tim.plots.style(ax);
mn = char(8722);
ylabel(ax, 'Transmission loss [dB]'); xlabel(ax, 'Frequency [Hz]');
B = tim.plots.octaveBands(o.band); centres = B.centres;
info = struct('summary', [], 'note', '', 'lines', gobjects(0));

if isempty(o.a)                                       % ---- empty state
    title(ax, char(160));                             % keeps the title line: no jump when data arrive
    tim.plots.fitAxes(ax, 'XRange', o.band, 'YRange', [0 30], 'YSteps', [1 2 5]);
    tim.plots.emptyState(ax, o.emptyText);
    info.summary = bandSummary(B, repmat({char(8211)}, numel(centres), 1), false);
    return
end

a = o.a; f = a.f; v = a.valid;
if ~a.boundary.available                              % ---- face positions unknown: nothing to draw
    msg = 'Specimen face positions unknown (L1, d, L2): the transmission loss is not available.';
    title(ax, tim.plots.dataTitle(res, struct('simulation', o.simulation)), 'Interpreter', 'none');
    tim.plots.fitAxes(ax, 'XRange', o.band, 'YRange', [0 30], 'YSteps', [1 2 5]);
    tim.plots.emptyState(ax, msg);
    info.summary = bandSummary(B, repmat({char(8211)}, numel(centres), 1), false);
    info.summary.note = msg;
    t = strrep(resultNote(res, a, false), ' (grey curves)', '');   % a missing calibration first
    if strcmp(t, msg), t = ''; end
    info.note = joinNotes({t, msg});
    return
end

[thick, thickTxt] = tim.plots.thickSpecimen(a);
showZt = a.boundary.available && ~thick;
mo = struct('stepped', o.stepped);
[h1, g1] = tim.plots.masked(ax, f, a.power.TL_tau_dB, v.validTau, P.q.first, mo);
info.lines = h1; names = {['TL = ' mn '20 log_{10}|\tau|']};
grey = g1; okAll = v.validTau & isfinite(a.power.TL_tau_dB);
if showZt
    mo.lineStyle = '--';
    [h2, g2] = tim.plots.masked(ax, f, a.thin.TL_dB, v.validThinZt, P.q.second, mo);
    info.lines(end + 1) = h2; names{end + 1} = 'TL from Z_t = 20 log_{10}|1 + Z_t / (2Z_c)|';
    grey = [grey; g2]; okAll = okAll | (v.validThinZt & isfinite(a.thin.TL_dB));
    uistack(grey, 'bottom');
end
if any(okAll) && ~o.stepped
    set(grey, 'YLimInclude', 'off');                 % y range from the valid values (no invalid spikes)
end
title(ax, tim.plots.dataTitle(res, struct('simulation', o.simulation)), 'Interpreter', 'none');
tim.plots.legend(ax, info.lines, names);
xr = o.band;                                         % analysis band; stepped: every step stays visible
if o.stepped, xr = [min([o.band(1); f(:)]) max([o.band(2); f(:)])]; end
tim.plots.fitAxes(ax, 'XRange', xr, 'YInclude', 0, 'YSteps', [1 2 5]);
miss = o.stepped & ~isfinite(a.power.TL_tau_dB);
markMissing(ax, f(miss));

% energy mean per band: TL_band = -10 log10(mean |tau|^2) of the valid bins
tl2txt = @(m) arrayfun(@(x) fmtTL(x), m, 'UniformOutput', false);
m1 = tim.plots.bandValues(f, 10.^(-a.power.TL_tau_dB / 10), v.validTau, centres);
cells = tl2txt(m1);
if showZt
    m2 = tim.plots.bandValues(f, 10.^(-a.thin.TL_dB / 10), v.validThinZt, centres);
    cells = [cells tl2txt(m2)];
end
info.summary = bandSummary(B, cells, showZt);
parts = {resultNote(res, a, showZt)};               % in order of importance
if thick, parts{end + 1} = [thickTxt ' - TL from Z_t not shown']; end
if any(miss)
    parts{end + 1} = sprintf('No value at %s Hz (see Validity)', strjoin(arrayfun(@(x) sprintf('%.0f', x), ...
        f(miss).', 'UniformOutput', false), ', '));
end
info.note = joinNotes(parts);
end

% ---------------------------------------------------------------------------
function txt = joinNotes(parts)
% the header shows ONE line: the most important parts that fit (about 140 characters)
parts = parts(~cellfun(@isempty, parts));
txt = '';
for i = 1:numel(parts)
    t = parts{i}; if ~isempty(txt), t = [txt '  ·  ' parts{i}]; end
    if isempty(txt) || numel(t) <= 140, txt = t; end
end
end

% ---------------------------------------------------------------------------
function s = fmtTL(tauPow)
if isnan(tauPow), s = char(8211); else, s = sprintf('%.1f', -10 * log10(tauPow)); end
end

function s = bandSummary(B, cells, withZt)
cols = {'Band [Hz]', 'TL [dB]'};
if withZt, cols{end + 1} = 'TL from Z_t [dB]'; end
note = ['Energy mean over the valid frequency lines of each octave band: TL = ' char(8722) ...
        '10·log10(mean |τ|²); ' char(8211) ' = no valid frequency line. TL from τ needs an anechoic termination.'];
if ~isempty(B.note), note = [note ' ' B.note]; end
s = struct('title', 'Octave bands', 'columns', {cols}, 'data', {[B.labels, cells]}, 'note', note);
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

function txt = resultNote(res, a, showZt)
% why nothing is valid (one line for the view header)
txt = '';
if isfield(res, 'calibration') && isfield(res.calibration, 'applied') && ~res.calibration.applied
    txt = 'No calibration applied: nothing is valid (grey curves). Load or run a calibration and reprocess.';
elseif ~a.boundary.available
    txt = 'Specimen face positions unknown (L1, d, L2): the transmission loss is not available.';
elseif ~any(a.valid.validTau) && ~(showZt && any(a.valid.validThinZt))
    txt = 'No valid frequency line (grey curves). See Validity for the reasons.';
end
end
