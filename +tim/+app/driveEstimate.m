function d = driveEstimate(cfg, amplitudeVpp)
%DRIVEESTIMATE Expected electrical drive of the loudspeaker.
%
%   d = tim.app.driveEstimate(cfg, amplitudeVpp)
%   amplitudeVpp : generator open-circuit amplitude (Vpp)
%   d.direct, d.gain, d.Z, d.Vspk_pk [V], d.Ipk [A], d.P_W, d.limit_W
%
%   Direct drive : Vspk = Voc * Z / (Z + 50)   (33220A 50-ohm source)
%   Amplifier    : Vspk = Voc * gain           (high amplifier input impedance,
%                                              ~0 output impedance assumed)
%   P = Vspk_pk^2 / (2 Z)  - mean power of a sine / sweep (nominal impedance;
%   the real loudspeaker impedance varies with frequency).
%   NaN when an amplifier is used without a recorded gain.

a = cfg.amplifier;
ls = struct('impedance_ohm', 8, 'maxPower_W', 1);
if isfield(cfg, 'loudspeaker'), ls = cfg.loudspeaker; end
Z = ls.impedance_ohm; vpk = amplitudeVpp / 2;
gf = NaN; if isfield(a, 'gainFactor'), gf = a.gainFactor; end
if isnan(gf) && isfield(a, 'gain_dB') && isfinite(a.gain_dB), gf = 10^(a.gain_dB / 20); end
d = struct('direct', startsWith(lower(a.model), 'none'), 'gain', gf, 'Z', Z, ...
    'limit_W', ls.maxPower_W, 'Vspk_pk', NaN, 'Ipk', NaN, 'P_W', NaN);
if d.direct
    d.gain = 1;
    d.Vspk_pk = vpk * Z / (Z + 50);
elseif isfinite(gf)
    d.Vspk_pk = vpk * gf;
end
d.Ipk = d.Vspk_pk / Z;
d.P_W = d.Vspk_pk^2 / (2 * Z);
end
