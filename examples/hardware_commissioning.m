%% HARDWARE COMMISSIONING - run section by section (Ctrl+Enter)
% Executes the pending hardware tests of docs/hardware_status.md in a safe
% order. Every section that drives the loudspeaker says so in its title.
% Results are collected in the struct "report" and saved at the end.
%
% BEFORE YOU START
%   * Amplifier gain at minimum, loudspeaker connected, tube closed.
%   * config/user_config.json: "mode": "hardware", correct "lanxi.connector"
%     (BNC or LEMO), conservative "generator.maxVpp" (e.g. 0.2).
%   * Hearing protection if levels may become high.

root = fileparts(fileparts(mfilename('fullpath')));
addpath(root);
cfg = tim.app.loadConfig(fullfile(root, 'config', 'user_config.json'));
assert(strcmp(cfg.mode, 'hardware'), 'Set "mode": "hardware" in config/user_config.json');
report = struct('date', char(datetime('now')), 'software', tim.app.softwareVersion());

%% H0 - connect (generator output stays OFF), identification, TEDS
s = tim.app.MeasurementSession(cfg);
s.connect();
s.prepareAcquisition();
report.H0 = struct('generator', s.Gen.Identity, 'lanxi', rmfield(s.Daq.Info, 'raw'), 'teds', {s.Daq.Teds}, ...
    'mics', s.Mics);
disp(struct2table(s.Mics(:)));

%% H1 - Test A: acquisition without excitation (microphones connected!)
report.H1 = tim.val.testA_acquisition(s, 2);
fprintf('Test A passed: %d\n', report.H1.passed);
fprintf('  fatal: %s\n', strjoin(report.H1.fatal, ' | '));
fprintf('  background level 100-5000 Hz [dB SPL]: %s\n', mat2str(report.H1.backgroundLevel_dB_100_5000Hz, 3));
% If all channels report INVALID: check "lanxi.connector" (BNC/LEMO) and cables.

%% H2 - channel identification (tap test, no excitation)
report.H2 = tim.val.channelIdentification(s);   % figure window: blow onto ch1..ch4 in turn
disp(report.H2)

%% H3 - FIRST EXCITATION: 1 kHz sine at low level  (LOUDSPEAKER ON)
% Raise the amplifier gain slowly between repetitions of this section until
% the channels show a clear tone (> 40 dB above background) without overload.
% Record every manual gain change (stored with the data, confirmed before playing):
s.setAmplifierGain(cfg.amplifier.model, cfg.amplifier.gainFactor);   % <-- e.g. s.setAmplifierGain('XYZ amp', 10)  (x10)
report.H3 =tim.val.testB_singleFrequency(s, 1000, min(0.05, cfg.generator.maxVpp), 1);
fprintf('peak fraction of range: %s\n', mat2str(report.H3.meas.channelInfo{1}.integrity.peakFractionOfRange, 3));
fprintf('SNR [dB]: %s\n', mat2str(report.H3.snr_dB, 3));

%% H4 - sweep timing with the configured sweep  (LOUDSPEAKER ON)
report.H4 = tim.val.sweepTimingTest(s);
disp(rmfield(report.H4, 'meas'))

%% H5 - Test B: single-frequency stability, 3 repeats at 3 frequencies  (LOUDSPEAKER ON)
for fq = [250 1000 3000]
    report.(sprintf('H5_%d', fq)) = tim.val.testB_singleFrequency(s, fq, cfg.excitation.sweep.amplitudeVpp, 3);
    r = report.(sprintf('H5_%d', fq));
    fprintf('%5d Hz: passed %d, scatter %s dB / %s deg, clock offset %.1f ppm\n', fq, r.passed, ...
        mat2str(r.scatter_dB, 2), mat2str(r.scatter_deg, 2), r.clockOffset_ppm);
end

%% H5b - geometry BEFORE the calibration (no excitation)
% The calibration stores the port distances and the empty-section length, and
% its automatic empty-tube check (Test E) uses the face positions. So:
% 1) Measure the axial positions of M1..M4 and of the specimen-section faces
%    (calipers) and enter them in the GUI (IMPEDANCE TUBE) or in
%    config/user_config.json (geometry.micPositions, xFront, xRear;
%    tubeDrawing.specimenSectionLength = length of the EMPTY section, 0.075 m).
% 2) Reload and reconnect if the file was changed:
%      s.close(); cfg = tim.app.loadConfig(fullfile(root, 'config', 'user_config.json'));
%      s = tim.app.MeasurementSession(cfg); s.connect(); s.prepareAcquisition();
disp(cfg.geometry)

%% H6 - Test C: switching calibration (interactive, LOUDSPEAKER ON) + consistency
% EMPTY specimen section mounted (no specimen, no absorber inside it); absorbing
% material only at the termination (docs/calibration_procedure.md).
% runCalibration ends with the automatic empty-tube check (Test E), stored in
% cal.meta.emptyCheck; the calibration is saved before that check.
[cal, calFile] = tim.app.runCalibration(s);
tim.app.plotCalibration(cal);
report.H6_emptyCheck = cal.meta.emptyCheck;
disp(cal.meta.emptyCheck)
% Independent consistency check with channels 1/2 interchanged:
input('Microphones in measurement ports. ENTER to measure A ...', 's');
mA = s.measure('sweep');
input('Interchange the microphones of channel 1 and channel 2 (keep cables). ENTER to measure B ...', 's');
mB = s.measure('sweep');
input('Put them back. ENTER ...', 's');
report.H6 = tim.val.testC_calibrationConsistency(cal, mA, mB, cfg, [1 2]);
report.H6.calFile = calFile;
disp(report.H6)

%% H7 - Test D (rigid plug) and Test E repeated (empty section)  (LOUDSPEAKER ON)
% Geometry as entered in H5b. Test D: rigid plug with its face L metres
% downstream of xFront.
L = 0.0;   % <-- enter the measured value
input('Insert the rigid plug. ENTER ...', 's');
resD = tim.app.processMeasurement(s.measure('sweep'), cfg, cal);
report.H7_D = tim.val.testDE_reference(resD, 'rigid', struct('L', L));
disp(report.H7_D)
input(['Remove the plug; keep the EMPTY 75 mm section mounted (do not join the tubes ' ...
    'directly), normal termination. ENTER ...'], 's');
resE = tim.app.processMeasurement(s.measure('sweep'), cfg, cal);
report.H7_E = tim.val.testDE_reference(resE, 'empty', struct());
disp(report.H7_E)

%% H8 - Test G: stepped sine vs log sweep on the same set-up  (LOUDSPEAKER ON)
rs = tim.app.processMeasurement(s.measure('stepped'), cfg, cal);
rw = tim.app.processMeasurement(s.measure('sweep'), cfg, cal);
Rw = interp1(rw.analysis.f, rw.analysis.R, rs.analysis.f);
ok = rs.analysis.valid.valid;
report.H8 = struct('f', rs.analysis.f, 'maxAbsDiffR', max(abs(rs.analysis.R(ok) - Rw(ok))), ...
    'passed', max(abs(rs.analysis.R(ok) - Rw(ok))) < 0.03, 'criteria', 'max |R_stepped - R_sweep| < 0.03 over valid bins');
disp(report.H8)

%% Save the commissioning report and disconnect
out = tim.app.uniqueName(fullfile(root, 'data', ['commissioning_' char(datetime('now'), 'yyyyMMdd_HHmmss') '.mat']));
save(out, 'report', '-v7.3');
fprintf('Commissioning report saved to %s\n', out);
s.close();
