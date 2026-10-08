function [cal, file, raw] = runCalibration(session, opts)
%RUNCALIBRATION Sequential sensor-switching calibration of all channels.
%
%   [cal, file] = tim.app.runCalibration(session)
%   [cal, file] = tim.app.runCalibration(session, struct('channels', [2 3 4], 'prompt', @fn))
%
%   For every channel k ~= ref (ref = cfg.analysis.refChannel), with the
%   calibration ports a, b = cfg.calibration.positions:
%     I   : reference microphone at port a, microphone k at port b -> measure
%     I'  : (optional) remove and re-insert both, same positions   -> repeat
%     II  : interchange the two microphones (each keeps its own cable /
%           preamplifier / DAQ channel!)                           -> measure
%   The remaining microphones stay in the other ports (their signals are
%   recorded but unused). The EMPTY specimen section (the middle part,
%   lab: 75 mm, SIT-PT-003, without specimen) is mounted, so the tube is
%   continuous and every port keeps its measurement position; the tube is
%   terminated anechoically (or with an absorber) so that no pressure node
%   falls on a calibration port. A first prompt shows this checklist.
%   After the switching measurements (cfg.calibration.verifyEmptySection)
%   one sweep with the microphones in their measurement ports is evaluated
%   as Test E (empty section: tau = exp(-j k d)), stored in
%   cal.meta.emptyCheck; cal.meta.tube records the set-up (section, length,
%   geometry, environment). The last prompt asks to mount the specimen
%   section again. In simulation the virtual rig models the empty section
%   (sample 'air') during the calibration and gets its specimen back
%   afterwards, also after an error or STOP. See docs/calibration_procedure.md.
%
%   opts.prompt(msg, mapping): called before each configuration. In
%   hardware mode the default prints the instruction and waits for ENTER.
%   In simulation mode the default moves the microphones in the virtual rig.
%   opts.report(q): (optional) called after every measurement with its
%   quality (q.kind = 'measurement': channel, config, fracOk, coherence
%   and SNR medians), after every channel (q.kind = 'channel': nValid,
%   Nf, repeatability) and after the empty-section check (q.kind =
%   'verification', q.check) - used by the GUI step list.
%   Every raw measurement is returned in raw and saved with the calibration.

if nargin < 2, opts = struct(); end
cfg = session.Cfg;
ref = cfg.analysis.refChannel;
ab = cfg.calibration.positions;
chans = setdiff(1:4, ref);
if isfield(opts, 'channels'), chans = opts.channels; end
lang = session.lang();
if isfield(opts, 'prompt')
    prompt = opts.prompt;
elseif strcmp(cfg.mode, 'simulation')
    prompt = @(msg, mapping) session.setMicPositionsForSimulation(mapping);
else
    prompt = @(msg, mapping) hardwarePrompt(msg, lang);
end
report = @(q) [];
if isfield(opts, 'report'), report = opts.report; end
a = cfg.analysis;
g = cfg.geometry;
dSec = g.xRear - g.xFront;                      % empty section = specimen section (lab: 75 mm)
secTxt = '';
if isfinite(dSec) && dSec > 0, secTxt = sprintf(' (%g mm)', round(1e3 * dSec, 3)); end
verify = ~isfield(cfg.calibration, 'verifyEmptySection') || cfg.calibration.verifyEmptySection;
session.beginOperation();                       % STOP between steps stays pending
opGuard = onCleanup(@() session.endOperation());
if strcmp(cfg.mode, 'simulation') && ~isempty(session.Rig)
    specimen = session.setSimulationSample(struct('type', 'air'));          % operator mounts the empty section
    restoreSpecimen = onCleanup(@() session.setSimulationSample(specimen));  % also on error / STOP
end
% step 0: preparation checklist (EMPTY specimen section mounted, anechoic /
% absorbing termination, ports sealed); microphones in their measurement ports
home0 = zeros(1, 4); home0([cfg.mics.channel]) = [cfg.mics.position];
prompt(tim.app.msg(lang, 'calPrepare', secTxt, ab(1), ab(2)), home0);
session.log('%s', tim.app.msg(lang, 'calPrepare', secTxt, ab(1), ab(2)));
results = cell(1, 4);
raw = struct('channel', {}, 'config', {}, 'meas', {}, 'spectra', {});
for k = chans
    others = setdiff(1:4, [ref k]);
    otherPos = setdiff(1:4, ab);
    mapI = zeros(1, 4); mapI(ref) = ab(1); mapI(k) = ab(2); mapI(others) = otherPos;
    mapII = mapI; mapII(ref) = ab(2); mapII(k) = ab(1);
    seq = {'I', mapI, tim.app.msg(lang, 'calConfigI', k, ref, ab(1), k, ab(2))};
    if cfg.calibration.repeatConfigI
        seq(end+1, :) = {'Irep', mapI, tim.app.msg(lang, 'calConfigIrep', k)};
    end
    seq(end+1, :) = {'II', mapII, tim.app.msg(lang, 'calConfigII', k, ref, ab(2), k, ab(1))};
    sp = struct();
    for i = 1:size(seq, 1)
        session.throwIfStopped();
        prompt(seq{i, 3}, seq{i, 2});
        session.throwIfStopped();
        session.log('%s', seq{i, 3});
        m = session.measure('sweep');
        s = tim.dsp.sweepResponse(m.records, m.fs, struct('refChannel', ref, 'fRange', [a.fMin a.fMax], ...
            'df', a.df, 'preRoll', m.settings.preRoll, 'excitationBand', [m.settings.fStart m.settings.fStop]));
        sp.(seq{i, 1}) = s;
        raw(end+1) = struct('channel', k, 'config', seq{i, 1}, 'meas', m, 'spectra', s); %#ok<AGROW>
        coh = s.coherence(:, k); snr = min(s.snr_dB(:, [ref k]), [], 2);
        okBins = coh >= cfg.calibration.coherenceMin & snr >= cfg.calibration.snrMin_dB;
        report(struct('kind', 'measurement', 'channel', k, 'config', seq{i, 1}, ...
            'fracOk', mean(okBins), 'coherenceMedian', median(coh, 'omitnan'), ...
            'snrMedian_dB', median(snr, 'omitnan'), 'integrityOk', m.integrityOk));
    end
    o = struct('cohI', sp.I.coherence(:, k), 'cohII', sp.II.coherence(:, k), ...
        'snrI', min(sp.I.snr_dB(:, [ref k]), [], 2), 'snrII', min(sp.II.snr_dB(:, [ref k]), [], 2), ...
        'coherenceMin', cfg.calibration.coherenceMin, 'snrMin_dB', cfg.calibration.snrMin_dB);
    if isfield(sp, 'Irep'), o.HIrepeat = sp.Irep.H(:, k); end
    results{k} = tim.cal.switchingCorrection(sp.I.f, sp.I.H(:, k), sp.II.H(:, k), o);
    r = results{k};
    msg = sprintf('Channel %d: %d/%d valid bins', k, r.nValid, r.Nf);
    if ~isempty(r.repeatability)
        msg = sprintf('%s, re-mount repeatability max %.3f dB / %.2f deg', msg, ...
            r.repeatability.maxMag_dB, r.repeatability.maxPhase_deg);
    end
    session.log('%s', msg);
    for n = 1:numel(r.notes), session.log('  note: %s', r.notes{n}); end
    report(struct('kind', 'channel', 'channel', k, 'nValid', r.nValid, 'Nf', r.Nf, ...
        'repeatability', r.repeatability, 'text', msg));
