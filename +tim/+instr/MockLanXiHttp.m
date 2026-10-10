classdef MockLanXiHttp < handle
    %MOCKLANXIHTTP Simulated LAN-XI Open API REST interface (simulation mode).
    %
    %   m = tim.instr.MockLanXiHttp(rig)
    %   Same request() signature as tim.instr.LanXiHttp. Emulates the
    %   recorder state machine of docs/ref_lanxi_openapi.md, returning HTTP
    %   403 (as tim:lanxi:http errors) for requests invalid in the current
    %   state, exactly like the real module (observed text: "Cannot create
    %   recording in module state Idle").
    %   module/info and the default setup are the REAL responses of the
    %   lab's 3676 (tests/fixtures).
    %
    %   Fault injection:
    %     TedsPresent      logical 1x4 - channels returning a TEDS record
    %     FailPath         path for which the next request fails (network error)
    %     StreamOptions    struct passed to MockLanXiStream (chunking, corruption...)
    %
    %   Log lists every request ('METHOD path'). While tim.instr.mockBusLog
    %   records (tests/TestBusTraffic), every request goes there with its body
    %   (bus 'REST': 'PUT /rest/rec/open {"performTransducerDetection":false}')
    %   and every stream connection as 'STREAM open port <port>'.

    properties
        Rig = []
        TedsPresent logical = true(1, 4)
        TedsSensitivity double = [11.2 11.5 10.9 11.3] * 1e-3
        TedsSerial double = [3001001 3001002 3001003 3001004]
        FailPath char = ''
        StreamOptions struct = struct()
        Port double = 1536
    end
    properties (SetAccess = private)
        State char = 'Idle'
        Tag double = 0
        Setup = []
        ActiveStream = []
        Info struct
        DefaultSetup struct
        Log cell = {}
    end

    methods
        function obj = MockLanXiHttp(rig)
            if nargin >= 1, obj.Rig = rig; end
            here = fileparts(mfilename('fullpath'));
            fx = fullfile(here, '..', '..', 'tests', 'fixtures');
            obj.Info = readJson(fullfile(fx, 'lanxi_module_info_3676_fw2.10.0.610.json'));
            obj.DefaultSetup = readJson(fullfile(fx, 'lanxi_default_setup_3676.json'));
        end

        function [data, status, raw] = request(obj, method, path, body, ~)
            if nargin < 4, body = []; end
            method = upper(method);
            obj.Log{end+1} = sprintf('%s %s', method, path);
            tim.instr.mockBusLog('add', 'REST', strtrim(sprintf('%s %s %s', method, path, bodyText(body))));
            if ~isempty(obj.FailPath) && strcmpi(path, obj.FailPath)
                obj.FailPath = '';
                error('tim:lanxi:network', 'LAN-XI %s %s failed: mock network error', method, path);
            end
            p = lower(regexprep(path, '\?.*$', ''));
            status = 200; data = [];
            switch [method ' ' p]
                case 'GET /rest/rec/module/info'
                    data = obj.Info; data.moduleState = obj.State;
                case 'GET /rest/rec/onchange'
                    data = struct('moduleState', obj.State, 'transducerDetectionActive', false, ...
                        'lastUpdateTag', obj.Tag, 'ptpStatus', 'Locked', 'inputStatus', 'Settled', ...
                        'canStartStreaming', strcmp(obj.State, 'RecorderStreaming'));
                case 'PUT /rest/rec/module/time'
                case 'PUT /rest/rec/open',      obj.transition('Idle', 'RecorderOpened', 'open recorder');
                case 'PUT /rest/rec/create',    obj.transition('RecorderOpened', 'RecorderConfiguring', 'create recording');
                case 'PUT /rest/rec/cancel',    obj.transition('RecorderConfiguring', 'RecorderOpened', 'cancel recording');
                case 'POST /rest/rec/channels/input/all/transducers/detect'
                case 'GET /rest/rec/channels/input/all/transducers'
                    data = obj.tedsResponse();
                case 'GET /rest/rec/channels/input/default'
                    data = obj.DefaultSetup;
                case 'PUT /rest/rec/channels/input'
                    obj.requireState('RecorderConfiguring', 'configure channels');
                    obj.validateSetup(body);
                    obj.Setup = body;
                    obj.State = 'RecorderStreaming'; obj.Tag = obj.Tag + 1;
                case 'GET /rest/rec/destination/socket'
                    obj.requireState({'RecorderStreaming', 'RecorderRecording'}, 'get socket');
                    data = struct('tcpPort', obj.Port);
                case 'POST /rest/rec/measurements'
                    obj.requireState('RecorderStreaming', 'start measurement');
                    obj.State = 'RecorderRecording'; obj.Tag = obj.Tag + 1;
                    if ~isempty(obj.ActiveStream), obj.ActiveStream.start(); end
                case 'PUT /rest/rec/measurements/stop'
                    obj.requireState('RecorderRecording', 'stop measurement');
                    obj.State = 'RecorderStreaming'; obj.Tag = obj.Tag + 1;
                    if ~isempty(obj.ActiveStream), obj.ActiveStream.stop(); end
                case 'PUT /rest/rec/finish',    obj.transition('RecorderStreaming', 'RecorderOpened', 'finish recording');
                case 'PUT /rest/rec/close',     obj.transition('RecorderOpened', 'Idle', 'close recorder');
                otherwise
                    status = 404;
                    error('tim:lanxi:http', 'LAN-XI %s %s returned HTTP 404: not found (mock)', method, path);
            end
            raw = '';
        end

        function s = openStream(obj, ~, port)
            %OPENSTREAM Stream factory for tim.instr.LanXi in simulation.
            tim.instr.mockBusLog('add', 'STREAM', sprintf('open port %d', port));
            if port ~= obj.Port
                error('tim:lanxi:streamConnect', 'Mock: no listener on port %d.', port);
            end
            ch = obj.Setup.channels;
            if iscell(ch), ch = [ch{:}]; end
            enabled = find([ch.enabled]);
            bw = ch(enabled(1)).bandwidth;
            fs = 2.56 * sscanf(bw, '%f') * 1e3;
            rangeV = sscanf(ch(enabled(1)).range, '%f');
            if ~isempty(obj.Rig) && abs(obj.Rig.Fs - fs) > 1e-6
                error('tim:sim:rate', 'Simulated rig Fs (%g) differs from configured rate (%g).', obj.Rig.Fs, fs);
            end
            s = tim.instr.MockLanXiStream(obj.Rig, fs, rangeV, enabled, obj.StreamOptions);
            obj.ActiveStream = s;
        end
    end

    methods (Access = private)
        function transition(obj, from, to, what)
            obj.requireState(from, what);
            obj.State = to; obj.Tag = obj.Tag + 1;
        end

        function requireState(obj, allowed, what)
            if ischar(allowed), allowed = {allowed}; end
            if ~any(strcmp(obj.State, allowed))
                error('tim:lanxi:http', 'LAN-XI request returned HTTP 403: Cannot %s in module state %s.', what, obj.State);
            end
        end

        function validateSetup(obj, s)
            ch = s.channels;
            if iscell(ch), ch = [ch{:}]; end
            if numel(ch) ~= 4, error('tim:lanxi:http', 'HTTP 400: expected 4 channels.'); end
            bw = unique({ch.bandwidth});
            if numel(bw) ~= 1, error('tim:lanxi:http', 'HTTP 400: bandwidth must be equal on all channels.'); end
            fs = 2.56 * sscanf(bw{1}, '%f') * 1e3;
            if ~ismember(fs, obj.Info.supportedSampleRates)
                error('tim:lanxi:http', 'HTTP 400: unsupported bandwidth %s.', bw{1});
            end
            for i = 1:numel(ch)
                if ~any(strcmp(ch(i).range, obj.Info.supportedRanges))
                    error('tim:lanxi:http', 'HTTP 400: unsupported range %s.', ch(i).range);
                end
                d = ch(i).destinations; if ischar(d), d = {d}; end
                if ~isequal(d, {'socket'}) && ch(i).enabled
                    error('tim:lanxi:http', 'HTTP 400: destination must be socket in this mock.');
                end
            end
        end

        function d = tedsResponse(obj)
            if ~any(obj.TedsPresent)
                d = [];      % real module: [null,null,null,null] -> jsondecode []
                return
            end
            d = cell(1, 4);
            for i = 1:4
                if obj.TedsPresent(i)
                    d{i} = struct('requires200V', 0, 'requiresCcld', 1, 'sensitivity', obj.TedsSensitivity(i), ...
                        'serialNumber', obj.TedsSerial(i), 'teds', 'MOCK', ...
                        'type', struct('model', '', 'number', '4957', 'prefix', '', 'variant', ''), 'unit', 'Pa');
                end
            end
            if all(obj.TedsPresent), d = [d{:}]; end   % jsondecode would give a struct array
        end
    end
end

function s = readJson(file)
s = jsondecode(tim.app.readTextUtf8(file));
end

function t = bodyText(body)
% request body as LanXiHttp sends it: struct -> JSON, text as is
if isstruct(body)
    t = jsonencode(body);
elseif ischar(body) || isstring(body)
    t = char(body);
else
    t = '';
end
end
