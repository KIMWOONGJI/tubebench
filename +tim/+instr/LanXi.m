classdef LanXi < handle
    %LANXI Driver for an HBK LAN-XI module (single-module recorder, Open API).
    %
    %   daq = tim.instr.LanXi(http, streamFactory, 'Host', ip)
    %     http           tim.instr.LanXiHttp (hardware) or tim.instr.MockLanXiHttp
    %     streamFactory  @(host, port) -> object with read()/bytesAvailable()/close()
    %                    (tim.instr.LanXiTcpStream or the mock's stream)
    %
    %   Typical sequence (docs/ref_lanxi_openapi.md):
    %     daq.prepare(cfg)        open -> create -> TEDS -> setup -> RecorderStreaming
    %     [data, info] = daq.acquire(nSamples, @onBlock)
    %     daq.shutdown()          stop/finish/close back to Idle
    %
    %   Data are delivered in VOLTS: the channel setup uses the module default
    %   transducer (sensitivity 1, unit "V"); conversion to Pa is done once in
    %   software (tim.acq.voltsToPascal). The decoded Unit descriptor is
    %   checked so the sensitivity can never be applied twice.

    properties (SetAccess = private)
        Http
        StreamFactory
        Host char
        Info struct = struct()
        Teds cell = {}
        Setup struct = struct()
        SampleRate double = NaN
        Range char = ''
        Stream = []
        LastStream = []
        Parser = []
        LastStatus struct = struct()
    end
    properties
        StateTimeout double = 20       % s, per state transition
        TedsTimeout double = 30        % s
        SetupTimeout double = 60       % s, PUT /channels/input (slow on hardware)
        Verbose logical = true
        ProgressFcn = []               % @(key, state, detail), see prepare()
    end

    properties (Constant)
        Bandwidths = containers.Map({4096, 8192, 16384, 32768, 65536, 131072, 262144}, ...
            {'1.6 kHz', '3.2 kHz', '6.4 kHz', '12.8 kHz', '25.6 kHz', '51.2 kHz', '102.4 kHz'})
        Headroom = 10^(1.5/20)        % BE 1872 ch.7 (informational)
    end

    methods
        function obj = LanXi(http, streamFactory, opts)
            arguments
                http
                streamFactory function_handle
                opts.Host (1,:) char = ''
            end
            obj.Http = http;
            obj.StreamFactory = streamFactory;
            obj.Host = opts.Host;
        end

        %% ---- identification / status ------------------------------------
        function info = moduleInfo(obj)
            d = obj.Http.request('GET', '/rest/rec/module/info');
            info = struct();
            info.raw = d;
            info.model = sprintf('%s%s-%s-%s', d.module.type.prefix, d.module.type.number, ...
                d.module.type.model, d.module.type.variant);
            info.typeNumber = d.module.type.number;
            info.serial = d.module.serial;
            info.firmware = d.module.version.firmware;
            info.hardware = d.module.version.hardware;
            info.numInputs = d.numberOfInputChannels;
            info.sampleRates = d.supportedSampleRates(:).';
            info.ranges = cellstr(d.supportedRanges);
            info.filters = cellstr(d.supportedFilters);
            info.destinations = cellstr(d.supportedDestinations);
            info.moduleState = d.moduleState;
            obj.Info = info;
        end

        function st = status(obj, lastTag, timeout)
            if nargin < 2 || isempty(lastTag)
                st = obj.Http.request('GET', '/rest/rec/onchange');
            else
                % long poll: blocks until something changes (max ~30 s)
                st = obj.Http.request('GET', sprintf('/rest/rec/onchange?last=%d', lastTag), [], timeout);
            end
            obj.LastStatus = st;
        end

        function s = state(obj)
            st = obj.status();
            s = st.moduleState;
        end

        function waitForState(obj, target, timeout)
            if nargin < 3, timeout = obj.StateTimeout; end
            t0 = tic;
            st = obj.status();
            while ~strcmp(st.moduleState, target)
                if toc(t0) > timeout
                    error('tim:lanxi:stateTimeout', 'Timeout waiting for state %s (current: %s).', ...
                        target, st.moduleState);
                end
                pause(0.1);
                st = obj.status();
            end
        end

        %% ---- recorder state machine --------------------------------------
        function open(obj)
            obj.requireState('Idle', 'open');
            try
                obj.Http.request('PUT', '/rest/rec/module/time', sprintf('%.0f', ...
                    posixtime(datetime('now', 'TimeZone', 'UTC')) * 1000));
            catch err
                obj.log('Setting module time failed (non-fatal): %s', err.message);
            end
            obj.Http.request('PUT', '/rest/rec/open', struct('performTransducerDetection', false));
            obj.waitForState('RecorderOpened');
        end

        function create(obj)
            obj.requireState('RecorderOpened', 'create');
            obj.Http.request('PUT', '/rest/rec/create');
            obj.waitForState('RecorderConfiguring');
        end

        function teds = detectTransducers(obj)
            %DETECTTRANSDUCERS TEDS detection; returns 1xN cell (struct or []).
            obj.Http.request('POST', '/rest/rec/channels/input/all/transducers/detect');
            t0 = tic;
            st = obj.status();
            while st.transducerDetectionActive
                if toc(t0) > obj.TedsTimeout
                    error('tim:lanxi:teds', 'TEDS detection did not finish within %.0f s.', obj.TedsTimeout);
                end
                pause(0.2);
                st = obj.status();
            end
            d = obj.Http.request('GET', '/rest/rec/channels/input/all/transducers');
            % jsondecode: all-null array -> [] ; mixed -> cell ; all present -> struct array
            if isstruct(d), d = num2cell(d); end
            if ~iscell(d)
                nIn = 4;
                if isfield(obj.Info, 'numInputs'), nIn = obj.Info.numInputs; end
                d = cell(1, nIn);   % hardware-observed: [null,null,null,null] when no TEDS
            end
            teds = cell(1, numel(d));
            for i = 1:numel(d)
                if isstruct(d{i})
                    t = d{i};
                    teds{i} = struct('channel', i, ...
                        'typeNumber', getf(t, {'type', 'number'}, ''), ...
                        'serialNumber', getf(t, {'serialNumber'}, NaN), ...
                        'sensitivity', getf(t, {'sensitivity'}, NaN), ...   % V per unit
                        'unit', getf(t, {'unit'}, ''), ...
                        'requiresCcld', logical(getf(t, {'requiresCcld'}, 0)), ...
                        'raw', t);
                else
                    teds{i} = [];
                end
            end
            obj.Teds = teds;
        end

        function setup = configureChannels(obj, c)
            %CONFIGURECHANNELS Apply the channel setup (RecorderConfiguring -> RecorderStreaming).
            %   c.sampleRate [Hz], c.range ('10 Vpeak'), c.filter ('0.7 Hz'),
            %   c.ccld (logical 1x4), c.channels (vector of enabled channels),
            %   c.names (cellstr)
            obj.requireState('RecorderConfiguring', 'configureChannels');
            if isempty(fieldnames(obj.Info)), obj.moduleInfo(); end
            if ~ismember(c.sampleRate, obj.Info.sampleRates)
                error('tim:lanxi:rate', 'Sample rate %g Hz not supported by module (supported: %s).', ...
                    c.sampleRate, mat2str(obj.Info.sampleRates));
            end
            if ~any(strcmp(c.range, obj.Info.ranges))
                error('tim:lanxi:range', 'Input range "%s" not supported (supported: %s).', c.range, strjoin(obj.Info.ranges, ', '));
            end
            if ~any(strcmp(c.filter, obj.Info.filters))
                error('tim:lanxi:filter', 'High-pass filter "%s" not supported (supported: %s).', c.filter, strjoin(obj.Info.filters, ', '));
            end
            connector = '';
            if isfield(c, 'connector') && ~isempty(c.connector)
                connector = c.connector;
                supported = {};
                if isfield(obj.Info.raw, 'supportedConnectors'), supported = cellstr(obj.Info.raw.supportedConnectors); end
                if ~any(strcmp(connector, supported))
                    error('tim:lanxi:connector', 'Connector "%s" not supported (supported: %s).', connector, strjoin(supported, ', '));
                end
            end
            setup = obj.Http.request('GET', '/rest/rec/channels/input/default');
            ch = setup.channels;
            if iscell(ch), ch = [ch{:}]; end
            bw = obj.Bandwidths(c.sampleRate);
            for i = 1:numel(ch)
                ch(i).enabled = ismember(i, c.channels);
                ch(i).destinations = {'socket'};
                ch(i).bandwidth = bw;
                ch(i).range = c.range;
                ch(i).filter = c.filter;
                ch(i).ccld = logical(c.ccld(min(i, end)));
                if ~isempty(connector)
                    % Field present on the real 3676 default setup (fw 2.10.0.610):
                    % "ConnectorSelect": "BNC" | "LEMO"
                    ch(i).ConnectorSelect = connector;
                end
                if isfield(c, 'names') && numel(c.names) >= i && ~isempty(c.names{i})
                    ch(i).name = c.names{i};
                end
                % Keep the module default transducer (sensitivity 1 V/V,
                % unit V): data stay in volts, see class help.
                if isfield(ch(i), 'transducer') && isfield(ch(i).transducer, 'sensitivity') ...
                        && abs(ch(i).transducer.sensitivity - 1) > 1e-12
                    error('tim:lanxi:sensitivity', ...
                        'Default setup has transducer sensitivity %g on channel %d (expected 1). Refusing to continue to avoid double sensitivity application.', ...
                        ch(i).transducer.sensitivity, i);
                end
            end
            setup.channels = ch;
            % Measured on the real 3676 (fw 2.10.0.610): this request takes
            % more than 10 s to return (front-end configuration).
            obj.Http.request('PUT', '/rest/rec/channels/input', setup, obj.SetupTimeout);
            obj.waitForState('RecorderStreaming');
            obj.Setup = setup;
            obj.SampleRate = c.sampleRate;
            obj.Range = c.range;
        end

        function prepare(obj, c)
            %PREPARE Idle -> RecorderStreaming including TEDS detection.
            %   Steps are reported to ProgressFcn (keys open, teds, setup).
            obj.progress('open', 'run', 'Idle -> RecorderOpened -> RecorderConfiguring');
            obj.moduleInfo();
            obj.open();
            obj.create();
            obj.progress('open', 'ok', 'RecorderConfiguring');
            if ~isfield(c, 'detectTeds') || c.detectTeds
                obj.progress('teds', 'run', 'transducer detection on all inputs');
                try
                    obj.detectTransducers();
                    found = find(~cellfun(@isempty, obj.Teds));
                    txt = sprintf('%d of %d inputs with TEDS', numel(found), numel(obj.Teds));
                    for i = found
                        txt = sprintf('%s,  ch%d %s s/n %d', txt, i, obj.Teds{i}.typeNumber, obj.Teds{i}.serialNumber);
                    end
                    if numel(found) == numel(obj.Teds), st = 'ok'; else, st = 'warn'; end
                    obj.progress('teds', st, txt);
                catch err
                    obj.log('TEDS detection failed (continuing with manual sensitivities): %s', err.message);
                    obj.Teds = {};
                    obj.progress('teds', 'warn', ['failed - manual sensitivities: ' err.message]);
                end
            else
                obj.progress('teds', 'skip', 'disabled in the configuration');
            end
            conn = ''; if isfield(c, 'connector'), conn = c.connector; end
            obj.progress('setup', 'run', sprintf('%g S/s, %s, high-pass %s, %s - can take more than 10 s', ...
                c.sampleRate, c.range, c.filter, conn));
            obj.configureChannels(c);
            obj.progress('setup', 'ok', sprintf('%g S/s, %s, high-pass %s, %s -> RecorderStreaming', ...
                c.sampleRate, c.range, c.filter, conn));
        end

        function startMeasurement(obj)
            obj.requireState('RecorderStreaming', 'startMeasurement');
            d = obj.Http.request('GET', '/rest/rec/destination/socket');
            port = d.tcpPort;
            obj.Parser = tim.instr.LanXiStreamParser();
            obj.Stream = obj.StreamFactory(obj.Host, port);     % connect BEFORE start ([P])
            obj.Http.request('POST', '/rest/rec/measurements');
            obj.waitForState('RecorderRecording');
        end

        function n = pump(obj)
            %PUMP Move available stream bytes into the parser; returns samples/channel.
            b = obj.Stream.read();
            if ~isempty(b), obj.Parser.feed(b); end
            n = obj.Parser.samplesAvailable();
        end

        function stopMeasurement(obj)
            % Stop BEFORE closing the socket ([P]); drain remaining bytes.
            try
                obj.Http.request('PUT', '/rest/rec/measurements/stop');
                obj.waitForState('RecorderStreaming');
            catch err
                obj.log('Stop failed: %s', err.message);
            end
            if ~isempty(obj.Stream)
                try
                    t0 = tic;
                    while toc(t0) < 0.3
                        b = obj.Stream.read();
                        if isempty(b), pause(0.05); else, obj.Parser.feed(b); end
                    end
                catch
                end
                try, obj.Stream.close(); catch, end
                obj.LastStream = obj.Stream;   % keeps raw bytes if a RecordingStream
                obj.Stream = [];
            end
        end

        function [data, info] = acquire(obj, nSamples, onBlock, timeout)
            %ACQUIRE Finite acquisition of nSamples per channel (volts).
            %   onBlock(nNow) is called after every received block; the
            %   measurement session uses it to trigger the generator at the
            %   right moment. Errors inside onBlock stop the acquisition but
            %   the data received so far are returned in the error's
            %   info (see tim.acq.runSweep).
            if nargin < 3, onBlock = []; end
            if nargin < 4, timeout = nSamples / obj.SampleRate * 1.5 + 10; end
            obj.startMeasurement();
            cleanup = onCleanup(@() obj.stopIfRecording());
            t0 = tic; n = 0; lastProgress = tic; lastN = 0;
            while n < nSamples
                n = obj.pump();
                if ~isempty(onBlock), onBlock(n); end
                if n == lastN
                    if toc(lastProgress) > 5
                        error('tim:lanxi:streamStalled', 'No stream data for 5 s (got %d of %d samples).', n, nSamples);
                    end
                    pause(0.01);
                else
                    lastN = n; lastProgress = tic;
                end
                if toc(t0) > timeout
                    error('tim:lanxi:acqTimeout', 'Acquisition timeout (%d of %d samples).', n, nSamples);
                end
            end
            obj.stopMeasurement();
            [data, info] = obj.collect(nSamples);
        end

        function [data, info] = collect(obj, nSamples)
            %COLLECT Decoded data so far (volts), integrity checks in info.
            ids = 1:numel(find([obj.Setup.channels.enabled]));
            [data, info] = obj.Parser.getData(ids);
            if nargin >= 2 && size(data, 1) > nSamples
                data = data(1:nSamples, :);
            end
            info.integrity = tim.acq.checkIntegrity(data, info, obj.SampleRate, obj.Range);
        end

        function stopIfRecording(obj)
            try
                if ~isempty(obj.Stream) || strcmp(obj.state(), 'RecorderRecording')
                    obj.stopMeasurement();
                end
            catch err
                obj.log('stopIfRecording: %s', err.message);
            end
        end

        function shutdown(obj)
            %SHUTDOWN Best effort return to Idle from any recorder state. Never throws.
            for i = 1:6
                try
                    s = obj.state();
                catch err
                    obj.log('shutdown: status failed: %s', err.message); return
                end
                try
                    switch s
                        case 'Idle', return
                        case 'RecorderRecording', obj.stopMeasurement();
                        case 'RecorderStreaming', obj.Http.request('PUT', '/rest/rec/finish');
                        case 'RecorderConfiguring', obj.Http.request('PUT', '/rest/rec/cancel');
                        case 'RecorderOpened', obj.Http.request('PUT', '/rest/rec/close');
                        otherwise
                            obj.log('shutdown: unexpected state %s, waiting', s); pause(0.5);
                    end
                catch err
                    obj.log('shutdown step in %s failed: %s', s, err.message);
                end
                pause(0.2);
            end
        end

        function delete(obj)
            if ~isempty(obj.Stream)
                try, obj.stopMeasurement(); catch, end
            end
        end
    end

    methods (Access = private)
        function requireState(obj, expected, action)
            s = obj.state();
            if ~strcmp(s, expected)
                error('tim:lanxi:state', '%s requires module state %s, but module is in %s. Use shutdown() to return to Idle.', ...
                    action, expected, s);
            end
        end
        function log(obj, varargin)
            if obj.Verbose, fprintf('[LAN-XI] %s\n', sprintf(varargin{:})); end
        end
        function progress(obj, key, state, detail)
            if ~isempty(obj.ProgressFcn)
                try, obj.ProgressFcn(key, state, detail); catch, end
            end
        end
    end
end

function v = getf(s, path, default)
v = default;
for i = 1:numel(path)
    if isstruct(s) && isfield(s, path{i})
        s = s.(path{i});
    else
        return
    end
end
v = s;
end
