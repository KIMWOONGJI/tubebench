function res = processMeasurement(meas, cfg, cal)
%PROCESSMEASUREMENT Raw recordings -> calibrated relative pressures -> acoustics.
%
%   res = tim.app.processMeasurement(meas, cfg, cal)
%
%   1) relative channel responses Y_c/Y_ref (method depends on meas.kind)
%   2) complex calibration (cal may be empty -> nothing will be "valid")
%   3) channel -> tube-position reordering (cfg.mics(c).position)
%   4) four-microphone analysis with validity diagnostics (stepped sine, 1.6.0:
%      also the settled check, flag notSettled; res.spectra.settleDrift)
%   5) absolute pressure spectra (sensitivities) for display only
%   6) level at the specimen front face (res.levels, 1.6.0): incident pressure
%      [dB SPL] and particle velocity [mm/s] from the calibrated decomposition
%      and the sensitivity of the reference microphone (swept / stepped sine)
%   7) an equalized stepped sine (meas.equalizer, 1.6.0): res.equalizer, the
%      achieved level of every step against the target (report only)
%   The raw data in meas are never modified.

if nargin < 3, cal = []; end
cfg = tim.app.analysisBand(cfg);      % analysis.bandMode 'geometry': the ASTM band of cfg.geometry
a = cfg.analysis;
fs = meas.fs;
ref = a.refChannel;
res = struct('kind', meas.kind, 'timestamp', meas.timestamp, 'softwareVersion', tim.app.softwareVersion());
res.diagnostics = struct('warnings', {{}});    % 1x0 cell; every warning is appended with {end+1}

switch meas.kind
    case 'sweep'
        s = meas.settings;
        sp = tim.dsp.sweepResponse(meas.records, fs, struct('refChannel', ref, ...
            'fRange', [a.fMin a.fMax], 'df', a.df, 'preRoll', s.preRoll, ...
            'excitationBand', [s.fStart s.fStop], 'ringDown', min(s.postRoll, 0.5), 'sweep', s));   % sweep gate: generator on/off transients excluded
        % excitation diagnostics OUTSIDE the try below (that one is only for
        % estimateSweepLaw): appending to a missing warnings field used to throw
        % and was stored as a false sweepLawError (formula review dsp-3)
        res.diagnostics.excitation = sp.excitation;
        if ~all([sp.excitation.detected])
            res.diagnostics.warnings{end+1} = 'Excitation not detected in at least one repetition.';
        end
        ex = sp.excitation(1);
        if ex.detected && ex.start_s < 0.5 * s.preRoll
            res.diagnostics.warnings{end+1} = 'Excitation started early in the pre-roll: noise estimate unreliable.';
        end
        if isfield(sp, 'warnings') && ~isempty(sp.warnings)
            w = sp.warnings; if ischar(w), w = {w}; end
            res.diagnostics.warnings = [res.diagnostics.warnings, reshape(w, 1, [])];
        end
        try
            law = tim.dsp.estimateSweepLaw(meas.records{1}(:, ref), fs, s.fStart, s.fStop, s.spacing, s.duration);
            res.diagnostics.sweepLaw = rmfield(law, {'ridgeT', 'ridgeF'});
            res.diagnostics.sweepLaw.nominalDuration_s = s.duration;
            res.diagnostics.sweepLaw.durationError = law.duration_s / s.duration - 1;
        catch err
            res.diagnostics.sweepLawError = err.message;
        end
    case 'stepped'
        sp = steppedSpectra(meas, ref);
    case 'noise'
        ev = meas.events{1};
        x = meas.records{1};
        i1 = max(1, ev.onSample + round(0.2 * fs)); i2 = min(size(x, 1), ev.offSample);
        if ~(i2 > i1), i1 = 1; i2 = size(x, 1); end
        fGrid = (a.fMin:a.df:a.fMax).';
        sp = tim.dsp.welchResponse(x(i1:i2, :), fs, struct('refChannel', ref, ...
            'nfft', meas.settings.nfft, 'fGrid', fGrid));
    otherwise
        error('tim:process:kind', 'Cannot process measurement kind "%s".', meas.kind);
end
res.spectra = sp;
f = sp.f(:);

