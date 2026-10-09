function info = transferFunctions(ax, res, opts)
%TRANSFERFUNCTIONS Relative transfer functions and coherence (view Measurement > Transfer functions).
%   info = tim.plots.transferFunctions(ax3, res)
%   info = tim.plots.transferFunctions(ax3, res, opts)
%   info = tim.plots.transferFunctions(ax3, [])           empty view
%
%   ax3 = 1 x 3 axes or uiaxes (top to bottom), created by the caller:
%     1) |H_m| [dB], H_m = p_m / p_ref: calibrated pressure at the tube port
%        M_m relative to the reference channel (res.Hposition)
%     2) phase of H_m [°]: unwrapped (swept sine, noise); stepped sine:
%        wrapped to ±180° and drawn as markers (a coarse frequency grid
%        cannot be unwrapped reliably)
%     3) coherence of every channel with the reference channel, dashed line
%        at the coherence limit (the reference channel itself is 1 by
%        definition and not drawn)
%   Every curve of a port M_m has the colour of the DAQ channel in that
%   port (res.channelOfPosition(m)), legend 'M1 (ch1)'. Stepped sine:
%   markers at the step frequencies.
%
%   opts (all optional): .band [fMin fMax] (default: band of the analysis,
%   else [120 4500]), .simulation, .emptyText, .coherenceMin and
%   .snrMin_dB (default: limits of the analysis, else 0.98 and 20 dB),
%   .stepped (default from res.kind).
%   info: .summary  Port | Channel | Median coherence | Min SNR [dB] | Bins meeting limits [%]
%         .note     explanation for the header of the view
%         .lines    1 x 4 handles of the |H| curves (M1..M4)
%         .axes     the axes

if nargin < 3 || isempty(opts), opts = struct(); end
hasRes = ~isempty(res) && isstruct(res) && isfield(res, 'Hposition') && ~isempty(res.Hposition);
o = defaults(opts, res, hasRes);
P = tim.gui.palette();
ax = ax(:).';
for i = 1:numel(ax)
    legend(ax(i), 'off');
    cla(ax(i)); hold(ax(i), 'on');
    ax(i).XScale = 'log';                         % before style: a log scale switches minor ticks on
    tim.plots.style(ax(i));
    title(ax(i), '');
    xlabel(ax(i), '');
end
ylabel(ax(1), '|H| [dB]');
ylabel(ax(2), 'Phase [\circ]');
ylabel(ax(3), 'Coherence [–]');
xlabel(ax(3), 'Frequency [Hz]');
info = struct('summary', [], 'note', '', 'lines', gobjects(0), 'axes', ax);

if ~hasRes
    limitLine(ax(3), o.coherenceMin);
    for i = 1:3, hold(ax(i), 'off'); end
    tim.plots.fitAxes(ax(1), 'XRange', o.band, 'YRange', [-10 10], 'YSteps', [1 2 5]);
    tim.plots.fitAxes(ax(2), 'XRange', o.band, 'YRange', [-180 180], 'YStep', 90);
    tim.plots.fitAxes(ax(3), 'XRange', o.band, 'YRange', [o.coherenceMin - 0.03 1], 'MaxTicks', 5, 'MinTicks', 3);
    shareX(ax);
    title(ax(1), blankTitle(o.simulation));
    msg = 'No processed measurement yet';
    if ~isempty(o.emptyText), msg = o.emptyText; end
    tim.plots.emptyState(ax(1), msg);
    info.summary = summaryTable([], [], [], [], [], o);
    return
end

% ---- data (rows = frequencies of the analysis, columns = ports M1..M4)
f = res.spectra.f(:);
H = res.Hposition;
nP = size(H, 2);
chP = 1:nP;
if isfield(res, 'channelOfPosition') && numel(res.channelOfPosition) == nP, chP = res.channelOfPosition; end
refCh = 1; if isfield(res.spectra, 'refChannel'), refCh = res.spectra.refChannel; end
coh = nan(numel(f), nP); snr = nan(numel(f), nP);
for m = 1:nP
    coh(:, m) = res.spectra.coherence(:, chP(m));
    if isfield(res.spectra, 'snr_dB'), snr(:, m) = res.spectra.snr_dB(:, chP(m)); end
end
isRef = chP == refCh;

