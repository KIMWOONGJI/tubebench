function idx = steppedSegment(meas, r, k)
%STEPPEDSEGMENT Sample indices analysed for step k of repetition r.
%   Starts settleSamples after the frequency command of step k and ends
%   after recordSamples, but never later than the command of step k+1 or
%   the end of the record. Empty if fewer than 100 samples remain.
%   settleSamples / recordSamples hold one value per step (tim.app.steppedPlan)
%   or one value for all steps (measurements saved before 1.5.0).
st = meas.settings; ev = meas.events{r};
x = meas.records{r};
nS = st.settleSamples; nR = st.recordSamples;
if numel(nS) > 1, nS = nS(k); end
if numel(nR) > 1, nR = nR(k); end
i1 = ev.stepStart(k) + nS + 1;
i2 = i1 + nR - 1;
if k < numel(ev.stepStart) && isfinite(ev.stepStart(k + 1))
    i2 = min(i2, ev.stepStart(k + 1));
end
i2 = min(i2, size(x, 1));
if ~isfinite(i1) || i2 - i1 < 100
    idx = [];
else
    idx = i1:i2;
end
end
