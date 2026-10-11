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
%             ringDown (s kept after detected end, default 0.5),
%             sweep (struct fStart, fStop, duration, spacing of the generator
%             sweep; enables the sweep gate below), excludeSwitching (true)
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
%   summed over repetitions AND over the FFT bins inside each frequency line,
%   the band [f - df/2, f + df/2] SYMMETRIC about its frequency f: a bin
%   exactly on an edge f +/- df/2 counts with weight 1/2 in both lines that
%   share it (nAvg sums the weights). Until 2026-10-11 the band was
%   half-open, [f - df/2, f + df/2), centred at f - fs/nfft/2 (audit).
%       H_c  = sum G_cr / sum G_rr                 (H1 estimator)
%       g2_c = |sum G_cr|^2 / (sum G_rr * sum G_cc) (consistency / coherence)
%   SWEEP GATE (opts.sweep given, excludeSwitching true): the generator
%   output relay clicks when the output is switched on (before the sweep
%   starts; the start-frequency tone follows) and off (after the sweep;
%   the 33220A also jumps back to the start frequency at the end of the
%   sweep). These transients are not part of the sweep and are excluded:
%   the actual sweep start t0 and duration T of every repetition are found
%   by a matched filter (tim.dsp.estimateSweepLaw) and the window is
%       0 before tA = t(max(fStart, fLo/1.5)), raised cosine up to
%       tB = t(max(fStart, fLo/1.1)), 1 up to tC = t(min(fStop, 1.1 fHi)),
%       raised cosine down to tD = t(min(fStop, 1.5 fHi))
%   with t(f) the time of frequency f on the sweep and [fLo fHi] the
%   analysis band: the window edges lie in the part of the sweep outside
%   the band (long, smooth ramps: no truncation leakage into the band) and
%   the band keeps its ring-down (at least the time from fHi to 1.1 fHi).
%   Ramps shorter than 'taper' are widened to 'taper' inside the sweep.
%   AN END WITHOUT THE MARGIN (owner decision 2026-10-11): when the sweep
%   starts above fLo/1.3 or stops below 1.1 fHi, the gate would put its ramp
%   on the band edge there (biased lines with a high coherence). That end of
%   the window is then
%       start: as without the gate, from the detected start - taper (raised
%              cosine; the output-on transient and the start tone included);
%       end:   extended past the sweep end t0+T by the gate's ring-down
%              margin, the sweep law continued beyond fStop: 1 up to
%              t(1.1 fHi), raised cosine down to t(1.5 fHi) (at least
%              'taper', at most the end of the record), so a later
%              output-off transient stays out.
%   excitation.gateEnds names the edge used per repetition ('gate',
%   'detected start', 'ring-down margin') and a warning says so. If the
%   sweep is not found reliably the record is cut as below and a warning
%   says so.
%   Without the gate the record of each repetition is cut from (detected
%   start - taper) to (detected end + ringDown) with short raised-cosine
%   tapers, so the acoustic ring-down is included and leakage from
%   truncation is confined to the tapers (where the signal has decayed).
%   SNR per band: signal energy vs. the expected energy of the background
%   noise measured in the pre-roll (same window, same length).
%
%   out fields: f, H (Nf x C, H(:,ref) = 1), coherence, snr_dB, nAvg,
%   excitation (per repetition: detected start/end/duration, gated,
%   sweepStart_s, sweepDuration_s, gate_s, gateEnds {lower, upper}),
%   method, options, warnings.

arguments
    records
    fs (1,1) double {mustBePositive}
    opts struct = struct()
end
if ~iscell(records), records = {records}; end
o = defaults(opts, struct('refChannel', 1, 'fRange', [100 5000], 'df', 2, 'fGrid', [], ...
    'preRoll', 0.5, 'excitationBand', [], 'taper', 0.01, 'ringDown', 0.5, 'detectThreshold_dB', 12, ...
    'sweep', [], 'excludeSwitching', true));
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
excit = struct('start_s', {}, 'end_s', {}, 'duration_s', {}, 'noiseRms', {}, 'peakRms', {}, 'detected', {}, ...
    'gated', {}, 'sweepStart_s', {}, 'sweepDuration_s', {}, 'gate_s', {}, 'gateEnds', {});
useGate = o.excludeSwitching && isstruct(o.sweep) && ~isempty(o.sweep);
gateWarn = [];
band = [min(fGrid) - o.df / 2, max(fGrid) + o.df / 2];

