function report = validateConfig(cfg, scope)
%VALIDATECONFIG Consistency checks of a configuration. Errors on fatal problems,
%   returns a cell array of warnings (geometry incomplete, etc.).
%
%   report = tim.app.validateConfig(cfg)
%   report = tim.app.validateConfig(cfg, 'instruments')
%
%   Messages name the GUI quantity first; the configuration key follows in
%   parentheses for script users. The instrument drivers selected by
%   generator.driver and daq.driver check their part (their static
%   checkConfig): the driver settings sub-struct and the allowed values of the
%   generic settings - generator.load and maxVpp, excitation signals, levels,
%   sweep times and frequencies, sample rate, analysis band, input range,
%   filter and CCLD. A configuration with the old instrument keys
%   (formatVersion 1, built in code) is read through tim.app.migrateConfig.
%   Without 'instruments' (loading a file: tim.app.loadConfig, File > Open
%   measurement, Load configuration) the instrument checks only warn, so a
%   file that an older version or another set-up wrote still loads: an
%   unknown driver name gives the warning tim:config:driver and skips that
%   driver's limits; a value outside the limits of the selected driver gives
%   its tim:config:* identifier as a warning. With 'instruments' (the
%   measurement session, i.e. Connect, and its setters) they are errors.

if nargin < 2, scope = ''; end
cfg = tim.app.migrateConfig(cfg);
report = {};
assert(any(strcmp(cfg.mode, {'simulation', 'hardware'})), 'tim:config:mode', ...
    'Operating mode (mode) must be "simulation" or "hardware".');
assert(isscalar(cfg.generator.maxVpp) && cfg.generator.maxVpp > 0, 'tim:config:maxVpp', ...
    'Generator amplitude limit (generator.maxVpp) must be greater than 0.');
if isfield(cfg.generator, 'allowUnconfirmedOff')
    assert(isscalar(cfg.generator.allowUnconfirmedOff) && islogical(cfg.generator.allowUnconfirmedOff), ...
        'tim:config:allowUnconfirmedOff', 'generator.allowUnconfirmedOff must be true or false.');
end
% generator output load setting (33220A OUTP:LOAD): 'INF' or a resistance
% written as a number ('600'). The values a driver accepts come from it
% (capabilities().source.loads / loadRange, checked below with EXACT text:
% Keysight33220A and the GUI compare the raw text, so 'inf' or ' 50' must
% not pass here and fail only at Connect, review analysis-6)
ld = cfg.generator.load;
if isstring(ld) && isscalar(ld), ld = char(ld); end
if ~ischar(ld)
    error('tim:config:load', ['Generator output load (generator.load) must be text: ''INF'' or a resistance in ohm such ' ...
        'as ''50'' or ''600'' (got %s).'], mat2str(ld));
end
R = tim.instr.SignalSource.loadOhm(ld);           % Inf, a resistance, or NaN (the driver check reports it)
% the safety limit generator.maxVpp is an OPEN-CIRCUIT voltage (WO-004): a
% level programmed at a load of R ohm has the open-circuit voltage
% level x (R + Rs) / R (Rs: source impedance of the generator driver)
lim = cfg.generator.maxVpp;
ocf = openCircuitFactor(cfg, ld);
exName = {'sweep', 'swept sine'; 'stepped', 'stepped sine'; 'noise', 'random noise'};
for i = 1:size(exName, 1)
    v = cfg.excitation.(exName{i, 1}).amplitudeVpp;
    if v * ocf > lim * (1 + 1e-9)
        if ocf == 1
            error('tim:config:amplitude', ['Generator amplitude of the %s, %.3g Vpk (%.3g Vpp), exceeds the amplitude limit ' ...
                'of %.3g Vpk (%.3g Vpp, generator.maxVpp).'], exName{i, 2}, v / 2, v, lim / 2, lim);
        end
        error('tim:config:amplitude', ['Generator amplitude of the %s, %.3g Vpk (%.3g Vpp) at load %s Ω, has the open-circuit ' ...
            'voltage %.3g Vpp, above the amplitude limit of %.3g Vpp open circuit (generator.maxVpp).'], ...
            exName{i, 2}, v / 2, v, ld, v * ocf, lim);
    end
