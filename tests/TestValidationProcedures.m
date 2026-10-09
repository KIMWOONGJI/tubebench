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
