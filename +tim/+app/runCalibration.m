function [cal, file, raw] = runCalibration(session, opts)
%RUNCALIBRATION Sequential switching calibration (microphone switching) of all channels.
%
%   [cal, file] = tim.app.runCalibration(session)
%   [cal, file] = tim.app.runCalibration(session, struct('channels', [2 3 4], 'prompt', @fn))
%
%   For every channel k ~= ref (ref = cfg.analysis.refChannel), with the
%   calibration ports a, b = cfg.calibration.positions:
%     I   : reference microphone in port a, microphone k in port b -> measure
%     I'  : (optional) remove and reinsert both, same ports        -> repeat
%     II  : interchange the two microphones (each keeps its own cable /
%           preamplifier / DAQ input)                              -> measure
%   The remaining microphones stay in the other ports (their signals are
%   recorded but unused). The empty specimen section (lab: 75 mm,
%   SIT-PT-003, without specimen) is mounted, so the tube is continuous
%   and every port keeps its measurement position; the absorbing
%   termination keeps pressure nodes away from the calibration ports.
%   A first prompt shows this checklist.
%   After the switching measurements (cfg.calibration.verifyEmptySection)
%   one sweep with the microphones in their measurement ports is evaluated
%   as the empty-tube check, Test E (tau = exp(-j k d)), stored in
%   cal.meta.emptyCheck; cal.meta.tube records the set-up (section, length,
%   geometry, environment) and cal.meta.acquisition the DAQ chain the factors
%   include (driver, module identity, input settings; session.acquisitionChain,
%   compared by tim.cal.calibrationContext). The last prompt asks to mount the specimen
%   section again. In simulation the virtual rig models the empty specimen
%   section (sample 'air') during the calibration and gets its specimen
%   back afterwards, also after an error or Stop. See docs/calibration_procedure.md.
%
%   The chain gain of channel k is g_k; the result is the calibration
%   factor C_k = g_k / g_ref (tim.cal.switchingCorrection).
%
%   opts.prompt(msg, mapping): called before each configuration. In
%   hardware mode the default prints the instruction and waits for Enter.
%   In simulation mode the default moves the microphones in the virtual rig.
%   opts.report(q): (optional) called after every measurement with its
%   quality (q.kind = 'measurement': channel, config, fracOk, coherence
%   and SNR medians), after every channel (q.kind = 'channel': nValid,
%   Nf, repeatability) and after the empty-tube check (q.kind =
%   'verification', q.check) - used by the GUI step list.
%   Every raw measurement is returned in raw and saved with the calibration.
%   The file is written (and adopted: session.Calibration,
%   session.CalibrationFile) before the "return the microphones" prompt, so
%   a cancel, Stop or error from there on keeps the calibration.

if nargin < 2, opts = struct(); end
cfg = tim.app.analysisBand(session.Cfg);   % analysis.bandMode 'geometry': the ASTM band of the tube
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
dSec = sectionLength(cfg);                      % length of the (empty) specimen section, lab: 75 mm
secTxt = '';
if isfinite(dSec) && dSec > 0, secTxt = sprintf(' (%g mm)', round(1e3 * dSec, 3)); end
verify = ~isfield(cfg.calibration, 'verifyEmptySection') || cfg.calibration.verifyEmptySection;
session.beginOperation();                       % STOP between steps stays pending
opGuard = onCleanup(@() session.endOperation());
% the absorbing termination the first prompt asks for (WO-005): recorded with
% every calibration sweep; in simulation the virtual rig gets it. It stays the
% session's termination afterwards (it is mounted); the window sets its own
% choice again before every measurement
session.setTermination(struct('kind', 'absorber', 'place', 'tubeEnd'));
home0 = zeros(1, 4); home0([cfg.mics.channel]) = [cfg.mics.position];
if strcmp(cfg.mode, 'simulation') && ~isempty(session.Rig)
    % the virtual microphones go back to their measurement ports on every
    % exit (a Stop, Cancel or error in a switching step left them in the
    % calibration ports, and the next measurement read swapped microphones)
    restoreMics = onCleanup(@() homeMics(session, home0));
    specimen = session.setSimulationSample(struct('type', 'air'));          % operator mounts the empty section
    restoreSpecimen = onCleanup(@() session.setSimulationSample(specimen));  % also on error / STOP
