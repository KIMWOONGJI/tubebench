function [C, valid] = interpolateCalibration(cal, f)
%INTERPOLATECALIBRATION Calibration factors on a new frequency grid.
%
%   [C, valid] = tim.cal.interpolateCalibration(cal, f)
%
%   C_k = g_k / g_ref (calibration factors, tim.cal.buildCalibration).
%   Magnitude and phase are interpolated SEPARATELY: log|C| and the
%   UNWRAPPED phase (unwrap along the calibration grid) are interpolated
%   linearly, then recombined. Interpolating real/imaginary parts would
%   shrink the magnitude between frequency lines where the phase changes quickly;
%   interpolating the wrapped phase would create spurious 2*pi jumps.
%   No extrapolation: outside [min(cal.f), max(cal.f)] C = NaN, valid = false.
%   The edges are tolerant by 1e-9 relative (a stepped-sine step at the
%   band edge that logspace rounded a few ulp outside, e.g. 120 Hz ->
%   119.99999999999996 Hz, uses the edge value instead of NaN).
%   A target frequency line is valid only if both neighbouring calibration
%   frequency lines are valid.

f = f(:);
Nf = numel(f);
C = nan(Nf, 4) + 1j * nan(Nf, 4);
valid = false(Nf, 4);
tol = 1e-9 * max(abs(cal.f([1 end])));
inR = f >= cal.f(1) - tol & f <= cal.f(end) + tol;
fq = min(max(f(inR), cal.f(1)), cal.f(end));      % clamp the tolerated edge bins onto the grid
for k = 1:4
    ck = cal.C(:, k);
    if all(~isfinite(ck)), continue; end
    lm = log(abs(ck));
    ph = unwrap(angle(ck));
    C(inR, k) = exp(interp1(cal.f, lm, fq, 'linear') + 1j * interp1(cal.f, ph, fq, 'linear'));
    vPrev = interp1(cal.f, double(cal.valid(:, k)), fq, 'previous');
    vNext = interp1(cal.f, double(cal.valid(:, k)), fq, 'next');
    vv = false(nnz(inR), 1);
    vv(:) = vPrev == 1 & vNext == 1;
    valid(inR, k) = vv;
end
end
