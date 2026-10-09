classdef TestDsp < matlab.unittest.TestCase
    %TESTDSP Spectral estimators: sine fit, swept sine, Welch, cross-method (Test B/G synthetic).

    properties
        cfg
    end

    methods (TestMethodSetup)
        function setup(tc)
            c = tim.app.defaultConfig();
            c.geometry = c.simulation.Geometry;
            tc.cfg = c;
        end
    end

    methods
        function rig = makeRig(tc, noisePa)
            rig = tim.sim.SimulatedRig(tc.cfg);
            rig.NoisePa = noisePa;
        end

        function x = record(~, rig, gen, n, triggerAt)
            % drive the rig directly (no instruments) - for estimator tests
            rig.setGeneratorState(gen);
            x = zeros(n, 4);
            blk = 4096; i = 0;
            while i < n
                m = min(blk, n - i);
                if nargin >= 5 && i <= triggerAt && triggerAt < i + m
                    x(i+1:i+m, :) = rig.generate(m);   % trigger granularity = block
                    rig.generatorTrigger();
                else
                    x(i+1:i+m, :) = rig.generate(m);
                end
                i = i + m;
            end
        end

        function g = genState(~, varargin)
            g = struct('OUTP', 1, 'FUNC', 'SIN', 'FREQ', 1000, 'VOLT', 0.2, 'FREQ_STAR', 80, ...
                'FREQ_STOP', 5500, 'SWE_SPAC', 'LOG', 'SWE_TIME', 3, 'SWE_STAT', 0, 'TRIG_SOUR', 'BUS');
            for i = 1:2:numel(varargin), g.(varargin{i}) = varargin{i+1}; end
        end
    end

    methods (Test)
        function sineFitWithClockOffset(tc)
            fs = 16384; N = 8192; t = (0:N-1).' / fs;
            f0 = 1000 * (1 + 80e-6);                       % 80 ppm generator offset
            a = [1, 0.8 * exp(1j * 0.3), 1.2 * exp(-1j * 1.1)];
            rng(1);
            x = real(exp(2j * pi * f0 * t) .* a) + 1e-3 * randn(N, 3) + [0.1 0 -0.05];
            r = tim.dsp.sineResponse(x, fs, 1000, struct('nBlocks', 4));
            tc.verifyEqual(r.f, f0, 'RelTol', 1e-7);
            % noise 1e-3 rms on 2048-sample blocks: amplitude std ~ 1e-3*sqrt(2/8192)
            tc.verifyEqual(r.H, a / a(1), 'AbsTol', 1e-4);
            tc.verifyGreaterThan(min(r.snr_dB), 50);
        end

        function sineFitSnrUnbiased(tc)
            % formula review dsp-1/dsp-2: snr_dB = (|a|^2/2) / (G fs/L) with the
            % one-sided noise PSD G = 2 s^2/fs (white noise of variance s^2) and
            % L = N/nBlocks: the noise power of the L-sample LS sine fit is
            % E|da|^2/2 = 2 s^2/L = G fs/L. Defined value for A = 0.01, s = 1e-3:
            % N = 8192 (one Welch segment), L = 2048 -> A^2 L/(4 s^2) = 47.09 dB;
            % N = 16384, L = 4096 -> 50.10 dB. The former estimate was 4.6 / 3.5 dB
            % high (factor 1/2 on G + median of an unaveraged periodogram).
            fs = 16384; A = 0.01; s = 1e-3; f0 = 1000.3; nT = 60;
            rs = RandStream('mt19937ar', 'Seed', 17);
            for N = [8192 16384]
                L = N / 4; t = (0:N-1).' / fs;
                snr = zeros(nT, 1);
                for i = 1:nT
                    x = A * cos(2 * pi * f0 * t + 0.3) + s * randn(rs, N, 1);
                    r = tim.dsp.sineResponse([x x], fs, 1000, struct('nBlocks', 4));
                    snr(i) = r.snr_dB(2);
                end
                defined = 10 * log10(A^2 * L / (4 * s^2));
                % std of one estimate ~ 0.6 dB (~90 correlated band bins) -> mean of 60 to +-0.1 dB;
                % measured bias +0.08 / +0.01 dB (200 runs, review check)
                tc.verifyEqual(mean(snr), defined, 'AbsTol', 0.25, sprintf('N = %d', N));
            end
            % a stray line 50 Hz from the tone (-14 dB) must not raise the SNR
            % (it is trimmed from the noise band; single estimate, std ~0.6 dB;
            % the former median-of-G/2 estimate was +4.6 dB)
            N = 8192; t = (0:N-1).' / fs;
            snr = zeros(10, 1);
            for i = 1:10
                x = A * cos(2 * pi * f0 * t) + 0.2 * A * cos(2 * pi * (f0 + 50) * t) + s * randn(rs, N, 1);
                r = tim.dsp.sineResponse(x, fs, 1000, struct('nBlocks', 4));
                snr(i) = r.snr_dB;
            end
            tc.verifyLessThan(mean(snr), 10 * log10(A^2 * 2048 / (4 * s^2)) + 0.5);
        end

        function sweepEstimatorMatchesRealisedResponse(tc)
            % Stepped (non-ideal) log sweep, generator clock +35 ppm, random
            % trigger latency, start-frequency tone before/after the sweep.
            rig = tc.makeRig(2e-3);
            fs = rig.Fs;
            g = tc.genState('SWE_STAT', 1);
            recs = cell(1, 2);
            for r = 1:2
                g.OUTP = 0; rig.setGeneratorState(g);
                rig.generate(fs);                                 % let previous ring-down decay
                pre = rig.generate(fs);                           % 1 s silence (pre-roll)
                g.OUTP = 1;
                x = tc.record(rig, g, round(4.2 * fs), 0);
                recs{r} = [pre; x];
            end
            sp = tim.dsp.sweepResponse(recs, fs, struct('fRange', [120 4500], 'df', 2, 'preRoll', 1, ...
                'excitationBand', [80 5500]));
            t = rig.trueResponse(sp.f);
            Htrue = t.G ./ t.G(:, 1);
            rel = abs(sp.H(:, 2:4) ./ Htrue(:, 2:4) - 1);
            % noise floor: 2 mPa vs ~0.4 Pa incident => per-band relative error
            % ~ 1/sqrt(SNR*nAvg); require median < 0.5 %, 99th pct < 3 %
            tc.verifyLessThan(median(rel(:)), 5e-3);
            tc.verifyLessThan(prctile(rel(:), 99), 3e-2);
            tc.verifyTrue(all([sp.excitation.detected]));
            % reported quality must be consistent with the true error
            good = all(sp.coherence(:, 2:4) > 0.99, 2) & all(sp.snr_dB(:, 2:4) > 30, 2);
            tc.verifyLessThan(max(rel(good, :), [], 'all'), 3e-2);
        end

        function sweepIndependentOfExcitationWaveform(tc)
            % The same tube measured with a LINEAR sweep and with noise gives
            % the same relative responses (excitation-independence).
            rig = tc.makeRig(0);       % noise-free -> only estimator error remains
            rig.NoiseV = 0;
            fs = rig.Fs;
            g = tc.genState('SWE_STAT', 1, 'SWE_SPAC', 'LIN');
            x = tc.record(rig, g, round(4.5 * fs), 0);
            sp = tim.dsp.sweepResponse({x}, fs, struct('fRange', [150 4500], 'df', 4, 'preRoll', 0, ...
                'excitationBand', [80 5500]));
            t = rig.trueResponse(sp.f);
            Htrue = t.G ./ t.G(:, 1);
            tc.verifyLessThan(prctile(abs(sp.H(:, 2:4) ./ Htrue(:, 2:4) - 1), 99, 'all'), 2e-3);
        end

        function steppedVsSweep(tc)
            % Test G (synthetic): cross-method comparison at selected frequencies
            rig = tc.makeRig(2e-3);
            fs = rig.Fs;
            fr = [150 400 1000 2500 4000];
            Hs = zeros(numel(fr), 4);
            for i = 1:numel(fr)
                g = tc.genState('FREQ', fr(i));
                x = tc.record(rig, g, round(0.8 * fs));
                r = tim.dsp.sineResponse(x(round(0.3 * fs):end, :), fs, fr(i));
                Hs(i, :) = r.H;
            end
            rig.reset();
            g = tc.genState('SWE_STAT', 1, 'OUTP', 0); rig.setGeneratorState(g); pre = rig.generate(fs);
            g.OUTP = 1;
            x = [pre; tc.record(rig, g, round(4.2 * fs), 0)];
            sp = tim.dsp.sweepResponse({x}, fs, struct('fGrid', fr(:), 'preRoll', 1, 'excitationBand', [80 5500]));
            d = abs(sp.H(:, 2:4) ./ Hs(:, 2:4) - 1);
            tc.verifyLessThan(max(d(:)), 1e-2);
            t = rig.trueResponse(fr(:)); Ht = t.G ./ t.G(:, 1);
            tc.verifyLessThan(max(abs(Hs(:, 2:4) ./ Ht(:, 2:4) - 1), [], 'all'), 5e-3);
        end

        function welchNoiseExcitation(tc)
            rig = tc.makeRig(1e-3);
            fs = rig.Fs;
            g = tc.genState('FUNC', 'NOIS', 'VOLT', 0.5);
            x = tc.record(rig, g, 30 * fs);
            w = tim.dsp.welchResponse(x, fs, struct('nfft', 8192, 'fGrid', (200:20:4400).'));
            t = rig.trueResponse(w.f); Ht = t.G ./ t.G(:, 1);
            rel = abs(w.H(:, 2:4) ./ Ht(:, 2:4) - 1);
            tc.verifyLessThan(median(rel(:)), 2e-2);
        end

        function excitationDetection(tc)
            fs = 16384; rng(3);
            x = 1e-4 * randn(5 * fs, 1);
            t = (0:2*fs-1).' / fs;
            x(fs + (1:2*fs)) = x(fs + (1:2*fs)) + 0.1 * sin(2 * pi * 500 * t);
            ex = tim.dsp.detectExcitation(x, fs, [100 2000], 12, 1);
            tc.verifyTrue(ex.detected);
            tc.verifyEqual(ex.start_s, 1, 'AbsTol', 0.02);
            tc.verifyEqual(ex.duration_s, 2, 'AbsTol', 0.04);
        end

        function sweepLawDiagnostic(tc)
            rig = tc.makeRig(2e-3);
            fs = rig.Fs;
            g = tc.genState('SWE_STAT', 1, 'OUTP', 0); rig.setGeneratorState(g); pre = rig.generate(fs);
            g.OUTP = 1;
            x = [pre; tc.record(rig, g, round(4 * fs), 0)];
            s = tim.dsp.estimateSweepLaw(x(:, 1), fs, 80, 5500, 'LOG', 3);
            % generator clock +35 ppm and 1 ms stepping: duration within 2 %;
            % acoustic start = 1 s pre + trigger after first block (0.25 s)
            % + latency (5..30 ms) + rig bulk delay (0.1 s), +-1 STFT hop
            tc.verifyEqual(s.duration_s, 3, 'RelTol', 0.02);
            t0 = 1 + 4096 / fs + rig.BulkDelay;
            tc.verifyGreaterThan(s.startTime_s, t0 + 0.005 - 0.02);
            tc.verifyLessThan(s.startTime_s, t0 + 0.030 + 0.02);
        end
    end
end