end
% step 0: preparation checklist (empty specimen section mounted, absorbing
% termination, ports sealed); microphones in their measurement ports
prompt(tim.app.msg(lang, 'calPrepare', secTxt, ab(1), ab(2)), home0);
session.log('%s', tim.app.msg(lang, 'calPrepare', secTxt, ab(1), ab(2)));
results = cell(1, 4);
raw = struct('channel', {}, 'config', {}, 'meas', {}, 'spectra', {});
% data integrity of every switching sweep (clipping, overload, device flags):
% recorded with the calibration and checked by tim.cal.calibrationContext
integrity = struct('channel', {}, 'config', {}, 'ok', {}, 'problems', {});
try
    for k = chans
        others = setdiff(1:4, [ref k]);
        otherPos = setdiff(1:4, ab);
        mapI = zeros(1, 4); mapI(ref) = ab(1); mapI(k) = ab(2); mapI(others) = otherPos;
        mapII = mapI; mapII(ref) = ab(2); mapII(k) = ab(1);
        seq = {'I', mapI, tim.app.msg(lang, 'calConfigI', k, ref, ab(1), k, ab(2))};
        if cfg.calibration.repeatConfigI
            seq(end+1, :) = {'Irep', mapI, tim.app.msg(lang, 'calConfigIrep', k)}; %#ok<AGROW>
        end
        seq(end+1, :) = {'II', mapII, tim.app.msg(lang, 'calConfigII', k, ref, ab(2), k, ab(1))}; %#ok<AGROW>
        sp = struct();
        for i = 1:size(seq, 1)
            session.throwIfStopped();
            prompt(seq{i, 3}, seq{i, 2});
            session.throwIfStopped();
            session.log('%s', seq{i, 3});
            m = session.measure('sweep');
            s = tim.dsp.sweepResponse(m.records, m.fs, struct('refChannel', ref, 'fRange', [a.fMin a.fMax], ...
                'df', a.df, 'preRoll', m.settings.preRoll, 'excitationBand', [m.settings.fStart m.settings.fStop], ...
                'sweep', m.settings));    % sweep gate: generator on/off transients excluded
            for w = reshape(s.warnings, 1, []), session.log('Warning: %s', w{1}); end
            sp.(seq{i, 1}) = s;
            raw(end+1) = struct('channel', k, 'config', seq{i, 1}, 'meas', m, 'spectra', s); %#ok<AGROW>
            integrity(end+1) = struct('channel', k, 'config', seq{i, 1}, 'ok', m.integrityOk, ...
                'problems', {integrityProblems(m)}); %#ok<AGROW>
            if ~m.integrityOk
                session.log(['Warning: configuration %s of ch%d has data integrity problems (%s): the calibration ' ...
                    'factor C%d may be wrong - repeat the calibration at a lower level.'], seq{i, 1}, k, ...
                    strjoin(integrity(end).problems, '; '), k);
            end
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
        try
            results{k} = tim.cal.switchingCorrection(sp.I.f, sp.I.H(:, k), sp.II.H(:, k), o);
        catch err
            if ~strcmp(err.identifier, 'tim:cal:noValidBins'), rethrow(err); end
            % a dead or unplugged input: this channel stays uncalibrated, the
            % other channels and every raw sweep are kept and saved
            results{k} = [];
            msg = sprintf(['C%d (ch%d/ch%d): no valid frequency line (coherence or SNR too low) - check the ' ...
                'microphone, cable and input of ch%d; channel not calibrated'], k, k, ref, k);
            session.log('%s', msg);
            report(struct('kind', 'channel', 'channel', k, 'nValid', 0, 'Nf', numel(sp.I.f), ...
                'repeatability', [], 'text', msg));
            continue
        end
        r = results{k};
        msg = sprintf('C%d (ch%d/ch%d): %d of %d frequency lines valid', k, k, ref, r.nValid, r.Nf);
        if ~isempty(r.repeatability)
            msg = sprintf('%s; remounting repeatability max. %.3f dB / %.2f°', msg, ...
                r.repeatability.maxMag_dB, r.repeatability.maxPhase_deg);
        end
        session.log('%s', msg);
        for n = 1:numel(r.notes), session.log('  Note: %s', r.notes{n}); end
        report(struct('kind', 'channel', 'channel', k, 'nValid', r.nValid, 'Nf', r.Nf, ...
            'repeatability', r.repeatability, 'text', msg));
    end
