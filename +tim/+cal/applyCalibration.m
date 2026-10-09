function [Hc, calValid, info, validCh] = applyCalibration(f, H, cal, refChannel)
%APPLYCALIBRATION Correct measured transfer functions with the calibration factors C_k.
%
%   [Hc, calValid, info, validCh] = tim.cal.applyCalibration(f, H, cal, refChannel)
%   H : (Nf x 4) measured Y_k / Y_ref (ref = refChannel)
%   Hc(:,k) = H(:,k) ./ C(:,k),  C_k = g_k / g_ref from interpolateCalibration
%   calValid (Nf x 1): true where all four channels have valid calibration.
%   validCh  (Nf x 4): per-channel validity (column k = DAQ channel k; the
%            reference column is valid wherever the calibration grid covers
%            f). The analysis reorders it to tube positions, so that R needs
%            only the calibration of the channels in M1/M2 (review analysis-3).
%   If cal is empty, H is returned unchanged and calValid is all false
%   (results can then never be marked valid - TEDS/nominal sensitivities
%   are NOT a substitute for the switching calibration of amplitude and phase).

if isempty(cal)
    Hc = H; calValid = false(numel(f), 1); validCh = false(numel(f), 4);
    info = 'No calibration applied: the results are not valid (sensitivities alone do not correct the phase between the channels).';
    return
end
if cal.refChannel ~= refChannel
    error('tim:cal:ref', 'Reference channel of the calibration (ch%d) differs from the reference channel of the measurement (ch%d).', ...
        cal.refChannel, refChannel);
end
[C, validCh] = tim.cal.interpolateCalibration(cal, f);
Hc = H ./ C;
calValid = all(validCh, 2);
info = sprintf('Calibration %s applied (%d of %d frequency lines valid).', cal.version, nnz(calValid), numel(f));
end
