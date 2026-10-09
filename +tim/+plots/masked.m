function [hValid, hAll] = masked(ax, f, y, ok, colour, opts)
%MASKED Curve with its valid part in colour and the rest in light grey.
%   hValid = tim.plots.masked(ax, f, y, ok, colour)
%   hValid = tim.plots.masked(ax, f, y, ok, colour, struct('stepped', true, 'lineStyle', '--'))
%   The whole curve is drawn thin and grey underneath; the valid values
%   (ok true) are drawn on top in colour. Nothing is drawn as valid just
%   because it is finite. Stepped sine (opts.stepped): results exist only
%   at the step frequencies -> markers (valid: filled, colour; not valid:
%   hollow, darker grey, so that an invalid step stays visible on white).
%   Returns the coloured line (use it for the legend) and the grey one.
if nargin < 6, opts = struct(); end
stepped = isfield(opts, 'stepped') && opts.stepped;
ls = '-'; if isfield(opts, 'lineStyle'), ls = opts.lineStyle; end
lw = 1.5; if isfield(opts, 'lineWidth'), lw = opts.lineWidth; end
P = tim.gui.palette();
held = ishold(ax); hold(ax, 'on');
f = f(:); y = y(:); ok = logical(ok(:));
if stepped
    hAll = plot(ax, f, y, ls, 'Color', P.invalid, 'LineWidth', 0.6, 'Marker', 'o', 'MarkerSize', 5, ...
        'MarkerEdgeColor', P.invalidMarker, 'MarkerFaceColor', 'w');
else
    hAll = plot(ax, f, y, '-', 'Color', P.invalid, 'LineWidth', 0.8);
end
yv = y; yv(~ok) = NaN;
if stepped
    hValid = plot(ax, f, yv, ls, 'Color', colour, 'LineWidth', lw - 0.3, 'Marker', 'o', 'MarkerSize', 5, ...
        'MarkerEdgeColor', colour, 'MarkerFaceColor', colour);
else
    hValid = plot(ax, f, yv, ls, 'Color', colour, 'LineWidth', lw);
end
if ~held, hold(ax, 'off'); end
end
