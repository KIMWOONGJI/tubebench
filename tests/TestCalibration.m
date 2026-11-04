classdef TestCalibration < matlab.unittest.TestCase
    %TESTCALIBRATION Sensor-switching mathematics (Test C, synthetic part).

    properties
        f = (100:2:5000).'
        env = struct('temperature_C', 22, 'pressure_Pa', 100500, 'c_override', [], 'rho_override', [])
    end

    methods
        function [cref, ck, pa, pb] = scenario(tc, phaseMis_deg)
            f = tc.f;
            s = 1j * f / 3; cref = 11.2e-3 * s ./ (1 + s);
            s2 = 1j * f / 4.5;
            ck = 11.9e-3 * exp(1j * deg2rad(phaseMis_deg) * (f / 5000)) .* exp(-2j*pi*f*3e-6) .* s2 ./ (1 + s2);
            g = struct('diameter', 0.029, 'micPositions', [-0.15 -0.121 0.071 0.1], 'xFront', 0, 'xRear', 0.01);
            m = tim.sim.tubeModel(f, g, tc.env, struct('type', 'porous', 'sigma', 2e4), struct('R', 0.3, 'x', 0.5));
            pa = m.p(:, 1); pb = m.p(:, 2);
        end
    end

    methods (Test)
        function calibrationContextChecks(tc)
            % calibration set-up (empty 75 mm section) vs measurement set-up
            cfg = tim.app.defaultConfig(); cfg.mode = 'hardware';
            g = struct('diameter', 0.029, 'micPositions', [-0.070 -0.041 0.116 0.145], ...
                'spacingUp', 0.029, 'spacingDown', 0.029, 'xFront', 0, 'xRear', 0.075);
            cfg.geometry = g;
            cal = struct('version', 'CAL-X', 'meta', struct('mode', 'hardware', ...
                'tube', struct('specimenSection', 'empty', 'sectionLength_m', 0.075, 'geometry', g, ...
                'environment', cfg.environment), 'emptyCheck', struct('performed', true, 'passed', true)));
            c = tim.cal.calibrationContext(cal, cfg);
            tc.verifyTrue(c.known); tc.verifyTrue(c.geometryMatch); tc.verifyEmpty(c.warnings);
            tc.verifyEqual(c.sectionLength_m, 0.075);
            m = cfg; m.geometry.micPositions(3:4) = m.geometry.micPositions(3:4) - 0.075;   % section taken out
            c = tim.cal.calibrationContext(cal, m);
            tc.verifyFalse(c.geometryMatch); tc.verifyNumElements(c.warnings, 1);
            m = cfg; m.geometry.xRear = 0.020;                % thinner specimen, same ports
            c = tim.cal.calibrationContext(cal, m);
            tc.verifyTrue(c.geometryMatch); tc.verifyEmpty(c.warnings);
            m = cfg; m.environment.temperature_C = cfg.environment.temperature_C + 4; m.mode = 'simulation';
            c = tim.cal.calibrationContext(cal, m);
            tc.verifyFalse(c.modeMatch); tc.verifyEqual(c.temperatureDiff_K, 4, 'AbsTol', 1e-12);
            tc.verifyNumElements(c.warnings, 2);
            old = rmfield(cal, 'meta'); old.meta = struct('mode', 'hardware');   % before the empty-section procedure
            c = tim.cal.calibrationContext(old, cfg);
            tc.verifyFalse(c.known); tc.verifyNumElements(c.warnings, 1);
            c = tim.cal.calibrationContext([], cfg);
            tc.verifyEmpty(c.warnings);
            bad = cal; bad.meta.emptyCheck.passed = false;
            c = tim.cal.calibrationContext(bad, cfg);
            tc.verifyFalse(c.emptyCheckPassed); tc.verifyNumElements(c.warnings, 1);
        end

        function calibrationContextAcquisitionChain(tc)
            % C_k includes the DAQ inputs: the chain recorded with a calibration
            % (cal.meta.acquisition) vs the measurement's metadata (WO-001 task 6).
            % A calibration and a measurement saved by the e8fb4fb code
            % (tests/fixtures/saved_e8fb4fb, before 1.2.0) give no false alarm.
            fx = fullfile(fileparts(mfilename('fullpath')), 'fixtures', 'saved_e8fb4fb');
            oldMeas = struct('metadata', jsondecode(tim.app.readTextUtf8(fullfile(fx, 'metadata.json'))), 'fs', 16384);
            S = load(fullfile(fx, 'calibration_meta.mat'));
            oldCal = S.calMeta;
            tc.assertFalse(isfield(oldCal.meta, 'acquisition'), 'calibration of 1.1.0');
            tc.assertFalse(isfield(oldMeas.metadata.daq, 'driver'), 'measurement of 1.1.0');
            cfg = tim.app.defaultConfig();
            cfg.geometry = cfg.simulation.Geometry;
            % old calibration: unknown, no warning - with an old or a new measurement
            c = tim.cal.calibrationContext(oldCal, cfg, oldMeas);
            tc.verifyFalse(c.acquisitionKnown);
            tc.verifyEmpty(c.warnings);
            newMeas = oldMeas;
            newMeas.metadata.daq.driver = 'simcombined';
            newMeas.metadata.daq.identity = struct('model', 'SIM-1AO-4AI', 'serial', 'SIM-0001', 'firmware', '1.0');
            tc.verifyEmpty(tim.cal.calibrationContext(oldCal, cfg, newMeas).warnings);
            % a calibration made with the same module and inputs: no warning with the
            % old measurement (its driver is unknown; model and serial compared as text)
            cal = oldCal;
            cal.meta.acquisition = struct('driver', 'lanxi', 'displayName', 'HBK LAN-XI module (Open API)', ...
                'model', '3676-B-040', 'serial', '110283', 'firmware', '2.10.0.610', 'sampleRate', 16384, ...
                'range', '10 Vpeak', 'filter', '0.7 Hz', 'ccld', true(1, 4));
            c = tim.cal.calibrationContext(cal, cfg, oldMeas);
            tc.verifyTrue(c.acquisitionKnown);
            tc.verifyTrue(c.acquisitionMatch);
            tc.verifyEmpty(c.warnings);
            % another module, another range, another driver: one warning naming them
            m = oldMeas; m.metadata.daq.serial = 110999;
            c = tim.cal.calibrationContext(cal, cfg, m);
            tc.verifyFalse(c.acquisitionMatch);
            tc.verifyNumElements(c.warnings, 1);
            tc.verifySubstring(c.warnings{1}, 'module serial number 110999 (calibration: 110283)');
            m = oldMeas; m.metadata.acquisition.range = '1 Vpeak'; m.metadata.acquisition.ccld = [true true false true];
            c = tim.cal.calibrationContext(cal, cfg, m);
            tc.verifySubstring(c.warnings{1}, 'input range 1 Vpeak (calibration: 10 Vpeak)');
            tc.verifySubstring(c.warnings{1}, 'CCLD');
            c = tim.cal.calibrationContext(cal, cfg, newMeas);
            tc.verifyNumElements(c.warnings, 1);
            tc.verifySubstring(c.warnings{1}, 'acquisition driver simcombined (calibration: lanxi)');
            tc.verifySubstring(c.warnings{1}, 'module model SIM-1AO-4AI');
            m = oldMeas; m.fs = 32768;
            tc.verifySubstring(tim.cal.calibrationContext(cal, cfg, m).warnings{1}, 'sample rate 32768 S/s');
            % without a measurement: the configured driver and inputs (module unknown)
            tc.verifyEmpty(tim.cal.calibrationContext(cal, cfg).warnings);
            b = cfg; b.acquisition.filter = 'DC';
            tc.verifySubstring(tim.cal.calibrationContext(cal, b).warnings{1}, 'high-pass filter DC');
            % the session's chain (connected module)
            ch = tim.cal.acquisitionChain(struct('driver', 'lanxi', 'identity', struct('model', '3676-B-040', ...
                'serial', '120000', 'firmware', '2.10.0.610')), cfg.acquisition, 16384);
            tc.verifySubstring(tim.cal.calibrationContext(cal, cfg, ch).warnings{1}, 'module serial number 120000');
        end

        function calibrationContextMicrophonesAndIntegrity(tc)
            % audit 2026-10-11: C_k includes the microphones - an exchange since
            % the calibration (TEDS serial numbers per channel) is reported, and
            % so is a calibration computed from sweeps that failed the data
            % integrity check
            cfg = tim.app.defaultConfig();
            mics = struct('channel', {1, 2, 3, 4}, 'position', {1, 2, 3, 4}, 'serial', {'', '', '', ''}, ...
                'tedsSerial', {3001001, 3001002, 3001003, 3001004});
            cal = struct('version', 'CAL-M', 'meta', struct('mode', cfg.mode, 'mics', mics));
            meas = struct('mics', mics);
            c = tim.cal.calibrationContext(cal, cfg, meas);
            tc.verifyTrue(c.micsKnown); tc.verifyTrue(c.micsMatch);
            tc.verifyFalse(any(contains(c.warnings, 'Microphones changed')));
            meas.mics(2).tedsSerial = 3001003; meas.mics(3).tedsSerial = 3001002;   % ch2 / ch3 exchanged
            c = tim.cal.calibrationContext(cal, cfg, meas);
            tc.verifyFalse(c.micsMatch);
            w = c.warnings(contains(c.warnings, 'Microphones changed'));
            tc.verifyNumElements(w, 1);
            tc.verifySubstring(w{1}, 'ch2 TEDS s/n 3001003 (calibration: 3001002)');
            tc.verifySubstring(w{1}, 'ch3 TEDS s/n 3001002 (calibration: 3001003)');
            meas.mics(2).tedsSerial = NaN; meas.mics(3).tedsSerial = NaN;   % no TEDS: unknown, no warning
            tc.verifyTrue(tim.cal.calibrationContext(cal, cfg, meas).micsMatch);
            % configured serial numbers when no TEDS is read (and from cfg without a measurement)
            cal.meta.mics(1).serial = '1234567'; cal.meta.mics(1).tedsSerial = NaN;
            meas.mics(1).serial = '7654321';
            tc.verifySubstring(strjoin(tim.cal.calibrationContext(cal, cfg, meas).warnings), ...
                'ch1 s/n 7654321 (calibration: 1234567)');
            c2 = cfg; c2.mics(1).serial = '1234567';
            tc.verifyTrue(tim.cal.calibrationContext(cal, c2).micsMatch);
            c2.mics(1).serial = '1111111';
            tc.verifyFalse(tim.cal.calibrationContext(cal, c2).micsMatch);
            % integrity of the switching sweeps
            cal = struct('version', 'CAL-I', 'meta', struct('mode', cfg.mode, 'integrity', ...
                struct('channel', {2, 2, 3}, 'config', {'I', 'II', 'I'}, 'ok', {true, false, true}, ...
                'problems', {{}, {'clipped'}, {}})));
            c = tim.cal.calibrationContext(cal, cfg);
            tc.verifyFalse(c.integrityOk);
            tc.verifySubstring(strjoin(c.warnings), 'data integrity problems (ch2 configuration II');
            cal.meta.integrity(2).ok = true;
            tc.verifyTrue(tim.cal.calibrationContext(cal, cfg).integrityOk);
        end

        function exactSwitching(tc)
            [cref, ck, pa, pb] = tc.scenario(25);
            HI = (ck .* pb) ./ (cref .* pa);
            HII = (ck .* pa) ./ (cref .* pb);
            r = tim.cal.switchingCorrection(tc.f, HI, HII);
            tc.verifyEqual(r.Hc, ck ./ cref, 'RelTol', 1e-12);
            tc.verifyEqual(r.Hpos, pb ./ pa, 'RelTol', 1e-12);
            tc.verifyTrue(all(r.valid));
        end

        function branchSelectionLargePhase(tc)
            % mismatch phase reaching 80 deg at 5 kHz plus position phase up to
            % ~ k s = 0.85 pi: the unwrapped/halved branch must stay continuous
            [cref, ck, pa, pb] = tc.scenario(80);
            HI = (ck .* pb) ./ (cref .* pa); HII = (ck .* pa) ./ (cref .* pb);
            r = tim.cal.switchingCorrection(tc.f, HI, HII, struct('maxPhase_deg', 120));
            tc.verifyEqual(r.Hc, ck ./ cref, 'RelTol', 1e-12);
            tc.verifyLessThan(max(abs(diff(unwrap(angle(r.Hc))))), 0.1);
        end

        function invalidBinsInterpolatedAndFlagged(tc)
            [cref, ck, pa, pb] = tc.scenario(10);
            HI = (ck .* pb) ./ (cref .* pa); HII = (ck .* pa) ./ (cref .* pb);
            coh = ones(size(tc.f)); bad = tc.f > 2000 & tc.f < 2100; coh(bad) = 0.5;
            HI(bad) = HI(bad) .* exp(1j * 2);   % garbage phase in bad bins
            r = tim.cal.switchingCorrection(tc.f, HI, HII, struct('cohI', coh, 'cohII', ones(size(tc.f))));
            tc.verifyFalse(any(r.valid(bad)));
            tc.verifyEqual(r.Hc(~bad), ck(~bad) ./ cref(~bad), 'RelTol', 1e-10);
        end

        function noiseScaling(tc)
            % with relative noise e on HI, HII the error of Hc ~ e/sqrt(2)
            [cref, ck, pa, pb] = tc.scenario(10);
            HI0 = (ck .* pb) ./ (cref .* pa); HII0 = (ck .* pa) ./ (cref .* pb);
            e = 1e-3; rng(5);
            n = @() e * (randn(size(tc.f)) + 1j * randn(size(tc.f))) / sqrt(2);
            r = tim.cal.switchingCorrection(tc.f, HI0 .* (1 + n()), HII0 .* (1 + n()));
            rel = abs(r.Hc ./ (ck ./ cref) - 1);
            tc.verifyLessThan(rms(rel), 1.2 * e / sqrt(2));
            tc.verifyGreaterThan(rms(rel), 0.8 * e / sqrt(2));
        end

        function repeatabilityReported(tc)
            [cref, ck, pa, pb] = tc.scenario(5);
            HI = (ck .* pb) ./ (cref .* pa); HII = (ck .* pa) ./ (cref .* pb);
            r = tim.cal.switchingCorrection(tc.f, HI, HII, struct('HIrepeat', HI * 1.01 * exp(1j * 0.01)));
            tc.verifyEqual(r.repeatability.maxMag_dB, 20 * log10(1.01), 'AbsTol', 1e-9);
            tc.verifyEqual(r.repeatability.maxPhase_deg, rad2deg(0.01), 'AbsTol', 1e-9);
        end

        function implausibleMismatchFlagged(tc)
            [cref, ck, pa, pb] = tc.scenario(5);
            ck = -ck * 3;   % e.g. reversed polarity and wrong gain
            HI = (ck .* pb) ./ (cref .* pa); HII = (ck .* pa) ./ (cref .* pb);
            r = tim.cal.switchingCorrection(tc.f, HI, HII);
            tc.verifyFalse(any(r.valid));
            tc.verifyNotEmpty(r.notes);
        end

        function interpolationPreservesPhase(tc)
            % pure 0.4 ms delay: phase wraps ~8 times below 5 kHz
            fc = (100:50:5000).';
            C = ones(numel(fc), 4);
            C(:, 2) = 1.05 * exp(-2j * pi * fc * 4e-4);
            C(:, 3) = 0.97 * exp(-2j * pi * fc * 1e-5);
            cal = struct('f', fc, 'C', C, 'valid', true(numel(fc), 4), 'refChannel', 1, 'version', 'T');
            ff = (100:1:5000).';
            [Ci, v] = tim.cal.interpolateCalibration(cal, ff);
            tc.verifyEqual(Ci(:, 2), 1.05 * exp(-2j * pi * ff * 4e-4), 'AbsTol', 1e-10);
            tc.verifyEqual(abs(Ci(:, 2)), 1.05 * ones(size(ff)), 'AbsTol', 1e-12);
            tc.verifyTrue(all(v(:)));
            % no extrapolation: outside the grid the nearest calibrated line is
            % held, never valid (1.5.1, owner decision 2026-11-04)
            [Ce, ve, out] = tim.cal.interpolateCalibration(cal, [50; 1000; 6000]);
            tc.verifyEqual(Ce([1 3], 2), C([1 end], 2), 'AbsTol', 1e-12);
            tc.verifyEqual(out, [true; false; true]);
            tc.verifyFalse(any(ve([1 3], :), 'all'));
            tc.verifyTrue(all(ve(2, :)));
        end

        function interpolationBandEdgeTolerance(tc)
            % UI audit B-L2: the first logspace step of 120 Hz is 3 ulp below
            % 120 (119.99999999999996) and used to get C = NaN (step vanished
            % from every result view); a few ulp outside the grid now takes the
            % edge value, a real offset is still not extrapolated
            fc = (120:2:4500).';
            C = ones(numel(fc), 4); C(:, 2) = 1.05 * exp(-2j * pi * fc * 4e-4);
            cal = struct('f', fc, 'C', C, 'valid', true(numel(fc), 4), 'refChannel', 1, 'version', 'T');
            fq = [120 - 3 * eps(120); 1000; 4500 + 2 * eps(4500)];
            [Ci, v] = tim.cal.interpolateCalibration(cal, fq);
            tc.verifyTrue(all(v(:)));
            tc.verifyEqual(Ci([1 3], 2), C([1 end], 2), 'AbsTol', 1e-12);
            [Co, vo, oo] = tim.cal.interpolateCalibration(cal, [120 * (1 - 1e-6); 4500 * (1 + 1e-6)]);
            tc.verifyTrue(all(oo) && ~any(vo(:)), 'a real offset is outside, never valid');
            tc.verifyEqual(Co(:, 2), C([1 end], 2), 'AbsTol', 1e-12, 'the edge factor is held');
            % the same step passes applyCalibration and the analysis band
            [Hc, cv, ~, ~, out] = tim.cal.applyCalibration(fq, C(1, :) .* ones(3, 4), cal, 1);
            tc.verifyTrue(all(isfinite(Hc(:))) && cv(1));
            tc.verifyFalse(any(out), 'within the edge tolerance: inside');
        end

        function applyCalibrationRoundTrip(tc)
            fc = (100:10:5000).';
            C = [ones(numel(fc), 1), 1.02 * exp(1j * 0.05 * ones(numel(fc), 1)), 0.98 * ones(numel(fc), 1), exp(-1j * 0.03 * ones(numel(fc), 1))];
            cal = struct('f', fc, 'C', C, 'valid', true(numel(fc), 4), 'refChannel', 1, 'version', 'T');
            Htrue = exp(1j * rand(numel(fc), 4)); Htrue(:, 1) = 1;
            [Hc, cv] = tim.cal.applyCalibration(fc, Htrue .* C, cal, 1);
            tc.verifyEqual(Hc, Htrue, 'AbsTol', 1e-12);
            tc.verifyTrue(all(cv));
            [~, cv0, ~, vc0] = tim.cal.applyCalibration(fc, Htrue, [], 1);
            tc.verifyFalse(any(cv0));
            tc.verifyEqual(vc0, false(numel(fc), 4));
            % review analysis-3: per-channel validity (DAQ channel columns) for the
            % position-wise masks; calValid is the all-channel AND
            cal.valid(11:20, 4) = false;
            [~, cv, ~, vc] = tim.cal.applyCalibration(fc, Htrue .* C, cal, 1);
            tc.verifySize(vc, [numel(fc) 4]);
            tc.verifyFalse(any(vc(11:20, 4)));
            tc.verifyTrue(all(vc(:, 1:3), 'all'));
            tc.verifyEqual(cv, all(vc, 2));
            tc.verifyError(@() tim.cal.applyCalibration(fc, Htrue, cal, 2), 'tim:cal:ref');
        end

        function sensitivityPolicy(tc)
            mics = tim.app.defaultConfig().mics;
            mics(2).certificateSensitivity_VperPa = 11.7e-3;
            teds = {struct('typeNumber', '4957', 'serialNumber', 5, 'sensitivity', 11.0e-3, 'unit', 'Pa', 'requiresCcld', true), [], [], []};
            m = tim.cal.resolveSensitivities(mics, teds, 'certificate>teds>nominal');
            tc.verifyEqual([m.sensitivity_VperPa], [11.0e-3 11.7e-3 11.2e-3 11.2e-3], 'AbsTol', 1e-15);
            tc.verifyEqual({m.sensitivitySource}, {'teds', 'certificate', 'nominal', 'nominal'});
            v = ones(10, 4) .* [m.sensitivity_VperPa];
            tc.verifyEqual(tim.acq.voltsToPascal(v, m, 'V'), ones(10, 4), 'AbsTol', 1e-12);
            tc.verifyError(@() tim.acq.voltsToPascal(v, m, 'Pa'), 'tim:acq:unit');   % double application blocked
        end
    end
end
