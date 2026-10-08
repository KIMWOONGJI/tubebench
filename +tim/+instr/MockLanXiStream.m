classdef MockLanXiStream < handle
    %MOCKLANXISTREAM Synthetic LAN-XI byte stream driven by a SimulatedRig.
    %
    %   Produces genuine Open API messages (tim.sim.lanxiEncode): one
    %   Interpretation message per signal when measuring starts, then
    %   SignalData messages of SamplesPerMessage samples (256, as observed on
    %   the real 3676 at 16384 S/s), DataQuality messages on overload.
    %   Each read() advances the virtual time by BlockSamples.
    %
    %   Options (struct fields, all optional):
    %     BlockSamples        samples generated per read()      (2048)
    %     SamplesPerMessage   samples per SignalData message    (256)
    %     RandomChunking      deliver bytes in random-size chunks (false)
    %     CorruptEvery        corrupt one byte every N messages (0 = never)
    %     StopAfterSamples    simulate interruption              (Inf)
    %     ShuffleSignals      random signal order inside messages (false)
    %     OmitInterpretation  never send Interpretation         (false)

    properties (SetAccess = private)
        Rig
        Fs double
        RangeV double
        SignalChannels double
        Opt struct
        Running logical = false
        Produced double = 0
        Backlog uint8 = zeros(1, 0, 'uint8')
        T0 double
        MsgCount double = 0
        Clipped logical
        Rng
    end

    methods
        function obj = MockLanXiStream(rig, fs, rangeV, channels, opt)
            d = struct('BlockSamples', 2048, 'SamplesPerMessage', 256, 'RandomChunking', false, ...
                'CorruptEvery', 0, 'StopAfterSamples', Inf, 'ShuffleSignals', false, 'OmitInterpretation', false);
            if nargin >= 5
                f = fieldnames(opt);
                for i = 1:numel(f), d.(f{i}) = opt.(f{i}); end
            end
            obj.Rig = rig; obj.Fs = fs; obj.RangeV = rangeV;
            obj.SignalChannels = channels; obj.Opt = d;
            obj.Clipped = false(1, numel(channels));
            obj.Rng = RandStream('mt19937ar', 'Seed', 7);
        end

        function start(obj)
            obj.Running = true;
            obj.T0 = floor(posixtime(datetime('now', 'TimeZone', 'UTC')));
            if ~obj.Opt.OmitInterpretation
                ids = 1:numel(obj.SignalChannels);
                scale = obj.RangeV * 10^(1.5/20) * ones(size(ids));
                obj.Backlog = [obj.Backlog, tim.sim.lanxiEncode('interpretation', ids, scale, obj.Fs, 'V', obj.T0)];
            end
        end

        function stop(obj)
            obj.Running = false;
        end

        function b = read(obj)
            if obj.Running && obj.Produced < obj.Opt.StopAfterSamples
                n = min(obj.Opt.BlockSamples, obj.Opt.StopAfterSamples - obj.Produced);
                obj.produce(n);
            end
            if obj.Opt.RandomChunking && numel(obj.Backlog) > 1
                k = randi(obj.Rng, numel(obj.Backlog));
            else
                k = numel(obj.Backlog);
            end
            b = obj.Backlog(1:k);
            obj.Backlog = obj.Backlog(k+1:end);
        end

        function close(obj)
            obj.Running = false;
        end
    end

    methods (Access = private)
        function produce(obj, n)
            if isempty(obj.Rig)
                v = 1e-3 * obj.Rng.randn(n, 4);
            else
                v = obj.Rig.generate(n);
            end
            v = v(:, obj.SignalChannels);
            fullScale = obj.RangeV * 10^(1.5/20);
            over = any(abs(v) > obj.RangeV, 1);
            q = round(v / fullScale * 2^23);
            q = min(max(q, -2^23), 2^23 - 1);
            ids = 1:numel(obj.SignalChannels);
            newClip = over & ~obj.Clipped;
            if any(newClip)
                tq = obj.T0 + obj.Produced / obj.Fs;
                obj.Backlog = [obj.Backlog, tim.sim.lanxiEncode('quality', ids(newClip), 2 * ones(1, nnz(newClip)), tq)];
                obj.Clipped = obj.Clipped | over;
            end
            spm = obj.Opt.SamplesPerMessage;
            for s0 = 1:spm:n
                idx = s0:min(n, s0 + spm - 1);
                order = ids;
                if obj.Opt.ShuffleSignals, order = order(randperm(obj.Rng, numel(order))); end
                vals = arrayfun(@(i) q(idx, i), order, 'UniformOutput', false);
                t = obj.T0 + (obj.Produced + idx(1) - 1) / obj.Fs;
                msg = tim.sim.lanxiEncode('signal', order, vals, t);
                obj.MsgCount = obj.MsgCount + 1;
                if obj.Opt.CorruptEvery > 0 && mod(obj.MsgCount, obj.Opt.CorruptEvery) == 0
                    msg(1) = uint8('X');    % destroy magic -> parser must resync
                end
                obj.Backlog = [obj.Backlog, msg];
            end
            obj.Produced = obj.Produced + n;
        end
    end
end
