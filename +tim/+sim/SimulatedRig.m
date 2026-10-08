classdef SimulatedRig < handle
    %SIMULATEDRIG Virtual impedance-tube rig used in SIMULATION mode.
    %
    %   rig = tim.sim.SimulatedRig(cfg)        (cfg from tim.app.defaultConfig)
    %
    %   Signal chain per DAQ channel c (all on the DAQ sample clock):
    %     generator volts x(t)  (33220A state from MockScpiTransport; own clock
    %                            with GenClockPpm offset; log sweep emulated as
    %                            a STEPPED sweep, not an ideal chirp; random
    %                            BUS-trigger latency)
    %     -> loudspeaker (2nd-order high-pass, SourceGain Pa/V incident at xFront)
    %     -> analytic tube field at position MicPosOfChannel(c) (tim.sim.tubeModel)
    %     -> microphone/channel chain: Sens(c) * Gain(c) * exp(-j w Tau(c)) * HP(fhp(c))
    %     + acoustic noise (independent per mic) + electrical noise
    %   Each channel response is realised as an FIR (frequency sampling,
    %   FirTaps taps) applied with stateful overlap-add.
    %
    %   The "truth" used in tests is obtained with trueResponse(f), which
    %   evaluates the realised FIR responses (and the analytic model) so that
    %   test tolerances are not polluted by FIR design error.

    properties
        Fs double = 16384
        Geometry struct
        Environment struct
        Sample struct = struct('type', 'thin', 'Zt', 200)
        Termination struct = struct('R', 0, 'x', 1.0)
        MicPosOfChannel double = [1 2 3 4]    % position index heard by DAQ channel c
        Sens double = [11.2 11.5 10.9 11.3] * 1e-3      % true V/Pa
        Gain double = [1 1.02 0.985 1.03]               % complex-chain gain mismatch
        Tau double = [0 2.0e-6 -1.5e-6 3.0e-6]           % s, phase mismatch
        Fhp double = [3.0 3.6 2.6 4.2]                  % Hz, chain high-pass corners
        SourceGain double = 4                           % Pa (incident amplitude) per V
        SpeakerFhp double = 60                          % Hz
        NoisePa double = 2e-3                           % rms acoustic noise per mic
        NoiseV double = 2e-6                            % rms electrical noise
        GenClockPpm double = 35
        TriggerLatency double = [0.005 0.030]           % s, uniform random
        SweepStepTime double = 1e-3                     % s, stepped sweep emulation
        BulkDelay double = 0.1     % s, loudspeaker -> x=xFront. Must exceed the precursor
                                   % length of the frequency-sampled responses: with 4 ms
                                   % the wrapped precursor caused 0.4 % FIR error (diagnosed).
        FirTaps double = 16384
        LossModel char = 'iso10534'
        Seed double = 1
    end
    properties (SetAccess = private)
        SampleCounter double = 0
        Gen struct = struct('OUTP', 0, 'FUNC', 'SIN', 'FREQ', 1e3, 'VOLT', 0.1, ...
            'FREQ_STAR', 100, 'FREQ_STOP', 1e3, 'SWE_SPAC', 'LIN', 'SWE_TIME', 1, 'SWE_STAT', 0, 'TRIG_SOUR', 'IMM')
        SweepStartSample double = NaN
        TriggerLog double = zeros(0, 1)    % DAQ sample index of every sweep start
        H double                           % FIR taps (FirTaps x 4)
        Dirty logical = true
    end
    properties (Access = private)
        Phase double = 0
        Tail double
        Rng
    end

    methods
        function obj = SimulatedRig(cfg)
            if nargin >= 1 && ~isempty(cfg)
                obj.Fs = cfg.acquisition.sampleRate;
                obj.Geometry = cfg.geometry;
                obj.Environment = cfg.environment;
                mp = zeros(1, 4); mp([cfg.mics.channel]) = [cfg.mics.position];
                obj.MicPosOfChannel = mp;
                if isfield(cfg, 'simulation')
                    s = cfg.simulation;
                    f = fieldnames(s);
                    for i = 1:numel(f)
                        if isprop(obj, f{i}), obj.(f{i}) = s.(f{i}); end
                    end
                end
            end
            obj.Rng = RandStream('mt19937ar', 'Seed', obj.Seed);
        end

        function set.Sample(obj, v), obj.Sample = v; obj.Dirty = true; end %#ok<MCSUP>
        function set.Termination(obj, v), obj.Termination = v; obj.Dirty = true; end %#ok<MCSUP>
        function set.MicPosOfChannel(obj, v), obj.MicPosOfChannel = v; obj.Dirty = true; end %#ok<MCSUP>

        %% ---- generator coupling -----------------------------------------
        function setGeneratorState(obj, s)
            obj.Gen = s;
        end
        function generatorTrigger(obj)
            lat = obj.TriggerLatency(1) + diff(obj.TriggerLatency) * rand(obj.Rng);
            obj.SweepStartSample = obj.SampleCounter + round(lat * obj.Fs);
            obj.TriggerLog(end+1, 1) = obj.SweepStartSample;
        end

        %% ---- signal generation ------------------------------------------
        function v = generate(obj, n)
            %GENERATE Next n samples (n x 4) of microphone output voltage.
            if obj.Dirty, obj.design(); end
            x = obj.sourceSignal(n);
            L = size(obj.H, 1);
            nfft = 2^nextpow2(n + L - 1);
            Y = ifft(fft(x, nfft) .* fft(obj.H, nfft), 'symmetric');
            acc = Y(1:n + L - 1, :);
            acc(1:L-1, :) = acc(1:L-1, :) + obj.Tail;
            v = acc(1:n, :);
            obj.Tail = acc(n+1:end, :);
            noise = obj.NoisePa * obj.Rng.randn(n, 4) .* obj.Sens + obj.NoiseV * obj.Rng.randn(n, 4);
            v = v + noise;
            obj.SampleCounter = obj.SampleCounter + n;
        end

        function reset(obj)
            obj.SampleCounter = 0; obj.Phase = 0; obj.SweepStartSample = NaN;
            obj.TriggerLog = zeros(0, 1); obj.Dirty = true;
            obj.Rng = RandStream('mt19937ar', 'Seed', obj.Seed);
        end

        %% ---- ground truth --------------------------------------------------
        function t = trueResponse(obj, f)
            %TRUERESPONSE Realised responses at frequencies f (column).
            %   t.G      (Nf x 4) channel output volts per generator volt (FIR)
            %   t.chain  (Nf x 4) microphone-chain response V/Pa (analytic)
            %   t.p      (Nf x 4) analytic pressure at the 4 POSITIONS per unit incident wave
            %   t.model  tubeModel output (R, tau, Zt, boundary values ...)
            if obj.Dirty, obj.design(); end
            f = f(:);
            t.G = zeros(numel(f), 4);
            for c = 1:4
                t.G(:, c) = freqz(obj.H(:, c), 1, f, obj.Fs);
            end
            t.chain = obj.chainResponse(f);
            t.model = tim.sim.tubeModel(f, obj.Geometry, obj.Environment, obj.Sample, obj.Termination, ...
                'lossModel', obj.LossModel);
            t.p = t.model.p;
        end

        function C = chainResponse(obj, f)
            f = f(:);
            C = zeros(numel(f), 4);
            for c = 1:4
                s = 1j * f / obj.Fhp(c);
                C(:, c) = obj.Sens(c) * obj.Gain(c) * exp(-2j * pi * f * obj.Tau(c)) .* s ./ (1 + s);
            end
        end
    end

    methods (Access = private)
        function design(obj)
            N = obj.FirTaps;
            f = (0:N/2).' * obj.Fs / N;
            fp = f; fp(1) = f(2) * 1e-3;    % avoid f = 0 in the tube model
            m = tim.sim.tubeModel(fp, obj.Geometry, obj.Environment, obj.Sample, obj.Termination, ...
                'lossModel', obj.LossModel);
            s = 1j * fp / obj.SpeakerFhp;
            spk = obj.SourceGain * (s.^2 ./ (1 + 1.414 * s + s.^2));
            delay = exp(-2j * pi * fp * obj.BulkDelay);
            C = obj.chainResponse(fp);
            G = zeros(numel(f), 4);
            for c = 1:4
                G(:, c) = spk .* delay .* m.p(:, obj.MicPosOfChannel(c)) .* C(:, c);
            end
            G(1, :) = 0; G(end, :) = real(G(end, :));
            full = [G; conj(G(end-1:-1:2, :))];
            h = real(ifft(full));
            % gentle taper of the last 5 % (wrap-around of residual ringing)
            nt = round(0.05 * N);
            w = ones(N, 1); w(end-nt+1:end) = 0.5 * (1 + cos(pi * (1:nt).' / nt));
            obj.H = h .* w;
            obj.Tail = zeros(N - 1, 4);
            obj.Dirty = false;
        end

        function x = sourceSignal(obj, n)
            g = obj.Gen;
            idx = obj.SampleCounter + (0:n-1).';
            k = 1 + obj.GenClockPpm * 1e-6;          % generator clock vs DAQ clock
            amp = g.VOLT / 2;
            if strncmpi(g.FUNC, 'NOI', 3)
                x = (g.VOLT / 6.6) * obj.Rng.randn(n, 1);   % ~Vpp/6.6 rms (crest ~3.3)
                if ~g.OUTP, x(:) = 0; end
                return
            end
            finst = g.FREQ * ones(n, 1);
            if g.SWE_STAT
                finst(:) = g.FREQ_STAR;
                if ~isnan(obj.SweepStartSample)
                    tau = (idx - obj.SweepStartSample) / obj.Fs * k;
                    in = tau >= 0 & tau < g.SWE_TIME;
                    tq = floor(tau(in) / obj.SweepStepTime) * obj.SweepStepTime;
                    if strncmpi(g.SWE_SPAC, 'LOG', 3)
                        finst(in) = g.FREQ_STAR * (g.FREQ_STOP / g.FREQ_STAR) .^ (tq / g.SWE_TIME);
                    else
                        finst(in) = g.FREQ_STAR + (g.FREQ_STOP - g.FREQ_STAR) * tq / g.SWE_TIME;
                    end
                    if tau(end) >= g.SWE_TIME, obj.SweepStartSample = NaN; end
                end
            end
            ph = obj.Phase + 2 * pi * cumsum(finst * k) / obj.Fs;
            obj.Phase = mod(ph(end), 2 * pi);
            x = amp * sin(ph);
            if ~g.OUTP, x(:) = 0; end
        end
    end
end