end
hasAmp = isfield(cfg, 'amplifier');
direct = hasAmp && startsWith(lower(cfg.amplifier.model), 'none');
if isfinite(R) && direct
    error('tim:config:load', ['Generator output load ''%s'' (generator.load) with direct drive: the generator would set ' ...
        'the voltage across %s Ω, not the open-circuit voltage that drives the loudspeaker through the generator''s ' ...
        'source impedance. Use ''INF'' for direct drive (owner decision 2026-10-12); a resistance is the input of an ' ...
        'amplifier.'], ld, ld);
end
zin = NaN;
if hasAmp && isfield(cfg.amplifier, 'inputImpedance_ohm') && ~isempty(cfg.amplifier.inputImpedance_ohm)
    zin = cfg.amplifier.inputImpedance_ohm;
end
if ~isnan(zin) && ~(zin > 0)
    error('tim:config:amplifier', ['Amplifier input impedance (amplifier.inputImpedance_ohm) must be greater than 0, ' ...
        'or empty to derive it from the generator output load.']);
end
if hasAmp && ~direct
    if isfinite(R) && isnan(zin)
        % driveEstimate then assumes an R-ohm amplifier input (Vin = programmed
        % voltage); a high-Z input gets the open-circuit voltage ((R+Rs)/R)x ->
        % power ((R+Rs)/R)^2 x (review analysis-2: 4x at 50 ohm)
        report{end+1} = sprintf(['Generator output load ''%s'' (generator.load) with an amplifier of unknown input ' ...
            'impedance: the loudspeaker power check assumes a %s Ω amplifier input. With a high-impedance input the ' ...
            'loudspeaker gets up to %.3g × the estimated power – enter the amplifier input impedance ' ...
            '(amplifier.inputImpedance_ohm; the window sets both).'], ld, ld, ocf^2);
    elseif zin > 0 && isfinite(zin) && zin <= 1e4 && ~(isfinite(R) && abs(R - zin) <= 1e-6 * zin)
        report{end+1} = sprintf(['Generator output load ''%s'' (generator.load) differs from the amplifier input ' ...
            'impedance %g Ω (amplifier.inputImpedance_ohm): the programmed level is then not the voltage at the ' ...
            'amplifier input. Set generator.load to ''%g'' (the window does).'], ld, zin, zin);
    end
end
if isfield(cfg, 'ui') && isfield(cfg.ui, 'amplitudeAt')
    at = cfg.ui.amplitudeAt; if isstring(at), at = char(at); end
    if ~ischar(at) || ~any(strcmp(at, {'generator', 'loudspeaker'}))
        error('tim:config:ui', 'Amplitude field (ui.amplitudeAt) must be ''generator'' or ''loudspeaker''.');
    end
    gainKnown = hasAmp && ((isfield(cfg.amplifier, 'gainFactor') && cfg.amplifier.gainFactor > 0) || ...
        (isfield(cfg.amplifier, 'gain_dB') && isfinite(cfg.amplifier.gain_dB)));
    if strcmp(at, 'loudspeaker') && hasAmp && ~direct && ~gainKnown
        report{end+1} = ['The amplitude is entered as the loudspeaker voltage (ui.amplitudeAt) but the amplifier gain ' ...
            'is not recorded (amplifier.gainFactor): the window shows the level at the amplifier input instead.'];
    end
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
vb = cfg.analysis.validatedBands;
if ~(isnumeric(vb) && (isempty(vb) || (ismatrix(vb) && size(vb, 2) == 2 && all(vb(:, 1) < vb(:, 2)))))
    error('tim:config:validatedBands', ['Validated bands (analysis.validatedBands) must be a list of bands ' ...
        '[fLo fHi] with fLo < fHi, e.g. [[200, 3000]] (got %s).'], mat2str(vb));
