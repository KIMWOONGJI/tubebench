function cfg = defaultConfig()
%DEFAULTCONFIG Default configuration of the transfer impedance tube system.
%
%   cfg = tim.app.defaultConfig()
%   Edit config/user_config.json (see config/example_config.json) rather
%   than this file; tim.app.loadConfig merges a JSON file onto these defaults.
%   All quantities in SI units. NaN = "not provided" (never invented).

cfg = struct();
cfg.formatVersion = 2;                  % 2: instruments selected by driver (tim.app.migrateConfig reads 1)
cfg.mode = 'simulation';                % 'simulation' | 'hardware'
cfg.projectName = 'tubebench';
cfg.ui = struct('language', 'en', ...  % operator prompts and confirmations (tim.app.msg): 'en' (default) | 'ko'
    'amplitudeAt', 'generator');        % what the window's amplitude field gives: 'generator' (the programmed
                                        % level: open circuit in direct drive, the amplifier input with an
                                        % amplifier; default) | 'loudspeaker' (the window computes the generator
                                        % level, tim.app.generatorAmplitude; with an amplifier it needs the gain).
                                        % The excitation amplitudes below are always the generator's.

% ---------------- instruments ----------------
% generator.driver and daq.driver select the instrument drivers (registry
% tim.instr.drivers; docs/instrument_interface.md). Each driver keeps its own
% settings in a sub-struct named after it, with the driver's defaults
% (describe().defaults.settings): generator.keysight33220a (host, port,
% timeout), daq.lanxi (host, timeout, connector). A driver that takes both
% roles is named in both sections and reads daq.<driver>.
% maxVpp and load are the same for every generator; their allowed values
% come from the driver (capabilities().source). maxVpp limits the OPEN-CIRCUIT
% voltage at the generator terminals, whatever the load setting (WO-004).
% 33220A: the source impedance is always 50 ohm and OUTP:LOAD only rescales
% the programmed amplitude: 'INF' -> VOLT is the open-circuit voltage; a
% resistance R ('50', '600', 1 .. 10000) -> VOLT is the voltage across R
% (open circuit = VOLT x (R + 50) / R). With an amplifier the window sets the
% load to the amplifier's input impedance; direct drive uses 'INF'.
gen = tim.instr.driverInfo('keysight33220a');
cfg.generator = struct('driver', gen.name, ...
    'maxVpp', 0.5, ...                  % SAFETY LIMIT for amplifier/loudspeaker [Vpp, open circuit]
    'load', 'INF', ...                  % 'INF' (direct drive; high-Z amplifier input) | the amplifier input in ohm as text ('50', '600')
    'allowUnconfirmedOff', false, ...   % true: accept a generator that cannot report its output state (hardware)
    gen.name, gen.defaults.settings);
% Power amplifier between 33220A and loudspeaker. Its gain is set BY HAND
% on the amplifier (not remote controlled); record it here (or in the GUI /
% s.setAmplifier) - it is stored with every measurement and confirmed by
% the operator before the loudspeaker is driven.
cfg.amplifier = struct('model', '', ...
    'gainFactor', NaN, ...              % voltage gain as a multiplier (x10 -> 10); 1 for direct drive; NaN = unknown
    'gainSetting', '', ...              % free text, e.g. knob position as written on the amplifier
    'gain_dB', NaN, ...                 % = 20*log10(gainFactor), kept for the metadata
    'inputImpedance_ohm', NaN, ...      % amplifier input [ohm] (data sheet); NaN = from generator.load (INF: high-Z)
    'knownModels', {{'none (direct drive)', 'power amplifier'}}, ...  % GUI drop-down items (typed models are added)
    'confirmBeforeExcitation', true);   % ask operator before driving the loudspeaker (hardware mode)
% Loudspeaker data: used to estimate the electrical drive (voltage, current,
% power) from generator amplitude x amplifier gain, and to REFUSE excitation
% above maxPower_W (the test limit; at most ratedPower_W). The power is taken
% at the NOMINAL impedance, P = Vrms^2 / Z (sine / sweep: Vrms = Vpk/sqrt(2);
% noise: Vpk / crest factor); 80 % of maxPower_W and more is shown as "near
% the limit" (tim.app.driveEstimate).
cfg.loudspeaker = struct('impedance_ohm', 8, 'ratedPower_W', 25, 'maxPower_W', 1.0);
% LAN-XI: daq.lanxi.connector 'BNC' | 'LEMO' (the 3676 supports both; must match the cabling);
% '' (files of 1.1.0) sends no ConnectorSelect: the module keeps its own setting
daq = tim.instr.driverInfo('lanxi');
cfg.daq = struct('driver', daq.name, daq.name, daq.defaults.settings);

