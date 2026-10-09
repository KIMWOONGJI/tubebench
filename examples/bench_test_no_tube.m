%% BENCH TEST WITHOUT IMPEDANCE TUBE - run section by section (Ctrl+Enter)
% Situation: microphones connected to the LAN-XI, but NOT mounted in the
% tube. Goal: verify everything that does not need the tube
%   B0 connection / TEDS / integrity (Test A)
%   B1 channel identification (tap test)
%   B2 first excitation at low level (speaker in free air)
%   B3 sweep trigger/timing without shared clock
%   B4 relative responses of the 4 microphones held together (chain matching)
%   B5 stepped sine vs sweep on the same set-up (Test G, relative responses)
%   B6 practice of the sensor-switching calibration (ch1 <-> ch2)
% Results with the tube geometry (R, tau, Zt) are MEANINGLESS here and are
% not computed: the microphones are not in the tube.
%
% Physical set-up for B2-B6:
%   * loudspeaker on the table, amplifier gain at MINIMUM
%   * the 4 microphone heads bundled side by side (tips as close together
%     as possible, all at the same distance, ~0.3-0.5 m in front of the
%     speaker, pointing at it). Tape them together if possible.
%   * quiet room; hearing protection if levels may become high.

root = fileparts(fileparts(mfilename('fullpath')));
addpath(root);
cfg = tim.app.loadConfig(fullfile(root, 'config', 'user_config.json'));
assert(strcmp(cfg.mode, 'hardware'), 'config/user_config.json must have "mode": "hardware"');
bench = struct('date', char(datetime('now')), 'note', 'bench test, microphones not in tube');
outDir = fullfile(root, 'data', ['bench_' char(datetime('now'), 'yyyyMMdd_HHmmss')]);
mkdir(outDir);

%% B0 - connect (generator output OFF), TEDS, 3 s background (no excitation)
s = tim.app.MeasurementSession(cfg);
s.connect();
s.prepareAcquisition();
for i = 1:numel(s.Daq.Teds)
    t = s.Daq.Teds{i};
    if isempty(t), fprintf('ch%d: NO TEDS\n', i);
    else, fprintf('ch%d: TEDS type %s, serial %d, %.3f mV/%s\n', i, t.typeNumber, t.serialNumber, 1e3 * t.sensitivity, t.unit); end
end
bench.B0 = tim.val.testA_acquisition(s, 3);
fprintf('Test A passed: %d\n  fatal: %s\n  background 100-5000 Hz [dB SPL]: %s\n', bench.B0.passed, ...
    strjoin(bench.B0.fatal, ' | '), mat2str(bench.B0.backgroundLevel_dB_100_5000Hz, 3));
% A channel with "INVALID" and no TEDS: swap its cable/microphone with a
% working channel and repeat B0 - does the fault follow the microphone,
% the cable or the LAN-XI input?

%% B1 - channel identification: blow gently onto each microphone in turn
% A figure window counts down ch1 -> ch4 (6 s each). Do NOT tap the table or
% the taped bundle: that excites all microphones (observed 2026-10-08).
bench.B1 = tim.val.channelIdentification(s);
disp(bench.B1)

%% B2 - FIRST EXCITATION: 1 kHz sine  (LOUDSPEAKER ON, ~4 s)
% Amplitude = excitation.stepped.amplitudeVpp of the config (capped by
% generator.maxVpp). With an amplifier: gain at minimum first, raise it
% step by step until SNR > 40 dB on all channels with peak fraction < 0.5.
% Direct drive (no amplifier): the 33220A 50-ohm output limits the current
% to Vpeak/(50+Zs), e.g. 1 Vpp into 8 ohm -> 8.6 mA peak, 0.3 mW.
% The amplifier (if any) is set BY HAND; record it in the config or here
% (stored with the data; confirmed before the loudspeaker is driven):
amp = cfg.amplifier;        % or e.g. amp.model = 'XYZ power amp'; amp.gainFactor = 10;  (x10)
s.setAmplifierGain(amp.model, amp.gainFactor);
b2Vpp = min(cfg.excitation.stepped.amplitudeVpp, cfg.generator.maxVpp);   % config stores Vpp = 2 x Vpk
bench.B2 = tim.val.testB_singleFrequency(s, 1000, b2Vpp, 1);
bench.B2.amplifier = s.Cfg.amplifier;
fprintf('SNR [dB]: %s\npeak fraction of range: %s\nlevel re ch%d [dB]: %s\nphase re ch%d [deg]: %s\nclock offset: %.1f ppm\n', ...
    mat2str(bench.B2.snr_dB, 3), mat2str(bench.B2.meas.channelInfo{1}.integrity.peakFractionOfRange, 2), ...
    cfg.analysis.refChannel, mat2str(bench.B2.relLevel_dB, 3), cfg.analysis.refChannel, mat2str(bench.B2.relPhase_deg, 3), ...
    bench.B2.clockOffset_ppm);

%% B3 - sweep trigger / timing (LOUDSPEAKER ON, one 5 s sweep)
bench.B3 = tim.val.sweepTimingTest(s);
disp(rmfield(bench.B3, 'meas'))

%% B4 - relative responses of the bundled microphones (LOUDSPEAKER ON)
% With the heads together, H_c = Y_c/Y_ref mainly shows the chain mismatch
% (+ small position differences, growing with frequency: 5 mm offset
% = 26 deg at 4.5 kHz). Expect |H| within ~ +-1 dB and small phase at low
% and mid frequencies. Coherence near 1 means a stable linear measurement.
mB4 = s.measure('sweep');
a = cfg.analysis;
o = struct('refChannel', a.refChannel, 'fRange', [100 5000], 'df', 5, 'preRoll', mB4.settings.preRoll, ...
    'excitationBand', [mB4.settings.fStart mB4.settings.fStop]);
