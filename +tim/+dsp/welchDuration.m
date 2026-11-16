function T = welchDuration(N, nfft, fs)
%WELCHDURATION Effective length of a Welch PSD for a transient (a sweep).
%
%   T = tim.dsp.welchDuration(N, nfft, fs)
%
%   N samples, Hann window of nfft samples, 75 % overlap (hop nfft/4, the
%   estimate of tim.plots.spectrum and res.pressureSpectrum): K =
%   floor((N - 3 nfft/4) / (nfft/4)) segments, T = K nfft / (4 fs) [s].
%   A sine that sweeps through f at a time where the shifted squared windows
%   add up to their constant sum (sum w^2 / hop) gives G(f) = A^2 / (2 fdot T),
%   so tim.dsp.sweepSineLevel needs this T, not the record length N / fs
%   (they differ by 3 hops: 0.2 dB for a 7 s record, 2 dB for the last 1 s of
%   the live view). Frequencies swept within the first or last 3 hops of
%   the record get less weight and read low.
hop = nfft / 4;
K = max(0, floor((N - 3 * hop) / hop));
T = K * hop / fs;
end
