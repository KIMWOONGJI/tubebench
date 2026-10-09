function report = validateConfig(cfg)
%VALIDATECONFIG Consistency checks of a configuration. Errors on fatal problems,
%   returns a cell array of warnings (geometry incomplete, etc.).
%   Messages name the GUI quantity first; the configuration key follows in
%   parentheses for script users.

report = {};
assert(any(strcmp(cfg.mode, {'simulation', 'hardware'})), 'tim:config:mode', ...
    'Operating mode (mode) must be "simulation" or "hardware".');
assert(cfg.generator.maxVpp > 0 && cfg.generator.maxVpp <= 20, 'tim:config:maxVpp', ...
    'Generator amplitude limit (generator.maxVpp) must be greater than 0 and at most 10 Vpk (20 Vpp).');
lim = cfg.generator.maxVpp;
exName = {'sweep', 'swept sine'; 'stepped', 'stepped sine'; 'noise', 'random noise'};
for i = 1:size(exName, 1)
    v = cfg.excitation.(exName{i, 1}).amplitudeVpp;
    if v > lim
        error('tim:config:amplitude', ['Generator amplitude of the %s, %.3g Vpk (%.3g Vpp), exceeds the amplitude limit ' ...
            'of %.3g Vpk (%.3g Vpp, generator.maxVpp).'], exName{i, 2}, v / 2, v, lim / 2, lim);
    end
end
% generator output load setting (33220A OUTP:LOAD; source impedance always 50 ohm).
% EXACT values: Keysight33220A (mustBeMember) and the GUI compare the raw text,
% so 'inf' or ' 50' must not pass here and fail only at Connect (review analysis-6)
ld = cfg.generator.load;
if isstring(ld) && isscalar(ld), ld = char(ld); end
if ~ischar(ld) || ~any(strcmp(ld, {'INF', '50'}))
    got = ld; if ~ischar(got), got = mat2str(got); end
    error('tim:config:load', 'Generator output load (generator.load) must be ''INF'' or ''50'' (got ''%s'').', got);
end
hasAmp = isfield(cfg, 'amplifier');
direct = hasAmp && startsWith(lower(cfg.amplifier.model), 'none');
if strcmp(ld, '50') && direct
    error('tim:config:load', ['Generator output load ''50'' (generator.load) with direct drive: the generator would set ' ...
        'the voltage across 50 Ω, which is half the open-circuit voltage that drives the loudspeaker. Use ''INF'' for ' ...
        'direct drive; ''50'' is only for an amplifier with a 50 Ω input.']);
end
zin = NaN;
if hasAmp && isfield(cfg.amplifier, 'inputImpedance_ohm') && ~isempty(cfg.amplifier.inputImpedance_ohm)
    zin = cfg.amplifier.inputImpedance_ohm;
end
if ~isnan(zin) && ~(zin > 0)
    error('tim:config:amplifier', ['Amplifier input impedance (amplifier.inputImpedance_ohm) must be greater than 0, ' ...
        'or empty to derive it from the generator output load.']);
end
if strcmp(ld, '50') && hasAmp && ~direct && isnan(zin)
    % driveEstimate then assumes a 50-ohm amplifier input (Vin = programmed
    % voltage); a high-Z input gets the open-circuit voltage 2x -> power 4x
    % (review analysis-2)
    report{end+1} = ['Generator output load ''50'' (generator.load) with an amplifier of unknown input impedance: ' ...
        'the loudspeaker power check assumes a 50 Ω amplifier input. With a high-impedance input the loudspeaker ' ...
        'gets up to 4 × the estimated power – enter the amplifier input impedance (amplifier.inputImpedance_ohm).'];
end
if isfield(cfg, 'loudspeaker')
    ls = cfg.loudspeaker;
    assert(ls.impedance_ohm > 0 && ls.maxPower_W > 0, 'tim:config:loudspeaker', ...
        ['Loudspeaker impedance (loudspeaker.impedance_ohm) and loudspeaker power limit (loudspeaker.maxPower_W) ' ...
        'must be greater than 0.']);
    if isfield(ls, 'ratedPower_W') && ls.maxPower_W > ls.ratedPower_W
        report{end+1} = ['Loudspeaker power limit (loudspeaker.maxPower_W) exceeds the rated power of the loudspeaker ' ...
            '(loudspeaker.ratedPower_W).'];
    end
end
g = cfg.geometry;
if isfinite(g.diameter) && (g.diameter <= 0 || g.diameter > 0.5)
    error('tim:config:geometry', 'Inner diameter D (geometry.diameter) must be greater than 0 and at most 500 mm.');
end
pos = [cfg.mics.position]; ch = [cfg.mics.channel];
assert(isequal(sort(pos), 1:4) && isequal(sort(ch), 1:4), 'tim:config:mics', ...
    'Each channel ch1–ch4 must be assigned to exactly one port M1–M4 (configuration: mics).');
