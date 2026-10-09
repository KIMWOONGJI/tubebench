function lg = legend(ax, h, names, loc)
%LEGEND House-style legend: inside the axes, light frame, no title.
%   lg = tim.plots.legend(ax, h, names)            Location 'best'
%   lg = tim.plots.legend(ax, h, names, 'northeast')
%   Pass explicit handles (h) so that grey "invalid" curves and helper lines
%   never get an entry.
if nargin < 4, loc = 'best'; end
lg = legend(ax, h, names, 'Location', loc, 'Box', 'on', 'EdgeColor', [0.85 0.85 0.87], ...
    'Color', [1 1 1], 'FontSize', ax.FontSize - 1, 'AutoUpdate', 'off');
lg.ItemTokenSize = [18 12];
end
