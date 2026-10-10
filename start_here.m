%% START HERE - tubebench
% Four-microphone impedance tube: Keysight 33220A + HBK LAN-XI 3676 + 4x B&K 4957.
% Repository: https://github.com/kimwoongji/tubebench (private)
%
% Run this file section by section (Ctrl+Enter in the MATLAB Editor).
% Nothing here switches the generator output on until a section that
% explicitly says "MEASURE" is run. Read docs/user_guide.md first.
%
% Configuration: config/user_config.json (lab settings, tracked in Git: mode,
% microphone serials/sensitivities, GEOMETRY, limits). Commit it after changes.
% It also selects the instrument drivers (generator.driver, daq.driver; default
% 'keysight33220a' and 'lanxi', docs/instrument_interface.md).

%% 0) Paths and configuration
root = fileparts(mfilename('fullpath'));
addpath(root);
cfgFile = fullfile(root, 'config', 'user_config.json');
if isfile(cfgFile)
    cfg = tim.app.loadConfig(cfgFile);
else
    cfg = tim.app.loadConfig(fullfile(root, 'config', 'example_config.json'));
    fprintf('Using config/example_config.json (create config/user_config.json for your settings).\n');
end
warn = tim.app.validateConfig(cfg);
fprintf('Mode: %s\n', upper(cfg.mode));
fprintf('  - %s\n', warn{:});

%% 1) (optional) Graphical interface instead of the sections below
% tubebench        % real instruments (config/user_config.json)
% tubebench sim    % virtual tube (practice)

%% 2) Self-test of the software (simulation only, ~3 min)
% results = run_tests();

%% 3) Connect instruments (generator output stays OFF) and prepare acquisition
s = tim.app.MeasurementSession(cfg);
s.connect();                     % logs each instrument with the identity it reported
s.prepareAcquisition();          % DAQ inputs set up (LAN-XI: streaming state), TEDS, sensitivities

%% 4) Electrical check: 2 s without excitation (Test A)
bg = s.measureBackground(2);
disp(bg.channelInfo{1}.integrity)

%% 5) Complex microphone calibration (sensor switching) - interactive
% Follow the prompts; each step is a sweep MEASUREMENT (output ON).
% [cal, calFile] = tim.app.runCalibration(s);
% fig = tim.app.plotCalibration(cal);
% ... or load an existing calibration:
% s.loadCalibration(fullfile(root, 'calibration', 'CAL-xxxxxxxx-xxxxxx.mat'));

%% 6) MEASURE (explicit start: generator output is armed for this measurement only)
meas = s.measure();              % cfg.excitation.mode: 'sweep' | 'stepped' | 'noise'

%% 7) Process, plot, save (raw data are never overwritten)
res = tim.app.processMeasurement(meas, cfg, s.Calibration);
disp(res.summary)
figs = tim.app.plotResults(res, meas);
folder = tim.app.saveMeasurement(meas, res, cfg, 'my_sample', figs);
fprintf('Saved to %s\n', folder);

%% 8) Disconnect (output off, DAQ stopped - LAN-XI: back to Idle)
s.close();
