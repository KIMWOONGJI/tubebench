function info = calibration(ax2, cal, opts)
%CALIBRATION View: calibration factors C_k = g_k / g_ref of the switching calibration.
%   info = tim.plots.calibration([axMag axPhase], cal)
%   info = tim.plots.calibration([axMag axPhase], cal, opts)
%   g_k is the complex gain of measurement chain k (microphone, cable, CCLD
%   supply, LAN-XI input). Two stacked axes (created by the caller: uiaxes
%   in the GUI, axes in a figure): top |C_k| [dB], bottom phase of C_k [°]
%   (unwrapped), one curve per channel k ~= ref in the colour of channel k,
%   masked by cal.valid(:,k) (grey = not valid), legend 'ch2 / ch1'. Title
%   (top axes only): tim.plots.dataTitle(cal). Calibrated transfer functions
%   are H_k = (Y_k / Y_ref) / C_k (tim.cal.applyCalibration).
%   cal = [] -> empty state: title, labels, default limits and the message
%   'No calibration loaded – use Load calibration… or Run switching calibration…'.
%
%   opts (struct, all optional)
%     band        [fMin fMax] x range of the empty state (default [120 4500])
%     simulation  true -> 'SIMULATION' in the title (also shown when the
%                 calibration itself was made in simulation mode)
%     emptyText   message of the empty state
%     stepped     markers instead of lines (default false: a calibration
%                 is always a swept-sine measurement)
%
%   info.summary     table: Channel | Valid [%] | Magnitude [dB] |
%                    Phase [°] | Remounting [dB / °]: min ... max of
%                    |C_k| and its phase over the valid frequency lines,
%                    remounting repeatability maxMag_dB / maxPhase_deg of
%                    cal.results{k}.repeatability ('–' = none / not measured)
%   info.note        header line: result of the empty-tube check (Test E,
%                    cal.meta.emptyCheck) and channels without calibration
%   info.status      'ok' (Test E passed) | 'warn' (check not performed /
%                    not recorded) | 'fail' (Test E failed or a channel not
%                    calibrated) | '' (no calibration)
%   info.emptyCheck  struct recorded / performed / passed / text
%   info.lines       coloured (valid) curves, 2 x nChannels: row 1 |C_k|,
%                    row 2 phase (Tags 'calMag<k>', 'calPhase<k>')
%   info.legend      legend of the top axes (empty without curves)

if nargin < 3 || isempty(opts), opts = struct(); end
if numel(ax2) ~= 2
    error('tim:plots:axes', 'tim.plots.calibration needs two axes: [magnitude phase].');
end
axM = ax2(1); axP = ax2(2);
P = tim.gui.palette();
sep = [' ' char(183) ' '];
ell = char(8230); none = char(8211); deg = char(176);
band = [120 4500];
if isfield(opts, 'band') && numel(opts.band) == 2 && all(isfinite(opts.band)), band = opts.band(:).'; end
stepped = isfield(opts, 'stepped') && ~isempty(opts.stepped) && opts.stepped;
sim = isfield(opts, 'simulation') && ~isempty(opts.simulation) && opts.simulation;

% ---- axes: cleared, house style, labels (also for the empty state)
for ax = [axM axP]
    if numel(ax.YAxis) > 1, cla(ax, 'reset'); end % axes used with yyaxis before (old GUI)
    cla(ax); legend(ax, 'off'); hold(ax, 'on');
    ax.XScale = 'log'; ax.YScale = 'linear';
    tim.plots.style(ax);
end
ylabel(axM, '|C_k| [dB]');
ylabel(axP, '\angleC_k [\circ]');
xlabel(axM, ''); xlabel(axP, 'Frequency [Hz]');
title(axP, '');
% y steps: dB in 1-2-5 steps; degrees in "round" steps (the mismatch of
% matched chains is a few degrees, so 45 / 90 deg steps would be too coarse)
magFit = {'YSteps', [1 2 5], 'MaxTicks', 7};
phFit = {'YSteps', [0.1 0.2 0.5 1 2 5 10 15 30 45 90 180], 'YMantissa', false, 'MaxTicks', 7};

% (no '|' in column names: a uitable splits a heading at '|')
cols = {'Channel', 'Valid [%]', 'Magnitude [dB]', ['Phase [' deg ']'], ['Remounting [dB / ' deg ']']};
info = struct('summary', struct('title', 'Calibration factors Ck = gk/gref', 'columns', {cols}, ...
    'data', {cell(0, numel(cols))}, 'note', ''), 'note', '', 'status', '', ...
    'emptyCheck', struct('recorded', false, 'performed', false, 'passed', false, 'text', ''), ...
    'lines', gobjects(2, 0), 'legend', gobjects(0));

