function [lines, names] = withOutside(ax, lines, names)
%WITHOUTSIDE Legend entries plus the diamonds of steps outside the calibration range.
%   [lines, names] = tim.plots.withOutside(ax, lines, names)
%   Appends one entry for the hollow diamonds that tim.plots.masked draws
%   (Tag 'timOutsideCalibration', 1.5.1) when the axes hold any.
ho = findobj(ax, 'Tag', 'timOutsideCalibration');
if ~isempty(ho)
    lines(end + 1) = ho(1); names{end + 1} = 'outside the calibration range (indicative)';
end
end
