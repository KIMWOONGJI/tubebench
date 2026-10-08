function r = switchingCorrection(f, HI, HII, opts)
%SWITCHINGCORRECTION Complex channel mismatch from a sensor-switching pair.
%
%   r = tim.cal.switchingCorrection(f, HI, HII, opts)
%
%   DERIVATION (docs/calibration_procedure.md). Let c_ref(f) and c_k(f) be the
%   complete complex responses (microphone + preamplifier + cable + DAQ
%   channel) of the reference chain and chain k, and p_a, p_b the sound
%   pressures at the two calibration positions a and b.
%     Configuration I : chain ref at a, chain k at b
%         HI  = Y_k / Y_ref = (c_k p_b) / (c_ref p_a)
%     Configuration II: microphones physically interchanged (each stays on
%                       its own cable/channel): chain ref at b, chain k at a
%         HII = Y_k / Y_ref = (c_k p_a) / (c_ref p_b)
%   Hence
%     HI * HII = (c_k / c_ref)^2        ->  Hc   = c_k / c_ref = +-sqrt(HI*HII)
%     HI / HII = (p_b / p_a)^2          ->  Hpos = p_b / p_a   = +-sqrt(HI/HII)
%   Both square roots are determined only up to sign (phase ambiguity of pi).
%   BRANCH SELECTION: the phase of HI*HII is unwrapped along frequency over
%   the valid bins (starting at the lowest valid frequency) and halved; the
%   integer multiple of pi is then chosen so that the median phase of Hc over
%   the lowest-frequency valid decade-fraction is closest to 0 - i.e. it is
%   ASSUMED that two chains of the same microphone type do not differ by
%   more than +-90 deg in phase at low frequency (true for matched 4957 chains,
%   a few degrees; see validity checks). The same rule is applied to Hpos
%   (|k s| < pi/2 between the calibration positions at low frequency).
%   Bins that are invalid (low coherence/SNR) are excluded from unwrapping
%   and receive linearly interpolated phase, but stay flagged invalid.
%
%   Inputs: f (Nf x 1); HI, HII (Nf x 1) complex; opts:
%     cohI, cohII (Nf x 1) coherence; snrI, snrII (dB); coherenceMin (0.98);
%     snrMin_dB (20); HIrepeat (Nf x 1, repeated configuration I after
%     re-mounting, optional); maxPhase_deg (45) plausibility; magRange [0.5 2]
%   Output r: Hc, Hpos, valid, plausible, repeatability, notes

arguments
    f (:,1) double
    HI (:,1) double
    HII (:,1) double
    opts struct = struct()
end
o = struct('cohI', [], 'cohII', [], 'snrI', [], 'snrII', [], 'coherenceMin', 0.98, ...
    'snrMin_dB', 20, 'HIrepeat', [], 'maxPhase_deg', 45, 'magRange', [0.5 2], 'lowBandFraction', 0.1);
fn = fieldnames(opts); for i = 1:numel(fn), o.(fn{i}) = opts.(fn{i}); end
Nf = numel(f);

valid = isfinite(HI) & isfinite(HII) & abs(HI) > 0 & abs(HII) > 0;
if ~isempty(o.cohI),  valid = valid & o.cohI(:)  >= o.coherenceMin; end
if ~isempty(o.cohII), valid = valid & o.cohII(:) >= o.coherenceMin; end
if ~isempty(o.snrI),  valid = valid & o.snrI(:)  >= o.snrMin_dB; end
if ~isempty(o.snrII), valid = valid & o.snrII(:) >= o.snrMin_dB; end

if nnz(valid) < 2
    error('tim:cal:noValidBins', 'Calibration has fewer than 2 valid frequency bins.');
end

prod = HI .* HII;
quot = HI ./ HII;
phC = halfPhase(f, prod, valid, o.lowBandFraction);
phP = halfPhase(f, quot, valid, o.lowBandFraction);
Hc = sqrt(abs(prod)) .* exp(1j * phC);
Hpos = sqrt(abs(quot)) .* exp(1j * phP);

plausible = abs(Hc) >= o.magRange(1) & abs(Hc) <= o.magRange(2) & ...
    abs(rad2deg(phC)) <= o.maxPhase_deg;
r = struct('f', f, 'Hc', Hc, 'Hpos', Hpos, 'valid', valid & plausible, ...
    'validSignal', valid, 'plausible', plausible, 'notes', {{}});
if any(valid & ~plausible)
    r.notes{end+1} = sprintf(['%d bins have implausible mismatch (|Hc| outside [%.2g %.2g] or ' ...
        '|phase| > %g deg): check wiring, swapped connectors or leakage.'], ...
        nnz(valid & ~plausible), o.magRange(1), o.magRange(2), o.maxPhase_deg);
end

% Repeatability after physically re-mounting (configuration I measured twice)
if ~isempty(o.HIrepeat)
    d = o.HIrepeat(:) ./ HI;
    r.repeatability = struct('magDiff_dB', 20 * log10(abs(d)), 'phaseDiff_deg', rad2deg(angle(d)), ...
        'maxMag_dB', max(abs(20 * log10(abs(d(valid))))), 'maxPhase_deg', max(abs(rad2deg(angle(d(valid))))));
else
    r.repeatability = [];
end
r.nValid = nnz(r.valid);
r.Nf = Nf;
end

function ph = halfPhase(f, z, valid, lowFrac)
% Unwrap phase of z on valid bins only, halve, choose the pi-branch closest
% to zero at low frequency; interpolate across invalid bins.
iv = find(valid);
phv = unwrap(angle(z(iv))) / 2;
fv = f(iv);
fLow = fv(1) + lowFrac * (fv(end) - fv(1));
low = fv <= max(fLow, fv(min(5, end)));
m = median(phv(low));
phv = phv - pi * round(m / pi);
ph = interp1(fv, phv, f, 'linear', 'extrap');
end