% ---- empty state
if isempty(cal)
    t = ['Calibration' sep 'none loaded'];
    if sim, t = [t sep 'SIMULATION']; end
    title(axM, t);
    msg = ['No calibration loaded ' none ' use Load calibration' ell ' or Run switching calibration' ell];
    if isfield(opts, 'emptyText') && ~isempty(opts.emptyText), msg = opts.emptyText; end
    finish(axM, axP, band, [-1 1], [-10 10], magFit, phFit);
    tim.plots.emptyState(axM, msg);
    return
end

% ---- calibration curves
if isfield(cal, 'meta') && isstruct(cal.meta) && isfield(cal.meta, 'mode') && strcmp(cal.meta.mode, 'simulation')
    sim = true;                                    % a simulated calibration stays marked as such
end
title(axM, tim.plots.dataTitle(cal, struct('simulation', sim)));
f = cal.f(:); Nf = numel(f); ref = cal.refChannel;
V = false(size(cal.C));                            % no mask stored -> nothing is drawn as valid
if isfield(cal, 'valid') && isequal(size(cal.valid), size(cal.C)), V = logical(cal.valid); end
mopts = struct('stepped', stepped, 'lineWidth', 1.1);   % 1-2 Hz frequency lines: a thinner line stays calm
hLeg = gobjects(0); names = {}; rows = cell(0, numel(cols)); notes = {}; missing = []; noValid = [];
magR = []; phR = []; fIn = [];
for k = 1:size(cal.C, 2)
    if k == ref, continue; end
    c = cal.C(:, k); fin = isfinite(c);
    name = sprintf('ch%d / ch%d', k, ref);
    if ~any(fin)                                   % channel not calibrated (C = NaN)
        rows(end + 1, :) = {name, '0.0', none, none, none}; %#ok<AGROW>
        missing(end + 1) = k; %#ok<AGROW>
        continue
    end
    ok = V(:, k) & fin;
    if ~any(ok), noValid(end + 1) = k; end %#ok<AGROW>
    mag = 20 * log10(abs(c));
    ph = nan(Nf, 1); ph(fin) = rad2deg(unwrap(angle(c(fin))));   % continuous; C_k is near 0 deg at low f
    col = P.ch(1 + mod(k - 1, size(P.ch, 1)), :);
    hM = tim.plots.masked(axM, f, mag, ok, col, mopts);
    hP = tim.plots.masked(axP, f, ph, ok, col, mopts);
    hM.Tag = sprintf('calMag%d', k); hP.Tag = sprintf('calPhase%d', k);
    info.lines(:, end + 1) = [hM; hP];
    hLeg(end + 1) = hM; names{end + 1} = name; %#ok<AGROW>
    if ~any(ok), names{end} = [name ' (no valid frequency line)']; end
    magR = [magR; yRange(mag, ok)]; phR = [phR; yRange(ph, ok)]; %#ok<AGROW>
    fIn = [fIn; f(fin)]; %#ok<AGROW>
    % summary row (ranges over the valid frequency lines)
    rows(end + 1, :) = {name, sprintf('%.1f', 100 * nnz(ok) / Nf), ...
        rangeText(mag(ok), 2, ell, none), rangeText(ph(ok), 1, ell, none), ...
        repeatText(cal, k, none)}; %#ok<AGROW>
    if isfield(cal, 'results') && numel(cal.results) >= k && isstruct(cal.results{k}) && ...
            isfield(cal.results{k}, 'notes')
        for n = 1:numel(cal.results{k}.notes)
            notes{end + 1} = sprintf('ch%d: %s', k, cal.results{k}.notes{n}); %#ok<AGROW>
        end
    end
end

% ---- limits, legend, empty state without curves
if isempty(fIn)
    finish(axM, axP, band, [-1 1], [-10 10], magFit, phFit);
    tim.plots.emptyState(axM, 'The calibration holds no calibrated channel');
else
    % x: the calibrated range; y: see yRange
    finish(axM, axP, [min(fIn) max(fIn)], [min(magR(:)) max(magR(:))], [min(phR(:)) max(phR(:))], magFit, phFit);
    info.legend = tim.plots.legend(axM, hLeg, names);
end
hold(axM, 'off'); hold(axP, 'off');