end
home = zeros(1, 4); home([cfg.mics.channel]) = [cfg.mics.position];
session.throwIfStopped();
prompt(tim.app.msg(lang, 'calDone'), home);
meta = struct('mics', session.Mics, 'positions', ab, 'refChannel', ref, ...
    'excitation', cfg.excitation.sweep, 'mode', cfg.mode, 'software', tim.app.softwareVersion());
meta.tube = struct('specimenSection', 'empty', 'sectionLength_m', dSec, 'geometry', g, ...
    'environment', cfg.environment, 'note', ['Calibrated with the EMPTY specimen section mounted (no specimen): ' ...
    'tube continuous, port positions as in the measurement.']);
cal = tim.cal.buildCalibration(sp.I.f, results, ref, meta);
chk = struct('performed', false, 'passed', false, 'text', 'disabled (calibration.verifyEmptySection = false)');
if verify
    [chk, mE] = emptySectionCheck(session, cfg, cal);
    if ~isempty(mE)
        raw(end+1) = struct('channel', 0, 'config', 'emptyCheck', 'meas', mE, 'spectra', []);
    end
end
cal.meta.emptyCheck = chk;
report(struct('kind', 'verification', 'check', chk));
d = tim.app.outputDir(cfg, 'calibration');
if ~exist(d, 'dir'), mkdir(d); end
file = tim.app.uniqueName(fullfile(d, [cal.version '.mat']));
save(file, 'cal', 'raw', '-v7.3');
session.Calibration = cal;
session.log('Calibration %s saved to %s', cal.version, file);
% back to the measurement set-up (the calibration is already saved: an abort here loses nothing)
clear restoreSpecimen                              % simulation: the specimen section is mounted again
try
    prompt(tim.app.msg(lang, 'calMountSpecimen'), home);
    session.log('%s', tim.app.msg(lang, 'calMountSpecimen'));
catch err
    session.log('Last step not confirmed (%s): mount the specimen section before measuring.', err.message);
end
end

function [chk, m] = emptySectionCheck(session, cfg, cal)
% Test E with the EMPTY section and the microphones in their measurement ports:
% tau = exp(-j k_c d), R = Rterm exp(-2j k_c d). Checks the port coordinates
% (s1, s2, M2->M3 = L1 + d + L2) and the calibration; not the L1/d/L2 split.
m = []; g = cfg.geometry;
chk = struct('performed', false, 'passed', false, 'text', '');
if ~(all(isfinite(g.micPositions)) && isfinite(g.xFront) && isfinite(g.xRear))
    chk.text = 'skipped: geometry incomplete (enter L1, d, L2)';
elseif ~all(any(cal.valid, 1))
    chk.text = 'skipped: not all channels calibrated';
end
if ~isempty(chk.text), session.log('Empty-section check %s', chk.text); return; end
session.throwIfStopped();
session.log('Empty-section check (Test E): one sweep, empty section, microphones in their measurement ports.');
m = session.measure('sweep');
res = tim.app.processMeasurement(m, cfg, cal);
r = tim.val.testDE_reference(res, 'empty', struct());
chk = r; chk.performed = true; chk.measurementTimestamp = m.timestamp;
verdict = 'FAILED - check s1, L1 + d + L2 (M2->M3), s2, leaks, and that the EMPTY section is mounted';
if r.passed, verdict = 'passed'; end
chk.text = sprintf(['Test E, empty %g mm section: %s (|tau| error %.3f, tau phase error %.2f deg rms, ' ...
    'R consistency %.3f, %d valid bins)'], round(1e3 * r.gap_m, 3), verdict, r.tauMagError_median, ...
    r.tauPhaseError_deg_rms, r.RconsistencyError_median, r.validBins);
session.log('%s', chk.text);
end

function hardwarePrompt(msg, lang)
fprintf('\n>>> %s\n', msg);
input(tim.app.msg(lang, 'pressEnter'), 's');
end
