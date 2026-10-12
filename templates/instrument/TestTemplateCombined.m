classdef TestTemplateCombined < matlab.unittest.TestCase
    %TESTTEMPLATECOMBINED TEMPLATE of a driver test: TemplateCombined on its protocol mock.
    %
    %   THIS IS A TEMPLATE. Copy it to tests/Test<Name>.m with the same
    %   replacements as the driver ('TemplateCombined' -> '<Name>',
    %   'templatecombined' -> '<registry name>'; docs/adding_an_instrument.md,
    %   steps 3 and 9). tests/TestInstrumentContract checks the contract duties
    %   of every registered driver (also the planned output of a block device);
    %   this class checks what is particular to YOUR device: 0 V before
    %   anything else, the settings it refuses, and one simulated measurement
    %   through the session with the device in both roles. Lines marked TODO
    %   name device facts (unsupported values, model text); then replace this
    %   paragraph by a description of your test.

    methods
        function cfg = config(~)
            % simulation configuration with the device in both roles; the
            % inputs at the driver's defaults (as a file that only names it)
            cfg = tim.app.defaultConfig();
            cfg.geometry = cfg.simulation.Geometry;
            cfg.generator.driver = 'templatecombined';
            cfg.daq = struct('driver', 'templatecombined');
            cfg.acquisition.sampleRate = []; cfg.acquisition.range = ''; cfg.acquisition.filter = ''; cfg.acquisition.ccld = [];
            cfg = tim.app.migrateConfig(cfg);                % empty values -> the driver's defaults
            sens = [11.2 11.5 10.9 11.3] * 1e-3;             % the virtual microphones; no TEDS: certificate values
            for i = 1:4, cfg.mics(i).certificateSensitivity_VperPa = sens(cfg.mics(i).channel); end
        end

        function c = channelSetup(~, cfg)
            a = cfg.acquisition;
            c = struct('sampleRate', a.sampleRate, 'range', a.range, 'filter', a.filter, 'ccld', a.ccld, ...
                'channels', 1:4, 'detectTeds', a.detectTeds, 'names', {{'M1', 'M2', 'M3', 'M4'}});
        end
    end

    methods (Test)
        function outputAtZeroBeforeAnythingElse(tc)
            cfg = tc.config();
            rig = tim.sim.SimulatedRig(cfg);
            dev = tim.instr.create('acquisition', cfg, struct('mode', 'simulation', 'rig', rig, 'progress', []));
            tc.addTeardown(@() dev.close());
            tc.verifyEqual(dev.Dev.Log{1}, 'output 0 V', 'the first device operation writes 0 V');
            tc.verifyEqual(rig.OutputLog(end, :), [0 0 0 0], 'the rig saw 0 V');
            tc.verifyEqual(dev.identity().model, 'TEMPLATE-DEV');           % TODO model as reported
            tc.verifyFalse(dev.isOutputOn());
        end

        function unsupportedSettingsRefused(tc)
            cfg = tc.config();
            dev = tim.instr.create('acquisition', cfg, struct('mode', 'simulation', 'rig', tim.sim.SimulatedRig(cfg), ...
                'progress', []));
            tc.addTeardown(@() dev.close());
            c = tc.channelSetup(cfg);
            bad = c; bad.sampleRate = 48000;                                % TODO a rate the device cannot run exactly
            tc.verifyError(@() dev.prepare(bad), 'tim:templatecombined:rate');
            bad = c; bad.range = '31.6 Vpeak';                             % TODO a range it does not have
            tc.verifyError(@() dev.prepare(bad), 'tim:templatecombined:range');
            dev.prepare(c);
            tc.verifyEqual(dev.SampleRate, cfg.acquisition.sampleRate);
            tc.verifyEqual(dev.Teds, {}, 'no TEDS');
        end

        function measurementThroughTheSession(tc)
            % one object in both roles: the sweep starts sample-exactly at the
            % pre-roll, the output ends at 0 V, the measurement names the driver
            c = tc.config();
            c.excitation.sweep = struct('fStart', 200, 'fStop', 4000, 'duration', 1, 'spacing', 'LOG', ...
                'amplitudeVpp', 0.2, 'repetitions', 1, 'preRoll', 0.5, 'postRoll', 0.5);
            s = tim.app.MeasurementSession(c);
            tc.addTeardown(@() s.close());
            s.connect(); s.prepareAcquisition();
            tc.verifyTrue(s.isCombined(), 'one object in both roles');
            meas = s.measure('sweep');
            tc.verifyTrue(meas.integrityOk);
            tc.verifyFalse(s.Gen.isOutputOn(), 'output off after the measurement');
            nPre = round(c.excitation.sweep.preRoll * c.acquisition.sampleRate);
            tc.verifyEqual(meas.events{1}.triggerSample, nPre, 'the sweep starts at its planned sample');
            tc.verifyEqual(meas.metadata.daq.driver, 'templatecombined');
            tc.verifyEqual(meas.metadata.daq.roles, {'source', 'acquisition'});
            tc.verifyEqual(s.Rig.OutputLog(end, 4), 0, 'the output ends at 0 V');
        end
    end
end
