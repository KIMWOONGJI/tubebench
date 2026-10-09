function d = driveEstimate(cfg, amplitudeVpp)
%DRIVEESTIMATE Expected electrical drive of the loudspeaker.
%
%   d = tim.app.driveEstimate(cfg, amplitudeVpp)
%   amplitudeVpp : PROGRAMMED generator amplitude (33220A VOLT, Vpp)
%   d.direct, d.gain, d.Z, d.Voc_pp, d.Vin_pk, d.Vspk_pk [V], d.Ipk [A],
%   d.P_W, d.limit_W, d.load, d.Zin
%
%   The 33220A has a 50-ohm source impedance whatever OUTP:LOAD says; the
%   load setting only rescales the programmed value (33220A User's Guide;
%   docs/ref_33220A_scpi.md):
%     generator.load 'INF' : VOLT = open-circuit voltage      Voc = Vprog
%     generator.load '50'  : VOLT = voltage across 50 ohm     Voc = 2 * Vprog
%   Direct drive : Vspk = Voc * Z / (Z + 50)
%   Amplifier    : Vin  = Voc * Zin / (Zin + 50),  Vspk = Vin * gain
%                  (~0 amplifier output impedance assumed). Zin =
%                  cfg.amplifier.inputImpedance_ohm; when not given (NaN) it
%                  follows generator.load: 'INF' -> high-Z input (Vin = Voc),
%                  '50' -> 50-ohm input (Vin = Voc/2 = Vprog). With '50' and
%                  a high-Z amplifier that assumption gives 2x too low a
%                  voltage (4x power): validateConfig warns when Zin is not
%                  given with load '50' (review analysis-2).
%   P = Vspk_pk^2 / (2 Z)  - mean power of a sine / sweep (nominal impedance;
%   the real loudspeaker impedance varies with frequency).
%   NaN when an amplifier is used without a recorded gain.
%   (Formula review 2026-10-09, calval-2: the open-circuit factor 2 for
%   load '50' was missing, i.e. V 2x and P 4x too low with a high-Z input.)

a = cfg.amplifier;
ls = struct('impedance_ohm', 8, 'maxPower_W', 1);
if isfield(cfg, 'loudspeaker'), ls = cfg.loudspeaker; end
ld = 'INF';
if isfield(cfg, 'generator') && isfield(cfg.generator, 'load') && ~isempty(cfg.generator.load)
    ld = upper(strtrim(char(cfg.generator.load)));
end
load50 = strcmp(ld, '50');
Z = ls.impedance_ohm;
vocPk = amplitudeVpp / 2 * (1 + load50);             % open-circuit voltage, peak
gf = NaN; if isfield(a, 'gainFactor'), gf = a.gainFactor; end
if isnan(gf) && isfield(a, 'gain_dB') && isfinite(a.gain_dB), gf = 10^(a.gain_dB / 20); end
Zin = NaN;
if isfield(a, 'inputImpedance_ohm') && ~isempty(a.inputImpedance_ohm), Zin = a.inputImpedance_ohm; end
if ~(Zin > 0)
    if load50, Zin = 50; else, Zin = Inf; end
end
d = struct('direct', startsWith(lower(a.model), 'none'), 'gain', gf, 'Z', Z, ...
    'limit_W', ls.maxPower_W, 'load', ld, 'Voc_pp', 2 * vocPk, 'Zin', Zin, ...
    'Vin_pk', NaN, 'Vspk_pk', NaN, 'Ipk', NaN, 'P_W', NaN);
if d.direct
    d.gain = 1;
    d.Zin = Z;
    d.Vin_pk = vocPk * Z / (Z + 50);
    d.Vspk_pk = d.Vin_pk;
else
    if isinf(Zin), d.Vin_pk = vocPk; else, d.Vin_pk = vocPk * Zin / (Zin + 50); end
    if isfinite(gf), d.Vspk_pk = d.Vin_pk * gf; end
end
d.Ipk = d.Vspk_pk / Z;
d.P_W = d.Vspk_pk^2 / (2 * Z);
end