catch err
    % the calibration ends before it was saved (Stop, Cancel, an error): the
    % microphones may sit in the calibration ports (simulation: moved back)
    if ~strcmp(cfg.mode, 'simulation')
        session.log('%s', tim.app.msg(lang, 'calAborted'));
    end
    rethrow(err);
end
home = zeros(1, 4); home([cfg.mics.channel]) = [cfg.mics.position];
session.throwIfStopped();
meta = struct('mics', session.Mics, 'positions', ab, 'refChannel', ref, ...
    'excitation', cfg.excitation.sweep, 'mode', cfg.mode);
[meta.software, meta.softwareInfo] = tim.app.softwareVersion();
meta.tube = struct('specimenSection', 'empty', 'sectionLength_m', dSec, ...
    'specimenThickness_m', g.xRear - g.xFront, 'geometry', g, 'environment', cfg.environment, ...
    'note', ['Calibrated with the empty specimen section mounted (no specimen): ' ...
    'tube continuous, port positions as in the measurement.']);
meta.acquisition = session.acquisitionChain();   % C_k includes the DAQ inputs: driver, module, input settings
meta.integrity = integrity;                       % per switching sweep: ok, problems (calibrationContext warns)
cal = tim.cal.buildCalibration(sp.I.f, results, ref, meta);
[willCheck, why] = checkPossible(verify, g, cal);
% save NOW, before the "return the microphones" step: C_k does not depend on the
% empty-tube check; cancelling that step, a Stop or an error during the check
% must not lose the switching measurements
if willCheck
    cal.meta.emptyCheck = struct('performed', false, 'passed', false, 'text', 'not performed yet (calibration saved before the check)');
else
    cal.meta.emptyCheck = struct('performed', false, 'passed', false, 'text', ['not performed: ' why]);
end
d = tim.app.outputDir(cfg, 'calibration');
if ~exist(d, 'dir'), mkdir(d); end
file = tim.app.uniqueName(fullfile(d, [cal.version '.mat']));
save(file, 'cal', 'raw', '-v7.3');
session.Calibration = cal;
session.CalibrationFile = file;                 % the GUI keeps this path also when the next step is cancelled
session.log('Calibration %s saved to %s', cal.version, file);
try
    if willCheck
        prompt(tim.app.msg(lang, 'calDone'), home);
    else
        prompt(tim.app.msg(lang, 'calDoneNoCheck', why), home);
    end
catch err
    % every error at this step (cancel, Stop, or an error of the prompt
    % callback): the saved file and the step list get the final reason
    % instead of 'not performed yet' (review analysis-7)
    if any(strcmp(err.identifier, {'tim:gui:abort', 'tim:session:stopped'}))
        cal.meta.emptyCheck.text = 'not performed: cancelled by the operator – calibration saved without the empty-tube check';
    else
        cal.meta.emptyCheck.text = ['not performed: error – calibration saved without the empty-tube check: ' ...
            regexprep(err.message, '\.$', '')];
    end
    save(file, 'cal', 'raw', '-v7.3');
    session.Calibration = cal;
    session.log('Empty-tube check (Test E): %s', cal.meta.emptyCheck.text);
    report(struct('kind', 'verification', 'check', cal.meta.emptyCheck));
    rethrow(err);
end
if willCheck
    try
        [chk, mE] = emptySectionCheck(session, cfg, cal);
        if ~isempty(mE)
            raw(end+1) = struct('channel', 0, 'config', 'emptyCheck', 'meas', mE, 'spectra', []);
        end
    catch err
        if strcmp(err.identifier, 'tim:session:stopped')
            txt = 'stopped by the operator – calibration saved without the empty-tube check';
        else
            txt = ['error – calibration saved without the empty-tube check: ' err.message];
        end
        chk = struct('performed', false, 'passed', false, 'text', txt);
        session.log('Empty-tube check (Test E): %s', txt);
    end
    cal.meta.emptyCheck = chk;
    save(file, 'cal', 'raw', '-v7.3');                 % same file, now with the check
    session.Calibration = cal;
end
report(struct('kind', 'verification', 'check', cal.meta.emptyCheck));
% back to the measurement set-up (the calibration is already saved: a stop here loses nothing)
clear restoreSpecimen                              % simulation: the specimen section is mounted again
try
    prompt(tim.app.msg(lang, 'calMountSpecimen'), home);
    session.log('%s', tim.app.msg(lang, 'calMountSpecimen'));
