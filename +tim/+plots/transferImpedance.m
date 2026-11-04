function info = transferImpedance(ax, res, opts)
%TRANSFERIMPEDANCE Results view: thin-element transfer impedance Z_t / rho c.
%   info = tim.plots.transferImpedance([axRe axIm], res)
%   info = tim.plots.transferImpedance([axRe axIm], res, struct('simulation', true))
%   info = tim.plots.transferImpedance([axRe axIm], [])        empty state
%
%   Re{Z_t}/rho c (top) and Im{Z_t}/rho c (bottom), Z_t = (p_L - p_R)/u of
%   a lumped element (u per res.analysis.thin.velocityRef), masked with
%   validThinZt (velocity continuity across the element, boundary data,
%   overall validity). Thick specimen (tim.plots.thickSpecimen, k*d > 1) or
%   unknown face positions: the axes keep their labels and default limits
%   and show an explanatory empty state; info.note says why. Stepped sine:
%   markers; a step without a value is marked by a hollow triangle on the
%   x axis.
%
%   opts (all optional): band [fMin fMax] (default res.analysis.options.fRange,
%   else [120 4500]), simulation, emptyText, stepped (default from res.kind),
%   transferMatrix (a result of tim.app.processTwoLoad, WO-005: Z_t = T12,
%   coloured where T is valid and the specimen is a thin element by T itself,
%   |Zc T21| and |T22 - 1| at most the velocity-mismatch limit; drawn also
%   for a thick specimen, then in grey, and the note says why).
%
%   info.summary  octave bands: Band [Hz] | Re{Z_t}/ρc | Im{Z_t}/ρc (mean over
%                 the VALID frequency lines of each band, '–' when there is
%                 none; bands of tim.plots.octaveBands, '*' = only partly
%                 inside the analysis band); for a thick specimen '–'
%                 everywhere and the reason in the note
%   info.note     one-line explanation for the view header ('' when none)
%   info.lines    coloured curves [Re Im] (empty when not drawn)
if nargin < 3, opts = struct(); end
P = tim.gui.palette();
o = viewOptions(res, opts);
ax1 = ax(1); ax2 = []; if numel(ax) > 1, ax2 = ax(2); end
for axi = ax(:).'
    legend(axi, 'off'); cla(axi); hold(axi, 'on'); set(axi, 'XScale', 'log', 'YDir', 'normal'); tim.plots.style(axi);
end
ylabel(ax1, 'Re\{Z_t\} / (\rho{}c) [–]');
if isempty(ax2)
    xlabel(ax1, 'Frequency [Hz]');
else
    ylabel(ax2, 'Im\{Z_t\} / (\rho{}c) [–]'); xlabel(ax2, 'Frequency [Hz]');
end
B = tim.plots.octaveBands(o.band); centres = B.centres;
dash = repmat({char(8211)}, numel(centres), 2);
info = struct('summary', bandSummary(B, dash, ''), 'note', '', 'lines', gobjects(0));

% ---- with a transfer matrix (WO-005): its series element T12 is Z_t where the
% specimen behaves as a thin element (Zc T21 ~ 0, T22 ~ 1)
if ~isempty(o.a) && ~isempty(o.tl) && o.a.boundary.available
    info = seriesElement(ax1, ax2, o, B, info);
    return
end
% ---- nothing to draw: empty state with the default limits
msg = '';
if isempty(o.a)
    msg = o.emptyText;
else
    a = o.a;
    [thick, thickTxt] = tim.plots.thickSpecimen(a);
    if ~a.boundary.available
        msg = 'Specimen face positions unknown (L1, d, L2): the transfer impedance is not available.';
    elseif thick
        msg = [thickTxt '. See Transmission loss or Reflection and transmission.'];
    end
end
shown = msg;                                          % two lines in the axes: fits a narrow view
if ~isempty(o.a) && thick && a.boundary.available
    shown = {thickTxt, 'See Transmission loss or Reflection and transmission.'};