% ---- calibration
[Hcal, calValid, calInfo, calValidCh, calOutside] = tim.cal.applyCalibration(f, sp.H, cal, ref);
res.calibration = struct('applied', ~isempty(cal), 'info', calInfo, 'version', 'none');
if ~isempty(cal), res.calibration.version = cal.version; end
% calibration set-up vs this measurement (empty section, port distances, temperature, mode,
% DAQ chain: driver, module, input settings - from the measurement's metadata)
res.calibration.context = tim.cal.calibrationContext(cal, cfg, meas);
if ~isempty(res.calibration.context.warnings)
    res.diagnostics.warnings = [res.diagnostics.warnings, reshape(res.calibration.context.warnings, 1, [])];
end
res.Hchannel = Hcal;

% ---- channel -> position
pos = [cfg.mics.position]; ch = [cfg.mics.channel];
% the mapping the data were recorded with (meas.mics) - a configuration with
% another mapping (re-cabled since, another file loaded) swaps microphones
% in the wave decomposition: used as configured (e.g. to correct a known
% cabling error), but reported
if isfield(meas, 'mics') && isstruct(meas.mics) && all(isfield(meas.mics, {'channel', 'position'})) && ...
        numel(meas.mics) == numel(ch)
    recorded = zeros(1, 4); recorded([meas.mics.channel]) = [meas.mics.position];
    used = zeros(1, 4); used(ch) = pos;
    if ~isequal(recorded, used)
        txt = @(m) strjoin(arrayfun(@(c) sprintf('ch%d M%d', c, m(c)), 1:4, 'UniformOutput', false), ', ');
        res.diagnostics.warnings{end+1} = sprintf(['Microphone mapping of the configuration (%s) differs from the ' ...
            'one this measurement was recorded with (%s): the results use the configuration''s mapping. Load the ' ...
            'measurement''s own configuration unless the cabling was recorded wrongly.'], txt(used), txt(recorded));
    end
end
Hp = zeros(numel(f), 4); cohP = ones(numel(f), 4); snrP = inf(numel(f), 4); calP = false(numel(f), 4);
for i = 1:4
    Hp(:, pos(i)) = Hcal(:, ch(i));
    cohP(:, pos(i)) = sp.coherence(:, ch(i));
    snrP(:, pos(i)) = sp.snr_dB(:, ch(i));
    calP(:, pos(i)) = calValidCh(:, ch(i));
end
res.Hposition = Hp;
res.channelOfPosition = zeros(1, 4); res.channelOfPosition(pos) = ch;   % DAQ channel in port M1..M4 (plot colours)

% ---- acoustics
o = rmfield(a, {'refChannel', 'fMin', 'fMax', 'df'});
o.quality = struct('coherence', cohP, 'snr_dB', snrP);
% stepped sine: the settled check (1.6.0, owner decision 2026-11-04), the
% excess drift of every port (analysis.settleDriftMax); a sweep or noise
% result has no such quality and no flag notSettled
if isfield(sp, 'settleDrift')
    sdP = nan(numel(f), 4);
    for i = 1:4, sdP(:, pos(i)) = sp.settleDrift(:, ch(i)); end
    o.quality.settleDrift = sdP;
end
o.calValid = calValid;
o.calValidPos = calP;          % per position: R needs only the calibration of M1/M2 (review analysis-3)
o.calOutside = calOutside;     % outside the calibration range: nearest calibrated line held, never valid (1.5.1)
o.fRange = [a.fMin a.fMax];
res.analysis = tim.acoustics.analyzeFourMic(f, Hp, cfg.geometry, cfg.environment, o);

% ---- absolute pressure spectra (display / SPL only). Record column c is DAQ
% channel c: the sensitivities are taken by mics.channel, not by the order of
% the list (a configuration may list ch2 before ch1; review plots-11)
mics = struct([]);
if isfield(meas, 'mics'), mics = tim.app.MeasurementSession.micsByChannel(meas.mics); end
chCol = 1:4; if isfield(mics, 'channel'), chCol = [mics.channel]; end
% data in full-scale units (a driver with an unknown input scale,
% docs/instrument_interface.md section 4.2): no sensitivity layer, no Pa / dB SPL
unit = 'V'; if isfield(meas, 'unit') && ~isempty(meas.unit), unit = char(meas.unit); end
volts = strcmp(unit, 'V');
try
    x = meas.records{1};
    nfft = min(8192, 2^nextpow2(size(x, 1)));
    if volts
        p = tim.acq.voltsToPascal(x - mean(x, 1), mics, 'V');
        [P, fp] = pwelch(p, hann(nfft, 'periodic'), 3 * nfft / 4, nfft, fs);   % 75 %: no ripple for a sweep (1.6.4)
        res.pressureSpectrum = struct('f', fp, 'PSD_Pa2perHz', P, 'channelOrder', chCol, ...
            'note', 'Uses the sensitivity layer (TEDS/certificate/nominal) only.');
    else
        [P, fp] = pwelch(x - mean(x, 1), hann(nfft, 'periodic'), 3 * nfft / 4, nfft, fs);
        res.pressureSpectrum = struct('f', fp, 'PSD', P, 'unit', unit, 'channelOrder', chCol, ...
            'note', sprintf('Data in %s (input scale unknown): no sound pressure levels.', unit));
    end
catch err
    res.pressureSpectrum = struct('error', err.message);
end
% ---- stepped sine: level of every step (display / SPL only). The PSD of a
% stepped record is a LINE spectrum (one narrow line per step, each holding
% 1/nSteps of the record energy) - not a useful level display.
if strcmp(meas.kind, 'stepped')
    if ~volts, mics = struct([]); end           % no sensitivities: spl_dB NaN
    res.toneLevels = steppedLevels(sp, mics, chCol);
    res.toneLevels.unit = unit;
end
% ---- level at the specimen front face (1.6.0, WO-006 stage 1): incident
% pressure [dB SPL] and particle velocity [mm/s] per line, for the Spectrum
% view, results.csv and the equalizer of the stepped sine; never a reason for
% the processing to fail
try
    res.levels = specimenLevels(meas, res, sp, mics, chCol, ref, volts, unit);
catch err
    res.levels = emptyLevels(meas.kind, f, ref);
    res.levels.note = ['Level at the specimen not computed: ' err.message];
end
% ---- level equalizer of the stepped sine (1.6.0, WO-006 stage 2): the level
% each step achieved against the target, recomputed from res.levels (also on
% Reprocess). Report only (owner decision 2026-11-04): a step that misses the
% target is never masked, no validity flag
if isfield(meas, 'equalizer') && isstruct(meas.equalizer) && isscalar(meas.equalizer)
    try
        res.equalizer = equalizerResult(meas.equalizer, res.levels);
    catch err
        res.diagnostics.warnings{end+1} = ['Equalizer result not computed: ' err.message];
    end
end
res.summary = res.analysis.valid.summary;
end

function q = equalizerResult(plan, lv)
% res.equalizer: per step the generator level played (plan.vpp), the limit
% the plan met (plan.limited: '' | 'max' | 'min' | 'unknown'), the achieved
% controlled quantity (res.levels: dB SPL or mm/s), its deviation from the
% target in dB and whether it lies within the tolerance (NaN: not reached).
% q.plan is the plan with the pre-measurement result (meas.equalizer).
f = lv.f(:);
n = numel(f);
vpp = reshape(double(plan.vpp), [], 1);
if numel(vpp) ~= n
    error('tim:process:equalizer', 'The equalizer plan has %d steps, the measurement %d.', numel(vpp), n);
end
switch plan.mode
    case 'incidentPressure'
        achieved = lv.incident_dB_SPL(:);
        dev = achieved - plan.target;
    case 'faceVelocity'
        achieved = lv.faceVelocity_mm_s(:);
        dev = 20 * log10(achieved / plan.target);
    otherwise
        error('tim:process:equalizer', 'Unknown equalizer mode "%s".', char(string(plan.mode)));
end
dev(~isfinite(dev)) = NaN;
reached = abs(dev) <= plan.tolerance_dB;             % NaN: false
limited = reshape(cellstr(plan.limited), [], 1);
txt = sprintf('Equalizer (%s, target %g %s ± %g dB): target reached at %d of %d steps', plan.mode, plan.target, ...
    plan.unit, plan.tolerance_dB, nnz(reached), n);
if ~lv.available
    txt = sprintf('%s - no level at the specimen (%s)', txt, regexprep(lv.note, '\.$', ''));
elseif any(~reached)
    hz = strjoin(arrayfun(@(x) sprintf('%.0f', x), f(~reached), 'UniformOutput', false), ', ');
    txt = sprintf('%s; not reached at %s Hz (%d of them at the maximum)', txt, hz, nnz(~reached & strcmp(limited, 'max')));
end
q = struct('mode', plan.mode, 'unit', plan.unit, 'target', plan.target, 'tolerance_dB', plan.tolerance_dB, ...
    'f', f, 'vpp', vpp, 'limited', {limited}, 'achieved', achieved, 'deviation_dB', dev, 'reached', reached, ...
    'nReached', nnz(reached), 'text', [txt '.'], 'plan', plan);
end

function sp = steppedSpectra(meas, ref)
st = meas.settings;
freqs = st.frequencies;
nF = numel(freqs);
H = zeros(nF, 4); coh = zeros(nF, 4); snr = zeros(nF, 4); fHat = zeros(nF, 1); se = zeros(nF, 4);
amp = nan(nF, 4);                       % fitted tone amplitude per step and channel [V peak]
sd = nan(nF, 4); bd = nan(nF, 4);       % settled check: excess drift and drift per step and channel
% Settled check (1.6.0, owner decision 2026-11-04): the drift of the channel
% ratio from the first to the last block (tim.dsp.sineResponse: drift) beyond
% zSettle standard deviations of its noise (driftSigma). Noise alone exceeds
% it with the probability e^(-zSettle^2) = e^-16 (about 1e-7) per channel and
% step, so the excess is a systematic change: a transient that has not
% decayed. The worst repetition counts; a skipped repetition or a single
% block gives NaN (not judged). analysis.settleDriftMax (validityMasks) is
% the limit of the excess. The noise of the drift comes from the pre-roll of
% the repetition (output off: noise only), not from the residual of the step,
% which holds the transient itself (review 2026-11-05); a record without a
% pre-roll of 0.1 s (synthetic data) uses the residual.
zSettle = 4;
nR = numel(meas.records);
noise = cell(1, nR);
for r = 1:nR, noise{r} = prerollNoise(meas, r); end
for k = 1:nF
    % SNR NaN for a skipped repetition (min ignores NaN): otherwise 0 dB would make the
    % noise level equal to the tone level; coherence 0 still invalidates the step
    Hs = zeros(nR, 4); cs = zeros(nR, 4); ss = nan(nR, 4); fh = nan(nR, 1); es = zeros(nR, 4);
    as = nan(nR, 4); dr = nan(nR, 4); ds = nan(nR, 4);
    for r = 1:nR
        idx = tim.app.steppedSegment(meas, r, k);
        if isempty(idx)
            Hs(r, :) = NaN; continue
        end
        opt = struct('refChannel', ref, 'nBlocks', st.nBlocks);
        if ~isempty(noise{r}), opt.noisePsd = noise{r}; end
        o = tim.dsp.sineResponse(meas.records{r}(idx, :), meas.fs, freqs(k), opt);
        Hs(r, :) = o.H; cs(r, :) = o.coherence; ss(r, :) = o.snr_dB; fh(r) = o.f; es(r, :) = o.stdErr;
        as(r, :) = o.amplitude; dr(r, :) = o.drift; ds(r, :) = o.driftSigma;
    end
    H(k, :) = mean(Hs, 1, 'omitnan'); coh(k, :) = min(cs, [], 1); snr(k, :) = min(ss, [], 1);
    fHat(k) = mean(fh, 'omitnan');      % a skipped repetition must not average in 0 Hz
    se(k, :) = sqrt(mean(es.^2, 1)) / sqrt(nR);
    amp(k, :) = mean(as, 1, 'omitnan');
    ex = dr - zSettle * ds;
    ex(ex < 0) = 0;                     % within the noise: 0 (NaN stays NaN: not judged)
    sd(k, :) = max(ex, [], 1);          % max ignores NaN; NaN only when no repetition was judged
    bd(k, :) = max(dr, [], 1);
end
sp = struct('f', freqs(:), 'fObserved', fHat, 'H', H, 'coherence', coh, 'snr_dB', snr, ...
    'stdErr', se, 'amplitude_V', amp, 'settleDrift', sd, 'blockDrift', bd, 'refChannel', ref, ...
    'method', 'stepped sine, 3-parameter LS sine fit at data-estimated frequency');
end

function nz = prerollNoise(meas, r)
% One-sided noise PSD of the pre-roll of repetition r - the samples received
% before the output went on (events.onSample; tim.app.steppedPlan: 0.5 s),
% noise only - for the noise of the settled check (tim.dsp.sineResponse,
% opts.noisePsd). [] with less than 0.1 s of it (synthetic records): the
% residual of the step is used. Segments of about 0.25 s (4 Hz at 16384 Hz)
% for the band 10-100 Hz around each step, 50 % overlap.
nz = [];
fs = meas.fs;
if ~isfield(meas, 'events') || numel(meas.events) < r || ~isstruct(meas.events{r}) || ...
        ~isfield(meas.events{r}, 'onSample')
    return
end
n0 = meas.events{r}.onSample;
x = meas.records{r};
if ~(isscalar(n0) && isfinite(n0)), return; end
n0 = min(floor(n0), size(x, 1));
if n0 < round(0.1 * fs), return; end
nseg = min(2^floor(log2(n0)), 2^nextpow2(round(0.25 * fs)));
x0 = x(1:n0, :);
[G, f] = pwelch(x0 - mean(x0, 1), hann(nseg, 'periodic'), nseg / 2, nseg, fs);
nz = struct('f', f, 'G', G);
end

function tl = steppedLevels(sp, mics, ch)
% Tone level of every step and DAQ channel from the sine fits of the settled
% part of each step (columns in channel order, like pressureSpectrum; mics
% sorted by channel).
sens = [];
if isfield(mics, 'sensitivity_VperPa'), sens = [mics.sensitivity_VperPa]; end
if numel(sens) ~= size(sp.amplitude_V, 2) || ~all(isfinite(sens) & sens > 0)
    sens = nan(1, size(sp.amplitude_V, 2));
end
prms = sp.amplitude_V ./ sens / sqrt(2);          % peak volts -> rms pascal
spl = 20 * log10(prms / 2e-5);
tl = struct('f', sp.f(:), 'fObserved', sp.fObserved(:), 'amplitude_V', sp.amplitude_V, ...
    'p_rms_Pa', prms, 'spl_dB', spl, 'noise_dB', spl - sp.snr_dB, 'channelOrder', ch, ...
    'note', ['Tone level of each step from the 3-parameter sine fit of the settled part (sensitivity layer only); ' ...
             'noise_dB = residual noise in the fit bandwidth (spl_dB - snr_dB).']);
end

function lv = specimenLevels(meas, res, sp, mics, chCol, ref, volts, unit)
% Level at the specimen front face (owner decisions 2026-11-04, WO-006 stage 1;
% docs/theory.md, section 3C): the incident pressure |A| at the front face
% [dB SPL] and the particle velocity |u_L| there [mm/s rms] per frequency line,
% from the CALIBRATED four-microphone decomposition (pressures relative to the
% reference microphone) times the absolute pressure amplitude at the reference
% microphone (DAQ channel ref, sensitivity layer only):
%   stepped sine: the fitted tone amplitude of every step (sp.amplitude_V, the
%                 mean over the blocks and the repetitions);
%   swept sine:   the sine-equivalent amplitude when the sweep passes the line
%                 (tim.dsp.sweepEquivalentAmplitude, from sp.refPower and the
%                 sweep rate on the DAQ clock).
% Random noise: not computed (no sine amplitude; a level per line would depend
% on the line width). Without a calibration, the face positions, data in volts
% or a sensitivity of the reference microphone the levels are NaN and lv.note
% says why; refAmplitude_Pa (the reference microphone alone) is kept when only
% the calibration or the faces are missing.
% The equalizer of the stepped sine (stage 2) reads its pre-measurement from
% here: per step the generator level played (generatorVpp; the per-step levels
% of an equalized run from settings.stepAmplitudeVpp) and the achieved
% quantities, at the step frequencies (lv.f = settings.frequencies).
an = res.analysis;
f = an.f(:);
n = numel(f);
lv = emptyLevels(meas.kind, f, ref);
st = meas.settings;
switch meas.kind
    case 'stepped'
        lv.method = 'stepped sine: fitted tone amplitude';
    case 'sweep'
        lv.method = 'swept sine: sine-equivalent amplitude from the reference spectrum and the sweep rate';
    otherwise
        lv.note = ['Random noise: no level at the specimen (no sine amplitude; a level per frequency line ' ...
            'would depend on the line width).'];
        return
end
if isfield(st, 'amplitudeVpp') && isscalar(st.amplitudeVpp), lv.generatorVpp(:) = st.amplitudeVpp; end
if isfield(st, 'stepAmplitudeVpp') && numel(st.stepAmplitudeVpp) == n
    lv.generatorVpp = st.stepAmplitudeVpp(:);   % a level per step (equalizer, stage 2)
end
if ~volts
    lv.note = sprintf('Data in %s (input scale unknown): no sound pressure at the specimen.', unit);
    return
end
c = find(chCol == ref, 1);
S = NaN;
if ~isempty(c) && c <= numel(mics) && isfield(mics, 'sensitivity_VperPa'), S = mics(c).sensitivity_VperPa; end
if ~(isscalar(S) && isfinite(S) && S > 0)
    lv.note = sprintf(['No valid sensitivity of the reference microphone (ch%d): no sound pressure at the ' ...
        'specimen.'], ref);
    return
end
lv.sensitivity_VperPa = S;
if strcmp(meas.kind, 'stepped')
    aRef = sp.amplitude_V(:, ref);              % V peak
else
    % duration of the sweep on the DAQ clock: the matched filter of the sweep
    % gate (mean over the gated repetitions), else the programmed one
    ex = sp.excitation;
    T = NaN;
    if ~isempty(ex) && any([ex.gated]), T = mean([ex([ex.gated]).sweepDuration_s]); end
    if ~(isfinite(T) && T > 0), T = st.duration; end
    [aRef, rate] = tim.dsp.sweepEquivalentAmplitude(sp.refPower, f, meas.fs, st, T);
    lv.sweepRate_Hz_s = rate;
    lv.sweepDuration_s = T;
end
lv.refAmplitude_Pa = aRef(:) / S;
if ~res.calibration.applied
    % owner decision 2026-11-04: from the calibrated decomposition only (an
    % uncalibrated pair is off by more than 1 dB at 120 Hz)
    lv.note = 'No calibration: the level at the specimen needs the calibrated decomposition.';
    return
end
if ~an.boundary.available
    lv.note = 'Position of the specimen front face unknown: no level at the specimen.';
    return
end
L = tim.acoustics.faceLevels(an, lv.refAmplitude_Pa);
lv.incident_Pa = L.incident_Pa;
lv.incident_dB_SPL = L.incident_dB_SPL;
lv.faceVelocity_mm_s = L.faceVelocity_mm_s;
lv.available = true;
lv.valid = an.valid.validR(:) & isfinite(lv.incident_dB_SPL);   % A1 and u_L: upstream pair only, as R
end

function lv = emptyLevels(kind, f, ref)
% res.levels with every value NaN (not available)
n = numel(f);
nanv = nan(n, 1);
lv = struct('f', f(:), 'kind', kind, 'available', false, 'method', '', 'note', '', 'refChannel', ref, ...
    'sensitivity_VperPa', NaN, 'generatorVpp', nanv, 'refAmplitude_Pa', nanv, 'sweepRate_Hz_s', nanv, ...
    'sweepDuration_s', NaN, 'incident_Pa', nanv, 'incident_dB_SPL', nanv, 'faceVelocity_mm_s', nanv, ...
    'valid', false(n, 1), 'units', struct('incident_Pa', 'Pa rms', 'incident_dB_SPL', 'dB re 20 uPa', ...
    'faceVelocity_mm_s', 'mm/s rms', 'refAmplitude_Pa', 'Pa peak', 'generatorVpp', 'Vpp', ...
    'sweepRate_Hz_s', 'Hz/s'));
end
