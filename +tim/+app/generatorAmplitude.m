function vpp = generatorAmplitude(cfg, speakerVpk)
%GENERATORAMPLITUDE Generator amplitude that drives the loudspeaker with a given voltage.
%
%   vpp = tim.app.generatorAmplitude(cfg, speakerVpk)
%   speakerVpk : wanted loudspeaker voltage [Vpk]
%   vpp        : programmed generator amplitude [Vpp] (excitation.*.amplitudeVpp)
%
%   The inverse of tim.app.driveEstimate (owner decisions 2026-10-12: WO-003
%   for direct drive, WO-004 with an amplifier).
%   Direct drive: the loudspeaker sees the open-circuit voltage of the
%   generator divided by its source impedance Rs (driver capabilities, 50 ohm
%   for the 33220A) and the nominal loudspeaker impedance Z,
%       Vspk = Voc * Z / (Z + Rs);
%   with the 33220A at High Z and 8 ohm, 10 mVpk at the loudspeaker needs
%   72.5 mVpk programmed.
%   Amplifier: Vspk = Vin * gain, Vin = Voc * Zin / (Zin + Rs); with the
%   generator load set to the amplifier input (Zin = R) the programmed level
%   is Vin = Vspk / gain.
%   Voc follows from the programmed value and generator.load ('INF':
%   Voc = programmed; R ohm: Voc = programmed * (R + Rs) / R). The real
%   loudspeaker impedance varies with frequency, so the loudspeaker voltage is
%   nominal, as in the drive estimate; with an amplifier it is as good as the
%   recorded gain.
%   Error tim:gui:input with an amplifier whose gain is not recorded.

d = tim.app.driveEstimate(cfg, 2);           % 1 Vpk programmed
if ~(d.Vspk_pk > 0)
    error('tim:gui:input', ['The amplitude can be given as the loudspeaker voltage only when the amplifier gain is ' ...
        'known (EXCITATION: Amplifier gain; amplifier.gainFactor).']);
end
vpp = 2 * speakerVpk / d.Vspk_pk;
end
