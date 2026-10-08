classdef LanXiHttp < handle
    %LANXIHTTP Minimal REST client for the LAN-XI Open API (matlab.net.http).
    %
    %   h = tim.instr.LanXiHttp('169.254.64.156', 10);
    %   [data, status] = h.request('GET', '/rest/rec/module/info');
    %   [data, status] = h.request('PUT', '/rest/rec/open', struct('performTransducerDetection', false));
    %
    %   * struct bodies are sent as application/json (jsonencode)
    %   * char bodies are sent as text/plain (used for /module/time)
    %   * the raw payload is decoded with jsondecode when possible, so the
    %     decoding does not depend on MATLAB's automatic content conversion
    %   * HTTP status >= 300 raises tim:lanxi:http with the status and body
    %   The Open API does not support persistent connections (BE 1872 6.2.1);
    %   each request uses a new connection.

    properties (SetAccess = private)
        Host char
        Timeout double
        Log cell = {}
    end

    methods
        function obj = LanXiHttp(host, timeout)
            arguments
                host (1,:) char
                timeout (1,1) double = 10
            end
            obj.Host = host; obj.Timeout = timeout;
        end

        function [data, status, raw] = request(obj, method, path, body, timeout)
            import matlab.net.http.*
            import matlab.net.http.field.*
            if nargin < 4, body = []; end
            if nargin < 5, timeout = obj.Timeout; end
            uri = matlab.net.URI(['http://' obj.Host path]);
            hdr = HeaderField.empty;
            if isstruct(body)
                txt = jsonencode(body);
                hdr = ContentTypeField('application/json');
                msgBody = MessageBody(); msgBody.Payload = unicode2native(txt, 'UTF-8');
            elseif ischar(body) || isstring(body)
                txt = char(body);
                hdr = ContentTypeField('text/plain');
                msgBody = MessageBody(); msgBody.Payload = unicode2native(txt, 'UTF-8');
            else
                txt = '';
                msgBody = MessageBody.empty;
            end
            req = RequestMessage(RequestMethod(upper(method)), hdr, msgBody);
            opts = HTTPOptions('ConnectTimeout', min(timeout, 10), 'ResponseTimeout', timeout, ...
                'SavePayload', true, 'ConvertResponse', false, 'KeepAliveTimeout', 0);
            % Body-less PUT/POST is what the Open API expects (BE 1872);
            % silence only that specific MATLAB warning.
            ws = warning('off', 'MATLAB:http:BodyExpectedFor');
            restoreWarn = onCleanup(@() warning(ws));
            t0 = tic;
            resp = [];
            for attempt = 1:2
                try
                    resp = req.send(uri, opts);
                    break
                catch err
                    obj.addLog(method, path, txt, NaN, toc(t0));
                    % Retry once only for GET (idempotent); a state-changing
                    % request may have been executed although no reply arrived.
                    if attempt == 2 || ~strcmpi(method, 'GET')
                        error('tim:lanxi:network', 'LAN-XI %s %s failed: %s', method, path, err.message);
                    end
                    pause(0.5);
                end
            end
            status = double(resp.StatusCode);
            raw = '';
            if ~isempty(resp.Body) && ~isempty(resp.Body.Payload)
                raw = native2unicode(resp.Body.Payload(:).', 'UTF-8');
            elseif ~isempty(resp.Body) && ~isempty(resp.Body.Data)
                raw = char(resp.Body.Data);
            end
            obj.addLog(method, path, txt, status, toc(t0));
            data = [];
            if ~isempty(strtrim(raw))
                try
                    data = jsondecode(raw);
                catch
                    data = raw;
                end
            end
            if status >= 300
                error('tim:lanxi:http', 'LAN-XI %s %s returned HTTP %d: %s', method, path, status, ...
                    strtrim(raw(1:min(end, 300))));
            end
        end
    end

    methods (Access = private)
        function addLog(obj, method, path, body, status, dt)
            obj.Log(end+1, :) = {datetime('now'), method, path, body(1:min(end, 200)), status, dt};
            if size(obj.Log, 1) > 2000, obj.Log(1:1000, :) = []; end
        end
    end
end
