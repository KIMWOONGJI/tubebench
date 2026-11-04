function out = calOutside(v)
%CALOUTSIDE Lines outside the frequency range of the calibration (1.5.1).
%   out = tim.plots.calOutside(res.analysis.valid)   flags.outsideCalibration
%   out = tim.plots.calOutside(tl.valid)             outsideCalibration (two loads)
%   [] when the result does not carry the flag (saved before 1.5.1). The
%   stepped-sine views draw these lines as hollow diamonds (tim.plots.masked).
out = [];
if isfield(v, 'flags') && isfield(v.flags, 'outsideCalibration')
    out = v.flags.outsideCalibration;
elseif isfield(v, 'outsideCalibration')
    out = v.outsideCalibration;
end
end
