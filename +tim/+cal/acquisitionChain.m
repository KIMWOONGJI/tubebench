function ch = acquisitionChain(daq, acquisition, fs)
%ACQUISITIONCHAIN The DAQ input chain that a switching calibration depends on.
%
%   ch = tim.cal.acquisitionChain(md.daq, md.acquisition, fs)
%   ch = tim.cal.acquisitionChain(session.Daq.metadata(), cfg.acquisition, fs)
%
%   C_k = g_k / g_ref is a ratio of chain gains that include the DAQ inputs,
%   so a calibration holds only for the module and input settings it was
%   made with. ch: driver, displayName, model, serial, firmware (text, '' =
%   unknown), sampleRate [S/s] (NaN = unknown), range, filter ('' = unknown),
%   ccld (logical row, [] = unknown). Stored as cal.meta.acquisition by
%   tim.app.runCalibration and compared by tim.cal.calibrationContext.
%   daq: the metadata() of the acquisition driver (md.daq of a measurement).
%   Metadata saved before 1.2.0 has no driver and no identity: the model,
%   serial (numeric) and firmware come from md.daq.model / serial / firmware.

ch = struct('driver', '', 'displayName', '', 'model', '', 'serial', '', 'firmware', '', ...
    'sampleRate', NaN, 'range', '', 'filter', '', 'ccld', []);
if isstruct(daq) && isscalar(daq)
    if isfield(daq, 'driver'), ch.driver = text(daq.driver); end
    if isfield(daq, 'displayName'), ch.displayName = text(daq.displayName); end
    id = daq;                                         % before 1.2.0: model, serial, firmware
    if isfield(daq, 'identity') && isstruct(daq.identity) && isscalar(daq.identity), id = daq.identity; end
    for f = {'model', 'serial', 'firmware'}
        if isfield(id, f{1}), ch.(f{1}) = text(id.(f{1})); end
    end
end
if isstruct(acquisition) && isscalar(acquisition)
    if isfield(acquisition, 'sampleRate') && isnumeric(acquisition.sampleRate) && isscalar(acquisition.sampleRate)
        ch.sampleRate = acquisition.sampleRate;
    end
    if isfield(acquisition, 'range'), ch.range = text(acquisition.range); end
    if isfield(acquisition, 'filter'), ch.filter = text(acquisition.filter); end
    if isfield(acquisition, 'ccld') && ~isempty(acquisition.ccld), ch.ccld = logical(acquisition.ccld(:).'); end
end
if nargin >= 3 && isnumeric(fs) && isscalar(fs) && isfinite(fs), ch.sampleRate = fs; end
end

function t = text(v)
% a value as text for comparisons ('' = unknown); numeric serials with num2str
if ischar(v)
    t = strtrim(v);
elseif isstring(v) && isscalar(v)
    t = strtrim(char(v));
elseif isnumeric(v) && isscalar(v) && isfinite(v)
    t = num2str(v);
else
    t = '';
end
end