for r = 1:numel(records)
    x = records{r};
    x = x - mean(x, 1);
    ex = tim.dsp.detectExcitation(x(:, ref), fs, o.excitationBand, o.detectThreshold_dB, o.preRoll);
    ex.gated = false; ex.sweepStart_s = NaN; ex.sweepDuration_s = NaN; ex.gate_s = nan(1, 4);
    ex.gateEnds = {'', ''};
    % ---- segment and window
    g = [];
    if useGate && ex.detected
        g = sweepGate(x(:, ref), fs, o.sweep, band, o.taper, ex);
    end
    if ~isempty(g)
        ex.gated = true; ex.sweepStart_s = g.t0; ex.sweepDuration_s = g.T; ex.gate_s = g.t;
        ex.gateEnds = g.ends;
        i1 = max(1, floor(g.t(1) * fs) + 1);
        i2 = min(size(x, 1), ceil(g.t(4) * fs));
        tt = (i1 - 1:i2 - 1).' / fs;
        w = gateWindow(tt, g.t);
    else
        if useGate, gateWarn(end + 1) = r; end %#ok<AGROW>
        if ex.detected
            i1 = max(1, round((ex.start_s - o.taper) * fs) + 1);
            i2 = min(size(x, 1), round((ex.end_s + o.ringDown) * fs));
        else
            i1 = 1; i2 = size(x, 1);
        end
        w = tukeyTaper(i2 - i1 + 1, round(o.taper * fs));
    end
    excit(r) = ex; %#ok<AGROW>
    seg = x(i1:i2, :);
    L = size(seg, 1);
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
    % ---- accumulate into the frequency lines [fGrid - df/2, fGrid + df/2],
    % symmetric about fGrid: bin ib goes to line b with weight wb (1/2 on an edge)
    [ib, b, wb] = lineWeights(fb, fGrid, o.df);
    Yr = Y(ib, ref);
    hasNoise = all(isfinite(noiseE(:)));
    for c = 1:C
        Scr(:, c) = Scr(:, c) + accumarray(b, wb .* Y(ib, c) .* conj(Yr), [nB 1]);
        Scc(:, c) = Scc(:, c) + accumarray(b, wb .* abs(Y(ib, c)).^2, [nB 1]);
        if hasNoise
            SccN(:, c) = SccN(:, c) + accumarray(b, wb .* abs(Y(ib, c)).^2, [nB 1]);
            Enoise(:, c) = Enoise(:, c) + accumarray(b, wb .* noiseE(ib, c), [nB 1]);
        end
    end
    nNoiseReps = nNoiseReps + hasNoise;
    Srr = Srr + accumarray(b, wb .* abs(Yr).^2, [nB 1]);
    nAvg = nAvg + accumarray(b, wb, [nB 1]);
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
if ~isempty(gateWarn)
    out.warnings{end+1} = sprintf(['Sweep not found reliably in repetition(s) %s: the generator on/off ' ...
        'transients are not excluded there (window from the detected excitation).'], mat2str(gateWarn));
end
if any([excit.gated])
    m = sweepMargin(o.sweep, band);
    if ~isempty(m)
        out.warnings{end+1} = m;
    end
end
end

function [lo, hi] = noMargin(sw, band)
% the sweep gate needs the sweep to reach beyond the analysis band: below it
% the ramp from f_lo/1.5 to f_lo/1.1 (shortened to less than half, the
% start-frequency tone cut close to the band), above it the ring-down margin
% up to 1.1 f_hi. Without that room the gated lines near the band edge were
% biased with a high coherence (simulation, |R_term| = 0.9, 120-4500 Hz: up
% to 13 % at a 109 Hz start, 8 % at a 4600 Hz stop, 58 % for 120-4500 Hz;
% audit 2026-10-11); such an end gets another edge (sweepGate)
lo = sw.fStart > band(1) / 1.3;
hi = sw.fStop < 1.1 * band(2);
end

function m = sweepMargin(sw, band)
% warning for a sweep without the margin at one or both ends: which window
% edge was used there instead of the gate
m = '';
[lo, hi] = noMargin(sw, band);
if ~(lo || hi), return; end
what = {}; parts = {};
if lo
    what{end+1} = ['the analysis window starts at the detected excitation, as without the gate (the ' ...
        'output-on transient and the start tone included)'];
    parts{end+1} = sprintf('start at or below %.0f Hz (now %g Hz)', floor(band(1) / 1.3), sw.fStart);
end
if hi
    what{end+1} = ['the window is extended past the end of the sweep by the gate''s ring-down margin (an ' ...
        'output-off transient within it is included)'];
    parts{end+1} = sprintf('stop at or above %.0f Hz (now %g Hz)', ceil(1.1 * band(2)), sw.fStop);
end
m = sprintf(['Sweep %g-%g Hz too close to the analysis band for the sweep gate: %s. Let the sweep %s to keep ' ...
    'the generator''s switching transients out of the analysis.'], sw.fStart, sw.fStop, strjoin(what, '; '), ...
    strjoin(parts, ' and '));