end
if ~isempty(msg)
    if isempty(o.a)
        title(ax1, char(160));                        % keeps the title line: no jump when data arrive
    else
        title(ax1, tim.plots.dataTitle(res, struct('simulation', o.simulation)), 'Interpreter', 'none');
        info.note = joinNotes({strrep(noCalNote(res), ' (grey curves)', ''), msg});
        if ~a.boundary.available, info.summary.note = msg; else, info.summary.note = [thickTxt '.']; end
    end
    tim.plots.fitAxes(ax1, 'XRange', o.band, 'YRange', [0 2], 'YStep', 0.5);
    if ~isempty(ax2), tim.plots.fitAxes(ax2, 'XRange', o.band, 'YRange', [-1 1], 'YStep', 0.5); end
    tim.plots.emptyState(ax1, shown);
    return
end

% ---- thin element
f = a.f; ok = a.valid.validThinZt; z = a.thin.Zt_norm;
mo = struct('stepped', o.stepped, 'outside', tim.plots.calOutside(a.valid));   % diamonds outside the calibration range
xr = o.band;                                         % analysis band; stepped: every step stays visible
if o.stepped, xr = [min([o.band(1); f(:)]) max([o.band(2); f(:)])]; end
[hRe, gRe] = tim.plots.masked(ax1, f, real(z), ok, P.q.first, mo);
info.lines = hRe;
title(ax1, tim.plots.dataTitle(res, struct('simulation', o.simulation)), 'Interpreter', 'none');
okAny = any(ok & isfinite(z)) && ~o.stepped;
if okAny, gRe.YLimInclude = 'off'; end                % y range from the valid values
if ~isempty(ax2)
    [hIm, gIm] = tim.plots.masked(ax2, f, imag(z), ok, P.q.second, mo);
    info.lines(2) = hIm;
    if okAny, gIm.YLimInclude = 'off'; end
    linkaxes([ax1 ax2], 'x');
    tim.plots.fitAxes(ax2, 'XRange', xr, 'YInclude', 0);
end
tim.plots.fitAxes(ax1, 'XRange', xr, 'YInclude', 0);
miss = o.stepped & ~isfinite(z);
markMissing(ax1, f(miss)); if ~isempty(ax2), markMissing(ax2, f(miss)); end

[~, ~, tRe] = tim.plots.bandValues(f, real(z), ok, centres, '%.2f');
[~, ~, tIm] = tim.plots.bandValues(f, imag(z), ok, centres, '%.2f');
switch a.thin.velocityRef
    case 'upstream', uTxt = 'u = front-face velocity';
    case 'downstream', uTxt = 'u = rear-face velocity';
    otherwise, uTxt = 'u = mean of the front- and rear-face velocities';
end
info.summary = bandSummary(B, [tRe tIm], sprintf(['Mean over the valid frequency lines of each octave band; ' ...
    '%s = no valid frequency line. ρc = %.1f Pa·s/m; %s.'], char(8211), a.air.Z0, uTxt));
parts = {noCalNote(res)};                           % in order of importance
if isempty(parts{1}) && ~any(ok)
    parts{end + 1} = 'No valid frequency line (grey curves; e.g. velocity mismatch across the element). See Validity.';
