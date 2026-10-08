function s = estimateSweepLaw(x, fs, fStart, fStop, spacing, nominalDuration)
%ESTIMATESWEEPLAW Diagnostic: estimate the actual sweep law from a recording.
%
%   s = tim.dsp.estimateSweepLaw(x, fs, fStart, fStop, spacing, nominalDuration)
%
%   The instantaneous frequency ridge is taken from an STFT (Hann, 2048
%   points, hop 256, parabolic peak interpolation). Frames whose ridge lies
%   inside (1.05 fStart, 0.95 fStop) are fitted with
%       LOG: ln f = a + b t   ->  start = (ln fStart - a)/b, T = ln(fStop/fStart)/b
%       LIN:    f = a + b t   ->  start = (fStart - a)/b,    T = (fStop - fStart)/b
%   Returned: startTime_s, duration_s, rate, residual (relative rms of the
%   ridge around the fitted law). This is a DIAGNOSTIC of the generator
%   behaviour (the analysis never relies on it).
%   If the ridge fit is unreliable (residual > 5 % or < 20 % usable frames,
%   typical at low SNR) and nominalDuration is given, start and duration
%   come from a matched filter with the head/tail of the nominal sweep
%   (s.method tells which estimate is reported).

if nargin < 6, nominalDuration = []; end

x = x(:) - mean(x);
nfft = 2048; hop = 256;
[S, F, T] = spectrogram(x, hann(nfft, 'periodic'), nfft - hop, nfft, fs);
P = abs(S).^2;
[~, k] = max(P, [], 1);
k = min(max(k, 2), numel(F) - 1);
idx = sub2ind(size(P), k, 1:numel(k));
a1 = log(P(idx - 1)); a2 = log(P(idx)); a3 = log(P(idx + 1));
delta = 0.5 * (a1 - a3) ./ (a1 - 2 * a2 + a3);
delta(~isfinite(delta)) = 0;
fr = (k - 1 + delta) * fs / nfft;
fr = fr(:); T = T(:);
% Only frames whose ridge stands well above the background (pre-roll noise
% frames have random ridge frequencies and must not enter the fit).
pk = P(idx).';
bg = prctile(pk, 10);
% A frame is used if its ridge is (a) 20 dB above the quietest frames, or
% (b) a prominent tonal peak: > 15 dB above the median of its own spectrum
% (for pure noise the maximum of ~1000 bins is only ~8-10 dB above the
% median). (b) was added after a bench test at low level where the sweep
% was only ~15 dB above the background and (a) rejected every frame.
prominence = pk ./ median(P, 1).';
strong = pk > bg * 10^(20/10) | prominence > 10^(15/10);
use = strong & fr > 1.05 * fStart & fr < 0.95 * fStop;
% A real sweep has a monotonic ridge: discard isolated outliers relative
% to a running median.
if nnz(use) > 9
    lf = log(fr); lf(~use) = NaN;
    med = movmedian(lf, 9, 'omitnan');
    use = use & abs(lf - med) < 0.1;
end
s = struct('startTime_s', NaN, 'duration_s', NaN, 'rate', NaN, 'residual', NaN, ...
    'nFrames', nnz(use), 'spacing', upper(spacing), 'ridgeT', T, 'ridgeF', fr);
% Matched-filter estimate (robust at low SNR): correlate the recording with
% the first and the last Th seconds of the nominal sweep (complex template ->
% phase-insensitive envelope). start = lag of the head; duration =
% lag(tail) - start + Th. Used when the ridge fit is unreliable.
s.method = 'ridge';
[s.matchedStart_s, s.matchedDuration_s, s.matchedPeakRatio] = matched(x, fs, fStart, fStop, spacing, nominalDuration);
if nnz(use) < 5
    s = useMatched(s);
    return
end
if strncmpi(spacing, 'LOG', 3)
    p = polyfit(T(use), log(fr(use)), 1);
    s.rate = p(1);                          % neper per second
    s.startTime_s = (log(fStart) - p(2)) / p(1);
    s.duration_s = log(fStop / fStart) / p(1);
    s.residual = rms(exp(polyval(p, T(use))) ./ fr(use) - 1);
else
    p = polyfit(T(use), fr(use), 1);
    s.rate = p(1);                          % Hz per second
    s.startTime_s = (fStart - p(2)) / p(1);
    s.duration_s = (fStop - fStart) / p(1);
    s.residual = rms(polyval(p, T(use)) ./ fr(use) - 1);
end
if ~(s.residual < 0.05) || nnz(use) < 0.2 * numel(fr)
    s = useMatched(s);
end
end

function s = useMatched(s)
if isfinite(s.matchedStart_s)
    s.startTime_s = s.matchedStart_s;
    s.duration_s = s.matchedDuration_s;
    s.method = 'matched filter (ridge fit unreliable)';
end
end

function [t0, dur, pr] = matched(x, fs, f1, f2, spacing, Tn)
t0 = NaN; dur = NaN; pr = NaN;
if isempty(Tn) || ~(Tn > 0), return; end
Th = min(1, Tn / 4);
n = (0:round(Th * fs) - 1).' / fs;
if strncmpi(spacing, 'LOG', 3)
    L = Tn / log(f2 / f1);
    ph = @(t) 2 * pi * f1 * L * (exp(t / L) - 1);
else
    ph = @(t) 2 * pi * (f1 * t + (f2 - f1) / (2 * Tn) * t.^2);
end
head = exp(1j * ph(n));
tail = exp(1j * (ph(Tn - Th + n) - ph(Tn - Th)));
N = 2^nextpow2(numel(x) + numel(n));
X = fft(x, N);
ch = abs(ifft(X .* conj(fft(head, N))));
ct = abs(ifft(X .* conj(fft(tail, N))));
valid = 1:numel(x) - numel(n);
[ph1, i1] = max(ch(valid)); [~, i2] = max(ct(valid));
t0 = (i1 - 1) / fs;
dur = (i2 - 1) / fs - t0 + Th;
pr = ph1 / median(ch(valid));
end
