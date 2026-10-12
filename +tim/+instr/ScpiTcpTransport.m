classdef ScpiTcpTransport < handle
    %SCPITCPTRANSPORT Raw-socket SCPI transport (LF terminated) using tcpclient.
    %
    %   t = tim.instr.ScpiTcpTransport('169.254.2.20', 5025, 5)
    %   t.write('*CLS'); r = t.query('*IDN?'); t.close();
    %
    %   Requires MATLAB R2020b+ (tcpclient with writeline/readline).
    %   Hardware status: VERIFIED against the real 33220A for *IDN?,
    %   SYST:ERR? and OUTP? (read-only) on 2026-10-08. See docs/hardware_status.md.

    properties (SetAccess = private)
        Host char
        Port double
        Timeout double
        Log cell = {}          % command log: {time, direction, text}
    end
    properties (Access = private)
        Client = []
        Desynchronised logical = false   % a query timed out: its answer may still arrive
    end

    methods
        function obj = ScpiTcpTransport(host, port, timeout)
            arguments
                host (1,:) char
                port (1,1) double = 5025
                timeout (1,1) double = 5
            end
            obj.Host = host; obj.Port = port; obj.Timeout = timeout;
            try
                obj.Client = tcpclient(host, port, 'Timeout', timeout, 'ConnectTimeout', timeout);
            catch err
                error('tim:scpi:connect', ...
                    'Cannot open TCP socket %s:%d (%s). Check cabling, IP address and that no other program holds the socket.', ...
                    host, port, err.message);
            end
            configureTerminator(obj.Client, "LF");
        end

        function write(obj, cmd)
            obj.ensureOpen();
            obj.addLog('>', cmd);
            writeline(obj.Client, cmd);
        end

        function resp = query(obj, cmd, timeout)
            %QUERY Write cmd and read its one-line answer. A reply that arrives
            %   after its query timed out must not be read as the answer to a
            %   later query: pending input is discarded before every query, and
            %   after a time-out the next query first resynchronises (*IDN?,
            %   every line before its answer dropped).
            if nargin < 3, timeout = obj.Timeout; end
            obj.ensureOpen();
            old = obj.Client.Timeout;
            obj.Client.Timeout = timeout;
            restore = onCleanup(@() obj.restoreTimeout(old));
            if obj.Desynchronised, obj.resynchronise(); end
            obj.discardInput();
            obj.addLog('>', cmd);
            writeline(obj.Client, cmd);
            resp = readline(obj.Client);
            if isempty(resp) || (isstring(resp) && ismissing(resp))
                obj.Desynchronised = true;      % its answer may still arrive
                error('tim:scpi:timeout', 'No response to "%s" within %.1f s.', cmd, timeout);
            end
            resp = strtrim(char(resp));
            obj.addLog('<', resp);
        end

        function tf = isOpen(obj)
            tf = ~isempty(obj.Client);
        end

        function setTimeout(obj, timeout)
            %SETTIMEOUT Read / write time-out [s] (short when closing the app).
            obj.Timeout = timeout;
            if ~isempty(obj.Client), obj.Client.Timeout = timeout; end
        end

        function close(obj)
            obj.Client = [];   % tcpclient closes when cleared
        end

        function delete(obj)
            obj.close();
        end
    end

    methods (Access = private)
        function ensureOpen(obj)
            if isempty(obj.Client)
                error('tim:scpi:closed', 'SCPI transport to %s is closed.', obj.Host);
            end
        end
        function restoreTimeout(obj, t)
            if ~isempty(obj.Client), obj.Client.Timeout = t; end
        end
        function discardInput(obj)
            % a late reply already received: logged and dropped
            n = obj.Client.NumBytesAvailable;
            if n > 0
                late = read(obj.Client, n, 'char');
                obj.addLog('<', sprintf('(late reply discarded) %s', strtrim(regexprep(char(late), '\s+', ' '))));
            end
        end
        function resynchronise(obj)
            % after a time-out: *IDN? and every line before its answer (four
            % comma-separated fields, IEEE 488.2) dropped; the late reply of
            % the timed-out query may arrive before or after the *IDN? is sent
            obj.discardInput();
            obj.addLog('>', '*IDN?');
            writeline(obj.Client, '*IDN?');
            for i = 1:10
                r = readline(obj.Client);
                if isempty(r) || (isstring(r) && ismissing(r))
                    error('tim:scpi:timeout', 'No response to "*IDN?" (resynchronisation after a time-out).');
                end
                r = strtrim(char(r));
                if numel(strfind(r, ',')) >= 3
                    obj.addLog('<', r);
                    obj.Desynchronised = false;
                    return
                end
                obj.addLog('<', sprintf('(late reply discarded) %s', r));
            end
            error('tim:scpi:desync', 'SCPI answers out of order after a time-out: reconnect the generator.');
        end
        function addLog(obj, dir, txt)
            obj.Log(end+1, :) = {datetime('now'), dir, txt};
            if size(obj.Log, 1) > 2000, obj.Log(1:1000, :) = []; end
        end
    end
end
