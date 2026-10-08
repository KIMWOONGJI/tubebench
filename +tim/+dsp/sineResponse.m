function r = sineResponse(x, fs, fNominal, opts)
%SINERESPONSE Complex amplitudes of a stationary sinusoid on all channels.
%
%   r = tim.dsp.sineResponse(x, fs, fNominal, opts)
%
%   x        (N x C) record (volts) taken AFTER the settling time
%   fNominal generator frequency setting [Hz]
%   opts     refChannel (1), nBlocks (4) blocks for averaging/uncertainty,
%            maxClockError (5e-4 relative search range for the frequency)
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
%   H from the block scatter, SNR = |a|^2/2 / residual variance.

arguments
    x double
    fs (1,1) double
    fNominal (1,1) double {mustBePositive}
    opts struct = struct()
end
o = struct('refChannel', 1, 'nBlocks', 4, 'maxClockError', 5e-4);
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
toneP = mean(abs(a).^2 / 2, 1);
resAll = zeros(N, C); tb = t;
M = [cos(2*pi*fHat*tb), -sin(2*pi*fHat*tb), ones(N, 1)];
resAll(:, :) = x - M * (M \ x);
nf = min(N, 2^floor(log2(N)));
[Pr, fr] = pwelch(resAll, hann(min(nf, 8192), 'periodic'), [], min(nf, 8192), fs);
band = abs(fr - fHat) >= 10 & abs(fr - fHat) <= 100;
if nnz(band) < 3, band = abs(fr - fHat) <= 200 & abs(fr - fHat) >= 2 * fs / min(nf, 8192); end
noiseInBw = median(Pr(band, :), 1) / 2 * fs / L;   % one-sided PSD -> noise power in fit bandwidth
r = struct('fNominal', fNominal, 'f', fHat, 'clockRatio', fHat / fNominal, ...
    'amplitude', mean(abs(a), 1), 'phasor', mean(a, 1), 'H', H, 'Hblocks', Hb, ...
    'stdErr', sem, 'coherence', abs(Scr).^2 ./ (Srr * Scc), ...
    'snr_dB', 10 * log10(toneP ./ noiseInBw), ...
    'snrBroadband_dB', 10 * log10(toneP ./ mean(resVar, 1)), 'nBlocks', nb);
r.H(ref) = 1;
end
