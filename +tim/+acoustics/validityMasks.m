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
%   The flags and v.valid use BOTH microphone pairs (all four positions).
%
%   Quantity-specific masks:
%     v.validR        R at the front face is B1 e^{jkxF} / (A1 e^{-jkxF}): it
%                     needs ONLY the upstream pair M1/M2. validR = v.upstream.valid:
%                     upstream measured, pair-1 geometry (spacing limits of s1,
%                     mode limit, near-singularity / condition / phase
%                     sensitivity of pair 1), coherence and SNR of positions
%                     1-2, calibration validity of positions 1-2 (o.calValidPos;
%                     all channels when only o.calValid is given), |R| <= 1 +
%                     passivityTol, and complete geometry. Downstream data (a
%                     rigid plug in front of M3/M4, high-TL specimens with low
%                     downstream SNR, a failed calibration of the M3/M4
%                     channels) do not reject R. (Formula review 2026-10-09,
%                     calval-1; review analysis-3.)
%     v.validTau      v.valid & complete geometry & |Rterm| <= anechoicRmax
%     v.validThinZt   v.valid & complete geometry & velocity mismatch <= max
%     v.upstream      the upstream-only masks and flags (measured, geometryOK,
%                     qualityOK, valid, flags); Test D uses geometryOK & qualityOK
%                     without the passivity screen.
%
%   Analysis-band edges are tolerant by 1e-9 relative: a stepped-sine step
%   at fMin / fMax that was rounded a few ulp outside (logspace) counts as
%   inside the band.

f = res.f; Nf = numel(f); k = res.k;
fl = struct();
sUp = res.geometry.spacingUp; sDn = res.geometry.spacingDown;

% 1) measured / analysis band
inBand = true(Nf, 1);
if ~isempty(o.fRange)
    tol = 1e-9 * max(abs(o.fRange));
    inBand = f >= o.fRange(1) - tol & f <= o.fRange(2) + tol;
end
measuredUp = isfinite(res.waves.A1) & isfinite(res.waves.B1) & inBand;
measured = measuredUp & isfinite(res.waves.A2) & isfinite(res.waves.B2);
fl.outsideBand = ~measured;

% 2) geometry
lim = tim.acoustics.frequencyLimits(geom.diameter, [sUp, sDn], res.air, ...
    'LowerFraction', o.lowerFraction, 'UpperFraction', o.upperFraction);
v.limits = lim;
fl.belowSpacingLimit = f < lim.fLower;
fl.aboveSpacingLimit = f > min(lim.upperSpacing);
fl.aboveModeCutOn = f >= min(lim.isoDiameterLimit, lim.cutOn11);
ks = real(k) * [sUp, sDn];
% Proximity to the singularity k*s = n*pi (n >= 1), tested PER PAIR:
% |sin(ks)| < sin(0.2 pi) on the side ks > pi/2 only. The small-ks side
% (|sin ks| small because ks is small) is covered by belowSpacingLimit,
% condMax and phaseSensitive. (A common gate f > c/(4 s_max) used to reject
% well-conditioned low-ks bins of the shorter pair when s_short/s_long < 0.4;
% formula review 2026-10-09, acoustics-2 / calval-3.)
nearSing = abs(sin(ks)) < sin(0.2 * pi) & ks > pi / 2;
fl.nearSingularity = any(nearSing, 2);
fl.illConditioned = res.waves.cond1 > o.condMax | res.waves.cond2 > o.condMax;

% Low-frequency phase sensitivity: a phase error dphi between the two mics
% of a pair produces a relative error of order dphi/(k*s) in the decomposed
% wave amplitudes (small-ks expansion, see docs/theory.md).
phaseSens = o.phaseUncertainty_rad ./ max(ks, eps);     % per pair
v.phaseSensitivity = max(phaseSens, [], 2);             % = dphi / (k * min(s))
fl.phaseSensitive = v.phaseSensitivity > o.maxPhaseSensitivity;
geometryOK = ~(fl.belowSpacingLimit | fl.aboveSpacingLimit | fl.aboveModeCutOn | ...
    fl.nearSingularity | fl.illConditioned | fl.phaseSensitive);

% upstream pair only (R)
up = struct();
up.outsideBand = ~measuredUp;
up.belowSpacingLimit = f < lim.lowerSpacing(1);
up.aboveSpacingLimit = f > lim.upperSpacing(1);
up.aboveModeCutOn = fl.aboveModeCutOn;
up.nearSingularity = nearSing(:, 1);
up.illConditioned = res.waves.cond1 > o.condMax;
up.phaseSensitive = phaseSens(:, 1) > o.maxPhaseSensitivity;
geometryOKup = ~(up.belowSpacingLimit | up.aboveSpacingLimit | up.aboveModeCutOn | ...
    up.nearSingularity | up.illConditioned | up.phaseSensitive);

