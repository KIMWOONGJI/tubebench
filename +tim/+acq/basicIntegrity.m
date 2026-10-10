function r = basicIntegrity(data, fsData, fsExpected, fullScale_V)
%BASICINTEGRITY Integrity checks that every acquisition driver can make on its data.
%
%   r = tim.acq.basicIntegrity(data, fsData, fsExpected, fullScale_V)
%   data         n x C samples (volts at the input)
%   fsData       sample rate the data were recorded with [S/s]
%   fsExpected   the configured sample rate [S/s]
%   fullScale_V  the input range (peak volts), NaN if unknown
%
%   r.ok, r.fatal, r.warnings (cellstr), r.peak_V and r.peakFractionOfRange
%   (1 x C), r.channelFaults (1 x C cell of cellstr, empty: the driver adds
%   the faults its device reports, in its own words) - the integrity fields
%   of the instrument contract (docs/instrument_interface.md section 4.1).
%   Fatal: another sample rate than configured, non-finite samples, a
%   constant (dead) channel, a peak of 99 % of the input range or more.
%   Warning: a channel below 0.1 % of the input range. The LAN-XI driver
%   uses tim.acq.checkIntegrity, which adds the checks of its data stream.

nCh = size(data, 2);
r = struct('ok', true, 'fatal', {{}}, 'warnings', {{}}, 'peak_V', nan(1, nCh), ...
    'peakFractionOfRange', nan(1, nCh), 'channelFaults', {repmat({{}}, 1, nCh)});
if any(abs(fsData - fsExpected) > 1e-9 * fsExpected)
    r.fatal{end+1} = sprintf('Data sample rate %s S/s differs from the configured %g S/s.', mat2str(fsData), fsExpected);
end
if any(~isfinite(data(:)))
    r.fatal{end+1} = 'Non-finite samples in data.';
end
if ~isempty(data)
    pk = max(abs(data), [], 1);
    r.peak_V = pk;
    r.peakFractionOfRange = pk / fullScale_V;
    if isfinite(fullScale_V)
        over = find(pk >= 0.99 * fullScale_V);
        if ~isempty(over)
            r.fatal{end+1} = sprintf('Overload: channel(s) %s reach >= 99%% of the %g V input range.', mat2str(over), fullScale_V);
        end
        low = find(pk < 1e-3 * fullScale_V);
        if ~isempty(low)
            r.warnings{end+1} = sprintf('Channel(s) %s peak below 0.1%% of range (check range / microphone connection).', ...
                mat2str(low));
        end
    end
    dead = find(std(data, 0, 1) == 0);
    if ~isempty(dead)
        r.fatal{end+1} = sprintf('Channel(s) %s constant (dead channel).', mat2str(dead));
    end
end
r.ok = isempty(r.fatal);
end
