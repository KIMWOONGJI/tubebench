function p = steppedPlan(st, fs)
%STEPPEDPLAN Frequencies and per-step timing of a stepped-sine measurement.
%
%   p = tim.app.steppedPlan(st)        times in seconds
%   p = tim.app.steppedPlan(st, fs)    also in samples at the sample rate fs
%
%   st is cfg.excitation.stepped. The output stays on and every step k waits
%   settle(k) after its frequency command, then records record(k):
%       settle(k) = max(settleTime, settleCycles / f_k)
%       record(k) = max(recordTime, recordCycles / f_k)
%   so a step lasts at least the given time and at least the given number of
%   cycles: low frequencies get more time, high frequencies no more than the
%   minimum (owner decision 2026-11-04). A missing or zero settleCycles /
%   recordCycles keeps the fixed time of earlier configurations.
%
%   p.freqs     (1 x n) step frequencies [Hz]: log or lin spacing, end points
%               exactly fStart and fStop
%   p.settle_s, p.record_s, p.step_s   (1 x n) [s]
%   p.pre_s, p.post_s   without excitation before the first and after the last
%                       step (0.5 s each)
%   p.total_s   one repetition
%   with fs: p.settleSamples, p.recordSamples (1 x n), p.preSamples,
%   p.postSamples (rounded to whole samples)

if strcmpi(st.spacing, 'log')
    f = logspace(log10(st.fStart), log10(st.fStop), st.nPoints);
else
    f = linspace(st.fStart, st.fStop, st.nPoints);
end
% exact end points: logspace(log10(120), ...) gives 119.99999999999997 Hz,
% which fell below the analysis band (120 Hz) and was never valid
f([1 end]) = [st.fStart st.fStop];
p = struct('freqs', f);
p.settle_s = max(st.settleTime, cycles(st, 'settleCycles') ./ f);
p.record_s = max(st.recordTime, cycles(st, 'recordCycles') ./ f);
p.step_s = p.settle_s + p.record_s;
p.pre_s = 0.5; p.post_s = 0.5;
p.total_s = p.pre_s + sum(p.step_s) + p.post_s;
if nargin > 1
    p.settleSamples = round(p.settle_s * fs);
    p.recordSamples = round(p.record_s * fs);
    p.preSamples = round(p.pre_s * fs);
    p.postSamples = round(p.post_s * fs);
end
end

function n = cycles(st, name)
n = 0;
if isfield(st, name) && ~isempty(st.(name)), n = double(st.(name)); end
end
