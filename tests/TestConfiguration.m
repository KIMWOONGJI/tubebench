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
            % the limits of the selected drivers (static checkConfig)
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
                tc.verifyError(@() tim.app.validateConfig(c), cases{i, 3}, cases{i, 1});
            end
            tc.verifyEmpty(tim.app.validateConfig(setPath(c0, 'geometry', c0.simulation.Geometry)));
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
    end
end

function c = setPath(c, path, value)
% c.(a).(b)... = value for a dotted path
parts = strsplit(path, '.');
c = setfield(c, parts{:}, value);
end
