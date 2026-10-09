function style(ax, opts)
%STYLE House style of every 2-D plot (GUI views and saved figures).
%   tim.plots.style(ax)
%   tim.plots.style(ax, 'FontSize', 10)
%   Outward ticks, no box (open top / right), light major grid, no minor
%   ticks, normal-weight titles, dark grey axes. The limits are set by
%   tim.plots.fitAxes (half a tick interval beyond the outermost ticks).
arguments
    ax
    opts.FontSize double = 11
end
c = [0.20 0.20 0.22];
set(ax, 'TickDir', 'out', 'TickLength', [0.006 0.006], 'Box', 'off', 'Layer', 'top', ...
    'LineWidth', 0.8, 'FontSize', opts.FontSize, 'XColor', c, 'YColor', c, ...
    'GridColor', [0.15 0.15 0.15], 'GridAlpha', 0.13, 'XGrid', 'on', 'YGrid', 'on', ...
    'XMinorTick', 'off', 'YMinorTick', 'off', 'XMinorGrid', 'off', 'YMinorGrid', 'off', ...
    'TitleFontWeight', 'normal', 'TitleFontSizeMultiplier', 1.1, 'LabelFontSizeMultiplier', 1, ...
    'Color', 'w');
end
