function figs = plotResults(res, meas, opts)
%PLOTRESULTS Saved figures of a measurement: one figure per view, as in the GUI.
%   figs = tim.app.plotResults(res, meas)                      visible figures
%   figs = tim.app.plotResults(res, meas, struct('Visible', 'off'))
%
%   Every figure is drawn by the same view as the window (tim.plots.*), so a
%   saved figure shows what the GUI shows: a header (what is shown, a
%   one-line description and the note of the view), the axes of the view
%   (stacked, plot boxes aligned as in a tiledlayout) and the summary table
%   of the view on the right. A uitable cannot be printed or exported, so
%   the table is drawn with text objects (rules above and below the column
%   headings and below the last row, units in the last heading line, every
%   second row shaded). A footer names the software version that processed
%   the data.
%
%     field              header                        view (axes)
%     waveforms          Time signals                  tim.plots.timeSignals (4)
%     spectrum           Spectrum                      tim.plots.spectrum (1)
%     transfer           Transfer functions            tim.plots.transferFunctions (3)
%     reflection         Reflection and transmission   tim.plots.reflection (2, heights 2:1)
%     transmissionLoss   Transmission loss             tim.plots.transmissionLoss (1)
%     impedance          Transfer impedance            tim.plots.transferImpedance (2)
%     validity           Validity                      tim.plots.validity (1)
%
%   opts (all optional): .Visible ('on' | 'off'), .Size (figure size in px,
%   default [1200 700]), .simulation (default: true when meas.metadata
%   has a WARNING field, i.e. simulated data: 'SIMULATION' in the titles of
%   the views and a red 'SIMULATED DATA' mark in the header); every other
%   field (band, emptyText, ...) is passed to the views. res or meas may be
%   [] (the views show their empty state).
%   Each figure keeps the info of its view (getappdata(fig, 'timViewInfo'));
%   header, table and footer are arranged again when a visible figure is
%   resized. A view that fails does not stop the others (nor the saving of
%   the data): its figure shows the error and a warning is issued.
%   Font Arial instead of the default Helvetica: Helvetica is a PDF base
%   font that is not embedded and cannot encode τ, α, ρ, −, √ or ≥ in a
%   vector PDF (tim.app.exportFigures); on screen both look the same.