% ---------------- acquisition ----------------
% Generic settings of the DAQ inputs. sampleRate, range, filter and ccld:
% empty (JSON null or '') = the default of the DAQ driver; the allowed values
% come from the driver (capabilities().acquisition). Defaults below: lanxi
% (3676: 4096|8192|16384|32768|65536 S/s, '1 Vpeak'|'10 Vpeak', module filters).
a = daq.defaults.acquisition;
cfg.acquisition = struct('sampleRate', a.sampleRate, ...  % S/s
    'range', a.range, ...               % input range
    'filter', a.filter, ...             % high-pass / coupling
    'ccld', a.ccld, ...                 % CCLD (IEPE) supply per input
    'detectTeds', true, ...
    'settleTime', 3, ...                % s after configuration (CCLD + high-pass settling)
    'maxPeakFraction', 0.8, ...         % warn above this fraction of the input range
    'sensitivityPolicy', 'certificate>teds>nominal');

% ---------------- microphones ----------------
% channel  = DAQ input; position = tube port (1..4 = M1..M4, M1 nearest the loudspeaker)
m = struct('channel', {1, 2, 3, 4}, 'position', {1, 2, 3, 4}, 'model', 'B&K 4957', ...
    'serial', '', 'nominalSensitivity_VperPa', 11.2e-3, ...
    'certificateSensitivity_VperPa', NaN, 'certificateDate', '');
cfg.mics = m;

% ---------------- geometry ----------------
% x axis along the tube, increasing from the loudspeaker towards the termination.
cfg.geometry = struct('diameter', 0.029, ...
    'micPositions', nan(1, 4), ...      % axial coordinates of M1..M4 [m]  (NOT YET PROVIDED)
    'spacingUp', 0.029, 'spacingDown', 0.029, ...
    'xFront', NaN, 'xRear', NaN, ...    % sample front/rear faces [m] (NOT YET PROVIDED)
    'note', 'Enter measured positions; boundary-plane quantities are disabled until then.');

% Dimensions used ONLY for the drawings (2D / 3D) of the tube, not for the
% analysis. Values from the lab CAD assembly (cad/transfer-impedance-tube.step,
% SolidWorks 2024 AP214 "Assy_SIT", read 2026-10-08 with tim.cad.readStep).
cfg.tubeDrawing = struct( ...
    'outerDiameter', 0.065, ...          % flanges, specimen section, extension, end cap [m]
    'bodyDiameter', 0.045, ...           % measurement tube between the flanges [m]
    'flangeThickness', 0.009, ...        % joint flanges [m]
    'boltCircleDiameter', 0.055, ...     % 6 x M4 per joint
    'upstreamLength', 0.095, ...         % loudspeaker end of the bore -> M1 [m]
    'downstreamTubeEnd', 0.041, ...      % M4 -> joint downstream tube / extension [m]
    'downstreamLength', 0.291, ...       % M4 -> termination face (end cap) [m]
    'endCapThickness', 0.008, ...
    'speakerHousingDiameter', 0.135, ... % large end: loudspeaker housing [m]
    'speakerHousingLength', 0.080, ...
    'speakerCavityDiameter', 0.097, ...
    'speakerFlangeDiameter', 0.127, ...  % tube flange recessed in the housing front
    'speakerFlangeThickness', 0.005, ...
    'holderDiameter', 0.022, ...         % microphone holder flange
    'holderHeight', 0.007, ...           % holder above the tube body surface
    'micDiameter', 0.007, ...            % B&K 4957
    'micLength', 0.0341, ...
    'micRecess', 0.00025, ...            % microphone tip behind the bore wall
    'portDiameter', 0.0064, ...          % hole between holder and bore
    'absorberLength', NaN, ...           % absorber at the small end [m] (NaN = not specified)
    'specimenSectionLength', 0.075, ...  % removable middle section SIT-PT-003 (mounted EMPTY for the calibration)
    'source', 'CAD Assy_SIT (SolidWorks 2024, AP214), read 2026-10-08');

% ---------------- environment ----------------
cfg.environment = struct('temperature_C', 20, 'pressure_Pa', 101325, 'relativeHumidity', 50, ...
    'c_override', [], 'rho_override', []);

% ---------------- excitation ----------------
cfg.excitation.mode = 'sweep';          % 'sweep' | 'stepped' | 'noise'
cfg.excitation.sweep = struct('fStart', 80, 'fStop', 5500, 'duration', 5, 'spacing', 'LOG', ...
    'amplitudeVpp', 0.2, 'repetitions', 4, 'preRoll', 1.0, 'postRoll', 1.0);
cfg.excitation.stepped = struct('fStart', 120, 'fStop', 4500, 'nPoints', 40, 'spacing', 'log', ...
    'amplitudeVpp', 0.2, 'settleTime', 0.3, 'recordTime', 0.5, 'nBlocks', 4, 'repetitions', 1);
