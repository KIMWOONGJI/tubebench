function B = octaveBands(band)
%OCTAVEBANDS Octave bands of the summary tables: every band that overlaps the analysis band.
%   B = tim.plots.octaveBands([120 4500])
%
%   Octave bands with the exact centres 1000*2^n Hz (16 Hz ... 31.5 kHz) and
%   the edges centre/sqrt(2) ... centre*sqrt(2) (as tim.plots.bandValues
%   averages them). Every band that overlaps the analysis band is listed, so
%   no part of the band is left out of a table. A band that is only partly
%   inside the analysis band (e.g. 125 Hz: 88 ... 177 Hz with fMin = 120 Hz)
%   is marked '*': its value is a mean over the part inside the band only.
%
%   B.centres  (n x 1) exact centres in Hz (pass to tim.plots.bandValues)
%   B.labels   (n x 1) cellstr: nominal centre ('63', '125', ..., '4000'),
%              '*' appended for a partial band
%   B.partial  (n x 1) logical, band only partly inside the analysis band
%   B.note     '* = only partly inside the analysis band (fMin–fMax Hz)'
%              when a band is partial, else ''
%   (Reflection and transmission, Transmission loss, Transfer impedance.)
if nargin < 1 || numel(band) ~= 2 || any(~isfinite(band)), band = [120 4500]; end
nominal = [16 31.5 63 125 250 500 1000 2000 4000 8000 16000 31500];
c = 1000 * 2.^(-6:5);
tol = 1e-9;                                            % a band that only touches the analysis band is not listed
in = c * sqrt(2) > band(1) * (1 + tol) & c / sqrt(2) < band(2) * (1 - tol);
c = c(in); nominal = nominal(in);
partial = c / sqrt(2) < band(1) * (1 - tol) | c * sqrt(2) > band(2) * (1 + tol);
labels = arrayfun(@(x) sprintf('%g', x), nominal, 'UniformOutput', false);
labels(partial) = strcat(labels(partial), '*');
note = '';
if any(partial)
    note = sprintf('* = only partly inside the analysis band (%g%s%g Hz).', band(1), char(8211), band(2));
end
B = struct('centres', c(:), 'labels', {labels(:)}, 'partial', partial(:), 'note', note);
end
