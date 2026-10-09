function [thick, txt, kd] = thickSpecimen(a)
%THICKSPECIMEN Is the thin-element (lumped) model meaningless for this specimen?
%   [thick, txt, kd] = tim.plots.thickSpecimen(res.analysis)
%
%   The transfer impedance Z_t = (p_L - p_R)/u treats the specimen as a
%   lumped element of negligible thickness. With the specimen section
%   d = xRear - xFront this needs k*d << 1; the views hide Z_t and the TL
%   derived from it when k*d exceeds 1 anywhere in the analysis band
%   (thick = kd > 1). kd is the largest k*d of the in-band bins
%   (res.analysis.valid.measured: stepped steps may lie outside the band);
%   without in-band bins it is evaluated at the upper band limit.
%   txt is a one-line explanation, e.g.
%   'Thin-element model not applicable: d = 75 mm (k·d up to 6.2)'
%   (empty when the model applies). Without the face positions (no
%   boundary quantities) thick is false and kd NaN.
thick = false; txt = ''; kd = NaN;
if ~isstruct(a) || ~isfield(a, 'boundary') || ~isfield(a.boundary, 'available') || ...
        ~a.boundary.available || ~isfield(a.boundary, 'thickness')
    return
end
d = a.boundary.thickness;
m = false(size(a.f));
if isfield(a, 'valid') && isfield(a.valid, 'measured'), m = a.valid.measured; end
if any(m)
    kd = max(real(a.k(m))) * d;
elseif isfield(a, 'options') && isfield(a.options, 'fRange') && numel(a.options.fRange) == 2
    kd = 2 * pi * a.options.fRange(2) / a.air.c * d;
else
    kd = max(real(a.k)) * d;
end
thick = kd > 1;
if thick
    txt = sprintf('Thin-element model not applicable: d = %g mm (k%sd up to %.1f)', ...
        round(1e3 * d, 3), char(183), kd);
end
end
