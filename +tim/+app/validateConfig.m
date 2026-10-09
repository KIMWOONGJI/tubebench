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
% generator output load setting (33220A OUTP:LOAD; source impedance always 50 ohm)
ld = upper(strtrim(char(cfg.generator.load)));
if ~any(strcmp(ld, {'INF', '50'}))
    error('tim:config:load', 'Generator output load (generator.load) must be ''INF'' or ''50'' (got ''%s'').', ld);
end
if strcmp(ld, '50') && isfield(cfg, 'amplifier') && startsWith(lower(cfg.amplifier.model), 'none')
    error('tim:config:load', ['Generator output load ''50'' (generator.load) with direct drive: the generator would set ' ...
        'the voltage across 50 Ω, which is half the open-circuit voltage that drives the loudspeaker. Use ''INF'' for ' ...
        'direct drive; ''50'' is only for an amplifier with a 50 Ω input.']);
end
if isfield(cfg, 'amplifier') && isfield(cfg.amplifier, 'inputImpedance_ohm') && ...
        ~isempty(cfg.amplifier.inputImpedance_ohm) && ~isnan(cfg.amplifier.inputImpedance_ohm) && ...
        ~(cfg.amplifier.inputImpedance_ohm > 0)
    error('tim:config:amplifier', ['Amplifier input impedance (amplifier.inputImpedance_ohm) must be greater than 0, ' ...
        'or empty to derive it from the generator output load.']);
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
