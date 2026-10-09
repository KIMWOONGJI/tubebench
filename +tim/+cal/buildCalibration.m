function cal = buildCalibration(f, results, refChannel, meta)
%BUILDCALIBRATION Assemble the 4-channel calibration from switching results.
%
%   cal = tim.cal.buildCalibration(f, results, refChannel, meta)
%   results : 1x4 cell; results{k} = output of switchingCorrection for
%             channel k vs refChannel (empty for refChannel)
%   meta    : struct (mics, operator, positions, notes, rawFiles ...)
%
%   cal.C(:,k) = C_k = g_k / g_ref (calibration factor, complex, Nf x 4),
%   cal.C(:,ref) = 1; g_k is the complex gain of measurement chain k.
%   Calibrated transfer function:  H_k = p_k/p_ref = (Y_k/Y_ref) / C_k
%   cal.valid (Nf x 4) per-channel validity; cal.version unique id.
%   cal.type ('tim.complexChannelCalibration') is the file identifier and
%   stays unchanged.

Nf = numel(f);
C = ones(Nf, 4); valid = true(Nf, 4); Hpos = nan(Nf, 4);
for k = 1:4
    if k == refChannel, continue; end
    if isempty(results{k})
        C(:, k) = NaN; valid(:, k) = false;
        continue
    end
    C(:, k) = results{k}.Hc;
    valid(:, k) = results{k}.valid;
    Hpos(:, k) = results{k}.Hpos;
end
ts = datetime('now');
cal = struct();
cal.type = 'tim.complexChannelCalibration';
cal.formatVersion = 1;
cal.version = sprintf('CAL-%s', char(ts, 'yyyyMMdd-HHmmss'));
cal.created = char(ts, 'yyyy-MM-dd HH:mm:ss');
cal.f = f(:);
cal.C = C;
cal.valid = valid;
cal.refChannel = refChannel;
cal.Hpos = Hpos;
cal.results = results;
cal.method = 'Switching calibration (microphone switching, ISO 10534-2 / ASTM E1050 type), C_k = sqrt(HI*HII), branch: low-frequency phase near 0';
cal.convention = 'C_k = g_k/g_ref (g_k: complex gain of chain k); calibrated H_k = measured H_k ./ C_k; exp(+j omega t)';
cal.meta = meta;
cal.matlabVersion = version;
end
