function g = roundGeometry(g)
%ROUNDGEOMETRY Snap the lengths / coordinates of cfg.geometry to 1 nm.
%
%   g = tim.app.roundGeometry(g)
%
%   Coordinates computed from distances carry binary floating-point residue
%   (0.075 + 0.041 = 0.11599999999999999, 1e3*(0.145 - 0.116) =
%   28.999999999999986). round(v*1e9)/1e9 is exactly the double the decimal
%   value parses to (0.116), so distances recomputed from the coordinates
%   and the JSON written by saveConfig stay clean. Change <= 0.5 nm.
%   NaN (= not provided), Inf and non-numeric fields (note) are unchanged.

for f = {'diameter', 'micPositions', 'spacingUp', 'spacingDown', 'xFront', 'xRear'}
    k = f{1};
    if isfield(g, k) && isnumeric(g.(k)) && isreal(g.(k))
        g.(k) = round(g.(k) * 1e9) / 1e9;
    end
end
end
