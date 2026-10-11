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

        function sweepGateExcludesSwitchingTransients(tc)
            % user request 2026-10-09: the output relay of the 33220A clicks when
            % the output is switched on (before the sweep) and off (after it).
            % The sweep gate cuts the analysis window to the sweep itself. Test
            % clicks that do NOT follow the tube response (independent per
            % channel, e.g. electrical) bias H when included; with the gate H
            % stays at the true response.
            rig = tc.makeRig(0); rig.NoiseV = 0;
            fs = rig.Fs;
            g = tc.genState('SWE_STAT', 1, 'OUTP', 0); rig.setGeneratorState(g);
            pre = rig.generate(fs);                                  % 1 s silence
            g.OUTP = 1;
            x = [pre; tc.record(rig, g, round(4.6 * fs), 0)];        % tone, then the sweep (3 s)
            ts = rig.TriggerLog(end) / fs + rig.BulkDelay;           % acoustic sweep start in x
            sw = struct('fStart', 80, 'fStop', 5500, 'duration', 3, 'spacing', 'LOG');
            rng(7);
            n = size(x, 1); t = (0:n - 1).' / fs;
            a = 3 * rms(x(round((ts + 1) * fs):round((ts + 2) * fs), 1));
            for tc0 = [ts - 0.1, ts + 3.04]                          % output on / output off (as measured)
                k = t >= tc0;
                x(k, :) = x(k, :) + a * [1 0.5 2 1.5] .* exp(-(t(k) - tc0) / 0.004) .* randn(nnz(k), 4);
            end
            o = struct('fRange', [120 4500], 'df', 2, 'preRoll', 1, 'excitationBand', [80 5500], 'sweep', sw);
            sp = tim.dsp.sweepResponse({x}, fs, o);
            o.excludeSwitching = false;
            sp0 = tim.dsp.sweepResponse({x}, fs, o);
            tr = rig.trueResponse(sp.f); Ht = tr.G ./ tr.G(:, 1);
            e = abs(sp.H(:, 2:4) ./ Ht(:, 2:4) - 1); e0 = abs(sp0.H(:, 2:4) ./ Ht(:, 2:4) - 1);
            tc.verifyTrue(sp.excitation.gated, 'sweep found');
            tc.verifyEqual(sp.excitation.sweepStart_s, ts, 'AbsTol', 0.005);
            tc.verifyEqual(sp.excitation.sweepDuration_s, 3, 'RelTol', 1e-3);
            tc.verifyLessThanOrEqual(sp.excitation.gate_s(4), sp.excitation.sweepStart_s + sp.excitation.sweepDuration_s + 1e-9, ...
                'window ends at the end of the sweep (before the off transient)');
            tc.verifyGreaterThanOrEqual(sp.excitation.gate_s(1), sp.excitation.sweepStart_s - 1e-9, ...
                'window starts at the sweep (after the on transient)');
            tc.verifyLessThan(prctile(e(:), 99), 3e-3, 'gated: true response');
            tc.verifyGreaterThan(prctile(e0(:), 99), 10 * prctile(e(:), 99), 'without the gate the clicks bias H');
            tc.verifyFalse(sp0.excitation.gated);
            % not found (wrong programmed duration): previous window and a warning
            o.excludeSwitching = true; o.sweep.duration = 5;
            sp2 = tim.dsp.sweepResponse({x}, fs, o);
            tc.verifyFalse(sp2.excitation.gated);
            tc.verifyTrue(any(contains(sp2.warnings, 'not excluded')));
        end

        function sweepGateWarnsWithoutMarginBeyondTheBand(tc)
            % audit 2026-10-11: a sweep that does not reach far enough beyond the
            % analysis band has no room for a gate ramp at that end; since the
            % owner's decision of 2026-10-11 that end gets another window edge,
            % recorded in excitation.gateEnds, and a warning names it and the
            % margin (lower end: from the detected start; upper end: the gate's
            % ring-down margin past the sweep end)
            rig = tc.makeRig(2e-3);
            fs = rig.Fs;
            cases = {80 5500 {'gate', 'gate'}; 120 4500 {'detected start', 'ring-down margin'}; ...
                109 5500 {'detected start', 'gate'}; 80 4600 {'gate', 'ring-down margin'}};
            for i = 1:size(cases, 1)
                [f1, f2, ends] = cases{i, :};
                rig.reset();
                g = tc.genState('SWE_STAT', 1, 'OUTP', 0, 'FREQ_STAR', f1, 'FREQ_STOP', f2);
                rig.setGeneratorState(g);
                pre = rig.generate(fs);
                g.OUTP = 1;
                x = [pre; tc.record(rig, g, round(4.6 * fs), 0)];
                sw = struct('fStart', f1, 'fStop', f2, 'duration', 3, 'spacing', 'LOG');
                sp = tim.dsp.sweepResponse({x}, fs, struct('fRange', [120 4500], 'df', 2, 'preRoll', 1, ...
                    'excitationBand', [f1 f2], 'sweep', sw));
                what = sprintf('sweep %g-%g Hz', f1, f2);
                tc.assertTrue(sp.excitation.gated, [what ' found']);
                tc.verifyEqual(sp.excitation.gateEnds, ends, what);
                w = sp.warnings(contains(sp.warnings, 'too close to the analysis band'));
                tc.verifyEqual(numel(w), double(~isequal(ends, {'gate', 'gate'})), what);
                if isempty(w), continue; end
                tc.verifyEqual(contains(w{1}, 'starts at the detected excitation'), strcmp(ends{1}, 'detected start'), what);
                tc.verifyEqual(contains(w{1}, 'extended past the end of the sweep by the gate''s ring-down margin'), ...
                    strcmp(ends{2}, 'ring-down margin'), what);
                t0 = sp.excitation.sweepStart_s; T = sp.excitation.sweepDuration_s; gt = sp.excitation.gate_s;
                if strcmp(ends{1}, 'detected start')
                    tc.verifyEqual(gt(2), min(sp.excitation.start_s, t0), 'AbsTol', 1e-9, [what ': window from the detected start']);
                end
                if strcmp(ends{2}, 'ring-down margin')
                    % 1 up to t(1.1 f_hi), 0 at t(1.5 f_hi) on the continued sweep law
                    tl = @(f) t0 + T * log(f / f1) / log(f2 / f1);
                    tc.verifyEqual(gt(3:4), [tl(1.1 * 4501) tl(1.5 * 4501)], 'AbsTol', 1e-9, [what ': ring-down margin']);
                end
            end
        end

        function sweepGateWithoutMarginKeepsTheEdgeLines(tc)
            % owner decision 2026-10-11 (audit: up to 58 % H error at |R_term|
            % 0.9 with the 10 ms gate ramps inside the band): a sweep without the
            % margin at an end is analysed from the detected start / with the
            % ring-down margin past the sweep end there, so the lines near the
            % band edges keep their accuracy. Session-like records: the output
            % is switched off just after the sweep.
            c = tc.cfg;
            c.simulation.Termination = struct('R', 0.9, 'x', 0.6);
            rig = tim.sim.SimulatedRig(c); rig.NoisePa = 2e-5; rig.NoiseV = 2e-8;
            fs = rig.Fs;
            for r = [120 4500; 109 5500; 80 4600]'
                rig.reset();
                g = tc.genState('SWE_STAT', 1, 'OUTP', 0, 'FREQ_STAR', r(1), 'FREQ_STOP', r(2));
                rig.setGeneratorState(g);
                pre = rig.generate(fs);
                g.OUTP = 1;
                on = tc.record(rig, g, round(3.4 * fs), 0);          % trigger after the first block, sweep 3 s
                g.OUTP = 0;
                off = tc.record(rig, g, round(1.2 * fs));            % output off, ring-down
                x = [pre; on; off];
                sw = struct('fStart', r(1), 'fStop', r(2), 'duration', 3, 'spacing', 'LOG');
                sp = tim.dsp.sweepResponse({x}, fs, struct('fRange', [120 4500], 'df', 2, 'preRoll', 1, ...
                    'excitationBand', r', 'ringDown', 0.5, 'sweep', sw));
                tc.assertTrue(sp.excitation.gated, sprintf('sweep %g-%g Hz found', r));
                tr = rig.trueResponse(sp.f); Ht = tr.G ./ tr.G(:, 1);
                e = abs(sp.H(:, 2:4) ./ Ht(:, 2:4) - 1);
                % measured 0.6-0.9 % (as without the gate); the gate gave 58 / 12 / 7.9 %
                tc.verifyLessThan(max(e(:)), 0.03, sprintf('sweep %g-%g Hz: max |H/H_true - 1|', r));
            end
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