% ---- summary, empty-tube check, header note
ec = emptyCheckInfo(cal);
info.emptyCheck = ec;
info.status = 'warn';
if ec.performed && ec.passed, info.status = 'ok'; elseif ec.performed, info.status = 'fail'; end
info.note = ec.text;
chList = @(ks) strjoin(arrayfun(@(k) sprintf('ch%d', k), ks, 'UniformOutput', false), ', ');
if ~isempty(missing) || ~isempty(noValid)       % every result needs all four channels calibrated
    info.status = 'fail';
    bad = {};
    if ~isempty(missing), bad{end + 1} = ['not calibrated: ' chList(missing)]; end
    if ~isempty(noValid), bad{end + 1} = ['no valid frequency line: ' chList(noValid)]; end
    bad = strjoin(bad, '; '); bad(1) = upper(bad(1));
    info.note = sprintf('%s  |  %s %s no measurement result can be valid.', info.note, bad, none);
end
info.summary.data = rows;
df = median(diff(f));
info.summary.note = strjoin([{sprintf(['%g%s%g Hz, df = %g Hz. Ranges over the valid frequency lines (coherence, ' ...
    'SNR, plausible mismatch). Remounting: configuration I measured twice, microphones reinserted; ' ...
    'max. change of H (about half of it in Ck); %s = not measured.'], min(f), none, max(f), df, none)}, notes], ' ');
end

% ---------------------------------------------------------------------------
function finish(axM, axP, xr, yM, yP, magFit, phFit)
% fitted limits (half a tick beyond the outermost ticks), 0 always inside,
% x linked (zoom in one axes zooms the other)
tim.plots.fitAxes(axM, 'XRange', xr, 'YRange', yM, 'YInclude', 0, magFit{:});
tim.plots.fitAxes(axP, 'XRange', xr, 'YRange', yP, 'YInclude', 0, phFit{:});
linkaxes([axM axP], 'x');
end

function r = yRange(y, ok)
% y range of one channel: its valid values; grey (not valid) frequency lines
% may run out of the axes (low-SNR lines scatter wildly and would squash the
% valid curves). A channel without any valid frequency line is still shown:
% 5 ... 95 % of its values (e.g. a reversed polarity at 180° or a wrong gain).
v = y(ok & isfinite(y));
if isempty(v)
    v = sort(y(isfinite(y))); n = numel(v);
    if n == 0, r = zeros(0, 2); return; end
    v = v(min(n, max(1, round([0.05 0.95] * n))));
end
r = [min(v) max(v)];
end

function s = rangeText(v, nd, ell, none)
% 'min ... max' with nd decimals (no '-0.00')
if isempty(v), s = none; return; end
x = round([min(v) max(v)] * 10^nd) / 10^nd;
x(x == 0) = 0;
fmt = sprintf('%%.%df', nd);
s = sprintf([fmt ' ' ell ' ' fmt], x(1), x(2));
end

function s = repeatText(cal, k, none)
% maxMag_dB / maxPhase_deg of results{k}.repeatability (configuration I repeated)
s = none;
if ~isfield(cal, 'results') || numel(cal.results) < k || ~isstruct(cal.results{k}), return; end
r = cal.results{k};
if ~isfield(r, 'repeatability') || ~isstruct(r.repeatability) || isempty(r.repeatability), return; end
s = sprintf('%.2f / %.2f', r.repeatability.maxMag_dB, r.repeatability.maxPhase_deg);
end

function ec = emptyCheckInfo(cal)
% result of the empty-tube check (Test E); missing in files made before it existed
ec = struct('recorded', false, 'performed', false, 'passed', false, 'text', '');
if ~(isfield(cal, 'meta') && isstruct(cal.meta) && isfield(cal.meta, 'emptyCheck') && isstruct(cal.meta.emptyCheck))
    ec.text = 'Empty-tube check (Test E): not recorded in this calibration file';
    return
end
e = cal.meta.emptyCheck;
ec.recorded = true;
if isfield(e, 'performed') && ~isempty(e.performed), ec.performed = logical(e.performed); end
if isfield(e, 'passed') && ~isempty(e.passed), ec.passed = ec.performed && logical(e.passed); end
t = '';
if isfield(e, 'text'), t = char(e.text); end
if isempty(t)
    if ~ec.performed, t = 'not performed'; elseif ec.passed, t = 'passed'; else, t = 'failed'; end
end
if startsWith(t, 'Test E')
    ec.text = t;
elseif startsWith(t, {'not ', 'stopped', 'aborted'})       % 'aborted': files saved before 2026-10-09
    ec.text = ['Empty-tube check (Test E) ' t];
else
    ec.text = ['Empty-tube check (Test E): ' t];
end
end
