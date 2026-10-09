function [Hc, calValid, info] = applyCalibration(f, H, cal, refChannel)
%APPLYCALIBRATION Correct measured transfer functions with the calibration factors C_k.
%
%   [Hc, calValid] = tim.cal.applyCalibration(f, H, cal, refChannel)
%   H : (Nf x 4) measured Y_k / Y_ref (ref = refChannel)
%   Hc(:,k) = H(:,k) ./ C(:,k),  C_k = g_k / g_ref from interpolateCalibration
%   calValid (Nf x 1): true where all four channels have valid calibration.
%   If cal is empty, H is returned unchanged and calValid is all false
%   (results can then never be marked valid - TEDS/nominal sensitivities
%   are NOT a substitute for the switching calibration of amplitude and phase).

if isempty(cal)
    Hc = H; calValid = false(numel(f), 1);
    info = 'No calibration applied: the results are not valid (sensitivities alone do not correct the phase between the channels).';
    return
end
if cal.refChannel ~= refChannel
    error('tim:cal:ref', 'Reference channel of the calibration (ch%d) differs from the reference channel of the measurement (ch%d).', ...
        cal.refChannel, refChannel);
end
[C, v] = tim.cal.interpolateCalibration(cal, f);
Hc = H ./ C;
calValid = all(v, 2);
info = sprintf('Calibration %s applied (%d of %d frequency lines valid).', cal.version, nnz(calValid), numel(f));
end
