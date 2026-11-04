function [Hc, calValid, info, validCh, outside] = applyCalibration(f, H, cal, refChannel)
%APPLYCALIBRATION Correct measured transfer functions with the calibration factors C_k.
%
%   [Hc, calValid, info, validCh, outside] = tim.cal.applyCalibration(f, H, cal, refChannel)
%   H : (Nf x 4) measured Y_k / Y_ref (ref = refChannel)
%   Hc(:,k) = H(:,k) ./ C(:,k),  C_k = g_k / g_ref from interpolateCalibration
%   calValid (Nf x 1): true where all four channels have valid calibration.
%   validCh  (Nf x 4): per-channel validity (column k = DAQ channel k; the
%            reference column is valid wherever the calibration grid covers
%            f). The analysis reorders it to tube positions, so that R needs
%            only the calibration of the channels in M1/M2 (review analysis-3).
%   outside  (Nf x 1): lines outside the frequency range of the calibration;
%            they are corrected with the factor of the nearest calibrated
%            line (indicative values, never valid; 1.5.1).
%   If cal is empty, H is returned unchanged and calValid is all false
%   (results can then never be marked valid - TEDS/nominal sensitivities
%   are NOT a substitute for the switching calibration of amplitude and phase).

if isempty(cal)
    Hc = H; calValid = false(numel(f), 1); validCh = false(numel(f), 4); outside = false(numel(f), 1);
    info = 'No calibration applied: the results are not valid (sensitivities alone do not correct the phase between the channels).';
    return
end
if cal.refChannel ~= refChannel
    error('tim:cal:ref', 'Reference channel of the calibration (ch%d) differs from the reference channel of the measurement (ch%d).', ...
        cal.refChannel, refChannel);
end
[C, validCh, outside] = tim.cal.interpolateCalibration(cal, f);
Hc = H ./ C;
calValid = all(validCh, 2);
info = sprintf('Calibration %s applied (%d of %d frequency lines valid).', cal.version, nnz(calValid), numel(f));
if any(outside)
    info = sprintf(['%s %d lines lie outside its range (%g–%g Hz): corrected with the nearest calibrated line, ' ...
        'shown for information, never valid.'], info, nnz(outside), cal.f(1), cal.f(end));
end
end
