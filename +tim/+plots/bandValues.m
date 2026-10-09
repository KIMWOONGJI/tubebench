function [m, n, txt] = bandValues(f, y, ok, centres, fmt)
%BANDVALUES Mean of a quantity over the VALID bins of each octave band.
%   m = tim.plots.bandValues(f, y, ok)
%   [m, n, txt] = tim.plots.bandValues(f, y, ok, [125 250 500 1000 2000 4000], '%.2f')
%
%   Band b covers centres(b)/sqrt(2) <= f < centres(b)*sqrt(2) (exact
%   octave edges around the nominal centre; half-open, so a bin on an edge
%   is counted once). Only bins with ok true and a finite y are averaged;
%   nothing is averaged just because it is finite (ok = [] -> finite bins).
%
%   m    (nBands x 1) arithmetic mean, NaN when the band has no valid bin
%   n    (nBands x 1) number of valid bins used
%   txt  (nBands x 1) cellstr formatted with fmt (default '%.2f'), '–' when
%        there is no valid bin (summary tables of the result views)
%
%   The mean is taken of y as given: pass |tau|.^2 and convert afterwards
%   for an energy mean (band transmission loss), see tim.plots.transmissionLoss.
if nargin < 4 || isempty(centres), centres = [125 250 500 1000 2000 4000]; end
if nargin < 5 || isempty(fmt), fmt = '%.2f'; end
f = f(:); y = double(y(:));
if isempty(ok), ok = true(size(y)); end
ok = logical(ok(:)) & isfinite(y) & isfinite(f);
centres = centres(:);
m = nan(numel(centres), 1); n = zeros(numel(centres), 1);
for b = 1:numel(centres)
    in = ok & f >= centres(b) / sqrt(2) & f < centres(b) * sqrt(2);
    n(b) = nnz(in);
    if n(b) > 0, m(b) = mean(y(in)); end
end
if nargout > 2
    txt = cell(numel(centres), 1);
    for b = 1:numel(centres)
        if isnan(m(b)), txt{b} = char(8211); else, txt{b} = sprintf(fmt, m(b)); end
    end
end
end
