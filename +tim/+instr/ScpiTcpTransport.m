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
    %   command reaches nobody and the instrument answers it with a reset.
    %   tcpclient (R2022b) reports that reset only in its own background
    %   handler, which prints a stack trace in the command window ("현재 연결은
    %   원격 호스트에 의해 강제로 끊겼습니다" on a Korean system; there is no
    %   public way to suppress it, and ErrorOccurredFcn is not called), lets
    %   the pending readline run into its time-out and fails the next
    %   writeline. So a query on a dropped connection ends with
    %   tim:scpi:timeout, a write with tim:scpi:connectionLost (English text;
    %   isOpen() is false afterwards). reopen() opens a new connection to the
    %   same address; the driver decides when (Keysight33220A.checkConnection).
    %   The readline time-out warning of tcpclient is not shown: the
    %   transport raises its own error instead.

    properties (SetAccess = private)
        Host char
        Port double
        Timeout double
        Log cell = {}          % command log: {time, direction, text}
    end
    properties (Access = private)
        Client = []
        Desynchronised logical = false   % a query timed out: its answer may still arrive
        Lost logical = false             % a write failed: the connection is gone (until reopen)
        LastIO = []                      % tic of the last successful write / answer (idleSeconds)
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
            obj.LastIO = tic;
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
            quiet = warning('off', 'transportlib:client:ReadlineWarning');   % (our own error below)
            restoreWarn = onCleanup(@() warning(quiet));
            if obj.Desynchronised, obj.resynchronise(); end
            obj.discardInput();
            obj.addLog('>', cmd);
            try
                writeline(obj.Client, cmd);
            catch err
                obj.connectionLost(err, cmd);
            end
            resp = readline(obj.Client);
            if isempty(resp) || (isstring(resp) && ismissing(resp))
                obj.Desynchronised = true;      % its answer may still arrive
                error('tim:scpi:timeout', 'No response to "%s" within %.1f s.', cmd, timeout);
            end
            resp = strtrim(char(resp));
            obj.addLog('<', resp);
            obj.LastIO = tic;
        end

        function s = idleSeconds(obj)
            %IDLESECONDS Seconds since the last successful write or answer on
            %   this connection (since it was opened when nothing yet).
            s = toc(obj.LastIO);
        end

        function tf = isOpen(obj)
            %ISOPEN The connection is open and not known to be lost.
            tf = ~isempty(obj.Client) && ~obj.Lost;
        end

        function reopen(obj)
            %REOPEN Close this connection and open a new one to the same
            %   address (tim:scpi:connect when the instrument does not answer).
            obj.Client = [];
            obj.addLog('*', sprintf('re-opening the connection to %s:%d', obj.Host, obj.Port));
            try
                obj.open();
            catch
                pause(0.3);                      % (the instrument may still be closing the old one)
                obj.open();
            end
            obj.Lost = false; obj.Desynchronised = false;
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
                obj.Client = tcpclient(obj.Host, obj.Port, 'Timeout', obj.Timeout, 'ConnectTimeout', obj.Timeout);
            catch err
                error('tim:scpi:connect', ...
                    'Cannot open TCP socket %s:%d (%s). Check cabling, IP address and that no other program holds the socket.', ...
                    obj.Host, obj.Port, err.message);
            end
            configureTerminator(obj.Client, "LF");
            obj.LastIO = tic;
        end
        function connectionLost(obj, err, cmd)
            % a write failed: mark the connection lost, raise the English error
            obj.Lost = true;
            obj.addLog('!', sprintf('connection lost while sending "%s": %s', cmd, ...
                strtrim(regexprep(err.message, '\s+', ' '))));
            error('tim:scpi:connectionLost', ['The connection to %s:%d was closed while sending "%s": the ' ...
                'instrument dropped it or the link is down.'], obj.Host, obj.Port, cmd);
        end
        function ensureOpen(obj)
            if isempty(obj.Client)
                error('tim:scpi:closed', 'SCPI transport to %s is closed.', obj.Host);
            end
            if obj.Lost
                error('tim:scpi:connectionLost', 'The connection to %s:%d was closed by the instrument or the link.', ...
                    obj.Host, obj.Port);
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
            try
                writeline(obj.Client, '*IDN?');
            catch err
                obj.connectionLost(err, '*IDN?');
            end
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
