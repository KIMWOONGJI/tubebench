classdef TestStreamParser < matlab.unittest.TestCase
    %TESTSTREAMPARSER LAN-XI binary stream decoder: fixtures and fault cases.

    properties
        fs = 16384
        scale = 10 * 10^(1.5/20)
    end

    methods
        function [bytes, vals] = makeStream(tc, nMsg, nPer, ids)
            if nargin < 4, ids = 1:4; end
            rng(2);
            bytes = tim.sim.lanxiEncode('interpretation', ids, tc.scale * ones(1, numel(ids)), tc.fs, 'V', 1000);
            vals = zeros(nMsg * nPer, numel(ids));
            for m = 1:nMsg
                v = randi([-2^23, 2^23 - 1], nPer, numel(ids));
                v(1, :) = -2^23; v(2, :) = 2^23 - 1;   % int24 extremes
                vals((m-1)*nPer + (1:nPer), :) = v;
                t = 1000 + (m-1) * nPer / tc.fs;
                bytes = [bytes, tim.sim.lanxiEncode('signal', ids, num2cell(v, 1), t)]; %#ok<AGROW>
            end
        end
    end

    methods (Test)
        function roundTripExact(tc)
            [b, v] = tc.makeStream(10, 256);
            p = tim.instr.LanXiStreamParser(); p.feed(b);
            [d, info] = p.getData(1:4);
            tc.verifyEqual(d, v / 2^23 * tc.scale, 'AbsTol', 1e-12);
            tc.verifyEqual(info.fs, tc.fs * ones(1, 4), 'RelTol', 1e-12);
            tc.verifyEqual(info.unit, {'V', 'V', 'V', 'V'});
            tc.verifyEqual(info.stats.corruptMessages, 0);
            tc.verifyEqual(info.stats.timestampGaps, 0);
        end

        function byteByByteAndRandomChunks(tc)
            [b, v] = tc.makeStream(5, 100);
            p = tim.instr.LanXiStreamParser();
            for i = 1:numel(b), p.feed(b(i)); end
            tc.verifyEqual(p.getData(1:4), v / 2^23 * tc.scale, 'AbsTol', 1e-12);
            p2 = tim.instr.LanXiStreamParser(); rng(4); pos = 1;
            while pos <= numel(b)
                n = randi(50); p2.feed(b(pos:min(end, pos + n - 1))); pos = pos + n;
            end
            tc.verifyEqual(p2.getData(1:4), v / 2^23 * tc.scale, 'AbsTol', 1e-12);
        end

        function incompleteTrailingMessage(tc)
            [b, v] = tc.makeStream(4, 64);
            p = tim.instr.LanXiStreamParser(); p.feed(b(1:end-10));
            d = p.getData(1:4);
            tc.verifyEqual(d, v(1:3*64, :) / 2^23 * tc.scale, 'AbsTol', 1e-12);
            tc.verifyGreaterThan(p.pendingBytes(), 0);
            p.feed(b(end-9:end));
            tc.verifyEqual(p.getData(1:4), v / 2^23 * tc.scale, 'AbsTol', 1e-12);
        end

        function corruptedMagicResync(tc)
            [b, v] = tc.makeStream(6, 64);
            msgLen = 28 + 4 + 4 * (4 + 3 * 64);
            interpLen = numel(b) - 6 * msgLen;
            k = interpLen + 2 * msgLen + 1;           % first byte of the 3rd SignalData
            b(k) = uint8('X');
            p = tim.instr.LanXiStreamParser(); p.feed(b);
            d = p.getData(1:4);
            keep = [1:2*64, 3*64+1:6*64];
            tc.verifyEqual(d, v(keep, :) / 2^23 * tc.scale, 'AbsTol', 1e-12);
            tc.verifyGreaterThan(p.Stats.discardedBytes, 0);
            tc.verifyGreaterThan(p.Stats.timestampGaps, 0, 'lost message must show as timestamp gap');
            info = struct();
            [~, info] = p.getData(1:4);
            r = tim.acq.checkIntegrity(d, info, tc.fs, '10 Vpeak');
            tc.verifyFalse(r.ok);
        end

        function inconsistentLengthDiscarded(tc)
            [b, ~] = tc.makeStream(2, 64);
            % corrupt numberOfValues of signal 1 in message 1 (claims 65 values)
            interpLen = numel(b) - 2 * (28 + 4 + 4 * (4 + 3 * 64));
            off = interpLen + 28 + 4 + 2;      % 0-based offset of numberOfValues
            b(off + 1:off + 2) = typecast(int16(65), 'uint8');
            p = tim.instr.LanXiStreamParser(); p.feed(b);
            tc.verifyEqual(p.Stats.corruptMessages, 1);
            tc.verifyEqual(p.samplesAvailable(), 64);
        end

        function unexpectedChannelOrder(tc)
            ids = 1:4; rng(9);
            b = tim.sim.lanxiEncode('interpretation', ids, tc.scale * [1 2 3 4], tc.fs, 'V', 0);
            v = randi([-1e6 1e6], 32, 4);
            order = [3 1 4 2];
            b = [b, tim.sim.lanxiEncode('signal', order, num2cell(v(:, order), 1), 0)];
            p = tim.instr.LanXiStreamParser(); p.feed(b);
            d = p.getData(1:4);
            tc.verifyEqual(d, v / 2^23 .* (tc.scale * [1 2 3 4]), 'AbsTol', 1e-12);
        end

        function missingAndLateMetadata(tc)
            v = randi([-1e6 1e6], 32, 2);
            sig = tim.sim.lanxiEncode('signal', [1 2], num2cell(v, 1), 0);
            p = tim.instr.LanXiStreamParser(); p.feed(sig);
            [d, info] = p.getData(1:2);
            tc.verifyEqual(info.missingMetadata, [true true]);
            r = tim.acq.checkIntegrity(d, info, tc.fs, '10 Vpeak');
            tc.verifyFalse(r.ok);
            % interpretation arriving later: data become scaled
            p.feed(tim.sim.lanxiEncode('interpretation', [1 2], [2 2], tc.fs, 'V', 0));
            [d2, info2] = p.getData(1:2);
            tc.verifyEqual(info2.missingMetadata, [false false]);
            tc.verifyEqual(d2, v / 2^23 * 2, 'AbsTol', 1e-12);
        end

        function wrongUnitDetected(tc)
            b = tim.sim.lanxiEncode('interpretation', 1:4, tc.scale * ones(1, 4), tc.fs, 'Pa', 0);
            b = [b, tim.sim.lanxiEncode('signal', 1:4, num2cell(randi(1000, 8, 4), 1), 0)];
            p = tim.instr.LanXiStreamParser(); p.feed(b);
            [d, info] = p.getData(1:4);
            r = tim.acq.checkIntegrity(d, info, tc.fs, '10 Vpeak');
            tc.verifyFalse(r.ok);
            tc.verifyTrue(any(contains(r.fatal, 'twice')));
        end

        function qualityFlags(tc)
            [b, ~] = tc.makeStream(2, 32);
            b = [b, tim.sim.lanxiEncode('quality', [2 3], [2 16], 1), tim.sim.lanxiEncode('aux', 1)];
            p = tim.instr.LanXiStreamParser(); p.feed(b);
            q = p.QualityEvents;
            tc.verifyEqual([q.signalId], [2 3]);
            tc.verifyEqual([q.clipped], [true false]);
            tc.verifyEqual([q.overrun], [false true]);
            tc.verifyEqual([q.sampleIndex], [64 64]);
            tc.verifyEqual(p.Stats.otherMessages, 1);
        end

        function tailForLiveView(tc)
            [b, v] = tc.makeStream(6, 100);
            p = tim.instr.LanXiStreamParser(); p.feed(b);
            x = p.tail(250, 1:4);
            tc.verifyEqual(x, v(end-249:end, :) / 2^23 * tc.scale, 'AbsTol', 1e-12);
            x2 = p.tail(1000, 1:4);                         % more than available -> NaN padded at the start
            tc.verifyTrue(all(isnan(x2(1:400, 1))));
            tc.verifyEqual(x2(401:end, :), v / 2^23 * tc.scale, 'AbsTol', 1e-12);
        end

        function missingSignalError(tc)
            [b, ~] = tc.makeStream(1, 8, [1 2 3]);
            p = tim.instr.LanXiStreamParser(); p.feed(b);
            tc.verifyError(@() p.getData(1:4), 'tim:stream:missingSignal');
        end

        function realHardwareFixture(tc)
            % Bytes recorded from the real LAN-XI 3676 (fw 2.10.0.610), 16384 S/s,
            % 4 channels, 10 Vpeak range, no excitation (2026-10-08).
            fx = fullfile(fileparts(mfilename('fullpath')), 'fixtures', 'lanxi_stream_3676_noise_16k.mat');
            S = load(fx, 'raw');
            p = tim.instr.LanXiStreamParser(); p.feed(S.raw);
            [d, info] = p.getData(1:4);
            tc.verifyEqual(info.fs, 16384 * ones(1, 4));
            tc.verifyEqual(info.unit, {'V', 'V', 'V', 'V'});
            tc.verifyEqual(info.scaleFactor, 10 * 10^(1.5/20) * ones(1, 4), 'RelTol', 1e-4);
            tc.verifyEqual(info.stats.corruptMessages, 0);
            tc.verifyEqual(info.stats.discardedBytes, 0);
            tc.verifyEqual(info.stats.timestampGaps, 0);
            tc.verifyGreaterThanOrEqual(size(d, 1), 32768);
            tc.verifyEqual(p.Stats.interpretationMessages, 4);
            % random re-chunking gives identical data
            p2 = tim.instr.LanXiStreamParser(); rng(1); pos = 1;
            while pos <= numel(S.raw)
                n = randi([1 3000]); p2.feed(S.raw(pos:min(end, pos + n - 1))); pos = pos + n;
            end
            tc.verifyEqual(p2.getData(1:4), d);
            % the recording had INVALID flags (no microphones / CCLD fault) -> must be reported:
            % one DataQuality message per signal (an empty list would pass all([]))
            tc.verifyNumElements(info.qualityEvents, 4);
            tc.verifyTrue(all([info.qualityEvents.invalid]));
            r = tim.acq.checkIntegrity(d, info, 16384, '10 Vpeak');
            tc.verifyFalse(r.ok, 'INVALID flags fail the integrity check');
            tc.verifyTrue(any(contains(r.fatal, 'INVALID')), strjoin(r.fatal, ' | '));
        end
    end
end
