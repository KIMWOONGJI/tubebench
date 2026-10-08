classdef LanXiStreamParser < handle
    %LANXISTREAMPARSER Incremental decoder for the LAN-XI Open API data stream.
    %
    %   p = tim.instr.LanXiStreamParser();
    %   p.feed(uint8Bytes);          % any chunking, partial messages allowed
    %   [data, info] = p.getData();  % (Nsamples x Nsignals) scaled values
    %
    %   Format: docs/ref_lanxi_openapi.md (BE 1872 ch.5, openapi_message.ksy).
    %   Robustness features:
    %     * messages split across feed() calls are reassembled
    %     * on a bad magic word / implausible header the parser re-synchronises
    %       on the next "BK" and counts the discarded bytes
    %     * SignalData whose content length is inconsistent is discarded and counted
    %     * signals are keyed by signalId (order inside a message is irrelevant)
    %     * samples received before the Interpretation of their signal are kept
    %       raw and scaled once the scale factor is known; if it never arrives,
    %       getData() reports the signal as unscaled (info.missingMetadata)
    %     * DataQuality flags (clipped / invalid / overrun) are logged with the
    %       sample index at which they were reported
    %     * header-timestamp continuity is checked per signal (diagnostic only)
    %
    %   Hardware status: see docs/hardware_status.md.

    properties (Constant)
        MSG_SIGNAL = 1
        MSG_QUALITY = 2
        MSG_INTERPRETATION = 8
        MSG_AUX = 11
        MAX_CONTENT = 4 * 1024 * 1024   % real SignalData messages are a few kB
    end

    properties (SetAccess = private)
        Signals          % containers.Map signalId -> struct (created in constructor)
        QualityEvents = struct('signalId', {}, 'flags', {}, 'sampleIndex', {}, 'clipped', {}, 'invalid', {}, 'overrun', {})
        Stats = struct('bytes', 0, 'messages', 0, 'signalMessages', 0, 'interpretationMessages', 0, ...
            'qualityMessages', 0, 'otherMessages', 0, 'discardedBytes', 0, 'resyncs', 0, ...
            'corruptMessages', 0, 'timestampGaps', 0)
        FirstTimestamp double = NaN    % seconds since 1970 of the first SignalData header
        Warnings cell = {}
    end
    properties (Access = private)
        Buf uint8 = zeros(1, 0, 'uint8')
        Resyncing logical = false
    end

    methods
        function obj = LanXiStreamParser()
            obj.Signals = containers.Map('KeyType', 'double', 'ValueType', 'any');
        end

        function feed(obj, bytes)
            if isempty(bytes), return; end
            obj.Buf = [obj.Buf, reshape(uint8(bytes), 1, [])];
            obj.Stats.bytes = obj.Stats.bytes + numel(bytes);
            obj.parseBuffer();
        end

        function n = pendingBytes(obj)
            n = numel(obj.Buf);
        end

        function ids = signalIds(obj)
            ids = sort(cell2mat(keys(obj.Signals)));
        end

        function n = samplesAvailable(obj)
            %SAMPLESAVAILABLE Minimum number of samples over all signals.
            ids = obj.signalIds();
            if isempty(ids), n = 0; return; end
            n = inf;
            for id = ids
                n = min(n, obj.Signals(id).count);
            end
        end

        function x = tail(obj, n, ids)
            %TAIL Last n samples of the given signals (scaled), for live display.
            %   Cheap: only the newest chunks are touched. Signals without
            %   data yet are returned as NaN; columns are aligned at the end.
            if nargin < 3, ids = obj.signalIds(); end
            x = nan(n, numel(ids));
            for i = 1:numel(ids)
                if ~isKey(obj.Signals, ids(i)), continue; end
                s = obj.Signals(ids(i));
                got = 0; k = numel(s.chunks); parts = {};
                while k >= 1 && got < n
                    parts = [s.chunks(k), parts]; %#ok<AGROW>
                    got = got + numel(s.chunks{k}); k = k - 1;
                end
                if got == 0, continue; end
                v = vertcat(parts{:});
                v = v(max(1, end - n + 1):end);
                sc = s.scaleFactor; if isnan(sc), sc = 1; end
                x(end - numel(v) + 1:end, i) = v / 2^23 * sc + s.offset;
            end
        end

        function [data, info] = getData(obj, expectedIds)
            %GETDATA Scaled data, columns ordered by signalId (or expectedIds).
            if nargin < 2, expectedIds = obj.signalIds(); end
            info = struct();
            info.signalIds = expectedIds;
            info.missingSignals = setdiff(expectedIds, obj.signalIds());
            if ~isempty(info.missingSignals)
                error('tim:stream:missingSignal', 'No data received for signal(s) %s.', mat2str(info.missingSignals));
            end
            n = obj.samplesAvailable();
            counts = arrayfun(@(id) obj.Signals(id).count, expectedIds);
            info.samplesPerSignal = counts;
            info.trimmedSamples = counts - n;
            data = zeros(n, numel(expectedIds));
            info.unit = cell(1, numel(expectedIds));
            info.scaleFactor = nan(1, numel(expectedIds));
            info.fs = nan(1, numel(expectedIds));
            info.missingMetadata = false(1, numel(expectedIds));
            for i = 1:numel(expectedIds)
                s = obj.Signals(expectedIds(i));
                raw = vertcat(s.chunks{:});
                raw = raw(1:n);
                if isnan(s.scaleFactor)
                    info.missingMetadata(i) = true;
                    data(:, i) = raw / 2^23;      % normalised, unscaled
                else
                    data(:, i) = raw / 2^23 * s.scaleFactor + s.offset;
                end
                info.unit{i} = s.unit;
                info.scaleFactor(i) = s.scaleFactor;
                info.fs(i) = 1 / s.period;
                info.timestampGaps(i) = s.gaps;
                info.dataType(i) = s.dataType;
            end
            info.qualityEvents = obj.QualityEvents;
            info.stats = obj.Stats;
            info.firstTimestamp = obj.FirstTimestamp;
            info.warnings = obj.Warnings;
        end

        function reset(obj)
            obj.Buf = zeros(1, 0, 'uint8');
            obj.Resyncing = false;
            obj.Signals = containers.Map('KeyType', 'double', 'ValueType', 'any');
            obj.QualityEvents = obj.QualityEvents([]);
            f = fieldnames(obj.Stats);
            for i = 1:numel(f), obj.Stats.(f{i}) = 0; end
            obj.FirstTimestamp = NaN;
            obj.Warnings = {};
        end
    end

    methods (Access = private)
        function parseBuffer(obj)
            b = obj.Buf;
            pos = 1;                       % 1-based index of next unparsed byte
            N = numel(b);
            while N - pos + 1 >= 28
                if ~(b(pos) == 66 && b(pos+1) == 75)      % 'B','K'
                    pos = obj.resync(b, pos);
                    obj.Resyncing = true;
                    if pos > N, break; end
                    continue
                end
                hdrLen = double(typecast(b(pos+2:pos+3), 'uint16'));
                msgType = double(typecast(b(pos+4:pos+5), 'uint16'));
                % plausibility of the header (protects against a false "BK"
                % inside sample data after a resynchronisation)
                if hdrLen < 20 || hdrLen > 64 || msgType > 255
                    obj.Stats.corruptMessages = obj.Stats.corruptMessages + 1;
                    pos = obj.resync(b, pos + 1); obj.Resyncing = true;
                    continue
                end
                contentStart = pos + 4 + hdrLen + 4;        % 1-based
                if N < contentStart - 1, break; end         % header incomplete
                fam = double(b(pos+12:pos+15));
                ticks = double(typecast(b(pos+16:pos+23), 'uint64'));
                len = double(typecast(b(pos+4+hdrLen:pos+4+hdrLen+3), 'uint32'));
                if len > obj.MAX_CONTENT || any(fam > 64)
                    obj.Stats.corruptMessages = obj.Stats.corruptMessages + 1;
                    pos = obj.resync(b, pos + 1); obj.Resyncing = true;
                    continue
                end
                if N < contentStart + len - 1, break; end   % content incomplete
                if obj.Resyncing
                    % header found by searching: accept only if the next
                    % message also starts with "BK" (or the buffer ends here)
                    nxt = contentStart + len;
                    if N >= nxt + 1 && ~(b(nxt) == 66 && b(nxt+1) == 75)
                        pos = obj.resync(b, pos + 1);
                        continue
                    elseif N < nxt + 1
                        break                                % wait for confirmation
                    end
                    obj.Resyncing = false;
                end
                content = b(contentStart:contentStart + len - 1);
                tickRate = 2^fam(1) * 3^fam(2) * 5^fam(3) * 7^fam(4);
                t = ticks / tickRate;
                obj.Stats.messages = obj.Stats.messages + 1;
                ok = true;
                switch msgType
                    case obj.MSG_SIGNAL
                        ok = obj.parseSignalData(content, t);
                        obj.Stats.signalMessages = obj.Stats.signalMessages + 1;
                    case obj.MSG_INTERPRETATION
                        ok = obj.parseInterpretation(content);
                        obj.Stats.interpretationMessages = obj.Stats.interpretationMessages + 1;
                    case obj.MSG_QUALITY
                        ok = obj.parseQuality(content);
                        obj.Stats.qualityMessages = obj.Stats.qualityMessages + 1;
                    otherwise
                        obj.Stats.otherMessages = obj.Stats.otherMessages + 1;
                end
                if ~ok
                    obj.Stats.corruptMessages = obj.Stats.corruptMessages + 1;
                end
                pos = contentStart + len;
            end
            obj.Buf = b(pos:end);
        end

        function pos = resync(obj, b, pos)
            % Skip forward to the next "BK"; count discarded bytes.
            start = pos;
            idx = find(b(pos:end-1) == 66 & b(pos+1:end) == 75, 1);
            if isempty(idx)
                % keep a possible trailing 'B'
                if b(end) == 66, pos = numel(b); else, pos = numel(b) + 1; end
            else
                pos = pos + idx - 1;
            end
            obj.Stats.discardedBytes = obj.Stats.discardedBytes + (pos - start);
            obj.Stats.resyncs = obj.Stats.resyncs + 1;
        end

        function s = getSignal(obj, id)
            if isKey(obj.Signals, id)
                s = obj.Signals(id);
            else
                s = struct('id', id, 'chunks', {{}}, 'count', 0, 'scaleFactor', NaN, ...
                    'offset', 0, 'unit', '', 'period', NaN, 'dataType', NaN, ...
                    'channelType', NaN, 'lastT', NaN, 'lastN', 0, 'gaps', 0);
            end
        end

        function ok = parseSignalData(obj, c, t)
            ok = false;
            L = numel(c);
            if L < 4, return; end
            nSig = double(typecast(c(1:2), 'uint16'));
            p = 5;
            blocks = cell(nSig, 1); ids = zeros(nSig, 1);
            for i = 1:nSig
                if p + 3 > L, return; end
                ids(i) = double(typecast(c(p:p+1), 'int16'));
                nv = double(typecast(c(p+2:p+3), 'int16'));
                p = p + 4;
                if nv < 0 || p + 3*nv - 1 > L, return; end
                v = reshape(c(p:p + 3*nv - 1), 3, nv);
                blocks{i} = double(v(1,:)).' + 256 * double(v(2,:)).' + ...
                    65536 * double(typecast(v(3,:), 'int8')).';
                p = p + 3*nv;
            end
            if p ~= L + 1
                return          % trailing bytes: inconsistent message, discard all
            end
            if isnan(obj.FirstTimestamp), obj.FirstTimestamp = t; end
            for i = 1:nSig
                s = obj.getSignal(ids(i));
                nv = numel(blocks{i});
                % timestamp continuity (diagnostic; semantics of the header
                % time is not specified to be "time of first sample")
                if ~isnan(s.lastT) && ~isnan(s.period)
                    expected = s.lastT + s.lastN * s.period;
                    if abs(t - expected) > 0.5 * s.period
                        s.gaps = s.gaps + 1;
                        obj.Stats.timestampGaps = obj.Stats.timestampGaps + 1;
                    end
                end
                s.lastT = t; s.lastN = nv;
                s.chunks{end+1} = blocks{i};
                s.count = s.count + nv;
                obj.Signals(ids(i)) = s;
            end
            ok = true;
        end

        function ok = parseInterpretation(obj, c)
            ok = true;
            L = numel(c); p = 1;
            while p + 7 <= L
                id = double(typecast(c(p:p+1), 'uint16'));
                dt = double(typecast(c(p+2:p+3), 'uint16'));
                vlen = double(typecast(c(p+6:p+7), 'uint16'));
                p = p + 8;
                vstart = p;
                switch dt
                    case 1  % DataType
                        need = 2;
                    case {2, 3}
                        need = 8;
                    case 4
                        need = 12;
                    case 5
                        if p + 1 > L, ok = false; return; end
                        cnt = double(typecast(c(p:p+1), 'uint16'));
                        need = 2 + cnt;
                    case {6, 7}
                        need = 2;
                    otherwise
                        need = vlen;   % unknown descriptor: skip by its length
                end
                if vstart + need - 1 > L, ok = false; return; end
                v = c(vstart:vstart + need - 1);
                if id == 0
                    targets = obj.signalIds();      % 0 = all signals
                else
                    targets = id;
                end
                for tid = targets(:).'
                    s = obj.getSignal(tid);
                    switch dt
                        case 1, s.dataType = double(typecast(v(1:2), 'uint16'));
                            if s.dataType ~= 3
                                obj.Warnings{end+1} = sprintf('Signal %d: unsupported data type %d (expected 3 = Int24).', tid, s.dataType);
                            end
                        case 2, s.scaleFactor = typecast(v(1:8), 'double');
                        case 3, s.offset = typecast(v(1:8), 'double');
                        case 4
                            fam = double(v(1:4));
                            s.period = double(typecast(v(5:12), 'uint64')) / (2^fam(1)*3^fam(2)*5^fam(3)*7^fam(4));
                        case 5, s.unit = native2unicode(v(3:end), 'UTF-8');
                        case 7, s.channelType = double(typecast(v(1:2), 'uint16'));
                    end
                    obj.Signals(tid) = s;
                end
                p = vstart + need;
                p = p + mod(4 - mod(p - 1, 4), 4);    % pad to 4-byte boundary (0-based pos)
            end
        end

        function ok = parseQuality(obj, c)
            ok = false;
            L = numel(c);
            if L < 2, return; end
            n = double(typecast(c(1:2), 'uint16'));
            if L < 2 + 6*n, return; end
            for i = 1:n
                p = 3 + 6*(i-1);
                id = double(typecast(c(p:p+1), 'uint16'));
                fl = double(typecast(c(p+2:p+3), 'uint16'));
                idx = 0;
                if isKey(obj.Signals, id), idx = obj.Signals(id).count; end
                obj.QualityEvents(end+1) = struct('signalId', id, 'flags', fl, 'sampleIndex', idx, ...
                    'clipped', bitand(fl, 2) > 0, 'invalid', bitand(fl, 8) > 0, 'overrun', bitand(fl, 16) > 0);
            end
            ok = true;
        end
    end
end
