classdef TemplateCombined < tim.instr.SignalSource & tim.instr.Acquisition
    %TEMPLATECOMBINED TEMPLATE of a combined driver: one output and four inputs on one clock.
    %
    %   THIS IS A TEMPLATE. Copy it, do not use it in place
    %   (docs/adding_an_instrument.md, steps 3 and 4):
    %     copy to +tim/+instr/<Name>.m, then replace, case-sensitive,
    %     'TemplateCombined' -> '<Name>', 'TEMPLATECOMBINED' -> '<NAME>' and
    %     'templatecombined' -> '<registry name>' (also in the copies of
    %     MockTemplateCombined.m and TestTemplateCombined.m).
    %   For a device that is generator AND acquisition (a DAQ card with an
    %   analog output, an audio interface): output and inputs on one sample
    %   clock, data recorded in blocks. As it stands it is a complete driver of
    %   an imaginary device that runs on its protocol mock (MockTemplateCombined)
    %   and passes tests/TestInstrumentContract (tests/TestInstrumentTemplates
    %   runs it). Every line marked TODO holds a DEVICE FACT: replace it with
    %   what YOUR device's manual and its MATLAB interface say, and enter the
    %   source in docs/ref_<instrument>.md. When you are done, replace this
    %   paragraph and the TODO line at the end of this help by a description of
    %   your driver: "TODO" must not occur in the file any more.
    %   The planning engine (acquire, render, apply, synthesize, haltOutput,
    %   finishOutput, endAcquire) is that of tim.sim.SimulatedCombined, with the
    %   virtual tube replaced by the device session; it needs no change.
    %
    %   Selected for BOTH roles: generator.driver = daq.driver = 'templatecombined';
    %   its settings are daq.templatecombined. The session then holds one object
    %   as s.Gen and s.Daq.
    %
    %   THE DEVICE SESSION. The driver talks to its device through one object,
    %   obj.Dev (hardware: a thin class around the vendor interface that you
    %   write, e.g. +tim/+instr/<Name>Session.m; simulation: the protocol mock,
    %   which has the same methods):
    %     id = Dev.identify()          vendor, model, serial, firmware, raw
    %     fs = Dev.configure(c)        inputs and the output channel; returns the
    %                                  rate the device REALLY runs at
    %     Dev.writeZero()              output at 0 V now, device idle
    %     Dev.start()                  start playing and recording
    %     [y, st] = Dev.playRecord(x)  play x (m x 1 volts) and return the m x C
    %                                  input volts recorded at the same samples;
    %                                  st.fault, st.overload: 1 x C logical
    %     Dev.stop()                   stop playing and recording
    %     Dev.close()                  release the device
    %     Dev.setTimeout(t)            I/O time-out [s]
    %   Examples of the hardware side (check every call in the vendor's and
    %   MathWorks' documentation): an audio interface through the Audio
    %   Toolbox - audioPlayerRecorder, one call per frame plays and records
    %   (ASIO driver on Windows; full-scale units: section 3.4 and 4.2 of the
    %   contract); an NI device through the Data Acquisition Toolbox - one
    %   DataAcquisition with an analog output and four inputs, the output
    %   preloaded / queued block by block. A sample-producing output can keep
    %   its last value after a stop: write 0 V (contract section 3.1).
    %
    %   TIMING (contract section 8.3). acquire(n, onBlock) first runs a PLANNING
    %   PASS: onBlock(B), onBlock(2B), ... up to n without waiting (B =
    %   settings.blockSamples), isPlanning() is true, and every source call made
    %   meanwhile is scheduled sample-exactly on the device timeline. An error
    %   out of onBlock (e.g. a Stop) discards the plan: nothing is played. Then
    %   the EXECUTION plays the plan block by block while recording and calls
    %   onBlock(nDone) again from the first block; a level, frequency, trigger
    %   or outputOn call then raises tim:gen:schedule, and outputOff stops the
    %   output at once (5 ms fade to 0 V, then zeros).
    %   OUTPUT OFF = 0 V: written on creation, by outputOff, close and delete,
    %   and every plan or abnormal end finishes with a fade to 0 V.
    %   TODO one line: the device (vendor, model), its interface and the manual.

    properties (SetAccess = private)
        Dev                          % device session (hardware class) or MockTemplateCombined
        Identity struct = struct()   % vendor, model, serial, firmware, raw (Dev.identify)
        Settings struct = struct()   % driver settings (daq.templatecombined) from fromConfig
        MaxVpp double = 0.5          % generator.maxVpp (fixed at creation)
        Load char = 'INF'
        Mode char = 'none'           % configured waveform: 'none' | 'sine' | 'sweep' | 'noise'
        Level double = NaN           % configured level [Vpp]
        Frequency double = NaN       % sine frequency [Hz]
        Sweep struct = struct()      % configured sweep (fStart, fStop, duration, spacing)
        Range char = ''              % input range after prepare
        Filter char = ''
        Ccld logical = true(1, 4)
        LevelLog double = zeros(1, 0)   % every level configured [Vpp] (test hook levelHistory)
        Played double = zeros(0, 1)     % output samples of the last acquisition [V]
    end
    properties (Access = private)
        ClockRate double = NaN       % acquisition.sampleRate captured at creation (before prepare)
        Prepared logical = false
        Closed logical = false
        Planning logical = false
        Executing logical = false
        Recording logical = false    % Dev.start done, Dev.stop not yet
        Done logical = false         % acquire reached its normal end (no abort)
        PlanN double = 0             % sample count of the running planning call
        Plan struct                  % source state while the plan is built
        Events struct = struct('n', {}, 'type', {}, 'value', {})   % the plan
        Next double = 1              % next event to apply while playing
        Out struct                   % output state while playing
        Data double = zeros(0, 4)
        Received double = 0
        DeviceOn logical = false     % the output produces a signal (device session state)
        Faults cell = {}             % 1 x C: device-reported faults (words) of the last acquisition
        Rng
    end
    properties (Constant)
        FadeTime = 5e-3              % s, raised-cosine fade to 0 V
    end

    methods
        function obj = TemplateCombined(dev, settings, maxVpp, load, sampleRate)
            %TEMPLATECOMBINED Driver on an open device session (tim.instr.create builds it through fromConfig).
            obj.Dev = dev;
            obj.Settings = settings;
            obj.MaxVpp = maxVpp;
            obj.Load = char(load);
            obj.ClockRate = sampleRate;
            obj.Rng = RandStream('mt19937ar', 'Seed', 11);   % noise output: reproducible
            obj.Plan = obj.sourceState();
            obj.writeZero();                                  % output 0 V before anything else
            obj.Identity = dev.identify();
        end

        %% ---- signal source ------------------------------------------------
        function configureSine(obj, f, vpp)
            %CONFIGURESINE Continuous sine f [Hz], vpp [Vpp]; output off.
            obj.assertOpen('configureSine');
            obj.assertNotPlaying('configureSine');
            obj.checkLevel(vpp);
            obj.checkFrequency(f, 'tim:gen:unsupported');
            obj.configure(struct('mode', 'sine', 'level', vpp, 'f', f, 'sweep', struct()));
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
                obj.Frequency = f;
            end
        end

        function configureSweep(obj, s)
            %CONFIGURESWEEP Single swept sine s.fStart, s.fStop [Hz], s.duration [s],
            %   s.spacing 'LOG'|'LIN', s.amplitudeVpp; started by triggerSweep.
            obj.assertOpen('configureSweep');
            obj.assertNotPlaying('configureSweep');
            obj.checkLevel(s.amplitudeVpp);
            c = tim.instr.TemplateCombined.capabilities();
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
                error('tim:gen:sweep', 'Sweep spacing must be %s.', strjoin(c.source.sweepSpacing, ' or '));
            end
            sw = struct('fStart', s.fStart, 'fStop', s.fStop, 'duration', s.duration, 'spacing', spacing);
            obj.configure(struct('mode', 'sweep', 'level', s.amplitudeVpp, 'f', s.fStart, 'sweep', sw));
        end

        function configureNoise(obj, vpp)
            %CONFIGURENOISE Gaussian noise, rms = vpp / 6.6; output off.
            obj.assertOpen('configureNoise');
            obj.assertNotPlaying('configureNoise');
            obj.checkLevel(vpp);
            obj.configure(struct('mode', 'noise', 'level', vpp, 'f', NaN, 'sweep', struct()));
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
            obj.checkLevel(p.level);                          % re-checked right before enabling
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
            %   before the sweep has ended).
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
            %PREPARE Channel setup: exactly c.sampleRate, c.range, c.filter, c.ccld;
            %   reports the checklist step 'setup'.
            obj.assertOpen('prepare');
            q = tim.instr.TemplateCombined.capabilities().acquisition;
            if ~any(strcmp(c.range, q.ranges))
                error('tim:templatecombined:range', 'Input range "%s" not supported (supported: %s).', ...
                    c.range, strjoin(q.ranges, ', '));
            end
            if ~any(strcmp(c.filter, q.filters))
                error('tim:templatecombined:filter', 'High-pass filter "%s" not supported (supported: %s).', ...
                    c.filter, strjoin(q.filters, ', '));
            end
            ccld = true(1, numel(c.channels));
            if isfield(c, 'ccld') && ~isempty(c.ccld), ccld = logical(c.ccld(:).'); end
            if any(ccld) && ~q.ccld
                error('tim:templatecombined:ccld', 'This device has no IEPE supply: set acquisition.ccld false.');
            end
            txt = sprintf('%g S/s, %s, high-pass %s', c.sampleRate, c.range, c.filter);
            obj.progress('setup', 'run', txt);
            fs = obj.Dev.configure(struct('sampleRate', c.sampleRate, 'channels', c.channels, ...
                'range', c.range, 'filter', c.filter, 'ccld', ccld));
            if abs(fs - c.sampleRate) > 1e-9 * c.sampleRate
                error('tim:templatecombined:rate', 'Sample rate %g S/s not possible: the device would run at %g S/s.', ...
                    c.sampleRate, fs);
            end
            obj.SampleRate = c.sampleRate;
            obj.Range = c.range; obj.Filter = c.filter; obj.Ccld = ccld;
            obj.Teds = {};                                    % TODO TEDS: 1 x C cell of [] or struct; {} = not read
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
                error('tim:templatecombined:state', 'acquire needs the channel setup (prepare) first.');
            end
            B = obj.Settings.blockSamples;
            marks = unique([B:B:nSamples, nSamples]);
            nCh = numel(obj.Ccld);
            obj.Done = false; obj.Data = zeros(nSamples, nCh); obj.Received = 0;
            obj.Played = zeros(nSamples, 1);
            obj.Faults = repmat({{}}, 1, nCh);
            cleanup = onCleanup(@() obj.endAcquire());
            % ---- planning pass: the schedule on the device timeline, nothing played
            obj.Events = obj.Events([]);
            obj.Plan = obj.sourceState();
            obj.Planning = true;
            for n = marks
                obj.PlanN = n;
                if ~isempty(onBlock), onBlock(n); end
                obj.assertOpen('acquire');                    % close() from inside onBlock
            end
            obj.Planning = false;
            % ---- execution: play the plan and record
            obj.Out = obj.sourceState();
            obj.Next = 1;
            obj.Dev.start();
            obj.Recording = true; obj.Executing = true;
            t0 = tic; n0 = 0;
            for n = marks
                obj.assertOpen('acquire');
                x = obj.render(n0, n - n0);
                obj.Played(n0 + 1:n) = x;
                [y, st] = obj.Dev.playRecord(x);              % play this block, record the same samples
                obj.Data(n0 + 1:n, :) = y;
                obj.noteFaults(st);
                obj.Received = n; n0 = n;
                if ~isempty(onBlock), onBlock(n); end
                obj.assertOpen('acquire');                    % close() from inside onBlock
                if toc(t0) > timeout
                    error('tim:templatecombined:timeout', 'Acquisition time-out (%d of %d samples).', n, nSamples);
                end
            end
            obj.Executing = false;
            obj.finishOutput();                               % fade to 0 V, zeros
            obj.stopDevice();
            obj.commitPlan();
            obj.Done = true;
            [data, info] = obj.collect(nSamples);
            clear cleanup
        end

        function [data, info] = collect(obj, nSamples)
            %COLLECT Data recorded so far (volts) and the integrity report; no I/O.
            data = obj.Data(1:obj.Received, :);
            if nargin >= 2 && size(data, 1) > nSamples, data = data(1:nSamples, :); end
            info = struct('fs', obj.SampleRate, 'dataUnit', 'V', 'blockSamples', obj.Settings.blockSamples);
            fullScale = sscanf(obj.Range, '%f');              % TODO input range in volts (peak)
            if isempty(fullScale), fullScale = NaN; end
            g = tim.acq.basicIntegrity(data, obj.SampleRate, obj.SampleRate, fullScale);
            for c = 1:min(numel(obj.Faults), numel(g.channelFaults))
                if isempty(obj.Faults{c}), continue; end
                g.channelFaults{c} = [g.channelFaults{c}, obj.Faults{c}];
                g.fatal{end+1} = sprintf('Input %d: %s.', c, strjoin(obj.Faults{c}, ', '));
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
            %RAWBYTES No undecoded data: the device session delivers volts.
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
                obj.Planning = false; obj.Executing = false;
                obj.writeZero();
            catch err
                warning('tim:templatecombined:close', 'Device: close: %s', err.message);
            end
            obj.stopDevice();
            try, obj.Dev.close(); catch, end
        end

        function delete(obj)
            % output 0 V and released (as close)
            try, obj.close(); catch, end
        end

        function setTimeout(obj, t)
            %SETTIMEOUT Shorten the I/O time-out [s] (closing the window).
            try, obj.Dev.setTimeout(t); catch, end
        end

        function id = identity(obj)
            %IDENTITY vendor, model, serial, firmware, raw (Dev.identify); no I/O.
            id = tim.instr.Instrument.emptyIdentity();
            f = fieldnames(id);
            for i = 1:numel(f)
                if isfield(obj.Identity, f{i}), id.(f{i}) = char(string(obj.Identity.(f{i}))); end
            end
        end

        function md = metadata(obj)
            %METADATA Contract fields, the role settings and the input settings.
            d = tim.instr.TemplateCombined.describe();
            id = obj.identity();
            md = struct('driver', d.name, 'displayName', d.displayName, 'roles', {obj.rolesInUse()}, ...
                'identity', id, 'sharedClock', true, 'settings', obj.Settings, ...
                'maxVpp', obj.MaxVpp, 'load', obj.Load, 'model', id.model, 'serial', id.serial, ...
                'firmware', id.firmware, 'sampleRate', obj.SampleRate, 'range', obj.Range, 'filter', obj.Filter, ...
                'ccld', obj.Ccld, 'teds', {obj.Teds});
        end
    end

    %% ---- contract: class-level members (no I/O) -------------------------------
    methods (Static)
        function d = describe()
            d = struct('name', 'templatecombined', ...                     % registry name = generator.driver = daq.driver
                'displayName', 'Template device (1 output + 4 inputs, one clock)', ...   % TODO vendor, model and kind
                'labels', struct('source', 'Output', 'acquisition', 'Inputs'), ...
                'defaults', struct( ...
                    'settings', struct( ...                                 % daq.templatecombined
                        'address', 'Dev1', ...                              % TODO what selects the device
                        'timeout', 5, ...                                   % I/O time-out [s]
                        'blockSamples', 2048), ...                          % TODO samples per block (device buffer)
                    'acquisition', struct('sampleRate', 16384, ...          % TODO defaults of acquisition.*
                        'range', '5 Vpeak', 'filter', 'AC 0.5 Hz', 'ccld', true(1, 4))), ...
                'texts', struct('settle', 'IEPE + %s coupling', ...         % TODO what settles after prepare ('' = nothing)
                    'noun', 'DAQ device', 'closed', 'stopped, output at 0 V'), ...
                'simulation', 'protocol');
        end

        function c = capabilities()
            % TODO every value from the manual (section / page in docs/ref_<instrument>.md)
            src = struct('waveforms', {{'sine', 'sweep', 'noise'}}, ...    % synthesised by this driver
                'sweepSpacing', {{'LOG', 'LIN'}}, ...
                'frequencyRange', [1 Inf], ...                              % limited by the sample rate:
                'bandFraction', 0.45, ...                                   % TODO highest frequency / sample rate (output filter)
                'loads', {{'INF'}}, ...                                     % programmed = open-circuit volts
                'maxVpp', 10, ...                                           % TODO output range [Vpp] (+-5 V: 10 Vpp)
                'minVpp', 0.001, ...                                        % TODO smallest meaningful level [Vpp]
                'sweepTime', [0.1 300], ...                                 % TODO [s] (memory / block count)
                'noiseCrest', 3.3, ...
                'outputImpedance_ohm', 0, ...                               % TODO source impedance [ohm] (an AO: about 0)
                'trigger', 'clock', ...                                     % sweep starts sample-exactly on the shared clock
                'readback', 'device', ...                                   % state of the device session
                'levelKnown', true);                                        % TODO false for full-scale units (audio): vppAtFullScale
            acq = struct('channels', 4, ...                                 % TODO analog inputs (>= 4)
                'simultaneous', true, ...                                   % TODO must be true
                'sampleRates', [8192 16384 32768], ...                      % TODO rates it runs EXACTLY, or [] and:
                'sampleRateRange', [], ...
                'bandFraction', 0.45, ...                                   % TODO usable band / sample rate
                'ranges', {{'5 Vpeak'}}, ...                                % TODO
                'filters', {{'AC 0.5 Hz'}}, ...                             % TODO
                'ccld', true, ...                                           % TODO switchable IEPE supply
                'teds', false, ...                                          % TODO
                'dataUnit', 'V', ...                                        % TODO 'FS' for an unknown input scale (audio)
                'mode', 'block', ...                                        % recorded in blocks
                'needsOwnSource', true);                                    % only together with its own output
            c = struct('roles', {{'source', 'acquisition'}}, 'sharedClock', true, 'rolesTogether', true, ...
                'products', struct('name', {}, 'feature', {}), ...          % TODO e.g. Data Acquisition Toolbox / Audio Toolbox
                'source', src, 'acquisition', acq);
        end

        function s = connectionSteps()
            s = struct('key', {'templatecombined', 'setup'}, ...
                'label', {'Template device (output + 4 inputs)', 'Channel setup'}, ...   % TODO checklist texts
                'role', {'both', 'acquisition'}, 'phase', {'connect', 'prepare'});
        end

        function report = checkConfig(cfg)
            %CHECKCONFIG Device settings (daq.templatecombined) and the generic
            %   source and acquisition limits.
            d = tim.instr.TemplateCombined.describe();
            c = tim.instr.TemplateCombined.capabilities();
            st = tim.instr.Instrument.settingsFrom(cfg, 'daq', d.name, d.defaults.settings);
            if ~(ischar(st.address) || isstring(st.address)) || isempty(strtrim(char(st.address)))
                error('tim:config:address', 'Device address (daq.%s.address) is empty.', d.name);
            end
            if ~(isscalar(st.timeout) && st.timeout > 0)
                error('tim:config:timeout', 'Device time-out (daq.%s.timeout) must be greater than 0 s.', d.name);
            end
            b = st.blockSamples;
            if ~(isscalar(b) && b >= 64 && b <= 65536 && b == round(b))
                error('tim:config:blockSamples', 'Block size (daq.%s.blockSamples) must be an integer 64 .. 65536.', d.name);
            end
            report = [tim.instr.SignalSource.checkSourceConfig(cfg, c, d.displayName), ...
                tim.instr.Acquisition.checkAcquisitionConfig(cfg, c, d)];
        end

        function obj = fromConfig(cfg, ctx)
            %FROMCONFIG Open the device (hardware: the device session; simulation:
            %   the mock on ctx.rig) for both roles, output 0 V, identify.
            if ~all(ismember({'source', 'acquisition'}, ctx.roles))
                error('tim:instr:role', 'The %s takes both roles (generator.driver and daq.driver).', ...
                    tim.instr.TemplateCombined.describe().displayName);
            end
            st = ctx.settings;
            sim = strcmp(ctx.mode, 'simulation');
            if sim
                detail = 'simulated device';
            else
                detail = sprintf('%s', st.address);           % TODO interface text
            end
            tim.instr.Instrument.reportStep(ctx, 'templatecombined', 'run', detail);
            if sim
                dev = tim.instr.MockTemplateCombined(ctx.rig);
            else
                error('tim:templatecombined:hardware', ...     % TODO open the device session class you wrote, e.g.
                    'The template has no hardware session.');  % dev = tim.instr.<Name>Session(st.address, st.timeout);
            end
            try
                obj = tim.instr.TemplateCombined(dev, st, cfg.generator.maxVpp, cfg.generator.load, cfg.acquisition.sampleRate);
            catch err
                try, dev.close(); catch, end
                rethrow(err);
            end
            obj.Roles = ctx.roles;
            tim.instr.Instrument.reportStep(ctx, 'templatecombined', 'ok', sprintf('%s – output 0 V', obj.identity().raw));
        end

        function h = testHooks(obj)
            %TESTHOOKS Simulation only: handles into the protocol mock (contract tests).
            dev = obj.Dev;
            if ~isa(dev, 'tim.instr.MockTemplateCombined')
                error('tim:instr:noHooks', 'Test hooks need the driver on its mock (simulation).');
            end
            h = struct();
            h.traffic = @() dev.Log;
            h.breakLink = @() dev.fault('broken');
            h.outputOn = @() dev.Playing;
            h.levelHistory = @() obj.LevelLog;
            h.forceOutputOn = @() dev.fault('forceOn');
            h.injectError = @() dev.fault('error');
            h.stallAfter = @(n) dev.fault('stallAfter', n);
            h.injectChannelFault = @(c) dev.fault('channel', c);
            h.isRecording = @() dev.Running;
            h.outputLog = @() dev.Rig.OutputLog;
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

        function configure(obj, cfgState)
            % configure*: outside acquire the next plan's initial state (output
            % 0 V), in the planning pass a scheduled change (output off at that sample)
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
            % after a played plan the source keeps its final settings
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
                k = n0 + i;                                   % samples before this one
                while obj.Next <= numel(obj.Events) && obj.Events(obj.Next).n <= k
                    obj.apply(obj.Events(obj.Next));
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

        function apply(obj, ev)
            % one planned action takes effect
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
            j = k + (0:m - 1).';                              % sample indices (0-based)
            gain = double(o.on) * ones(m, 1);
            if ~isnan(o.fadeStart)
                t = j - o.fadeStart;
                w = 0.5 * (1 + cos(pi * t / fadeN)); w(t >= fadeN) = 0;
                gain = max(gain, w .* (t >= 0));
                if k + m >= o.fadeStart + fadeN, o.fadeStart = NaN; end
            end
            x = zeros(m, 1);
            if any(gain > 0) && ~strcmp(o.mode, 'none')
                amp = o.level / 2;                            % TODO full-scale units: amp / vppAtFullScale * 2
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
        end

        function finishOutput(obj)
            % end of playing: a running fade (or an output still on) is
            % completed to 0 V after the last recorded sample, then 0 V
            o = obj.Out;
            if isempty(o) || ~isfield(o, 'on'), return; end
            fadeN = round(obj.FadeTime * obj.SampleRate);
            if o.on && ~o.halted
                o.on = false; o.fadeStart = obj.Received;
                obj.Out = o;
            end
            if ~isnan(obj.Out.fadeStart)
                rest = obj.Out.fadeStart + fadeN - obj.Received;
                if rest > 0
                    x = obj.synthesize(obj.Received, rest);    % played, not recorded
                    obj.Dev.playRecord(x);
                end
            end
            obj.Out.fadeStart = NaN; obj.Out.on = false;
            obj.writeZero();
        end

        function writeZero(obj)
            % 0 V on the output (device idle)
            obj.DeviceOn = false;
            obj.Dev.writeZero();
        end

        function stopDevice(obj)
            % stop playing and recording; never throws (a failure is a warning)
            if ~obj.Recording, return; end
            obj.Recording = false;
            try
                obj.Dev.stop();
            catch err
                warning('tim:templatecombined:stop', 'Could not stop the device: %s', err.message);
            end
        end

        function endAcquire(obj)
            % onCleanup of acquire: on an abnormal end AbortFcn first (no device
            % operation before it), then the output to 0 V and the device stopped -
            % unless close() did that already
            obj.Planning = false;
            if ~obj.Done, obj.callAbortFcn(); end
            wasPlaying = obj.Executing;
            obj.Executing = false;
            if ~obj.Done && ~obj.Closed
                try
                    if wasPlaying, obj.finishOutput(); end
                    obj.writeZero();
                catch err
                    warning('tim:templatecombined:stop', 'Device: output to 0 V after an error: %s', err.message);
                end
                obj.stopDevice();
            end
            obj.DeviceOn = false;
        end

        function noteFaults(obj, st)
            % device flags of this block -> words per channel (TODO the device's flags)
            for c = find(st.fault(:).')
                obj.addFault(c, 'input fault reported by the device (open circuit or IEPE supply)');
            end
            for c = find(st.overload(:).')
                obj.addFault(c, 'overload reported by the device');
            end
        end

        function addFault(obj, c, words)
            if ~any(strcmp(obj.Faults{c}, words)), obj.Faults{c}{end+1} = words; end
        end

        function checkLevel(obj, vpp)
            % level limit BEFORE any level is set (contract section 3.4)
            c = tim.instr.TemplateCombined.capabilities().source;
            if ~(isscalar(vpp) && isnumeric(vpp) && isfinite(vpp) && vpp > 0)
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
            c = tim.instr.TemplateCombined.capabilities().source;
            fs = obj.SampleRate; if isnan(fs), fs = obj.ClockRate; end
            if isnan(fs)
                error('tim:gen:mode', 'No sample rate known yet: prepare the inputs first.');
            end
            fMax = min(c.bandFraction * fs, c.frequencyRange(2));
            if any(~(f >= c.frequencyRange(1) & f <= fMax))
                error(id, 'Frequency %s Hz outside %g .. %.0f Hz (%.2g x sample rate %g S/s).', mat2str(f), ...
                    c.frequencyRange(1), fMax, c.bandFraction, fs);
            end
        end

        function assertOpen(obj, action)
            % after close() nothing is done any more
            if obj.Closed
                error('tim:instr:closed', 'Device driver closed: %s refused (connect again).', action);
            end
        end

        function assertNotPlaying(obj, action)
            % levels, frequencies and triggers are planned, not changed while playing
            if obj.Executing
                error('tim:gen:schedule', '%s refused while the planned output plays.', action);
            end
        end

        function progress(obj, key, state, detail)
            % checklist step of prepare (a failing callback does not stop the setup)
            if ~isempty(obj.ProgressFcn)
                try, obj.ProgressFcn(key, state, detail); catch, end
            end
        end
    end
end
