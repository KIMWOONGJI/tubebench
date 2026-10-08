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
            % no extrapolation
            [Ce, ve] = tim.cal.interpolateCalibration(cal, [50; 6000]);
            tc.verifyTrue(all(isnan(Ce(:, 2))) && ~any(ve(:)));
        end

        function applyCalibrationRoundTrip(tc)
            fc = (100:10:5000).';
            C = [ones(numel(fc), 1), 1.02 * exp(1j * 0.05 * ones(numel(fc), 1)), 0.98 * ones(numel(fc), 1), exp(-1j * 0.03 * ones(numel(fc), 1))];
            cal = struct('f', fc, 'C', C, 'valid', true(numel(fc), 4), 'refChannel', 1, 'version', 'T');
            Htrue = exp(1j * rand(numel(fc), 4)); Htrue(:, 1) = 1;
            [Hc, cv] = tim.cal.applyCalibration(fc, Htrue .* C, cal, 1);
            tc.verifyEqual(Hc, Htrue, 'AbsTol', 1e-12);
            tc.verifyTrue(all(cv));
            [~, cv0] = tim.cal.applyCalibration(fc, Htrue, [], 1);
            tc.verifyFalse(any(cv0));
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