end
% analysis band: fixed, or the ASTM E1050 / E2611 limits of the tube (owner
% decision 2026-10-13, tim.app.analysisBand); the checks below use that band
if isfield(cfg.analysis, 'bandMode')
    bm = cfg.analysis.bandMode;
    if ~((ischar(bm) || (isstring(bm) && isscalar(bm))) && any(strcmp(char(bm), {'fixed', 'geometry'})))
        error('tim:config:bandMode', 'Analysis band (analysis.bandMode) must be ''fixed'' or ''geometry''.');
    end
end
[cfg, band] = tim.app.analysisBand(cfg);
if band.outside
    report{end+1} = sprintf(['Analysis band %g–%g Hz (analysis.fMin, analysis.fMax) extends beyond the ASTM ' ...
        'E1050 / E2611 limits of this tube, %.0f–%.0f Hz: the lines outside are computed but not valid. Set ' ...
        'analysis.bandMode to ''geometry'' to follow the tube.'], band.fMin, band.fMax, band.limits(1), band.limits(2));
end
if isfield(cfg, 'calibration')
    cb = cfg.calibration;
    if isfield(cb, 'positions')
        ab = cb.positions;
        if ~(isnumeric(ab) && numel(ab) == 2 && all(ismember(ab, 1:4)) && ab(1) ~= ab(2))
            error('tim:config:calPositions', ['Calibration ports (calibration.positions) must be two different ' ...
                'ports of M1–M4, e.g. [1, 2] (got %s).'], mat2str(ab));
        end
    end
    if isfield(cb, 'coherenceMin') && ~(isscalar(cb.coherenceMin) && cb.coherenceMin > 0 && cb.coherenceMin <= 1)
        error('tim:config:calQuality', 'Calibration coherence limit (calibration.coherenceMin) must be in (0, 1].');
    end
    if isfield(cb, 'snrMin_dB') && ~(isscalar(cb.snrMin_dB) && isfinite(cb.snrMin_dB))
        error('tim:config:calQuality', 'Calibration SNR limit (calibration.snrMin_dB) must be a finite number of dB.');
    end
end
fs = cfg.acquisition.sampleRate;
assert(isscalar(fs) && isnumeric(fs) && fs > 0, 'tim:config:fs', ...
    'Sample rate (acquisition.sampleRate) must be a positive number of samples per second.');
if cfg.analysis.fMax >= fs / 2
    % the drivers limit the band to their anti-alias filter (bandFraction x sample rate)
    error('tim:config:fmax', ['Upper limit of the analysis band (analysis.fMax) %g Hz is above half the sample rate ' ...
        '(sample rate %g S/s).'], cfg.analysis.fMax, fs);
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
% the sweep gate needs room outside the band (docs/theory.md section 4);
% without it that end of the analysis window includes the generator's
% output switching (owner decision 2026-10-11, tim.dsp.sweepResponse). The
% limits are those of the analysis: the outer edges of the lines of the grid
% fMin:df:fMax (tim.app.processMeasurement), tim.dsp.sweepGateLimits
an = cfg.analysis;
dfl = NaN; fl = [];
if isfield(an, 'df') && isnumeric(an.df) && isscalar(an.df), dfl = an.df; end
if isfinite(dfl) && dfl > 0, fl = an.fMin:dfl:an.fMax; end
if isempty(fl), fl = [an.fMin an.fMax]; dfl = 0; end      % no valid line width: the band itself
[fStartMax, fStopMin] = tim.dsp.sweepGateLimits(fl, dfl);
if sw.fStart > cfg.analysis.fMin || sw.fStop < cfg.analysis.fMax
    report{end+1} = 'Swept sine: start/stop frequencies do not cover the analysis band, so its edges will have a low SNR.';
