function [k, Zc] = wavenumber(f, air, diameter, lossModel)
%WAVENUMBER Complex wavenumber and characteristic impedance in the tube.
%
%   [k, Zc] = tim.acoustics.wavenumber(f, air, diameter, lossModel)
%
%   CONVENTION (used everywhere in this project):
%     time dependence exp(+j*omega*t); a wave travelling towards +x
%     (from the loudspeaker towards the termination) is A*exp(-j*k*x).
%     Attenuation therefore requires Im(k) <= 0:  k = k' - j*k''.
%
%   lossModel:
%     'none'      k = omega/c (lossless), Zc = rho*c
%     'iso10534'  k'' = 1.94e-2*sqrt(f)/(c*d)   (empirical visco-thermal wall
%                 attenuation constant quoted in ISO 10534-2; d in m, f in Hz.
%                 The exact clause number should be checked against the
%                 user's copy of the standard.)
%                 Zc = rho*c (the small dispersion of Zc is neglected).
%
%   f may be any array; k and Zc have the same size as f.

arguments
    f double
    air struct
    diameter (1,1) double {mustBePositive}
    lossModel (1,:) char {mustBeMember(lossModel, {'none', 'iso10534'})} = 'iso10534'
end

omega = 2 * pi * f;
k0 = omega / air.c;
switch lossModel
    case 'none'
        k = k0;
    case 'iso10534'
        kpp = 1.94e-2 * sqrt(abs(f)) / (air.c * diameter);
        k = k0 - 1j * kpp;
end
Zc = air.Z0 * ones(size(f));
end
