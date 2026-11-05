function r = sineResponse(x, fs, fNominal, opts)
%SINERESPONSE Complex amplitudes of a stationary sinusoid on all channels.
%
%   r = tim.dsp.sineResponse(x, fs, fNominal, opts)
%
%   x        (N x C) record (volts) taken AFTER the settling time
%   fNominal generator frequency setting [Hz]
%   opts     refChannel (1), nBlocks (4) blocks for averaging/uncertainty,
%            maxClockError (5e-4 relative search range for the frequency),
%            noisePsd ([]): struct('f', f, 'G', G), the one-sided PSD
%            (V^2/Hz, one column per channel) of noise-only data of the same
%            recording - the pre-roll of a stepped sine, output off - for
%            driftSigma only
%
%   Because the generator clock is not the DAQ clock, the actual frequency
%   seen by the DAQ differs from fNominal by up to ~1e-4. It is estimated
%   from the reference channel by maximising the Hann-windowed DTFT
%   magnitude (fminbnd) and then used for all channels. Complex amplitudes
%   a_c are obtained by linear least squares on [cos, sin, 1] at that
%   frequency in each of nBlocks blocks (3-parameter sine fit, IEEE 1057):
%       x_c(t) ~ Re{ a_c exp(j 2 pi f t) } + d_c
%   (exp(+j w t) convention: a_c is the phasor of channel c.)
%   H_c = sum_b a_cb conj(a_rb) / sum_b |a_rb|^2,   coherence-like
%   g2_c = |sum a_c a_r^*|^2 / (sum|a_c|^2 sum|a_r|^2), standard error of
%   H from the block scatter.
%   snr_dB          = (|a|^2/2) / (G_n fs/L), per block of L = N/nBlocks
%                     samples (narrow-band; G_n one-sided noise PSD near f).
%                     The SNR of the nBlocks average is snr_dB + 10 log10(nBlocks).
%   snrBroadband_dB = (|a|^2/2) / residual variance (all frequencies).
%   drift           = |Hb_last - Hb_first| / |H| per channel: the relative
%                     change of the block ratio Hb = a_c / a_ref from the first
%                     to the last block (settled check of the stepped sine,
%                     1.6.0); 0 for the reference channel; NaN for every
%                     channel with one block (not judged).
%   driftSigma      = sqrt(2 (10^(-snr_c/10) + 10^(-snr_ref/10))): its standard
%                     deviation from noise alone. One block has E|da/a|^2 =
%                     (E|da|^2/2) / (|a|^2/2) = 1/SNR (snr_dB is per block), so
%                     the ratio of the two independent blocks has the variance
%                     2 (1/SNR_c + 1/SNR_ref); |drift|^2 / driftSigma^2 is then
%                     exponentially distributed, P(drift > z driftSigma) = e^(-z^2).
%                     0 for the reference channel. With opts.noisePsd the SNR
%                     of this formula takes G_n from that noise-only PSD
%                     (driftSnr_dB; the same band and trimming as snr_dB), not
%                     from the residual: the residual of the fit over the
%                     whole record holds the transient under test, and an
%                     abrupt one (the sound of the step arriving during the
%                     record) would raise its own sigma in proportion to its
%                     size. Without it driftSnr_dB = snr_dB.

arguments
    x double
    fs (1,1) double
    fNominal (1,1) double {mustBePositive}
    opts struct = struct()
end
o = struct('refChannel', 1, 'nBlocks', 4, 'maxClockError', 5e-4, 'noisePsd', []);
fn = fieldnames(opts); for i = 1:numel(fn), o.(fn{i}) = opts.(fn{i}); end
[N, C] = size(x);
ref = o.refChannel;
t = (0:N-1).' / fs;

% --- frequency estimate on reference channel
w = hann(N, 'periodic');
xr = (x(:, ref) - mean(x(:, ref))) .* w;
cost = @(f) -abs(sum(xr .* exp(-2j * pi * f * t)));
span = max(o.maxClockError * fNominal, 2 * fs / N);
fHat = fminbnd(cost, fNominal - span, fNominal + span, optimset('TolX', 1e-9 * fNominal));

% --- block-wise 3-parameter fits
nb = max(1, o.nBlocks);
L = floor(N / nb);
a = zeros(nb, C); resVar = zeros(nb, C);
for b = 1:nb
    idx = (b-1) * L + (1:L);
    tb = t(idx);
    M = [cos(2*pi*fHat*tb), -sin(2*pi*fHat*tb), ones(L, 1)];
    coef = M \ x(idx, :);
    a(b, :) = coef(1, :) + 1j * coef(2, :);
    res = x(idx, :) - M * coef;
    resVar(b, :) = var(res, 0, 1);
end
Scr = sum(a .* conj(a(:, ref)), 1);
Srr = sum(abs(a(:, ref)).^2);
Scc = sum(abs(a).^2, 1);
H = Scr / Srr;
Hb = a ./ a(:, ref);
if nb > 1
    sem = std(Hb, 0, 1) / sqrt(nb);
