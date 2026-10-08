classdef MeasurementSession < handle
    %MEASUREMENTSESSION Connects instruments and runs measurements.
    %
    %   s = tim.app.MeasurementSession(cfg);
    %   s.connect();                  % generator output stays OFF
    %   s.prepareAcquisition();       % LAN-XI -> RecorderStreaming, TEDS, sensitivities
    %   meas = s.measure();           % USER START: arms output, runs cfg.excitation.mode
    %   s.close();
    %
    %   cfg.mode = 'simulation' uses MockScpiTransport / MockLanXiHttp coupled
    %   by a tim.sim.SimulatedRig; 'hardware' uses the real instruments.
    %
    %   SCHEDULING WITHOUT SHARED CLOCK: every action (output on, trigger,
    %   frequency step, output off) is scheduled on the number of samples
    %   already RECEIVED from the LAN-XI. The true acoustic timing differs by
    %   the network/stream latency and the generator trigger latency; the
    %   design only requires that the excitation happens inside the recorded
    %   window (verified afterwards by tim.dsp.detectExcitation) - the
    %   relative microphone responses do not depend on it.
    %
    %   SAFETY: generator output is armed only inside measure*(); any error
    %   switches the output off, stops the acquisition, preserves the data
    %   received so far (s.LastPartial, and an emergency file) and rethrows.

    properties (SetAccess = private)
        Cfg struct
        Gen = []
        Daq = []
        Rig = []
        Http = []
        Mics struct
        Status char = 'disconnected'
        LastPartial = []
        LogLines cell = {}
        ConfirmedExcitation char = ''    % signature of the last operator-confirmed excitation
        Connected logical = false
        Prepared logical = false
    end
    properties
        Calibration = []
        StatusCallback = []      % @(msg) for GUI
        BlockCallback = []       % @() called for every received block (GUI: drawnow limitrate)
        ExcitationConfirm = []   % @(msg) -> logical; operator confirmation of amplitude + amplifier gain
                                 % (default in hardware mode: command-window prompt)
        StopRequested logical = false
        InOperation logical = false  % inside a multi-measurement operation (calibration)
        ProgressCallback = []    % @(key, state, detail): connection checklist (GUI). keys:
                                 % gen, lanxi, idle, open, teds, setup, sens, settle, signal;
                                 % state: run | ok | warn | fail | skip
    end
    properties (Access = private)
        ProgressKey char = ''    % checklist step currently running (marked 'fail' on error)
        OperationDepth double = 0  % nested beginOperation calls (GUI action > calibration)
        Closed logical = false   % close() done: never shut the module down twice
    end

    methods
        function obj = MeasurementSession(cfg)
            if nargin < 1, cfg = tim.app.defaultConfig(); end
            tim.app.validateConfig(cfg);
            obj.Cfg = cfg;
            obj.Mics = cfg.mics;
            if ~isempty(cfg.calibration.file)
                obj.loadCalibration(cfg.calibration.file);
            end
        end

        %% ---- connection -------------------------------------------------
        function connect(obj)
            c = obj.Cfg;
            obj.log('Connecting (%s mode)...', c.mode);
            sim = strcmp(c.mode, 'simulation');
            try
                obj.progress('gen', 'run', tim.app.MeasurementSession.ternary(sim, 'simulated instrument', ...
                    sprintf('%s:%d (SCPI over TCP)', c.generator.host, c.generator.port)));
                switch c.mode
                    case 'simulation'
                        obj.Rig = tim.sim.SimulatedRig(c);
                        tr = tim.instr.MockScpiTransport(obj.Rig);
                        obj.Http = tim.instr.MockLanXiHttp(obj.Rig);
                        http = obj.Http;
                        factory = @(h, p) tim.instr.RecordingStream(http.openStream(h, p));
                    case 'hardware'
                        tr = tim.instr.ScpiTcpTransport(c.generator.host, c.generator.port, c.generator.timeout);
                        obj.Http = tim.instr.LanXiHttp(c.lanxi.host, c.lanxi.timeout);
                        factory = @(h, p) tim.instr.RecordingStream(tim.instr.LanXiTcpStream(h, p));
                end
                obj.Gen = tim.instr.Keysight33220A(tr, 'MaxVpp', c.generator.maxVpp, 'Load', c.generator.load);
                obj.log('Generator: %s (output OFF)', obj.Gen.Identity.raw);
                obj.progress('gen', 'ok', sprintf('%s - output OFF', obj.Gen.Identity.raw));
                obj.progress('lanxi', 'run', tim.app.MeasurementSession.ternary(sim, 'simulated module', ...
                    sprintf('%s (REST, Open API)', c.lanxi.host)));
                obj.Daq = tim.instr.LanXi(obj.Http, factory, 'Host', c.lanxi.host);
                info = obj.Daq.moduleInfo();
                obj.log('LAN-XI: %s s/n %d firmware %s, state %s', info.model, info.serial, info.firmware, info.moduleState);
                obj.progress('lanxi', 'ok', sprintf('%s  s/n %d  firmware %s', info.model, info.serial, info.firmware));
                obj.progress('idle', 'run', sprintf('state %s', info.moduleState));
                if ~strcmp(info.moduleState, 'Idle')
                    obj.log('LAN-XI not Idle (%s): returning it to Idle.', info.moduleState);
                    obj.Daq.shutdown();
                    obj.progress('idle', 'ok', sprintf('was %s - returned to Idle', info.moduleState));
                else
                    obj.progress('idle', 'ok', 'Idle');
                end
            catch err
                obj.progressFailed(err);
                rethrow(err);
            end
            obj.Connected = true;
            obj.setStatus('connected');
        end

        function prepareAcquisition(obj)
            obj.requireConnected();
            a = obj.Cfg.acquisition;
            dc = struct('sampleRate', a.sampleRate, 'range', a.range, 'filter', a.filter, ...
                'ccld', a.ccld, 'channels', 1:4, 'detectTeds', a.detectTeds, ...
                'connector', obj.Cfg.lanxi.connector, ...
                'names', {arrayfun(@(m) sprintf('M%d', m.position), obj.Cfg.mics, 'UniformOutput', false)});
            try
                obj.Daq.ProgressFcn = @(key, state, detail) obj.progress(key, state, detail);
                obj.Daq.prepare(dc);
                obj.progress('sens', 'run', a.sensitivityPolicy);
                obj.Mics = tim.cal.resolveSensitivities(obj.Cfg.mics, obj.Daq.Teds, a.sensitivityPolicy);
                parts = cell(1, numel(obj.Mics)); state = 'ok';
                for i = 1:numel(obj.Mics)
                    m = obj.Mics(i);
                    obj.log('ch%d (pos M%d): %.4g mV/Pa from %s%s', m.channel, m.position, ...
                        1e3 * m.sensitivity_VperPa, m.sensitivitySource, ...
                        tim.app.MeasurementSession.ternary(m.serialMismatch, ' (TEDS serial differs from configuration!)', ''));
                    parts{i} = sprintf('ch%d %.4g (%s)', m.channel, 1e3 * m.sensitivity_VperPa, m.sensitivitySource);
                    if m.serialMismatch || ~any(strcmp(m.sensitivitySource, {'certificate', 'teds'}))
                        state = 'warn';       % nominal value or wrong microphone
                    end
                end
                obj.progress('sens', state, ['mV/Pa: ' strjoin(parts, ',  ')]);
                if strcmp(obj.Cfg.mode, 'hardware') && a.settleTime > 0
                    obj.log('Settling %.1f s (CCLD / high-pass)...', a.settleTime);
                    obj.progress('settle', 'run', sprintf('%.1f s (CCLD + %s high-pass)', a.settleTime, a.filter));
                    pause(a.settleTime);
                    obj.progress('settle', 'ok', sprintf('%.1f s', a.settleTime));
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
            if nargin < 2, duration = 1; end
            obj.progress('signal', 'run', sprintf('%.1f s recording, no excitation', duration));
            try
                m = obj.measureBackground(duration);
            catch err
                obj.progressFailed(err);
                rethrow(err);
            end
            x = m.records{1}; info = m.channelInfo{1};
            rangeV = sscanf(obj.Cfg.acquisition.range, '%f');
            q = info.qualityEvents;
            ids = 1:size(x, 2); if isfield(info, 'signalIds'), ids = info.signalIds; end
            chk = struct('channel', {}, 'spl_dB', {}, 'peak_V', {}, 'state', {}, 'text', {});
            for c = 1:size(x, 2)
                v = x(:, c) - mean(x(:, c));
                s = obj.Mics(c).sensitivity_VperPa;
                spl = 20 * log10(sqrt(mean(v.^2)) / s / 2e-5);
                pk = max(abs(x(:, c)));
                flags = {};
                if ~isempty(q)
                    mine = [q.signalId] == ids(c);
                    if any([q(mine).invalid]), flags{end+1} = 'INVALID (cable / CCLD fault)'; end %#ok<AGROW>
                    if any([q(mine).clipped]), flags{end+1} = 'CLIPPED'; end %#ok<AGROW>
                end
                if std(x(:, c)) == 0, flags{end+1} = 'constant (dead)'; end %#ok<AGROW>
                if ~isempty(rangeV) && pk >= 0.99 * rangeV, flags{end+1} = 'overload'; end %#ok<AGROW>
                if isempty(flags)
                    st = 'ok'; txt = sprintf('%.1f dB SPL', spl);
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
            %   the next step (own steps; steps reported by LanXi.prepare
            %   cannot throw through its callback guard).
            if nargin < 4, detail = ''; end
            if strcmp(state, 'run') && obj.StopRequested
                obj.ProgressKey = '';
                if ~isempty(obj.ProgressCallback)
                    try, obj.ProgressCallback(key, 'fail', 'stopped by the operator'); catch, end
                end
                error('tim:session:stopped', 'Connection stopped by user.');
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
                otherwise, error('tim:session:mode', 'Unknown excitation mode "%s".', mode);
            end
        end

        function meas = measureBackground(obj, duration)
            %MEASUREBACKGROUND Record without excitation (noise floor, Test A).
            obj.requirePrepared();
            fs = obj.Cfg.acquisition.sampleRate;
            [data, info] = obj.Daq.acquire(round(duration * fs));
            meas = obj.packMeasurement('background', {data}, {info}, struct('duration', duration), {});
        end

        function meas = measureSweep(obj)
            obj.requirePrepared();
            sw = obj.Cfg.excitation.sweep;
            fs = obj.Cfg.acquisition.sampleRate;
            obj.Gen.configureSweep(sw);
            obj.log('Sweep %g-%g Hz %s, %.2f s, %.3g Vpk (%.3g Vpp), %d repetition(s).', sw.fStart, sw.fStop, ...
                sw.spacing, sw.duration, sw.amplitudeVpp / 2, sw.amplitudeVpp, sw.repetitions);
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
                    ev.opcOk = obj.Gen.waitComplete(5);   % *OPC? returns when the sweep is complete
                    obj.Gen.outputOff();
                    ev.offSample = n;
                end
            end
            for r = 1:sw.repetitions
                obj.checkStop();
                ev = struct('triggerSample', NaN, 'offSample', NaN, 'opcOk', false);
                [data, info] = obj.guardedAcquire(nTotal, @onBlock, sprintf('sweep repetition %d', r), records, infos, sw.amplitudeVpp);
                if isnan(ev.offSample), obj.Gen.outputOff(); end
                records{end+1} = data; infos{end+1} = info; events{end+1} = ev; %#ok<AGROW>
                obj.log('Repetition %d: trigger issued at sample %d, output off at %d; integrity %s', ...
                    r, ev.triggerSample, ev.offSample, obj.okText(info.integrity));
            end
            obj.Gen.armOutput(false);
            meas = obj.packMeasurement('sweep', records, infos, sw, events);
        end

        function meas = measureStepped(obj)
            obj.requirePrepared();
            st = obj.Cfg.excitation.stepped;
            fs = obj.Cfg.acquisition.sampleRate;
            if strcmpi(st.spacing, 'log')
                freqs = logspace(log10(st.fStart), log10(st.fStop), st.nPoints);
            else
                freqs = linspace(st.fStart, st.fStop, st.nPoints);
            end
            obj.Gen.configureSine(freqs(1), st.amplitudeVpp);
            nSettle = round(st.settleTime * fs); nRec = round(st.recordTime * fs);
            nPre = round(0.5 * fs);
            nStep = nSettle + nRec;
            % Steps are scheduled at FIXED targets onSample + (k-1)*nStep, so the
            % block granularity of the received data (overshoot <= 1 block) does
            % not accumulate over the steps (bug found on the bench test).
            nTotal = nPre + numel(freqs) * nStep + round(0.5 * fs);
            ev = struct('stepStart', nan(1, numel(freqs)), 'freqs', freqs, 'onSample', NaN);
            k = 0;
            function onBlock(n)
                obj.checkStop();
                if isnan(ev.onSample) && n >= nPre
                    obj.Gen.outputOn(); ev.onSample = n; k = 1; ev.stepStart(1) = n;
                elseif k >= 1 && k < numel(freqs) && n >= ev.onSample + k * nStep
                    k = k + 1;
                    obj.Gen.setFrequency(freqs(k));
                    ev.stepStart(k) = n;
                elseif k == numel(freqs) && n >= ev.onSample + k * nStep
                    obj.Gen.outputOff(); k = k + 1;
                end
            end
            records = {}; infos = {}; evs = {};
            for r = 1:st.repetitions
                ev.stepStart(:) = NaN; ev.onSample = NaN; k = 0;
                if r > 1, obj.Gen.setFrequency(freqs(1)); end
                [data, info] = obj.guardedAcquire(nTotal, @onBlock, 'stepped sine', records, infos, st.amplitudeVpp);
                obj.Gen.outputOff();
                records{end+1} = data; infos{end+1} = info; %#ok<AGROW>
                evs{r} = ev; %#ok<AGROW>
            end
            obj.Gen.armOutput(false);
            st.frequencies = freqs; st.settleSamples = nSettle; st.recordSamples = nRec;
            meas = obj.packMeasurement('stepped', records, infos, st, evs);
        end

        function meas = measureNoise(obj)
            obj.requirePrepared();
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
            [data, info] = obj.guardedAcquire(nTotal, @onBlock, 'noise', {}, {}, nz.amplitudeVpp);
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
                error('tim:session:gain', 'Amplifier gain factor must be > 0 (or NaN if unknown).');
            end
            a = obj.Cfg.amplifier;
            a.model = model; a.gainFactor = gainFactor; a.gain_dB = 20 * log10(gainFactor);
            a.gainSetting = char(note);
            if ~isfield(a, 'knownModels') || isempty(a.knownModels), a.knownModels = {'none (direct drive)'}; end
            if ~isempty(model) && ~any(strcmp(a.knownModels, model)), a.knownModels{end+1} = model; end
            obj.Cfg.amplifier = a;
            obj.ConfirmedExcitation = '';
            obj.log('Amplifier recorded: %s, gain x%g (%.1f dB)%s.', ...
                tim.app.MeasurementSession.ternary(isempty(model), 'model not specified', model), ...
                gainFactor, a.gain_dB, tim.app.MeasurementSession.ternary(isempty(a.gainSetting), '', [' "' a.gainSetting '"']));
        end

        function d = driveEstimate(obj, amplitudeVpp)
            %DRIVEESTIMATE Expected loudspeaker drive (see tim.app.driveEstimate).
            d = tim.app.driveEstimate(obj.Cfg, amplitudeVpp);
        end

        function setLoudspeaker(obj, impedance_ohm, maxPower_W)
            %SETLOUDSPEAKER Loudspeaker data used for the drive estimate / power limit.
            c = obj.Cfg;
            c.loudspeaker.impedance_ohm = impedance_ohm;
            c.loudspeaker.maxPower_W = maxPower_W;
            tim.app.validateConfig(c);
            obj.Cfg = c;
        end

        function setGeometryEnvironment(obj, geometry, environment)
            %SETGEOMETRYENVIRONMENT Update tube geometry / air conditions (metadata).
            c = obj.Cfg; c.geometry = geometry; c.environment = environment;
            tim.app.validateConfig(c);
            obj.Cfg = c;
        end

        function line = amplifierLine(obj, amplitudeVpp)
            %AMPLIFIERLINE Operator-readable description of the drive chain.
            a = obj.Cfg.amplifier; lang = obj.lang();
            d = obj.driveEstimate(amplitudeVpp);
            note = '';
            if ~isempty(a.gainSetting) && ~strcmp(a.gainSetting, '-'), note = sprintf(' (setting "%s")', a.gainSetting); end
            mdl = a.model; if isempty(mdl), mdl = '(model not specified)'; end
            if d.direct
                line = tim.app.msg(lang, 'ampDirect', d.Z, d.Vspk_pk, 1e3 * d.Ipk, 1e3 * d.P_W, 1e3 * d.limit_W);
            elseif isfinite(d.gain)
                line = tim.app.msg(lang, 'ampGain', mdl, d.gain, 20 * log10(d.gain), d.Z, d.Vspk_pk, ...
                    1e3 * d.P_W, 1e3 * d.limit_W, note);
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
            c = obj.Cfg; c.excitation = ex;
            tim.app.validateConfig(c);
            obj.Cfg = c;
        end

        %% ---- calibration ----------------------------------------------------
        function loadCalibration(obj, file)
            S = load(file, 'cal');
            if ~isfield(S, 'cal') || ~strcmp(S.cal.type, 'tim.complexChannelCalibration')
                error('tim:cal:file', '"%s" is not a complex channel calibration file.', file);
            end
            obj.Calibration = S.cal;
            obj.log('Loaded calibration %s (%s).', S.cal.version, file);
        end

        function setMicPositionsForSimulation(obj, mapping)
            %Simulation only: emulate physically moving microphones.
            if isempty(obj.Rig), error('tim:session:sim', 'Only available in simulation mode.'); end
            obj.Rig.MicPosOfChannel = mapping;
        end

        function prev = setSimulationSample(obj, sample)
            %SETSIMULATIONSAMPLE Simulation only: exchange the specimen of the virtual
            %   rig, e.g. struct('type','air') = EMPTY specimen section (air column of
            %   length xRear - xFront, tim.sim.tubeModel). Returns the previous sample.
            if isempty(obj.Rig), error('tim:session:sim', 'Only available in simulation mode.'); end
            prev = obj.Rig.Sample;
            obj.Rig.Sample = sample;          % setter marks the FIR for re-design
            obj.log('Simulation: specimen section -> "%s".', sample.type);
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

        function close(obj, fast)
            %CLOSE Generator output off + local, LAN-XI back to Idle. close(true)
            %   uses short time-outs (2 s) so that closing the app never waits
            %   long for an instrument that does not answer (switched off).
            if nargin < 2, fast = false; end
            if obj.Closed, return; end         % e.g. the destructor of an already closed session
            obj.Closed = true;
            if fast
                for h = {obj.Http, obj.Gen}
                    try
                        t = h{1};
                        if isa(t, 'tim.instr.Keysight33220A'), t = t.Transport; end
                        if ~isempty(t) && ismethod(t, 'setTimeout'), t.setTimeout(2); end
                    catch
                    end
                end
            end
            if ~isempty(obj.Gen)
                try, obj.Gen.close(); catch, end
            end
            if ~isempty(obj.Daq)
                try, obj.Daq.shutdown(); catch, end
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
        function progressFailed(obj, err)
            % the running checklist step failed
            if ~isempty(obj.ProgressKey)
                obj.progress(obj.ProgressKey, 'fail', err.message);
            end
        end

        function [data, info] = guardedAcquire(obj, nTotal, onBlock, what, prevRecords, prevInfos, amplitudeVpp)
            obj.confirmExcitation(amplitudeVpp, what);
            obj.Gen.armOutput(true);       % explicit user start of this measurement
            obj.setStatus(['measuring: ' what]);
            try
                [data, info] = obj.Daq.acquire(nTotal, onBlock);
            catch err
                obj.Gen.outputOff();
                obj.Gen.armOutput(false);
                partial = struct('records', {prevRecords}, 'infos', {prevInfos}, 'error', err.message);
                try
                    [pd, pinfo] = obj.Daq.collect();
                    partial.records{end+1} = pd; partial.infos{end+1} = pinfo;
                catch
                end
                try
                    if ~isempty(obj.Daq.LastStream) && isa(obj.Daq.LastStream, 'tim.instr.RecordingStream')
                        partial.rawStream = obj.Daq.LastStream.bytes();
                    end
                catch
                end
                obj.LastPartial = partial;
                f = tim.app.saveEmergency(obj, partial);
                obj.setStatus('error');
                obj.log('ERROR during %s: %s. Output switched off. Partial data saved to %s', what, err.message, f);
                rethrow(err);
            end
            obj.setStatus('ready');
        end

        function meas = packMeasurement(obj, kind, records, infos, settings, events)
            meas = struct();
            meas.kind = kind;
            meas.records = records;          % RAW volts, never modified
            meas.fs = obj.Cfg.acquisition.sampleRate;
            meas.unit = 'V';
            meas.channelInfo = infos;
            meas.settings = settings;
            meas.events = events;
            meas.mics = obj.Mics;
            meas.timestamp = char(datetime('now'), 'yyyy-MM-dd HH:mm:ss.SSS');
            meas.metadata = tim.app.collectMetadata(obj);
            raw = {};
            if obj.Cfg.output.saveRawStream && ~isempty(obj.Daq.LastStream) && isa(obj.Daq.LastStream, 'tim.instr.RecordingStream')
                raw = {obj.Daq.LastStream.bytes()};   % last repetition's undecoded bytes
            end
            meas.rawStreamLast = raw;
            meas.integrityOk = all(cellfun(@(i) i.integrity.ok, infos));
            if ~meas.integrityOk
                obj.log('WARNING: data-integrity problems detected - see meas.channelInfo{.}.integrity');
            end
        end

        function confirmExcitation(obj, amplitudeVpp, what)
            % Operator confirmation of generator amplitude + manual amplifier
            % gain before the loudspeaker is driven. Asked once per
            % combination (a calibration with 9 sweeps asks once); asked again
            % after setAmplifier() or an amplitude change.
            amp = obj.Cfg.amplifier;
            % loudspeaker protection (always, also without confirmation)
            d = obj.driveEstimate(amplitudeVpp);
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
                obj.amplifierLine(amplitudeVpp));
            fcn = obj.ExcitationConfirm;
            if isempty(fcn), fcn = @(m) tim.app.MeasurementSession.consoleConfirm(m, lang); end
            if ~fcn(msg)
                obj.Gen.outputOff();
                error('tim:session:notConfirmed', 'Excitation not confirmed by the operator - nothing was played.');
            end
            obj.ConfirmedExcitation = sig;
            obj.log('Excitation confirmed: %.3g Vpk (%.3g Vpp); %s', amplitudeVpp / 2, amplitudeVpp, obj.amplifierLine(amplitudeVpp));
        end

        function requireConnected(obj)
            if ~obj.Connected, error('tim:session:state', 'Not connected. Call connect() first.'); end
        end
        function requirePrepared(obj)
            obj.requireConnected();
            if ~obj.Prepared, error('tim:session:state', 'Acquisition not prepared. Call prepareAcquisition() first.'); end
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
            if integ.ok, t = 'OK'; else, t = ['FAILED: ' strjoin(integ.fatal, '; ')]; end
        end
    end

    methods (Static)
        function v = ternary(c, a, b)
            if c, v = a; else, v = b; end
        end
        function ok = consoleConfirm(msg, lang)
            if nargin < 2, lang = 'en'; end
            fprintf('\n%s\n', msg);
            a = input(tim.app.msg(lang, 'typeY'), 's');
            ok = strcmpi(strtrim(a), 'y');
        end
    end
end
