function p = voltsToPascal(v, mics, unit)
%VOLTSTOPASCAL Convert channel voltages to sound pressure (applied ONCE).
%
%   p = tim.acq.voltsToPascal(v, mics, unit)
%   v    (N x C) in volts; column c corresponds to DAQ channel mics(c).channel
%   unit stream unit reported by the LAN-XI Interpretation message; must be
%        'V' (module default transducer, sensitivity 1). If the stream were
%        already in 'Pa', dividing again would apply the sensitivity twice,
%        so this function refuses.

if nargin >= 3
    u = unit; if iscell(u), u = unique(strtrim(u)); else, u = {strtrim(u)}; end
    if ~isequal(u, {'V'})
        error('tim:acq:unit', 'Data unit is "%s", expected "V". Refusing to apply sensitivity twice.', strjoin(u, ','));
    end
end
s = [mics.sensitivity_VperPa];
if numel(s) ~= size(v, 2)
    error('tim:acq:size', 'Need one sensitivity per column.');
end
p = v ./ s;
end
