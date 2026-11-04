classdef TestConfiguration < matlab.unittest.TestCase
    %TESTCONFIGURATION Instrument layout of formatVersion 2 and the migration of older files.
    %
    %   docs/instrument_interface.md section 9 (WO-001 task 3): the instruments
    %   are selected by generator.driver / daq.driver, each driver keeps its
    %   settings in a sub-struct named after it, and the selected drivers
    %   check their part (tim.app.validateConfig -> checkConfig). Files and
    %   scripts of formatVersion 1 (generator.host / port / timeout, a
    %   top-level lanxi section) load with the same settings
    %   (tim.app.migrateConfig). Fixtures: tests/fixtures/config_formatVersion1.json
    %   (config/user_config.json of commit e8fb4fb) and the same settings in
    %   the new layout; tests/fixtures/saved_e8fb4fb (config.json and
    %   metadata.json of a simulated measurement saved by the e8fb4fb code).

    properties
        tmp
    end

    methods (TestMethodSetup)
        function setup(tc)
            f = tc.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            tc.tmp = f.Folder;
        end
    end

    methods (Static)
        function f = fixture(name)
            f = fullfile(fileparts(mfilename('fullpath')), 'fixtures', name);
        end
    end

    methods
        function file = writeJson(tc, s, name)
            % s as a JSON file in the temporary folder
            file = fullfile(tc.tmp, name);
            fid = fopen(file, 'w', 'n', 'UTF-8');
            fwrite(fid, unicode2native(jsonencode(s, 'PrettyPrint', true), 'UTF-8'));
            fclose(fid);
        end

        function u = fixtureStruct(~, name)
            u = jsondecode(tim.app.readTextUtf8(TestConfiguration.fixture(name)));
        end
    end

    methods (Test)
        function oldLayoutLoadsLikeNewLayout(tc)
            % the lab file of e8fb4fb (formatVersion 1) gives exactly the
            % configuration of the same settings written in the new layout
            c1 = tc.verifyWarningFree(@() tim.app.loadConfig(TestConfiguration.fixture('config_formatVersion1.json')));
            c2 = tc.verifyWarningFree(@() tim.app.loadConfig(TestConfiguration.fixture('config_formatVersion2.json')));
            tc.verifyEqual(rmfield(c1, 'configFile'), rmfield(c2, 'configFile'));
            tc.verifyEqual(c1.formatVersion, 2);
            tc.verifyFalse(isfield(c1, 'lanxi'), 'old section moved');
            tc.verifyFalse(any(isfield(c1.generator, {'host', 'port', 'timeout'})), 'old keys moved');
            tc.verifyEqual(c1.generator.driver, 'keysight33220a');
            tc.verifyEqual(c1.generator.keysight33220a, struct('host', '169.254.2.20', 'port', 5025, 'timeout', 5));
            tc.verifyEqual(c1.daq.driver, 'lanxi');
            tc.verifyEqual(c1.daq.lanxi, struct('host', '169.254.64.156', 'timeout', 10, 'connector', 'BNC'));
            tc.verifyEqual([c1.generator.maxVpp c1.acquisition.sampleRate], [2 16384]);
            tc.verifyEqual(c1.mode, 'hardware');
        end

        function configFilesLoad(tc)
            % every file of config/ loads without a warning and is written in
            % the current layout (user_config.json, the owner's lab file, since
            % 2026-10-12: D7, rewritten after the hardware check)
            root = fileparts(fileparts(mfilename('fullpath')));
            for f = {'user_config.json', 'example_config.json', 'sim_thin_screen.json'}
                c = tc.verifyWarningFree(@() tim.app.loadConfig(fullfile(root, 'config', f{1})), f{1});
                tc.verifyEqual(c.formatVersion, 2, f{1});
                tc.verifyTrue(isfield(c.generator, c.generator.driver) && isfield(c.daq, c.daq.driver), f{1});
                u = jsondecode(tim.app.readTextUtf8(fullfile(root, 'config', f{1})));
                tc.verifyEqual(u.formatVersion, 2, [f{1} ': the file shows the current layout']);
                tc.verifyFalse(isfield(u, 'lanxi'), f{1});
            end
        end

        function analysisBandFollowsTheGeometry(tc)
            % owner decision 2026-10-13: analysis.bandMode 'geometry' sets fMin / fMax
            % to the ASTM E1050 / E2611 limits of the tube (0.01-0.40 c/s and the
            % plane-wave limit 0.58 c/D), rounded inward to df; 'fixed' (default)
            % keeps them, and validateConfig says when they extend beyond the limits
            c = tim.app.defaultConfig();
            tc.verifyEqual(c.analysis.bandMode, 'fixed', 'default: as before');
            [c1, b] = tim.app.analysisBand(c);
            tc.verifyEqual([c1.analysis.fMin c1.analysis.fMax], [120 4500], 'fixed: unchanged');
            tc.verifyFalse(b.outside, '120-4500 Hz lies inside the limits of the 29 mm tube');
            tc.verifySubstring(b.text, 'fixed in the configuration; ASTM E1050 / E2611 limits of this tube 118–4735 Hz');
            air = tim.acoustics.airProperties(c.environment);
            c.analysis.bandMode = 'geometry';
            [c2, b2] = tim.app.analysisBand(c);
            tc.verifyEqual([c2.analysis.fMin c2.analysis.fMax], [120 4734], 'the lab tube at 20 °C');
            tc.verifySubstring(b2.text, 'ASTM E1050 / E2611 limits of this tube (0.01–0.4 c/s)');
            % wider spacing: a lower band; two spacings: the stricter of each limit
            g = c; g.geometry.spacingUp = 0.04; g.geometry.spacingDown = 0.04;
            g = tim.app.analysisBand(g);
            tc.verifyEqual([g.analysis.fMin g.analysis.fMax], [2 * ceil(0.01 * air.c / 0.04 / 2), 2 * floor(0.40 * air.c / 0.04 / 2)]);
            g = c; g.geometry.spacingUp = 0.02; g.geometry.spacingDown = 0.05;
            g = tim.app.analysisBand(g);
            tc.verifyEqual([g.analysis.fMin g.analysis.fMax], [2 * ceil(0.01 * air.c / 0.02 / 2), 2 * floor(0.40 * air.c / 0.05 / 2)]);
            % narrow spacing: the plane-wave limit of the diameter binds
            g = c; g.geometry.spacingUp = 0.010; g.geometry.spacingDown = 0.010;
            g = tim.app.analysisBand(g);
            tc.verifyEqual(g.analysis.fMax, 2 * floor(0.58 * air.c / 0.029 / 2));
            % warmer air: a higher speed of sound, a wider band
            g = c; g.environment.temperature_C = 30;
            g = tim.app.analysisBand(g);
            tc.verifyGreaterThan(g.analysis.fMax, 4734);
            % incomplete geometry: the configured band stays
            g = c; g.geometry.diameter = NaN;
            [g, bg] = tim.app.analysisBand(g);
            tc.verifyEqual([g.analysis.fMin g.analysis.fMax], [120 4500]);
            tc.verifySubstring(bg.text, 'incomplete');
            % loadConfig applies it; the file keeps the mode
            file = tc.writeJson(struct('formatVersion', 2, 'analysis', struct('bandMode', 'geometry', 'fMax', 4700)), 'band.json');
            cl = tc.verifyWarningFree(@() tim.app.loadConfig(file));
            tc.verifyEqual([cl.analysis.fMin cl.analysis.fMax], [120 4734], 'loaded: the band of its geometry');
            % a fixed band beyond the limits is reported; a wrong mode refused
            f = tim.app.defaultConfig(); f.geometry.spacingUp = 0.04; f.geometry.spacingDown = 0.04;
            tc.verifyTrue(any(contains(tim.app.validateConfig(f), 'extends beyond the ASTM E1050 / E2611 limits of this tube')));
            f.analysis.bandMode = 'geometry';
            tc.verifyFalse(any(contains(tim.app.validateConfig(f), 'extends beyond')));
            f.analysis.bandMode = 'astm';
            tc.verifyError(@() tim.app.validateConfig(f), 'tim:config:bandMode');
            % the analysis uses the band of the configuration it is given
            c2.mode = 'simulation'; c2.geometry = c2.simulation.Geometry;
            c2.excitation.sweep.duration = 1; c2.excitation.sweep.repetitions = 1;
            c2.output.dataDir = fullfile(tc.tmp, 'data'); c2.output.calibrationDir = fullfile(tc.tmp, 'cal');
            s = tim.app.MeasurementSession(c2); s.connect(); s.prepareAcquisition();
            tc.addTeardown(@() s.close());
            m = s.measure('sweep');
            r = tim.app.processMeasurement(m, c2, []);
            tc.verifyEqual(r.spectra.f([1 end]).', [120 4734], 'processMeasurement: the band of the geometry');
        end

        function savedMeasurementOfOldVersionLoads(tc)
            % config.json of a measurement folder saved by the e8fb4fb code
            c = tc.verifyWarningFree(@() tim.app.loadConfig(TestConfiguration.fixture(fullfile('saved_e8fb4fb', 'config.json'))));
            tc.verifyEqual(c.daq.lanxi.host, '169.254.64.156');
            tc.verifyEqual(c.generator.keysight33220a.port, 5025);
            tc.verifyEqual(c.mode, 'simulation');
        end

        function saveWritesTheNewLayout(tc)
            c = tim.app.loadConfig(TestConfiguration.fixture('config_formatVersion1.json'));
            file = fullfile(tc.tmp, 'saved.json');
            tim.app.saveConfig(c, file);
            u = jsondecode(tim.app.readTextUtf8(file));
            tc.verifyEqual(u.formatVersion, 2);
            tc.verifyFalse(isfield(u, 'lanxi'));
            tc.verifyEqual(u.daq.lanxi.connector, 'BNC');
            tc.verifyEqual(u.generator.keysight33220a.host, '169.254.2.20');
            c2 = tc.verifyWarningFree(@() tim.app.loadConfig(file));
            tc.verifyEqual(rmfield(c2, 'configFile'), rmfield(c, 'configFile'));
        end

        function oldKeysSetInCode(tc)
            % an old script that sets the old keys on the default configuration
            % keeps working: they replace the driver defaults
            c = tim.app.defaultConfig();
            c.generator.host = '10.0.0.7'; c.generator.port = 5026; c.lanxi.connector = 'LEMO';
            m = tc.verifyWarningFree(@() tim.app.migrateConfig(c));
            tc.verifyEqual(m.generator.keysight33220a, struct('host', '10.0.0.7', 'port', 5026, 'timeout', 5));
            tc.verifyEqual(m.daq.lanxi.connector, 'LEMO');
            tc.verifyEqual(m.daq.lanxi.host, '169.254.64.156');
            tc.verifyFalse(isfield(m, 'lanxi'));
            tc.verifyFalse(isfield(m.generator, 'host'));
            tc.verifyEqual(tim.app.migrateConfig(m), m, 'idempotent');
            tc.verifyEqual(tim.app.migrateConfig(tim.app.defaultConfig()), tim.app.defaultConfig(), ...
                'the defaults are already in the new layout');
            % a configuration built in code without driver names or daq section
            old = rmfield(c, 'daq'); old.generator = rmfield(old.generator, {'driver', 'keysight33220a'});
            m2 = tim.app.migrateConfig(old);
            tc.verifyEqual(orderfields(m2.generator), orderfields(m.generator));
            tc.verifyEqual(orderfields(m2.daq), orderfields(m.daq));
        end

        function bothLayoutsInOneFile(tc)
            % the new key wins; the ignored old key is named in a warning
            u = tc.fixtureStruct('config_formatVersion2.json');
            u.mode = 'simulation';
            u.generator.host = '10.0.0.1';                       % old key, ignored
            u.generator.keysight33220a.host = '10.0.0.2';
            u.lanxi = struct('connector', 'LEMO');               % old section, ignored
            file = tc.writeJson(u, 'both.json');
            c = tc.verifyWarning(@() tim.app.loadConfig(file), 'tim:config:legacyField');
            tc.verifyEqual(c.generator.keysight33220a.host, '10.0.0.2');
            tc.verifyEqual(c.daq.lanxi.connector, 'BNC');
            tc.verifyFalse(isfield(c.generator, 'host'));
            tc.verifyFalse(isfield(c, 'lanxi'));
        end

        function oldKeysWithAnotherGeneratorDriver(tc)
            % generator.host is a 33220A setting: with another generator driver
            % it is not used, and the warning says where that driver's setting goes
            c = tim.app.defaultConfig();
            c.generator.driver = 'othersource'; c.generator.host = '10.0.0.9';
            ws = warning('off', 'tim:config:driver'); restore = onCleanup(@() warning(ws));
            m = tc.verifyWarning(@() tim.app.migrateConfig(c), 'tim:config:legacyField');
            tc.verifyEqual(m.generator.driver, 'othersource');
            tc.verifyFalse(isfield(m.generator, 'host'));
            tc.verifyEqual(m.generator.keysight33220a.host, '10.0.0.9', 'kept with the 33220A settings');
            clear restore
        end

        function unknownDriverLoadsButCannotConnect(tc)
            % a configuration of another set-up (driver not registered here)
            % loads for analysis with a warning; the session refuses it
            u = tc.fixtureStruct('config_formatVersion2.json');
            u.mode = 'simulation';
            u.daq.driver = 'otherdaq';
            u.daq.otherdaq = struct('device', 'Dev1', 'gain', 3);
            file = tc.writeJson(u, 'other.json');
            c = tc.verifyWarning(@() tim.app.loadConfig(file), 'tim:config:driver');
            tc.verifyEqual(c.daq.otherdaq, struct('device', 'Dev1', 'gain', 3), 'its settings are kept as they are');
            tc.verifyEqual(c.acquisition.sampleRate, 16384);
            ws = warning('off', 'tim:config:driver'); restore = onCleanup(@() warning(ws));
            tc.verifyError(@() tim.app.validateConfig(c, 'instruments'), 'tim:config:driver');
            tc.verifyError(@() tim.app.MeasurementSession(c), 'tim:config:driver');
            clear restore
        end

        function typoInDriverSettings(tc)
            u = tc.fixtureStruct('config_formatVersion2.json');
            u.mode = 'simulation';
            u.daq.lanxi.hots = '10.0.0.3';
            file = tc.writeJson(u, 'typo.json');
            tc.verifyWarning(@() tim.app.loadConfig(file), 'tim:config:unknownField');
        end

        function emptyAcquisitionValuesAreDriverDefaults(tc)
            % sampleRate, range, filter and ccld left out, null or '': the
            % default of the DAQ driver (describe().defaults.acquisition)
            u = tc.fixtureStruct('config_formatVersion2.json');
            u.mode = 'simulation';
            u.acquisition = rmfield(u.acquisition, 'sampleRate');
            u.acquisition.range = '';
            u.acquisition.filter = [];
            file = tc.writeJson(u, 'defaults.json');
            c = tim.app.loadConfig(file);
            def = tim.instr.driverInfo('lanxi').defaults.acquisition;
            tc.verifyEqual(c.acquisition.sampleRate, def.sampleRate);
            tc.verifyEqual(c.acquisition.range, def.range);
            tc.verifyEqual(c.acquisition.filter, def.filter);
            c = tim.app.defaultConfig(); c.acquisition.range = ''; c.acquisition.ccld = [];
            m = tim.app.migrateConfig(c);
            tc.verifyEqual(m.acquisition.range, def.range);
            tc.verifyEqual(m.acquisition.ccld, def.ccld);
            tc.verifyEqual(tim.app.defaultConfig().acquisition.sampleRate, def.sampleRate, 'defaults of the default driver');
        end

        function driversCheckTheirPart(tc)
            % the limits of the selected drivers (static checkConfig): errors
            % where the instruments are needed (the session, i.e. Connect);
            % warnings, also in the report, when a file is only loaded
            c0 = tim.app.defaultConfig();
            cases = {
                'generator.keysight33220a.port', 0, 'tim:config:port'
                'daq.lanxi.connector', 'XLR', 'tim:config:connector'
                'generator.maxVpp', 25, 'tim:config:maxVpp'             % 33220A: 20 Vpp at load INF
                'acquisition.sampleRate', 12000, 'tim:config:fs'        % 3676 rates
                'acquisition.range', '5 Vpeak', 'tim:config:range'
                'excitation.sweep.duration', 600, 'tim:config:sweep'    % 33220A: at most 500 s
                'excitation.sweep.amplitudeVpp', 0.01, 'tim:config:amplitude'  % 33220A: 20 mVpp minimum at INF
                'generator.driver', 'lanxi', 'tim:config:driver'        % not a signal source
                'daq.driver', 'keysight33220a', 'tim:config:driver'};
            for i = 1:size(cases, 1)
                c = setPath(c0, cases{i, 1}, cases{i, 2});
                tc.verifyError(@() tim.app.validateConfig(c, 'instruments'), cases{i, 3}, cases{i, 1});
                tc.verifyError(@() tim.app.MeasurementSession(c), cases{i, 3}, cases{i, 1});
                rep = tc.verifyWarning(@() tim.app.validateConfig(c), cases{i, 3}, cases{i, 1});
                tc.verifyTrue(any(contains(rep, 'connect')), [cases{i, 1} ': named in the report']);
            end
            tc.verifyEmpty(tim.app.validateConfig(setPath(c0, 'geometry', c0.simulation.Geometry)));
        end

        function filesOfVersion110StillLoad(tc)
            % values that 1.1.0 accepted and wrote (its window's amplitude went
            % down to 0.005 Vpk = 0.01 Vpp, written into all three signals;
            % generator.maxVpp up to 20 Vpp at any load; any sweep time; LAN-XI
            % connector '') still load. A level below the generator minimum
            % matters only for the swept sine (calibration, Test E) and the
            % selected signal; Connect refuses what the driver cannot do.
            u0 = tc.fixtureStruct('config_formatVersion1.json');
            u0.mode = 'simulation';
            cases = {   % path, value, warning when loaded ('' = none), error at Connect ('' = connects)
                'excitation.stepped.amplitudeVpp', 0.01, '', ''
                'excitation.noise.amplitudeVpp', 0.015, '', ''
                'excitation.sweep.amplitudeVpp', 0.01, 'tim:config:amplitude', 'tim:config:amplitude'
                'generator.maxVpp', 25, 'tim:config:maxVpp', 'tim:config:maxVpp'
                'excitation.sweep.duration', 600, 'tim:config:sweep', 'tim:config:sweep'
                'lanxi.connector', '', '', ''};
            for i = 1:size(cases, 1)
                u = setPath(u0, cases{i, 1}, cases{i, 2});
                if strcmp(cases{i, 1}, 'generator.maxVpp')
                    % 1.1.0 allowed maxVpp up to 20 Vpp also at load 50; since 1.3.0 it is the
                    % open-circuit voltage (WO-004), at most the 33220A's 20 Vpp at any load
                    u.generator.load = '50'; u.amplifier.model = 'power amplifier'; u.amplifier.inputImpedance_ohm = 50;
                end
                file = tc.writeJson(u, sprintf('v110_%d.json', i));
                if isempty(cases{i, 3})
                    c = tc.verifyWarningFree(@() tim.app.loadConfig(file), cases{i, 1});
                else
                    c = tc.verifyWarning(@() tim.app.loadConfig(file), cases{i, 3}, cases{i, 1});
                end
                if isempty(cases{i, 4})
                    s = tc.verifyWarningFree(@() tim.app.MeasurementSession(c), cases{i, 1});
                    s.close();
                else
                    tc.verifyError(@() tim.app.MeasurementSession(c), cases{i, 4}, cases{i, 1});
                end
            end
            % connector '': no ConnectorSelect is sent, the module keeps its own setting (as 1.1.0)
            c = tim.app.loadConfig(tc.writeJson(setPath(u0, 'lanxi.connector', ''), 'connector.json'));
            s = tim.app.MeasurementSession(c);
            tc.addTeardown(@() s.close());
            s.connect(); s.Daq.Verbose = false; s.prepareAcquisition();
            tc.verifyEqual(s.Daq.metadata().connector, '');
            % the noise level below the minimum is refused when it is played (before any level command)
            u = setPath(u0, 'excitation.noise.amplitudeVpp', 0.01);
            c = tim.app.loadConfig(tc.writeJson(u, 'noise.json'));
            s2 = tim.app.MeasurementSession(c);
            tc.addTeardown(@() s2.close());
            ex = c.excitation; ex.mode = 'noise';
            tc.verifyError(@() s2.setExcitation(ex), 'tim:config:amplitude', 'selected: checked by the session');
        end

        function misplacedDriverSettingsWarn(tc)
            % a device in both roles reads its settings from daq.<driver>: the
            % same settings in the generator section are never used - a warning
            % when the file is loaded and when the driver connects
            u = tc.fixtureStruct('config_formatVersion2.json');
            u.mode = 'simulation';
            u.generator.driver = 'simcombined'; u.daq.driver = 'simcombined';
            u.generator.simcombined = struct('blockSamples', 4096, 'serial', 'MISPLACED');
            file = tc.writeJson(u, 'misplaced.json');
            c = tc.verifyWarning(@() tim.app.loadConfig(file), 'tim:config:misplacedSettings');
            ctx = struct('mode', 'simulation', 'rig', tim.sim.SimulatedRig(c), 'progress', []);
            dev = tc.verifyWarning(@() tim.instr.create('source', c, ctx), 'tim:config:misplacedSettings');
            tc.addTeardown(@() dev.close());
            tc.verifyEqual(dev.metadata().settings.serial, 'SIM-0001', 'generator.simcombined is not read');
            % in daq.<driver>: used, no warning
            u.daq.simcombined = u.generator.simcombined; u.generator = rmfield(u.generator, 'simcombined');
            c = tc.verifyWarningFree(@() tim.app.loadConfig(tc.writeJson(u, 'placed.json')));
            ctx.rig = tim.sim.SimulatedRig(c);
            dev2 = tc.verifyWarningFree(@() tim.instr.create('source', c, ctx));
            tc.addTeardown(@() dev2.close());
            tc.verifyEqual(dev2.metadata().settings.serial, 'MISPLACED');
            % settings of a driver in a section of a role it does not have
            m = tim.instr.Instrument.misplacedSettings(setPath(tim.app.defaultConfig(), 'generator.lanxi', struct('host', 'x')));
            tc.verifyNumElements(m, 1);
            tc.verifySubstring(m{1}, 'daq.lanxi');
            tc.verifyEmpty(tim.instr.Instrument.misplacedSettings(tim.app.defaultConfig()));
        end

        function valuesSurviveTheJsonRoundTrip(tc)
            % audit 2026-10-11: one validated band (written as a flat array),
            % emptied lists and a microphone entry without some keys load as
            % they were meant
            c = tim.app.defaultConfig();
            c.geometry = c.simulation.Geometry;
            c.analysis.validatedBands = [200 3000];
            c.output.figureFormats = {};
            c.amplifier.knownModels = {};
            f = fullfile(tc.tmp, 'round.json');
            tim.app.saveConfig(c, f);
            c2 = tim.app.loadConfig(f);
            tc.verifyEqual(c2.analysis.validatedBands, [200 3000], 'one band: 1 x 2');
            tc.verifyEmpty(c2.output.figureFormats, 'an emptied list stays empty');
            tc.verifyEmpty(c2.amplifier.knownModels);
            c.analysis.validatedBands = [200 1000; 1500 3000];
            tim.app.saveConfig(c, f);
            tc.verifyEqual(tim.app.loadConfig(f).analysis.validatedBands, [200 1000; 1500 3000]);
            % hand-written: one band as a flat array, two bands as a flat array
            u = struct('analysis', struct('validatedBands', [200 3000]));
            tc.verifyEqual(tim.app.loadConfig(tc.writeJson(u, 'flat1.json')).analysis.validatedBands, [200 3000]);
            u.analysis.validatedBands = [200 1000 1500 3000];
            tc.verifyEqual(tim.app.loadConfig(tc.writeJson(u, 'flat2.json')).analysis.validatedBands, [200 1000; 1500 3000]);
            % a microphone entry without "serial" and "certificateDate"
            u = tc.fixtureStruct('config_formatVersion2.json');
            u.mics = num2cell(u.mics);
            u.mics{2} = rmfield(u.mics{2}, {'serial', 'certificateDate'});
            c3 = tc.verifyWarningFree(@() tim.app.loadConfig(tc.writeJson(u, 'mics.json')));
            tc.verifyEqual([c3.mics.position], [1 2 3 4]);
            d = tim.app.defaultConfig();
            tc.verifyEqual(c3.mics(2).serial, d.mics(2).serial, 'missing key: the default');
        end

        function invalidCalibrationAndBandSettingsRefused(tc)
            % audit 2026-10-11: settings that used to fail only deep inside the
            % calibration or the analysis are refused when the file is checked
            c = tim.app.defaultConfig();
            b = c; b.calibration.positions = [2 2];
            tc.verifyError(@() tim.app.validateConfig(b), 'tim:config:calPositions');
            b.calibration.positions = [1 5];
            tc.verifyError(@() tim.app.validateConfig(b), 'tim:config:calPositions');
            b = c; b.calibration.coherenceMin = 1.5;
            tc.verifyError(@() tim.app.validateConfig(b), 'tim:config:calQuality');
            b = c; b.calibration.snrMin_dB = NaN;
            tc.verifyError(@() tim.app.validateConfig(b), 'tim:config:calQuality');
            b = c; b.analysis.validatedBands = [200; 3000];
            tc.verifyError(@() tim.app.validateConfig(b), 'tim:config:validatedBands');
            b.analysis.validatedBands = [3000 200];
            tc.verifyError(@() tim.app.validateConfig(b), 'tim:config:validatedBands');
            % the sweep gate needs room outside the band; the SNR a noise-only pre-roll
            tc.verifyFalse(any(contains(tim.app.validateConfig(c), 'Swept sine')), 'default 80-5500 Hz');
            for r = [109 5500; 80 4600; 120 4500]'
                b = c; b.excitation.sweep.fStart = r(1); b.excitation.sweep.fStop = r(2);
                tc.verifyTrue(any(contains(tim.app.validateConfig(b), 'the sweep gate has no room at that end')), mat2str(r'));
            end
            b = c; b.excitation.sweep.preRoll = 0.05;
            tc.verifyTrue(any(contains(tim.app.validateConfig(b), 'pre-roll 0.05 s')));
        end

        function steppedTimingFollowsFrequency(tc)
            % owner decision 2026-11-04: a stepped-sine step settles
            % max(settleTime, settleCycles/f) and records max(recordTime,
            % recordCycles/f); without cycles the times stay fixed
            c = tim.app.defaultConfig(); st = c.excitation.stepped;
            p = tim.app.steppedPlan(st, 16384);
            f = p.freqs;
            tc.verifyEqual(f([1 end]), [120 4500], 'exact end points');
            tc.verifyEqual(p.settle_s, max(0.2, 50 ./ f));
            tc.verifyEqual(p.record_s, max(0.2, 100 ./ f));
            tc.verifyEqual(p.step_s(1), 50 / 120 + 100 / 120, 'AbsTol', 1e-12);   % 1.25 s at 120 Hz
            tc.verifyEqual(p.step_s(end), 0.4, 'AbsTol', 1e-12);
            tc.verifyEqual(p.total_s, 1 + sum(p.step_s), 'AbsTol', 1e-12);
            tc.verifyLessThan(p.total_s, 1 + 40 * 0.8, 'shorter than the former fixed 0.3 s + 0.5 s');
            tc.verifyEqual(p.recordSamples, round(p.record_s * 16384));
            tc.verifyGreaterThanOrEqual(min(p.record_s .* f) / st.nBlocks, 25 - 1e-9, 'at least 25 cycles per block');
            % a configuration without cycles (before 1.5.0, or set in code) keeps fixed times
            old = rmfield(st, {'settleCycles', 'recordCycles'}); old.settleTime = 0.3; old.recordTime = 0.5;
            q = tim.app.steppedPlan(old);
            tc.verifyEqual([unique(q.settle_s) unique(q.record_s)], [0.3 0.5]);
            b = c; b.excitation.stepped = old;
            tc.verifyFalse(any(contains(tim.app.validateConfig(b), 'Stepped sine')), 'accepted without cycles');
            % the lab file and the shipped files use the cycles
            for n = {'user_config.json', 'example_config.json', 'sim_thin_screen.json'}
                u = tim.app.loadConfig(fullfile(fileparts(fileparts(mfilename('fullpath'))), 'config', n{1}));
                tc.verifyEqual([u.excitation.stepped.settleCycles u.excitation.stepped.recordCycles], [50 100], n{1});
            end
            % invalid values refused
            for bad = {{'settleCycles', -1}, {'recordCycles', NaN}, {'settleTime', -0.1}, {'recordTime', [0.1 0.2]}}
                b = c; b.excitation.stepped.(bad{1}{1}) = bad{1}{2};
                tc.verifyError(@() tim.app.validateConfig(b), 'tim:config:stepped', bad{1}{1});
            end
            b = c; b.excitation.stepped.recordTime = 0; b.excitation.stepped.recordCycles = 0;
            tc.verifyError(@() tim.app.validateConfig(b), 'tim:config:stepped', 'no recording');
            % the analysed segment: one value per step, or one for all steps (saved before 1.5.0)
            m = struct('records', {{zeros(20000, 4)}}, 'events', {{struct('stepStart', [100 5100])}});
            m.settings = struct('settleSamples', [1000 500], 'recordSamples', [3000 2000]);
            tc.verifyEqual(tim.app.steppedSegment(m, 1, 1), 1101:4100);
            tc.verifyEqual(tim.app.steppedSegment(m, 1, 2), 5601:7600);
            m.settings = struct('settleSamples', 1000, 'recordSamples', 3000);
            tc.verifyEqual(tim.app.steppedSegment(m, 1, 2), 6101:9100);
        end

        function sweepMarginCheckedAtTheLimitsOfTheAnalysis(tc)
            % review 2026-10-11: the configuration check used the line centres
            % fMin/1.3 and 1.1 fMax (92 / 4950 Hz for 120-4500 Hz), the analysis
            % the outer line edges (fMin - df/2)/1.3 and 1.1 (fMax + df/2), i.e.
            % 91.5 / 4951.1 Hz: a sweep set to the advised 92 Hz or 4950 Hz passed
            % the check silently and was analysed without the gate at that end.
            % One definition now (tim.dsp.sweepGateLimits); the message prints
            % the limits the analysis uses.
            c = tim.app.defaultConfig();                        % 120-4500 Hz, df 2 Hz
            [lo, hi] = tim.dsp.sweepGateLimits(c.analysis.fMin:c.analysis.df:c.analysis.fMax, c.analysis.df);
            tc.verifyEqual([lo hi], [119 / 1.3, 1.1 * 4501], 'AbsTol', 1e-9, 'outer edges of the first and last line');
            for r = [92 5500; 80 4950; 92 4950; 91.6 5500; 80 4951]'
                b = c; b.excitation.sweep.fStart = r(1); b.excitation.sweep.fStop = r(2);
                m = tim.app.validateConfig(b);
                m = m(contains(m, 'the sweep gate has no room at that end'));
                tc.verifyNumElements(m, 1, mat2str(r'));
                tc.verifyTrue(all(contains(m, 'start at or below 91 Hz and stop at or above 4952 Hz')), mat2str(r'));
            end
            for r = [91 5500; 80 4952; 91.5 4951.2]'
                b = c; b.excitation.sweep.fStart = r(1); b.excitation.sweep.fStop = r(2);
                tc.verifyFalse(any(contains(tim.app.validateConfig(b), 'Swept sine')), mat2str(r'));
            end
            % a band that is not a whole number of lines: the last line of
            % processMeasurement's grid 120:2:4499 is 4498 Hz, its upper edge 4499 Hz,
            % so the limit is 1.1 x 4499 = 4948.9 Hz (not 1.1 x (4499 + 1))
            b = c; b.analysis.fMax = 4499; b.excitation.sweep.fStart = 80; b.excitation.sweep.fStop = 4949;
            tc.verifyFalse(any(contains(tim.app.validateConfig(b), 'Swept sine')), 'fMax 4499 Hz, stop 4949 Hz');
            b.excitation.sweep.fStop = 4948;
            tc.verifyTrue(any(contains(tim.app.validateConfig(b), 'stop at or above 4949 Hz')), 'fMax 4499 Hz, stop 4948 Hz');
        end

        function driveEstimateUsesTheDriversSourceImpedance(tc)
            % docs/instrument_interface.md D12: the drive estimate and the operator
            % text take the source impedance from the generator driver
            c = tim.app.defaultConfig();
            c.amplifier.model = 'none (direct drive)'; c.loudspeaker.impedance_ohm = 8;
            d = tim.app.driveEstimate(c, 1);
            tc.verifyEqual(d.Rs, 50, '33220A');
            tc.verifyEqual(d.Vspk_pk, 0.5 * 8 / 58, 'RelTol', 1e-12);
            c.generator.driver = 'unknownsource';
            d0 = tim.app.driveEstimate(c, 1);
            tc.verifyEqual(d0.Rs, 0, 'unknown driver: the worst case');
            tc.verifyEqual(d0.Vspk_pk, 0.5, 'RelTol', 1e-12);
            tc.verifyGreaterThan(d0.P_W / d.P_W, 50, 'about 50 x the power of a 50 ohm estimate at 8 ohm');
            tc.verifySubstring(tim.app.msg('en', 'ampDirect', 50, 8, 1, 2, 3, 4), 'via the 50 Ω generator output');
            tc.verifySubstring(tim.app.msg('en', 'ampDirect', 0, 8, 1, 2, 3, 4), 'via the 0 Ω generator output');
        end

        function loudspeakerVoltageGivesTheGeneratorLevel(tc)
            % owner decision 2026-10-12 (WO-003): in direct drive the level may be
            % given at the loudspeaker; tim.app.generatorAmplitude is the inverse
            % of the drive estimate (33220A at High Z, 8 ohm: 10 mVpk at the
            % loudspeaker = 72.5 mVpk programmed); ui.amplitudeAt is checked
            c = tim.app.defaultConfig();
            c.amplifier.model = 'none (direct drive)';
            tc.verifyEqual(c.ui.amplitudeAt, 'generator', 'default');
            for Z = [4 8 16]
                c.loudspeaker.impedance_ohm = Z;
                vpp = tim.app.generatorAmplitude(c, 0.01);
                tc.verifyEqual(tim.app.driveEstimate(c, vpp).Vspk_pk, 0.01, 'RelTol', 1e-12, sprintf('%g ohm', Z));
            end
            c.loudspeaker.impedance_ohm = 8;
            tc.verifyEqual(tim.app.generatorAmplitude(c, 0.01) / 2, 0.01 * 58 / 8, 'RelTol', 1e-12);
            % WO-004: also with an amplifier of known gain - the generator load is
            % the amplifier input, so the programmed level is the input voltage
            % (High Z: the open-circuit voltage); without the gain: refused
            a = c; a.amplifier.model = 'power amplifier'; a.amplifier.gainFactor = 10;
            tc.verifyEqual(tim.app.generatorAmplitude(a, 0.5), 2 * 0.05, 'RelTol', 1e-12, 'High Z amplifier input');
            a6 = a; a6.generator.load = '600'; a6.amplifier.inputImpedance_ohm = 600;
            tc.verifyEqual(tim.app.generatorAmplitude(a6, 0.5), 2 * 0.05, 'RelTol', 1e-12, 'load = amplifier input');
            tc.verifyEqual(tim.app.driveEstimate(a6, 0.1).Vspk_pk, 0.5, 'RelTol', 1e-12);
            n = a; n.amplifier.gainFactor = NaN; n.amplifier.gain_dB = NaN;
            tc.verifyError(@() tim.app.generatorAmplitude(n, 0.01), 'tim:gui:input', 'no gain');
            c.ui.amplitudeAt = 'loudspeaker';
            tc.verifyFalse(any(contains(tim.app.validateConfig(c), 'gain')), 'loudspeaker level with direct drive');
            a.ui.amplitudeAt = 'loudspeaker';
            tc.verifyFalse(any(contains(tim.app.validateConfig(a), 'not recorded')), 'with an amplifier of known gain');
            n.ui.amplitudeAt = 'loudspeaker';
            tc.verifyTrue(any(contains(tim.app.validateConfig(n), 'gain is not recorded')));
            c.ui.amplitudeAt = 'speaker';
            tc.verifyError(@() tim.app.validateConfig(c), 'tim:config:ui');
        end

        function amplifierInputIsTheGeneratorLoad(tc)
            % WO-004 (owner decisions 2026-10-12): generator.load 'INF' or a
            % resistance as text; with direct drive only 'INF'; generator.maxVpp is
            % the open-circuit voltage; the drive at a load of R ohm
            c = tim.app.defaultConfig(); c.generator.maxVpp = 2;
            c.amplifier.model = 'power amplifier'; c.amplifier.gainFactor = 10;
            c.generator.load = '600'; c.amplifier.inputImpedance_ohm = 600;
            c.excitation.sweep.amplitudeVpp = 0.1;
            noLoadNote = @(r) ~any(contains(r, {'generator.load', 'inputImpedance'}));
            tc.verifyTrue(noLoadNote(tim.app.validateConfig(c, 'instruments')), 'a 600 ohm amplifier input');
            d = tim.app.driveEstimate(c, 0.1);
            tc.verifyEqual(d.Voc_pp, 0.1 * 650 / 600, 'RelTol', 1e-12, 'open circuit at 600 ohm');
            tc.verifyEqual(d.Vin_pk, 0.05, 'RelTol', 1e-12, 'the programmed level is at the amplifier input');
            % maxVpp as open-circuit voltage: 1.9 Vpp into 600 ohm is 2.06 Vpp open circuit
            c.excitation.sweep.amplitudeVpp = 1.9;
            tc.verifyError(@() tim.app.validateConfig(c), 'tim:config:amplitude', 'open circuit above maxVpp');
            c.excitation.sweep.amplitudeVpp = 1.8;
            tc.verifyTrue(noLoadNote(tim.app.validateConfig(c, 'instruments')), '1.95 Vpp open circuit');
            % a numeric load with direct drive is refused; 'inf' is not 'INF'
            dd = c; dd.amplifier.model = 'none (direct drive)';
            tc.verifyError(@() tim.app.validateConfig(dd), 'tim:config:load', 'direct drive needs High Z');
            bad = c; bad.generator.load = '20000';
            tc.verifyError(@() tim.app.validateConfig(bad, 'instruments'), 'tim:config:load', 'above 10 kOhm');
            bad.generator.load = 'inf';
            tc.verifyError(@() tim.app.validateConfig(bad, 'instruments'), 'tim:config:load', 'exact text');
            % a load that differs from the amplifier input is reported; no input impedance: the risk
            m = c; m.amplifier.inputImpedance_ohm = 50;
            tc.verifyTrue(any(contains(tim.app.validateConfig(m), 'differs from the amplifier input')));
            u = c; u.amplifier.inputImpedance_ohm = NaN;
            r = tim.app.validateConfig(u);
            tc.verifyTrue(any(contains(r, 'unknown input impedance')) && any(contains(r, '1.17 ×')), strjoin(r, ' | '));
            % the level range of the 33220A scales with R / (R + 50) (manual p.189)
            s = tim.instr.Keysight33220A.capabilities().source;
            [lo, hi] = tim.instr.SignalSource.levelRange(s, '600');
            tc.verifyEqual([lo hi], [0.02 20] * 600 / 650, 'RelTol', 1e-12);
            tc.verifyEqual(tim.instr.SignalSource.levelRange(s, '50'), 0.01, 'listed load');
            tc.verifyTrue(isnan(tim.instr.SignalSource.levelRange(s, '0.5')), 'below 1 ohm');
            tc.verifyEqual(tim.instr.SignalSource.openCircuitFactor(s, 'INF'), 1);
        end

        function driveStatesAndLimits(tc)
            % WO-004: the power at the nominal impedance against the test limit
            % (ok / near from 80 % / over), noise with its crest factor, and the
            % criterion that sets the largest level (tim.app.driveLimits)
            c = tim.app.defaultConfig(); c.generator.maxVpp = 2;
            c.amplifier.model = 'power amplifier'; c.amplifier.gainFactor = 10;
            c.generator.load = '600'; c.amplifier.inputImpedance_ohm = 600;
            c.loudspeaker.impedance_ohm = 8; c.loudspeaker.maxPower_W = 1;
            vppFor = @(Vspk) 2 * Vspk / 10;                     % programmed Vpp for a loudspeaker Vpk
            tc.verifyEqual(tim.app.driveEstimate(c, vppFor(0.707)).state, 'ok');
            d = tim.app.driveEstimate(c, vppFor(3.79));
            tc.verifyEqual(d.state, 'near'); tc.verifyEqual(d.fraction, 3.79^2 / 2 / 8, 'RelTol', 1e-12);
            tc.verifyEqual(tim.app.driveEstimate(c, vppFor(4.1)).state, 'over');
            dn = tim.app.driveEstimate(c, vppFor(4.1), 'noise');
            tc.verifyEqual(dn.Vspk_rms, 4.1 / 3.3, 'RelTol', 1e-12, 'noise: peak / crest factor');
            tc.verifyEqual(dn.state, 'ok');
            n = c; n.amplifier.gainFactor = NaN;
            tc.verifyEqual(tim.app.driveEstimate(n, 0.1).state, 'unknown');
            % the speaker limit sets the maximum with this amplifier: sqrt(2 * 1 W * 8 ohm) = 4 Vpk
            L = tim.app.driveLimits(c);
            tc.verifyEqual(L.binding, 'speaker'); tc.verifyEqual(L.maxSpeakerVpk, 4, 'RelTol', 1e-12);
            tc.verifyEqual(L.maxVpp, vppFor(4), 'RelTol', 1e-12);
            % direct drive with maxVpp 2 Vpp: generator.maxVpp sets it, 1 Vpk x 8/58 at the loudspeaker
            dd = c; dd.amplifier.model = 'none (direct drive)'; dd.generator.load = 'INF';
            L = tim.app.driveLimits(dd);
            tc.verifyEqual(L.binding, 'generator'); tc.verifyEqual(L.maxSpeakerVpk, 8 / 58, 'RelTol', 1e-12);
            % the generator's own 20 Vpp when maxVpp is above it
            dd.generator.maxVpp = 30;
            tc.verifyEqual(tim.app.driveLimits(dd).binding, 'output');
            % without a gain: no loudspeaker maximum, the generator sets the level
            L = tim.app.driveLimits(n);
            tc.verifyTrue(isnan(L.maxSpeakerVpk)); tc.verifyEqual(L.binding, 'generator');
            tc.verifyEqual(L.maxVpp, 2 * 600 / 650, 'RelTol', 1e-12, 'maxVpp open circuit at 600 ohm');
            r = c; r.loudspeaker.maxPower_W = 30;
            tc.verifyTrue(tim.app.driveLimits(r).limitAboveRated, 'test limit above the rated 25 W');
        end

        function recordedMappingForReprocessing(tc)
            % owner decision 2026-10-11: a saved measurement is reprocessed with
            % the channel-to-port mapping it was recorded with
            % (tim.app.useRecordedMapping, also used by the window); only the
            % ports change, both lists may be in any order
            c = tim.app.defaultConfig();
            c.mics = c.mics([2 1 3 4]);                                    % listed ch2, ch1, ch3, ch4
            rec = struct('channel', {3, 1, 2, 4}, 'position', {3, 2, 1, 4});   % recorded: ch1 in M2, ch2 in M1
            [c2, info] = tim.app.useRecordedMapping(c, rec);
            tc.verifyEqual(info.recorded, [2 1 3 4]);
            tc.verifyEqual(info.configured, 1:4);
            tc.verifyTrue(info.differs);
            tc.verifyEqual(info.recordedText, 'ch1 M2, ch2 M1, ch3 M3, ch4 M4', 'wording of the processMeasurement warning');
            tc.verifyEqual(info.configuredText, 'ch1 M1, ch2 M2, ch3 M3, ch4 M4');
            tc.verifyEqual([c2.mics.channel], [2 1 3 4], 'list order kept');
            tc.verifyEqual([c2.mics.position], [1 2 3 4], 'ch2 in M1, ch1 in M2');
            tc.verifyEqual(rmfield(c2.mics, 'position'), rmfield(c.mics, 'position'), 'the other microphone fields kept');
            tc.verifyEqual(rmfield(c2, 'mics'), rmfield(c, 'mics'), 'nothing else changed');
            tc.verifyWarningFree(@() tim.app.validateConfig(c2, 'instruments'));
            [~, again] = tim.app.useRecordedMapping(c2, rec);
            tc.verifyFalse(again.differs);
            bad = rec; bad(2).position = 3;                                % two channels in M3
            tc.verifyError(@() tim.app.useRecordedMapping(c, bad), 'tim:config:mics');
            tc.verifyError(@() tim.app.useRecordedMapping(c, rec(1:3)), 'tim:config:mics');
            tc.verifyError(@() tim.app.useRecordedMapping(c, rmfield(rec, 'position')), 'tim:config:mics');
            tc.verifyError(@() tim.app.useRecordedMapping(c, []), 'tim:config:mics');
        end
    end
end

function c = setPath(c, path, value)
% c.(a).(b)... = value for a dotted path
parts = strsplit(path, '.');
c = setfield(c, parts{:}, value);
end
