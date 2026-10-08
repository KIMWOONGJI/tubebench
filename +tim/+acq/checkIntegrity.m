function r = checkIntegrity(data, info, fsExpected, rangeStr, expectedUnit)
%CHECKINTEGRITY Data-integrity checks on decoded LAN-XI data (Test A).
%
%   r = tim.acq.checkIntegrity(data, info, fsExpected, rangeStr)
%
%   Checks: sample rate reported in the stream == configured rate; unit
%   == expected ('V', i.e. no sensitivity applied in the module); scale
%   factors present; no stream corruption / resynchronisation; no
%   timestamp gaps; DataQuality flags (clipped, invalid, overrun); software
%   overload detection (|v| >= 99 % of the nominal range); trimmed samples
%   between channels; non-finite values; dead (constant) channels.
%   r.ok is false if any FATAL problem exists; r.warnings lists the rest.

if nargin < 5, expectedUnit = 'V'; end
r = struct('ok', true, 'fatal', {{}}, 'warnings', {{}});
nCh = size(data, 2);

if any(abs(info.fs - fsExpected) > 1e-6 * fsExpected)
    r.fatal{end+1} = sprintf('Stream sample rate %s Hz differs from configured %g Hz.', mat2str(info.fs), fsExpected);
end
for i = 1:nCh
    if info.missingMetadata(i)
        r.fatal{end+1} = sprintf('Signal %d: no scale factor (Interpretation message missing).', i);
    elseif ~strcmp(strtrim(info.unit{i}), expectedUnit)
        r.fatal{end+1} = sprintf('Signal %d: stream unit "%s" but "%s" expected (sensitivity would be applied twice).', ...
            i, info.unit{i}, expectedUnit);
    end
end
if info.stats.corruptMessages > 0 || info.stats.discardedBytes > 0
    r.fatal{end+1} = sprintf('Stream corruption: %d corrupt messages, %d discarded bytes, %d resyncs.', ...
        info.stats.corruptMessages, info.stats.discardedBytes, info.stats.resyncs);
end
if info.stats.timestampGaps > 0
    r.warnings{end+1} = sprintf('%d header-timestamp discontinuities (possible lost data).', info.stats.timestampGaps);
end
q = info.qualityEvents;
if ~isempty(q)
    if any([q.overrun])
        r.fatal{end+1} = 'DataQuality: OVERRUN (gap in data) reported by module.';
    end
    if any([q.clipped])
        r.fatal{end+1} = sprintf('DataQuality: CLIPPED/overload on signal(s) %s.', mat2str(unique([q([q.clipped]).signalId])));
    end
    if any([q.invalid])
        r.fatal{end+1} = sprintf('DataQuality: INVALID (cable fault / CCLD / common-mode / analog overload) on signal(s) %s.', ...
            mat2str(unique([q([q.invalid]).signalId])));
    end
end
if any(info.trimmedSamples > 0)
    r.warnings{end+1} = sprintf('Channels had unequal length; trimmed %s samples.', mat2str(info.trimmedSamples));
end
if any(~isfinite(data(:)))
    r.fatal{end+1} = 'Non-finite samples in data.';
end
rangeV = sscanf(rangeStr, '%f');
if ~isempty(rangeV) && ~isempty(data)
    pk = max(abs(data), [], 1);
    r.peak_V = pk;
    r.peakFractionOfRange = pk / rangeV;
    over = find(pk >= 0.99 * rangeV);
    if ~isempty(over)
        r.fatal{end+1} = sprintf('Software overload check: channel(s) %s reach >= 99%% of the %s range.', mat2str(over), rangeStr);
    end
    low = find(pk < 1e-3 * rangeV);
    if ~isempty(low)
        r.warnings{end+1} = sprintf('Channel(s) %s peak below 0.1%% of range (check range / microphone connection).', mat2str(low));
    end
end
if ~isempty(data)
    dead = find(std(data, 0, 1) == 0);
    if ~isempty(dead)
        r.fatal{end+1} = sprintf('Channel(s) %s constant (dead channel).', mat2str(dead));
    end
end
r.ok = isempty(r.fatal);
end
