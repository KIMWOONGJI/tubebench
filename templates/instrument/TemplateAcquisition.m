classdef TemplateAcquisition < tim.instr.Acquisition
    %TEMPLATEACQUISITION TEMPLATE of an acquisition driver (data arrive while it records).
    %
    %   THIS IS A TEMPLATE. Copy it, do not use it in place
    %   (docs/adding_an_instrument.md, steps 3 and 4):
    %     copy to +tim/+instr/<Name>.m, then replace, case-sensitive,
    %     'TemplateAcquisition' -> '<Name>', 'TEMPLATEACQUISITION' -> '<NAME>'
    %     and 'templateacquisition' -> '<registry name>' (also in the copies
    %     of MockTemplateAcquisition.m and TestTemplateAcquisition.m).
    %   As it stands it is a complete driver of an imaginary 4-input DAQ that
    %   runs on its protocol mock (MockTemplateAcquisition) and passes
    %   tests/TestInstrumentContract (tests/TestInstrumentTemplates runs it).
    %   Every line marked TODO holds an INSTRUMENT FACT: replace it with what
    %   YOUR device's manual and its MATLAB interface say, and enter the source
    %   in docs/ref_<instrument>.md. When you are done, replace this paragraph
    %   and the TODO line at the end of this help by a description of your
    %   driver: "TODO" must not occur in the file any more.
    %
    %   acq = tim.instr.create('acquisition', cfg, ctx, src)   % registry (driver 'templateacquisition')
    %
    %   THE DEVICE SESSION. The driver talks to its device through one object,
    %   obj.Dev, with these methods (hardware: a thin class around the vendor
    %   interface that you write, e.g. +tim/+instr/<Name>Session.m; simulation:
    %   the protocol mock, which has the same methods):
    %     id = Dev.identify()       vendor, model, serial, firmware, raw
    %     fs = Dev.configure(c)     channels, rate, range, coupling, IEPE; returns
    %                               the rate the device REALLY runs at
    %     Dev.start()               start a continuous (background) acquisition
    %     [x, st] = Dev.read()      the samples received since the last call,
    %                               m x C volts (m may be 0; never waits long);
    %                               st.fault, st.overload: 1 x C logical flags
    %                               the device reports for this data
    %     Dev.stop()                stop the acquisition (any state)
    %     Dev.close()               release the device
    %     Dev.setTimeout(t)         I/O time-out [s]
    %   Examples of the hardware side (check every call in the vendor's and
    %   MathWorks' documentation): NI-DAQmx through the Data Acquisition
    %   Toolbox - daq("ni"), addinput(d, "Dev1", "ai0", "IEPE"), d.Rate,
    %   start(d, "continuous"), read(d, "all", "OutputFormat", "Matrix"),
    %   stop(d); an audio interface through the Audio Toolbox -
    %   audioDeviceReader per frame (inputs in full-scale units, section 4.2 of
    %   the contract); a network instrument - its own protocol (REST, SCPI).
    %
    %   Acquisition of the instrument contract (docs/instrument_interface.md
    %   sections 4, 8 and 11): streaming (onBlock as data arrive, at least
    %   every 0.25 s), exactly the configured sample rate, volts at the input
    %   (no sensitivity applied), device faults in integrity.channelFaults in
    %   the driver's words, AbortFcn first on every abnormal end (the session
    %   sets it to switch the source output off before the stop), the device
    %   stopped on every exit path (onCleanup), nothing sent after close().
    %   TODO one line: the device (vendor, model), its interface and the manual.

    properties (SetAccess = private)
        Dev                          % device session (hardware class) or MockTemplateAcquisition
        Identity struct = struct()   % vendor, model, serial, firmware, raw (Dev.identify)
        Settings struct = struct()   % driver settings (daq.templateacquisition) from fromConfig
        Range char = ''              % input range after prepare
        Filter char = ''             % high-pass / coupling after prepare
        Ccld logical = false(1, 0)   % IEPE supply per input after prepare
    end
    properties (Access = private)
        Closed logical = false       % close() done: nothing is sent any more
        Prepared logical = false
        Running logical = false      % Dev.start done, Dev.stop not yet
        Done logical = false         % acquire reached its normal end (no abort)
        Data double = zeros(0, 4)    % samples of the running / last acquisition [V]
        Received double = 0          % samples per channel received so far
        Faults cell = {}             % 1 x C: device-reported faults (words) of the last acquisition
    end

    methods
        function obj = TemplateAcquisition(dev, settings)
            %TEMPLATEACQUISITION Driver on an open device session (tim.instr.create builds it through fromConfig).
            obj.Dev = dev;
            obj.Settings = settings;
            obj.Identity = dev.identify();
            obj.Dev.stop();                                   % idle: a previous program may have left it running
        end

        %% ---- acquisition --------------------------------------------------
        function prepare(obj, c)
            %PREPARE Channel setup: exactly c.sampleRate, c.range, c.filter, c.ccld on
            %   inputs c.channels; the device is then ready to acquire. Reports
            %   the checklist step 'setup'.
            obj.assertOpen('prepare');
            q = tim.instr.TemplateAcquisition.capabilities().acquisition;
            if ~any(strcmp(c.range, q.ranges))
                error('tim:templateacquisition:range', 'Input range "%s" not supported (supported: %s).', ...
                    c.range, strjoin(q.ranges, ', '));
            end
            if ~any(strcmp(c.filter, q.filters))
                error('tim:templateacquisition:filter', 'High-pass filter "%s" not supported (supported: %s).', ...
                    c.filter, strjoin(q.filters, ', '));
            end
            ccld = true(1, numel(c.channels));
            if isfield(c, 'ccld') && ~isempty(c.ccld), ccld = logical(c.ccld(:).'); end
            if any(ccld) && ~q.ccld
                error('tim:templateacquisition:ccld', 'This device has no IEPE supply: set acquisition.ccld false.');
            end
            txt = sprintf('%g S/s, %s, high-pass %s', c.sampleRate, c.range, c.filter);
            obj.progress('setup', 'run', txt);
            fs = obj.Dev.configure(struct('sampleRate', c.sampleRate, 'channels', c.channels, ...
                'range', c.range, 'filter', c.filter, 'ccld', ccld));
            if abs(fs - c.sampleRate) > 1e-9 * c.sampleRate
                % a coerced rate would mislabel the frequency axis (contract section 4)
                error('tim:templateacquisition:rate', 'Sample rate %g S/s not possible: the device would run at %g S/s.', ...
                    c.sampleRate, fs);
            end
            obj.SampleRate = c.sampleRate;
            obj.Range = c.range; obj.Filter = c.filter; obj.Ccld = ccld;
            obj.Teds = {};                                    % TODO TEDS: 1 x C cell of [] or struct (contract section 4); {} = not read
            obj.Data = zeros(0, numel(c.channels)); obj.Received = 0;
            obj.Prepared = true;
            obj.progress('setup', 'ok', [txt ' - ready']);
        end

        function [data, info] = acquire(obj, nSamples, onBlock, timeout)
            %ACQUIRE Record nSamples per channel (volts at the input).
            %   onBlock(n) after every block of data and at least every 0.25 s
            %   while recording (n = samples received so far). On every
            %   abnormal end (own error, onBlock error, interrupt) AbortFcn
            %   first, then the device stopped (onCleanup); partial data stay
            %   available through collect().
            if nargin < 3, onBlock = []; end
            if nargin < 4 || isempty(timeout), timeout = nSamples / obj.SampleRate * 1.5 + 10; end
            obj.assertOpen('acquire');
            if ~obj.Prepared
                error('tim:templateacquisition:state', 'acquire needs the channel setup (prepare) first.');
            end
            nCh = numel(obj.Ccld);
            obj.Done = false;
            obj.Data = zeros(nSamples, nCh); obj.Received = 0;
            obj.Faults = repmat({{}}, 1, nCh);
            obj.Dev.start();
            obj.Running = true;
            cleanup = onCleanup(@() obj.endAcquire());
            t0 = tic; lastData = tic; lastCall = tic;
            while obj.Received < nSamples
                obj.assertOpen('acquire');                    % close() from a callback during pause
                [x, st] = obj.Dev.read();
                m = min(size(x, 1), nSamples - obj.Received);
                if m > 0
                    obj.Data(obj.Received + (1:m), :) = x(1:m, :);
                    obj.Received = obj.Received + m;
                    obj.noteFaults(st);
                    lastData = tic;
                end
                if ~isempty(onBlock) && (m > 0 || toc(lastCall) >= 0.2)
                    lastCall = tic;
                    onBlock(obj.Received);
                    obj.assertOpen('acquire');                % close() from inside onBlock
                end
                if m == 0
                    if toc(lastData) > obj.Settings.stallTimeout
                        error('tim:templateacquisition:stalled', 'No data from the device for %g s (got %d of %d samples).', ...
                            obj.Settings.stallTimeout, obj.Received, nSamples);
                    end
                    pause(0.01);
                end
                if toc(t0) > timeout
                    error('tim:templateacquisition:timeout', 'Acquisition time-out (%d of %d samples).', obj.Received, nSamples);
                end
            end
            obj.stopDevice();
            obj.Done = true;
            [data, info] = obj.collect(nSamples);
            clear cleanup
        end

        function [data, info] = collect(obj, nSamples)
            %COLLECT Data received so far (volts) and the integrity report; no I/O.
            data = obj.Data(1:obj.Received, :);
            if nargin >= 2 && size(data, 1) > nSamples, data = data(1:nSamples, :); end
            info = struct('fs', obj.SampleRate, 'dataUnit', 'V');
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
            %RECENT Last <= n samples of the running or last acquisition; no I/O (live view).
            nTotal = obj.Received;
            x = [];
            if nTotal == 0, return; end
            x = obj.Data(max(1, nTotal - n + 1):nTotal, :);
        end

        function tf = isAcquiring(obj)
            %ISACQUIRING An acquisition is running.
            tf = obj.Running;
        end

        function b = rawBytes(~)
            %RAWBYTES No undecoded data: the device session delivers volts.
            b = zeros(1, 0, 'uint8');                         % TODO the raw bytes, if the device delivers any worth keeping
        end

        %% ---- both roles: close, identity, metadata ------------------------
        function close(obj)
            %CLOSE Stop and release. Never throws; a second close() sends nothing.
            %   Inside acquire (e.g. from onBlock) the device stops at once and
            %   acquire ends with tim:instr:closed at its next step.
            if obj.Closed, return; end
            obj.Closed = true;
            obj.stopDevice();
            try, obj.Dev.close(); catch, end
        end

        function delete(obj)
            % a running acquisition stopped, nothing else sent
            if obj.Running, obj.stopDevice(); end
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
            %METADATA Stored with every measurement (JSON-encodable): the contract
            %   fields, the driver settings and the input settings in use.
            d = tim.instr.TemplateAcquisition.describe();
            id = obj.identity();
            md = struct('driver', d.name, 'displayName', d.displayName, 'roles', {obj.rolesInUse()}, ...
                'identity', id, 'sharedClock', false, 'settings', obj.Settings, ...
                'model', id.model, 'serial', id.serial, 'firmware', id.firmware, ...
                'sampleRate', obj.SampleRate, 'range', obj.Range, 'filter', obj.Filter, 'ccld', obj.Ccld, ...
                'teds', {obj.Teds});
        end
    end

    %% ---- contract: class-level members (no I/O) -------------------------------
    methods (Static)
        function d = describe()
            d = struct('name', 'templateacquisition', ...                  % registry name = daq.driver
                'displayName', 'Template DAQ (4 IEPE inputs)', ...          % TODO vendor, model and kind
                'labels', struct('acquisition', 'DAQ'), ...                 % lamp label: the role, not the product
                'defaults', struct( ...
                    'settings', struct( ...                                 % daq.templateacquisition
                        'address', '', ...                                  % TODO what selects the device (NI name, IP address, ...); no default
                        'timeout', 5, ...                                   % I/O time-out [s]
                        'stallTimeout', 2), ...                             % s without data = stalled
                    'acquisition', struct('sampleRate', 16384, ...          % TODO defaults of acquisition.*
                        'range', '5 Vpeak', 'filter', 'AC 0.5 Hz', 'ccld', true(1, 4))), ...
                'texts', struct('settle', 'IEPE + %s coupling', ...         % TODO what settles after prepare ('' = nothing)
                    'noun', 'DAQ', 'closed', 'stopped'), ...
                'simulation', 'protocol');
        end

        function c = capabilities()
            % TODO every value from the manual (section / page in docs/ref_<instrument>.md)
            acq = struct('channels', 4, ...                                 % TODO analog inputs (>= 4)
                'simultaneous', true, ...                                   % TODO must be true: one clock, sampled together
                'sampleRates', [8192 16384 32768], ...                      % TODO rates it runs EXACTLY, or [] and:
                'sampleRateRange', [], ...                                  % [min max] of a continuous range
                'bandFraction', 0.45, ...                                   % TODO usable band / sample rate (anti-alias filter)
                'ranges', {{'5 Vpeak'}}, ...                                % TODO input ranges
                'filters', {{'AC 0.5 Hz'}}, ...                             % TODO high-pass / coupling settings
                'ccld', true, ...                                           % TODO switchable IEPE / CCLD supply
                'teds', false, ...                                          % TODO reads TEDS
                'dataUnit', 'V', ...                                        % 'V', or 'FS' for an unknown input scale
                'mode', 'streaming', ...                                    % data arrive while it records
                'needsOwnSource', false);                                   % onBlock as data arrive
            c = struct('roles', {{'acquisition'}}, 'sharedClock', false, 'rolesTogether', false, ...
                'products', struct('name', {}, 'feature', {}), ...          % TODO e.g. struct('name', 'Data Acquisition Toolbox', 'feature', 'Data_Acq_Toolbox')
                'acquisition', acq);
        end

        function s = connectionSteps()
            s = struct('key', {'templateacquisition', 'setup'}, ...
                'label', {'connect (Template DAQ)', 'channel setup'}, ...   % TODO checklist texts, shown after the lamp label
                'role', 'acquisition', 'phase', {'connect', 'prepare'});
        end

        function report = checkConfig(cfg)
            %CHECKCONFIG Driver settings (daq.templateacquisition) and the generic
            %   acquisition limits (tim.instr.Acquisition.checkAcquisitionConfig).
            d = tim.instr.TemplateAcquisition.describe();
            st = tim.instr.Instrument.settingsFrom(cfg, 'daq', d.name, d.defaults.settings);
            if ~(ischar(st.address) || isstring(st.address))
                error('tim:config:address', 'DAQ address (daq.%s.address) must be text.', d.name);
            end
            if strcmp(cfg.mode, 'hardware') && isempty(strtrim(char(st.address)))
                % no default address: a forgotten setting never opens another device
                error('tim:config:address', 'DAQ address (daq.%s.address) is empty: set the name or address of the device.', ...
                    d.name);
            end
            if ~(isscalar(st.timeout) && st.timeout > 0)
                error('tim:config:timeout', 'DAQ time-out (daq.%s.timeout) must be greater than 0 s.', d.name);
            end
            if ~(isscalar(st.stallTimeout) && st.stallTimeout > 0)
                error('tim:config:stallTimeout', 'DAQ stall time-out (daq.%s.stallTimeout) must be greater than 0 s.', d.name);
            end
            report = tim.instr.Acquisition.checkAcquisitionConfig(cfg, tim.instr.TemplateAcquisition.capabilities(), d);
        end

        % OPTIONAL (TODO keep and fill in, or delete): a support package or vendor
        % runtime that ver does not list is checked by a static checkInstalled(),
        % which tim.instr.create calls in hardware mode before any I/O. E.g. for an
        % NI device (check daqvendorlist in the R2022b documentation):
        %
        % function checkInstalled()
        %     v = daqvendorlist;
        %     if ~any(strcmp(v.ID, 'ni') & v.IsOperational)
        %         error('tim:instr:missingProduct', ['The %s needs the Data Acquisition Toolbox ' ...
        %             'support package for NI-DAQmx and the NI-DAQmx driver (not installed or not ' ...
        %             'operational).'], tim.instr.TemplateAcquisition.describe().displayName);
        %     end
        % end

        function obj = fromConfig(~, ctx)
            %FROMCONFIG Open the device session (hardware) or the mock on ctx.rig
            %   (simulation), identify, idle. Reports the checklist step.
            st = ctx.settings;
            sim = strcmp(ctx.mode, 'simulation');
            if sim
                detail = 'simulated DAQ';
            else
                detail = sprintf('%s', st.address);           % TODO interface text
            end
            tim.instr.Instrument.reportStep(ctx, 'templateacquisition', 'run', detail);
            if sim
                dev = tim.instr.MockTemplateAcquisition(ctx.rig);
            else
                error('tim:templateacquisition:hardware', ...  % TODO open the device session class you wrote, e.g.
                    'The template has no hardware session.');  % dev = tim.instr.<Name>Session(st.address, st.timeout);
            end
            try
                obj = tim.instr.TemplateAcquisition(dev, st);
            catch err
                try, dev.close(); catch, end
                rethrow(err);
            end
            obj.Roles = ctx.roles;
            id = obj.identity();
            tim.instr.Instrument.reportStep(ctx, 'templateacquisition', 'ok', ...
                sprintf('%s  s/n %s  firmware %s', id.model, id.serial, id.firmware));
        end

        function h = testHooks(obj)
            %TESTHOOKS Simulation only: handles into the protocol mock (contract tests).
            dev = obj.Dev;
            if ~isa(dev, 'tim.instr.MockTemplateAcquisition')
                error('tim:instr:noHooks', 'Test hooks need the driver on its mock (simulation).');
            end
            h = struct();
            h.traffic = @() dev.Log;
            h.breakLink = @() dev.fault('broken');
            h.stallAfter = @(n) dev.fault('stallAfter', n);
            h.injectChannelFault = @(c) dev.fault('channel', c);
            h.isRecording = @() dev.Running;
        end
    end

    methods (Access = private)
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

        function stopDevice(obj)
            % stop a running acquisition; never throws (a failure is a warning)
            if ~obj.Running, return; end
            obj.Running = false;
            try
                obj.Dev.stop();
            catch err
                warning('tim:templateacquisition:stop', 'Could not stop the acquisition: %s', err.message);
            end
        end

        function endAcquire(obj)
            % onCleanup of acquire: on an abnormal end AbortFcn first (no I/O
            % before it), then the device stopped - unless close() did that already
            if ~obj.Done, obj.callAbortFcn(); end
            if ~obj.Closed, obj.stopDevice(); end
        end

        function assertOpen(obj, action)
            % after close() nothing is sent any more
            if obj.Closed
                error('tim:instr:closed', 'DAQ driver closed: %s refused (connect again).', action);
            end
        end

        function progress(obj, key, state, detail)
            % checklist step of prepare (a failing callback does not stop the
            % setup); close() from the callback: prepare ends, nothing more is sent
            if ~isempty(obj.ProgressFcn)
                try, obj.ProgressFcn(key, state, detail); catch, end
            end
            obj.assertOpen('prepare');
        end
    end
end
