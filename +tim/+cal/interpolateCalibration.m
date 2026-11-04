function [C, valid, outside] = interpolateCalibration(cal, f)
%INTERPOLATECALIBRATION Calibration factors on a new frequency grid.
%
%   [C, valid, outside] = tim.cal.interpolateCalibration(cal, f)
%
%   C_k = g_k / g_ref (calibration factors, tim.cal.buildCalibration).
%   Magnitude and phase are interpolated SEPARATELY: log|C| and the
%   UNWRAPPED phase (unwrap along the calibration grid) are interpolated
%   linearly, then recombined. Interpolating real/imaginary parts would
%   shrink the magnitude between frequency lines where the phase changes quickly;
%   interpolating the wrapped phase would create spurious 2*pi jumps.
%   No extrapolation: outside [min(cal.f), max(cal.f)] (outside = true) C is
%   the factor of the nearest calibrated line at that edge, held constant,
%   and valid = false. Such a line (a stepped-sine step outside the
%   calibration band, owner decision 2026-11-04) gets a value for
%   information only, never a valid one; before 1.5.1 C was NaN there.
%   The edges are tolerant by 1e-9 relative (a stepped-sine step at the
%   band edge that logspace rounded a few ulp outside, e.g. 120 Hz ->
%   119.99999999999996 Hz, uses the edge value and counts as inside).
%   A target frequency line is valid only if both neighbouring calibration
%   frequency lines are valid.

f = f(:);
Nf = numel(f);
C = nan(Nf, 4) + 1j * nan(Nf, 4);
valid = false(Nf, 4);
tol = 1e-9 * max(abs(cal.f([1 end])));
inR = f >= cal.f(1) - tol & f <= cal.f(end) + tol;
below = f < cal.f(1) - tol; above = f > cal.f(end) + tol;
outside = below | above;
fq = min(max(f(inR), cal.f(1)), cal.f(end));      % clamp the tolerated edge bins onto the grid
for k = 1:4
    ck = cal.C(:, k);
    if all(~isfinite(ck)), continue; end
    lm = log(abs(ck));
    ph = unwrap(angle(ck));
    C(inR, k) = exp(interp1(cal.f, lm, fq, 'linear') + 1j * interp1(cal.f, ph, fq, 'linear'));
    % outside the grid: the factor of the nearest calibrated line, held
    fin = find(isfinite(ck));
    C(below, k) = ck(fin(1)); C(above, k) = ck(fin(end));
    vPrev = interp1(cal.f, double(cal.valid(:, k)), fq, 'previous');
    vNext = interp1(cal.f, double(cal.valid(:, k)), fq, 'next');
    vv = false(nnz(inR), 1);
    vv(:) = vPrev == 1 & vNext == 1;
    valid(inR, k) = vv;
end
end
