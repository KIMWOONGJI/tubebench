function [g, ends] = analysisGate(res)
%ANALYSISGATE Analysed part of repetition 1 of a swept-sine result.
%   [g, ends] = tim.plots.analysisGate(res)  ->  g = [tA tB tC tD] in s (sweep
%   gate of tim.dsp.sweepResponse: window 0 before tA and after tD, ramps tA-tB
%   and tC-tD), or [] when the sweep was not gated (other signals, older
%   results); ends = {lower, upper}, the edge used at each end
%   (excitation.gateEnds: 'gate', 'detected start' or 'ring-down margin'),
%   {} when not recorded (results before 2026-10-11: the gate at both ends).
%   Used by the Time signals view (opts.gate and opts.gateEnds of
%   tim.plots.timeSignals).
g = []; ends = {};
if isstruct(res) && isfield(res, 'spectra') && isstruct(res.spectra) && isfield(res.spectra, 'excitation') ...
        && isstruct(res.spectra.excitation) && ~isempty(res.spectra.excitation) ...
        && isfield(res.spectra.excitation, 'gated') && res.spectra.excitation(1).gated
    g = res.spectra.excitation(1).gate_s;
    if isfield(res.spectra.excitation, 'gateEnds') && iscell(res.spectra.excitation(1).gateEnds) ...
            && numel(res.spectra.excitation(1).gateEnds) == 2
        ends = res.spectra.excitation(1).gateEnds;
    end
end
end