else
    sem = nan(1, C);
end
% SNR definitions:
%   snrBroadband_dB : tone power / total residual variance (all frequencies)
%   snr_dB          : NARROW-BAND SNR relevant for the estimate: tone power vs
%                     the residual noise power in the fit's effective noise
%                     bandwidth (fs/L, L = block length), with the residual
%                     noise PSD taken from f +- (10..100) Hz (bench finding
%                     2026-10-08: broadband SNR was negative for a clearly
%                     measurable 40 dB SPL tone in 60 dB SPL room noise).
%   Derivation: white noise of variance s^2 has the one-sided PSD G = 2 s^2/fs
%   (pwelch of a real signal). The LS fit of [cos, -sin, 1] over L samples
%   gives var = s^2/(L/2) per quadrature, E|da|^2 = 4 s^2/L, so the noise
%   power of the fitted sinusoid is E|da|^2/2 = 2 s^2/L = G*fs/L (= ENBW fs/L
%   of an L-point rectangular DFT bin). Hence SNR = (|a|^2/2) / (G fs/L).
%   (Formula review 2026-10-09, dsp-1: a factor 1/2 on G made snr_dB 3.01 dB
%   too high; dsp-2: the plain median of an unaveraged periodogram is ln2 =
%   -1.59 dB below the mean PSD; together +4.6 dB with the default settings.)
toneP = mean(abs(a).^2 / 2, 1);
resAll = zeros(N, C); tb = t;
M = [cos(2*pi*fHat*tb), -sin(2*pi*fHat*tb), ones(N, 1)];
resAll(:, :) = x - M * (M \ x);
nf = min(N, 2^floor(log2(N)));
nw = min(nf, 8192);
[Pr, fr] = pwelch(resAll, hann(nw, 'periodic'), [], nw, fs);   % one-sided PSD G [V^2/Hz]
Gn = bandNoise(Pr, fr, fHat, fs / nw);
noiseInBw = Gn * fs / L;                % G x ENBW fs/L of the L-sample sine fit (= E|da|^2/2)
snr = 10 * log10(toneP ./ noiseInBw);
% settled check (1.6.0, owner decision 2026-11-04): a transient that has not
% decayed changes the channel ratio from the first to the last block; a common
% amplitude or frequency error of all channels cancels in the ratio
if nb > 1
    drift = abs(Hb(nb, :) - Hb(1, :)) ./ abs(H);
    drift(ref) = 0;
else
    drift = nan(1, C);                  % one block: not judged (also the reference)
end
% its noise: from noise-only data when the caller has them (the pre-roll of
% the recording), never from the residual above, which holds the transient
% under test (review 2026-11-05: an abrupt one raised its own sigma in
% proportion to its size); a channel without a band estimate keeps the residual's
snrDrift = snr;
nz = o.noisePsd;
if isstruct(nz) && isscalar(nz) && all(isfield(nz, {'f', 'G'})) && size(nz.G, 2) == C && numel(nz.f) >= 2
    fz = nz.f(:);
    G0 = bandNoise(nz.G, fz, fHat, fz(2) - fz(1));
    use = isfinite(G0);
    snrDrift(use) = 10 * log10(toneP(use) ./ (G0(use) * fs / L));
end
driftSigma = sqrt(2 * (10.^(-snrDrift / 10) + 10^(-snrDrift(ref) / 10)));
driftSigma(ref) = 0;
r = struct('fNominal', fNominal, 'f', fHat, 'clockRatio', fHat / fNominal, ...
    'amplitude', mean(abs(a), 1), 'phasor', mean(a, 1), 'H', H, 'Hblocks', Hb, ...
    'stdErr', sem, 'coherence', abs(Scr).^2 ./ (Srr * Scc), ...
    'snr_dB', snr, ...
    'snrBroadband_dB', 10 * log10(toneP ./ mean(resVar, 1)), 'nBlocks', nb, ...
    'drift', drift, 'driftSigma', driftSigma, 'driftSnr_dB', snrDrift);
r.H(ref) = 1;
end

function G = bandNoise(P, fr, fHat, df)
% Unbiased, robust band estimate of the noise PSD G near fHat: mean of the
% bins 10-100 Hz away on both sides (with fewer than 3 such bins: +-200 Hz,
% at least two bins of width df away) after removing stray lines (previous
% step, harmonics, mains) above 10 x median. For a Gaussian-noise periodogram
% (chi-square, 2 dof per bin) the trimmed mean is 0.03 dB low; the plain
% median would be 1.59 dB low. NaN for a channel without band bins.
band = abs(fr - fHat) >= 10 & abs(fr - fHat) <= 100;
if nnz(band) < 3, band = abs(fr - fHat) <= 200 & abs(fr - fHat) >= 2 * df; end
G = zeros(1, size(P, 2));
for c = 1:size(P, 2)
    p = P(band, c);
    G(c) = mean(p(p <= 10 * median(p)));
end
end
