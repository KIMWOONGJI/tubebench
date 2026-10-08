function out = sweepResponse(records, fs, opts)
%SWEEPRESPONSE Relative microphone responses from swept-sine recordings.
%
%   out = tim.dsp.sweepResponse(records, fs, opts)
%
%   records : cell array of (N x C) recordings (one cell per sweep
%             repetition), volts, all channels on the SAME DAQ clock
%   opts    : refChannel (1), fRange [f1 f2] of the analysis grid,
%             df (output resolution, Hz, default 2), fGrid (explicit grid,
%             overrides df), preRoll (s, nominal, for noise estimation),
%             excitationBand [fmin fmax] (sweep range), taper (s, 0.01),
%             ringDown (s kept after detected end, default 0.5)
%
%   METHOD (docs/theory.md, "Swept-sine estimator without generator sync")
%   The generator and the DAQ do not share a clock and the 33220A sweep is
%   stepped and not an ideal exponential chirp. The estimator therefore
%   never uses the excitation signal. Because the tube is linear and all
%   microphones are sampled by the same DAQ clock, for every frequency
%       Y_c(f) = P(x_c, f) * Chain_c(f) * S(f)
%   where S(f) is the (unknown) spectrum of the loudspeaker drive. The ratio
%   Y_c / Y_ref is independent of S(f): of its waveform, its exact start
%   time, the generator clock offset, loudspeaker distortion products (they
%   are acoustic excitation at their own frequency too) and of the start-
%   frequency tone emitted before/after the sweep. Per repetition r:
%       G_cr(f) = Y_c Y_ref^*,   G_rr(f) = |Y_ref|^2,   G_cc(f) = |Y_c|^2
%   summed over repetitions AND over the FFT bins inside each output band
%   (band width df):
%       H_c  = sum G_cr / sum G_rr                 (H1 estimator)
%       g2_c = |sum G_cr|^2 / (sum G_rr * sum G_cc) (consistency / coherence)
%   The record of each repetition is cut from (detected start - taper) to
%   (detected end + ringDown) with short raised-cosine tapers, so the
%   acoustic ring-down is included and leakage from truncation is confined
%   to the tapers (where the signal has decayed).
%   SNR per band: signal energy vs. the expected energy of the background
%   noise measured in the pre-roll (same window, same length).
%
%   out fields: f, H (Nf x C, H(:,ref) = 1), coherence, snr_dB, nAvg,
%   excitation (per repetition: detected start/end/duration), noisePSD,
%   method, options.

arguments
    records
    fs (1,1) double {mustBePositive}
    opts struct = struct()
end
if ~iscell(records), records = {records}; end
o = defaults(opts, struct('refChannel', 1, 'fRange', [100 5000], 'df', 2, 'fGrid', [], ...
    'preRoll', 0.5, 'excitationBand', [], 'taper', 0.01, 'ringDown', 0.5, 'detectThreshold_dB', 12));
C = size(records{1}, 2);
ref = o.refChannel;
if isempty(o.fGrid)
    fGrid = (o.fRange(1):o.df:o.fRange(2)).';
else
    % explicit (possibly sparse) grid: band of width df around each point;
    % bands must not overlap
    fGrid = o.fGrid(:);
    if any(diff(fGrid) < o.df)
        error('tim:dsp:grid', 'fGrid spacing must be >= df (%.3g Hz).', o.df);
    end
end
if isempty(o.excitationBand), o.excitationBand = [min(fGrid) max(fGrid)]; end

nB = numel(fGrid);
Scr = zeros(nB, C); Srr = zeros(nB, 1); Scc = zeros(nB, C);
SccN = zeros(nB, C); Enoise = zeros(nB, C);   % SNR only from reps with a noise estimate
nAvg = zeros(nB, 1); nNoiseReps = 0;
excit = struct('start_s', {}, 'end_s', {}, 'duration_s', {}, 'noiseRms', {}, 'peakRms', {}, 'detected', {});