% 3) quality (columns of o.quality are tube POSITIONS M1..M4)
fl.lowCoherence = false(Nf, 1); fl.lowSNR = false(Nf, 1); fl.calInvalid = false(Nf, 1);
up.lowCoherence = false(Nf, 1); up.lowSNR = false(Nf, 1);
if ~isempty(o.quality)
    if isfield(o.quality, 'coherence') && ~isempty(o.quality.coherence)
        low = o.quality.coherence < o.coherenceMin;
        fl.lowCoherence = any(low, 2);
        up.lowCoherence = any(low(:, 1:2), 2);
    end
    if isfield(o.quality, 'snr_dB') && ~isempty(o.quality.snr_dB)
        low = o.quality.snr_dB < o.snrMin_dB;
        fl.lowSNR = any(low, 2);
        up.lowSNR = any(low(:, 1:2), 2);
    end
end
if isfield(o, 'calValidPos') && ~isempty(o.calValidPos)
    % per position (columns M1..M4): R uses only H1/H2, i.e. C of the channels
    % in M1/M2 (the reference column is always valid). A partial calibration
    % or a failed downstream switching measurement no longer rejects R
    % (review analysis-3).
    fl.calInvalid = ~all(o.calValidPos, 2);
    up.calInvalid = ~all(o.calValidPos(:, 1:2), 2);
elseif ~isempty(o.calValid)
    fl.calInvalid = ~o.calValid(:);
    up.calInvalid = fl.calInvalid;   % all-channel validity only (older callers)
else
    fl.calInvalid = true(Nf, 1);     % no complex calibration -> never "valid"
    up.calInvalid = fl.calInvalid;
end
qualityOK = ~fl.lowCoherence & ~fl.lowSNR & ~fl.calInvalid;
qualityOKup = ~up.lowCoherence & ~up.lowSNR & ~up.calInvalid;

% 4) physical plausibility (passive sample), only where boundary data exist
fl.nonPassive = false(Nf, 1); fl.velocityMismatch = false(Nf, 1); fl.terminationNotAnechoic = false(Nf, 1);
up.nonPassive = false(Nf, 1);
hasB = res.boundary.available;
if hasB
    fl.nonPassive = abs(res.R) > 1 + o.passivityTol | ...
        (abs(res.R).^2 + abs(res.tau).^2 > 1 + o.passivityTol & abs(res.Rterm) <= o.anechoicRmax);
    up.nonPassive = abs(res.R) > 1 + o.passivityTol;     % one-sided: needs only R
    fl.velocityMismatch = res.thin.velocityMismatch > o.velocityMismatchMax;
    fl.terminationNotAnechoic = abs(res.Rterm) > o.anechoicRmax;
end

v.measured = measured;
v.geometryOK = measured & geometryOK;
v.qualityOK = qualityOK;
v.valid = measured & geometryOK & qualityOK & ~fl.nonPassive;
v.upstream = struct('measured', measuredUp, 'geometryOK', measuredUp & geometryOKup, ...
    'qualityOK', qualityOKup, 'valid', measuredUp & geometryOKup & qualityOKup & ~up.nonPassive & hasB, ...
    'flags', up, 'note', ['R needs only the upstream pair M1/M2: masks from pair-1 geometry, ' ...
    'coherence/SNR of positions 1-2, calibration of positions 1-2 and |R| <= 1 + passivityTol.']);
% quantity-specific masks (boundary quantities need the complete geometry;
% v.valid alone then only qualifies the pair-local decomposition)
v.validR = v.upstream.valid;
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
% operator text (messages pane, saved README): glossary terms, no flag identifiers
s = sprintf(['%d frequency lines: %d in the analysis band, %d meet the geometry criteria, %d the quality ' ...
    'criteria; %d valid (R: %d, upstream pair), %d validated by experiment.'], numel(f), nnz(v.measured), ...
    nnz(v.geometryOK), nnz(v.qualityOK), nnz(v.valid), nnz(v.validR), nnz(v.validated));
names = fieldnames(fl);
parts = {};
for i = 1:numel(names)
    n = nnz(fl.(names{i}) & v.measured);
    if n > 0, parts{end+1} = sprintf('%s %d', flagText(names{i}), n); end %#ok<AGROW>
end
if ~isempty(parts), s = [s ' Rejected in the band by: ' strjoin(parts, ', ') '.']; end
end

function t = flagText(name)
% readable name of a rejection flag
switch name
    case 'outsideBand', t = 'outside the analysis band';
    case 'belowSpacingLimit', t = 'below the spacing limit';
    case 'aboveSpacingLimit', t = 'above the spacing limit';
    case 'aboveModeCutOn', t = 'above the (1,1) cut-on';
    case 'nearSingularity', t = 'near the spacing singularity';
    case 'illConditioned', t = 'ill-conditioned decomposition';
    case 'phaseSensitive', t = 'phase sensitivity';
    case 'lowCoherence', t = 'low coherence';
    case 'lowSNR', t = 'low SNR';
    case 'calInvalid', t = 'no valid calibration';
    case 'nonPassive', t = 'not passive';
    case 'terminationNotAnechoic', t = 'termination not anechoic (τ, TL)';
    case 'velocityMismatch', t = 'velocity mismatch (thin-element Zt)';
    otherwise, t = lower(regexprep(name, '([a-z])([A-Z])', '$1 $2'));
end
end
