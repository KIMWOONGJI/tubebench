function v = validityMasks(res, geom, o)
%VALIDITYMASKS Per-frequency validity diagnostics for a four-mic analysis.
%
%   v = tim.acoustics.validityMasks(res, geom, o)   (called by analyzeFourMic)
%
%   Three levels are kept strictly separate:
%     v.measured      frequencies present in the data / analysis band
%     v.geometryOK    permitted by tube geometry (spacing limits, mode cut-on,
%                     decomposition conditioning)
%     v.qualityOK     signal quality (coherence, SNR) and calibration validity
%     v.valid         measured & geometryOK & qualityOK & physical checks
%     v.validated     subset of v.valid inside experimentally validated bands
%                     (empty bands -> nothing is "validated")
%   Every reason a bin is rejected is recorded in v.flags (logical columns).

f = res.f; Nf = numel(f); k = res.k;
fl = struct();

% 1) measured / analysis band
measured = all(isfinite(res.waves.A1), 2) & isfinite(res.waves.A2);
if ~isempty(o.fRange)
    measured = measured & f >= o.fRange(1) & f <= o.fRange(2);
end
fl.outsideBand = ~measured;

% 2) geometry
lim = tim.acoustics.frequencyLimits(geom.diameter, ...
    [res.geometry.spacingUp, res.geometry.spacingDown], res.air, ...
    'LowerFraction', o.lowerFraction, 'UpperFraction', o.upperFraction);
v.limits = lim;
fl.belowSpacingLimit = f < lim.fLower;
fl.aboveSpacingLimit = f > min(lim.upperSpacing);
fl.aboveModeCutOn = f >= min(lim.isoDiameterLimit, lim.cutOn11);
ks = real(k) * [res.geometry.spacingUp, res.geometry.spacingDown];
fl.nearSingularity = any(abs(sin(ks)) < sin(0.2 * pi), 2) & f > 0.5 * min(lim.singular);
fl.illConditioned = res.waves.cond1 > o.condMax | res.waves.cond2 > o.condMax;
geometryOK = ~(fl.belowSpacingLimit | fl.aboveSpacingLimit | fl.aboveModeCutOn | ...
    fl.nearSingularity | fl.illConditioned);

% Low-frequency phase sensitivity: a phase error dphi between the two mics
% of a pair produces a relative error of order dphi/(k*s) in the decomposed
% wave amplitudes (small-ks expansion, see docs/theory.md).
v.phaseSensitivity = o.phaseUncertainty_rad ./ max(min(ks, [], 2), eps);
fl.phaseSensitive = v.phaseSensitivity > o.maxPhaseSensitivity;
geometryOK = geometryOK & ~fl.phaseSensitive;

% 3) quality
qualityOK = true(Nf, 1);
fl.lowCoherence = false(Nf, 1); fl.lowSNR = false(Nf, 1); fl.calInvalid = false(Nf, 1);
if ~isempty(o.quality)
    if isfield(o.quality, 'coherence') && ~isempty(o.quality.coherence)
        fl.lowCoherence = any(o.quality.coherence < o.coherenceMin, 2);
    end
    if isfield(o.quality, 'snr_dB') && ~isempty(o.quality.snr_dB)
        fl.lowSNR = any(o.quality.snr_dB < o.snrMin_dB, 2);
    end
end
if ~isempty(o.calValid)
    fl.calInvalid = ~o.calValid(:);
else
    fl.calInvalid = true(Nf, 1);   % no complex calibration -> never "valid"
end
qualityOK = qualityOK & ~fl.lowCoherence & ~fl.lowSNR & ~fl.calInvalid;

% 4) physical plausibility (passive sample), only where boundary data exist
fl.nonPassive = false(Nf, 1); fl.velocityMismatch = false(Nf, 1); fl.terminationNotAnechoic = false(Nf, 1);
if res.boundary.available
    fl.nonPassive = abs(res.R) > 1 + o.passivityTol | ...
        (abs(res.R).^2 + abs(res.tau).^2 > 1 + o.passivityTol & abs(res.Rterm) <= o.anechoicRmax);
    fl.velocityMismatch = res.thin.velocityMismatch > o.velocityMismatchMax;
    fl.terminationNotAnechoic = abs(res.Rterm) > o.anechoicRmax;
end

v.measured = measured;
v.geometryOK = measured & geometryOK;
v.qualityOK = qualityOK;
v.valid = measured & geometryOK & qualityOK & ~fl.nonPassive;
% quantity-specific masks (boundary quantities need the complete geometry;
% v.valid alone then only qualifies the pair-local decomposition)
hasB = res.boundary.available;
v.validR = v.valid & hasB;
v.validTau = v.valid & hasB & ~fl.terminationNotAnechoic;
v.validThinZt = v.valid & hasB & ~fl.velocityMismatch;
v.validated = false(Nf, 1);
for i = 1:size(o.validatedBands, 1)
    v.validated = v.validated | (f >= o.validatedBands(i,1) & f <= o.validatedBands(i,2));
end
v.validated = v.validated & v.valid;
v.flags = fl;
v.summary = summarize(f, v, fl);
end

function s = summarize(f, v, fl)
s = sprintf('%d bins: %d measured, %d geometry-permitted, %d quality-OK, %d valid, %d experimentally validated.', ...
    numel(f), nnz(v.measured), nnz(v.geometryOK), nnz(v.qualityOK), nnz(v.valid), nnz(v.validated));
names = fieldnames(fl);
parts = {};
for i = 1:numel(names)
    n = nnz(fl.(names{i}) & v.measured);
    if n > 0, parts{end+1} = sprintf('%s=%d', names{i}, n); end %#ok<AGROW>
end
if ~isempty(parts), s = [s ' Rejections in band: ' strjoin(parts, ', ') '.']; end
end
