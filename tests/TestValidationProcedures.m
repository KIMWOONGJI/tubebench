classdef TestValidationProcedures < matlab.unittest.TestCase
    %TESTVALIDATIONPROCEDURES The hardware commissioning helpers (tim.val.*)
    %   executed on the virtual rig. Passing here means the PROCEDURES work;
    %   it says nothing about the real hardware (those tests remain PENDING).

    properties
        cfg
    end

    methods (TestMethodSetup)
        function setup(tc)
            f = tc.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            c = tim.app.defaultConfig();
            c.geometry = c.simulation.Geometry;
            c.output.dataDir = fullfile(f.Folder, 'data');
            c.output.calibrationDir = fullfile(f.Folder, 'cal');
            c.excitation.sweep.duration = 3; c.excitation.sweep.repetitions = 2;
            c.calibration.repeatConfigI = false;
            tc.cfg = c;
        end
    end

    methods
        function s = session(tc, c)
            if nargin < 2, c = tc.cfg; end
            s = tim.app.MeasurementSession(c);
            s.connect(); s.prepareAcquisition();
        end
    end

    methods (Test)
        function testA(tc)
            s = tc.session(); c = onCleanup(@() s.close());
            r = tim.val.testA_acquisition(s, 1);
            tc.verifyTrue(r.passed);
            tc.verifyEqual(r.unit, {'V', 'V', 'V', 'V'});
        end

        function testB(tc)
            s = tc.session(); c = onCleanup(@() s.close());
            r = tim.val.testB_singleFrequency(s, 1000, 0.2, 3);
            tc.verifyTrue(r.passed);
            tc.verifyEqual(r.clockOffset_ppm, 35, 'AbsTol', 2);     % simulated generator offset
            tc.verifyFalse(s.Gen.isOutputOn());
        end

        function sweepTiming(tc)
            s = tc.session(); c = onCleanup(@() s.close());
            r = tim.val.sweepTimingTest(s);
            tc.verifyTrue(r.passed);
            tc.verifyGreaterThan(r.apparentLatency_s, 0);
        end

        function testC(tc)
            s = tc.session(); c = onCleanup(@() s.close());
            cal = tim.app.runCalibration(s);
            mA = s.measure('sweep');
            home = [1 2 3 4];
            sw = home; sw([1 2]) = [2 1];                    % interchange mics of ch1/ch2
            s.setMicPositionsForSimulation(sw);
            mB = s.measure('sweep');
            s.setMicPositionsForSimulation(home);
            r = tim.val.testC_calibrationConsistency(cal, mA, mB, tc.cfg, [1 2]);
            tc.verifyTrue(r.passed);
            tc.verifyLessThan(r.after_rms_dB, r.before_rms_dB);
            % audit 2026-10-11: the estimator of the calibration (sweep gate)
            tc.verifyTrue(all(r.gated), 'Test C uses the sweep gate');
        end

        function testBPhaseNear180Degrees(tc)
            % audit 2026-10-11: a relative phase at +-180 deg; repeats on both
            % sides of the branch cut must not average to about 60 deg with a
            % scatter of 200 deg. ch4 is set to exactly 180 deg at 1 kHz by
            % shifting its chain delay in the virtual rig.
            s = tc.session(); c = onCleanup(@() s.close());
            f = 1000; rig = s.Rig;
            rig.GenClockPpm = 0;                                % the tone exactly at f (no 35 ppm offset)
            for it = 1:4                                        % the realised FIR converges in a few steps
                t = rig.trueResponse([f; f + 1]);               % (a scalar would be a number of points)
                dphi = angle(-t.G(1, 4) / t.G(1, 1));           % phase that is missing to 180 deg
                rig.Tau(4) = rig.Tau(4) + dphi / (2 * pi * f);
                rig.MicPosOfChannel = rig.MicPosOfChannel;      % re-design the channel responses
            end
            t = rig.trueResponse([f; f + 1]);
            tc.assertLessThan(abs(abs(rad2deg(angle(t.G(1, 4) / t.G(1, 1)))) - 180), 1e-3);
            r = tim.val.testB_singleFrequency(s, f, 0.2, 8);
            tc.verifyLessThan(abs(abs(r.relPhase_deg(4)) - 180), 0.05, 'relative phase about 180 deg');
            tc.verifyLessThan(r.scatter_deg(4), 0.2, 'scatter of the repeats, not of the branch cut');
            tc.verifyTrue(r.passed);
        end

        function testDrigid(tc)
            % rigid plug 5 cm behind xFront, i.e. UPSTREAM of M3/M4 (0.071/0.100 m):
            % as in the lab with the plug in the specimen section, M3/M4 sit behind
            % the plug and receive no sound (virtual tube: p = 0 there, only noise).
            % Test D uses the upstream pair only (formula review calval-1).
            c = tc.cfg;
            c.simulation.Sample = struct('type', 'air');
            c.simulation.Geometry.xRear = 0; c.geometry.xRear = 0;
            c.simulation.Termination = struct('R', 1, 'x', 0.05);
            s = tc.session(c); cl = onCleanup(@() s.close());
            cal = tim.app.runCalibration(s);
            res = tim.app.processMeasurement(s.measure('sweep'), c, cal);
            t = s.Rig.trueResponse(res.analysis.f);
            tc.verifyEqual(t.p(:, 3:4), zeros(numel(res.analysis.f), 2), 'no sound behind the plug');
            r = tim.val.testDE_reference(res, 'rigid', struct('L', 0.05));
            tc.verifyTrue(r.passed);
            tc.verifyGreaterThan(r.validBins, 0.5 * nnz(res.analysis.valid.measured));
            tc.verifyEqual(r.nonPassiveBins, 0);
            tc.verifyEmpty(r.warning);
            % the all-position mask fails (M3/M4 noise); R stays valid from M1/M2
            tc.verifyLessThan(nnz(res.analysis.valid.valid), 0.05 * r.validBins);
            tc.verifyGreaterThan(nnz(res.analysis.valid.validR), 0.5 * r.validBins);
        end

        function testEempty(tc)
            c = tc.cfg;
            c.simulation.Sample = struct('type', 'air');
            c.simulation.Termination = struct('R', 0.3, 'x', 0.6);    % NOT anechoic on purpose
            s = tc.session(c); cl = onCleanup(@() s.close());
            cal = tim.app.runCalibration(s);
            res = tim.app.processMeasurement(s.measure('sweep'), c, cal);
            r = tim.val.testDE_reference(res, 'empty', struct());
            tc.verifyTrue(r.passed);
        end
    end
end
