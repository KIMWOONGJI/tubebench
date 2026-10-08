classdef RecordingStream < handle
    %RECORDINGSTREAM Wraps a stream object and keeps a copy of every raw byte.
    %
    %   Used to preserve the undecoded LAN-XI stream with each measurement
    %   (raw-data preservation; re-decodable later) and to create parser
    %   fixtures from real hardware.

    properties (SetAccess = private)
        Inner
        Chunks cell = {}
    end

    methods
        function obj = RecordingStream(inner)
            obj.Inner = inner;
        end
        function b = read(obj)
            b = obj.Inner.read();
            if ~isempty(b), obj.Chunks{end+1} = b; end
        end
        function close(obj)
            obj.Inner.close();
        end
        function b = bytes(obj)
            if isempty(obj.Chunks)
                b = zeros(1, 0, 'uint8');
            else
                b = [obj.Chunks{:}];
            end
        end
    end
end