hMag = gobjects(1, nP);
for m = 1:nP
    col = P.ch(min(max(chP(m), 1), size(P.ch, 1)), :);
    mag = 20 * log10(abs(H(:, m)));
    ph = angle(H(:, m));
    if o.stepped
        mk = {'Marker', 'o', 'MarkerSize', 5, 'MarkerFaceColor', col, 'MarkerEdgeColor', col};
        hMag(m) = plot(ax(1), f, mag, '-', 'Color', col, 'LineWidth', 0.9, mk{:});
        plot(ax(2), f, rad2deg(ph), 'LineStyle', 'none', 'Color', col, mk{:});
        if ~isRef(m), plot(ax(3), f, coh(:, m), '-', 'Color', col, 'LineWidth', 0.9, mk{:}); end
    else
        hMag(m) = plot(ax(1), f, mag, '-', 'Color', col, 'LineWidth', 1.2);
        plot(ax(2), f, rad2deg(unwrapFinite(ph)), '-', 'Color', col, 'LineWidth', 1.2);
        if ~isRef(m), plot(ax(3), f, coh(:, m), '-', 'Color', col, 'LineWidth', 1.1); end
    end
end
limitLine(ax(3), o.coherenceMin);
for i = 1:3, hold(ax(i), 'off'); end

% ---- legend, limits
names = arrayfun(@(m) sprintf('M%d (ch%d)', m, chP(m)), 1:nP, 'UniformOutput', false);
fx = f(isfinite(f) & f > 0);
xr = {'XRange', o.band, 'XInclude', [min(fx) max(fx)]};
y1 = 20 * log10(abs(H(:))); y1 = y1(isfinite(y1));
top = [];                                           % headroom for the legend strip (no curve below it)
if ~isempty(y1), top = max(y1) + 0.3 * max(max(y1) - min(y1), 1); end
tim.plots.fitAxes(ax(1), xr{:}, 'YSteps', [1 2 5], 'YInclude', top, 'MaxTicks', 7);
if o.stepped
    tim.plots.fitAxes(ax(2), xr{:}, 'YRange', [-180 180], 'YStep', 90);
else
    tim.plots.fitAxes(ax(2), xr{:}, 'YSteps', [45 90 180 360 720 1440 2880], 'YMantissa', false, 'MaxTicks', 7);
end
c = coh(:, ~isRef); c = c(isfinite(c));
lo = o.coherenceMin - 0.03;
if ~isempty(c) && min(c) < lo
    lo = max(0, floor(min(c) * 10) / 10);           % low coherence: show it, do not clip
end
tim.plots.fitAxes(ax(3), xr{:}, 'YRange', [lo 1], 'MaxTicks', 5, 'MinTicks', 3);
% one legend strip in the headroom of the top axes: covers no curve, keeps the x extent of all axes
lg = tim.plots.legend(ax(1), hMag, names, 'north');
lg.Orientation = 'horizontal';
if legendTooWide(lg, ax(1))                          % narrow axes: two rows, more headroom
    lg.NumColumns = 2;
    if ~isempty(y1)
        tim.plots.fitAxes(ax(1), 'Axis', 'y', 'YSteps', [1 2 5], 'MaxTicks', 7, ...
            'YInclude', max(y1) + 0.7 * max(max(y1) - min(y1), 1));
    end
end
shareX(ax);
title(ax(1), tim.plots.dataTitle(res, struct('simulation', o.simulation)));

% ---- note and summary
refPort = find(isRef, 1);
if isempty(refPort), refTxt = sprintf('ch%d', refCh); else, refTxt = sprintf('ch%d in M%d', refCh, refPort); end
calTxt = 'calibrated';
if isfield(res, 'calibration') && isfield(res.calibration, 'version') && strcmp(res.calibration.version, 'none')
    calTxt = 'NOT calibrated';
end
info.note = sprintf('H_m = p_m / p_ref (%s), reference %s. Phase %s.', calTxt, refTxt, ...
    ternary(o.stepped, 'wrapped to ±180° (stepped sine)', 'unwrapped'));
miss = any(~isfinite(H), 2);
if any(miss)                                        % no data, or no calibration there (no extrapolation)
    noData = miss;                                  % H of the raw spectra undefined too: no data (e.g. a
    if isfield(res.spectra, 'H') && size(res.spectra.H, 1) == numel(f)   % stepped-sine step without a value)
        noData = miss & any(~isfinite(res.spectra.H), 2);
    end
    noCal = miss & ~noData & strcmp(calTxt, 'calibrated');
    noData = miss & ~noCal;
    why = {};
    if any(noData), why{end + 1} = 'no data'; end
    if any(noCal), why{end + 1} = 'outside the calibrated frequency range'; end
    if numel(why) == 2
        why = {sprintf('%d no data, %d outside the calibrated frequency range', nnz(noData), nnz(noCal))};
    end
    info.note = sprintf('%s H undefined at %d of %d frequencies (%s).', info.note, nnz(miss), numel(f), why{1});
