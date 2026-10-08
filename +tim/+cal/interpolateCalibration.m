function [C, valid] = interpolateCalibration(cal, f)
%INTERPOLATECALIBRATION Calibration factors on a new frequency grid.
%
%   [C, valid] = tim.cal.interpolateCalibration(cal, f)
%
%   Magnitude and phase are interpolated SEPARATELY: log|C| and the
%   UNWRAPPED phase (unwrap along the calibration grid) are interpolated
%   linearly, then recombined. Interpolating real/imaginary parts would
%   shrink the magnitude between bins where the phase changes quickly;
%   interpolating the wrapped phase would create spurious 2*pi jumps.
%   No extrapolation: outside [min(cal.f), max(cal.f)] C = NaN, valid = false.
%   A target bin is valid only if both neighbouring calibration bins are valid.

f = f(:);
Nf = numel(f);
C = nan(Nf, 4) + 1j * nan(Nf, 4);
valid = false(Nf, 4);
inR = f >= cal.f(1) & f <= cal.f(end);
for k = 1:4
    ck = cal.C(:, k);
    if all(~isfinite(ck)), continue; end
    lm = log(abs(ck));
    ph = unwrap(angle(ck));
    C(inR, k) = exp(interp1(cal.f, lm, f(inR), 'linear') + 1j * interp1(cal.f, ph, f(inR), 'linear'));
    vPrev = interp1(cal.f, double(cal.valid(:, k)), f(inR), 'previous');
    vNext = interp1(cal.f, double(cal.valid(:, k)), f(inR), 'next');
    vv = false(nnz(inR), 1);
    vv(:) = vPrev == 1 & vNext == 1;
    valid(inR, k) = vv;
end
end
