function [Hc, calValid, info] = applyCalibration(f, H, cal, refChannel)
%APPLYCALIBRATION Correct measured relative responses with a complex calibration.
%
%   [Hc, calValid] = tim.cal.applyCalibration(f, H, cal, refChannel)
%   H : (Nf x 4) measured Y_k / Y_ref (ref = refChannel)
%   Hc(:,k) = H(:,k) ./ C(:,k),  C from interpolateCalibration
%   calValid (Nf x 1): true where all four channels have valid calibration.
%   If cal is empty, H is returned unchanged and calValid is all false
%   (results can then never be marked valid - TEDS/nominal sensitivities
%   are NOT a substitute for the complex phase calibration).

if isempty(cal)
    Hc = H; calValid = false(numel(f), 1);
    info = 'NO complex calibration applied: results are not valid for wave decomposition.';
    return
end
if cal.refChannel ~= refChannel
    error('tim:cal:ref', 'Calibration reference channel %d differs from measurement reference %d.', ...
        cal.refChannel, refChannel);
end
[C, v] = tim.cal.interpolateCalibration(cal, f);
Hc = H ./ C;
calValid = all(v, 2);
info = sprintf('Calibration %s applied (%d of %d bins valid).', cal.version, nnz(calValid), numel(f));
end