if nargin < 1, res = []; end
if nargin < 2, meas = []; end
if nargin < 3 || isempty(opts), opts = struct(); end
vis = 'on'; if isfield(opts, 'Visible'), vis = opts.Visible; end
sz = [1200 700]; if isfield(opts, 'Size') && numel(opts.Size) == 2, sz = double(opts.Size(:).'); end
vo = rmfield(opts, intersect(fieldnames(opts), {'Visible', 'Size'}));
if ~isfield(vo, 'simulation') || isempty(vo.simulation)
    vo.simulation = isstruct(meas) && isfield(meas, 'metadata') && isstruct(meas.metadata) && ...
        isfield(meas.metadata, 'WARNING');
end
vo.simulation = logical(vo.simulation);
foot = versionText(res);

% field, header title, description (TeX), axes heights, view (texts as in the GUI)
V = {
    'waveforms', 'Time signals', ['Recorded signal of every DAQ channel, with the tube port of its microphone ' ...
        'in brackets.'], [1 1 1 1], ...
        @(ax) tim.plots.timeSignals(ax, meas, vo)
    'spectrum', 'Spectrum', ['Power spectral density of the sound pressure (swept sine, noise, background ' ...
        'noise) or the level of every step (stepped sine). Dashed: analysis band.'], 1, ...
        @(ax) tim.plots.spectrum(ax, meas, res, vo)
    'transfer', 'Transfer functions', ['Calibrated transfer functions H = p(port) / p(reference) of the ' ...
        'four ports, their phase and the coherence of every channel.'], [1 1 1], ...
        @(ax) tim.plots.transferFunctions(ax, res, vo)
    'reflection', 'Reflection and transmission', ['Reflection coefficient R at the specimen front face, ' ...
        'transmission coefficient τ to the rear face and dissipation coefficient α_d = 1 − |R|² − |τ|². Grey: outside the valid range.'], ...
        [2 1], @(ax) tim.plots.reflection(ax, res, vo)
    'transmissionLoss', 'Transmission loss', ['Normal-incidence transmission loss TL = ' char(8722) ...
        '20 log_{10}|τ| (anechoic termination). Grey: outside the valid range.'], 1, ...
        @(ax) tim.plots.transmissionLoss(ax, res, vo)
    'impedance', 'Transfer impedance', ['Thin-element transfer impedance Z_t = (p_{front} ' char(8722) ...
        ' p_{rear}) / u, normalised by ρc (thin specimens: k·d << 1). Grey: outside the valid range.'], [1 1], ...
        @(ax) tim.plots.transferImpedance(ax, res, vo)
    'validity', 'Validity', ['Which frequency lines meet each criterion (geometry, coherence and SNR, ' ...
        'passivity, anechoic termination, thin-element velocity match).'], 1, ...
        @(ax) tim.plots.validity(ax, res, vo)
    };
figs = struct();
meter = newMeter();                                   % text sizes, shared by the figures
cleanup = onCleanup(@() delete(ancestor(meter, 'figure')));
for i = 1:size(V, 1)
    [fig, ax, ov] = newFigure(V{i, 2}, vis, sz, V{i, 4});
    fig.Tag = ['timSaved_' V{i, 1}];
    try
        info = V{i, 5}(ax);
    catch err                                       % the data are saved even if a figure fails
        warning('tim:plotResults:view', 'Figure ''%s'' could not be drawn: %s', V{i, 2}, err.message);
        tim.plots.emptyState(ax(1), ['Figure could not be drawn: ' err.message]);
        info = struct('summary', [], 'note', 'Figure could not be drawn - see the warning in the command window.');
    end
    setappdata(fig, 'timViewInfo', info);
    setappdata(fig, 'timSavedFrame', struct('title', V{i, 2}, 'description', V{i, 3}, ...
        'note', fieldText(info, 'note'), 'summary', fieldOr(info, 'summary', []), ...
        'simulation', vo.simulation, 'footer', foot, 'overlay', ov, 'axes', ax, 'heights', V{i, 4}));
    arrange(fig, meter);
    fig.SizeChangedFcn = @(f, ~) arrange(f);
    figs.(V{i, 1}) = fig;
end
end

function t = newMeter()
% text in a hidden, empty figure for measuring text sizes in px (the Extent
% of a text in a figure full of data is slow: that figure is updated first);
% the sizes are cached in t.UserData
f = figure('Visible', 'off', 'Units', 'pixels', 'Position', [0 0 1600 1000], 'IntegerHandle', 'off', ...
    'HandleVisibility', 'off', 'NumberTitle', 'off', 'Name', 'text meter', 'Tag', 'timTextMeter');
a = axes(f, 'Units', 'pixels', 'Position', [1 1 1600 1000], 'XLim', [0 1600], 'YLim', [0 1000], ...
    'Visible', 'off');
t = text(a, 0, 0, '', 'Interpreter', 'tex', 'FontName', 'Arial', ...
    'UserData', containers.Map('KeyType', 'char', 'ValueType', 'any'));
end

% ---------------------------------------------------------------------------
function [fig, ax, ov] = newFigure(name, vis, sz, heights)
% white figure, Arial everywhere (PDF), stacked axes (one per height entry,
% top to bottom), overlay axes in pixel coordinates for header / table / footer
font = 'Arial';
pos = get(groot, 'DefaultFigurePosition');            % px; the top edge stays where MATLAB puts figures
fig = figure('Visible', vis, 'Name', name, 'NumberTitle', 'off', 'Color', 'w', 'Units', 'pixels', ...
    'Position', [pos(1), max(40, pos(2) + pos(4) - sz(2)), sz], ...
    'DefaultAxesFontName', font, 'DefaultTextFontName', font, 'DefaultLegendFontName', font, ...
    'DefaultConstantLineFontName', font);
ax = gobjects(1, numel(heights));
for i = 1:numel(heights), ax(i) = axes(fig, 'Units', 'normalized'); end
% first guess: the narrowest plot area (widest table); arrange sets the final one
placeAxes(ax, heights, [6, 24, max(200, round(0.6 * sz(1)) - 30), max(150, sz(2) - 110)]);
% overlay: data units = pixels of the figure, transparent, never picked,
% hidden from gca / findobj. Visible 'on' without colour or ticks:
% exportgraphics crops to the visible axes and would cut off the header and
% the table of an invisible one
ov = axes(fig, 'Units', 'normalized', 'Position', [0 0 1 1], 'XLim', [0 sz(1)], 'YLim', [0 sz(2)], ...
    'Color', 'none', 'XColor', 'none', 'YColor', 'none', 'XTick', [], 'YTick', [], 'Box', 'off', ...
    'HitTest', 'off', 'PickableParts', 'none', 'HandleVisibility', 'off', 'Tag', 'timSavedOverlay');
ov.Toolbar = [];
disableDefaultInteractivity(ov);
end

function placeAxes(ax, heights, rect)
% stacked axes in rect = [x y w h] (px, labels included), as a tiledlayout
% ('compact') would place them: common left and right edges of the plot
% boxes (the widest tick labels decide), height shares as given, the space
% for the labels of every axes from its TightInset. Not a tiledlayout: when
% a tiledlayout does not fill its figure, exportgraphics (R2022b) lays the
% legends out about 20 % too narrow - their text runs out of the box.
n = numel(ax);
ti = zeros(n, 4);
for i = 1:n
    ax(i).Units = 'pixels'; ti(i, :) = ax(i).TightInset;
end
gap = 8;                                              % between a plot box and the labels above / below
x1 = rect(1) + max(ti(:, 1)) + 2;
x2 = rect(1) + rect(3) - max(ti(:, 3)) - 2;
free = rect(4) - ti(1, 4) - ti(n, 2) - sum(ti(1:n - 1, 2) + ti(2:n, 4)) - gap * (n - 1) - 4;
h = max(20, free * heights(:) / sum(heights));
y = rect(2) + rect(4) - ti(1, 4) - 2;
for i = 1:n
    y = y - h(i);
    ax(i).Position = [x1, y, max(40, x2 - x1), h(i)];
    if i < n, y = y - ti(i, 2) - gap - ti(i + 1, 4); end
end
for i = 1:n, ax(i).Units = 'normalized'; end
end

% ---------------------------------------------------------------------------
function arrange(fig, t)
% header (title, description, note, simulation mark), summary table on the
% right, footer; the axes get the rest (pixels of the current size). The
% table is made narrower (smaller font) when the axes title would run into
% it (Validity: the long row labels make the plot box narrow).
% t: measuring text (newMeter; a new one when not given, e.g. on a resize)
if ~isgraphics(fig), return; end
F = getappdata(fig, 'timSavedFrame');
if isempty(F) || ~isgraphics(F.overlay), return; end
if nargin < 2 || ~isgraphics(t)
    t = newMeter();
    cleanup = onCleanup(@() delete(ancestor(t, 'figure')));
end
ov = F.overlay;
pos = getpixelposition(fig);
W = pos(3); H = pos(4);
if W < 200 || H < 150, return; end                    % minimised / tiny window: keep the layout
delete(allchild(ov));
set(ov, 'Units', 'normalized', 'Position', [0 0 1 1], 'XLim', [0 W], 'YLim', [0 H]);
maxW = 0.4 * W;
for k = 1:3
    x0 = drawFrame(F, ov, t, W, H, maxW);
    if isinf(x0), break; end
    over = titleRight(F.axes(1), W) - (x0 - 8);
    if over <= 0, break; end
    % the title is centred on the plot box: it moves by half the width change
    maxW = max(150, (W - 18 - x0) - 2 * over - 4);
end
end

function r = titleRight(ax, W)
% right end of the axes title in figure pixels: right edge of the plot box
% + the part of the title beyond it
r = -Inf;
if ~isgraphics(ax) || isempty(ax.Title.String), return; end
u = ax.Title.Units;
ax.Title.Units = 'pixels'; ep = ax.Title.Extent;
ax.Title.Units = 'normalized'; en = ax.Title.Extent;
ax.Title.Units = u;
if en(3) <= 0, return; end
p = ax.Position * W;                                  % normalized -> px (x only)
r = p(1) + p(3) + (en(1) + en(3) - 1) * ep(3) / en(3);
end

function x0 = drawFrame(F, ov, t, W, H, maxW)
% draws header, footer and table; returns the left edge of the table (Inf: none)
P = tim.gui.palette();
delete(allchild(ov));
mx = 18; x1 = mx; x2 = W - mx;

% ---- header
y = H - 12;
hT = text(ov, x1, y, F.title, 'FontSize', 14, 'FontWeight', 'bold', 'Color', P.ui.text, ...
    'Interpreter', 'none', 'VerticalAlignment', 'top', 'Tag', 'timHeaderTitle');
if F.simulation
    text(ov, x2, y, 'SIMULATED DATA', 'FontSize', 10, 'FontWeight', 'bold', 'Color', P.fail, ...
        'Interpreter', 'none', 'HorizontalAlignment', 'right', 'VerticalAlignment', 'top', ...
        'Tag', 'timSimulationMark');
end
y = y - hT.Extent(4) - 2;
set(t, 'FontSize', 10, 'FontWeight', 'normal', 'Interpreter', 'tex');
hD = text(ov, x1, y, wrap(t, F.description, x2 - x1), 'FontSize', 10, 'Color', P.ui.muted, ...
    'Interpreter', 'tex', 'VerticalAlignment', 'top', 'Tag', 'timHeaderDescription');
y = y - hD.Extent(4) - 1;
if ~isempty(F.note)
    set(t, 'FontWeight', 'bold');
    hN = text(ov, x1, y, wrap(t, tex(F.note), x2 - x1), 'FontSize', 10, 'FontWeight', 'bold', ...
        'Color', [0.62 0.36 0.00], 'Interpreter', 'tex', 'VerticalAlignment', 'top', 'Tag', 'timHeaderNote');
    y = y - hN.Extent(4) - 1;
end
y = y - 5;
line(ov, [x1 x2], [y y], 'Color', [0.82 0.84 0.87], 'LineWidth', 0.75, 'Tag', 'timHeaderRule');

% ---- footer
yb = 6;
if ~isempty(F.footer)
    hF = text(ov, x2, yb, F.footer, 'FontSize', 8, 'Color', [0.55 0.57 0.60], 'Interpreter', 'none', ...
        'HorizontalAlignment', 'right', 'VerticalAlignment', 'bottom', 'Tag', 'timFooter');
    yb = yb + hF.Extent(4) + 2;
end

% ---- summary table on the right, axes on the left
x0 = drawSummary(ov, t, F.summary, x2, y - 12, yb, maxW);
xr = x0 - 16; if isinf(x0), xr = x2; end              % no table: the axes use the full width
if all(isgraphics(F.axes))
    placeAxes(F.axes, F.heights, [6, yb, max(100, xr - 6), max(100, y - 10 - yb)]);
end
end

% ---------------------------------------------------------------------------
function x0 = drawSummary(ov, t, S, xR, yTop, yBot, maxW)
% summary table of a view (struct title / columns / data / note) right-aligned
% at xR below yTop, at most maxW wide if the font allows; returns its left
% edge (Inf when there is no table)
x0 = Inf;
if ~isstruct(S) || ~isfield(S, 'columns') || isempty(S.columns), return; end
P = tim.gui.palette();
cols = cellfun(@char, cellstr(S.columns), 'UniformOutput', false);
D = {}; if isfield(S, 'data'), D = S.data; end
if isnumeric(D) || islogical(D), D = num2cell(D); end
D = cellfun(@cellText, D, 'UniformOutput', false);
if size(D, 2) ~= numel(cols), D = cell(0, numel(cols)); end
Dt = cellfun(@tex, D, 'UniformOutput', false);
ttl = ''; if isfield(S, 'title') && ~isempty(S.title), ttl = char(S.title); end
note = ''; if isfield(S, 'note') && ~isempty(S.note), note = tex(S.note); end
minW = min(250, maxW);
for fs = [9.5 9 8.5 8]                                % the largest font that fits
    L = tableLayout(t, cols, Dt, fs);
    set(t, 'FontSize', fs + 1.5, 'FontWeight', 'bold', 'Interpreter', 'none');
    [tw, th] = sizeOf(t, ttl);
    pw = max(L.width, min(max([L.width, tw, minW]), maxW));   % never narrower than the columns
    set(t, 'FontSize', fs - 0.5, 'FontWeight', 'normal', 'Interpreter', 'tex');
    nl = wrap(t, note, pw);
    [~, nh] = sizeOf(t, nl);
    if L.width <= maxW && th + 4 + L.height + 6 + nh <= yTop - yBot, break; end
end
x0 = xR - pw;
y = yTop;
if ~isempty(ttl)
    text(ov, x0, y, ttl, 'FontSize', fs + 1.5, 'FontWeight', 'bold', 'Color', P.ui.text, ...
        'Interpreter', 'none', 'VerticalAlignment', 'top', 'Tag', 'timSummaryTitle');
    y = y - th - 4;
end
nC = numel(cols); nR = size(D, 1);
gap = L.gap; if nC > 1, gap = gap + (pw - L.width) / (nC - 1); end    % the table spans the panel
xl = x0 + L.pad + [0, cumsum(L.w(1:end - 1) + gap)];                  % left edges of the columns
xa = xl; xa(L.right) = xl(L.right) + L.w(L.right);                    % anchor of each column
ha = repmat({'left'}, 1, nC); ha(L.right) = {'right'};
dark = [0.30 0.32 0.35];
line(ov, [x0 x0 + pw], [y y], 'Color', dark, 'LineWidth', 0.9, 'Tag', 'timSummaryRule');
y = y - 3;
for c = 1:nC
    text(ov, xa(c), y - L.hdrH, L.hdr{c}, 'FontSize', fs, 'Color', P.ui.text, 'Interpreter', 'tex', ...
        'HorizontalAlignment', ha{c}, 'VerticalAlignment', 'bottom', 'Tag', 'timSummaryHeading');
end
y = y - L.hdrH - 3;
line(ov, [x0 x0 + pw], [y y], 'Color', [0.62 0.64 0.67], 'LineWidth', 0.6, 'Tag', 'timSummaryRule');
for r = 2:2:nR                                        % shading of every second row (under the text)
    yr = y - [r, r, r - 1, r - 1] * L.rowH;
    patch(ov, [x0 x0 + pw x0 + pw x0], yr, [0.955 0.962 0.972], 'EdgeColor', 'none', 'HitTest', 'off');
end
for r = 1:nR
    yc = y - (r - 0.5) * L.rowH;
    for c = 1:nC
        col = P.ui.text;
        if strcmp(D{r, c}, char(8211)), col = [0.55 0.57 0.60]; end   % no value
        text(ov, xa(c), yc, Dt{r, c}, 'FontSize', fs, 'Color', col, 'Interpreter', 'tex', ...
            'HorizontalAlignment', ha{c}, 'VerticalAlignment', 'middle', 'Tag', 'timSummaryCell', ...
            'UserData', [r c]);
    end
end
y = y - nR * L.rowH;
line(ov, [x0 x0 + pw], [y y], 'Color', dark, 'LineWidth', 0.9, 'Tag', 'timSummaryRule');
if ~isempty(nl)
    text(ov, x0, y - 6, nl, 'FontSize', fs - 0.5, 'Color', P.ui.muted, 'Interpreter', 'tex', ...
        'VerticalAlignment', 'top', 'Tag', 'timSummaryNote');
end
end

function L = tableLayout(t, cols, Dt, fs)
% column widths, heading lines (name wrapped, unit in a last, muted line)
% and heights in px for the font size fs; Dt = cells as TeX
set(t, 'FontSize', fs, 'FontWeight', 'normal', 'Interpreter', 'tex');
nC = numel(cols);
L.gap = 14; L.pad = 4;
L.right = false(1, nC); L.w = zeros(1, nC); L.hdr = cell(1, nC);
nH = ones(1, nC);
muted = '\color[rgb]{0.40 0.42 0.45}';
for c = 1:nC
    dw = sizeOf(t, Dt(:, c));                        % widest cell (one multi-line measurement)
    L.right(c) = c > 1 && isNumericColumn(Dt(:, c));
    [name, unit] = splitUnit(cols{c});
    uw = sizeOf(t, tex(unit));
    target = max([dw, uw, 72]);
    for k = 1:10                                     % at most 3 heading lines (unit included)
        nl = wrap(t, tex(name), target);
        if numel(nl) + ~isempty(unit) <= 3, break; end
        target = target * 1.25;
    end
    if isempty(nl), nl = {''}; end
    L.w(c) = max([dw, uw, sizeOf(t, nl)]);
    if ~isempty(unit), nl{end + 1} = [muted tex(unit)]; end %#ok<AGROW>
    L.hdr{c} = nl(:);
    nH(c) = numel(nl);
end
[~, lineH] = sizeOf(t, 'Mg');
[~, L.hdrH] = sizeOf(t, repmat({'Mg'}, max(nH), 1));
L.rowH = ceil(lineH + 2);
L.width = sum(L.w) + L.gap * (nC - 1) + 2 * L.pad;
L.height = 3 + L.hdrH + 3 + size(Dt, 1) * L.rowH;
end

% ---------------------------------------------------------------------------
function lines = wrap(t, s, width)
% greedy word wrap of a TeX string to 'width' px with the font of the
% measuring text t; a single word longer than the width keeps its own line.
% No line starts with a dash, slash or '=', no line ends with '>' or '≥',
% no number is split from its unit.
lines = {};
if isempty(s), return; end
words = strsplit(s, ' ');
for k = numel(words):-1:2
    glue = any(strcmp(words{k}, {char(8211), char(8212), char(8722), '-', '/', char(8230), char(183), '='})) || ...
        any(strcmp(words{k - 1}, {'>', '<', char(8805), char(8804), '~', char(177)})) || ...
        (~isempty(regexp(words{k - 1}, '\d$', 'once')) && ~isempty(regexp(words{k}, ...
        '^(k?Hz|dB|mm|ms|s|Pa|mPa|mV|V|%)\W*$', 'once')));
    if glue, words{k - 1} = [words{k - 1} ' ' words{k}]; words(k) = []; end
end
ww = cellfun(@(x) sizeOf(t, x), words);              % every word measured once (cached)
sp = sizeOf(t, 'x x') - sizeOf(t, 'xx');             % width of a space
cur = words{1}; cw = ww(1);
for k = 2:numel(words)
    if cw + sp + ww(k) <= width - 2                   % sum of the words: no kerning between them
        cur = [cur ' ' words{k}]; cw = cw + sp + ww(k); %#ok<AGROW>
    else
        lines{end + 1} = cur; cur = words{k}; cw = ww(k); %#ok<AGROW>
    end
end
lines{end + 1} = cur;
lines = lines(:);
end

function [w, h] = sizeOf(t, s)
% width and height in px of a string (cellstr: widest line, all lines) at the
% current font of the measuring text t; cached in t.UserData (Extent is slow)
w = 0; h = 0;
if isempty(s), return; end
key = sprintf('%g|%s|%s|%s', t.FontSize, t.FontWeight, t.Interpreter, strjoin(cellstr(s), newline));
M = t.UserData;
if isKey(M, key)
    v = M(key); w = v(1); h = v(2);
    return
end
t.String = s;
e = t.Extent; w = e(3); h = e(4);
M(key) = [w h]; %#ok<NASGU>  (containers.Map is a handle: stored in t.UserData)
end

function s = tex(s)
% plain text of a view -> TeX: \ { } ^ escaped, X_word as a subscript (Z_t,
% R_term), the angle sign from the TeX symbol font (it is not in Arial)
s = char(s);
if isempty(s), return; end
s = regexprep(s, '([\\{}^])', '\\$1');
s = regexprep(s, '_(\w+)', '_{$1}');
s = strrep(s, char(8736), '{\angle}');
end

function [name, unit] = splitUnit(s)
% 'Level [dB SPL]' -> 'Level', '[dB SPL]'
tok = regexp(s, '^(.*\S)\s*(\[[^\[\]]*\])$', 'tokens', 'once');
if isempty(tok), name = s; unit = ''; else, name = tok{1}; unit = tok{2}; end
end

function tf = isNumericColumn(c)
% right-aligned when most cells with a value start with a number (or no cell
% has a value: a result column without a valid band)
c = c(~strcmp(c, char(8211)) & ~cellfun(@isempty, c));
tf = isempty(c) || mean(~cellfun(@isempty, regexp(c, ['^[-+' char(8722) ']?\d'], 'once'))) >= 0.5;
end

function s = cellText(v)
% a summary cell as text ('–' when there is no value)
if ischar(v), s = v;
elseif isstring(v), s = char(strjoin(v, ' '));
elseif islogical(v) && isscalar(v), if v, s = 'yes'; else, s = 'no'; end
elseif isnumeric(v) && isscalar(v) && isfinite(v)
    if v == round(v), s = sprintf('%d', v); else, s = sprintf('%.4g', v); end
else
    s = char(8211);
end
end

function s = fieldText(st, name)
s = '';
if isstruct(st) && isfield(st, name) && ~isempty(st.(name)), s = char(st.(name)); end
end

function v = fieldOr(st, name, default)
v = default;
if isstruct(st) && isfield(st, name), v = st.(name); end
end

function s = versionText(res)
% software that processed the data (the version stored in the result)
if isstruct(res) && isfield(res, 'softwareVersion') && ~isempty(res.softwareVersion)
    s = char(res.softwareVersion);
else
    try
        s = tim.app.softwareVersion();
    catch
        s = '';                                       % no footer
    end
end
end
