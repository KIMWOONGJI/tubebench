classdef SimulatedCombined < tim.instr.SignalSource & tim.instr.Acquisition
    %SIMULATEDCOMBINED Simulated combined device: one output and four inputs on one clock.
    %
    %   Driver 'simcombined' of the registry (tim.instr.drivers), simulation
    %   mode only. Selected in the configuration for BOTH roles:
    %       "generator": {"driver": "simcombined", ...}, "daq": {"driver": "simcombined"}
    %   s = tim.app.MeasurementSession(cfg) then holds ONE object as s.Gen and
    %   s.Daq.
    %
    %   A deliberately different instrument from the 33220A + LAN-XI pair
    %   (WO-001 section 0, change B), modelled on a DAQ card with an analog
    %   output or an audio interface: output and inputs on one sample clock,
    %   data recorded in blocks (nothing is delivered while it records), no
    %   TEDS, no recorder states, an output of about 0 ohm whose state is read
    %   back from the device session, a sample-buffer output whose "off" is
    %   0 V. It implements the instrument contract (docs/instrument_interface.md)
    %   directly on tim.sim.SimulatedRig: the planned output samples go through
    %   rig.respond (excitation volts in, microphone volts out); no protocol
    %   mock. It is also the model for a real combined driver.
    %
    %   TIMING (contract section 8.3). acquire(n, onBlock) first runs a
    %   PLANNING PASS: onBlock(B), onBlock(2B), ... up to n without waiting
    %   (B = settings.blockSamples), isPlanning() is true, and every source call
    %   made meanwhile - outputOn, triggerSweep, setFrequency, configure*,
    %   outputOff - is scheduled sample-exactly at the current n on the device
    %   timeline. An error out of onBlock (e.g. a Stop) discards the plan:
    %   nothing is played. Then the EXECUTION plays the plan while recording
    %   and calls onBlock(nDone) again from the first block; a level,
    %   frequency, trigger or outputOn call then raises tim:gen:schedule, and
    %   outputOff stops the output at once (5 ms fade to 0 V, then zeros; the
    %   recording continues to the end). Outside acquire, configure* and
    %   setFrequency set the initial state of the next plan, outputOn and
    %   triggerSweep raise tim:gen:schedule and isOutputOn is false.
    %
    %   OUTPUT OFF = 0 V (section 3.1): 0 V is written on creation, by
    %   outputOff, close and delete, and every plan or abnormal end finishes
    %   with a 5 ms raised-cosine fade to 0 V followed by zeros.
    %   Waveforms (section 3.3): sine; exponential (LOG) or linear (LIN) swept
    %   sine, sample-exact, phase continuous, back to fStart after the sweep;
    %   Gaussian noise with rms = Vpp / 6.6. Load 'INF' only (the programmed
    %   value is the open-circuit voltage).
    %
    %   Settings (daq.simcombined): blockSamples (2048), serial ('SIM-0001'),
    %   seed (random numbers of the noise output, 11).
    %   testHooks: traffic, breakLink, outputOn, levelHistory, forceOutputOn,
    %   injectError, stallAfter, injectChannelFault, isRecording, plus
    %   outputLog (the rig's OutputLog) and playedSignal (the output samples
    %   of the last acquisition).

    properties (SetAccess = private)
        Rig = []                  % tim.sim.SimulatedRig
        Settings struct = struct()
        MaxVpp double = 0.5       % generator.maxVpp (fixed at creation)
        Load char = 'INF'
        Mode char = 'none'        % configured waveform: 'none' | 'sine' | 'sweep' | 'noise'
        Level double = NaN        % configured level [Vpp]
        Frequency double = NaN    % sine frequency [Hz]
        Sweep struct = struct()   % configured sweep (fStart, fStop, duration, spacing)
        Range char = ''           % input range after prepare
        Filter char = ''
        Ccld logical = true(1, 4)
        Log cell = {}             % device operations (test hook 'traffic')
        LevelLog double = zeros(1, 0)   % every level programmed [Vpp]
        Played double = zeros(0, 1)     % output samples of the last acquisition [V]
    end
    properties (Access = private)
        ClockRate double = NaN    % acquisition.sampleRate captured at creation (before prepare)
        Prepared logical = false
        Closed logical = false
        Planning logical = false
        Executing logical = false
        Recording logical = false
        Done logical = false      % acquire reached its normal end (no abort)
        PlanN double = 0          % sample count of the running planning call
        Plan struct               % source state while the plan is built
        Events struct = struct('n', {}, 'type', {}, 'value', {})   % the plan
        Next double = 1           % next event to apply while playing
        Out struct                % output state while playing
        Data double = zeros(0, 4)
        Received double = 0
        DeviceOn logical = false  % the output produces a signal (device session state)
        Fault struct = struct('broken', false, 'error', '', 'stallAfter', Inf, 'channels', [])
        Rng
    end
    properties (Constant)
        FadeTime = 5e-3           % s, raised-cosine fade to 0 V
    end

    methods
        function obj = SimulatedCombined(rig, settings, maxVpp, load, sampleRate)
            %SIMULATEDCOMBINED Device on rig (tim.instr.create builds it through fromConfig).
            obj.Rig = rig;
            obj.Settings = settings;
            obj.MaxVpp = maxVpp;
            obj.Load = char(load);
            obj.ClockRate = sampleRate;
            obj.Rng = RandStream('mt19937ar', 'Seed', settings.seed);
            obj.Plan = obj.sourceState();
            obj.device('open');
            obj.writeZero();                          % output 0 V before anything else
        end

        %% ---- signal source ------------------------------------------------
        function configureSine(obj, f, vpp)
            %CONFIGURESINE Continuous sine f [Hz], vpp [Vpp]; output off.
            obj.assertOpen('configureSine');
            obj.assertNotPlaying('configureSine');
            obj.checkLevel(vpp);
            obj.checkFrequency(f, 'tim:gen:unsupported');
            obj.configure(struct('mode', 'sine', 'level', vpp, 'f', f, 'sweep', struct()), ...
                sprintf('configure sine %.6g Hz %.4g Vpp', f, vpp));
        end

        function setFrequency(obj, f)
            %SETFREQUENCY New sine frequency, phase continuous (sine only).
            obj.assertOpen('setFrequency');
            if ~strcmp(obj.planOrConfig().mode, 'sine')
                error('tim:gen:mode', 'setFrequency requires sine mode.');
            end
            obj.assertNotPlaying('setFrequency');
            obj.checkFrequency(f, 'tim:gen:unsupported');
            if obj.Planning
                obj.schedule('freq', f);
                obj.Plan.f = f;
            else
                obj.device(sprintf('frequency %.6g Hz', f));
                obj.Frequency = f;
            end
        end

        function configureSweep(obj, s)
            %CONFIGURESWEEP Single swept sine s.fStart, s.fStop [Hz], s.duration [s],
            %   s.spacing 'LOG'|'LIN', s.amplitudeVpp; started by triggerSweep.
            obj.assertOpen('configureSweep');
            obj.assertNotPlaying('configureSweep');
            obj.checkLevel(s.amplitudeVpp);
            c = tim.sim.SimulatedCombined.capabilities();
            if ~(s.duration >= c.source.sweepTime(1) && s.duration <= c.source.sweepTime(2))
                error('tim:gen:sweep', 'Sweep time %.3g s outside %g .. %g s.', s.duration, ...
                    c.source.sweepTime(1), c.source.sweepTime(2));
            end
            if ~(s.fStart > 0 && s.fStop > 0)
                error('tim:gen:sweep', 'Sweep frequencies must be positive.');
            end
            obj.checkFrequency([s.fStart s.fStop], 'tim:gen:sweep');
            spacing = upper(char(s.spacing));
            if ~any(strcmp(spacing, c.source.sweepSpacing))
                error('tim:gen:sweep', 'Sweep spacing must be LOG or LIN.');
            end
            sw = struct('fStart', s.fStart, 'fStop', s.fStop, 'duration', s.duration, 'spacing', spacing);
            obj.configure(struct('mode', 'sweep', 'level', s.amplitudeVpp, 'f', s.fStart, 'sweep', sw), ...
                sprintf('configure sweep %.6g-%.6g Hz %s %.6g s %.4g Vpp', s.fStart, s.fStop, spacing, s.duration, ...
                s.amplitudeVpp));
        end

        function configureNoise(obj, vpp)
            %CONFIGURENOISE Gaussian noise, rms = vpp / 6.6; output off.
            obj.assertOpen('configureNoise');
            obj.assertNotPlaying('configureNoise');
            obj.checkLevel(vpp);
            obj.configure(struct('mode', 'noise', 'level', vpp, 'f', NaN, 'sweep', struct()), ...
                sprintf('configure noise %.4g Vpp', vpp));
        end

        function armOutput(obj, tf)
            %ARMOUTPUT Permission from the session; false switches the output off.
            obj.OutputArmed = logical(tf);
            if ~tf, obj.outputOff(); end
        end

        function outputOn(obj)
            %OUTPUTON Output on at the current sample of the planning pass.
            obj.assertOpen('outputOn');
            if ~obj.OutputArmed
                error('tim:gen:notArmed', ...
                    'Output enable refused: no measurement has been explicitly started (armOutput(true) not called).');
            end
            p = obj.planOrConfig();
            if strcmp(p.mode, 'none')
                error('tim:gen:mode', 'Output enable refused: output not configured.');
            end
            obj.checkLevel(p.level);                  % re-checked right before enabling
            if ~obj.Planning
                error('tim:gen:schedule', ['Output on refused: this device plays a planned output - outputOn only ' ...
                    'inside an acquisition (planning pass).']);
            end
            obj.schedule('on', []);
            obj.Plan.on = true;
        end

        function outputOff(obj)
            %OUTPUTOFF Output off (0 V). Never throws; idempotent; re-entrant.
            %   Planning pass: scheduled at the current sample. While playing:
            %   at once (5 ms fade, then zeros). Otherwise: 0 V written.
            if obj.Closed, return; end
            try
                if obj.Planning
                    obj.schedule('off', []);
                    obj.Plan.on = false;
                elseif obj.Executing
                    obj.haltOutput();
                else
                    obj.writeZero();
                end
            catch err
                warning('tim:gen:outputOff', 'Could not switch the output off: %s', err.message);
            end
        end

        function tf = isOutputOn(obj, ~)
            %ISOUTPUTON State of the device session ('device' read-back): the
            %   output is producing a signal. False outside an acquisition.
            tf = obj.DeviceOn;
        end

        function triggerSweep(obj)
            %TRIGGERSWEEP Start the configured sweep at the current sample of the planning pass.
            obj.assertOpen('triggerSweep');
            if ~strcmp(obj.planOrConfig().mode, 'sweep')
                error('tim:gen:mode', 'triggerSweep requires a configured sweep.');
            end
            if ~obj.Planning
                error('tim:gen:schedule', 'triggerSweep refused: the sweep starts on the device clock, inside an acquisition.');
            end
            obj.schedule('trigger', []);
            obj.Plan.sweepStart = obj.PlanN;
        end

        function tf = waitComplete(obj, ~)
            %WAITCOMPLETE True when no sweep runs on the device timeline (never
            %   before the sweep has ended): in the planning pass at the planned
            %   sample, while playing at the samples played so far.
            if obj.Planning
                p = obj.Plan; n = obj.PlanN;
            elseif obj.Executing
                p = obj.Out; n = obj.Received;
            else
                tf = true; return
            end
            tf = true;
            if strcmp(p.mode, 'sweep') && ~isnan(p.sweepStart)
                tf = n >= p.sweepStart + round(p.sweep.duration * obj.SampleRate);
            end
        end

        %% ---- acquisition --------------------------------------------------
        function prepare(obj, c)
            %PREPARE Channel setup: exactly c.sampleRate (the rig's clock), the
            %   range and filter of the capabilities, CCLD. No TEDS (Teds {}).
            %   Step 'setup' to ProgressFcn.
            obj.assertOpen('prepare');
            q = tim.sim.SimulatedCombined.capabilities().acquisition;
            if ~ismember(c.sampleRate, q.sampleRates) || abs(obj.Rig.Fs - c.sampleRate) > 1e-9 * c.sampleRate
                error('tim:simcombined:rate', 'Sample rate %g S/s not possible (this device runs at %g S/s).', ...
                    c.sampleRate, obj.Rig.Fs);
            end
            if ~any(strcmp(c.range, q.ranges))
                error('tim:simcombined:range', 'Input range "%s" not supported (supported: %s).', c.range, strjoin(q.ranges, ', '));
            end
            if ~any(strcmp(c.filter, q.filters))
                error('tim:simcombined:filter', 'High-pass filter "%s" not supported (supported: %s).', c.filter, ...
                    strjoin(q.filters, ', '));
            end
            txt = sprintf('%g S/s, %s, high-pass %s', c.sampleRate, c.range, c.filter);
            obj.progress('setup', 'run', txt);
            obj.device(['channel setup ' txt]);
            obj.SampleRate = c.sampleRate;
            obj.Range = c.range; obj.Filter = c.filter;
            if isfield(c, 'ccld'), obj.Ccld = logical(c.ccld(:).'); end
            obj.Teds = {};                            % no TEDS
            obj.Prepared = true;
            obj.progress('setup', 'ok', [txt ' - ready']);
        end

        function [data, info] = acquire(obj, nSamples, onBlock, timeout)
            %ACQUIRE Plan, then play the plan and record nSamples per channel (volts).
            %   onBlock(n): planning pass (isPlanning() true), then while playing.
            %   On every abnormal end (error, onBlock error, interrupt) AbortFcn
            %   first, then the output to 0 V and the device stopped (onCleanup).
            if nargin < 3, onBlock = []; end
            if nargin < 4 || isempty(timeout), timeout = nSamples / obj.SampleRate * 1.5 + 10; end
            obj.assertOpen('acquire');
            if ~obj.Prepared
                error('tim:simcombined:state', 'acquire needs the channel setup (prepare) first.');
            end
            B = obj.Settings.blockSamples;
            marks = unique([B:B:nSamples, nSamples]);
            obj.Done = false; obj.Data = zeros(nSamples, 4); obj.Received = 0;
            obj.Played = zeros(nSamples, 1);
            fault = obj.Fault;
            cleanup = onCleanup(@() obj.endAcquire());
            % ---- planning pass: the schedule on the device timeline, nothing played
            obj.Events = obj.Events([]);
            obj.Plan = obj.sourceState();
            obj.Planning = true;
            for n = marks
                obj.PlanN = n;
                if ~isempty(onBlock), onBlock(n); end
                obj.assertOpen('acquire');            % close() from inside onBlock
            end
            obj.Planning = false;
            % ---- execution: play the plan and record
            obj.Out = obj.sourceState();
            obj.Next = 1;
            obj.device(sprintf('start: play and record %d samples', nSamples));
            obj.Executing = true; obj.Recording = true;
            t0 = tic; n0 = 0;
            for n = marks
                obj.assertOpen('acquire');
                if n > fault.stallAfter
                    error('tim:simcombined:stalled', 'No data from the device after %d of %d samples.', n0, nSamples);
                end
                obj.device(sprintf('block %d-%d', n0 + 1, n));
                x = obj.render(n0, n - n0);
                obj.Played(n0 + 1:n) = x;
                obj.Data(n0 + 1:n, :) = obj.Rig.respond(x);
                obj.Received = n; n0 = n;
                if ~isempty(onBlock), onBlock(n); end
                obj.assertOpen('acquire');            % close() from inside onBlock
                if toc(t0) > timeout
                    error('tim:simcombined:timeout', 'Acquisition time-out (%d of %d samples).', n, nSamples);
                end
            end
            obj.Executing = false; obj.Recording = false;
            obj.finishOutput();                       % fade to 0 V, zeros
            obj.device('stop');
            obj.commitPlan();
            obj.Done = true;
            [data, info] = obj.collect(nSamples);
            clear cleanup
        end

        function [data, info] = collect(obj, nSamples)
            %COLLECT Data recorded so far (volts) and the integrity report.
            data = obj.Data(1:obj.Received, :);
            if nargin >= 2 && size(data, 1) > nSamples, data = data(1:nSamples, :); end
            info = struct('fs', obj.SampleRate, 'dataUnit', 'V', 'blockSamples', obj.Settings.blockSamples);
            fullScale = sscanf(obj.Range, '%f');
            if isempty(fullScale), fullScale = NaN; end
            g = tim.acq.basicIntegrity(data, obj.SampleRate, obj.SampleRate, fullScale);
            for c = reshape(obj.Fault.channels, 1, [])
                if c >= 1 && c <= numel(g.channelFaults)
                    g.channelFaults{c}{end+1} = 'input fault reported by the device (open circuit / IEPE supply)';
                    g.fatal{end+1} = sprintf('Input %d: fault reported by the device.', c);
                end
            end
            g.ok = isempty(g.fatal);
            info.integrity = g;
        end

        function [x, nTotal] = recent(obj, n)
            %RECENT Last <= n samples of the running or last acquisition; no I/O.
            nTotal = obj.Received;
            x = [];
            if nTotal == 0, return; end
            x = obj.Data(max(1, nTotal - n + 1):nTotal, :);
        end

        function tf = isAcquiring(obj)
            %ISACQUIRING A planning pass or a recording is running.
            tf = obj.Planning || obj.Executing;
        end

        function tf = isPlanning(obj)
            %ISPLANNING True during the planning pass of acquire.
            tf = obj.Planning;
        end

        function b = rawBytes(~)
            %RAWBYTES No undecoded data: the device delivers samples.
            b = zeros(1, 0, 'uint8');
        end

        %% ---- both roles -----------------------------------------------------
        function close(obj)
            %CLOSE Output 0 V, device stopped and released. Never throws; a
            %   second close() does nothing. Inside acquire the output stops at
            %   once and acquire ends with tim:instr:closed at its next step.
            if obj.Closed, return; end
            obj.Closed = true;
            obj.OutputArmed = false;
            try
                if obj.Executing, obj.haltOutput(); obj.finishOutput(); end
                obj.Planning = false; obj.Executing = false; obj.Recording = false;
                obj.writeZero();
                obj.device('release');
            catch err
                warning('tim:simcombined:close', 'Simulated device: close: %s', err.message);
            end
        end

        function delete(obj)
            % output 0 V and released (as close)
            try, obj.close(); catch, end
        end

        function id = identity(obj)
            %IDENTITY vendor, model, serial, firmware, raw; no I/O.
            id = struct('vendor', 'tubebench (simulation)', 'model', 'SIM-1AO-4AI', ...
                'serial', char(string(obj.Settings.serial)), 'firmware', '1.0', 'raw', '');
            id.raw = sprintf('%s  s/n %s  firmware %s (simulation)', id.model, id.serial, id.firmware);
        end

        function md = metadata(obj)
            %METADATA Contract fields, the role settings and the input settings.
            d = tim.sim.SimulatedCombined.describe();
            id = obj.identity();
            md = struct('driver', d.name, 'displayName', d.displayName, 'roles', {obj.rolesInUse()}, ...
                'identity', id, 'sharedClock', true, 'settings', obj.Settings, ...
                'maxVpp', obj.MaxVpp, 'load', obj.Load, 'model', id.model, 'serial', id.serial, ...
                'firmware', id.firmware, 'sampleRate', obj.SampleRate, 'range', obj.Range, 'filter', obj.Filter, ...
                'ccld', obj.Ccld, 'teds', {obj.Teds});
        end
    end

    %% ---- contract: class-level members ----------------------------------
    methods (Static)
        function d = describe()
            d = struct('name', 'simcombined', ...
                'displayName', 'Simulated combined device (1 output + 4 inputs, one clock)', ...
                'labels', struct('source', 'Output', 'acquisition', 'Inputs'), ...
                'defaults', struct( ...
                    'settings', struct('blockSamples', 2048, 'serial', 'SIM-0001', 'seed', 11), ...
                    'acquisition', struct('sampleRate', 16384, 'range', '10 Vpeak', 'filter', '0.7 Hz', ...
                        'ccld', true(1, 4))), ...
                'texts', struct('settle', ''), ...
                'simulation', 'only');
        end

        function c = capabilities()
            src = struct('waveforms', {{'sine', 'sweep', 'noise'}}, 'sweepSpacing', {{'LOG', 'LIN'}}, ...
                'frequencyRange', [1 Inf], 'bandFraction', 0.45, 'loads', {{'INF'}}, ...
                'maxVpp', 10, 'minVpp', 0.001, 'sweepTime', [0.1 300], 'noiseCrest', 3.3, ...
                'outputImpedance_ohm', 0, 'trigger', 'clock', 'readback', 'device', 'levelKnown', true);
            acq = struct('channels', 4, 'simultaneous', true, 'sampleRates', [4096 8192 16384 32768 65536], ...
                'sampleRateRange', [], 'bandFraction', 0.45, 'ranges', {{'10 Vpeak'}}, 'filters', {{'0.7 Hz'}}, ...
                'ccld', true, 'teds', false, 'dataUnit', 'V', 'mode', 'block', 'needsOwnSource', true);
            c = struct('roles', {{'source', 'acquisition'}}, 'sharedClock', true, 'rolesTogether', true, ...
                'products', struct('name', {}, 'feature', {}), 'source', src, 'acquisition', acq);
        end

        function s = connectionSteps()
            s = struct('key', {'device', 'setup'}, ...
                'label', {'Simulated device (output + 4 inputs)', 'Channel setup'}, ...
                'role', {'both', 'acquisition'}, 'phase', {'connect', 'prepare'});
        end

        function report = checkConfig(cfg)
            %CHECKCONFIG Device settings (daq.simcombined) and the generic
            %   source and acquisition limits.
            d = tim.sim.SimulatedCombined.describe();
            c = tim.sim.SimulatedCombined.capabilities();
            st = tim.instr.Instrument.settingsFrom(cfg, 'daq', d.name, d.defaults.settings);
            b = st.blockSamples;
            if ~(isscalar(b) && b >= 64 && b <= 65536 && b == round(b))
                error('tim:config:blockSamples', 'Block size (daq.%s.blockSamples) must be an integer 64 .. 65536.', d.name);
            end
            report = [tim.instr.SignalSource.checkSourceConfig(cfg, c, d.displayName), ...
                tim.instr.Acquisition.checkAcquisitionConfig(cfg, c, d)];
        end

        function obj = fromConfig(cfg, ctx)
            %FROMCONFIG The device on ctx.rig (both roles, simulation only), output
            %   0 V. Reports the checklist step 'device'.
            if ~strcmp(ctx.mode, 'simulation')
                error('tim:instr:simulationOnly', 'The simulated combined device exists only in simulation mode.');
            end
            if ~all(ismember({'source', 'acquisition'}, ctx.roles))
                error('tim:instr:role', 'The simulated combined device takes both roles (generator.driver and daq.driver).');
            end
            tim.instr.Instrument.reportStep(ctx, 'device', 'run', 'simulated device on the virtual tube');
            rig = ctx.rig;
            if isempty(rig), rig = tim.sim.SimulatedRig(cfg); end
            obj = tim.sim.SimulatedCombined(rig, ctx.settings, cfg.generator.maxVpp, cfg.generator.load, ...
                cfg.acquisition.sampleRate);
            obj.Roles = ctx.roles;
            tim.instr.Instrument.reportStep(ctx, 'device', 'ok', sprintf('%s – output 0 V', obj.identity().raw));
        end

        function h = testHooks(obj)
            %TESTHOOKS Handles into the simulated device (contract tests).
            if ~isa(obj, 'tim.sim.SimulatedCombined')
                error('tim:instr:noHooks', 'Test hooks need the simulated combined device.');
            end
            h = struct();
            h.traffic = @() obj.Log;
            h.breakLink = @() obj.setFault('broken', true);
            h.outputOn = @() obj.DeviceOn;
            h.levelHistory = @() obj.LevelLog;
            h.forceOutputOn = @() obj.forceOn();
            h.injectError = @() obj.setFault('error', 'E-101 simulated device fault');
            h.stallAfter = @(n) obj.setFault('stallAfter', n);
            h.injectChannelFault = @(c) obj.setFault('channels', c);
            h.isRecording = @() obj.Recording;
            h.outputLog = @() obj.Rig.OutputLog;
            h.playedSignal = @() obj.Played;
        end
    end

    methods (Access = private)
        function s = sourceState(obj)
            % configured source state at the start of a plan (output off)
            s = struct('mode', obj.Mode, 'level', obj.Level, 'f', obj.Frequency, 'sweep', obj.Sweep, ...
                'on', false, 'sweepStart', NaN, 'fadeStart', NaN, 'phase', 0, 'halted', false);
        end

        function p = planOrConfig(obj)
            % the source state that a call refers to: planned while planning
            if obj.Planning || obj.Executing
                p = obj.Plan;
            else
                p = obj.sourceState();
            end
        end

        function configure(obj, cfgState, op)
            % configure*: outside acquire the next plan's initial state,
            % in the planning pass a scheduled change (output off at that sample)
            obj.device(op);
            obj.LevelLog(end+1) = cfgState.level;
            if obj.Planning
                obj.schedule('config', cfgState);
                obj.Plan.mode = cfgState.mode; obj.Plan.level = cfgState.level;
                obj.Plan.f = cfgState.f; obj.Plan.sweep = cfgState.sweep;
                obj.Plan.on = false; obj.Plan.sweepStart = NaN;
            else
                obj.Mode = cfgState.mode; obj.Level = cfgState.level;
                obj.Frequency = cfgState.f; obj.Sweep = cfgState.sweep;
                obj.writeZero();
            end
        end

        function commitPlan(obj)
            % after a played plan the source keeps its final settings (as an
            % instrument keeps the last frequency of a stepped sine)
            p = obj.Out;
            obj.Mode = p.mode; obj.Level = p.level; obj.Frequency = p.f; obj.Sweep = p.sweep;
        end

        function schedule(obj, type, value)
            % one action of the plan, at the sample count of the running planning call
            obj.Events(end+1) = struct('n', obj.PlanN, 'type', type, 'value', value);
        end

        function x = render(obj, n0, m)
            % output samples n0+1 .. n0+m of the plan (excitation volts, m x 1)
            x = zeros(m, 1);
            i = 0;
            while i < m
                k = n0 + i;                            % samples before this one
                while obj.Next <= numel(obj.Events) && obj.Events(obj.Next).n <= k
                    obj.apply(obj.Events(obj.Next), k - n0);
                    obj.Next = obj.Next + 1;
                end
                nextN = Inf;
                if obj.Next <= numel(obj.Events), nextN = obj.Events(obj.Next).n; end
                seg = min(m - i, nextN - k);
                x(i + 1:i + seg) = obj.synthesize(k, seg);
                i = i + seg;
            end
            if ~isempty(x), obj.DeviceOn = obj.Out.on && ~obj.Out.halted; end
        end

        function apply(obj, ev, offset)
            % one planned action takes effect (offset: its sample within the block)
            o = obj.Out;
            switch ev.type
                case 'on'
                    if ~o.halted, o.on = true; o.fadeStart = NaN; end
                case 'off'
                    if o.on, o.on = false; o.fadeStart = ev.n; end
                case 'freq'
                    o.f = ev.value;
                case 'trigger'
                    o.sweepStart = ev.n;
                    obj.Rig.markTrigger(obj.Rig.SampleCounter + offset);   % sweep start on the rig timeline
                case 'config'
                    if o.on, o.on = false; o.fadeStart = ev.n; end
                    o.mode = ev.value.mode; o.level = ev.value.level; o.f = ev.value.f; o.sweep = ev.value.sweep;
                    o.sweepStart = NaN;
            end
            obj.Out = o;
        end

        function x = synthesize(obj, k, m)
            % m samples after sample k of the current output state (phase continuous)
            o = obj.Out;
            fadeN = round(obj.FadeTime * obj.SampleRate);
            j = k + (0:m - 1).';                       % sample indices (0-based)
            gain = double(o.on) * ones(m, 1);
            if ~isnan(o.fadeStart)
                t = j - o.fadeStart;
                w = 0.5 * (1 + cos(pi * t / fadeN)); w(t >= fadeN) = 0;
                gain = max(gain, w .* (t >= 0));
                if k + m >= o.fadeStart + fadeN, o.fadeStart = NaN; end
            end
            x = zeros(m, 1);
            if any(gain > 0) && ~strcmp(o.mode, 'none')
                amp = o.level / 2;
                fs = obj.SampleRate;
                switch o.mode
                    case 'noise'
                        x = (o.level / 6.6) * obj.Rng.randn(m, 1);
                    otherwise
                        f = o.f * ones(m, 1);
                        if strcmp(o.mode, 'sweep')
                            f(:) = o.sweep.fStart;
                            if ~isnan(o.sweepStart)
                                t = (j - o.sweepStart) / fs;
                                in = t >= 0 & t < o.sweep.duration;
                                if strcmp(o.sweep.spacing, 'LOG')
                                    f(in) = o.sweep.fStart * (o.sweep.fStop / o.sweep.fStart) .^ (t(in) / o.sweep.duration);
                                else
                                    f(in) = o.sweep.fStart + (o.sweep.fStop - o.sweep.fStart) * t(in) / o.sweep.duration;
                                end
                            end
                        end
                        ph = o.phase + 2 * pi * cumsum(f) / fs;
                        o.phase = mod(ph(end), 2 * pi);
                        x = amp * sin(ph);
                end
            elseif ~strcmp(o.mode, 'none') && ~strcmp(o.mode, 'noise')
                % silent: the phase runs on, so that a later output on is phase continuous
                f = o.f; if strcmp(o.mode, 'sweep'), f = o.sweep.fStart; end
                o.phase = mod(o.phase + 2 * pi * f * m / obj.SampleRate, 2 * pi);
            end
            x = x .* gain;
            obj.Out = o;
        end

        function haltOutput(obj)
            % outputOff while playing: from the next sample a fade to 0 V, then
            % zeros to the end of the acquisition (later planned actions ignored)
            o = obj.Out;
            if o.on || ~isnan(o.fadeStart)
                if o.on, o.fadeStart = obj.Received; end
                o.on = false;
            end
            o.halted = true;
            obj.Out = o;
            obj.DeviceOn = false;
            try, obj.device('output stop'); catch, end
        end

        function finishOutput(obj)
            % end of playing: a running fade (or an output still on) is
            % completed to 0 V after the last recorded sample, then 0 V
            o = obj.Out;
            if isempty(o), return; end
            fadeN = round(obj.FadeTime * obj.SampleRate);
            if o.on && ~o.halted
                o.on = false; o.fadeStart = obj.Received;
                obj.Out = o;
            end
            if ~isnan(obj.Out.fadeStart)
                rest = obj.Out.fadeStart + fadeN - obj.Received;
                if rest > 0
                    x = obj.synthesize(obj.Received, rest);   % played, not recorded
                    obj.Rig.respond(x);
                end
            end
            obj.Out.fadeStart = NaN; obj.Out.on = false;
            obj.DeviceOn = false;
            obj.Rig.respond(zeros(0, 1));                % 0 V
        end

        function writeZero(obj)
            % 0 V on the output (device session stopped)
            obj.DeviceOn = false;
            obj.Rig.respond(zeros(0, 1));
            obj.device('output 0 V');
        end

        function endAcquire(obj)
            % onCleanup of acquire: on an abnormal end AbortFcn first (no device
            % operation before it), then the output to 0 V and the device stopped -
            % unless close() did that already
            obj.Planning = false;
            if ~obj.Done, obj.callAbortFcn(); end
            wasPlaying = obj.Executing;
            obj.Executing = false; obj.Recording = false;
            if ~obj.Done && ~obj.Closed
                try
                    if wasPlaying, obj.finishOutput(); end
                    obj.writeZero();
                    obj.device('stop');
                catch err
                    warning('tim:simcombined:stop', 'Simulated device: stop after an error: %s', err.message);
                end
            end
            obj.DeviceOn = false;
        end

        function device(obj, op)
            % one operation on the device: logged (test hook 'traffic'); a lost
            % link or an injected device error is raised here, before it happens
            if obj.Fault.broken
                error('tim:simcombined:link', 'Simulated device not reachable (%s).', op);
            end
            if ~isempty(obj.Fault.error)
                e = obj.Fault.error; obj.Fault.error = '';
                error('tim:simcombined:device', 'Simulated device error during "%s": %s', op, e);
            end
            obj.Log{end+1} = op;
        end

        function checkLevel(obj, vpp)
            % level limit BEFORE any level is set (contract section 3.4)
            c = tim.sim.SimulatedCombined.capabilities().source;
            if ~(isscalar(vpp) && isnumeric(vpp) && vpp > 0)
                error('tim:gen:amplitude', 'Amplitude must be a positive scalar [Vpp].');
            end
            if vpp > obj.MaxVpp * (1 + 1e-9)
                error('tim:gen:amplitude', 'Requested %.4g Vpp exceeds the configured safety limit MaxVpp = %.4g Vpp.', ...
                    vpp, obj.MaxVpp);
            end
            if vpp > c.maxVpp(1) || vpp < c.minVpp(1)
                error('tim:gen:amplitude', 'Requested %.4g Vpp outside the output range %.3g .. %.3g Vpp.', ...
                    vpp, c.minVpp(1), c.maxVpp(1));
            end
        end

        function checkFrequency(obj, f, id)
            % frequencies up to the band of the shared clock (bandFraction x sample rate)
            c = tim.sim.SimulatedCombined.capabilities().source;
            fs = obj.SampleRate; if isnan(fs), fs = obj.ClockRate; end
            if isnan(fs)
                error('tim:gen:mode', 'No sample rate known yet: prepare the inputs first.');
            end
            fMax = c.bandFraction * fs;
            if any(~(f >= c.frequencyRange(1) & f <= fMax))
                error(id, 'Frequency %s Hz outside %g .. %.0f Hz (%.2g x sample rate %g S/s).', mat2str(f), ...
                    c.frequencyRange(1), fMax, c.bandFraction, fs);
            end
        end

        function assertOpen(obj, action)
            % after close() nothing is done any more
            if obj.Closed
                error('tim:instr:closed', 'Simulated device closed: %s refused (connect again).', action);
            end
        end

        function assertNotPlaying(obj, action)
            % levels, frequencies and triggers are planned, not changed while playing
            if obj.Executing
                error('tim:gen:schedule', '%s refused while the planned output plays.', action);
            end
        end

        function progress(obj, key, state, detail)
            if ~isempty(obj.ProgressFcn)
                try, obj.ProgressFcn(key, state, detail); catch, end
            end
        end

        function setFault(obj, name, value)
            % test hooks: fault injection
            obj.Fault.(name) = value;
        end

        function forceOn(obj)
            % test hook: the output started behind the driver's back
            obj.DeviceOn = true;
        end
    end
end
