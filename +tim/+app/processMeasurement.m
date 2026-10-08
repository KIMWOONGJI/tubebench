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
res.diagnostics = struct();

switch meas.kind
    case 'sweep'
        s = meas.settings;
        sp = tim.dsp.sweepResponse(meas.records, fs, struct('refChannel', ref, ...
            'fRange', [a.fMin a.fMax], 'df', a.df, 'preRoll', s.preRoll, ...
            'excitationBand', [s.fStart s.fStop], 'ringDown', min(s.postRoll, 0.5)));
        try
            ex = sp.excitation(1);
            law = tim.dsp.estimateSweepLaw(meas.records{1}(:, ref), fs, s.fStart, s.fStop, s.spacing, s.duration);
            res.diagnostics.sweepLaw = rmfield(law, {'ridgeT', 'ridgeF'});
            res.diagnostics.sweepLaw.nominalDuration_s = s.duration;
            res.diagnostics.sweepLaw.durationError = law.duration_s / s.duration - 1;
            res.diagnostics.excitation = sp.excitation;
            if ~all([sp.excitation.detected])
                res.diagnostics.warnings = {'Excitation not detected in at least one repetition.'};
            end
            if ex.detected && ex.start_s < 0.5 * s.preRoll
                res.diagnostics.warnings{end+1} = 'Excitation started early in the pre-roll: noise estimate unreliable.';
            end
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
[Hcal, calValid, calInfo] = tim.cal.applyCalibration(f, sp.H, cal, ref);
res.calibration = struct('applied', ~isempty(cal), 'info', calInfo, 'version', 'none');
if ~isempty(cal), res.calibration.version = cal.version; end
res.Hchannel = Hcal;

% ---- channel -> position
pos = [cfg.mics.position]; ch = [cfg.mics.channel];
Hp = zeros(numel(f), 4); cohP = ones(numel(f), 4); snrP = inf(numel(f), 4);
for i = 1:4
    Hp(:, pos(i)) = Hcal(:, ch(i));
    cohP(:, pos(i)) = sp.coherence(:, ch(i));
    snrP(:, pos(i)) = sp.snr_dB(:, ch(i));
end
res.Hposition = Hp;

% ---- acoustics
o = rmfield(a, {'refChannel', 'fMin', 'fMax', 'df'});
o.quality = struct('coherence', cohP, 'snr_dB', snrP);
o.calValid = calValid;
o.fRange = [a.fMin a.fMax];
res.analysis = tim.acoustics.analyzeFourMic(f, Hp, cfg.geometry, cfg.environment, o);

% ---- absolute pressure spectra (display / SPL only)
try
    x = meas.records{1};
    p = tim.acq.voltsToPascal(x - mean(x, 1), meas.mics, 'V');
    nfft = min(8192, 2^nextpow2(size(p, 1)));
    [P, fp] = pwelch(p, hann(nfft, 'periodic'), nfft / 2, nfft, fs);
    res.pressureSpectrum = struct('f', fp, 'PSD_Pa2perHz', P, 'channelOrder', ch, ...
        'note', 'Uses the sensitivity layer (TEDS/certificate/nominal) only.');
catch err
    res.pressureSpectrum = struct('error', err.message);
end
res.summary = res.analysis.valid.summary;
end

function sp = steppedSpectra(meas, ref)
st = meas.settings;
freqs = st.frequencies;
nF = numel(freqs);
H = zeros(nF, 4); coh = zeros(nF, 4); snr = zeros(nF, 4); fHat = zeros(nF, 1); se = zeros(nF, 4);
nR = numel(meas.records);
for k = 1:nF
    Hs = zeros(nR, 4); cs = zeros(nR, 4); ss = zeros(nR, 4); fh = zeros(nR, 1); es = zeros(nR, 4);
    for r = 1:nR
        idx = tim.app.steppedSegment(meas, r, k);
        if isempty(idx)
            Hs(r, :) = NaN; continue
        end
        o = tim.dsp.sineResponse(meas.records{r}(idx, :), meas.fs, freqs(k), struct('refChannel', ref, 'nBlocks', st.nBlocks));
        Hs(r, :) = o.H; cs(r, :) = o.coherence; ss(r, :) = o.snr_dB; fh(r) = o.f; es(r, :) = o.stdErr;
    end
    H(k, :) = mean(Hs, 1, 'omitnan'); coh(k, :) = min(cs, [], 1); snr(k, :) = min(ss, [], 1);
    fHat(k) = mean(fh); se(k, :) = sqrt(mean(es.^2, 1)) / sqrt(nR);
end
sp = struct('f', freqs(:), 'fObserved', fHat, 'H', H, 'coherence', coh, 'snr_dB', snr, ...
    'stdErr', se, 'refChannel', ref, ...
    'method', 'stepped sine, 3-parameter LS sine fit at data-estimated frequency');
end
