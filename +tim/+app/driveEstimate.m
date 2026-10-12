function d = driveEstimate(cfg, amplitudeVpp, kind)
%DRIVEESTIMATE Expected electrical drive of the loudspeaker.
%
%   d = tim.app.driveEstimate(cfg, amplitudeVpp)          % a sine or a sweep
%   d = tim.app.driveEstimate(cfg, amplitudeVpp, kind)    % kind 'sweep' | 'stepped' | 'noise'
%   amplitudeVpp : PROGRAMMED generator amplitude (33220A VOLT, Vpp) at
%                  generator.load
%   d.direct, d.gain, d.Z, d.Voc_pp, d.Vin_pk, d.Vspk_pk, d.Vspk_rms [V],
%   d.Ipk [A], d.P_W, d.limit_W, d.rated_W, d.fraction (P_W / limit_W),
%   d.state ('ok' | 'near' | 'over' | 'unknown'), d.near (0.8), d.crest,
%   d.load, d.Zin, d.Rs
%
%   Rs is the source impedance of the generator driver selected by
%   generator.driver (capabilities().source.outputImpedance_ohm): 50 ohm for
%   the 33220A, about 0 ohm for a DAQ analog output or the simulated combined
%   device. An unknown driver counts as 0 ohm, the worst case (the highest
%   loudspeaker voltage). A 0 ohm output driving the loudspeaker directly
%   gets (Z + 50)^2 / Z^2 (about 50 x at 8 ohm) the power a 50 ohm estimate
%   would give (docs/instrument_interface.md D12).
%   The 33220A has a 50-ohm source impedance whatever OUTP:LOAD says; the
%   load setting only rescales the programmed value (33220A User's Guide;
%   docs/ref_33220A_scpi.md):
%     generator.load 'INF' : VOLT = open-circuit voltage      Voc = Vprog
%     generator.load R     : VOLT = voltage across R ohm      Voc = Vprog * (R + Rs) / R
%                            ('50': 2 * Vprog with the 33220A)
%   Direct drive : Vspk = Voc * Z / (Z + Rs)
%   Amplifier    : Vin  = Voc * Zin / (Zin + Rs),  Vspk = Vin * gain
%                  (~0 amplifier output impedance assumed). Zin =
%                  cfg.amplifier.inputImpedance_ohm; when not given (NaN) it
%                  follows generator.load: 'INF' -> high-Z input (Vin = Voc),
%                  R -> an R-ohm input (Vin = Vprog). The window sets the load
%                  to the amplifier input (WO-004); validateConfig warns when a
%                  numeric load comes without the input impedance (a high-Z
%                  input would get ((R + Rs)/R)^2 x the estimated power).
%   Power at the NOMINAL impedance (the convention of the rated power, IEC
%   60268-5; owner decision 2026-10-12): P = Vspk_rms^2 / Z with
%   Vspk_rms = Vspk_pk / crest, crest = sqrt(2) for a sine or a sweep and the
%   crest factor of the source's noise (capabilities().source.noiseCrest,
%   3.3) for noise (the programmed Vpp of noise is its peak-to-peak value).
%   d.state: 'ok' below 80 % of the test limit loudspeaker.maxPower_W,
%   'near' from 80 % (the real impedance may be 20 % below the nominal one,
%   IEC 60268-5), 'over' above the limit (the session refuses it), 'unknown'
%   when an amplifier is used without a recorded gain (P NaN).
%   (Formula review 2026-10-09, calval-2: the open-circuit factor 2 for
%   load '50' was missing, i.e. V 2x and P 4x too low with a high-Z input.)

if nargin < 3 || isempty(kind), kind = 'sweep'; end
a = cfg.amplifier;
ls = struct('impedance_ohm', 8, 'maxPower_W', 1);
if isfield(cfg, 'loudspeaker'), ls = cfg.loudspeaker; end
rated = NaN; if isfield(ls, 'ratedPower_W'), rated = ls.ratedPower_W; end
ld = 'INF';
if isfield(cfg, 'generator') && isfield(cfg.generator, 'load') && ~isempty(cfg.generator.load)
    ld = upper(strtrim(char(cfg.generator.load)));
end
R = tim.instr.SignalSource.loadOhm(ld);
if isnan(R), R = Inf; end
[Rs, noiseCrest] = sourceData(cfg);
Z = ls.impedance_ohm;
vocPk = amplitudeVpp / 2;                            % open-circuit voltage, peak
if isfinite(R), vocPk = vocPk * (R + Rs) / R; end
crest = sqrt(2); if strcmpi(kind, 'noise'), crest = noiseCrest; end
gf = NaN; if isfield(a, 'gainFactor'), gf = a.gainFactor; end
if isnan(gf) && isfield(a, 'gain_dB') && isfinite(a.gain_dB), gf = 10^(a.gain_dB / 20); end
Zin = NaN;
if isfield(a, 'inputImpedance_ohm') && ~isempty(a.inputImpedance_ohm), Zin = a.inputImpedance_ohm; end
if ~(Zin > 0), Zin = R; end
d = struct('direct', startsWith(lower(a.model), 'none'), 'gain', gf, 'Z', Z, ...
    'limit_W', ls.maxPower_W, 'rated_W', rated, 'load', ld, 'Voc_pp', 2 * vocPk, 'Zin', Zin, 'Rs', Rs, ...
    'crest', crest, 'Vin_pk', NaN, 'Vspk_pk', NaN, 'Vspk_rms', NaN, 'Ipk', NaN, 'P_W', NaN, ...
    'fraction', NaN, 'near', 0.8, 'state', 'unknown');
if d.direct
    d.gain = 1;
    d.Zin = Z;
    d.Vin_pk = vocPk * Z / (Z + Rs);
    d.Vspk_pk = d.Vin_pk;
else
    if isinf(Zin), d.Vin_pk = vocPk; else, d.Vin_pk = vocPk * Zin / (Zin + Rs); end
    if isfinite(gf), d.Vspk_pk = d.Vin_pk * gf; end
end
d.Ipk = d.Vspk_pk / Z;
d.Vspk_rms = d.Vspk_pk / crest;
d.P_W = d.Vspk_rms^2 / Z;
d.fraction = d.P_W / d.limit_W;
if isnan(d.fraction)
    d.state = 'unknown';
elseif d.fraction > 1 + 1e-9
    d.state = 'over';
elseif d.fraction >= d.near
    d.state = 'near';
else
    d.state = 'ok';
end
end

function [Rs, crest] = sourceData(cfg)
% source impedance of the selected generator driver (0 ohm, the worst case,
% when unknown) and the crest factor of its noise (3.3 when not given)
Rs = 0; crest = 3.3;
name = 'keysight33220a';                 % configurations without a driver name (formatVersion 1)
if isfield(cfg, 'generator') && isfield(cfg.generator, 'driver') && ~isempty(cfg.generator.driver)
    name = char(string(cfg.generator.driver));
end
if ~any(strcmp(name, {tim.instr.drivers().name})), return; end
c = tim.instr.driverInfo(name).capabilities;
if ~isfield(c, 'source'), return; end
if isfield(c.source, 'outputImpedance_ohm'), Rs = c.source.outputImpedance_ohm; end
if isfield(c.source, 'noiseCrest') && c.source.noiseCrest > 0, crest = c.source.noiseCrest; end
end
