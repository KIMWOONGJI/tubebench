classdef TestTemplateAcquisition < matlab.unittest.TestCase
    %TESTTEMPLATEACQUISITION TEMPLATE of a driver test: TemplateAcquisition on its protocol mock.
    %
    %   THIS IS A TEMPLATE. Copy it to tests/Test<Name>.m with the same
    %   replacements as the driver ('TemplateAcquisition' -> '<Name>',
    %   'templateacquisition' -> '<registry name>'; docs/adding_an_instrument.md,
    %   steps 3 and 9). tests/TestInstrumentContract checks the contract duties
    %   of every registered driver; this class checks what is particular to
    %   YOUR device: the settings it refuses, the words of its fault flags, and
    %   one simulated measurement through the session with the default
    %   generator driver. Lines marked TODO name device facts (unsupported
    %   values, fault words); then replace this paragraph by a description of
    %   your test.

    methods
        function cfg = config(~)
            % simulation configuration selecting the driver; the inputs at the
            % driver's defaults, as in a configuration file that only names it
            cfg = tim.app.defaultConfig();
            cfg.geometry = cfg.simulation.Geometry;
            cfg.daq = struct('driver', 'templateacquisition');
            cfg.acquisition.sampleRate = []; cfg.acquisition.range = ''; cfg.acquisition.filter = ''; cfg.acquisition.ccld = [];
            cfg = tim.app.migrateConfig(cfg);                % empty values -> the driver's defaults
        end

        function [acq, dev, cfg] = make(tc)
            cfg = tc.config();
            ctx = struct('mode', 'simulation', 'rig', tim.sim.SimulatedRig(cfg), 'progress', []);
            acq = tim.instr.create('acquisition', cfg, ctx);
            tc.addTeardown(@() acq.close());
            dev = acq.Dev;
        end

        function c = channelSetup(~, cfg)
            a = cfg.acquisition;
            c = struct('sampleRate', a.sampleRate, 'range', a.range, 'filter', a.filter, 'ccld', a.ccld, ...
                'channels', 1:4, 'detectTeds', a.detectTeds, 'names', {{'M1', 'M2', 'M3', 'M4'}});
        end
    end

    methods (Test)
        function connectsIdleAndIdentifies(tc)
            [acq, dev] = tc.make();
            tc.verifyEqual(acq.identity().model, 'TEMPLATE-DAQ');           % TODO model as reported
            tc.verifyFalse(dev.Running, 'idle after connecting');
            tc.verifyFalse(acq.isAcquiring());
        end

        function unsupportedSettingsRefused(tc)
            [acq, ~, cfg] = tc.make();
            c = tc.channelSetup(cfg);
            bad = c; bad.sampleRate = 48000;                                % TODO a rate the device cannot run exactly
            tc.verifyError(@() acq.prepare(bad), 'tim:templateacquisition:rate');
            bad = c; bad.range = '31.6 Vpeak';                             % TODO a range it does not have
            tc.verifyError(@() acq.prepare(bad), 'tim:templateacquisition:range');
            bad = c; bad.filter = 'DC';                                     % TODO a filter it does not have
            tc.verifyError(@() acq.prepare(bad), 'tim:templateacquisition:filter');
            acq.prepare(c);
            tc.verifyEqual(acq.SampleRate, cfg.acquisition.sampleRate);
        end

        function faultFlagsInWords(tc)
            [acq, dev, cfg] = tc.make();
            acq.prepare(tc.channelSetup(cfg));
            dev.fault('channel', 3);
            [~, info] = acq.acquire(4096);
            tc.verifyFalse(info.integrity.ok);
            tc.verifyEqual(info.integrity.channelFaults{3}, ...
                {'input fault reported by the device (open circuit or IEPE supply)'});   % TODO the driver's words
        end

        function measurementThroughTheSession(tc)
            % the driver as the acquisition of a simulated session with the
            % default generator driver: the sweep is recorded inside the record
            c = tc.config();
            c.excitation.sweep = struct('fStart', 200, 'fStop', 4000, 'duration', 1, 'spacing', 'LOG', ...
                'amplitudeVpp', 0.2, 'repetitions', 1, 'preRoll', 0.5, 'postRoll', 0.5);
            s = tim.app.MeasurementSession(c);
            tc.addTeardown(@() s.close());
            s.connect(); s.prepareAcquisition();
            meas = s.measure('sweep');
            tc.verifyTrue(meas.integrityOk);
            tc.verifyFalse(s.Gen.isOutputOn(), 'output off after the measurement');
            tc.verifyEqual(meas.metadata.daq.driver, 'templateacquisition');
            tc.verifyEqual(meas.metadata.daq.identity, s.Daq.identity());
            ex = tim.dsp.detectExcitation(meas.records{1}(:, 1), meas.fs, [200 4000], 12, 0.5);
            tc.verifyTrue(ex.detected, 'the sweep was recorded');
            tc.verifyGreaterThan(ex.start_s, 0.4, 'after the pre-roll');
        end
    end
end