elseif sw.fStart > fStartMax || sw.fStop < fStopMin
    report{end+1} = sprintf(['Swept sine: let the sweep start at or below %.0f Hz and stop at or above %.0f Hz ' ...
        '(analysis band %g–%g Hz): closer to the band the sweep gate has no room at that end, so the analysis ' ...
        'window there may include the generator''s output switching (the ramp on the start tone before the sweep; ' ...
        'the ring-down margin after the sweep).'], floor(fStartMax), ceil(fStopMin), cfg.analysis.fMin, cfg.analysis.fMax);
end
if sw.preRoll < 0.15
    report{end+1} = sprintf(['Swept sine: pre-roll %.3g s (excitation.sweep.preRoll) is shorter than 0.15 s: no ' ...
        'noise-only part before the sweep, the SNR is unknown and no frequency line is valid.'], sw.preRoll);
end
assert(sw.repetitions >= 1 && sw.repetitions <= 100, 'tim:config:repetitions', ...
    'Swept sine: repetitions must be between 1 and 100.');
st = cfg.excitation.stepped;
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
report = [report, checkDrivers(cfg, strcmp(scope, 'instruments'))];
end

function report = checkDrivers(cfg, required)
% the selected drivers check their part of the configuration (a combined
% driver once). An unknown name, a driver in a role it does not have and a
% value outside the driver's limits are errors when required; otherwise
% warnings, also returned in the report (the window logs them as checks)
report = {};
sections = {'generator', 'daq'};
roles = {'source', 'acquisition'};
roleText = {'signal source (generator)', 'acquisition (DAQ)'};
registered = {tim.instr.drivers().name};
checked = {};
for k = 1:2
    name = cfg.(sections{k}).driver;
    if isstring(name) && isscalar(name), name = char(name); end
    if ~ischar(name) || ~any(strcmp(name, registered))
        got = name; if ~ischar(got), got = mat2str(got); end
        msg = sprintf(['Unknown instrument driver "%s" (%s.driver; registered: %s): the instrument settings of this ' ...
            'configuration are not checked and it cannot connect.'], got, sections{k}, strjoin(registered, ', '));
        report = notRequired(report, required, 'tim:config:driver', msg);
        continue
    end
    d = tim.instr.driverInfo(name);
    if ~any(strcmp(roles{k}, d.capabilities.roles))
        msg = sprintf('The %s (%s.driver "%s") cannot be the %s.', d.displayName, sections{k}, name, roleText{k});
        report = notRequired(report, required, 'tim:config:driver', msg);
        continue
    end
    if any(strcmp(name, checked)), continue; end          % one driver for both roles
    checked{end+1} = name; %#ok<AGROW>
    try
        r = feval([d.class '.checkConfig'], cfg);
    catch err
        % a file of 1.1.0 or of another set-up may hold values the driver does
        % not accept (e.g. a level below its minimum): it loads, Connect refuses it
        if ~startsWith(err.identifier, 'tim:config:'), rethrow(err); end
        report = notRequired(report, required, err.identifier, err.message);
        continue
    end
    report = [report, reshape(r, 1, [])]; %#ok<AGROW>
end
end

function f = openCircuitFactor(cfg, load)
% open-circuit voltage per volt programmed at the load, with the source
% impedance of the generator driver (1 for 'INF' or an unknown driver)
f = 1;
name = cfg.generator.driver;
if isstring(name) && isscalar(name), name = char(name); end
if ~ischar(name) || ~any(strcmp(name, {tim.instr.drivers().name})), return; end
c = tim.instr.driverInfo(name).capabilities;
if isfield(c, 'source'), f = tim.instr.SignalSource.openCircuitFactor(c.source, load); end
end

function report = notRequired(report, required, id, msg)
% a failed instrument check: an error when the instruments are required,
% otherwise a warning with the same identifier, also added to the report
if required, error(id, '%s', msg); end
if ~endsWith(msg, 'cannot connect.')
    msg = sprintf('%s The instruments cannot connect with this configuration until it is changed.', msg);
end
warning(id, '%s', msg);
report{end+1} = msg;
end