for r = 1:numel(records)
    x = records{r};
    x = x - mean(x, 1);
    ex = tim.dsp.detectExcitation(x(:, ref), fs, o.excitationBand, o.detectThreshold_dB, o.preRoll);
    excit(r) = ex; %#ok<AGROW>
    % ---- segment and window
    if ex.detected
        i1 = max(1, round((ex.start_s - o.taper) * fs) + 1);
        i2 = min(size(x, 1), round((ex.end_s + o.ringDown) * fs));
    else
        i1 = 1; i2 = size(x, 1);
    end
    seg = x(i1:i2, :);
    L = size(seg, 1);
    w = tukeyTaper(L, round(o.taper * fs));
    nfft = 2^nextpow2(L);
    Y = fft(seg .* w, nfft);
    fb = (0:nfft/2).' * fs / nfft;
    Y = Y(1:nfft/2 + 1, :);
    % ---- noise estimate from pre-roll (before excitation)
    nNoise = 0;
    if ex.detected
        nNoise = round((ex.start_s - 0.02) * fs);
    end
    if nNoise >= round(0.1 * fs)
        nseg = min(nNoise, 2^nextpow2(round(0.1 * fs)));
        [Pn, fn] = pwelch(x(1:nNoise, :), hann(nseg, 'periodic'), round(nseg/2), nseg, fs);   % one-sided V^2/Hz
        Gn = interp1(fn, Pn, fb, 'linear', 'extrap');
        noiseE = max(Gn, 0) / 2 * fs * sum(w.^2);       % expected |Y|^2 of noise
    else
        noiseE = nan(numel(fb), C);
    end
    % ---- accumulate into output bands [fGrid - df/2, fGrid + df/2)
    if nB == 1
        near = ones(size(fb));
    else
        near = interp1(fGrid, (1:nB).', fb, 'nearest', 'extrap');
    end
    dist = fb - fGrid(near);
    ok = abs(dist) < o.df / 2 | dist == -o.df / 2;    % half-open band [f-df/2, f+df/2)
    b = near(ok);
    Yr = Y(ok, ref);
    hasNoise = all(isfinite(noiseE(:)));
    for c = 1:C
        Scr(:, c) = Scr(:, c) + accumarray(b, Y(ok, c) .* conj(Yr), [nB 1]);
        Scc(:, c) = Scc(:, c) + accumarray(b, abs(Y(ok, c)).^2, [nB 1]);
        if hasNoise
            SccN(:, c) = SccN(:, c) + accumarray(b, abs(Y(ok, c)).^2, [nB 1]);
            Enoise(:, c) = Enoise(:, c) + accumarray(b, noiseE(ok, c), [nB 1]);
        end
    end
    nNoiseReps = nNoiseReps + hasNoise;
    Srr = Srr + accumarray(b, abs(Yr).^2, [nB 1]);
    nAvg = nAvg + accumarray(b, 1, [nB 1]);
end

H = Scr ./ Srr;
H(:, ref) = 1;
coh = abs(Scr).^2 ./ (Srr .* Scc);
coh(:, ref) = 1;
if nNoiseReps > 0
    % floor at -40 dB: when the noise estimate exceeds the total energy the
    % band is noise-dominated; a value like -168 dB would only be an artefact
    snr = 10 * log10(max(SccN - Enoise, 1e-4 * Enoise) ./ Enoise);
else
    snr = nan(nB, C);     % no noise-only pre-roll available
end
out = struct('f', fGrid, 'H', H, 'coherence', coh, 'snr_dB', snr, 'nAvg', nAvg, ...
    'excitation', excit, 'refChannel', ref, 'options', o, ...
    'method', 'ratio of channel spectra (H1, band- and repetition-averaged); excitation-independent');
out.nNoiseReps = nNoiseReps;
out.warnings = {};
if numel(records) == 1 && max(nAvg) < 2
    out.warnings{end+1} = 'Single repetition and single bin per band: coherence is trivially 1 and not informative.';
end
if nNoiseReps < numel(records)
    out.warnings{end+1} = sprintf(['SNR estimated from %d of %d repetitions (the others had no ' ...
        'noise-only pre-roll >= 0.1 s before the detected excitation).'], nNoiseReps, numel(records));
end
end

function w = tukeyTaper(L, nt)
w = ones(L, 1);
nt = min(nt, floor(L / 2));
if nt > 0
    r = 0.5 * (1 - cos(pi * (0:nt-1).' / nt));
    w(1:nt) = r; w(end-nt+1:end) = flipud(r);
end
end

function o = defaults(o, d)
f = fieldnames(d);
for i = 1:numel(f)
    if ~isfield(o, f{i}), o.(f{i}) = d.(f{i}); end
end
end
