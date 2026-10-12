classdef ScpiTcpTransport < handle
    %SCPITCPTRANSPORT Raw-socket SCPI transport (LF terminated) using tcpclient.
    %
    %   t = tim.instr.ScpiTcpTransport('169.254.2.20', 5025, 5)
    %   t.write('*CLS'); r = t.query('*IDN?'); t.close();
    %
    %   Requires MATLAB R2020b+ (tcpclient with writeline/readline).
    %   Hardware status: VERIFIED against the real 33220A for *IDN?,
    %   SYST:ERR? and OUTP? (read-only) on 2026-10-08. See docs/hardware_status.md.
    %
    %   A LOST CONNECTION. The 33220A drops an idle socket connection now and
    %   then without telling the PC (hardware check 2026-10-12): the next
    %   command reaches nobody, the instrument answers it with a reset. The
    %   reset arrives in tcpclient's ErrorOccurredFcn (registered here, so
    %   MATLAB prints no stack trace in the command window) and marks the
    %   connection lost; isOpen() is then false, and every write or query
    %   raises tim:scpi:connectionLost (English text) instead of MATLAB's
    %   message. reopen() opens a new connection to the same address; the
    %   driver decides when (Keysight33220A.checkConnection).

    properties (SetAccess = private)
        Host char
        Port double
        Timeout double
        Log cell = {}          % command log: {time, direction, text}
    end
    properties (Access = private)
        Client = []
        Desynchronised logical = false   % a query timed out: its answer may still arrive
        Lost = []              % containers.Map: 'lost' (logical), 'message' - shared with the
                               % ErrorOccurredFcn of the client (no reference back to obj)
    end

    methods
        function obj = ScpiTcpTransport(host, port, timeout)
            arguments
                host (1,:) char
                port (1,1) double = 5025
                timeout (1,1) double = 5
            end
            obj.Host = host; obj.Port = port; obj.Timeout = timeout;
            obj.open();
        end

        function write(obj, cmd)
            obj.ensureOpen();
            obj.addLog('>', cmd);
            try
                writeline(obj.Client, cmd);
            catch err
                obj.connectionLost(err, cmd);
            end
            % a reset noticed while the command was sent (the connection was
            % already gone): this command reached nobody either
            if obj.lost(), obj.connectionLost([], cmd); end
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
            try
                if obj.Desynchronised, obj.resynchronise(); end
                obj.discardInput();
                obj.addLog('>', cmd);
                writeline(obj.Client, cmd);
                resp = readline(obj.Client);
            catch err
                if startsWith(err.identifier, 'tim:scpi:'), rethrow(err); end
                obj.connectionLost(err, cmd);
            end
            if obj.lost(), obj.connectionLost([], cmd); end
            if isempty(resp) || (isstring(resp) && ismissing(resp))
                obj.Desynchronised = true;      % its answer may still arrive
                error('tim:scpi:timeout', 'No response to "%s" within %.1f s.', cmd, timeout);
            end
            resp = strtrim(char(resp));
            obj.addLog('<', resp);
        end

        function tf = isOpen(obj)
            %ISOPEN The connection is open and not known to be lost.
            tf = ~isempty(obj.Client) && ~obj.lost();
        end

        function reopen(obj)
            %REOPEN Close this connection and open a new one to the same
            %   address (tim:scpi:connect when the instrument does not answer).
            obj.Client = [];
            obj.addLog('*', sprintf('re-opening the connection to %s:%d', obj.Host, obj.Port));
            obj.open();
            obj.Desynchronised = false;
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
        function open(obj)
            try
                c = tcpclient(obj.Host, obj.Port, 'Timeout', obj.Timeout, 'ConnectTimeout', obj.Timeout);
            catch err
                error('tim:scpi:connect', ...
                    'Cannot open TCP socket %s:%d (%s). Check cabling, IP address and that no other program holds the socket.', ...
                    obj.Host, obj.Port, err.message);
            end
            configureTerminator(c, "LF");
            box = containers.Map({'lost', 'message'}, {false, ''});
            try
                c.ErrorOccurredFcn = @(~, evt) noteError(box, evt);
            catch
                % (a MATLAB without ErrorOccurredFcn: the errors of writeline /
                % readline still mark the connection lost)
            end
            obj.Lost = box;
            obj.Client = c;
        end
        function tf = lost(obj)
            tf = ~isempty(obj.Lost) && obj.Lost('lost');
        end
        function connectionLost(obj, err, cmd)
            % mark the connection lost and raise the English error
            if ~isempty(obj.Lost), obj.Lost('lost') = true; end
            raw = '';
            if ~isempty(err), raw = err.message; elseif ~isempty(obj.Lost), raw = obj.Lost('message'); end
            obj.addLog('!', sprintf('connection lost while sending "%s": %s', cmd, ...
                strtrim(regexprep(raw, '\s+', ' '))));
            error('tim:scpi:connectionLost', ['The connection to %s:%d was closed while sending "%s": the ' ...
                'instrument dropped it or the link is down.'], obj.Host, obj.Port, cmd);
        end
        function ensureOpen(obj)
            if isempty(obj.Client)
                error('tim:scpi:closed', 'SCPI transport to %s is closed.', obj.Host);
            end
            if obj.lost()
                error('tim:scpi:connectionLost', 'The connection to %s:%d was closed by the instrument or the link.', ...
                    obj.Host, obj.Port);
            end
        end
        function restoreTimeout(obj, t)
            if ~isempty(obj.Client), try, obj.Client.Timeout = t; catch, end, end
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

function noteError(box, evt)
% ErrorOccurredFcn of the tcpclient: a reset or a closed connection (no
% stack trace in the command window; the next write / query reports it)
msg = 'connection error';
try, msg = char(evt.Message); catch, end
box('lost') = true;      % (box is a handle: the transport reads it)
box('message') = msg; %#ok<NASGU>
end
