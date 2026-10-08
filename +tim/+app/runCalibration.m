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
%   recorded but unused). The TEST SPECIMEN IS REMOVED and the tube is
%   terminated anechoically (or with an absorber) so that no pressure node
%   falls on a calibration port; a first prompt shows this checklist.
%   See docs/calibration_procedure.md.
%
%   opts.prompt(msg, mapping): called before each configuration. In
%   hardware mode the default prints the instruction and waits for ENTER.
%   In simulation mode the default moves the microphones in the virtual rig.
%   opts.report(q): (optional) called after every measurement with its
%   quality (q.kind = 'measurement': channel, config, fracOk, coherence
%   and SNR medians) and after every channel (q.kind = 'channel': nValid,
%   Nf, repeatability) - used by the GUI step list.
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
session.beginOperation();                       % STOP between steps stays pending
opGuard = onCleanup(@() session.endOperation());
% step 0: preparation checklist (test specimen removed, anechoic/absorbing
% termination, ports sealed); microphones in their measurement ports
home0 = zeros(1, 4); home0([cfg.mics.channel]) = [cfg.mics.position];
prompt(tim.app.msg(lang, 'calPrepare', ab(1), ab(2)), home0);
session.log('%s', tim.app.msg(lang, 'calPrepare', ab(1), ab(2)));
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
prompt(tim.app.msg(lang, 'calDone'), home);
meta = struct('mics', session.Mics, 'positions', ab, 'refChannel', ref, ...
    'excitation', cfg.excitation.sweep, 'mode', cfg.mode, 'software', tim.app.softwareVersion());
cal = tim.cal.buildCalibration(sp.I.f, results, ref, meta);
d = tim.app.outputDir(cfg, 'calibration');
if ~exist(d, 'dir'), mkdir(d); end
file = tim.app.uniqueName(fullfile(d, [cal.version '.mat']));
save(file, 'cal', 'raw', '-v7.3');
session.Calibration = cal;
session.log('Calibration %s saved to %s', cal.version, file);
end

function hardwarePrompt(msg, lang)
fprintf('\n>>> %s\n', msg);
input(tim.app.msg(lang, 'pressEnter'), 's');
end
