function h = emptyState(ax, msg)
%EMPTYSTATE Centred message in an axes that has no data (yet).
%   tim.plots.emptyState(ax, 'No measurement yet - press START')
%   tim.plots.emptyState(ax, '')      removes the message
%   The axes keep their title, labels, ticks and limits, so an empty view
%   already shows what it will display. Returns the text handle (Tag
%   'timEmptyState'); it is excluded from the axis limits.
delete(findobj(ax, 'Tag', 'timEmptyState'));
h = gobjects(0);
if nargin < 2 || isempty(msg), return; end
h = text(ax, 0.5, 0.5, msg, 'Units', 'normalized', 'HorizontalAlignment', 'center', ...
    'VerticalAlignment', 'middle', 'Color', [0.45 0.47 0.50], 'FontSize', 12, ...
    'Interpreter', 'none', 'Tag', 'timEmptyState', 'HitTest', 'off', 'Clipping', 'off');
end
