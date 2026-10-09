function g = analysisGate(res)
%ANALYSISGATE Analysed part of repetition 1 of a swept-sine result.
%   g = tim.plots.analysisGate(res)  ->  [tA tB tC tD] in s (sweep gate of
%   tim.dsp.sweepResponse: window 0 before tA and after tD, ramps tA-tB and
%   tC-tD), or [] when the sweep was not gated (other signals, older results).
%   Used by the Time signals view (opts.gate of tim.plots.timeSignals).
g = [];
if isstruct(res) && isfield(res, 'spectra') && isstruct(res.spectra) && isfield(res.spectra, 'excitation') ...
        && isstruct(res.spectra.excitation) && ~isempty(res.spectra.excitation) ...
        && isfield(res.spectra.excitation, 'gated') && res.spectra.excitation(1).gated
    g = res.spectra.excitation(1).gate_s;
end
end
