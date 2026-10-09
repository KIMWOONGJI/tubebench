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
%   lossModel (k0 = omega/c, D = inner diameter [m], f [Hz], c [m/s]):
%     'kirchhoff' (DEFAULT) visco-thermal wall losses of a wide tube
%                 (Kirchhoff 1868; wide-tube limit of the Zwikker-Kosten
%                 model, Tijdeman 1975, Stinson 1991). With the viscous
%                 boundary layer delta_v = sqrt(2 nu/omega) and radius a = D/2:
%                   rho_eff/rho = 1 + (1-j) delta_v/a
%                   K/K_eff     = 1 + (gamma-1)(1-j) delta_v/(a sqrt(Pr))
%                 k = k0 sqrt(rho_eff/rho * K/K_eff) gives, to first order,
%                   k   = k0 + (1 - j) k''
%                   k'' = Cw sqrt(f) / (c D),
%                   Cw  = 2 sqrt(pi nu) (1 + (gamma-1)/sqrt(Pr))
%                       = 2.03e-2 m s^-1/2 for air at 20 degC, 101.3 kPa
%                 i.e. the phase velocity is reduced by the same amount as
%                 the wave is attenuated: Re(k) = k0 + k''. The matching
%                 characteristic impedance, Zc = sqrt(rho_eff K_eff), is
%                   Zc = rho c [1 + (1 - j) Psi k''/k0],
%                   Psi = (1 - (gamma-1)/sqrt(Pr)) / (1 + (gamma-1)/sqrt(Pr)) = 0.356
%                 (real part 0.36 % at 120 Hz, 0.06 % at 4.5 kHz for D = 29 mm).
%                 Against the exact circular-tube (Zwikker-Kosten) solution
%                 the error of this k/Zc pair is below 0.1 % in a thin-element
%                 Zt (formula review 2026-10-09, acoustics-1).
%                 Valid for a/delta_v >> 1 (D = 29 mm: a/delta_v = 66 at 100 Hz).
%     'iso10534'  k = k0 - j k'',  k'' = 1.94e-2 sqrt(f)/(c D)  (empirical
%                 wall attenuation constant quoted in ISO 10534-2; the exact
%                 clause number should be checked against the user's copy of
%                 the standard); Zc = rho c. ISO-conformant option for
%                 absorption work. It keeps Re(k) = k0, i.e. it omits the
%                 equal-magnitude phase-velocity reduction. That is harmless
%                 for |R| (< 0.008) but biases the thin-element Zt, which is
%                 a small difference of pressures extrapolated over x3 - x2:
%                 absolute error ~ k''(x3 - x2) rho c (~0.02 rho c at 4.5 kHz
%                 for x3 - x2 = 157 mm). Against the exact tube field (lab
%                 tube, 120 Hz - 4.5 kHz, frequency-independent Zt) the error
%                 reaches ~47 % at |Zt|/rho c = 0.05, ~12 % at 0.2 and ~2 %
%                 at 1 (review analysis-1; the earlier figure 3-17 % was
%                 for a Zt rising from 0.05 to 0.21 rho c). validateConfig
%                 reports a warning for 'iso10534' and 'none'.
%     'none'      k = k0 (lossless), Zc = rho c (thin-element Zt error up to
%                 ~66 % at |Zt|/rho c = 0.05 in the lab tube)
%
%   The same model must be used for the analysis, the reference expectations
%   (Test D/E) and the virtual rig (tim.sim.tubeModel); all of them take it
%   from cfg.analysis.lossModel.
%
%   f may be any array; k and Zc have the same size as f.

arguments
    f double
    air struct
    diameter (1,1) double {mustBePositive}
    lossModel (1,:) char {mustBeMember(lossModel, {'none', 'iso10534', 'kirchhoff'})} = 'kirchhoff'
end

omega = 2 * pi * f;
k0 = omega / air.c;
Zc = air.Z0 * ones(size(f));
switch lossModel
    case 'none'
        k = k0;
    case 'iso10534'
        kpp = 1.94e-2 * sqrt(abs(f)) / (air.c * diameter);
        k = k0 - 1j * kpp;
    case 'kirchhoff'
        if ~all(isfield(air, {'nu', 'gamma', 'Pr'}))
            error('tim:air:fields', 'lossModel ''kirchhoff'' needs air.nu, air.gamma and air.Pr (tim.acoustics.airProperties).');
        end
        b = (air.gamma - 1) / sqrt(air.Pr);
        Cw = 2 * sqrt(pi * air.nu) * (1 + b);            % [m s^-1/2]
        kpp = Cw * sqrt(abs(f)) / (air.c * diameter);
        % (sign(f) - j): k(-f) = -conj(k(f)), Zc(-f) = conj(Zc(f)) (real time signals)
        k = k0 + (sign(f) - 1j) .* kpp;
        Psi = (1 - b) / (1 + b);
        rel = zeros(size(f));
        nz = k0 ~= 0;
        rel(nz) = kpp(nz) ./ abs(k0(nz));
        Zc = air.Z0 * (1 + Psi * rel .* (1 - 1j * sign(f)));
end
end
