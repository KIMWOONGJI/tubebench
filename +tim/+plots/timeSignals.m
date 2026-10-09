function info = timeSignals(ax, meas, opts)
%TIMESIGNALS Time signals of the DAQ channels (view Measurement > Time signals).
%   info = tim.plots.timeSignals(ax4, meas)
%   info = tim.plots.timeSignals(ax4, meas, opts)
%   info = tim.plots.timeSignals(ax4, [], struct('mics', mics))   empty view (e.g. before a live run)
%
%   One axes per DAQ channel (ax4 = 1 x 4 axes or uiaxes, top to bottom,
%   created by the caller), shared time axis. Shown: sound pressure
%   p = voltage / sensitivity [Pa] of repetition 1; channel voltages in mV
%   when a sensitivity is missing. Column c of a record is DAQ channel c;
%   its port and sensitivity are those of the microphone with channel c. A
%   display high-pass at 20 Hz (2nd-order Butterworth applied forward and
%   backward: zero phase, -6 dB at 20 Hz) removes the slow CCLD / DC
%   settling drift; the raw data stay unchanged (stored in V). Long records
%   are drawn as a min / max envelope, so that every peak stays visible.
%
%   opts (all optional): .simulation (logical), .emptyText, .mics
%   (microphones used for the labels and the unit when meas is empty).
%   info: .summary  Channel | Port | Peak | Level [dB SPL] | Sensitivity | Source
%         .note     explanation for the header of the view
%         .lines    1 x C line handles, Tag 'timWave1'..'timWave4'
%         .axes     the axes (top to bottom)
%         .unit     'Pa' or 'mV'
%         .scale    1 x C factors: displayed value = volts .* scale
%   Live view (GUI): set(info.lines(c), 'XData', t, 'YData', v(:, c) * info.scale(c))
%   and then tim.plots.fitAxes(info.axes(c)).

if nargin < 3 || isempty(opts), opts = struct(); end
P = tim.gui.palette();
ax = ax(:).';
nA = numel(ax);
hasData = ~isempty(meas) && isstruct(meas) && isfield(meas, 'records') && ~isempty(meas.records);
mics = [];
if hasData && isfield(meas, 'mics'), mics = meas.mics;
elseif isfield(opts, 'mics'), mics = opts.mics;
end
[scale, unit] = displayScale(mics, nA);
[ch, port] = channelPorts(mics, nA);
sim = isfield(opts, 'simulation') && opts.simulation;

% ---- data (repetition 1, display filter only)
t = []; y = []; tt = []; yy = [];
if hasData
    x = double(meas.records{1});
    x = x - mean(x, 1);
    fs = meas.fs;
    if size(x, 1) > 12
        [b, a] = butter(2, 20 / (fs / 2), 'high');
        x = filtfilt(b, a, x);
    end
    y = x(:, 1:min(nA, size(x, 2))) .* scale(1:min(nA, size(x, 2)));
    t = (0:size(y, 1) - 1).' / fs;
    [tt, yy] = envelope(t, y, 4000);
end

lines = gobjects(1, nA);
for c = 1:nA
    a = ax(c);
    legend(a, 'off');
    cla(a); hold(a, 'on');
    tim.plots.style(a);
    if hasData && c <= size(y, 2)
        lines(c) = plot(a, tt, yy(:, c), '-', 'Color', P.ch(ch(c), :), 'LineWidth', 0.8, ...
            'Tag', sprintf('timWave%d', c));
    else
        lines(c) = plot(a, NaN, NaN, '-', 'Color', P.ch(ch(c), :), 'LineWidth', 0.8, ...
            'Tag', sprintf('timWave%d', c));
    end
    hold(a, 'off');
    ylabel(a, sprintf('%s [%s]', channelName(ch(c), port(c)), unit));
    title(a, '');
    if c == nA
        xlabel(a, 'Time [s]');
        a.XAxis.TickLabelColor = a.XColor;
    else
        xlabel(a, '');
    end
    % limits: time = whole record, pressure symmetric around zero
    if hasData && c <= size(y, 2)
        pk = max(abs(y(:, c)));
        if ~(isfinite(pk) && pk > 0), pk = defaultPeak(unit); end
        tim.plots.fitAxes(a, 'Axis', 'x', 'XRange', [0 t(end)]);
    else
        pk = defaultPeak(unit);
        tim.plots.fitAxes(a, 'Axis', 'x', 'XRange', [0 1]);
    end
    tim.plots.fitAxes(a, 'Axis', 'y', 'YRange', [-pk pk], 'MaxTicks', 5, 'MinTicks', 3);
    if c < nA                                       % shared time axis: labels on the bottom axes only
        a.XTickLabel = {};
        a.XAxis.TickLabelColor = 'w';               % also after a zoom (fitAxes then uses auto labels)
    end
end
if nA > 1, linkaxes(ax, 'x'); end
if hasData
    title(ax(1), tim.plots.dataTitle(meas, struct('simulation', sim)));
else
    title(ax(1), blankTitle(sim));
    msg = 'No measurement yet';
    if isfield(opts, 'emptyText') && ~isempty(opts.emptyText), msg = opts.emptyText; end
    tim.plots.emptyState(ax(1), msg);
end