end
if any(miss)
    parts{end + 1} = sprintf('No value at %s Hz (see Validity)', strjoin(arrayfun(@(x) sprintf('%.0f', x), ...
        f(miss).', 'UniformOutput', false), ', '));
end
if ~isempty(findobj(ax1, 'Tag', 'timOutsideCalibration'))
    parts{end + 1} = 'Diamonds: steps outside the calibration range (indicative, never valid)';
end
info.note = joinNotes(parts);
end

% ---------------------------------------------------------------------------
function info = seriesElement(ax1, ax2, o, B, info)
% T12 / rho c of the transfer matrix, coloured where T is valid AND the
% specimen is a thin element by T itself (|Zc T21| and |T22 - 1| at most the
% velocity-mismatch limit): independent of the termination, unlike delta_u
P = tim.gui.palette(); tl = o.tl; f = tl.f;
lim = 0.10;
if isfield(o.a, 'options') && isfield(o.a.options, 'velocityMismatchMax'), lim = o.a.options.velocityMismatchMax; end
thin = tl.thin.T21Zc <= lim & tl.thin.T22dev <= lim;
ok = tl.valid.valid & thin;
z = tl.thin.Zt / tl.Z0;
xr = o.band;
[hRe, gRe] = tim.plots.masked(ax1, f, real(z), ok, P.q.first);
info.lines = hRe;
title(ax1, tim.plots.dataTitle(tl, struct('simulation', o.simulation)), 'Interpreter', 'none');
if any(ok), gRe.YLimInclude = 'off'; end
if ~isempty(ax2)
    [hIm, gIm] = tim.plots.masked(ax2, f, imag(z), ok, P.q.second);
    info.lines(2) = hIm;
    if any(ok), gIm.YLimInclude = 'off'; end
    linkaxes([ax1 ax2], 'x');
    tim.plots.fitAxes(ax2, 'XRange', xr, 'YInclude', 0);
end
tim.plots.fitAxes(ax1, 'XRange', xr, 'YInclude', 0);
[~, ~, tRe] = tim.plots.bandValues(f, real(z), ok, B.centres, '%.2f');
[~, ~, tIm] = tim.plots.bandValues(f, imag(z), ok, B.centres, '%.2f');
info.summary = bandSummary(B, [tRe tIm], sprintf(['Z_t = T12 of the transfer matrix, valid where T is valid and ' ...
    'the specimen is a thin element by T itself: |Z_c·T21| %s %g and |T22 %s 1| %s %g (independent of the ' ...
    'termination). Mean over those lines of each octave band; %s = none. ρc = %.1f Pa·s/m.'], char(8804), lim, ...
    char(8722), char(8804), lim, char(8211), tl.Z0));
if ~isempty(tl.checks.errors)
    info.note = ['Two loads not combined: ' tl.checks.errors{1}];
elseif any(tl.valid.valid) && ~any(ok)
    info.note = sprintf(['Not a thin element: |Z_c·T21| or |T22 %s 1| above %g on every valid line - T12 in grey; ' ...
        'see Transfer matrix'], char(8722), lim);
elseif ~any(tl.valid.valid)
    info.note = 'No valid frequency line of the transfer matrix (grey curves) - see Validity';
elseif strcmp(tl.method, 'oneLoadSymmetric')
    info.note = 'From one load: assumes a symmetric, reciprocal specimen';
end
end

function txt = noCalNote(res)
txt = '';
if isfield(res, 'calibration') && isfield(res.calibration, 'applied') && ~res.calibration.applied
    txt = 'No calibration applied: nothing is valid (grey curves). Load or run a calibration and reprocess.';
end
end

function txt = joinNotes(parts)
% the header shows ONE line: the most important parts that fit (about 140 characters)
parts = parts(~cellfun(@isempty, parts));
txt = '';
for i = 1:numel(parts)
    t = parts{i}; if ~isempty(txt), t = [txt '  ·  ' parts{i}]; end
    if isempty(txt) || numel(t) <= 140, txt = t; end
end
end

function s = bandSummary(B, cells, note)
if isempty(note)
    note = ['Mean over the valid frequency lines of each octave band; ' char(8211) ' = no valid frequency line.'];
end
if ~isempty(B.note), note = [note ' ' B.note]; end
s = struct('title', 'Octave bands', 'columns', {{'Band [Hz]', 'Re{Z_t}/ρc', 'Im{Z_t}/ρc'}}, ...
    'data', {[B.labels, cells]}, 'note', note);
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

function markMissing(ax, fm)
% stepped sine: a step without a value stays visible as a hollow triangle on the x axis
if isempty(fm), return; end
P = tim.gui.palette();
yl = ax.YLim;
plot(ax, fm, repmat(yl(1) + 0.04 * diff(yl), numel(fm), 1), '^', 'MarkerSize', 7, 'LineWidth', 1, ...
    'MarkerEdgeColor', P.invalidMarker, 'MarkerFaceColor', 'w', 'XLimInclude', 'off', ...
    'YLimInclude', 'off', 'Clipping', 'off', 'Tag', 'timMissingStep', 'HitTest', 'off');
end
