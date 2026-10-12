classdef TestDemoSource < matlab.unittest.TestCase
    %TESTDEMOSOURCE The demo signal generator DEMO-SG1 on its protocol mock (simulation only).
    %
    %   The driver test of tim.instr.DemoSource, the worked example of
    %   docs/adding_an_instrument.md (section 13), made from
    %   templates/instrument/TestTemplateSource.m. tests/TestInstrumentContract
    %   checks the contract duties of every registered driver, the demo
    %   included; this class checks what is particular to the DEMO-SG1
    %   (docs/ref_demo_source.md): the identification, the channel-numbered
    %   commands and their order, the ON / OFF output state, the refused noise,
    %   the error queue, and one simulated measurement through the session with
    %   the default DAQ driver (LAN-XI on its mock).

    methods (Test)
        function connectsWithOutputOffAndIdentifies(tc)
            tr = tim.instr.MockDemoSource();
            g = tim.instr.DemoSource(tr, 1, 'INF');
            tc.addTeardown(@() g.close());
            tc.verifyEqual(g.identity().model, 'DEMO-SG1');
            tc.verifyEqual(g.identity().serial, 'DEMO-0001');
            k = find(startsWith(tr.Log, '> '), 2);
            tc.verifyEqual(tr.Log(k(2)), {'> OUTP1:STAT OFF'}, ...
                'the first command after the identification switches the output off');
            tc.verifyFalse(g.isOutputOn());
            tc.verifyEqual(tr.Log(end-1:end), {'> OUTP1:STAT?', '< OFF'}, 'the state is read back as ON / OFF');
            tc.verifyEmpty(tr.LevelLog, 'no level is programmed at connect');
        end

        function otherInstrumentRefused(tc)
            tr = tim.instr.MockDemoSource();
            tr.IdnString = 'Other vendor,MODEL-X,123,1.0';
            tc.verifyError(@() tim.instr.DemoSource(tr, 1, 'INF'), 'tim:demo:identity');
        end

        function sweepCommandsInTheOrderOfTheManual(tc)
            tr = tim.instr.MockDemoSource();
            g = tim.instr.DemoSource(tr, 1, 'INF');
            tc.addTeardown(@() g.close());
            s = struct('fStart', 80, 'fStop', 5500, 'duration', 5, 'spacing', 'LOG', 'amplitudeVpp', 0.2);
            g.configureSweep(s);
            L = tr.Log;
            iOn = find(strcmp(L, '> SOUR1:SWE:STAT ON'), 1);
            iTrig = find(strcmp(L, '> TRIG1:SOUR BUS'), 1);
            iTime = find(startsWith(L, '> SOUR1:SWE:TIME'), 1);
            tc.verifyTrue(iTrig < iOn && iTime < iOn, 'the sweep is enabled last (ref 3.3)');
            tc.verifyFalse(any(strcmp(L, '> OUTP1:STAT ON')), 'configureSweep never switches the output on');
            tc.verifyEqual({tr.State.spacing, tr.State.start, tr.State.stop, tr.State.time}, {'LOG', 80, 5500, 5});
            tc.verifyFalse(g.isOutputOn());
        end

        function noiseRefusedWithoutTraffic(tc)
            tr = tim.instr.MockDemoSource();
            g = tim.instr.DemoSource(tr, 1, 'INF');
            tc.addTeardown(@() g.close());
            n = numel(tr.Log);
            tc.verifyError(@() g.configureNoise(0.1), 'tim:gen:unsupported', 'no noise function (ref 3.2)');
            tc.verifyEqual(numel(tr.Log), n, 'nothing is sent');
        end

        function instrumentErrorsSurface(tc)
            tr = tim.instr.MockDemoSource();
            g = tim.instr.DemoSource(tr, 1, 'INF');
            tc.addTeardown(@() g.close());
            tr.fault('error');
            tc.verifyError(@() g.configureSine(1000, 0.1), 'tim:demo:instrumentError');
            tc.verifyFalse(tr.State.output, 'output off after the error');
            g.configureSine(1000, 0.1);                                      % queue emptied: works again
            tc.verifyEqual(tr.State.freq, 1000);
        end

        function measurementThroughTheSession(tc)
            % the driver as the signal source of a simulated session with the
            % default DAQ driver: the sweep is played and recorded, the output
            % is off afterwards and the measurement names the driver
            c = tim.app.defaultConfig();
            c.geometry = c.simulation.Geometry;
            c.generator.driver = 'demo';
            c.excitation.sweep = struct('fStart', 200, 'fStop', 4000, 'duration', 1, 'spacing', 'LOG', ...
                'amplitudeVpp', 0.2, 'repetitions', 1, 'preRoll', 0.5, 'postRoll', 0.5);
            s = tim.app.MeasurementSession(c);
            tc.addTeardown(@() s.close());
            s.connect(); s.prepareAcquisition();
            meas = s.measure('sweep');
            tc.verifyTrue(meas.integrityOk);
            tc.verifyFalse(s.Gen.isOutputOn(), 'output off after the measurement');
            tc.verifyEqual(meas.metadata.generator.driver, 'demo');
            tc.verifyEqual(meas.metadata.generator.identity, s.Gen.identity());
            ex = tim.dsp.detectExcitation(meas.records{1}(:, 1), meas.fs, [200 4000], 12, 0.5);
            tc.verifyTrue(ex.detected, 'the sweep was recorded');
            tc.verifyGreaterThan(ex.duration_s, 0.8);
        end
    end
end
