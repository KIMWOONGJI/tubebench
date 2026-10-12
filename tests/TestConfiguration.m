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
            % every file of config/ loads without a warning; user_config.json
            % may stay in the old layout (owner's lab file)
            root = fileparts(fileparts(mfilename('fullpath')));
            for f = {'user_config.json', 'example_config.json', 'sim_thin_screen.json'}
                c = tc.verifyWarningFree(@() tim.app.loadConfig(fullfile(root, 'config', f{1})), f{1});
                tc.verifyEqual(c.formatVersion, 2, f{1});
                tc.verifyTrue(isfield(c.generator, c.generator.driver) && isfield(c.daq, c.daq.driver), f{1});
            end
            u = jsondecode(tim.app.readTextUtf8(fullfile(root, 'config', 'sim_thin_screen.json')));
            tc.verifyEqual(u.formatVersion, 2, 'the templates show the current layout');
            tc.verifyFalse(isfield(u, 'lanxi'));
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
                'generator.maxVpp', 15, 'tim:config:maxVpp', 'tim:config:maxVpp'
                'excitation.sweep.duration', 600, 'tim:config:sweep', 'tim:config:sweep'
                'lanxi.connector', '', '', ''};
            for i = 1:size(cases, 1)
                u = setPath(u0, cases{i, 1}, cases{i, 2});
                if strcmp(cases{i, 1}, 'generator.maxVpp')         % 1.1.0: maxVpp up to 20 Vpp, also at load 50
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
            a = c; a.amplifier.model = 'power amplifier'; a.amplifier.gainFactor = 10;
            tc.verifyError(@() tim.app.generatorAmplitude(a, 0.01), 'tim:gui:input', 'direct drive only');
            c.ui.amplitudeAt = 'loudspeaker';
            tc.verifyFalse(any(contains(tim.app.validateConfig(c), 'only with direct drive')), 'loudspeaker level with direct drive');
            a.ui.amplitudeAt = 'loudspeaker';
            tc.verifyTrue(any(contains(tim.app.validateConfig(a), 'only with direct drive')));
            c.ui.amplitudeAt = 'speaker';
            tc.verifyError(@() tim.app.validateConfig(c), 'tim:config:ui');
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
