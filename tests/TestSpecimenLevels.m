classdef TestSpecimenLevels < matlab.unittest.TestCase
    %TESTSPECIMENLEVELS Level at the specimen front face (1.6.0, WO-006 stage 1).
    %
    %   res.levels of tim.app.processMeasurement: the incident pressure |A| at
    %   the specimen front face [dB SPL] and the particle velocity |u_L| there
    %   [mm/s] per frequency line, from the calibrated decomposition and the
    %   sensitivity of the reference microphone (owner decisions 2026-11-04).
    %   Checked: the sine-equivalent amplitude of a sweep on synthetic sweeps
    %   (tim.dsp.sweepEquivalentAmplitude), the face values of an analytic field
    %   (tim.acoustics.faceLevels), stepped and swept sine against the truth of
    %   the virtual rig and against each other, the conditions (calibration,
    %   face positions, volts, sensitivity, noise), results.csv and the Spectrum
    %   view (axes, window page, saved figure).
    %
    %   One switching calibration and one swept and one stepped measurement of
    %   the virtual rig are made once for the class. Simulation: the tests
    %   verify software behaviour, not physical accuracy.

    properties
        cfg
        cal
        tmp
        mSweep
        rSweep
        mStep
        rStep
        truthSweep      % struct L [dB SPL], u [mm/s] at rSweep.levels.f
        truthStep       % the same at rStep.levels.f
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
            % 8 steps 200-4000 Hz, default timing (settle 0.2 s / 50 cycles, record 0.2 s / 100 cycles)
            c.excitation.stepped.fStart = 200; c.excitation.stepped.fStop = 4000;
            c.excitation.stepped.nPoints = 8;
            tc.cfg = c;
            s = tim.app.MeasurementSession(c);
            cleanup = onCleanup(@() s.close());
            s.connect(); s.prepareAcquisition();
            tc.cal = tim.app.runCalibration(s);
            clear cleanup
            % the measurements in a new session (the calibration moved the microphones of the rig)
            s = tim.app.MeasurementSession(c);
            cleanup = onCleanup(@() s.close());
            s.connect(); s.prepareAcquisition();
            tc.mSweep = s.measure('sweep');
            tc.mStep = s.measure('stepped');
            tc.rSweep = tim.app.processMeasurement(tc.mSweep, c, tc.cal);
            tc.rStep = tim.app.processMeasurement(tc.mStep, c, tc.cal);
            ref = c.analysis.refChannel;
            tc.truthSweep = TestSpecimenLevels.rigTruth(s.Rig, tc.mSweep, tc.rSweep.levels.f, ref);
            tc.truthStep = TestSpecimenLevels.rigTruth(s.Rig, tc.mStep, tc.rStep.levels.f, ref);
            clear cleanup
        end
    end

    methods (Test)
        function sweepEquivalentAmplitudeOfASyntheticSweep(tc)
            % formula check (docs/theory.md, section 3C): A = (2/fs) sqrt(fdot P) of an
            % ideal swept sine of 0.3 V gives 0.3 V at every line of the band
            fs = 16384; A0 = 0.3;
            sw = struct('fStart', 80, 'fStop', 5500, 'duration', 3, 'spacing', 'LOG');
            x = TestSpecimenLevels.syntheticSweep(fs, sw, 0.5, 0.5);
            [b, a] = butter(1, 1000 / (fs / 2));                      % first-order low-pass, 1 kHz
            rs = RandStream('mt19937ar', 'Seed', 3);
            X = A0 * [x, 0.5 * x, filter(b, a, x), x] + 1e-6 * randn(rs, numel(x), 4);
            o = struct('fRange', [120 4500], 'df', 2, 'preRoll', 0.5, 'excitationBand', [80 5500], 'sweep', sw);
            sp = tim.dsp.sweepResponse({X}, fs, o);
            tc.assertTrue(sp.excitation.gated, 'the sweep gate found the sweep');
            tc.verifySize(sp.refPower, size(sp.f));
            [A, rate] = tim.dsp.sweepEquivalentAmplitude(sp.refPower, sp.f, fs, sw, sp.excitation.sweepDuration_s);
            tc.verifyEqual(rate, sp.f * log(5500 / 80) / sp.excitation.sweepDuration_s, 'RelTol', 1e-12);
            in = sp.f >= 150 & sp.f <= 4000;
            e = abs(20 * log10(A(in) / A0));
            tc.verifyLessThan(median(e), 0.05, 'log sweep: median error [dB]');
            tc.verifyLessThan(max(e), 0.3, 'log sweep: largest error [dB]');
            % the level is that of the reference channel: half the amplitude on ch2
            o2 = o; o2.refChannel = 2;
            sp2 = tim.dsp.sweepResponse({X}, fs, o2);
            A2 = tim.dsp.sweepEquivalentAmplitude(sp2.refPower, sp2.f, fs, sw, sp2.excitation.sweepDuration_s);
            tc.verifyEqual(A2(in), A(in) / 2, 'RelTol', 1e-3);
            % a channel behind a linear filter: |G(f)| times the amplitude, as a stepped sine would give
            o3 = o; o3.refChannel = 3;
            sp3 = tim.dsp.sweepResponse({X}, fs, o3);
            tc.assertTrue(sp3.excitation.gated);
            A3 = tim.dsp.sweepEquivalentAmplitude(sp3.refPower, sp3.f, fs, sw, sp3.excitation.sweepDuration_s);
            G = abs(freqz(b, a, sp3.f, fs));
            tc.verifyLessThan(max(abs(20 * log10(A3(in) ./ (A0 * G(in))))), 0.2, 'low-pass channel [dB]');
            % two repetitions (the second one 1234 samples later) give the same amplitude:
            % refPower is a mean per bin and repetition
            Xd = [1e-6 * randn(rs, 1234, 4); X];
            sp12 = tim.dsp.sweepResponse({X, Xd}, fs, o);
            tc.assertTrue(all([sp12.excitation.gated]));
            A12 = tim.dsp.sweepEquivalentAmplitude(sp12.refPower, sp12.f, fs, sw, ...
                mean([sp12.excitation.sweepDuration_s]));
            tc.verifyEqual(A12(in), A(in), 'RelTol', 1e-3);
            % outside the sweep: NaN; T omitted: the programmed duration
            tc.verifyTrue(all(isnan(tim.dsp.sweepEquivalentAmplitude([1; 1], [60; 6000], fs, sw))));
            tc.verifyEqual(tim.dsp.sweepEquivalentAmplitude(sp.refPower, sp.f, fs, sw), ...
                A * sqrt(sp.excitation.sweepDuration_s / 3), 'RelTol', 1e-12);
            % linear sweep (the gate ramp at the start is short: lines from 600 Hz)
            sw.spacing = 'LIN';
            xl = TestSpecimenLevels.syntheticSweep(fs, sw, 0.5, 0.5);
            XL = A0 * repmat(xl, 1, 4) + 1e-6 * randn(rs, numel(xl), 4);
            o.sweep = sw;
            spl = tim.dsp.sweepResponse({XL}, fs, o);
            tc.assertTrue(spl.excitation.gated);
            [AL, rateL] = tim.dsp.sweepEquivalentAmplitude(spl.refPower, spl.f, fs, sw, spl.excitation.sweepDuration_s);
            tc.verifyEqual(rateL, (5500 - 80) / spl.excitation.sweepDuration_s * ones(size(spl.f)), 'RelTol', 1e-12);
            inL = spl.f >= 600 & spl.f <= 4000;
            eL = abs(20 * log10(AL(inL) / A0));
            tc.verifyLessThan(median(eL), 0.1, 'linear sweep: median error [dB]');
            tc.verifyLessThan(max(eL), 0.3, 'linear sweep: largest error [dB]');
        end

        function faceLevelsOfAnAnalyticField(tc)
            % formula check: the analytic field of a thin screen with an incident wave of
            % 2 Pa peak at the front face, seen relative to M1 (as the decomposition sees it)
            c = tc.cfg; g = c.geometry;
            f = (150:10:4500).';
            m = tim.sim.tubeModel(f, g, c.environment, struct('type', 'thin', 'Zt', 400), ...
                struct('R', 0.05, 'x', 0.6), 'lossModel', c.analysis.lossModel);
            H = m.p ./ m.p(:, 1);
            o = struct('lossModel', c.analysis.lossModel);
            an = tim.acoustics.analyzeFourMic(f, H, g, c.environment, o);
            L = tim.acoustics.faceLevels(an, 2 * abs(m.p(:, 1)));
            tc.verifyEqual(L.incident_Pa, 2 / sqrt(2) * ones(size(f)), 'RelTol', 1e-9);
            tc.verifyEqual(L.incident_dB_SPL, 20 * log10(sqrt(2) / 2e-5) * ones(size(f)), 'AbsTol', 1e-7);
            tc.verifyEqual(L.faceVelocity_mm_s, 1e3 * 2 * abs(m.uL) / sqrt(2), 'RelTol', 1e-9);
            % face position unknown: no level
            g.xFront = NaN;
            an = tim.acoustics.analyzeFourMic(f, H, g, c.environment, o);
            L = tim.acoustics.faceLevels(an, 2 * abs(m.p(:, 1)));
            tc.verifyTrue(all(isnan([L.incident_Pa; L.incident_dB_SPL; L.faceVelocity_mm_s])));
        end

        function steppedLevelsAgreeWithTheVirtualRig(tc)
            lv = tc.rStep.levels;
            m = tc.mStep;
            tc.assertTrue(lv.available, lv.note);
            tc.verifyEmpty(lv.note);
            tc.verifyEqual(lv.method, 'stepped sine: fitted tone amplitude');
            tc.verifyEqual(lv.f, m.settings.frequencies(:), 'the step frequencies (the equalizer reads them)');
            tc.verifyEqual(lv.generatorVpp, m.settings.amplitudeVpp * ones(8, 1));
            tc.verifyEqual(lv.sensitivity_VperPa, m.mics([m.mics.channel] == 1).sensitivity_VperPa);
            % the reference amplitude is the tone level of the reference channel
            tc.verifyEqual(20 * log10(lv.refAmplitude_Pa / sqrt(2) / 2e-5), tc.rStep.toneLevels.spl_dB(:, 1), ...
                'AbsTol', 1e-9);
            ok = lv.valid;
            tc.verifyEqual(ok, tc.rStep.analysis.valid.validR & isfinite(lv.incident_dB_SPL));
            tc.assertGreaterThanOrEqual(nnz(ok), 6, 'most steps valid');
            t = tc.truthStep;
            dL = abs(lv.incident_dB_SPL(ok) - t.L(ok));
            tc.verifyLessThan(max(dL), 0.3, 'incident level [dB]');
            tc.verifyLessThan(median(dL), 0.1, 'incident level, median [dB]');
            tc.verifyLessThan(max(abs(lv.faceVelocity_mm_s(ok) ./ t.u(ok) - 1)), 0.05, 'face velocity');
            tc.verifyEqual(lv.incident_Pa, 2e-5 * 10.^(lv.incident_dB_SPL / 20), 'RelTol', 1e-12);
            tc.verifyTrue(all(isnan(lv.sweepRate_Hz_s)) && isnan(lv.sweepDuration_s));
        end

        function sweptLevelsAgreeWithStepped(tc)
            % the sine-equivalent level of the sweep against the step levels at the
            % same generator amplitude (and against the truth of the rig)
            ls = tc.rSweep.levels; lt = tc.rStep.levels;
            tc.assertTrue(ls.available, ls.note);
            tc.assertTrue(lt.available, lt.note);
            tc.assertEqual(tc.mSweep.settings.amplitudeVpp, tc.mStep.settings.amplitudeVpp);
            tc.verifySubstring(ls.method, 'sine-equivalent');
            tc.verifyEqual(ls.f, tc.rSweep.analysis.f);
            ex = tc.rSweep.diagnostics.excitation;
            tc.assertTrue(all([ex.gated]), 'sweep gate in every repetition');
            tc.verifyEqual(ls.sweepDuration_s, mean([ex.sweepDuration_s]), 'RelTol', 1e-12, ...
                'duration on the DAQ clock (matched filter)');
            tc.verifyEqual(ls.sweepDuration_s, tc.mSweep.settings.duration, 'RelTol', 1e-3);
            tc.verifyEqual(ls.sweepRate_Hz_s, ls.f * log(tc.mSweep.settings.fStop / tc.mSweep.settings.fStart) / ...
                ls.sweepDuration_s, 'RelTol', 1e-12);
            fk = lt.f;
            vs = interp1(ls.f, double(ls.valid), fk, 'linear', 0) == 1;   % both neighbouring lines valid
            ok = vs & lt.valid;
            tc.assertGreaterThanOrEqual(nnz(ok), 5);
            dL = interp1(ls.f, ls.incident_dB_SPL, fk(ok)) - lt.incident_dB_SPL(ok);
            tc.verifyLessThan(max(abs(dL)), 0.5, 'incident level, sweep vs steps [dB]');
            tc.verifyLessThan(median(abs(dL)), 0.2, 'incident level, sweep vs steps, median [dB]');
            dU = 20 * log10(interp1(ls.f, ls.faceVelocity_mm_s, fk(ok)) ./ lt.faceVelocity_mm_s(ok));
            tc.verifyLessThan(max(abs(dU)), 0.5, 'face velocity, sweep vs steps [dB]');
            tc.verifyLessThan(median(abs(dU)), 0.2, 'face velocity, sweep vs steps, median [dB]');
            % against the truth of the rig, valid lines from 150 Hz
            v = ls.valid & ls.f >= 150;
            tc.assertGreaterThan(nnz(v), 0.5 * numel(v));
            e = abs(ls.incident_dB_SPL(v) - tc.truthSweep.L(v));
            tc.verifyLessThan(median(e), 0.2, 'sweep vs truth, median [dB]');
            tc.verifyLessThan(prctile(e, 99), 0.5, 'sweep vs truth, 99th percentile [dB]');
            % outside the sweep: no level (none here: the sweep covers the band)
            tc.verifyTrue(all(isfinite(ls.refAmplitude_Pa)));
        end

        function levelsNeedCalibrationFacesAndVolts(tc)
            lv = tc.rStep.levels;
            m = tc.mStep; c = tc.cfg;
            noLevel = @(l) ~l.available && ~any(l.valid) && all(isnan(l.incident_dB_SPL)) && ...
                all(isnan(l.incident_Pa)) && all(isnan(l.faceVelocity_mm_s));
            % no calibration (owner decision 2026-11-04: calibrated decomposition only)
            r = tim.app.processMeasurement(m, c, []);
            tc.verifyTrue(noLevel(r.levels));
            tc.verifySubstring(r.levels.note, 'calibration');
            tc.verifyEqual(r.levels.refAmplitude_Pa, lv.refAmplitude_Pa, 'RelTol', 1e-12, ...
                'the reference microphone alone needs no calibration');
            tc.verifyFalse(any(contains(r.diagnostics.warnings, 'level at the specimen', 'IgnoreCase', true)), ...
                'no warning of its own');
            % front face unknown
            cf = c; cf.geometry.xFront = NaN;
            r = tim.app.processMeasurement(m, cf, tc.cal);
            tc.verifyTrue(noLevel(r.levels));
            tc.verifySubstring(r.levels.note, 'front face');
            % data in full-scale units: no sound pressure at all
            mf = m; mf.unit = 'FS';
            r = tim.app.processMeasurement(mf, c, tc.cal);
            tc.verifyTrue(noLevel(r.levels));
            tc.verifyTrue(all(isnan(r.levels.refAmplitude_Pa)));
            tc.verifySubstring(r.levels.note, 'FS');
            % no valid sensitivity of the reference microphone (DAQ channel 1)
            mn = m; mn.mics([mn.mics.channel] == c.analysis.refChannel).sensitivity_VperPa = NaN;
            r = tim.app.processMeasurement(mn, c, tc.cal);
            tc.verifyTrue(noLevel(r.levels));
            tc.verifySubstring(r.levels.note, 'sensitivity');
            % random noise: no sine amplitude (not computed in 1.6.0)
            cn = c; cn.excitation.noise.duration = 3;
            s = tim.app.MeasurementSession(cn);
            cleanup = onCleanup(@() s.close());
            s.connect(); s.prepareAcquisition();
            r = tim.app.processMeasurement(s.measure('noise'), cn, tc.cal);
            tc.verifyTrue(noLevel(r.levels));
            tc.verifySubstring(r.levels.note, 'noise');
            tc.verifyEqual(numel(r.levels.f), numel(r.analysis.f));
            clear cleanup
        end

        function levelsInResultsCsv(tc)
            d = fullfile(tc.tmp, 'csv');
            if ~isfolder(d), mkdir(d); end
            for r = {tc.rStep, tc.rSweep}
                lv = r{1}.levels;
                tim.app.exportCsv(r{1}, d);
                T = readtable(fullfile(d, 'results.csv'));
                tc.verifyEqual(height(T), numel(lv.f));
                TestSpecimenLevels.verifyColumn(tc, T.incident_dB_SPL, lv.incident_dB_SPL);
                TestSpecimenLevels.verifyColumn(tc, T.faceVelocity_mm_s, lv.faceVelocity_mm_s);
            end
            % uncalibrated: the columns exist, NaN
            r0 = tim.app.processMeasurement(tc.mStep, tc.cfg, []);
            tim.app.exportCsv(r0, d);
            T = readtable(fullfile(d, 'results.csv'));
            tc.verifyTrue(all(isnan(T.incident_dB_SPL)) && all(isnan(T.faceVelocity_mm_s)));
            % a result saved before 1.6.0 (no res.levels): no level columns
            tim.app.exportCsv(rmfield(tc.rStep, 'levels'), d);
            T = readtable(fullfile(d, 'results.csv'));
            tc.verifyFalse(any(ismember({'incident_dB_SPL', 'faceVelocity_mm_s'}, T.Properties.VariableNames)));
        end

        function spectrumViewShowsTheIncidentLevel(tc)
            fig = figure('Visible', 'off', 'Position', [50 50 1180 640]);
            tc.addTeardown(@() close(fig));
            % ---- stepped sine: black squares on the tone-level axis (dB SPL)
            ax = axes(fig);
            info = tim.plots.spectrum(ax, tc.mStep, tc.rStep);
            lv = tc.rStep.levels;
            h = findobj(ax, 'Tag', 'timLevelIncident');
            tc.assertNumElements(h, 1);
            y = h.YData(:);
            tc.verifyEqual(~isnan(y), lv.valid);
            tc.verifyEqual(y(lv.valid), lv.incident_dB_SPL(lv.valid), 'AbsTol', 1e-9);
            tc.verifyEqual(h.XData(:), lv.f, 'RelTol', 1e-12);
            tc.verifyNumElements(findobj(ax, 'Tag', 'timLevelIncidentAll'), 1, 'grey: every step');
            tc.verifyNumElements(findobj(ax, 'Type', 'line', 'Marker', 'o'), 4, 'channels: circles');
            tc.verifyNumElements(findobj(ax, 'Type', 'line', 'LineStyle', ':'), 5, 'noise: dotted');
            tc.verifyEqual(ax.YLabel.String, 'Tone level [dB SPL]');
            tc.verifyEqual(ax.Legend.String{end}, 'Noise in fit bandwidth');
            tc.verifyTrue(any(strcmp(ax.Legend.String, 'Incident wave at the front face')));
            tc.verifyNumElements(ax.YAxis, 1, 'stepped sine: one y axis');
            tc.verifyTrue(info.levels.shown);
            tc.verifyEqual(info.levels.axis, 'left');
            tc.verifySubstring(info.note, 'incident wave at the front face');
            tc.verifySubstring(info.summary.note, 'Front face (valid lines)');
            % ---- swept sine: right axis in dB SPL, the left one stays the PSD
            delete(ax); ax = axes(fig);
            info = tim.plots.spectrum(ax, tc.mSweep, tc.rSweep);
            lv = tc.rSweep.levels;
            tc.assertNumElements(ax.YAxis, 2);
            tc.verifyEqual(char(ax.YAxis(2).Visible), 'on');
            tc.verifySubstring(ax.YAxis(2).Label.String, 'dB SPL');
            tc.verifyEqual(ax.YLabel.String, 'PSD [dB re (20 \muPa)^2/Hz]', 'the left (PSD) axis stays active');
            S = getappdata(ax, 'timFitAxes');
            tc.verifyEqual(S.yl, ax.YLim, 'the fit of the left axis stays the reference');
            tc.verifyEqual(ax.YLim, [ax.YTick(1), ax.YTick(end)] + [-1 1] * diff(ax.YTick(1:2)) / 2, 'AbsTol', 1e-9);
            h = TestSpecimenLevels.findBothSides(ax, 'timLevelIncident');
            tc.assertNumElements(h, 1);
            y = h.YData(:);
            tc.verifyEqual(y(lv.valid), lv.incident_dB_SPL(lv.valid), 'AbsTol', 1e-9);
            tc.verifyTrue(all(isnan(y(~lv.valid))));
            tc.verifyTrue(any(strcmp(ax.Legend.String, 'Incident wave at the front face (sine-equivalent)')));
            tc.verifyTrue(startsWith(ax.Legend.String{end}, 'Analysis band'));
            tc.verifyTrue(all(strcmp({info.lines.Marker}, 'none')), 'PSD curves without markers');
            tc.verifyTrue(info.levels.shown);
            tc.verifyEqual(info.levels.axis, 'right');
            tc.verifySubstring(info.summary.note, 'dB SPL');
            % ---- the same axes, an uncalibrated result: the right axis emptied and hidden
            r0 = tim.app.processMeasurement(tc.mSweep, tc.cfg, []);
            info = tim.plots.spectrum(ax, tc.mSweep, r0);
            tc.verifyEmpty(TestSpecimenLevels.findBothSides(ax, 'timLevelIncident'));
            tc.verifyEmpty(TestSpecimenLevels.findBothSides(ax, 'timLevelIncidentAll'));
            tc.verifyEqual(char(ax.YAxis(2).Visible), 'off');
            tc.verifyEqual(ax.YLabel.String, 'PSD [dB re (20 \muPa)^2/Hz]');
            tc.verifyNumElements(ax.Legend.String, 5, 'four channels and the band, as before 1.6.0');
            tc.verifyFalse(info.levels.shown);
            % ... and a stepped result afterwards: on the left axis, the right one stays hidden
            tim.plots.spectrum(ax, tc.mStep, tc.rStep);
            tc.verifyNumElements(findobj(ax, 'Tag', 'timLevelIncident'), 1);
            tc.verifyEqual(char(ax.YAxis(2).Visible), 'off');
            tc.verifyEqual(ax.YLabel.String, 'Tone level [dB SPL]');
            % ---- saved figures: the same drawing code
            for k = {{tc.rStep, tc.mStep}, {tc.rSweep, tc.mSweep}}
                figs = tim.app.plotResults(k{1}{1}, k{1}{2}, struct('Visible', 'off', 'Views', {{'spectrum'}}));
                closeFigs = onCleanup(@() close(figs.spectrum));
                fr = getappdata(figs.spectrum, 'timSavedFrame');
                h = TestSpecimenLevels.findBothSides(fr.axes(1), 'timLevelIncident');
                tc.verifyNumElements(h, 1, ['saved figure of the ' k{1}{1}.kind]);
                clear closeFigs
            end
        end

        function spectrumPageKeepsItsToolbar(tc)
            % the right axis of a sweep is hidden, not removed with cla(ax, 'reset'),
            % which would also drop the axes toolbar of the window (tim.gui.ViewPage)
            fig = uifigure('Visible', 'off', 'Position', [50 50 1200 700]);
            tc.addTeardown(@() delete(fig));
            [ttl, desc] = tim.plots.viewText('spectrum');
            p = tim.gui.ViewPage(fig, ttl, desc, 'Axes', 1, 'SummaryTitle', 'Levels');
            ax = p.Axes(1);
            n0 = numel(ax.Toolbar.Children);
            tc.assertGreaterThan(n0, 0);
            p.show(tim.plots.spectrum(ax, tc.mSweep, tc.rSweep));
            tc.verifyNumElements(TestSpecimenLevels.findBothSides(ax, 'timLevelIncident'), 1);
            r0 = tim.app.processMeasurement(tc.mSweep, tc.cfg, []);
            p.show(tim.plots.spectrum(ax, tc.mSweep, r0));
            tc.verifyEmpty(TestSpecimenLevels.findBothSides(ax, 'timLevelIncident'));
            tc.verifyNumElements(ax.Toolbar.Children, n0, 'toolbar of the window kept');
            p.show(tim.plots.spectrum(ax, tc.mStep, tc.rStep));
            tc.verifyNumElements(ax.Toolbar.Children, n0);
            tc.verifySubstring(p.Note.Text, 'Black squares');
        end

        function spectrumViewShowsTheEqualizerTarget(tc)
            % 1.6.0 (WO-006 stage 2; owner decision 2026-11-04): an equalized stepped
            % sine shows its target as a dashed line in a light band of ± the
            % tolerance - the incident pressure on the tone-level axis, the face
            % velocity with the velocity itself on a right axis in mm/s. Lines and
            % patches, no ConstantLine. (res.equalizer built here; the equalized
            % measurement itself: TestEqualizer, TestGuiTwoLoad)
            fig = figure('Visible', 'off', 'Position', [50 50 1180 640]);
            tc.addTeardown(@() close(fig));
            r = tc.rStep; lv = r.levels; n = numel(lv.f);
            r.equalizer = TestSpecimenLevels.equalizerOf(lv, 'incidentPressure', 90, 1, [2 5]);
            ax = axes(fig);
            info = tim.plots.spectrum(ax, tc.mStep, r);
            ht = findobj(ax, 'Tag', 'timEqTarget'); hb = findobj(ax, 'Tag', 'timEqBand');
            tc.assertNumElements(ht, 1); tc.assertNumElements(hb, 1);
            tc.verifyEqual(ht.YData, [90 90]);
            tc.verifyEqual(char(ht.LineStyle), '--');
            tc.verifyEqual(unique(hb.YData(:)), [89; 91], 'the band: target ± tolerance');
            tc.verifyEqual(ax.Children(end), hb, 'the band behind the data (drawn first)');
            tc.verifyEmpty(findobj(ax, 'Type', 'ConstantLine'));
            tc.verifyNumElements(ax.YAxis, 1, 'incident pressure: on the tone-level axis');
            tc.verifyLessThanOrEqual(ax.YLim(1), 89); tc.verifyGreaterThanOrEqual(ax.YLim(2), 91);
            tc.verifyTrue(any(strcmp(ax.Legend.String, 'Target 90 dB SPL ± 1 dB')));
            tc.verifyTrue(any(strcmp(ax.Legend.String, 'Incident wave at the front face')));
            tc.verifyEqual(ax.Legend.String{end}, 'Noise in fit bandwidth');
            tc.verifyTrue(info.equalizer.shown);
            tc.verifyEqual(info.equalizer.axis, 'left');
            tc.verifySubstring(info.note, 'equalizer target');
            tc.verifySubstring(info.summary.note, sprintf('Equalizer: target 90 dB SPL ± 1 dB, %d of %d steps within', ...
                n - 2, n));
            % the face velocity: the velocity and its target on a right axis in mm/s
            t = round(median(lv.faceVelocity_mm_s(lv.valid)), 2, 'significant');
            r.equalizer = TestSpecimenLevels.equalizerOf(lv, 'faceVelocity', t, 1, []);
            info = tim.plots.spectrum(ax, tc.mStep, r);
            tc.assertNumElements(ax.YAxis, 2);
            tc.verifyEqual(char(ax.YAxis(2).Visible), 'on');
            tc.verifySubstring(ax.YAxis(2).Label.String, 'mm/s');
            tc.verifyEqual(ax.YLabel.String, 'Tone level [dB SPL]', 'the tone-level axis stays active');
            hv = TestSpecimenLevels.findBothSides(ax, 'timLevelVelocity');
            tc.assertNumElements(hv, 1);
            y = hv.YData(:);
            tc.verifyEqual(y(lv.valid), lv.faceVelocity_mm_s(lv.valid), 'RelTol', 1e-12);
            tc.verifyTrue(all(isnan(y(~lv.valid))), 'grey where not valid');
            ht = TestSpecimenLevels.findBothSides(ax, 'timEqTarget');
            tc.assertNumElements(ht, 1);
            tc.verifyEqual(ht.YData, [t t]);
            tc.verifyEqual(info.equalizer.axis, 'right');
            tc.verifyTrue(any(strcmp(ax.Legend.String, sprintf('Target %g mm/s ± 1 dB', t))));
            tc.verifyEqual(ax.Legend.String{end}, 'Noise in fit bandwidth');
            yyaxis(ax, 'right');
            tc.verifyEqual(ax.Children(end).Tag, 'timEqBand', 'right side: the band behind the velocity');
            yyaxis(ax, 'left');
            % the incident target again on these yyaxis axes (the window reuses
            % them; uistack failed here before)
            r.equalizer = TestSpecimenLevels.equalizerOf(lv, 'incidentPressure', 90, 1, [2 5]);
            info = tim.plots.spectrum(ax, tc.mStep, r);
            hb = findobj(ax, 'Tag', 'timEqBand');
            tc.assertNumElements(hb, 1);
            tc.verifyEqual(ax.Children(end), hb, 'left side of yyaxis axes: the band behind the data');
            tc.verifyEqual(info.equalizer.axis, 'left');
            tc.verifyEqual(char(ax.YAxis(2).Visible), 'off');
            % the next drawing without the equalizer: the right axis emptied and hidden
            info = tim.plots.spectrum(ax, tc.mStep, tc.rStep);
            tc.verifyEmpty(TestSpecimenLevels.findBothSides(ax, 'timLevelVelocity'));
            tc.verifyEmpty(TestSpecimenLevels.findBothSides(ax, 'timEqTarget'));
            tc.verifyEqual(char(ax.YAxis(2).Visible), 'off');
            tc.verifyFalse(info.equalizer.shown);
        end
    end

    methods (Static)
        function x = syntheticSweep(fs, sw, pre, post)
            % ideal swept sine of amplitude 1 with the generator's sweep law (log:
            % f = fStart (fStop/fStart)^(t/T)), starting at 0, silence around it
            t = (0:round(sw.duration * fs) - 1).' / fs;
            if strncmpi(sw.spacing, 'LOG', 3), law = 'logarithmic'; else, law = 'linear'; end
            s = chirp(t, sw.fStart, sw.duration, sw.fStop, law, -90);
            x = [zeros(round(pre * fs), 1); s; zeros(round(post * fs), 1)];
        end

        function t = rigTruth(rig, m, f, ref)
            % incident level [dB SPL] and face velocity [mm/s] of the virtual rig for
            % the generator level of m, as the program must report them: the
            % reference microphone is read with its sensitivity of the measurement,
            % against the true response of its chain
            tr = rig.trueResponse(f);
            S = m.mics([m.mics.channel] == ref).sensitivity_VperPa;
            g = abs(tr.chain(:, ref)) / S;
            pk = abs(tr.incidentPerVolt) .* g * m.settings.amplitudeVpp / 2;   % incident wave [Pa peak]
            t = struct('L', 20 * log10(pk / sqrt(2) / 2e-5), 'u', 1e3 * abs(tr.model.uL) .* pk / sqrt(2));
        end

        function e = equalizerOf(lv, mode, target, tol, missed)
            % a res.equalizer in the layout of tim.app.processMeasurement for the
            % drawing tests: every step reached except the steps 'missed'
            n = numel(lv.f);
            reached = true(n, 1); reached(missed) = false;
            unit = 'dB SPL'; if strcmp(mode, 'faceVelocity'), unit = 'mm/s'; end
            e = struct('mode', mode, 'unit', unit, 'target', target, 'tolerance_dB', tol, 'f', lv.f(:), ...
                'vpp', repmat(0.2, n, 1), 'limited', {repmat({''}, n, 1)}, 'achieved', nan(n, 1), ...
                'deviation_dB', nan(n, 1), 'reached', reached, 'nReached', nnz(reached), 'text', '', ...
                'plan', struct('maxVpp', 0.2));
        end

        function h = findBothSides(ax, tag)
            % objects with the tag on both sides of an axes with two y axes (the
            % children of the side that is not active may not be listed)
            h = findobj(ax, 'Tag', tag);
            if numel(ax.YAxis) > 1
                yyaxis(ax, 'right');
                h = [h; findobj(ax, 'Tag', tag)];
                yyaxis(ax, 'left');
            end
            keep = true(size(h));
            for i = 2:numel(h), keep(i) = ~any(h(1:i - 1) == h(i)); end
            h = h(keep);
        end

        function verifyColumn(tc, col, want)
            % a CSV column against the result: NaN where NaN, else equal
            tc.verifyEqual(isnan(col), isnan(want));
            k = ~isnan(want);
            tc.verifyEqual(col(k), want(k), 'AbsTol', 1e-6 * max(1, max(abs(want(k)))));
        end
    end
end
