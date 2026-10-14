function out = runTwoLoad(session, opts)
%RUNTWOLOAD Two-load measurement of the specimen (ASTM E2611 [3]): A -> B -> A' (WO-005).
%
%   out = tim.app.runTwoLoad(session)
%   out = tim.app.runTwoLoad(session, opts)
%
%   The loads are session.Cfg.measurement.loadA and loadB (tim.app.describeLoad);
%   with measurement.repeatLoadA load A is measured again at the end (A'). For
%   every load, in turn:
%     1. a prompt names the load and how it is mounted (opts.prompt; the first
%        one asks to check load A, the others to change the termination);
%     2. session.setTermination(load): recorded in the measurement's metadata,
%        and in simulation the virtual rig mounts the load;
%     3. one measurement with cfg.excitation.mode - load B at
%        measurement.loadBLevel_dB relative to load A (only lower);
%     4. processing with session.Calibration (tim.app.processMeasurement);
%     5. saving AT ONCE in a folder of its own (tim.app.saveMeasurement, name
%        <kind>[_<specimen>]_load<role>_<tag>): a Stop, a cancel or an error
%        later keeps the loads measured so far.
%   Then the two-load result (tim.app.processTwoLoad) is computed and saved in
%   a pair folder (tim.app.saveTwoLoad) that names the load folders.
%
%   opts.prompt(msg, load, k, n)  before load k of n (n = 2 or 3). Default:
%           simulation - nothing (the rig mounts the load); hardware - the
%           message in the command window, Enter to go on
%   opts.report(q)   q.kind 'load' after every load (role, label, folder, res,
%           meas, k, n, load, cfg), 'saving' before the figures and the pair
%           folder are written (text), 'result' at the end (tl, folder)
%   opts.specimen    name for the folders and the metadata ('' = none)
%   opts.save        false: nothing is written (tests); default true
%   opts.figures     @(res, meas) -> struct of figures for a load folder
%           (the window: tim.app.plotResults), drawn and saved after the
%           last load (the data are saved at once); default none
%   opts.pairFigures @(tl, loads) -> struct of figures for the pair folder
%   opts.cfg         configuration of the loads, the analysis and the output
%           (the window's); default session.Cfg. The excitation and the mode
%           are always the session's
%
%   out.loads   struct array: role ('A', 'B', 'A2'), load, meas, res, folder, cfg
%   out.tl      the two-load result, [] when the sequence ended before load B
%   out.folder  the pair folder ('' when not saved)

if nargin < 2, opts = struct(); end
cfg = session.Cfg;
if isfield(opts, 'cfg') && ~isempty(opts.cfg)
    % the window's configuration: loads, analysis and output as set there;
    % the excitation and the mode are the session's
    cfg = opts.cfg; cfg.excitation = session.Cfg.excitation; cfg.mode = session.Cfg.mode;
    tim.app.validateConfig(cfg);
end
cfg = tim.app.analysisBand(cfg);
ms = cfg.measurement;
lang = session.lang();
if isfield(opts, 'prompt')
    prompt = opts.prompt;
elseif strcmp(cfg.mode, 'simulation')
    prompt = @(varargin) [];
else
    prompt = @(msg, varargin) hardwarePrompt(msg, lang);
end
report = @(q) []; if isfield(opts, 'report'), report = opts.report; end
doSave = ~isfield(opts, 'save') || opts.save;
specimen = ''; if isfield(opts, 'specimen'), specimen = strtrim(char(opts.specimen)); end
if strcmp(specimen, 'unnamed specimen'), specimen = ''; end
figFcn = []; if isfield(opts, 'figures'), figFcn = opts.figures; end

dA = tim.app.describeLoad(ms.loadA, cfg); dB = tim.app.describeLoad(ms.loadB, cfg);
if strcmp(dA.tag, dB.tag)
    error('tim:twoload:sameLoad', 'Load A and load B are both "%s": choose two different terminations.', dA.label);
end
steps = struct('role', {'A', 'B'}, 'load', {ms.loadA, ms.loadB}, 'desc', {dA, dB});
if ms.repeatLoadA
    steps(3) = struct('role', 'A2', 'load', ms.loadA, 'desc', dA);
end
n = numel(steps);
group = char(datetime('now'), 'yyyyMMdd_HHmmss');
session.beginOperation();                       % a Stop between the loads stays pending
opGuard = onCleanup(@() session.endOperation());
ex0 = cfg.excitation;
restoreLevel = onCleanup(@() restoreExcitation(session, ex0));
loads = struct('role', {}, 'load', {}, 'meas', {}, 'res', {}, 'folder', {}, 'cfg', {});
session.log('Two-load measurement (ASTM E2611): load A "%s", load B "%s"%s.', dA.label, dB.label, ...
    ternary(n == 3, ', load A repeated at the end', ''));
for k = 1:n
    st = steps(k);
    session.throwIfStopped();
    name = st.role; if strcmp(name, 'A2'), name = tim.app.msg(lang, 'tlRepeatName'); end
    mount = tim.app.msg(lang, ['tlMount_' st.desc.kind '_' st.desc.place], distText(st.desc.distance_m));
    if k == 1
        msg = tim.app.msg(lang, 'tlFirst', name, st.desc.label, mount);
    else
        msg = tim.app.msg(lang, 'tlSwap', name, st.desc.label, mount);
    end
    prompt(msg, st.load, k, n);
    session.throwIfStopped();
    session.log('%s', msg);
    session.setTermination(st.load);
    if strcmp(st.role, 'B') && ms.loadBLevel_dB < 0
        ex = ex0; md = ex.mode;
        ex.(md).amplitudeVpp = ex0.(md).amplitudeVpp * 10^(ms.loadBLevel_dB / 20);
        session.setExcitation(ex);
        session.log('Load B at %+.1f dB relative to load A: %.3g Vpk.', ms.loadBLevel_dB, ex.(md).amplitudeVpp / 2);
    elseif ~isequal(session.Cfg.excitation, ex0)
        session.setExcitation(ex0);
    end
    m = session.measure(cfg.excitation.mode);
    m.metadata.specimen = ternary(isempty(specimen), 'unnamed specimen', specimen);
    m.metadata.twoLoad = struct('group', group, 'role', st.role, 'loadA', dA.label, 'loadB', dB.label);
    c = cfg; c.excitation = session.Cfg.excitation;
    res = tim.app.processMeasurement(m, c, session.Calibration);
    folder = '';
    if doSave
        % the data at once (fast); the figures of all loads after the last one,
        % so that the operator does not wait for them between the loads
        nm = m.kind; if ~isempty(specimen), nm = sprintf('%s_%s', m.kind, specimen); end
        folder = tim.app.saveMeasurement(m, res, c, sprintf('%s_load%s_%s', nm, st.role, st.desc.tag));
        session.log('Load %s saved to %s', st.role, folder);
    end
    loads(end+1) = struct('role', st.role, 'load', st.load, 'meas', m, 'res', res, 'folder', folder, 'cfg', c); %#ok<AGROW>
    report(struct('kind', 'load', 'role', st.role, 'label', st.desc.label, 'folder', folder, 'res', res, ...
        'meas', m, 'k', k, 'n', n, 'load', st.load, 'cfg', c));
    if ~m.integrityOk
        session.log('Warning: load %s has data integrity problems - repeat the sequence at a lower level.', st.role);
    end
end
clear restoreLevel
tl = tim.app.processTwoLoad(loadsFor(loads), cfg);
session.log('Two-load result: %s.', tl.valid.summary);
if tl.repeat.performed, session.log('%s.', capital(tl.repeat.text)); end
if ~isempty(tl.level.text), session.log('%s.', capital(tl.level.text)); end
for w = reshape(tl.checks.warnings, 1, []), session.log('Warning: %s.', w{1}); end
for e = reshape(tl.checks.errors, 1, []), session.log('Error: %s - no transfer matrix.', e{1}); end
folder = '';
if doSave
    report(struct('kind', 'saving', 'text', 'drawing and saving the figures of the loads and the pair folder ...'));
end
if doSave && ~isempty(figFcn) && cfg.output.exportFigures
    for i = 1:numel(loads)
        figs = figFcn(loads(i).res, loads(i).meas);
        figEnd = onCleanup(@() closeFigures(figs));
        tim.app.exportFigures(figs, loads(i).folder, cfg.output.figureFormats);
        clear figEnd
    end
end
if doSave
    figs = [];
    if isfield(opts, 'pairFigures') && ~isempty(opts.pairFigures), figs = opts.pairFigures(tl, loads); end
    figEnd = onCleanup(@() closeFigures(figs));
    folder = tim.app.saveTwoLoad(tl, loads, cfg, specimen, figs);
    clear figEnd
    session.log('Two-load result saved to %s', folder);
end
session.log('%s', tim.app.msg(lang, 'tlDone', steps(end).desc.label));
report(struct('kind', 'result', 'tl', tl, 'folder', folder));
out = struct('loads', loads, 'tl', tl, 'folder', folder);
end

function L = loadsFor(loads)
% the processTwoLoad input of the measured loads
L = struct('role', {loads.role}, 'res', {loads.res}, 'load', {loads.load}, 'meas', {loads.meas}, ...
    'cfg', {loads.cfg}, 'folder', {loads.folder});
end

function t = distText(d)
if isfinite(d), t = sprintf('%g mm', round(1e3 * d, 1)); else, t = '?'; end
end

function restoreExcitation(session, ex0)
% the level of load A again after a lowered load B (also after a Stop or an error)
try
    if ~isequal(session.Cfg.excitation, ex0), session.setExcitation(ex0); end
catch
end
end

function closeFigures(figs)
if isempty(figs) || ~isstruct(figs), return; end
for f = reshape(fieldnames(figs), 1, [])
    h = figs.(f{1});
    if ~isempty(h) && all(isgraphics(h)), delete(h); end
end
end

function s = capital(s)
if ~isempty(s), s(1) = upper(s(1)); end
end

function v = ternary(c, a, b)
if c, v = a; else, v = b; end
end

function hardwarePrompt(msg, lang)
fprintf('\n>>> %s\n', msg);
input(tim.app.msg(lang, 'pressEnter'), 's');
end
