function report = validateConfig(cfg)
%VALIDATECONFIG Consistency checks of a configuration. Errors on fatal problems,
%   returns a cell array of warnings (geometry incomplete, etc.).

report = {};
assert(any(strcmp(cfg.mode, {'simulation', 'hardware'})), 'tim:config:mode', 'mode must be simulation or hardware.');
assert(cfg.generator.maxVpp > 0 && cfg.generator.maxVpp <= 20, 'tim:config:maxVpp', 'generator.maxVpp out of range (0, 20].');
amps = [cfg.excitation.sweep.amplitudeVpp, cfg.excitation.stepped.amplitudeVpp, cfg.excitation.noise.amplitudeVpp];
if any(amps > cfg.generator.maxVpp)
    error('tim:config:amplitude', 'An excitation amplitude exceeds generator.maxVpp (%.3g Vpp).', cfg.generator.maxVpp);
end
if isfield(cfg, 'loudspeaker')
    ls = cfg.loudspeaker;
    assert(ls.impedance_ohm > 0 && ls.maxPower_W > 0, 'tim:config:loudspeaker', ...
        'loudspeaker.impedance_ohm and loudspeaker.maxPower_W must be positive.');
    if isfield(ls, 'ratedPower_W') && ls.maxPower_W > ls.ratedPower_W
        report{end+1} = 'loudspeaker.maxPower_W exceeds the rated power of the loudspeaker.';
    end
end
g = cfg.geometry;
if isfinite(g.diameter) && (g.diameter <= 0 || g.diameter > 0.5)
    error('tim:config:geometry', 'geometry.diameter must be in (0, 0.5] m.');
end
pos = [cfg.mics.position]; ch = [cfg.mics.channel];
assert(isequal(sort(pos), 1:4) && isequal(sort(ch), 1:4), 'tim:config:mics', ...
    'mics must map channels 1..4 one-to-one onto positions 1..4.');
assert(ismember(cfg.analysis.refChannel, 1:4), 'tim:config:ref', 'analysis.refChannel must be 1..4.');
fs = cfg.acquisition.sampleRate;
assert(ismember(fs, [4096 8192 16384 32768 65536]), 'tim:config:fs', 'Unsupported sample rate for the 3676.');
if cfg.analysis.fMax > 0.45 * fs
    error('tim:config:fmax', 'analysis.fMax (%.0f Hz) too close to Nyquist for fs = %d Hz.', cfg.analysis.fMax, fs);
end
sw = cfg.excitation.sweep;
if sw.fStart > cfg.analysis.fMin || sw.fStop < cfg.analysis.fMax
    report{end+1} = 'Sweep range does not cover the analysis band; edges will have low SNR.';
end
if sw.fStop > 0.45 * fs
    error('tim:config:sweep', 'Sweep stop frequency above 0.45*fs.');
end
assert(sw.repetitions >= 1 && sw.repetitions <= 100, 'tim:config:repetitions', 'Sweep repetitions must be 1..100.');
st = cfg.excitation.stepped;
if st.fStop > 0.45 * fs
    error('tim:config:stepped', 'Stepped stop frequency (%g Hz) above 0.45*fs (%g Hz).', st.fStop, 0.45 * fs);
end
assert(st.nPoints >= 1 && st.nPoints <= 400 && st.repetitions >= 1 && st.repetitions <= 100, 'tim:config:stepped', ...
    'Stepped sine: nPoints must be 1..400 and repetitions 1..100.');
if st.fStart < cfg.analysis.fMin || st.fStop > cfg.analysis.fMax
    report{end+1} = 'Stepped frequencies outside the analysis band are always flagged not valid.';
end
g = cfg.geometry;
if any(~isfinite(g.micPositions))
    report{end+1} = 'Microphone positions not provided: only pair-local results will be available.';
end
if ~isfinite(g.xFront) || ~isfinite(g.xRear)
    report{end+1} = 'Sample face positions not provided: boundary quantities (Zt, R, tau at faces) disabled.';
end
if all(isfinite(g.micPositions))
    if abs(abs(diff(g.micPositions(1:2))) - g.spacingUp) > 1e-3 || abs(abs(diff(g.micPositions(3:4))) - g.spacingDown) > 1e-3
        report{end+1} = 'micPositions disagree with spacingUp/spacingDown by more than 1 mm; positions are used.';
    end
end
end