assert(ismember(cfg.analysis.refChannel, 1:4), 'tim:config:ref', ...
    'Reference channel (analysis.refChannel) must be 1, 2, 3 or 4.');
fs = cfg.acquisition.sampleRate;
assert(ismember(fs, [4096 8192 16384 32768 65536]), 'tim:config:fs', ...
    'Sample rate %g Hz is not supported by the LAN-XI module 3676 (use 4096, 8192, 16384, 32768 or 65536 Hz).', fs);
fNy = 0.45 * fs;                       % usable band of the 3676 anti-alias filter
if cfg.analysis.fMax > fNy
    error('tim:config:fmax', ['Upper limit of the analysis band (analysis.fMax) %g Hz is above 0.45 × sample rate ' ...
        '= %.0f Hz (sample rate %d Hz).'], cfg.analysis.fMax, fNy, fs);
end
lm = cfg.analysis.lossModel;
if ~(ischar(lm) || isstring(lm)) || ~any(strcmp(lm, {'kirchhoff', 'iso10534', 'none'}))
    error('tim:config:lossModel', 'Tube loss model (analysis.lossModel) must be ''kirchhoff'', ''iso10534'' or ''none''.');
end
% Configurations saved before 'kirchhoff' became the default (and config.json
% of older measurement folders) still name 'iso10534'; loadConfig keeps the
% saved value. Bias of the thin-element Zt in the lab tube, 120 Hz - 4.5 kHz,
% against the exact tube field (review analysis-1, see wavenumber.m):
% 'iso10534' up to ~47 % at |Zt|/rho c = 0.05, 'none' up to ~66 %.
if strcmp(lm, 'iso10534')
    report{end+1} = ['Tube loss model ''iso10534'' (analysis.lossModel) omits the phase-velocity reduction of the ' ...
        'tube losses: the thin-element Zt is biased by about k''''(x3 - x2)·ρc (up to ~0.02 ρc at 4.5 kHz in the lab ' ...
        'tube, i.e. ~45 % at |Zt|/ρc = 0.05). Use ''kirchhoff'' for Zt.'];
elseif strcmp(lm, 'none')
    report{end+1} = ['Tube loss model ''none'' (analysis.lossModel) ignores the tube losses: the thin-element Zt is ' ...
        'biased by up to ~0.03 ρc at 4.5 kHz in the lab tube (~65 % at |Zt|/ρc = 0.05). Use ''kirchhoff''.'];
end
sw = cfg.excitation.sweep;
if sw.fStart > cfg.analysis.fMin || sw.fStop < cfg.analysis.fMax
    report{end+1} = 'Swept sine: start/stop frequencies do not cover the analysis band, so its edges will have a low SNR.';
end
if sw.fStop > fNy
    error('tim:config:sweep', 'Swept sine: stop frequency %g Hz is above 0.45 × sample rate = %.0f Hz (sample rate %d Hz).', ...
        sw.fStop, fNy, fs);
end
assert(sw.repetitions >= 1 && sw.repetitions <= 100, 'tim:config:repetitions', ...
    'Swept sine: repetitions must be between 1 and 100.');
st = cfg.excitation.stepped;
if st.fStop > fNy
    error('tim:config:stepped', 'Stepped sine: stop frequency %g Hz is above 0.45 × sample rate = %.0f Hz (sample rate %d Hz).', ...
        st.fStop, fNy, fs);
end
assert(st.nPoints >= 1 && st.nPoints <= 400 && st.repetitions >= 1 && st.repetitions <= 100, 'tim:config:stepped', ...
    'Stepped sine: number of steps must be between 1 and 400 and repetitions between 1 and 100.');
if st.fStart < cfg.analysis.fMin || st.fStop > cfg.analysis.fMax
    report{end+1} = 'Stepped sine: frequencies outside the analysis band are always marked not valid.';
end
g = cfg.geometry;
if any(~isfinite(g.micPositions))
    report{end+1} = 'Microphone port positions not entered: only the results of the individual microphone pairs are available.';
end
if ~isfinite(g.xFront) || ~isfinite(g.xRear)
    report{end+1} = 'Specimen face positions not entered (L1, d, L2): specimen results (R, τ, Zt, TL) disabled.';
end
if all(isfinite(g.micPositions))
    if abs(abs(diff(g.micPositions(1:2))) - g.spacingUp) > 1e-3 || abs(abs(diff(g.micPositions(3:4))) - g.spacingDown) > 1e-3
        report{end+1} = ['Microphone port positions disagree with the microphone spacings s1/s2 by more than 1 mm; ' ...
            'the port positions are used.'];
    end
end
end
