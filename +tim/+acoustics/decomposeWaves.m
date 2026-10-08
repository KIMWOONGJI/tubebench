function [A, B, condM] = decomposeWaves(pa, pb, xa, xb, k)
%DECOMPOSEWAVES Forward/backward plane-wave amplitudes from two pressures.
%
%   [A, B, condM] = tim.acoustics.decomposeWaves(pa, pb, xa, xb, k)
%
%   Model (exp(+j*omega*t) convention, see wavenumber.m):
%       p(x) = A*exp(-j*k*x) + B*exp(+j*k*x)
%   A is the amplitude of the wave travelling towards +x (downstream) and
%   B the amplitude of the wave travelling towards -x, both referred to
%   x = 0 of the global tube coordinate system.
%
%   pa, pb : complex pressures (or pressures relative to a common reference
%            channel) at the microphone positions xa, xb [m]; column vectors
%   k      : complex wavenumber, same size as pa
%
%   Solution of [pa; pb] = M*[A; B], M = [e^{-jkxa} e^{jkxa}; e^{-jkxb} e^{jkxb}]:
%       det(M) = e^{-jk(xa-xb)} - e^{jk(xa-xb)} = 2j*sin(k*(xb-xa))
%       A = (pa*e^{jkxb} - pb*e^{jkxa}) / det
%       B = (pb*e^{-jkxa} - pa*e^{-jkxb}) / det
%   The system is singular when k*s = n*pi (s = |xb - xa|), i.e. at
%   f = n*c/(2s). condM returns the 2-norm condition number of M per frequency.

arguments
    pa (:,1) double
    pb (:,1) double
    xa (1,1) double {mustBeFinite}
    xb (1,1) double {mustBeFinite}
    k  (:,1) double
end
if xa == xb
    error('tim:decomp:geometry', 'Microphone positions must differ.');
end

ea = exp(1j * k * xa);  eb = exp(1j * k * xb);
detM = (1 ./ ea) .* eb - ea .* (1 ./ eb);
A = (pa .* eb - pb .* ea) ./ detM;
B = (pb ./ ea - pa ./ eb) ./ detM;

if nargout > 2
    % Condition number evaluated in PAIR-LOCAL coordinates (origin at the
    % pair midpoint): with a lossy k the global-coordinate matrix has
    % columns scaled by exp(+-k''x), which would make the diagnostic depend
    % on the arbitrary choice of origin (the solution itself does not).
    h = (xb - xa) / 2;
    condM = zeros(size(k));
    for i = 1:numel(k)
        e = exp(1j * k(i) * h);
        M = [e, 1/e; 1/e, e];        % rows: x = -h, x = +h
        condM(i) = cond(M);
    end
end
end
