function ex = detectExcitation(x, fs, band, threshold_dB, preRoll)
%DETECTEXCITATION Locate the excited interval in a recording (one channel).
%
%   ex = tim.dsp.detectExcitation(x, fs, band, threshold_dB, preRoll)
%
%   The signal is band-limited to 'band' (zero-phase Butterworth), its
%   short-time RMS (10 ms frames) is compared with the background level
%   measured in the pre-roll (median frame RMS of the first 80 % of
%   preRoll; if preRoll is empty, the 10th percentile of all frames).
%   start/end = first/last frame more than threshold_dB above background.
%   Used to (i) verify that the excitation happened inside the recording
%   (generator/DAQ are not synchronised) and (ii) choose the analysis window.

if nargin < 4 || isempty(threshold_dB), threshold_dB = 12; end
if nargin < 5, preRoll = []; end
x = x(:);
nyq = fs / 2;
lo = max(band(1) * 0.7, 1); hi = min(band(2) * 1.3, 0.95 * nyq);
[z, p, k] = butter(3, [lo hi] / nyq, 'bandpass');
[sos, g] = zp2sos(z, p, k);          % second-order sections: well conditioned
y = filtfilt(sos, g, x);
fl = max(1, round(0.01 * fs));
nF = floor(numel(y) / fl);
fr = sqrt(mean(reshape(y(1:nF * fl), fl, nF).^2, 1)).';
if ~isempty(preRoll) && preRoll > 0.05
    nb = max(1, floor(0.8 * preRoll * fs / fl));
    noise = median(fr(1:min(nb, nF)));
else
    noise = prctile(fr, 10);
end
thr = noise * 10^(threshold_dB / 20);
above = find(fr > thr);
ex = struct('start_s', NaN, 'end_s', NaN, 'duration_s', NaN, 'noiseRms', noise, ...
    'peakRms', max(fr), 'detected', false);
if ~isempty(above)
    ex.start_s = (above(1) - 1) * fl / fs;
    ex.end_s = above(end) * fl / fs;
    ex.duration_s = ex.end_s - ex.start_s;
    ex.detected = true;
end
end
