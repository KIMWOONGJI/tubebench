function bytes = lanxiEncode(kind, varargin)
%LANXIENCODE Build synthetic LAN-XI Open API stream messages (test fixtures).
%
%   b = tim.sim.lanxiEncode('interpretation', signalIds, scaleFactor, fs, unit, t)
%   b = tim.sim.lanxiEncode('signal', signalIds, int24Values(cell), t)
%   b = tim.sim.lanxiEncode('quality', signalIds, flags, t)
%   b = tim.sim.lanxiEncode('aux', t)
%
%   Encoding follows docs/ref_lanxi_openapi.md (little endian, 28-byte
%   header, int24 samples, 4-byte padded interpretation descriptors).
%
%   TIME FAMILY: messages are stamped with family (k,l,m,n) = (21,0,0,0),
%   i.e. 2^21 ticks/s, which represents any sample rate 2^n Hz exactly.
%   t is the message time in seconds.
%
%   int24 values must be integers in [-2^23, 2^23-1].

switch kind
    case 'interpretation'
        [ids, scale, fs, unit, t] = varargin{:};
        c = zeros(1, 0, 'uint8');
        for id = ids(:).'
            c = [c, descr(id, 1, u16(3))];                       %#ok<AGROW> DataType Int24
            c = [c, descr(id, 2, typecast(double(scale(min(id, end))), 'uint8'))]; %#ok<AGROW>
            c = [c, descr(id, 3, typecast(0, 'uint8'))];         %#ok<AGROW>
            c = [c, descr(id, 4, timeBytes(1 / fs))];            %#ok<AGROW>
            ub = unicode2native(unit, 'UTF-8');
            c = [c, descr(id, 5, [u16(numel(ub)), ub])];         %#ok<AGROW>
            c = [c, descr(id, 6, u16(0))];                       %#ok<AGROW>
            c = [c, descr(id, 7, u16(1))];                       %#ok<AGROW>
        end
        bytes = [header(8, t, numel(c)), c];
    case 'signal'
        [ids, vals, t] = varargin{:};
        c = [u16(numel(ids)), u16(0)];
        for i = 1:numel(ids)
            v = int32(round(vals{i}(:).'));
            if any(v < -2^23 | v > 2^23 - 1)
                error('tim:sim:int24', 'Value outside int24 range.');
            end
            b4 = reshape(typecast(v, 'uint8'), 4, []);
            c = [c, typecast(int16(ids(i)), 'uint8'), typecast(int16(numel(v)), 'uint8'), ...
                reshape(b4(1:3, :), 1, [])]; %#ok<AGROW>
        end
        bytes = [header(1, t, numel(c)), c];
    case 'quality'
        [ids, flags, t] = varargin{:};
        c = u16(numel(ids));
        for i = 1:numel(ids)
            c = [c, u16(ids(i)), u16(flags(i)), u16(4)]; %#ok<AGROW>
        end
        bytes = [header(2, t, numel(c)), c];
    case 'aux'
        t = varargin{1};
        c = uint8([1 2 3 4]);
        bytes = [header(11, t, numel(c)), c];
    otherwise
        error('tim:sim:kind', 'Unknown message kind "%s".', kind);
end
end

function b = u16(x), b = typecast(uint16(x), 'uint8'); end

function b = timeBytes(tsec)
fam = uint8([21 0 0 0]);
b = [fam, typecast(uint64(round(tsec * 2^21)), 'uint8')];
end

function b = header(type, t, len)
b = [uint8('BK'), u16(20), u16(type), u16(0), typecast(uint32(0), 'uint8'), ...
    timeBytes(t), typecast(uint32(len), 'uint8')];
end

function d = descr(id, type, value)
% descriptor: id, type, reserved, valueLength, value, pad to 4 bytes.
% Header (8 bytes) is 4-aligned, so padding depends on value length only
% when every descriptor starts 4-aligned (which this encoder guarantees).
d = [u16(id), u16(type), u16(0), u16(numel(value)), value];
pad = mod(4 - mod(numel(d), 4), 4);
d = [d, zeros(1, pad, 'uint8')];
end
