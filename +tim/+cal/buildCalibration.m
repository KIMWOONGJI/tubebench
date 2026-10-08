function cal = buildCalibration(f, results, refChannel, meta)
%BUILDCALIBRATION Assemble a 4-channel complex calibration from switching results.
%
%   cal = tim.cal.buildCalibration(f, results, refChannel, meta)
%   results : 1x4 cell; results{k} = output of switchingCorrection for
%             channel k vs refChannel (empty for refChannel)
%   meta    : struct (mics, operator, positions, notes, rawFiles ...)
%
%   cal.C(:,k) = c_k / c_ref (complex, Nf x 4), cal.C(:,ref) = 1
%   Corrected relative pressure:  p_k/p_ref = (Y_k/Y_ref) / C_k
%   cal.valid (Nf x 4) per-channel validity; cal.version unique id.

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
cal.method = 'Sensor switching (ISO 10534-2 / ASTM E1050 type), Hc = sqrt(HI*HII), branch: low-frequency phase near 0';
cal.convention = 'C_k = c_k/c_ref; corrected H_k = measured H_k ./ C_k; exp(+j omega t)';
cal.meta = meta;
cal.matlabVersion = version;
end
