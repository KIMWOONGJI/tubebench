classdef TestSettledCheck < matlab.unittest.TestCase
    %TESTSETTLEDCHECK Settled check of the stepped sine (1.6.0, owner decision 2026-11-04).
    %
    %   A transient that has not decayed when the record of a step begins
    %   changes the ratio of the channels from block to block. Per step and
    %   channel tim.dsp.sineResponse returns the drift |H_last - H_first| / |H|
    %   and its standard deviation from noise alone (driftSigma, from the
    %   per-block SNR with the noise of the pre-roll, output off, when the
    %   caller gives it - review 2026-11-05: the residual of the step holds the
    %   transient itself); tim.app.processMeasurement keeps the excess over four
    %   standard deviations (the worst repetition, res.spectra.settleDrift) and
    %   tim.acoustics.validityMasks flags notSettled above
    %   analysis.settleDriftMax (a quality flag: the line is not valid; R only
    %   through M1/M2). Checked: synthetic records (a decaying transient, the
    %   noise statistic, the processing path with repetitions, one block, the
    %   rule of R) and the virtual rig: the default timing flags no step (the
    %   33220A / LAN-XI mocks and the combined device), a settling of 0 s - the
    %   first 80 ms block ends before the rig's 0.1 s acoustic delay - is
    %   flagged and loses its valid lines; the Validity view, results.csv and
    %   spectra.csv, the configurable limit, no flag for a sweep.
    %
    %   One switching calibration, one stepped sine with the provoked transient
    %   and the same steps with the default timing are made once for the class.
    %   Simulation: the tests verify software behaviour, not physical accuracy.

    properties
        cfg         % default configuration, the measured geometry = the simulated one
        cal         % switching calibration of the virtual tube
        tmp
        bulkDelay   % acoustic delay of the virtual rig, generator -> front face [s]
        mShort      % stepped sine, 8 steps 200-4000 Hz, settling 0 s, four 80 ms blocks
        rShort      % its result with the calibration
        rSettled    % the same 8 steps with the default timing, with the calibration
    end

    methods (TestClassSetup)
        function calibrateAndMeasure(tc)
            f = tc.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            tc.tmp = f.Folder;
            c = tim.app.defaultConfig();
            c.geometry = c.simulation.Geometry;            % simulated "measured" geometry
            c.output.dataDir = fullfile(tc.tmp, 'data');
            c.output.calibrationDir = fullfile(tc.tmp, 'cal');
            c.excitation.sweep.duration = 3;
            c.excitation.sweep.repetitions = 2;
            c.calibration.repeatConfigI = false;
            tc.cfg = c;
            s = tim.app.MeasurementSession(c);
            cleanup = onCleanup(@() s.close());
            s.connect(); s.prepareAcquisition();
            tc.cal = tim.app.runCalibration(s);
            clear cleanup
            % the measurements in a new session (the calibration moved the
            % microphones of its rig). The provoked transient: no settling and a
            % record of four 80 ms blocks. The rig delays the sound by BulkDelay
            % (0.1 s) from the generator to the front face, so block 1 of every
            % step still holds the step before (step 1: silence) and the new tone
            % arrives during block 2
            cs = TestSettledCheck.shortSettling(c);
            s = tim.app.MeasurementSession(cs);
            cleanup = onCleanup(@() s.close());
            s.connect(); s.prepareAcquisition();
            tc.bulkDelay = s.Rig.BulkDelay;
            tc.mShort = s.measure('stepped');
            tc.rShort = tim.app.processMeasurement(tc.mShort, cs, tc.cal);
            % the same steps with the default timing (settle max(0.2 s, 50 cycles))
            cSettled = c;
            cSettled.excitation.stepped.fStart = 200; cSettled.excitation.stepped.fStop = 4000;
            cSettled.excitation.stepped.nPoints = 8;
            ex = s.Cfg.excitation; ex.stepped = cSettled.excitation.stepped;
            s.setExcitation(ex);
            tc.rSettled = tim.app.processMeasurement(s.measure('stepped'), cSettled, tc.cal);
            clear cleanup
        end
    end

    methods
        function s = session(tc, c)
            % a connected session of the virtual tube (a new rig)
            s = tim.app.MeasurementSession(c);
            tc.addTeardown(@() s.close());
            s.connect(); s.prepareAcquisition();
        end
    end

    methods (Static)
        function c = shortSettling(c)
            % 8 steps 200-4000 Hz without settling, 0.32 s records in 4 blocks
            st = c.excitation.stepped;
            st.fStart = 200; st.fStop = 4000; st.nPoints = 8;
            st.settleTime = 0; st.settleCycles = 0;
            st.recordTime = 0.32; st.recordCycles = 0; st.nBlocks = 4;
            c.excitation.stepped = st;
            c.excitation.mode = 'stepped';
        end

        function [x, t] = tones(fs, f0, T, g, sigma, seed)
            % steady tones of the amplitudes g (fixed phases) in white noise of
            % standard deviation sigma, one column per channel
            N = round(T * fs); t = (0:N - 1).' / fs;
            ph = [0 0.3 -0.7 1.1];
            x = cos(2 * pi * f0 * t + ph(1:numel(g))) .* g;
            rs = RandStream('mt19937ar', 'Seed', seed);
            x = x + sigma * randn(rs, N, numel(g));
        end

        function meas = syntheticStepped(fs, freqs, T, nBlocks, transient, pre)
            % stepped measurement of steady tones (white noise 1 mV), no settling,
            % one record per cell of transient: transient{r} lists [step channel]
            % rows whose tone carries a decaying transient (+20 %, 50 ms) in
            % repetition r. pre [s] (default 0): a pre-roll of noise only before
            % the first step, as a measured record has (events.onSample)
            if nargin < 6, pre = 0; end
            N = round(T * fs); t = (0:N - 1).' / fs; nF = numel(freqs);
            N0 = round(pre * fs);
            g = [1 0.8 1.2 0.6]; ph = [0 0.3 -0.7 1.1];
            nR = numel(transient);
            records = cell(1, nR); events = cell(1, nR);
            for r = 1:nR
                x = zeros(N0 + nF * N, 4);
                tr = transient{r};
                for k = 1:nF
                    y = cos(2 * pi * freqs(k) * t + ph) .* g;
                    for i = 1:size(tr, 1)
                        if tr(i, 1) == k
                            y(:, tr(i, 2)) = y(:, tr(i, 2)) .* (1 + 0.2 * exp(-t / 0.05));
                        end
                    end
                    x(N0 + (k - 1) * N + (1:N), :) = y;
                end
                rs = RandStream('mt19937ar', 'Seed', r);
                records{r} = x + 1e-3 * randn(rs, size(x));
                events{r} = struct('stepStart', N0 + (0:nF - 1) * N, 'freqs', freqs, 'onSample', N0);
            end
            st = struct('frequencies', freqs, 'settleSamples', zeros(1, nF), 'recordSamples', N * ones(1, nF), ...
                'nBlocks', nBlocks, 'repetitions', nR);
            meas = struct('kind', 'stepped', 'timestamp', '2026-11-04 12:00:00', 'fs', fs, 'unit', 'V', ...
                'records', {records}, 'events', {events}, 'settings', st);
        end

        function cal = unitCalibration()
            % C = 1 everywhere (the synthetic channels need no correction)
            f = (100:2:5000).';
            cal = struct('type', 'tim.complexChannelCalibration', 'version', 'CAL-UNIT', 'refChannel', 1, ...
                'f', f, 'C', ones(numel(f), 4), 'valid', true(numel(f), 4), 'meta', struct('mode', 'simulation'));
        end
    end

    methods (Test)
        function driftOfADecayingTransient(tc)
            % ch2 carries a transient that decays with 50 ms (+20 % at the start
            % of the record): its ratio to the reference drifts from block 1 to
            % block 4 far beyond the noise; ch3 / ch4 stay within 4 sigma
            fs = 16384; f0 = 500;
            [x0, t] = TestSettledCheck.tones(fs, f0, 0.4, [1 0.8 1.2 0.6], 1e-2, 11);
            env = 1 + 0.2 * exp(-t / 0.05);
            x = x0; x(:, 2) = x(:, 2) .* env;
            r = tim.dsp.sineResponse(x, fs, f0, struct('nBlocks', 4));
            tc.verifySize(r.drift, [1 4]); tc.verifySize(r.driftSigma, [1 4]);
            tc.verifyEqual([r.drift(1) r.driftSigma(1)], [0 0], 'reference channel');
            ex = max(0, r.drift - 4 * r.driftSigma);
            tc.verifyGreaterThan(r.drift(2), 0.05, 'block 1 holds about 9 % more than block 4');
            tc.verifyGreaterThan(ex(2), 0.01, 'flagged at the default limit');
            tc.verifyEqual(ex(3:4), [0 0], 'steady channels: within 4 sigma');
            % the formulas of the help text (docs/theory.md, section 5 step 7)
            Hb = r.Hblocks;
            tc.verifyEqual(r.drift(2:4), abs(Hb(4, 2:4) - Hb(1, 2:4)) ./ abs(r.H(2:4)), 'RelTol', 1e-12);
            tc.verifyEqual(r.driftSigma(2:4), sqrt(2 * (10.^(-r.snr_dB(2:4) / 10) + 10^(-r.snr_dB(1) / 10))), ...
                'RelTol', 1e-12);
            % a change common to all channels (the generator level) cancels in the ratio
            r2 = tim.dsp.sineResponse(x0 .* env, fs, f0, struct('nBlocks', 4));
            tc.verifyEqual(max(0, r2.drift - 4 * r2.driftSigma), zeros(1, 4), 'common transient: not flagged');
            % the transient on the reference channel: every ratio drifts
            z = x0; z(:, 1) = z(:, 1) .* env;
            r3 = tim.dsp.sineResponse(z, fs, f0, struct('nBlocks', 4));
            tc.verifyGreaterThan(r3.drift(2:4) - 4 * r3.driftSigma(2:4), 0.01 * [1 1 1]);
        end

        function abruptChangeJudgedAgainstThePrerollNoise(tc)
            % review 2026-11-05: an abrupt change inside the record (ch2 +1.2 %
            % during the first 30 % of it, then steady) spreads into the noise band
            % of the residual of the fit over the whole record and raises the sigma
            % it is judged against, in proportion to its own size; the noise of the
            % pre-roll (output off, opts.noisePsd) does not hold it, so the drift
            % just above the limit is flagged. Only driftSigma changes
            fs = 16384; f0 = 700; T = 0.4; sigma = 1e-4; jump = 0.012;
            N = round(T * fs); t = (0:N - 1).' / fs;
            y = cos(2 * pi * f0 * t + [0 0.3 -0.7 1.1]) .* [1 0.8 1.2 0.6];
            y(t < 0.3 * T, 2) = (1 + jump) * y(t < 0.3 * T, 2);
            rs = RandStream('mt19937ar', 'Seed', 21);
            x = y + sigma * randn(rs, N, 4);
            x0 = sigma * randn(rs, round(0.5 * fs), 4);          % the pre-roll: noise only
            [G, f] = pwelch(x0, hann(4096, 'periodic'), 2048, 4096, fs);
            r0 = tim.dsp.sineResponse(x, fs, f0, struct('nBlocks', 4));
            r1 = tim.dsp.sineResponse(x, fs, f0, struct('nBlocks', 4, 'noisePsd', struct('f', f, 'G', G)));
            tc.verifyEqual([r1.H r1.drift r1.snr_dB], [r0.H r0.drift r0.snr_dB], 'the estimate itself is the same');
            tc.verifyEqual(r0.driftSnr_dB, r0.snr_dB, 'without a pre-roll: the SNR of the residual');
            % block 1 holds the +1.2 %, block 4 none; |H| holds 0.3 of it
            tc.verifyEqual(r1.drift(2), jump / (1 + 0.3 * jump), 'AbsTol', 5e-4);
            % the noise of the pre-roll: the sigma of the help text with that SNR
            L = floor(N / 4);
            tc.verifyEqual(r1.driftSigma(2:4), sqrt(2 * (10.^(-r1.driftSnr_dB(2:4) / 10) + ...
                10^(-r1.driftSnr_dB(1) / 10))), 'RelTol', 1e-12);
            expected = sqrt(2 * (2 * sigma^2 / L) * (1 / (0.8^2 / 2) + 1 / (1 / 2)));   % white noise, ch2 / ref
            tc.verifyEqual(r1.driftSigma(2), expected, 'RelTol', 0.25, 'the noise alone');
            tc.verifyGreaterThan(r0.driftSigma(2), 5 * r1.driftSigma(2), 'the residual holds the change itself');
            ex1 = max(0, r1.drift - 4 * r1.driftSigma);
            tc.verifyGreaterThan(ex1(2), 0.01, 'flagged at the default limit');
            tc.verifyEqual(ex1([1 3 4]), [0 0 0], 'the steady channels');
            % through tim.app.processMeasurement: a stepped measurement with a
            % pre-roll of 0.5 s (the steps 1 mV noise, as syntheticStepped) takes
            % the noise from there; without it from the residual
            fs = 16384; freqs = [300 600 1200];
            meas = TestSettledCheck.syntheticStepped(fs, freqs, 0.4, 4, {zeros(0, 2)}, 0.5);
            idx = tim.app.steppedSegment(meas, 1, 2);
            first = idx(1:round(0.3 * numel(idx)));
            meas.records{1}(first, 3) = (1 + jump) * meas.records{1}(first, 3);   % ch3 (port M3), step 2
            c = tim.app.defaultConfig(); c.geometry = c.simulation.Geometry;
            calUnit = TestSettledCheck.unitCalibration();
            r = tim.app.processMeasurement(meas, c, calUnit);
            sd = r.spectra.settleDrift; bd = r.spectra.blockDrift;
            tc.verifyGreaterThan(sd(2, 3), 0.01, 'step 2, ch3: flagged');
            tc.verifyEqual(r.analysis.valid.flags.notSettled, [false; true; false]);
            tc.verifyLessThan(max(bd - sd, [], 'all'), 1e-3, 'the excess is the drift up to 4 sigma of the pre-roll');
            m0 = meas;                                                    % the same steps without the pre-roll
            n0 = meas.events{1}.onSample;
            m0.records{1} = meas.records{1}(n0 + 1:end, :);
            m0.events{1}.stepStart = meas.events{1}.stepStart - n0; m0.events{1}.onSample = 0;
            r0 = tim.app.processMeasurement(m0, c, calUnit);
            tc.verifyEqual(r0.spectra.blockDrift, bd, 'AbsTol', 1e-12, 'the same drift');
            tc.verifyLessThan(r0.spectra.settleDrift(2, 3), sd(2, 3), 'the residual: a larger sigma, a smaller excess');
        end

        function noFalseAlarmsOnNoise(tc)
            % steady tones in white noise at a per-block SNR of 25 dB (a little
            % above snrMin_dB 20 of the masks, where the first-order noise model
            % of the ratio holds): the drift over its sigma follows
            % P(drift > z sigma) = exp(-z^2) - never above 4 sigma in 900
            % channel-steps (expected about 1e-4 cases), above 2 sigma in about
            % e^-4 = 1.8 % (the sigma is neither too large nor too small)
            fs = 16384; f0 = 1000; T = 0.2; nb = 4;
            L = floor(round(T * fs) / nb);
            sigma = sqrt(L / (4 * 10^(25 / 10)));      % |a| = 1: SNR = |a|^2 L / (4 sigma^2)
            z = zeros(0, 1);
            for trial = 1:300
                x = TestSettledCheck.tones(fs, f0, T, [1 1 1 1], sigma, trial);
                r = tim.dsp.sineResponse(x, fs, f0, struct('nBlocks', nb));
                z = [z; (r.drift(2:4) ./ r.driftSigma(2:4)).']; %#ok<AGROW>
            end
            tc.assertTrue(all(isfinite(z)));
            tc.verifyEqual(nnz(z > 4), 0, 'no false alarm');
            p2 = mean(z > 2);
            tc.verifyGreaterThan(p2, 0.005, sprintf('P(drift > 2 sigma) = %.3f, expected e^-4', p2));
            tc.verifyLessThan(p2, 0.04, sprintf('P(drift > 2 sigma) = %.3f, expected e^-4', p2));
        end

        function processingKeepsTheWorstRepetition(tc)
            % a synthetic stepped measurement (3 steps, 2 repetitions) through
            % tim.app.processMeasurement: step 2 has a transient on ch3 (port M3)
            % in repetition 2 only, step 3 one on the reference channel ch1 (M1)
            % in repetition 1 only. The worst repetition counts; the flag rejects
            % the line by itself (coherence, SNR and calibration pass); R only
            % where M1/M2 drift
            fs = 16384; freqs = [300 600 1200];
            meas = TestSettledCheck.syntheticStepped(fs, freqs, 0.4, 4, {[3 1], [2 3]});
            c = tim.app.defaultConfig(); c.geometry = c.simulation.Geometry;
            calUnit = TestSettledCheck.unitCalibration();
            r = tim.app.processMeasurement(meas, c, calUnit);
            sd = r.spectra.settleDrift;
            tc.verifySize(sd, [3 4]);
            tc.verifySize(r.spectra.blockDrift, [3 4]);
            tc.verifyEqual(sd(:, 1), zeros(3, 1), 'the reference channel');
            tc.verifyEqual(sd(1, :), zeros(1, 4), 'step 1: steady in both repetitions');
            tc.verifyGreaterThan(sd(2, 3), 0.01, 'step 2: ch3 drifts in repetition 2 (the worst counts)');
            tc.verifyEqual(sd(2, [2 4]), [0 0]);
            tc.verifyGreaterThan(sd(3, 2:4), 0.01 * [1 1 1], 'step 3: a transient of the reference changes every ratio');
            tc.verifyGreaterThan(r.spectra.blockDrift(2, 3), sd(2, 3), 'the drift itself is larger than its excess');
            v = r.analysis.valid;
            tc.verifyEqual(v.flags.notSettled, [false; true; true]);
            tc.verifyEqual(v.upstream.flags.notSettled, [false; false; true], 'R: M1/M2 only (ch3 is in M3)');
            tc.verifyEqual(v.settleDrift, max(sd, [], 2), 'the largest excess over the ports');
            % a quality flag: the other quality criteria pass, the line is rejected by it alone
            tc.verifyFalse(any(v.flags.lowCoherence | v.flags.lowSNR | v.flags.calInvalid));
            tc.verifyEqual(v.qualityOK, [true; false; false]);
            tc.verifyEqual(v.upstream.qualityOK, [true; true; false]);
            tc.verifySubstring(v.summary, 'not settled (drift between the blocks) 2');
            % repetition 1 alone: step 2 has settled there
            m1 = meas; m1.records = m1.records(1); m1.events = m1.events(1);
            r1 = tim.app.processMeasurement(m1, c, calUnit);
            tc.verifyEqual(r1.analysis.valid.flags.notSettled, [false; false; true]);
            % one block: not judged (NaN, also the reference), never flagged
            m0 = TestSettledCheck.syntheticStepped(fs, freqs, 0.4, 1, {[3 1], [2 3]});
            r0 = tim.app.processMeasurement(m0, c, calUnit);
            tc.verifyTrue(all(isnan(r0.spectra.settleDrift(:))), 'one block: NaN');
            tc.verifyEqual(r0.analysis.valid.flags.notSettled, false(3, 1));
            tc.verifyTrue(all(isnan(r0.analysis.valid.settleDrift)));
            x = TestSettledCheck.tones(fs, 500, 0.2, [1 0.8 1.2 0.6], 1e-3, 5);
            o = tim.dsp.sineResponse(x, fs, 500, struct('nBlocks', 1));
            tc.verifyTrue(all(isnan(o.drift)), 'sineResponse: one block');
        end

        function cleanVirtualMeasurementNotFlagged(tc)
            % owner decision 2026-11-04: the default settings (40 steps
            % 120-4500 Hz, settle max(0.2 s, 50 cycles), record max(0.2 s,
            % 100 cycles), 4 blocks) flag no step of a clean simulated measurement
            c = tc.cfg;
            s = tc.session(c);
            m = s.measure('stepped');
            tc.assertEqual(numel(m.settings.frequencies), 40, 'the default steps');
            r = tim.app.processMeasurement(m, c, tc.cal);
            v = r.analysis.valid;
            tc.assertTrue(isfield(v.flags, 'notSettled'), 'a stepped sine has the flag');
            tc.verifyEqual(nnz(v.flags.notSettled), 0, sprintf('largest excess drift %.3g', max(v.settleDrift)));
            tc.verifyTrue(all(isfinite(v.settleDrift)), 'every step judged (4 blocks)');
            tc.verifyLessThan(max(v.settleDrift), c.analysis.settleDriftMax);
            tc.verifyGreaterThan(nnz(v.valid), 0.5 * numel(v.valid), 'valid lines');
        end

        function combinedDeviceNotFlagged(tc)
            % the simulated combined device (shared clock, planned acquisition)
            % with the default timing: no step flagged (12 of the 40 default steps
            % over the same range keep the run short; the timing is the default)
            c = tc.cfg;
            c.generator.driver = 'simcombined'; c.daq.driver = 'simcombined';
            sens = [11.2 11.5 10.9 11.3] * 1e-3;      % the virtual microphones; no TEDS: certificate values
            for i = 1:4, c.mics(i).certificateSensitivity_VperPa = sens(c.mics(i).channel); end
            c.excitation.stepped.nPoints = 12;
            s = tc.session(c);
            r = tim.app.processMeasurement(s.measure('stepped'), c, []);
            v = r.analysis.valid;
            tc.assertTrue(isfield(v.flags, 'notSettled'));
            tc.verifyEqual(nnz(v.flags.notSettled), 0, sprintf('largest excess drift %.3g', max(v.settleDrift)));
            tc.verifyTrue(all(isfinite(v.settleDrift)));
        end

        function shortSettlingFlagged(tc)
            % the provoked transient: no settling, four 80 ms blocks; block 1
            % ends before the sound of the new step reaches the microphones, so
            % the ratios of block 1 and block 4 differ: notSettled at (nearly)
            % every step and no valid line there, while the same steps with the
            % default timing are valid
            tc.assertGreaterThan(tc.bulkDelay, 0.08, 'block 1 lies before the acoustic delay of the rig');
            r = tc.rShort; v = r.analysis.valid; fl = v.flags;
            n = numel(r.analysis.f);
            tc.assertEqual(n, 8);
            tc.assertTrue(isfield(fl, 'notSettled'));
            tc.verifyGreaterThanOrEqual(nnz(fl.notSettled), n - 1, 'flagged at (nearly) every step');
            tc.verifyFalse(any(v.valid(fl.notSettled)), 'a step that has not settled is never valid');
            tc.verifyFalse(any(v.qualityOK(fl.notSettled)), 'a quality flag');
            tc.verifyFalse(any(v.validR & v.upstream.flags.notSettled), 'R: rejected through M1/M2');
            tc.verifyGreaterThan(min(v.settleDrift(fl.notSettled)), tc.cfg.analysis.settleDriftMax);
            % the noise of the drift comes from the pre-roll (review 2026-11-05),
            % which the arriving tone cannot raise: the excess is the drift up to
            % four noise standard deviations, not a share of it
            tc.verifyLessThan(max(r.spectra.blockDrift - r.spectra.settleDrift, [], 'all'), 0.02);
            % the check sees what the coherence and the SNR do not
            tc.verifyGreaterThan(nnz(fl.notSettled & ~fl.lowCoherence & ~fl.lowSNR), 0, ...
                'flagged steps that pass the coherence and the SNR');
            % the same steps settled: not flagged, valid lines - lost without settling
            vs = tc.rSettled.analysis.valid;
            tc.verifyEqual(nnz(vs.flags.notSettled), 0, 'default timing');
            tc.verifyGreaterThanOrEqual(nnz(vs.valid), 4, 'the settled steps are valid');
            tc.verifyLessThanOrEqual(nnz(v.valid), n - nnz(fl.notSettled));
            tc.verifyLessThan(nnz(v.valid), nnz(vs.valid), 'valid lines lost by the short settling');
            % Validity view: the row after "low SNR", red at the flagged steps
            fig = figure('Visible', 'off'); tc.addTeardown(@() delete(fig));
            ax = axes(fig);
            info = tim.plots.validity(ax, r);
            ticks = cellstr(ax.YTickLabel);
            i = find(strcmp(ticks, 'Rejected: not settled'));
            tc.assertNumElements(i, 1, 'the row of the settled check');
            tc.verifyEqual(ticks{i - 1}, 'Rejected: low SNR', 'after the SNR row');
            red = info.lines(i);
            tc.verifyEqual(red.MarkerFaceColor, tim.gui.palette().fail);
            tc.verifyEqual(isfinite(red.XData(:)), fl.notSettled, 'red at the steps that have not settled');
            d = info.summary.data;
            k = find(strcmp(d(:, 1), 'Rejected: not settled'));
            tc.assertNumElements(k, 1);
            tc.verifyEqual(d{k, 2}, n - nnz(fl.notSettled), 'Passing');
            tc.verifyEqual(d{k, 4}, '|τ|, α_d, TL, Z_t (R: M1/M2)');
            tc.verifyTrue(any(strcmp(d(:, 1), 'Quality OK (coherence, SNR, cal.)')), 'the label stays');
            tc.verifySubstring(v.summary, 'not settled (drift between the blocks)');
            % the empty view lists the flags of every result: not this one
            tim.plots.validity(ax, []);
            tc.verifyFalse(any(strcmp(cellstr(ax.YTickLabel), 'Rejected: not settled')));
            % results.csv and spectra.csv
            folder = fullfile(tc.tmp, 'csvShort'); mkdir(folder);
            tim.app.exportCsv(r, folder);
            T = readtable(fullfile(folder, 'results.csv'));
            tc.verifyEqual(logical(T.flag_notSettled), fl.notSettled);
            tc.verifyEqual(T.settleDrift, v.settleDrift, 'AbsTol', 1e-9);
            S = readtable(fullfile(folder, 'spectra.csv'));
            for c = 1:4
                tc.verifyEqual(S.(sprintf('settleDrift%d', c)), r.spectra.settleDrift(:, c), 'AbsTol', 1e-9);
            end
        end

        function toleranceConfigurable(tc)
            % analysis.settleDriftMax: Inf switches the check off (scripts), a
            % configuration without it (an older script or file) gets 0.01, and
            % validateConfig accepts only a number greater than 0
            c = TestSettledCheck.shortSettling(tc.cfg);
            c.analysis.settleDriftMax = Inf;
            r = tim.app.processMeasurement(tc.mShort, c, tc.cal);
            v = r.analysis.valid;
            tc.verifyEqual(nnz(v.flags.notSettled), 0, 'Inf: nothing flagged');
            tc.verifyEqual(v.settleDrift, tc.rShort.analysis.valid.settleDrift, 'the indicator is kept');
            c0 = TestSettledCheck.shortSettling(tc.cfg);
            c0.analysis = rmfield(c0.analysis, 'settleDriftMax');
            r0 = tim.app.processMeasurement(tc.mShort, c0, tc.cal);
            tc.verifyEqual(r0.analysis.valid.flags.notSettled, tc.rShort.analysis.valid.flags.notSettled, ...
                'a configuration struct without the key: the default 0.01');
            file = fullfile(tc.tmp, 'noSettleKey.json');
            fid = fopen(file, 'w', 'n', 'UTF-8');
            fwrite(fid, unicode2native(jsonencode(struct('analysis', struct('coherenceMin', 0.98))), 'UTF-8'));
            fclose(fid);
            tc.verifyEqual(tim.app.loadConfig(file).analysis.settleDriftMax, 0.01, 'a file without the key');
            for ok = {0.05, Inf}
                b = tc.cfg; b.analysis.settleDriftMax = ok{1};
                tc.verifyClass(tim.app.validateConfig(b), 'cell');
            end
            for bad = {0, -1, NaN, [0.01 0.02], 'x', 1j}
                b = tc.cfg; b.analysis.settleDriftMax = bad{1};
                tc.verifyError(@() tim.app.validateConfig(b), 'tim:config:settled', mat2str(bad{1}));
            end
        end

        function sweepHasNoSettledFlag(tc)
            % the swept sine has no blocks: no flag notSettled, no column
            c = tc.cfg;
            c.excitation.sweep.duration = 1; c.excitation.sweep.repetitions = 1;
            c.excitation.sweep.preRoll = 0.3; c.excitation.sweep.postRoll = 0.2;
            s = tc.session(c);
            r = tim.app.processMeasurement(s.measure('sweep'), c, tc.cal);
            v = r.analysis.valid;
            tc.verifyFalse(isfield(v.flags, 'notSettled'));
            tc.verifyFalse(isfield(v.upstream.flags, 'notSettled'));
            tc.verifyFalse(isfield(v, 'settleDrift'));
            tc.verifyFalse(isfield(r.spectra, 'settleDrift'));
            folder = fullfile(tc.tmp, 'csvSweep'); mkdir(folder);
            tim.app.exportCsv(r, folder);
            T = readtable(fullfile(folder, 'results.csv'));
            tc.verifyFalse(any(ismember({'settleDrift', 'flag_notSettled'}, T.Properties.VariableNames)));
        end
    end
end
