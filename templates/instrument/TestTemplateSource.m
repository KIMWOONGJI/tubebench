classdef TestTemplateSource < matlab.unittest.TestCase
    %TESTTEMPLATESOURCE TEMPLATE of a driver test: TemplateSource on its protocol mock.
    %
    %   THIS IS A TEMPLATE. Copy it to tests/Test<Name>.m with the same
    %   replacements as the driver ('TemplateSource' -> '<Name>',
    %   'templatesource' -> '<registry name>'; docs/adding_an_instrument.md,
    %   steps 3 and 9). tests/TestInstrumentContract checks the contract duties
    %   of every registered driver; this class checks what is particular to
    %   YOUR instrument: the identification, the commands and their order as
    %   the manual requires them, the instrument's error reporting, and one
    %   simulated measurement through the session with the default DAQ driver.
    %   Lines marked TODO name instrument facts (model text, command strings);
    %   then replace this paragraph by a description of your test.

    methods (Test)
        function connectsWithOutputOffAndIdentifies(tc)
            tr = tim.instr.MockTemplateSource();
            g = tim.instr.TemplateSource(tr, 1, 'INF');
            tc.addTeardown(@() g.close());
            tc.verifyEqual(g.identity().model, 'TEMPLATE-GEN');              % TODO model as reported
            tc.verifyNotEmpty(g.identity().serial);
            k = find(startsWith(tr.Log, '> '), 2);
            tc.verifyEqual(tr.Log(k(2)), {'> OUTP OFF'}, ...                 % TODO output-off command
                'the first command after the identification switches the output off');
            tc.verifyFalse(g.isOutputOn());
            tc.verifyEmpty(tr.LevelLog, 'no level is programmed at connect');
        end

        function otherInstrumentRefused(tc)
            tr = tim.instr.MockTemplateSource();
            tr.IdnString = 'Other vendor,MODEL-X,123,1.0';
            tc.verifyError(@() tim.instr.TemplateSource(tr, 1, 'INF'), 'tim:templatesource:identity');
        end

        function sweepCommandsInTheOrderOfTheManual(tc)
            tr = tim.instr.MockTemplateSource();
            g = tim.instr.TemplateSource(tr, 1, 'INF');
            tc.addTeardown(@() g.close());
            s = struct('fStart', 80, 'fStop', 5500, 'duration', 5, 'spacing', 'LOG', 'amplitudeVpp', 0.2);
            g.configureSweep(s);
            L = tr.Log;
            iOn = find(strcmp(L, '> SWE:STAT ON'), 1);                       % TODO sweep-on command
            iTrig = find(strcmp(L, '> TRIG:SOUR BUS'), 1);                   % TODO trigger-source command
            iTime = find(startsWith(L, '> SWE:TIME'), 1);                    % TODO sweep-time command
            tc.verifyTrue(iTrig < iOn && iTime < iOn, 'the sweep is enabled last (manual)');
            tc.verifyFalse(any(strcmp(L, '> OUTP ON')), 'configureSweep never switches the output on');
            tc.verifyEqual(tr.State.spacing, 'LOG');
            tc.verifyFalse(g.isOutputOn());
        end

        function instrumentErrorsSurface(tc)
            tr = tim.instr.MockTemplateSource();
            g = tim.instr.TemplateSource(tr, 1, 'INF');
            tc.addTeardown(@() g.close());
            tr.fault('error');
            tc.verifyError(@() g.configureSine(1000, 0.1), 'tim:templatesource:instrumentError');
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
            c.generator.driver = 'templatesource';
            c.excitation.sweep = struct('fStart', 200, 'fStop', 4000, 'duration', 1, 'spacing', 'LOG', ...
                'amplitudeVpp', 0.2, 'repetitions', 1, 'preRoll', 0.5, 'postRoll', 0.5);
            s = tim.app.MeasurementSession(c);
            tc.addTeardown(@() s.close());
            s.connect(); s.prepareAcquisition();
            meas = s.measure('sweep');
            tc.verifyTrue(meas.integrityOk);
            tc.verifyFalse(s.Gen.isOutputOn(), 'output off after the measurement');
            tc.verifyEqual(meas.metadata.generator.driver, 'templatesource');
            tc.verifyEqual(meas.metadata.generator.identity, s.Gen.identity());
            ex = tim.dsp.detectExcitation(meas.records{1}(:, 1), meas.fs, [200 4000], 12, 0.5);
            tc.verifyTrue(ex.detected, 'the sweep was recorded');
            tc.verifyGreaterThan(ex.duration_s, 0.8);
        end
    end
end