end
info.lines = hMag;
info.summary = summaryTable(f, coh, snr, chP, isRef, o);
end

% ---------------------------------------------------------------------------
function o = defaults(opts, res, hasRes)
o = struct('band', [120 4500], 'simulation', false, 'emptyText', '', 'coherenceMin', 0.98, ...
    'snrMin_dB', 20, 'stepped', []);
if hasRes && isfield(res, 'analysis') && isfield(res.analysis, 'options')   % limits of the analysis
    ao = res.analysis.options;
    if isfield(ao, 'coherenceMin'), o.coherenceMin = ao.coherenceMin; end
    if isfield(ao, 'snrMin_dB'), o.snrMin_dB = ao.snrMin_dB; end
    if isfield(ao, 'fRange') && numel(ao.fRange) == 2, o.band = ao.fRange; end
end
fn = fieldnames(opts);
for i = 1:numel(fn)
    if ~isempty(opts.(fn{i})) || strcmp(fn{i}, 'emptyText'), o.(fn{i}) = opts.(fn{i}); end
end
if isempty(o.stepped)
    o.stepped = hasRes && isfield(res, 'kind') && strcmp(res.kind, 'stepped');
end
end

function h = limitLine(ax, cmin)
% dashed limit line, labelled on the line (below it, left: where valid data never are)
h = yline(ax, cmin, '--', sprintf('Limit %.2f', cmin), 'Color', [0.45 0.45 0.45], 'LineWidth', 0.9, ...
    'LabelHorizontalAlignment', 'left', 'LabelVerticalAlignment', 'bottom', 'FontSize', ax.FontSize - 2, ...
    'Tag', 'timCoherenceLimit');
end

function tf = legendTooWide(lg, ax)
% one-row legend wider than the plot box (pixels)?
tf = false;
try
    u = lg.Units; lg.Units = 'pixels'; w = lg.Position(3); lg.Units = u;
    p = getpixelposition(ax);
    tf = w > 0.95 * p(3);
catch
end
end

function shareX(ax)
% one frequency axis: tick labels on the bottom axes only
for i = 1:numel(ax) - 1
    ax(i).XTickLabel = {};
    ax(i).XAxis.TickLabelColor = 'w';             % also after a zoom (fitAxes then uses auto labels)
end
ax(end).XAxis.TickLabelColor = ax(end).XColor;
if numel(ax) > 1, linkaxes(ax, 'x'); end
end

function p = unwrapFinite(p)
% unwrap the finite part (NaN would stop unwrap from working)
k = isfinite(p);
p(k) = unwrap(p(k));
end

function S = summaryTable(f, coh, snr, chP, isRef, o)
cols = {'Port', 'Channel', 'Median coherence', 'Min SNR [dB]', 'Lines meeting limits [%]'};
note = sprintf('In the analysis band %g–%g Hz; limits coherence ≥ %.2f and SNR ≥ %g dB (validity masks).', ...
    o.band(1), o.band(2), o.coherenceMin, o.snrMin_dB);
if isempty(f)
    D = [arrayfun(@(m) sprintf('M%d', m), (1:4).', 'UniformOutput', false), repmat({'–'}, 4, 4)];
    S = struct('title', 'Signal quality', 'columns', {cols}, 'data', {D}, 'note', note);
    return
end
in = f >= o.band(1) & f <= o.band(2);
nP = size(coh, 2);
D = cell(nP, numel(cols));
for m = 1:nP
    c = coh(in, m); s = snr(in, m);
    okC = ~(c < o.coherenceMin);                     % same rule as the validity masks (NaN passes)
    okS = ~(s < o.snrMin_dB);
    if isRef(m)
        medC = 'reference'; okC = true(size(okC));
    else
        medC = num(median(c, 'omitnan'), '%.4f');
    end
    share = '–';
    if any(in), share = sprintf('%.1f', 100 * mean(okC & okS)); end
    D(m, :) = {sprintf('M%d', m), sprintf('ch%d', chP(m)), medC, num(min(s), '%.1f'), share};
end
S = struct('title', 'Signal quality', 'columns', {cols}, 'data', {D}, 'note', note);
end

function s = num(v, fmt)
if isempty(v) || ~isfinite(v), s = '–'; else, s = sprintf(fmt, v); end
end

function s = blankTitle(sim)
if sim, s = 'SIMULATION'; else, s = ' '; end
end

function s = ternary(c, a, b)
if c, s = a; else, s = b; end
end
