function air = airProperties(env)
%AIRPROPERTIES Speed of sound, density, viscosity and impedance of air.
%
%   air = tim.acoustics.airProperties(env)
%
%   env fields (SI units):
%     temperature_C   air temperature in the tube [degC]
%     pressure_Pa     static (ambient) pressure p_s [Pa]
%     c_override      optional, speed of sound [m/s] (empty = computed)
%     rho_override    optional, air density [kg/m^3] (empty = computed)
%
%   Formulas (T in kelvin):
%     c0   = 343.2 m/s * sqrt(T / 293 K)          ISO 10534-2:1998 eq. (3)
%     rho0 = p_s / (R_d * T),  R_d = 287.05 J/(kg K)
%            ideal-gas law for DRY air (R_d = R/M, M = 28.9647 g/mol):
%            1.2041 kg/m^3 at 20 degC, 101325 Pa.
%     mu   = 1.716e-5 Pa s * (T/273.15)^1.5 * (273.15 + 110.4)/(T + 110.4)
%            (Sutherland's law, dry air; 1.813e-5 Pa s at 20 degC)
%     gamma = 1.4, Pr = 0.709 (dry air near room temperature; both vary
%            by < 0.5 % between 0 and 40 degC)
%   The pair (c0, rho0) is thermodynamically consistent: rho0*c0^2 = gamma*p_s
%   holds to 0.03 % (gamma = 1.4005 at 20 degC). The former ISO 10534-2
%   density rho = 1.186*(p_s/101325)*(293/T) is 1.55 % below the density of
%   air at 20 degC (rho*c^2/p_s = 1.379 instead of 1.40); it biased every
%   absolute impedance in Pa s/m (Zt, T12, T21) low by 1.5 %. Quantities
%   normalised by rho*c (R, tau, TL, alpha, Zt/rho c) do not depend on rho.
%   Humidity is neglected: at 20 degC / 50 % RH, c is 0.18 % higher and rho
%   0.44 % lower than for dry air (uncertainty budget; for thin elements with
%   small |Zt|/rho c the c error matters, see docs/theory.md).
%   mu, gamma and Pr are used only by the visco-thermal tube-loss model
%   (tim.acoustics.wavenumber, lossModel 'kirchhoff').
%
%   Returns struct: c [m/s], rho [kg/m^3], Z0 = rho*c [Pa*s/m], T_K,
%   pressure_Pa, mu [Pa s], nu = mu/rho [m^2/s], gamma, Pr, source.

arguments
    env struct
end

T_K = env.temperature_C + 273.15;
if T_K < 200 || T_K > 350
    error('tim:air:temperature', 'Temperature %.1f degC outside plausible range.', env.temperature_C);
end
pa = env.pressure_Pa;
if pa < 5e4 || pa > 1.2e5
    error('tim:air:pressure', 'Ambient pressure %.0f Pa outside plausible range.', pa);
end

Rd = 287.05;                                   % specific gas constant of dry air [J/(kg K)]
c = 343.2 * sqrt(T_K / 293);
rho = pa / (Rd * T_K);
src = 'c: ISO 10534-2 eq.(3); rho: ideal gas, dry air (287.05 J/(kg K))';
if isfield(env, 'c_override') && ~isempty(env.c_override)
    c = env.c_override; src = [src ' (c overridden)'];
end
if isfield(env, 'rho_override') && ~isempty(env.rho_override)
    rho = env.rho_override; src = [src ' (rho overridden)'];
end
mu = 1.716e-5 * (T_K / 273.15)^1.5 * (273.15 + 110.4) / (T_K + 110.4);

air = struct('c', c, 'rho', rho, 'Z0', rho * c, 'T_K', T_K, 'pressure_Pa', pa, ...
    'mu', mu, 'nu', mu / rho, 'gamma', 1.4, 'Pr', 0.709, 'source', src);
end
