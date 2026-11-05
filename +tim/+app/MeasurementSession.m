classdef MeasurementSession < handle
    %MEASUREMENTSESSION Connects instruments and runs measurements.
    %
    %   s = tim.app.MeasurementSession(cfg);
    %   s.connect();                  % generator output stays OFF
    %   s.prepareAcquisition();       % DAQ inputs set up (channels, TEDS), sensitivities
    %   meas = s.measure();           % USER START: arms output, runs cfg.excitation.mode
    %   s.close();
    %
    %   Level equalizer of the stepped sine (1.6.0, WO-006): with
    %   cfg.excitation.stepped.equalizer.mode 'incidentPressure' or
    %   'faceVelocity' (and a calibration in s.Calibration), measure('stepped')
    %   runs the pre-measurement and then every step at its own level, never
    %   above excitation.stepped.amplitudeVpp; plan = s.measureEqualizerPlan()
    %   runs only the pre-measurement and arms the plan for the next stepped
    %   measurement, s.setEqualizerPlan(plan) arms a plan made before.
    %   The instruments are the drivers the configuration selects
    %   (generator.driver, daq.driver), built by the registry tim.instr.create
    %   (contract: docs/instrument_interface.md): s.Gen is the signal source,
    %   s.Daq the acquisition; a driver that takes both roles is ONE object in
    %   both. cfg.mode = 'simulation' runs the drivers on a tim.sim.SimulatedRig
    %   (s.Rig) - over their protocol mocks or, for a contract-level simulated
    %   driver, directly; 'hardware' uses the real instruments. The checklist
    %   steps and their texts come from the drivers (connectionSteps).
    %
    %   SCHEDULING ON THE RECEIVED SAMPLES: every action (output on, trigger,
    %   frequency step, output off) is scheduled on the number of samples
    %   already RECEIVED from the acquisition. Without a shared clock the true
    %   acoustic timing differs by the network/stream latency and the
    %   generator trigger latency; the design only requires that the
    %   excitation happens inside the recorded window (verified afterwards by
    %   tim.dsp.detectExcitation) - the relative microphone responses do not
    %   depend on it. A device that takes both roles on one sample clock runs
    %   the same schedule first as a planning pass (s.Daq.isPlanning()), so the
    %   actions fall sample-exactly on its timeline, and then plays and records.
    %
    %   SAFETY: generator output is armed only inside measure*(); any error
    %   switches the output off, stops the acquisition, preserves the data
    %   received so far (s.LastPartial, and an emergency file) and rethrows;
    %   an interrupt (Ctrl+C) switches it off through tim.app.outputGuard.
    %   On every abnormal end of an acquisition the acquisition driver
    %   switches the output off FIRST, before its own stop sequence
    %   (s.Daq.AbortFcn = @() s.Gen.outputOff(), set by connect).

    properties (SetAccess = private)
        Cfg struct
        Gen = []                 % signal source (tim.instr.SignalSource)
        Daq = []                 % acquisition (tim.instr.Acquisition); == Gen for a combined device
        Rig = []                 % tim.sim.SimulatedRig (simulation mode)
        Mics struct
        Status char = 'disconnected'
        LastPartial = []
        LogLines cell = {}
        ConfirmedExcitation char = ''    % signature of the last operator-confirmed excitation
        LostRole char = ''       % role whose connection checkConnection found lost ('source' | 'acquisition')
        Connected logical = false
        Prepared logical = false
        Termination = []         % termination load mounted now (tim.app.describeLoad: kind, place);
                                 % setTermination; recorded with every measurement (metadata.termination)
        EqualizerPlan = []       % level plan of the stepped-sine equalizer for the NEXT stepped measurement
                                 % (measureEqualizerPlan / setEqualizerPlan; 1.6.0, WO-006); consumed by it,
                                 % discarded when the termination, the stepped sine, the amplifier, the
                                 % geometry or the virtual specimen changes
    end
    properties
        Calibration = []
        CalibrationFile char = ''  % file of Calibration: set by loadCalibration and by
                                   % tim.app.runCalibration right after its first save
                                   % (also when the operator then cancels or stops)
        StatusCallback = []      % @(msg) for GUI
        BlockCallback = []       % @() called for every received block (GUI: drawnow limitrate)
        ExcitationConfirm = []   % @(msg) -> logical; operator confirmation of amplitude + amplifier gain
                                 % (default in hardware mode: command-window prompt)
        StopRequested logical = false
        InOperation logical = false  % inside a multi-measurement operation (calibration)
        ProgressCallback = []    % @(key, state, detail): connection checklist (GUI). keys:
                                 % the drivers' connectionSteps(), then sens, settle, signal;
                                 % state: run | ok | warn | fail | skip
    end
    properties (Hidden)
        ConsoleInput = @input    % TEST ONLY: reads the answer to the command-window confirmation
                                 % (consoleConfirm; same call as input(prompt, 's')), so that
                                 % tests/TestSessionHardwareMode can answer it without a keyboard
    end
    properties (Access = private)
        ProgressKey char = ''    % checklist step currently running (marked 'fail' on error)
        OperationDepth double = 0  % nested beginOperation calls (GUI action > calibration)
        Closed logical = false   % close() done: never shut the module down twice
        AcquireFailed logical = false  % guardedAcquire handled the error of this measurement
                                       % (output off, disarmed, partial data saved)
    end

    methods
        function obj = MeasurementSession(cfg)
            %MEASUREMENTSESSION Session on a configuration (tim.app.loadConfig or
            %   built in code; the old instrument keys are read through
            %   tim.app.migrateConfig). The drivers it selects must be registered.
            if nargin < 1, cfg = tim.app.defaultConfig(); end
            cfg = tim.app.migrateConfig(cfg);
            tim.app.validateConfig(cfg, 'instruments');
            obj.Cfg = cfg;
            obj.Mics = tim.app.MeasurementSession.micsByChannel(cfg.mics);
            if isfield(cfg, 'measurement') && isfield(cfg.measurement, 'loadA')
                obj.Termination = cfg.measurement.loadA;    % the configured termination until setTermination
            end
            if ~isempty(cfg.calibration.file)
                % a relative path is relative to the project root, as in the
                % window (tim.app.resolvePath), not to MATLAB's current folder
                obj.loadCalibration(tim.app.resolvePath(cfg.calibration.file));
            end
        end

        %% ---- connection -------------------------------------------------
        function connect(obj)
            %CONNECT Build the selected drivers through the registry: the
            %   whole selection is checked before any I/O, then each driver
            %   connects, identifies itself and puts its instrument in the safe
            %   state (output off), reporting its checklist steps. The
            %   acquisition's AbortFcn then switches the source output off
            %   first on every abnormal end of an acquisition (setAbortHook).
            c = obj.Cfg;
            obj.log('Connecting (%s mode)…', c.mode);
            % a session closed before connects again: its next close() must
            % release these instruments (also those of a connection that fails)
            obj.Closed = false;
            ctx = struct('mode', c.mode, 'rig', [], 'progress', @(key, state, detail) obj.progress(key, state, detail));
            try
                if strcmp(c.mode, 'simulation')
                    obj.Rig = tim.sim.SimulatedRig(c);
                    ctx.rig = obj.Rig;
                    if ~isempty(obj.Termination) && ~strcmp(char(obj.Termination.kind), 'absorber')
                        obj.Rig.Termination = tim.app.terminationModel(c, obj.Termination);   % the selected load
                    end
                end
                obj.Gen = tim.instr.create('source', c, ctx);
                obj.Daq = tim.instr.create('acquisition', c, ctx, obj.Gen);
            catch err
                obj.progressFailed(err);
                rethrow(err);
            end
            obj.setAbortHook();
            obj.logInstruments();
            obj.Connected = true;
            obj.setStatus('connected');
        end

        function tf = isCombined(obj)
            %ISCOMBINED One device takes both roles (s.Gen and s.Daq are the same object).
            tf = ~isempty(obj.Gen) && ~isempty(obj.Daq) && strcmp(class(obj.Gen), class(obj.Daq)) && obj.Gen == obj.Daq;
        end

        function ch = acquisitionChain(obj)
            %ACQUISITIONCHAIN The DAQ input chain in use (tim.cal.acquisitionChain):
            %   driver, display name, model, serial, firmware of the connected
            %   module and the input settings (sample rate, range, filter, CCLD).
            %   The switching calibration depends on it (cal.meta.acquisition).
            md = struct('driver', obj.Cfg.daq.driver);
            if ~isempty(obj.Daq), md = obj.Daq.metadata(); end
            ch = tim.cal.acquisitionChain(md, obj.Cfg.acquisition, obj.Cfg.acquisition.sampleRate);
        end

        function d = driverInfo(obj, role)
            %DRIVERINFO Class-level description of the driver of a role
            %   ('source' | 'acquisition'; tim.instr.driverInfo).
            if strcmp(role, 'source'), d = tim.instr.driverInfo(obj.Cfg.generator.driver);
            else, d = tim.instr.driverInfo(obj.Cfg.daq.driver);
            end
        end

        function prepareAcquisition(obj)
            obj.requireConnected();
            a = obj.Cfg.acquisition;
            micsCh = tim.app.MeasurementSession.micsByChannel(obj.Cfg.mics);   % element c = channel c
            % driver-specific input settings (e.g. the connector) come from the
            % driver's own settings, captured when it was created
            dc = struct('sampleRate', a.sampleRate, 'range', a.range, 'filter', a.filter, ...
                'ccld', a.ccld, 'channels', 1:4, 'detectTeds', a.detectTeds, ...
                'names', {arrayfun(@(m) sprintf('M%d', m.position), micsCh, 'UniformOutput', false)});
            try
                obj.Daq.ProgressFcn = @(key, state, detail) obj.progress(key, state, detail);
                obj.Daq.prepare(dc);
                srcName = @tim.app.MeasurementSession.sourceName;
                obj.progress('sens', 'run', ['order: ' strjoin(cellfun(srcName, strsplit(char(a.sensitivityPolicy), '>'), ...
                    'UniformOutput', false), ' → ')]);
                obj.Mics = tim.cal.resolveSensitivities(micsCh, obj.Daq.Teds, a.sensitivityPolicy);
                parts = cell(1, numel(obj.Mics)); state = 'ok';
                for i = 1:numel(obj.Mics)
                    m = obj.Mics(i);
                    obj.log('ch%d (port M%d): sensitivity %.4g mV/Pa (%s)%s', m.channel, m.position, ...
                        1e3 * m.sensitivity_VperPa, srcName(m.sensitivitySource), ...
                        tim.app.MeasurementSession.ternary(m.serialMismatch, ' – TEDS serial number differs from the configuration', ''));
                    parts{i} = sprintf('ch%d %.4g (%s)', m.channel, 1e3 * m.sensitivity_VperPa, srcName(m.sensitivitySource));
                    if m.serialMismatch || ~any(strcmp(m.sensitivitySource, {'certificate', 'teds'}))
                        state = 'warn';       % nominal value or wrong microphone
                    end
                end
                obj.progress('sens', state, ['mV/Pa: ' strjoin(parts, ',  ')]);
                settle = obj.driverInfo('acquisition').texts.settle;   % what the inputs settle from ('' = nothing)
                if strcmp(obj.Cfg.mode, 'hardware') && a.settleTime > 0 && ~isempty(settle)
                    what = sprintf(settle, a.filter);
                    obj.log('Waiting %.1f s for the inputs to settle (%s)…', a.settleTime, what);
                    obj.progress('settle', 'run', sprintf('%.1f s (%s)', a.settleTime, what));
                    pause(a.settleTime);
                    obj.progress('settle', 'ok', sprintf('%.1f s', a.settleTime));
                elseif strcmp(obj.Cfg.mode, 'hardware')
                    obj.progress('settle', 'skip', 'not needed');
                else
                    obj.progress('settle', 'skip', 'not needed (simulation)');
                end
            catch err
                obj.progressFailed(err);
                rethrow(err);
            end
            obj.Prepared = true;
            obj.setStatus('ready');
        end

        function chk = signalCheck(obj, duration)
            %SIGNALCHECK Short recording WITHOUT excitation: level and fault
            %   flags per channel (connection check). chk(c): channel, spl_dB,
            %   peak_V, state ('ok' | 'fail'), text. Never drives the loudspeaker.
            %   Faults come from the acquisition's integrity report: the device
            %   flags of each input in the driver's words (channelFaults), a
            %   constant signal, and a peak of 99 % of the input range or more
            %   (peakFractionOfRange).
            if nargin < 2, duration = 1; end
            obj.progress('signal', 'run', sprintf('%.1f s recording, no excitation', duration));
            try
                m = obj.measureBackground(duration);
            catch err
                obj.progressFailed(err);
                rethrow(err);
            end
            x = m.records{1}; g = m.channelInfo{1}.integrity;
            chk = struct('channel', {}, 'spl_dB', {}, 'peak_V', {}, 'state', {}, 'text', {});
            for c = 1:size(x, 2)
                v = x(:, c) - mean(x(:, c));
                s = obj.Mics([obj.Mics.channel] == c).sensitivity_VperPa;   % record column c = channel c
                if strcmp(m.unit, 'V')
                    spl = 20 * log10(sqrt(mean(v.^2)) / s / 2e-5); level = sprintf('%.1f dB SPL', spl);
                else
                    spl = NaN; level = sprintf('%.1f dB re FS', 20 * log10(sqrt(mean(v.^2))));   % input scale unknown
                end
                pk = max(abs(x(:, c)));
                flags = {};
                if isfield(g, 'channelFaults') && numel(g.channelFaults) >= c
                    flags = reshape(cellstr(g.channelFaults{c}), 1, []);
                end
                if std(x(:, c)) == 0, flags{end+1} = 'no signal (constant value)'; end %#ok<AGROW>
                if isfield(g, 'peakFractionOfRange') && numel(g.peakFractionOfRange) >= c && g.peakFractionOfRange(c) >= 0.99
                    flags{end+1} = 'overload (≥ 99 % of input range)'; %#ok<AGROW>
                end
                if isempty(flags)
                    st = 'ok'; txt = level;
                else
                    st = 'fail'; txt = strjoin(flags, ', ');
                end
                chk(c) = struct('channel', c, 'spl_dB', spl, 'peak_V', pk, 'state', st, 'text', txt);
            end
            parts = arrayfun(@(k) sprintf('ch%d %s', k.channel, k.text), chk, 'UniformOutput', false);
            if any(strcmp({chk.state}, 'fail')), st = 'fail'; else, st = 'ok'; end
            obj.log('Signal check (no excitation): %s', strjoin(parts, ' | '));
            obj.progress('signal', st, strjoin(parts, ',  '));
        end

        function progress(obj, key, state, detail)
            %PROGRESS Report a connection step to ProgressCallback (GUI checklist).
            %   A STOP requested meanwhile aborts the connection at the start of
            %   the next step: the session's own steps and the drivers' connect
            %   steps (a driver then releases what it opened); a driver may
            %   ignore the error during its prepare steps - the session's next
            %   own step stops.
            if nargin < 4, detail = ''; end
            if strcmp(state, 'run') && obj.StopRequested
                obj.ProgressKey = '';
                if ~isempty(obj.ProgressCallback)
                    try, obj.ProgressCallback(key, 'fail', 'stopped by the operator'); catch, end
                end
                error('tim:session:stopped', 'Connection stopped by the operator.');
            end
            if strcmp(state, 'run')
                obj.ProgressKey = key;
            elseif strcmp(key, obj.ProgressKey)
                obj.ProgressKey = '';
            end
            if ~isempty(obj.ProgressCallback)
                try, obj.ProgressCallback(key, state, detail); catch, end
            end
        end

        %% ---- measurements -------------------------------------------------
        function meas = measure(obj, mode)
            if nargin < 2, mode = obj.Cfg.excitation.mode; end
            switch mode
                case 'sweep',   meas = obj.measureSweep();
                case 'stepped', meas = obj.measureStepped();
                case 'noise',   meas = obj.measureNoise();
                otherwise, error('tim:session:mode', 'Unknown excitation signal "%s" (sweep, stepped or noise).', mode);
            end
        end

        function meas = measureBackground(obj, duration)
            %MEASUREBACKGROUND Record without excitation (noise floor, Test A).
            obj.requirePrepared();
            fs = obj.Cfg.acquisition.sampleRate;
            [data, info] = obj.Daq.acquire(round(duration * fs));
            info = obj.checkRate(info);
            meas = obj.packMeasurement('background', {data}, {info}, struct('duration', duration), {});
        end

        function meas = measureSweep(obj)
            obj.requirePrepared();
            obj.checkConnection();                 % a dropped connection re-opened before anything is sent
            sw = obj.Cfg.excitation.sweep;
            fs = obj.Cfg.acquisition.sampleRate;
            obj.Gen.configureSweep(sw);
            obj.log('Swept sine %g–%g Hz (%s), %.2f s, %.3g Vpk (%.3g Vpp), %d repetition(s).', sw.fStart, sw.fStop, ...
                tim.app.MeasurementSession.ternary(strcmpi(sw.spacing, 'log'), 'logarithmic', 'linear'), ...
                sw.duration, sw.amplitudeVpp / 2, sw.amplitudeVpp, sw.repetitions);
            nPre = round(sw.preRoll * fs);
            nSweep = round(sw.duration * fs);
            nTotal = nPre + nSweep + round((sw.postRoll + 0.2) * fs);
            records = {}; infos = {}; events = {};
            ev = struct('triggerSample', NaN, 'offSample', NaN, 'opcOk', false);
            function onBlock(n)
                obj.checkStop();
                if isnan(ev.triggerSample) && n >= nPre
                    obj.Gen.outputOn();
                    obj.Gen.triggerSweep();
                    ev.triggerSample = n;
                elseif ~isnan(ev.triggerSample) && isnan(ev.offSample) && n >= ev.triggerSample + nSweep
                    ev.opcOk = obj.Gen.waitComplete(5);   % true when the sweep has ended, never earlier
                    obj.Gen.outputOff();
                    ev.offSample = n;
                end
            end
            % an interrupt (Ctrl+C) between two repetitions: never left armed
            disarm = obj.disarmOnExit(); %#ok<NASGU>
            obj.AcquireFailed = false;
            try
                for r = 1:sw.repetitions
                    obj.checkStop();
                    ev = struct('triggerSample', NaN, 'offSample', NaN, 'opcOk', false);
                    [data, info] = obj.guardedAcquire(nTotal, @onBlock, sprintf('swept sine, repetition %d', r), records, infos, sw.amplitudeVpp);
                    if isnan(ev.offSample), obj.Gen.outputOff(); end
                    records{end+1} = data; infos{end+1} = info; events{end+1} = ev; %#ok<AGROW>
                    obj.log('Repetition %d: sweep triggered at sample %d, output off at sample %d; data integrity %s', ...
                        r, ev.triggerSample, ev.offSample, obj.okText(info.integrity));
                end
            catch err
                obj.failedOutsideAcquisition(err, 'swept sine', records, infos);
                rethrow(err);
            end
            obj.Gen.armOutput(false);
            meas = obj.packMeasurement('sweep', records, infos, sw, events);
        end

        function meas = measureStepped(obj)
            %MEASURESTEPPED Stepped sine (cfg.excitation.stepped). With the
            %   level equalizer off (excitation.stepped.equalizer.mode 'off', the
            %   default) every step plays the amplitude field, with the same
            %   instrument calls in the same order as before 1.6.0. With it on
            %   (1.6.0, WO-006; owner decisions 2026-11-04): a pre-measurement of
            %   the same steps at preLevel_dB below the amplitude field (or the
            %   plan armed by measureEqualizerPlan / setEqualizerPlan), then
            %   every step at the voltage that gives the target at the specimen
            %   front face (tim.app.equalizerPlan) - never above the amplitude
            %   field, which is the maximum of every step and of the drive check.
            %   meas.equalizer holds the plan with the pre-measurement result,
            %   meas.metadata.equalizer its summary, meas.settings.stepAmplitudeVpp
            %   the level of every step.
            % an armed plan is for THIS start only (one-shot): taken before
            % anything that can refuse or stop it, so that a refused or stopped
            % start never leaves it armed for a later one (review 2026-11-05)
            plan = obj.EqualizerPlan;
            obj.EqualizerPlan = [];
            obj.requirePrepared();
            obj.checkConnection();
            eq = tim.app.equalizerSettings(obj.Cfg.excitation.stepped);
            if strcmp(eq.mode, 'off')
                meas = obj.runStepped([], 'stepped sine');
                return
            end
            % refused before anything is configured or armed (owner decision
            % 2026-11-04): a source that cannot change its level while the
            % output is on, no calibration, no geometry
            obj.checkEqualizerReady(eq);
            st = obj.Cfg.excitation.stepped;
            if isempty(plan)
                plan = obj.premeasure(st, eq);      % (a Stop while it was processed: premeasure)
                obj.checkConnection();
            else
                obj.checkPlan(plan, st, eq);
                obj.log('Equalizer: the plan of %s used (%d steps between %.3g and %.3g Vpk; no new pre-measurement).', ...
                    plan.created, numel(plan.vpp), min(plan.vpp) / 2, max(plan.vpp) / 2);
            end
            meas = obj.runStepped(plan.vpp, 'stepped sine (equalized)');
            meas.equalizer = plan;
            meas.metadata.equalizer = tim.app.MeasurementSession.equalizerSummary(plan);
        end

        function plan = measureEqualizerPlan(obj)
            %MEASUREEQUALIZERPLAN The pre-measurement of the stepped-sine level
            %   equalizer on its own (1.6.0, WO-006): the steps at preLevel_dB
            %   below the amplitude field, the voltage of every step from its
            %   levels (tim.app.equalizerPlan), ARMED for the next stepped
            %   measurement of this session (EqualizerPlan, consumed by it). The
            %   two-load sequence runs it after every change of termination
            %   (owner decision 2026-11-04). Refused (tim:session:equalizer)
            %   while the equalizer is off and, before anything is played, when
            %   the signal source cannot change its level while the output is on
            %   or the calibration or the geometry is missing. The output is off
            %   and disarmed when it returns; a plan armed before is disarmed
            %   first, and a refusal, an error or a Stop (also while the
            %   pre-measurement is processed) arms none.
            obj.EqualizerPlan = [];
            obj.requirePrepared();
            obj.checkConnection();
            st = obj.Cfg.excitation.stepped;
            eq = tim.app.equalizerSettings(st);
            if strcmp(eq.mode, 'off')
                error('tim:session:equalizer', ['The stepped-sine equalizer is off ' ...
                    '(excitation.stepped.equalizer.mode): no pre-measurement.']);
            end
            obj.checkEqualizerReady(eq);
            plan = obj.premeasure(st, eq);
            obj.EqualizerPlan = plan;
        end

        function setEqualizerPlan(obj, plan)
            %SETEQUALIZERPLAN Arm a plan made before for the next stepped
            %   measurement, without a new pre-measurement: load A again with
            %   the voltages of load A (tim.app.runTwoLoad; owner decision
            %   2026-11-04: the repeat then compares only the mounting). The plan
            %   must fit the session now - the equalizer settings, the steps,
            %   the amplitude field (its maximum), the termination, the amplifier,
            %   the generator load and the calibration it was measured with -
            %   otherwise tim:session:equalizer. setEqualizerPlan([]) disarms the
            %   plan (sends nothing).
            if isempty(plan), obj.EqualizerPlan = []; return; end
            st = obj.Cfg.excitation.stepped;
            obj.checkPlan(plan, st, tim.app.equalizerSettings(st));
            obj.EqualizerPlan = plan;
        end

        function meas = measureNoise(obj)
            obj.requirePrepared();
            obj.checkConnection();
            nz = obj.Cfg.excitation.noise;
            fs = obj.Cfg.acquisition.sampleRate;
            obj.Gen.configureNoise(nz.amplitudeVpp);
            nPre = round(nz.preRoll * fs); nOn = round(nz.duration * fs);
            nTotal = nPre + nOn + round(0.3 * fs);
            ev = struct('onSample', NaN, 'offSample', NaN);
            function onBlock(n)
                obj.checkStop();
                if isnan(ev.onSample) && n >= nPre
                    obj.Gen.outputOn(); ev.onSample = n;
                elseif ~isnan(ev.onSample) && isnan(ev.offSample) && n >= ev.onSample + nOn
                    obj.Gen.outputOff(); ev.offSample = n;
                end
            end
            [data, info] = obj.guardedAcquire(nTotal, @onBlock, 'random noise', {}, {}, nz.amplitudeVpp);
            obj.Gen.outputOff();
            obj.Gen.armOutput(false);
            meas = obj.packMeasurement('noise', {data}, {info}, nz, {ev});
        end

        function setAmplifier(obj, gainSetting, gain_dB, model)
            %SETAMPLIFIER Record the (manually set) amplifier gain.
            %   s.setAmplifier('-20 dB', -20)  or  s.setAmplifier('knob 3/10', NaN, 'XYZ amp')
            %   A change requires a new operator confirmation before excitation.
            %   (compatibility form; preferred: setAmplifierGain(model, factor))
            if nargin < 3 || isempty(gain_dB), gain_dB = NaN; end
            if nargin < 4, model = obj.Cfg.amplifier.model; end
            obj.setAmplifierGain(model, 10^(gain_dB / 20), gainSetting);
        end

        function setAmplifierGain(obj, model, gainFactor, note)
            %SETAMPLIFIERGAIN Record amplifier model and voltage gain as a multiplier.
            %   s.setAmplifierGain('none (direct drive)', 1)
            %   s.setAmplifierGain('XYZ power amp', 10)          % x10 = 20 dB
            %   s.setAmplifierGain('XYZ power amp', NaN, 'knob 3')   % gain unknown
            %   A change requires a new operator confirmation before excitation.
            if nargin < 3 || isempty(gainFactor), gainFactor = NaN; end
            if nargin < 4, note = ''; end
            model = char(model);
            if startsWith(lower(model), 'none'), gainFactor = 1; end   % direct drive
            if ~(isnan(gainFactor) || gainFactor > 0)
                error('tim:session:gain', 'Amplifier gain must be greater than 0.');
            end
            a = obj.Cfg.amplifier;
            a.model = model; a.gainFactor = gainFactor; a.gain_dB = 20 * log10(gainFactor);
            a.gainSetting = char(note);
            if ~isfield(a, 'knownModels') || isempty(a.knownModels), a.knownModels = {'none (direct drive)'}; end
            if ~isempty(model) && ~any(strcmp(a.knownModels, model)), a.knownModels{end+1} = model; end
            % validated like every other setter: e.g. direct drive with generator
            % load '50' is refused here, not only at the next setExcitation
            % (review analysis-5)
            c = obj.Cfg; c.amplifier = a;
            tim.app.validateConfig(c, 'instruments');
            obj.Cfg = c;
            obj.ConfirmedExcitation = '';
            obj.discardEqualizerPlan('the amplifier was set');   % another gain: another transfer
            if isfinite(gainFactor)
                gainTxt = sprintf('gain ×%.3g (%.1f dB)', gainFactor, a.gain_dB);
            else
                gainTxt = 'gain not entered';
            end
            if startsWith(lower(model), 'none')
                obj.log('Amplifier: none (direct drive from the generator).');
            else
                obj.log('Amplifier: %s, %s%s.', ...
                    tim.app.MeasurementSession.ternary(isempty(model), 'model not specified', model), ...
                    gainTxt, tim.app.MeasurementSession.ternary(isempty(a.gainSetting), '', [' (setting "' a.gainSetting '")']));
            end
        end

        function d = driveEstimate(obj, amplitudeVpp, kind)
            %DRIVEESTIMATE Expected loudspeaker drive (see tim.app.driveEstimate);
            %   kind 'sweep' (default) | 'stepped' | 'noise'.
            if nargin < 3, kind = 'sweep'; end
            d = tim.app.driveEstimate(obj.Cfg, amplitudeVpp, kind);
        end

        function setLoudspeaker(obj, impedance_ohm, maxPower_W)
            %SETLOUDSPEAKER Loudspeaker data used for the drive estimate / power limit.
            c = obj.Cfg;
            c.loudspeaker.impedance_ohm = impedance_ohm;
            c.loudspeaker.maxPower_W = maxPower_W;
            tim.app.validateConfig(c, 'instruments');
            obj.Cfg = c;
        end

        function setGeometryEnvironment(obj, geometry, environment)
            %SETGEOMETRYENVIRONMENT Update tube geometry / air conditions (metadata).
            c = obj.Cfg; c.geometry = geometry; c.environment = environment;
            tim.app.validateConfig(c, 'instruments');
            if ~isequaln(c.geometry, obj.Cfg.geometry)
                obj.discardEqualizerPlan('the geometry changed');   % the levels at the front face move with it
            end
            obj.Cfg = c;
        end

        function line = amplifierLine(obj, amplitudeVpp, kind)
            %AMPLIFIERLINE Operator-readable description of the drive chain:
            %   the loudspeaker voltage (Vpk, Vrms) and power at the nominal
            %   impedance with its share of the test limit (WO-004).
            if nargin < 3, kind = 'sweep'; end
            a = obj.Cfg.amplifier; lang = obj.lang();
            d = obj.driveEstimate(amplitudeVpp, kind);
            note = '';
            if ~isempty(a.gainSetting) && ~strcmp(a.gainSetting, '-'), note = sprintf(' (setting "%s")', a.gainSetting); end
            mdl = a.model; if isempty(mdl), mdl = '(model not specified)'; end
            near = '';
            if strcmp(d.state, 'near'), near = tim.app.msg(lang, 'nearLimit'); end
            if d.direct
                line = tim.app.msg(lang, 'ampDirect', d.Rs, d.Z, d.Vspk_pk, d.Vspk_rms, 1e3 * d.Ipk, 1e3 * d.P_W, ...
                    100 * d.fraction, 1e3 * d.limit_W, near);
            elseif isfinite(d.gain)
                line = tim.app.msg(lang, 'ampGain', mdl, d.gain, 20 * log10(d.gain), d.Z, d.Vspk_pk, d.Vspk_rms, ...
                    1e3 * d.P_W, 100 * d.fraction, 1e3 * d.limit_W, near, note);
            else
                line = tim.app.msg(lang, 'ampUnknownGain', mdl, note);
            end
        end

        function l = lang(obj)
            %LANG Language of operator prompts ('en' default).
            l = 'en';
            if isfield(obj.Cfg, 'ui') && isfield(obj.Cfg.ui, 'language'), l = obj.Cfg.ui.language; end
        end

        function setExcitation(obj, ex)
            %SETEXCITATION Change excitation settings between measurements (validated).
            %   A change of the stepped sine discards an armed equalizer plan.
            c = obj.Cfg; c.excitation = ex;
            tim.app.validateConfig(c, 'instruments');
            if ~isequaln(c.excitation.stepped, obj.Cfg.excitation.stepped)
                obj.discardEqualizerPlan('the stepped-sine settings changed');
            end
            obj.Cfg = c;
        end

        function setAmplitudeAt(obj, at)
            %SETAMPLITUDEAT What the window's amplitude field gave: 'generator' or
            %   'loudspeaker' (direct drive), stored with every measurement
            %   (configuration ui.amplitudeAt). The excitation amplitudes are
            %   the generator's in either case (metadata.drive has both levels).
            c = obj.Cfg; c.ui.amplitudeAt = at;
            tim.app.validateConfig(c, 'instruments');
            obj.Cfg = c;
        end

        %% ---- calibration ----------------------------------------------------
        function loadCalibration(obj, file)
            S = load(file, 'cal');
            if ~isfield(S, 'cal') || ~strcmp(S.cal.type, 'tim.complexChannelCalibration')
                error('tim:cal:file', '"%s" is not a calibration file of this program (switching calibration).', file);
            end
            obj.Calibration = S.cal;
            obj.CalibrationFile = char(file);
            obj.log('Loaded calibration %s (%s).', S.cal.version, file);
        end

        function setMicPositionsForSimulation(obj, mapping)
            %Simulation only: emulate physically moving microphones.
            if isempty(obj.Rig), error('tim:session:sim', 'Only available in simulation mode.'); end
            obj.Rig.MicPosOfChannel = mapping;
        end

        function prev = setSimulationSample(obj, sample)
            %SETSIMULATIONSAMPLE Simulation only: exchange the specimen of the virtual
            %   rig, e.g. struct('type','air') = empty specimen section (air column of
            %   length xRear - xFront, tim.sim.tubeModel). Returns the previous sample.
            if isempty(obj.Rig), error('tim:session:sim', 'Only available in simulation mode.'); end
            prev = obj.Rig.Sample;
            obj.Rig.Sample = sample;          % setter marks the FIR for re-design
            obj.discardEqualizerPlan('another virtual specimen was mounted');
            if strcmp(sample.type, 'air')
                obj.log('Simulation: empty specimen section mounted in the virtual tube.');
            else
                obj.log('Simulation: virtual specimen "%s" mounted.', sample.type);
            end
        end

        function prev = setTermination(obj, load)
            %SETTERMINATION The termination load mounted now (WO-005): recorded
            %   with every following measurement (metadata.termination). In
            %   simulation the virtual rig gets that termination
            %   (tim.app.terminationModel). Returns the previous load. Another
            %   termination discards an armed equalizer plan (1.6.0: the
            %   transfer to the specimen depends on it).
            d = tim.app.describeLoad(load, obj.Cfg);      % checks kind and place
            prev = obj.Termination;
            obj.Termination = struct('kind', d.kind, 'place', d.place);
            if ~isequal(prev, obj.Termination)
                obj.discardEqualizerPlan('the termination changed');
            end
            if ~isempty(obj.Rig)
                t = tim.app.terminationModel(obj.Cfg, obj.Termination);
                if ~isequal(obj.Rig.Termination, t)
                    obj.Rig.Termination = t;          % setter marks the FIR for re-design
                    obj.log('Simulation: termination "%s" mounted in the virtual tube.', d.label);
                end
            end
        end

        %% ---- shutdown -------------------------------------------------------
        function requestStop(obj)
            obj.StopRequested = true;
        end

        function beginOperation(obj)
            %BEGINOPERATION Start an operation (GUI action, calibration): the
            %   OUTERMOST call clears the stop flag once; a later STOP stays
            %   pending until the matching endOperation, even between
            %   measurements. Nestable (the GUI wraps every action, the
            %   calibration nests inside), so a STOP / window close that arrives
            %   between the START click and the first measurement is not lost.
            if obj.OperationDepth == 0
                obj.StopRequested = false;
            end
            obj.OperationDepth = obj.OperationDepth + 1;
            obj.InOperation = true;
        end

        function endOperation(obj)
            obj.OperationDepth = max(0, obj.OperationDepth - 1);
            obj.InOperation = obj.OperationDepth > 0;
        end

        function throwIfStopped(obj)
            %THROWIFSTOPPED Public check used between operator steps.
            obj.checkStop();
        end

        function r = checkConnection(obj)
            %CHECKCONNECTION The instruments' connections still work (the
            %   drivers' checkConnection): before every excitation (measure*)
            %   and from the window every 60 s while it is idle (hardware). An
            %   instrument that dropped its connection unnoticed - the lab generator
            %   does now and then (hardware check 2026-10-12) - is re-opened
            %   by its driver and the session logs it; one that cannot be
            %   re-opened stops here with tim:instr:connectionLost, before
            %   anything is configured or armed. r: struct array role,
            %   state ('ok' | 'reconnected'), detail.
            obj.requireConnected();
            obj.LostRole = '';
            devs = {obj.Gen, 'source'};
            if ~obj.isCombined(), devs(end+1, :) = {obj.Daq, 'acquisition'}; end
            r = struct('role', {}, 'state', {}, 'detail', {});
            for i = 1:size(devs, 1)
                if isempty(devs{i, 1}), continue; end
                try
                    c = devs{i, 1}.checkConnection();
                catch err
                    obj.LostRole = devs{i, 2};
                    rethrow(err);
                end
                if strcmp(c.state, 'reconnected')
                    noun = devs{i, 2};
                    try, noun = obj.driverInfo(devs{i, 2}).texts.noun; catch, end
                    obj.log('%s: %s.', [upper(noun(1)) noun(2:end)], c.detail);
                end
                r(end+1) = struct('role', devs{i, 2}, 'state', c.state, 'detail', c.detail); %#ok<AGROW>
            end
        end

        function close(obj, fast)
            %CLOSE Instruments to their safe state and released: the source
            %   first (output off), then the acquisition (stopped, idle); the
            %   drivers' close() never throws. close(true) first shortens the
            %   I/O time-outs to 2 s, so that closing the app never waits long
            %   for an instrument that does not answer (switched off). Called
            %   during an acquisition (closing the window), the acquisition
            %   ends with tim:instr:closed; the data received stay available.
            if nargin < 2, fast = false; end
            if obj.Closed, return; end         % e.g. the destructor of an already closed session
            obj.Closed = true;
            devices = {obj.Gen};
            if ~obj.isCombined(), devices{end+1} = obj.Daq; end
            devices = devices(~cellfun(@isempty, devices));
            if fast
                for i = 1:numel(devices)
                    try, devices{i}.setTimeout(2); catch, end
                end
            end
            for i = 1:numel(devices)
                try, devices{i}.close(); catch, end
            end
            % the abort hook is released with the instruments (for a combined
            % device it refers to the object itself); connect sets it again
            if ~isempty(obj.Daq)
                try, obj.Daq.AbortFcn = []; catch, end
            end
            obj.Connected = false; obj.Prepared = false;
            obj.setStatus('disconnected');
        end

        function delete(obj)
            try, obj.close(); catch, end
        end

        function log(obj, varargin)
            msg = sprintf(varargin{:});
            line = sprintf('[%s] %s', char(datetime('now'), 'HH:mm:ss'), msg);
            obj.LogLines{end+1} = line;
            fprintf('%s\n', line);
            if ~isempty(obj.StatusCallback)
                try, obj.StatusCallback(line); catch, end
            end
        end
    end

    methods (Access = private)
        function setAbortHook(obj)
            % D24 (approved by the owner 2026-10-11; docs/instrument_interface.md
            % section 8.1 rule 4): on every abnormal end of an acquisition - its
            % own error (stalled stream, time-out, transport fault), an error
            % thrown by onBlock (a Stop), an interrupt - the acquisition driver
            % calls AbortFcn BEFORE any stop or drain I/O, so the source output
            % goes off before the driver stops its device (stopping an
            % unreachable network module can take about 20 s). Set once here,
            % so direct callers of acquire (tim.val.channelIdentification) are
            % covered too. A combined device (Gen == Daq) gets the same hook: its
            % re-entrant outputOff stops its output at once (section 8.3), then
            % its own stop sequence runs (stopped, then 0 V).
            gen = obj.Gen;
            obj.Daq.AbortFcn = @() gen.outputOff();
        end

        function logInstruments(obj)
            % one log line per instrument: role, display name and the identity it reported
            line = @(o) sprintf('%s – %s', o.metadata().displayName, o.identity().raw);
            if obj.isCombined()
                obj.log('Signal source and acquisition: %s (output off)', line(obj.Gen));
            else
                obj.log('Signal source: %s (output off)', line(obj.Gen));
                obj.log('Acquisition: %s', line(obj.Daq));
            end
        end

        function progressFailed(obj, err)
            % the running checklist step failed
            if ~isempty(obj.ProgressKey)
                obj.progress(obj.ProgressKey, 'fail', err.message);
            end
        end

        function [data, info] = guardedAcquire(obj, nTotal, onBlock, what, prevRecords, prevInfos, amplitudeVpp)
            obj.confirmExcitation(amplitudeVpp, what);
            obj.Gen.armOutput(true);       % explicit user start of this measurement
            % interrupt (Ctrl+C) inside the acquisition: try/catch does not run,
            % the guard's destructor switches the output off and disarms it
            guard = tim.app.outputGuard(obj.Gen);
            obj.setStatus(['measuring: ' what]);
            try
                [data, info] = obj.Daq.acquire(nTotal, onBlock);
            catch err
                obj.AcquireFailed = true;  % handled here, not again by failedOutsideAcquisition
                % the driver switched the output off through AbortFcn BEFORE its
                % stop sequence (setAbortHook, D24); disarming switches it off
                % once more - also when the error came before the driver could
                % call the hook
                obj.Gen.armOutput(false);
                guard.dismiss();           % switched off here: no second output-off command
                partial = struct('records', {prevRecords}, 'infos', {prevInfos}, 'error', err.message);
                try
                    [pd, pinfo] = obj.Daq.collect();
                    partial.records{end+1} = pd; partial.infos{end+1} = pinfo;
                catch
                end
                try
                    b = obj.Daq.rawBytes();             % undecoded bytes, if the driver keeps them
                    if ~isempty(b), partial.rawStream = b; end
                catch
                end
                obj.LastPartial = partial;
                f = tim.app.saveEmergency(obj, partial);
                obj.setStatus('error');
                % commanded, not read back (outputOff never throws; a failure is
                % only a warning): never claim the output is off here
                obj.log('Error during %s: %s. Generator output commanded off (not read back). Partial data saved to %s.', ...
                    what, regexprep(err.message, '\.$', ''), f);
                rethrow(err);
            end
            guard.dismiss();               % normal end: the schedule switched the output off
            info = obj.checkRate(info);
            obj.setStatus('ready');
        end

        function failedOutsideAcquisition(obj, err, what, records, infos)
            % an error of measureSweep / measureStepped outside guardedAcquire's
            % acquisition: a Stop or an instrument error between two repetitions
            % (checkStop, setFrequency) or a refused confirmation. The generator
            % is disarmed (armOutput(false) also switches the output off) and the
            % completed repetitions are kept in LastPartial and an emergency file,
            % as for an error inside the acquisition. Nothing to do when
            % guardedAcquire handled the error itself; before the first
            % repetition nothing was armed or recorded, so nothing is sent.
            if obj.AcquireFailed, return; end
            if obj.Gen.OutputArmed, obj.Gen.armOutput(false); end
            if isempty(records), return; end
            partial = struct('records', {records}, 'infos', {infos}, 'error', err.message);
            obj.LastPartial = partial;
            f = tim.app.saveEmergency(obj, partial);
            obj.setStatus('error');
            obj.log(['Error during %s after %d completed repetition(s): %s. Generator output commanded off (not read back). ' ...
                'The completed repetitions were saved to %s.'], what, numel(records), regexprep(err.message, '\.$', ''), f);
        end

        function c = disarmOnExit(obj)
            % onCleanup of measureSweep / measureStepped: an exit that skips the
            % normal end and the error paths (an interrupt between two
            % repetitions, where no output guard exists) leaves the generator
            % disarmed and its output off. Sends nothing when it is not armed.
            gen = obj.Gen;
            c = onCleanup(@() tim.app.MeasurementSession.disarmSource(gen));
        end

        function meas = runStepped(obj, vpp, what)
            % One stepped-sine measurement of measure*(): the steps of
            % tim.app.steppedPlan, scheduled on the received samples.
            % vpp [] (the equalizer off): every step at the amplitude field,
            % with the instrument calls and their order of the stepped sine
            % before 1.6.0 (bus-traffic fixtures unchanged).
            % vpp (1 x n): the level of every step (the equalizer, 1.6.0; owner
            % decisions 2026-11-04): checked against the amplitude field before
            % anything is configured - no step above it; the operator
            % confirmation and the loudspeaker power check use the amplitude
            % field, the maximum (metadata.drive is that of the maximum). A level
            % change goes with the frequency change of its step (setAmplitude,
            % output on): a lower level before the new frequency, a higher one
            % after it, so that no frequency plays at more than its own level
            % or that of the step before. A planned (combined) device schedules
            % it in its planning pass like setFrequency. Its errors take the
            % error path of the acquisition (output off first, partial data).
            st = obj.Cfg.excitation.stepped;
            fs = obj.Cfg.acquisition.sampleRate;
            % frequencies and the settling / recording samples of every step
            % (longer at low frequencies when cycles are set: tim.app.steppedPlan)
            plan = tim.app.steppedPlan(st, fs);
            freqs = plan.freqs;
            perStep = ~isempty(vpp);
            level = st.amplitudeVpp;
            if perStep
                vpp = reshape(double(vpp), 1, []);
                if ~(numel(vpp) == numel(freqs) && all(isfinite(vpp) & vpp > 0 & vpp <= st.amplitudeVpp * (1 + 1e-9)))
                    error('tim:session:equalizer', ['Equalizer: %d step level(s) for %d steps, between %.4g and %.4g ' ...
                        'Vpp; every level must be positive and at most the amplitude, %.4g Vpp. Nothing was played.'], ...
                        numel(vpp), numel(freqs), min(vpp), max(vpp), st.amplitudeVpp);
                end
                level = vpp(1);
            end
            obj.Gen.configureSine(freqs(1), level);
            nSettle = plan.settleSamples; nRec = plan.recordSamples;
            nPre = plan.preSamples;
            stepEnd = cumsum(nSettle + nRec);       % end of step k after the output went on
            % Steps are scheduled at FIXED targets onSample + stepEnd(k), so the
            % block granularity of the received data (overshoot <= 1 block) does
            % not accumulate over the steps (bug found on the bench test).
            nTotal = nPre + stepEnd(end) + plan.postSamples;
            ev = struct('stepStart', nan(1, numel(freqs)), 'freqs', freqs, 'onSample', NaN);
            k = 0;
            function onBlock(n)
                obj.checkStop();
                if isnan(ev.onSample) && n >= nPre
                    obj.Gen.outputOn(); ev.onSample = n; k = 1; ev.stepStart(1) = n;
                elseif k >= 1 && k < numel(freqs) && n >= ev.onSample + stepEnd(k)
                    k = k + 1;
                    if perStep && vpp(k) < vpp(k - 1), obj.Gen.setAmplitude(vpp(k)); end
                    obj.Gen.setFrequency(freqs(k));
                    if perStep && vpp(k) > vpp(k - 1), obj.Gen.setAmplitude(vpp(k)); end
                    ev.stepStart(k) = n;
                elseif k == numel(freqs) && n >= ev.onSample + stepEnd(k)
                    obj.Gen.outputOff(); k = k + 1;
                end
            end
            records = {}; infos = {}; evs = {};
            % an interrupt (Ctrl+C) between two repetitions: never left armed
            disarm = obj.disarmOnExit(); %#ok<NASGU>
            obj.AcquireFailed = false;
            try
                for r = 1:st.repetitions
                    ev.stepStart(:) = NaN; ev.onSample = NaN; k = 0;
                    if r > 1
                        if perStep && vpp(1) < vpp(end), obj.Gen.setAmplitude(vpp(1)); end
                        obj.Gen.setFrequency(freqs(1));
                        if perStep && vpp(1) > vpp(end), obj.Gen.setAmplitude(vpp(1)); end
                    end
                    [data, info] = obj.guardedAcquire(nTotal, @onBlock, what, records, infos, st.amplitudeVpp);
                    obj.Gen.outputOff();
                    records{end+1} = data; infos{end+1} = info; %#ok<AGROW>
                    evs{r} = ev; %#ok<AGROW>
                end
            catch err
                obj.failedOutsideAcquisition(err, what, records, infos);
                rethrow(err);
            end
            obj.Gen.armOutput(false);
            st.frequencies = freqs; st.settleSamples = nSettle; st.recordSamples = nRec;   % per step
            if perStep, st.stepAmplitudeVpp = vpp; end    % the level of every step (res.levels.generatorVpp)
            meas = obj.packMeasurement('stepped', records, infos, st, evs);
        end

        function plan = premeasure(obj, st, eq)
            % The equalizer's pre-measurement (owner decisions 2026-11-04): the
            % steps of the stepped sine at preLevel_dB below the amplitude field
            % (at least the smallest level of the source), processed with the
            % session's calibration; the voltage of every step from its levels
            % (tim.app.equalizerPlan). The output is off and disarmed when it
            % returns; a pre-measurement without a level at the specimen or with
            % data integrity problems stops here (tim:session:equalizer), and so
            % does a Stop while it is processed (tim:session:stopped) - each
            % keeping the recorded pre-measurement (LastPartial, an emergency
            % file), as every other error path keeps its data.
            freqs = tim.app.steppedPlan(st).freqs;
            [vPre, vMin, raised] = obj.equalizerPreLevel(st, eq);
            unit = 'dB SPL'; if strcmp(eq.mode, 'faceVelocity'), unit = 'mm/s'; end
            note = '';
            if raised, note = ', raised to the smallest level of the signal source'; end
            obj.log(['Equalizer (%s, target %g %s ± %g dB): pre-measurement of the %d steps at %+g dB of the ' ...
                'maximum (%.3g Vpk%s).'], eq.mode, eq.target, unit, eq.tolerance_dB, numel(freqs), eq.preLevel_dB, ...
                vPre / 2, note);
            pre = obj.runStepped(repmat(vPre, 1, numel(freqs)), 'stepped sine (equalizer pre-measurement)');
            try
                if ~pre.integrityOk
                    error('tim:session:equalizer', ['Equalizer: the pre-measurement has data integrity problems (see ' ...
                        'the log) - the steps were not played. Repeat it.']);
                end
                res = tim.app.processMeasurement(pre, obj.Cfg, obj.Calibration);
                if ~res.levels.available
                    error('tim:session:equalizer', ['Equalizer: the pre-measurement gives no level at the specimen ' ...
                        '(%s) - the steps were not played.'], regexprep(res.levels.note, '\.$', ''));
                end
                plan = tim.app.equalizerPlan(eq, freqs, res.levels, vPre, st.amplitudeVpp, vMin);
                plan.pre.timestamp = pre.timestamp;
                plan.pre.integrityOk = pre.integrityOk;
                plan.pre.calibration = res.calibration.version;
                plan.termination = obj.Termination;
                plan.chain = obj.equalizerChain();
                obj.checkStop();                    % a Stop while the pre-measurement was processed: no plan
            catch err
                obj.keepPreMeasurement(pre, err);
                rethrow(err);
            end
            obj.logPlan(plan);
        end

        function keepPreMeasurement(obj, pre, err)
            % the recorded pre-measurement of the equalizer when it is refused or
            % stopped after its acquisition (review 2026-11-05): kept in
            % LastPartial and an emergency file like the data of every other error
            % path, with its settings and events, so that it can be processed
            % again. runStepped ended normally: the output is off and disarmed
            % (disarmed once more here, which sends nothing then).
            tim.app.MeasurementSession.disarmSource(obj.Gen);
            partial = struct('records', {pre.records}, 'infos', {pre.channelInfo}, 'error', err.message, ...
                'what', 'stepped sine (equalizer pre-measurement)', 'settings', pre.settings, 'events', {pre.events});
            obj.LastPartial = partial;
            f = tim.app.saveEmergency(obj, partial);
            obj.setStatus('error');
            obj.log('Error after the equalizer pre-measurement: %s. Its %d repetition(s) were saved to %s.', ...
                regexprep(err.message, '\.$', ''), numel(pre.records), f);
        end

        function [vPre, vMin, raised] = equalizerPreLevel(obj, st, eq)
            % level of the pre-measurement [Vpp]: preLevel_dB below the amplitude
            % field on the 0.1 mVpp grid of tim.app.equalizerPlan, at least the
            % smallest level of the source at its load, at most the amplitude
            src = obj.driverInfo('source').capabilities.source;
            vMin = tim.instr.SignalSource.levelRange(src, obj.Cfg.generator.load);
            if ~(isscalar(vMin) && isfinite(vMin) && vMin >= 0), vMin = 0; end
            dv = 1e-4;
            v = round(st.amplitudeVpp * 10^(eq.preLevel_dB / 20) / dv) * dv;
            vLo = ceil(vMin / dv - 1e-9) * dv;
            raised = v < vLo;
            vPre = min(st.amplitudeVpp, max(v, vLo));
        end

        function checkEqualizerReady(obj, eq)
            % owner decision 2026-11-04: the equalizer is refused before anything
            % is configured or armed when the signal source cannot change its
            % level while the output is on (capabilities().source.levelWhileOn);
            % the levels at the specimen need the calibrated decomposition and
            % the positions of the microphones and of the front face
            d = obj.driverInfo('source');
            if ~tim.instr.SignalSource.levelWhileOn(d.capabilities.source)
                error('tim:session:equalizer', ['The stepped-sine equalizer (%s) needs a signal source that can change ' ...
                    'its level while the output is on; the %s cannot (capabilities().source.levelWhileOn). Switch the ' ...
                    'equalizer off (excitation.stepped.equalizer.mode ''off''). Nothing was played.'], eq.mode, d.displayName);
            end
            if isempty(obj.Calibration)
                error('tim:session:equalizer', ['The stepped-sine equalizer needs a switching calibration: the level at ' ...
                    'the specimen comes from the calibrated decomposition. Load or run a calibration first. Nothing was ' ...
                    'played.']);
            end
            g = obj.Cfg.geometry;
            if ~(all(isfinite(g.micPositions)) && isfinite(g.xFront))
                error('tim:session:equalizer', ['The stepped-sine equalizer needs the microphone positions and the ' ...
                    'position of the specimen front face (geometry). Nothing was played.']);
            end
        end

        function checkPlan(obj, plan, st, eq)
            % a plan made before must fit the session now (setEqualizerPlan, an
            % armed plan): otherwise tim:session:equalizer, nothing is played
            need = {'mode', 'target', 'tolerance_dB', 'freqs', 'vpp', 'limited', 'maxVpp', 'termination', 'chain'};
            if ~(isstruct(plan) && isscalar(plan) && all(isfield(plan, need)))
                error('tim:session:equalizer', ['Not an equalizer plan of this session (measureEqualizerPlan, ' ...
                    'tim.app.equalizerPlan).']);
            end
            freqs = tim.app.steppedPlan(st).freqs;
            why = '';
            if ~(strcmp(plan.mode, eq.mode) && isequal(plan.target, eq.target) && isequal(plan.tolerance_dB, eq.tolerance_dB))
                why = 'the equalizer settings changed';
            elseif numel(plan.freqs) ~= numel(freqs) || any(abs(plan.freqs(:).' - freqs) > 1e-9 * freqs)
                why = 'the steps changed';
            elseif abs(plan.maxVpp - st.amplitudeVpp) > 1e-9 * st.amplitudeVpp || numel(plan.vpp) ~= numel(freqs) || ...
                    any(~(plan.vpp > 0 & plan.vpp <= st.amplitudeVpp * (1 + 1e-9)))
                why = sprintf('the amplitude changed (plan: maximum %.4g Vpp, now %.4g Vpp)', plan.maxVpp, st.amplitudeVpp);
            elseif ~isequal(plan.termination, obj.Termination)
                why = 'another termination is mounted';
            elseif ~isequaln(plan.chain, obj.equalizerChain())
                why = 'the amplifier or the generator load changed';
            elseif isfield(plan, 'pre') && isstruct(plan.pre) && isscalar(plan.pre) && ...
                    isfield(plan.pre, 'calibration') && ~strcmp(char(string(plan.pre.calibration)), obj.calibrationVersion())
                % the levels of the plan came from the calibrated decomposition
                % (review 2026-11-05: loadCalibration does not discard a plan)
                why = sprintf('the calibration changed (plan: %s, now: %s)', char(string(plan.pre.calibration)), ...
                    obj.calibrationVersion());
            end
            if ~isempty(why)
                error('tim:session:equalizer', ['Equalizer plan not used: %s since its pre-measurement. A stepped ' ...
                    'measurement without an armed plan measures a new one. Nothing was played.'], why);
            end
        end

        function v = calibrationVersion(obj)
            % version of the session's calibration as processMeasurement records
            % it (res.calibration.version): 'none' without one
            v = 'none';
            if ~isempty(obj.Calibration) && isstruct(obj.Calibration) && isfield(obj.Calibration, 'version')
                v = char(string(obj.Calibration.version));
            end
        end

        function c = equalizerChain(obj)
            % the drive chain a plan belongs to: generator load and amplifier
            a = obj.Cfg.amplifier;
            c = struct('load', char(obj.Cfg.generator.load), 'model', char(a.model), 'gainFactor', a.gainFactor, ...
                'gainSetting', char(a.gainSetting));
        end

        function discardEqualizerPlan(obj, why)
            % an armed plan that no longer fits is dropped (logged)
            if isempty(obj.EqualizerPlan), return; end
            obj.EqualizerPlan = [];
            obj.log('Equalizer plan discarded: %s.', why);
        end

        function logPlan(obj, plan)
            % one log line: the levels of the plan and the steps it cannot equalize
            parts = '';
            lim = plan.limited;
            hz = @(m) strjoin(arrayfun(@(f) sprintf('%.0f', f), plan.freqs(m), 'UniformOutput', false), ', ');
            m = strcmp(lim, 'max');
            if any(m)
                parts = sprintf('%s; %d at the maximum, the target not reachable there (%s Hz)', parts, nnz(m), hz(m));
            end
            m = strcmp(lim, 'min');
            if any(m)
                parts = sprintf('%s; %d at the smallest level of the source, above the target (%s Hz)', parts, nnz(m), hz(m));
            end
            m = strcmp(lim, 'unknown');
            if any(m)
                parts = sprintf('%s; %d without a level from the pre-measurement, played at its level (%s Hz)', ...
                    parts, nnz(m), hz(m));
            end
            obj.log('Equalizer plan: %d steps between %.3g and %.3g Vpk (maximum %.3g Vpk)%s.', numel(plan.vpp), ...
                min(plan.vpp) / 2, max(plan.vpp) / 2, plan.maxVpp / 2, parts);
        end

        function info = checkRate(obj, info)
            % data at another rate than the configured one would shift the
            % frequency axis: a fatal integrity problem for every driver
            fs = obj.Cfg.acquisition.sampleRate;
            if ~isfield(info, 'fs') || ~isfield(info, 'integrity') || all(abs(info.fs - fs) <= 1e-9 * fs), return; end
            if ~any(contains(lower(info.integrity.fatal), 'sample rate'))     % not reported by the driver already
                info.integrity.fatal{end+1} = sprintf('Sample rate of the data %s S/s differs from the configured %g S/s.', ...
                    mat2str(info.fs), fs);
            end
            info.integrity.ok = false;
        end

        function meas = packMeasurement(obj, kind, records, infos, settings, events)
            meas = struct();
            meas.kind = kind;
            meas.records = records;          % RAW data (volts), never modified
            meas.fs = obj.Cfg.acquisition.sampleRate;
            meas.unit = 'V';                 % 'V', or 'FS' from a driver with an unknown input scale
            if ~isempty(infos) && isfield(infos{1}, 'dataUnit'), meas.unit = infos{1}.dataUnit; end
            meas.channelInfo = infos;
            meas.settings = settings;
            meas.events = events;
            meas.mics = obj.Mics;
            meas.timestamp = char(datetime('now'), 'yyyy-MM-dd HH:mm:ss.SSS');
            meas.metadata = tim.app.collectMetadata(obj);
            if isfield(settings, 'amplitudeVpp')
                % the drive of this excitation: the programmed generator level
                % (settings.amplitudeVpp) and the estimated loudspeaker voltage,
                % current and power (WO-003: both values recorded; WO-004: the
                % power of noise with its crest factor, the share of the limit)
                meas.metadata.drive = tim.app.driveEstimate(obj.Cfg, settings.amplitudeVpp, kind);
            end
            raw = {};
            if obj.Cfg.output.saveRawStream
                b = obj.Daq.rawBytes();      % last repetition's undecoded bytes (empty: the driver keeps none)
                if ~isempty(b), raw = {b}; end
            end
            meas.rawStreamLast = raw;
            meas.integrityOk = all(cellfun(@(i) i.integrity.ok, infos));
            if ~meas.integrityOk
                obj.log('Warning: data integrity problems detected – see the repetition lines above; the details are saved with the raw data.');
            end
        end

        function confirmExcitation(obj, amplitudeVpp, what)
            % Operator confirmation of generator amplitude + manual amplifier
            % gain before the loudspeaker is driven. Asked once per
            % combination (a calibration with 9 sweeps asks once); asked again
            % after setAmplifier() or an amplitude change.
            amp = obj.Cfg.amplifier;
            kind = 'sweep'; if startsWith(what, 'random noise'), kind = 'noise'; end
            % loudspeaker protection (always, also without confirmation): the
            % power at the nominal impedance against the test limit (WO-004)
            d = obj.driveEstimate(amplitudeVpp, kind);
            if strcmp(obj.Cfg.mode, 'hardware') && ~d.direct && isnan(d.gain)
                error('tim:session:gainRequired', '%s', tim.app.msg(obj.lang(), 'gainRequired'));
            end
            if d.P_W > d.limit_W
                obj.Gen.outputOff();
                error('tim:session:speakerPower', '%s', tim.app.msg(obj.lang(), 'speakerPower', 1e3 * d.P_W, 1e3 * d.limit_W));
            end
            if ~amp.confirmBeforeExcitation, return; end
            if strcmp(obj.Cfg.mode, 'simulation') && isempty(obj.ExcitationConfirm), return; end
            sig = sprintf('%.6g|%s|%.6g|%s', amplitudeVpp, amp.gainSetting, amp.gain_dB, amp.model);
            if strcmp(sig, obj.ConfirmedExcitation), return; end
            lang = obj.lang();
            msg = tim.app.msg(lang, 'confirmExcitation', what, amplitudeVpp, obj.Cfg.generator.maxVpp, ...
                obj.amplifierLine(amplitudeVpp, kind), obj.Cfg.generator.load, d.Voc_pp);
            if startsWith(what, 'stepped sine (equal')
                % the equalizer (1.6.0): the level above is the maximum; the
                % pre-measurement and the main measurement are confirmed once
                % (the same signature)
                st = obj.Cfg.excitation.stepped; eq = tim.app.equalizerSettings(st);
                if contains(what, 'pre-measurement')
                    msg = sprintf('%s\n%s', msg, tim.app.msg(lang, 'eqConfirm', eq.preLevel_dB, ...
                        obj.equalizerPreLevel(st, eq) / 2, eq.tolerance_dB));
                else
                    msg = sprintf('%s\n%s', msg, tim.app.msg(lang, 'eqConfirmPlan', eq.tolerance_dB));
                end
            end
            fcn = obj.ExcitationConfirm;
            if isempty(fcn), fcn = @(m) tim.app.MeasurementSession.consoleConfirm(m, lang, obj.ConsoleInput); end
            if ~fcn(msg)
                obj.Gen.outputOff();
                error('tim:session:notConfirmed', 'Excitation cancelled by the operator – the loudspeaker was not driven.');
            end
            obj.ConfirmedExcitation = sig;
            obj.log('Excitation confirmed: generator %.3g Vpk (%.3g Vpp). %s', amplitudeVpp / 2, amplitudeVpp, ...
                obj.amplifierLine(amplitudeVpp, kind));
        end

        function requireConnected(obj)
            if ~obj.Connected, error('tim:session:state', 'Instruments not connected. Connect first.'); end
        end
        function requirePrepared(obj)
            obj.requireConnected();
            if ~obj.Prepared, error('tim:session:state', 'Acquisition not ready. Connect the instruments first.'); end
            % A stand-alone measurement starts with a cleared stop flag. Inside a
            % multi-measurement operation (e.g. calibration) a STOP pressed
            % between two measurements must NOT be lost (bench finding).
            if ~obj.InOperation
                obj.StopRequested = false;
            end
            obj.checkStop();
        end
        function checkStop(obj)
            if ~isempty(obj.BlockCallback)
                try, obj.BlockCallback(); catch, end    % e.g. drawnow -> processes Stop button
            end
            if obj.StopRequested
                obj.Gen.outputOff();
                error('tim:session:stopped', 'Measurement stopped by user.');
            end
        end
        function setStatus(obj, s)
            obj.Status = s;
        end
        function t = okText(~, integ)
            if integ.ok, t = 'OK'; else, t = ['failed: ' strjoin(integ.fatal, '; ')]; end
        end
    end

    methods (Static)
        function v = ternary(c, a, b)
            if c, v = a; else, v = b; end
        end
        function m = micsByChannel(m)
            %MICSBYCHANNEL Microphone list sorted by DAQ channel (element c =
            %   channel c = record column c). validateConfig accepts cfg.mics in
            %   any order; consumers that index by column (sensitivities, DAQ
            %   channel names, GUI live display) need channel order (review plots-11).
            if ~isempty(m) && isfield(m, 'channel')
                [~, i] = sort([m.channel]);
                m = m(i);
            end
        end
        function disarmSource(gen)
            %DISARMSOURCE armOutput(false) if the source is still armed (also
            %   switches its output off). Never throws.
            try
                if ~isempty(gen) && isvalid(gen) && gen.OutputArmed, gen.armOutput(false); end
            catch err
                warning('tim:session:outputGuard', 'Output guard: %s', err.message);
            end
        end
        function s = equalizerSummary(plan)
            %EQUALIZERSUMMARY The equalizer plan of a measurement for its
            %   metadata (metadata.json; 1.6.0): settings, levels, the steps at
            %   a limit, the level of every step and the pre-measurement time.
            %   The whole plan with the pre-measurement result is meas.equalizer.
            lim = plan.limited;
            s = struct('mode', plan.mode, 'unit', plan.unit, 'target', plan.target, 'tolerance_dB', plan.tolerance_dB, ...
                'preLevel_dB', plan.preLevel_dB, 'preVpp', plan.preVpp, 'maxVpp', plan.maxVpp, 'minVpp', plan.minVpp, ...
                'nSteps', numel(plan.vpp), 'nAtMaximum', nnz(strcmp(lim, 'max')), 'nAtMinimum', nnz(strcmp(lim, 'min')), ...
                'nWithoutLevel', nnz(strcmp(lim, 'unknown')), 'reusedFrom', plan.reusedFrom, ...
                'preTimestamp', plan.pre.timestamp, 'frequencies', plan.freqs, 'stepVpp', plan.vpp);
        end
        function s = sourceName(key)
            %SOURCENAME Operator name of a sensitivity source key ('teds' -> 'TEDS').
            s = char(key);
            if strcmpi(s, 'teds'), s = 'TEDS'; end
        end
        function ok = consoleConfirm(msg, lang, reader)
            %CONSOLECONFIRM Default excitation confirmation in hardware mode:
            %   prints msg in the command window and continues only on "y".
            %   reader (tests only): replaces input(prompt, 's').
            if nargin < 2, lang = 'en'; end
            if nargin < 3, reader = @input; end
            fprintf('\n%s\n', msg);
            a = reader(tim.app.msg(lang, 'typeY'), 's');
            ok = strcmpi(strtrim(a), 'y');
        end
    end
end
