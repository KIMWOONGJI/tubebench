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
            c = tc.cfg;
            c.simulation.Sample = struct('type', 'air');
            c.simulation.Geometry.xRear = 0; c.geometry.xRear = 0;
            c.simulation.Termination = struct('R', 1, 'x', 0.05);     % rigid plug 5 cm behind xFront
            s = tc.session(c); cl = onCleanup(@() s.close());
            cal = tim.app.runCalibration(s);
            res = tim.app.processMeasurement(s.measure('sweep'), c, cal);
            r = tim.val.testDE_reference(res, 'rigid', struct('L', 0.05));
            tc.verifyTrue(r.passed);
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