catch err
    session.log('Warning: last calibration step not confirmed (%s) – mount the specimen section before measuring.', ...
        regexprep(err.message, '\.$', ''));
end
end

function L = sectionLength(cfg)
% length of the removable specimen section: tubeDrawing.specimenSectionLength
% (CAD, lab 75 mm); otherwise the specimen thickness if it is >= 1 mm
L = NaN;
if isfield(cfg, 'tubeDrawing') && isfield(cfg.tubeDrawing, 'specimenSectionLength')
    L = cfg.tubeDrawing.specimenSectionLength;
end
if ~(isscalar(L) && isfinite(L) && L > 0)
    d = cfg.geometry.xRear - cfg.geometry.xFront;
    L = NaN; if isfinite(d) && d >= 1e-3, L = d; end
end
end

function [ok, why] = checkPossible(verify, g, cal)
% will the empty-tube check (Test E) be measured?
ok = false;
if ~verify
    why = 'disabled (calibration.verifyEmptySection = false)';
elseif ~(all(isfinite(g.micPositions)) && isfinite(g.xFront) && isfinite(g.xRear))
    why = 'geometry incomplete (enter L1, d, L2)';
elseif ~all(any(cal.valid, 1))
    why = 'not all channels calibrated';
else
    ok = true; why = '';
end
end

function [chk, m] = emptySectionCheck(session, cfg, cal)
% Test E (empty-tube check) with the empty specimen section and the microphones
% in their measurement ports: tau = exp(-j k_c d), R = Rterm exp(-2j k_c d).
% Checks the port coordinates (s1, s2, M2 -> M3 = L1 + d + L2) and the
% calibration; not the L1/d/L2 split. Called only when checkPossible() is true.
session.throwIfStopped();
session.log(['Empty-tube check (Test E): one sweep with the empty specimen section mounted ' ...
    'and the microphones in their measurement ports.']);
m = session.measure('sweep');
if ~m.integrityOk
    % a clipped or flagged check sweep says nothing about the calibration:
    % not evaluated (neither passed nor failed)
    chk = struct('performed', false, 'passed', false, 'text', ['not evaluated: data integrity problems in the ' ...
        'check sweep (' strjoin(integrityProblems(m), '; ') ') - repeat it at a lower level'], ...
        'measurementTimestamp', m.timestamp);
    session.log('Empty-tube check (Test E): %s', chk.text);
    return
end
res = tim.app.processMeasurement(m, cfg, cal);
r = tim.val.testDE_reference(res, 'empty', struct());
chk = r; chk.performed = true; chk.measurementTimestamp = m.timestamp;
if r.validBins == 0
    chk.text = ['Test E failed: no frequency line meets the geometry and quality criteria (check coherence, ' ...
        'SNR and calibration validity; the check measurement is saved with the raw calibration measurements)'];
else
    verdict = 'failed – check s1, L1 + d + L2 (M2 → M3), s2, leaks, and that the empty specimen section is mounted';
    if r.passed, verdict = 'passed'; end
    chk.text = sprintf(['Test E, empty specimen section (d = %g mm): %s (|τ| error %.3f, τ phase error %.2f° rms, ' ...
        'R consistency %.3f, %d frequency lines evaluated)'], round(1e3 * r.gap_m, 3), verdict, r.tauMagError_median, ...
        r.tauPhaseError_deg_rms, r.RconsistencyError_median, r.validBins);
end
session.log('%s', chk.text);
end

function p = integrityProblems(m)
% the fatal integrity findings of all repetitions of a measurement (texts)
p = {};
for i = 1:numel(m.channelInfo)
    g = m.channelInfo{i}.integrity;
    if isfield(g, 'fatal'), p = [p, reshape(cellstr(g.fatal), 1, [])]; end %#ok<AGROW>
end
p = unique(p, 'stable');
if isempty(p) && ~m.integrityOk, p = {'integrity check failed'}; end
end

function homeMics(session, home)
% simulation: the virtual microphones back in their measurement ports (no
% change, and no re-design of the rig, when they are there already)
try
    if ~isempty(session.Rig) && ~isequal(session.Rig.MicPosOfChannel, home)
        session.setMicPositionsForSimulation(home);
    end
catch
end
end

function hardwarePrompt(msg, lang)
fprintf('\n>>> %s\n', msg);
input(tim.app.msg(lang, 'pressEnter'), 's');
end
