function [p, u] = fieldAt(A, B, x, k, Zc)
%FIELDAT Pressure and axial particle velocity of a 1-D two-wave field.
%
%   [p, u] = tim.acoustics.fieldAt(A, B, x, k, Zc)
%
%   p(x) = A e^{-jkx} + B e^{+jkx}
%   u(x) = (A e^{-jkx} - B e^{+jkx}) / Zc        (u positive towards +x)
%
%   From the linearised Euler equation  j*omega*rho*u = -dp/dx  with
%   k = omega/c and Zc = rho*c (lossless); for the lossy wavenumber the
%   same expression is used with Zc = rho*c (see wavenumber.m).

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