% ---- summary and note
info = struct();
info.summary = summaryTable(y, ch, port, unit, mics, scale, hasData, nA);
if hasData
    nRep = numel(meas.records);
    if strcmp(unit, 'Pa')
        txt = 'Sound pressure p = voltage / sensitivity';
    else
        txt = 'Channel voltages in mV (no valid sensitivity for every channel)';
    end
    info.note = sprintf('%s; repetition 1 of %d; display high-pass 20 Hz (raw data unchanged, stored in V).', ...
        txt, nRep);
else
    info.note = '';
end
info.lines = lines;
info.axes = ax;
info.unit = unit;
info.scale = scale;
end

% ---------------------------------------------------------------------------
function k = micIndex(mics, n)
% column c of a record = DAQ channel c (as in tim.app.processMeasurement);
% k(c) = index of the microphone on that channel (mics(k).channel == c)
k = 1:n;
if isempty(mics) || ~isfield(mics, 'channel'), return; end
chs = [mics.channel];
for c = 1:n
    i = find(chs == c, 1);
    if ~isempty(i), k(c) = i; end
end
end

function [scale, unit] = displayScale(mics, n)
% volts -> Pa with the resolved sensitivities, else volts -> mV
scale = 1e3 * ones(1, n); unit = 'mV';
if isempty(mics)
    scale = nan(1, n); unit = 'Pa';              % empty view: Pa expected, factors unknown
    return
end
if ~isfield(mics, 'sensitivity_VperPa') || numel(mics) < n, return; end
s = [mics.sensitivity_VperPa];
s = s(micIndex(mics, n));
if all(isfinite(s) & s > 0)
    scale = 1 ./ s; unit = 'Pa';
end
end

function [ch, port] = channelPorts(mics, n)
% DAQ channel of column c (= c) and its tube port (position of the microphone on it)
ch = 1:n; port = nan(1, n);
if isempty(mics) || ~isfield(mics, 'position'), return; end
k = micIndex(mics, n);
for c = 1:n
    if k(c) <= numel(mics) && ~isempty(mics(k(c)).position), port(c) = mics(k(c)).position; end
end
end

function s = channelName(ch, port)
if isfinite(port), s = sprintf('ch%d (M%d)', ch, port); else, s = sprintf('ch%d', ch); end
end

function pk = defaultPeak(unit)
if strcmp(unit, 'Pa'), pk = 1; else, pk = 10; end
end

function s = blankTitle(sim)
% keeps the space of the title (no layout jump when data arrive)
if sim, s = 'SIMULATION'; else, s = ' '; end
end

function [tt, yy] = envelope(t, y, nMax)
% min / max per bucket for long records (keeps every peak, ~2*nMax points)
N = size(y, 1);
if N <= 2 * nMax, tt = t; yy = y; return; end
L = ceil(N / nMax);
nb = floor(N / L);
C = size(y, 2);
yb = reshape(y(1:nb * L, :), L, nb, C);
[ymin, imin] = min(yb, [], 1); [ymax, imax] = max(yb, [], 1);
first = imin <= imax;                              % keep the time order inside a bucket
lo = reshape(ymin, nb, C); hi = reshape(ymax, nb, C); f1 = reshape(first, nb, C);
yy = zeros(2 * nb, C);
yy(1:2:end, :) = lo .* f1 + hi .* ~f1;
yy(2:2:end, :) = hi .* f1 + lo .* ~f1;
tb = t(1:L:nb * L);
tt = reshape([tb.'; tb.' + (L - 1) / 2 * (t(2) - t(1))], [], 1);
if nb * L < N                                       % remainder: drawn as is
    tt = [tt; t(nb * L + 1:end)];
    yy = [yy; y(nb * L + 1:end, :)];
end
end

function S = summaryTable(y, ch, port, unit, mics, scale, hasData, n)
cols = {'Channel', 'Port', sprintf('Peak [%s]', unit), 'Level [dB SPL]', 'Sensitivity [mV/Pa]', 'Source'};
D = repmat({'–'}, n, numel(cols));
k = micIndex(mics, n);
for c = 1:n
    D{c, 1} = sprintf('ch%d', ch(c));
    if isfinite(port(c)), D{c, 2} = sprintf('M%d', port(c)); end
    if strcmp(unit, 'Pa') && ~isempty(mics) && k(c) <= numel(mics)
        D{c, 5} = sprintf('%.2f', 1e3 / scale(c));
        if isfield(mics, 'sensitivitySource') && ~isempty(mics(k(c)).sensitivitySource)
            D{c, 6} = sourceName(mics(k(c)).sensitivitySource);
        end
    end
    if hasData && c <= size(y, 2)
        D{c, 3} = sprintf('%.3g', max(abs(y(:, c))));
        if strcmp(unit, 'Pa')
            D{c, 4} = sprintf('%.1f', 20 * log10(sqrt(mean(y(:, c).^2)) / 2e-5));
        end
    end
end
note = '';
if hasData
    note = 'Level: rms of the whole displayed record (repetition 1, > 20 Hz), re 20 µPa.';
    if ~strcmp(unit, 'Pa'), note = 'No valid sensitivity for every channel: voltages in mV, no SPL.'; end
end
S = struct('title', 'Channels', 'columns', {cols}, 'data', {D}, 'note', note);
end

function s = sourceName(src)
switch lower(char(src))
    case 'teds', s = 'TEDS';
    case 'certificate', s = 'Certificate';
    case 'nominal', s = 'Nominal';
    otherwise, s = char(src);
end
end
