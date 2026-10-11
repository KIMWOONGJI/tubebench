function r = testB_singleFrequency(session, f, vpp, nRepeat)
%TESTB_SINGLEFREQUENCY Stable sinusoid: inter-channel amplitude/phase (Test B).
%
%   r = tim.val.testB_singleFrequency(session, 1000, 0.05, 3)
%   Uses the stepped-sine machinery with a single frequency, repeated
%   nRepeat times. Reports the relative amplitude [dB] and phase [deg] of
%   every channel w.r.t. the reference channel, their repeat scatter, the
%   generator/DAQ clock ratio, SNR, and checks against plausibility limits:
%     * SNR > 40 dB on all channels (narrow-band SNR of tim.dsp.sineResponse:
%       tone power / (G_n fs/L) per block of L = N/4 samples = 0.25 s; the
%       estimate was 3.5 dB too high before the 2026-10-09 fix, so the limit
%       is now met only by a true 40 dB; the 0.05 dB scatter limit below
%       already needs about 36.5 dB)
%     * repeat scatter < 0.05 dB and < 0.2 deg
%     * no overload / integrity problems
%   (The absolute relative values depend on the tube field and are only
%   physically interpretable after the complex calibration.)

if nargin < 4, nRepeat = 3; end
c = session.Cfg.excitation;
ex = c; ex.mode = 'stepped';
ex.stepped = struct('fStart', f, 'fStop', f, 'nPoints', 1, 'spacing', 'lin', 'amplitudeVpp', vpp, ...
    'settleTime', 0.5, 'recordTime', 1.0, 'nBlocks', 4, 'repetitions', nRepeat);
session.setExcitation(ex);
cleanup = onCleanup(@() session.setExcitation(c));
m = session.measure('stepped');
ref = session.Cfg.analysis.refChannel;
H = zeros(nRepeat, 4); snr = zeros(nRepeat, 4); clk = zeros(nRepeat, 1);
for k = 1:nRepeat
    idx = tim.app.steppedSegment(m, k, 1);
    o = tim.dsp.sineResponse(m.records{k}(idx, :), m.fs, f, struct('refChannel', ref));
    H(k, :) = o.H; snr(k, :) = o.snr_dB; clk(k) = o.clockRatio;
end
magdB = 20 * log10(abs(H));
% phases about the mean phasor: a relative phase near +-180 deg must not
% average +179.99 and -179.99 deg to 0 (audit 2026-10-11)
Hm = mean(H, 1);
ph = rad2deg(angle(H ./ Hm));
r = struct('name', sprintf('Test B - single frequency %g Hz', f), 'H', Hm, ...
    'relLevel_dB', mean(magdB, 1), 'relPhase_deg', rad2deg(angle(Hm)), ...
    'scatter_dB', std(magdB, 0, 1), 'scatter_deg', std(ph, 0, 1), 'snr_dB', min(snr, [], 1), ...
    'clockRatio', mean(clk), 'clockOffset_ppm', (mean(clk) - 1) * 1e6, 'integrityOk', m.integrityOk, 'meas', m);
r.passed = m.integrityOk && all(r.snr_dB > 40) && all(r.scatter_dB < 0.05) && all(r.scatter_deg < 0.2);
r.criteria = 'SNR > 40 dB (per 0.25 s block, fit bandwidth 4 Hz), repeat scatter < 0.05 dB and < 0.2 deg, integrity OK';
end