spB4 = tim.dsp.sweepResponse(mB4.records, mB4.fs, o);
bench.B4 = struct('f', spB4.f, 'H', spB4.H, 'coherence', spB4.coherence, 'snr_dB', spB4.snr_dB, ...
    'integrityOk', mB4.integrityOk, 'warnings', {spB4.warnings});
fig = figure('Name', 'B4 relative responses (bundled mics)', 'Color', 'w');
tl = tiledlayout(fig, 3, 1);
ax = nexttile(tl); semilogx(ax, spB4.f, 20 * log10(abs(spB4.H))); ylabel(ax, '|H_c| [dB]'); grid(ax, 'on');
legend(ax, compose('ch%d/ch%d', (1:4).', a.refChannel)); title(ax, 'Bench: microphones bundled, free field');
ax = nexttile(tl); semilogx(ax, spB4.f, rad2deg(angle(spB4.H))); ylabel(ax, 'phase [deg]'); grid(ax, 'on');
ax = nexttile(tl); semilogx(ax, spB4.f, spB4.coherence); ylabel(ax, 'coherence'); xlabel(ax, 'Frequency [Hz]'); grid(ax, 'on');
exportgraphics(fig, fullfile(outDir, 'B4_relative_responses.png'));
for fq = [250 500 1000 2000 4000]
    [~, j] = min(abs(spB4.f - fq));
    fprintf('%5d Hz: |H| [dB] %s  phase [deg] %s  coh %s\n', fq, mat2str(20 * log10(abs(spB4.H(j, :))), 2), ...
        mat2str(rad2deg(angle(spB4.H(j, :))), 2), mat2str(spB4.coherence(j, :), 4));
end

%% B5 - Test G on relative responses: stepped sine vs sweep (LOUDSPEAKER ON)
% Do NOT move the microphones between B4 and B5.
ex = s.Cfg.excitation;
ex5 = ex; ex5.stepped.fStart = 250; ex5.stepped.fStop = 4000; ex5.stepped.nPoints = 6;
ex5.stepped.amplitudeVpp = ex.sweep.amplitudeVpp;
s.setExcitation(ex5);
mB5 = s.measure('stepped');
s.setExcitation(ex);
st = mB5.settings; Hs = zeros(numel(st.frequencies), 4);
for k = 1:numel(st.frequencies)
    idx = tim.app.steppedSegment(mB5, 1, k);
    r = tim.dsp.sineResponse(mB5.records{1}(idx, :), mB5.fs, st.frequencies(k), ...
        struct('refChannel', a.refChannel));
    Hs(k, :) = r.H;
end
Hw = interp1(spB4.f, spB4.H, st.frequencies(:));
d = Hs ./ Hw;
bench.B5 = struct('f', st.frequencies(:), 'Hstepped', Hs, 'Hsweep', Hw, ...
    'diff_dB', 20 * log10(abs(d)), 'diff_deg', rad2deg(angle(d)));
disp(table(st.frequencies(:), round(bench.B5.diff_dB, 3), round(bench.B5.diff_deg, 2), ...
    'VariableNames', {'f_Hz', 'diff_dB', 'diff_deg'}));
% Agreement within ~0.1 dB / ~1 deg (free field, room reflections) shows the
% sweep estimator works without generator/DAQ synchronisation.

%% B6 - practice switching calibration ch1 <-> ch2 (LOUDSPEAKER ON, 2 sweeps)
% Configuration I = the current bundle. Then physically interchange the
% heads of the ch1 and ch2 microphones in the bundle (cables stay).
mI = mB4;
input(tim.app.msg(cfg.ui.language, 'interchange12'), 's');
mII = s.measure('sweep');
spII = tim.dsp.sweepResponse(mII.records, mII.fs, o);
c12 = tim.cal.switchingCorrection(spB4.f, spB4.H(:, 2), spII.H(:, 2), struct('cohI', spB4.coherence(:, 2), ...
    'cohII', spII.coherence(:, 2)));
bench.B6 = c12;
fig = figure('Name', 'B6 switching result ch2/ch1', 'Color', 'w');
tl = tiledlayout(fig, 2, 1);
ax = nexttile(tl); semilogx(ax, c12.f, 20 * log10(abs(c12.Hc)), c12.f, 20 * log10(abs(c12.Hpos)));
legend(ax, {'chain mismatch C_2 = c_2/c_1', 'position ratio p_b/p_a'}); ylabel(ax, 'dB'); grid(ax, 'on');
ax = nexttile(tl); semilogx(ax, c12.f, rad2deg(angle(c12.Hc)), c12.f, rad2deg(angle(c12.Hpos)));
ylabel(ax, 'deg'); xlabel(ax, 'Frequency [Hz]'); grid(ax, 'on');
exportgraphics(fig, fullfile(outDir, 'B6_switching_ch1_ch2.png'));
% Expect C_2 smooth, within ~+-1 dB and a few degrees; it does NOT replace
% the in-tube calibration (free field + room reflections differ).

%% Save and disconnect
save(fullfile(outDir, 'bench_results.mat'), 'bench', '-v7.3');
fprintf('Bench results saved in %s\n', outDir);
s.close();