cfg.excitation.noise = struct('amplitudeVpp', 0.2, 'duration', 20, 'nfft', 8192, 'preRoll', 1.0);

% ---------------- measurement method and terminations (WO-005) ----------------
% method: 'oneLoad' (one measurement with the termination loadA; tau, alpha_d
% and the TL from tau need an anechoic termination) | 'oneLoadSymmetric' (the
% transfer matrix from one measurement, valid only for a front-to-back
% symmetric, reciprocal specimen; ASTM E2611) | 'twoLoad' (loads A and B,
% ASTM E2611; tim.app.runTwoLoad). A load is a termination kind ('absorber',
% 'rigid', 'open') at a place ('tubeEnd', 'joint'; the absorber only at the
% tube end): tim.app.describeLoad. Every measurement records its termination.
cfg.measurement = struct('method', 'oneLoad', ...
    'loadA', struct('kind', 'absorber', 'place', 'tubeEnd'), ...  % also the termination of a one-load measurement
    'loadB', struct('kind', 'rigid', 'place', 'tubeEnd'), ...
    'repeatLoadA', true, ...            % A -> B -> A': T(A,B) and T(A',B) compared (nothing moved)
    'loadBLevel_dB', 0, ...             % level of load B relative to load A [dB] (<= 0: only lower)
    'levelStepWarn_dB', 10, ...         % warn when the peak level of load B exceeds load A by this much
    'maxTemperatureDiff_C', 1, ...      % warn when the loads differ more in temperature
    'maxMinutesBetween', 30);           % warn when the loads lie further apart in time

% ---------------- analysis ----------------
% lossModel: 'kirchhoff' (visco-thermal wide-tube losses, k = w/c + (1-j)k'',
% matching Zc; default) | 'iso10534' (ISO 10534-2 attenuation only, Re k = w/c,
% Zc = rho c) | 'none'. Used by the analysis, Test D/E and the virtual rig.
% bandMode: 'fixed' (fMin / fMax as set) | 'geometry' (fMin / fMax = the ASTM
% E1050 / E2611 limits of the tube, lowerFraction..upperFraction x c/s and
% 0.58 c/D, following the geometry and the temperature; tim.app.analysisBand)
% Transfer matrix (WO-005, tim.app.processTwoLoad): condQMax limits the
% condition number of the two loads' boundary states (columns scaled to unit
% length); reciprocityTol flags |det T - 1|; repeatTol limits the median
% difference of T(A,B) and T(A',B) relative to |T| (the repeat of load A).
cfg.analysis = struct('refChannel', 1, 'fMin', 120, 'fMax', 4500, 'bandMode', 'fixed', 'df', 2, ...
    'lossModel', 'kirchhoff', 'velocityRef', 'mean', 'condMax', 40, ...
    'phaseUncertainty_rad', 0.002, 'maxPhaseSensitivity', 0.05, ...
    'coherenceMin', 0.98, 'snrMin_dB', 20, 'validatedBands', zeros(0, 2), ...
    'lowerFraction', 0.01, 'upperFraction', 0.40, 'passivityTol', 0.05, ...
    'velocityMismatchMax', 0.10, 'anechoicRmax', 0.1, ...
    'condQMax', 10, 'reciprocityTol', 0.1, 'repeatTol', 0.05);

% ---------------- calibration ----------------
cfg.calibration = struct('file', '', ...      % path of the complex calibration MAT file
    'positions', [1 2], ...                   % tube ports a,b used for switching
    'repeatConfigI', true, ...
    'verifyEmptySection', true, ...           % Test E sweep with the EMPTY section after the switching steps
    'coherenceMin', 0.98, 'snrMin_dB', 20);

% ---------------- output ----------------
cfg.output = struct('dataDir', 'data', 'calibrationDir', 'calibration', ...
    'saveRawStream', true, 'exportCsv', true, 'exportFigures', true, ...
    'figureFormats', {{'png'}});      % PNG only; 'pdf' (vector, slow), 'svg', 'fig' on request

% ---------------- simulation (virtual rig, used only in simulation mode) ----
sg = struct('diameter', 0.029, 'micPositions', [-0.150, -0.121, 0.071, 0.100], ...
    'spacingUp', 0.029, 'spacingDown', 0.029, 'xFront', 0, 'xRear', 0.010);
cfg.simulation = struct('Geometry', sg, ...
    'Sample', struct('type', 'porous', 'sigma', 2e4), ...
    'Termination', struct('R', 0.05, 'x', 0.6), ...
    'NoisePa', 2e-3, 'GenClockPpm', 35, 'Seed', 1);
end