end

function [ib, b, wb] = lineWeights(fb, fGrid, df)
% contributions of the FFT bins fb to the frequency lines fGrid: bin ib goes
% to line b with weight wb. Line f covers [f - df/2, f + df/2], symmetric
% about f: weight 1 inside, 1/2 for a bin exactly on an edge, which the
% neighbouring line shares (at the ends of the grid: half in the one line)
nB = numel(fGrid);
if nB == 1
    near = ones(size(fb));
else
    near = interp1(fGrid, (1:nB).', fb, 'nearest', 'extrap');
end
dist = fb - fGrid(near);
tol = 1e-9 * df;
inner = find(abs(dist) < df / 2 - tol);
edge = find(abs(abs(dist) - df / 2) <= tol);
other = near(edge) + sign(dist(edge));               % the line on the other side of the edge
shared = other >= 1 & other <= nB;
shared(shared) = abs(abs(fb(edge(shared)) - fGrid(other(shared))) - df / 2) <= tol;
ib = [inner; edge; edge(shared)];
b = [near(inner); near(edge); other(shared)];
wb = [ones(numel(inner), 1); 0.5 * ones(numel(edge) + nnz(shared), 1)];
end

function g = sweepGate(xr, fs, sw, band, taper, ex)
% analysis gate on the sweep itself (see the help): [] if the sweep is not found reliably
g = [];
try
    law = tim.dsp.estimateSweepLaw(xr, fs, sw.fStart, sw.fStop, sw.spacing, sw.duration);
catch
    return
end
t0 = law.matchedStart_s; T = law.matchedDuration_s;
% plausibility: clear correlation peak, duration as programmed, start inside the excited interval
if ~(isfinite(t0) && isfinite(T) && law.matchedPeakRatio >= 8 && abs(T / sw.duration - 1) < 0.02 && ...
        t0 >= ex.start_s - 0.1 && t0 + T <= ex.end_s + 0.1 && t0 + T <= numel(xr) / fs)
    return
end
f1 = sw.fStart; f2 = sw.fStop;
if strncmpi(sw.spacing, 'LOG', 3)
    tf = @(f) t0 + T * log(min(max(f, f1), f2) / f1) / log(f2 / f1);
else
    tf = @(f) t0 + T * (min(max(f, f1), f2) - f1) / (f2 - f1);
end
t = [tf(band(1) / 1.5), tf(band(1) / 1.1), tf(band(2) * 1.1), tf(band(2) * 1.5)];
[lo, hi] = noMargin(sw, band);
ends = {'gate', 'gate'};
if lo
    % no room below the band (owner decision 2026-10-11): from the detected
    % start, as without the gate (docs/theory.md section 4, step 2')
    t(1) = max(0, min(ex.start_s, t0) - taper); t(2) = t(1) + taper;
    ends{1} = 'detected start';
elseif t(2) - t(1) < taper
    % minimum ramp length inside the sweep
    t(1) = max(t0, t(2) - taper); t(2) = t(1) + taper;
end
if hi
    % no room above the band (owner decision 2026-10-11): the gate's ring-down
    % margin past the sweep end, the sweep law continued beyond fStop - 1 up
    % to t(1.1 f_hi), raised cosine down to t(1.5 f_hi) (at least the taper,
    % at most the record), so a later output-off transient stays out
    if strncmpi(sw.spacing, 'LOG', 3)
        tx = @(f) t0 + T * log(f / f1) / log(f2 / f1);
    else
        tx = @(f) t0 + T * (f - f1) / (f2 - f1);
    end
    t(4) = min(numel(xr) / fs, max(tx(band(2) * 1.5), t0 + T + taper));
    t(3) = min(max(tx(band(2) * 1.1), t0 + T), t(4) - taper);
    ends{2} = 'ring-down margin';
elseif t(4) - t(3) < taper
    % minimum ramp length inside the sweep
    t(4) = min(t0 + T, t(3) + taper); t(3) = t(4) - taper;
end
if ~(t(2) <= t(3)), return; end
g = struct('t0', t0, 'T', T, 't', t, 'ends', {ends});
end

function w = gateWindow(tt, t)
% 0 -> raised cosine -> 1 -> raised cosine -> 0 at the gate times t(1..4)
w = zeros(size(tt));
up = tt >= t(1) & tt < t(2); w(up) = 0.5 * (1 - cos(pi * (tt(up) - t(1)) / (t(2) - t(1))));
w(tt >= t(2) & tt <= t(3)) = 1;
dn = tt > t(3) & tt <= t(4); w(dn) = 0.5 * (1 + cos(pi * (tt(dn) - t(3)) / (t(4) - t(3))));
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
