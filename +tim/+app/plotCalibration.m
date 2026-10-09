function fig = plotCalibration(cal, opts)
%PLOTCALIBRATION Figure of a complex channel calibration C_k = c_k / c_ref.
%   fig = tim.app.plotCalibration(cal)
%   fig = tim.app.plotCalibration(cal, struct('Visible', 'off'))
%   Two stacked axes drawn by the same view as the GUI (tim.plots.calibration):
%   |C_k| [dB] and the phase of C_k [deg], colour of channel k, grey =
%   invalid frequency lines. Below the axes a footnote repeats the summary of
%   the view (valid lines, ranges, remounting repeatability per channel) and the
%   empty-tube check (Test E), so that a saved figure is self-contained.
%   cal = [] gives the empty view. Other opts fields (band, simulation,
%   emptyText) are passed to the view.
if nargin < 1, cal = []; end
if nargin < 2 || isempty(opts), opts = struct(); end
vis = 'on'; if isfield(opts, 'Visible'), vis = opts.Visible; end
if isfield(opts, 'Visible'), opts = rmfield(opts, 'Visible'); end
W = 960; H = 680;                                  % px; the top edge stays where MATLAB puts figures
pos = get(groot, 'DefaultFigurePosition');
fig = figure('Visible', vis, 'Name', 'Calibration', 'Color', 'w', ...
    'Position', [pos(1), max(40, pos(2) + pos(4) - H), W, H]);
P = tim.gui.palette();
tl = tiledlayout(fig, 2, 1, 'TileSpacing', 'compact', 'Padding', 'compact');
ax = [nexttile(tl), nexttile(tl)];
info = tim.plots.calibration(ax, cal, opts);
if isempty(cal), return; end

% footnote: one line per channel + the empty-tube check (Test E)
deg = char(176); none = char(8211);
d = info.summary.data;
lines = cell(size(d, 1), 1);
for i = 1:size(d, 1)
    rep = 'not measured';
    if ~strcmp(d{i, 5}, none), rep = [strrep(d{i, 5}, ' / ', ' dB / ') deg]; end
    if strcmp(d{i, 3}, none)                       % no valid line (or not calibrated)
        lines{i} = sprintf('%s:   valid lines %s %% – no valid calibration,   remounting repeatability %s', ...
            d{i, 1}, d{i, 2}, rep);
    else
        lines{i} = sprintf('%s:   valid lines %s %%,   |C| %s dB,   phase %s%s,   remounting repeatability %s', ...
            d{i, 1}, d{i, 2}, d{i, 3}, d{i, 4}, deg, rep);
    end
end
lines = [lines; strtrim(strsplit(info.note, '  |  ')).'];   % Test E, channels without calibration
h = (numel(lines) * 15 + 18) / H;                  % 9 pt lines, normalized height
tl.Units = 'normalized'; tl.OuterPosition = [0 h 1 1 - h];
annotation(fig, 'textbox', [0.012 0.006 0.976 h - 0.006], 'String', lines, 'EdgeColor', 'none', ...
    'Interpreter', 'none', 'FontSize', 9, 'Color', P.ui.muted, 'VerticalAlignment', 'bottom', ...
    'HorizontalAlignment', 'left', 'FitBoxToText', 'off', 'Margin', 2, 'Tag', 'calFootnote');
end
