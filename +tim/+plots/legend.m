function lg = legend(ax, h, names, loc, nCol)
%LEGEND House-style legend: light frame, no title.
%   lg = tim.plots.legend(ax, h, names)            inside the axes, Location 'best'
%   lg = tim.plots.legend(ax, h, names, 'northeast')
%   lg = tim.plots.legend(ax, h, names, 'northoutside', nCol)   above the plot
%       area in nCol columns (default: up to 4) without a frame, so that it
%       never covers the data (Spectrum, 1.6.1)
%   Pass explicit handles (h) so that grey "invalid" curves and helper lines
%   never get an entry.
if nargin < 4, loc = 'best'; end
lg = legend(ax, h, names, 'Location', loc, 'Box', 'on', 'EdgeColor', [0.85 0.85 0.87], ...
    'Color', [1 1 1], 'FontSize', ax.FontSize - 1, 'AutoUpdate', 'off');
lg.ItemTokenSize = [18 12];
if endsWith(loc, 'outside') && (startsWith(loc, 'north') || startsWith(loc, 'south'))
    if nargin < 5 || isempty(nCol), nCol = min(4, numel(names)); end
    lg.NumColumns = max(1, nCol);
    lg.Box = 'off';
end
end
