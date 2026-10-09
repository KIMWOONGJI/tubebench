function [p, u] = fieldAt(A, B, x, k, Zc)
%FIELDAT Pressure and axial particle velocity of a 1-D two-wave field.
%
%   [p, u] = tim.acoustics.fieldAt(A, B, x, k, Zc)
%
%   p(x) = A e^{-jkx} + B e^{+jkx}
%   u(x) = (A e^{-jkx} - B e^{+jkx}) / Zc        (u positive towards +x)
%
%   From the linearised Euler equation  j*omega*rho_eff*u = -dp/dx  (u =
%   cross-section average): u = k/(omega*rho_eff) * (A e^{-jkx} - B e^{jkx}),
%   and k/(omega*rho_eff) = 1/Zc with Zc = sqrt(rho_eff*K_eff). Lossless:
%   Zc = rho*c. lossModel 'kirchhoff' supplies the matching visco-thermal
%   Zc; 'iso10534' keeps Zc = rho*c (dispersion of Zc neglected, ASTM E2611
%   practice). See wavenumber.m.

arguments
    A (:,1) double
    B (:,1) double
    x (1,1) double {mustBeFinite}
    k (:,1) double
    Zc (:,1) double
end
ef = exp(-1j * k * x);
eb = exp(+1j * k * x);
p = A .* ef + B .* eb;
u = (A .* ef - B .* eb) ./ Zc;
end
