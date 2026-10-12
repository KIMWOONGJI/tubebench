function res = processMeasurement(meas, cfg, cal)
%PROCESSMEASUREMENT Raw recordings -> calibrated relative pressures -> acoustics.
%
%   res = tim.app.processMeasurement(meas, cfg, cal)
%
%   1) relative channel responses Y_c/Y_ref (method depends on meas.kind)
%   2) complex calibration (cal may be empty -> nothing will be "valid")
%   3) channel -> tube-position reordering (cfg.mics(c).position)
%   4) four-microphone analysis with validity diagnostics
%   5) absolute pressure spectra (sensitivities) for display only
%   The raw data in meas are never modified.

if nargin < 3, cal = []; end
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
[Hcal, calValid, calInfo, calValidCh] = tim.cal.applyCalibration(f, sp.H, cal, ref);
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
o.calValid = calValid;
o.calValidPos = calP;          % per position: R needs only the calibration of M1/M2 (review analysis-3)
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
        [P, fp] = pwelch(p, hann(nfft, 'periodic'), nfft / 2, nfft, fs);
        res.pressureSpectrum = struct('f', fp, 'PSD_Pa2perHz', P, 'channelOrder', chCol, ...
            'note', 'Uses the sensitivity layer (TEDS/certificate/nominal) only.');
    else
        [P, fp] = pwelch(x - mean(x, 1), hann(nfft, 'periodic'), nfft / 2, nfft, fs);
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
res.summary = res.analysis.valid.summary;
end

function sp = steppedSpectra(meas, ref)
st = meas.settings;
freqs = st.frequencies;
nF = numel(freqs);
H = zeros(nF, 4); coh = zeros(nF, 4); snr = zeros(nF, 4); fHat = zeros(nF, 1); se = zeros(nF, 4);
amp = nan(nF, 4);                       % fitted tone amplitude per step and channel [V peak]
nR = numel(meas.records);
for k = 1:nF
    % SNR NaN for a skipped repetition (min ignores NaN): otherwise 0 dB would make the
    % noise level equal to the tone level; coherence 0 still invalidates the step
    Hs = zeros(nR, 4); cs = zeros(nR, 4); ss = nan(nR, 4); fh = nan(nR, 1); es = zeros(nR, 4);
    as = nan(nR, 4);
    for r = 1:nR
        idx = tim.app.steppedSegment(meas, r, k);
        if isempty(idx)
            Hs(r, :) = NaN; continue
        end
        o = tim.dsp.sineResponse(meas.records{r}(idx, :), meas.fs, freqs(k), struct('refChannel', ref, 'nBlocks', st.nBlocks));
        Hs(r, :) = o.H; cs(r, :) = o.coherence; ss(r, :) = o.snr_dB; fh(r) = o.f; es(r, :) = o.stdErr;
        as(r, :) = o.amplitude;
    end
    H(k, :) = mean(Hs, 1, 'omitnan'); coh(k, :) = min(cs, [], 1); snr(k, :) = min(ss, [], 1);
    fHat(k) = mean(fh, 'omitnan');      % a skipped repetition must not average in 0 Hz
    se(k, :) = sqrt(mean(es.^2, 1)) / sqrt(nR);
    amp(k, :) = mean(as, 1, 'omitnan');
end
sp = struct('f', freqs(:), 'fObserved', fHat, 'H', H, 'coherence', coh, 'snr_dB', snr, ...
    'stdErr', se, 'amplitude_V', amp, 'refChannel', ref, ...
    'method', 'stepped sine, 3-parameter LS sine fit at data-estimated frequency');
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
