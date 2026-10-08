classdef LanXiTcpStream < handle
    %LANXITCPSTREAM TCP stream socket for LAN-XI data (tcpclient wrapper).
    %
    %   s = tim.instr.LanXiTcpStream(host, port);  b = s.read();  s.close();
    %   read() returns all bytes currently buffered (uint8 row, possibly empty);
    %   message boundaries are NOT preserved (handled by LanXiStreamParser).

    properties (SetAccess = private)
        Host char
        Port double
        BytesRead double = 0
    end
    properties (Access = private)
        Client = []
    end

    methods
        function obj = LanXiTcpStream(host, port, timeout)
            if nargin < 3, timeout = 10; end
            obj.Host = host; obj.Port = port;
            try
                % Large input buffer: 4 ch x 65536 S/s x 3 B ~ 0.8 MB/s.
                obj.Client = tcpclient(host, port, 'Timeout', timeout, 'ConnectTimeout', timeout);
            catch err
                error('tim:lanxi:streamConnect', 'Cannot connect LAN-XI stream socket %s:%d: %s', host, port, err.message);
            end
        end

        function b = read(obj)
            n = obj.Client.NumBytesAvailable;
            if n > 0
                b = read(obj.Client, n, 'uint8');
                obj.BytesRead = obj.BytesRead + n;
            else
                b = zeros(1, 0, 'uint8');
            end
        end

        function close(obj)
            obj.Client = [];
        end

        function delete(obj)
            obj.close();
        end
    end
end
