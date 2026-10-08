function air = airProperties(env)
%AIRPROPERTIES Speed of sound, density and characteristic impedance of air.
%
%   air = tim.acoustics.airProperties(env)
%
%   env fields (SI units):
%     temperature_C   air temperature in the tube [degC]
%     pressure_Pa     static (ambient) pressure [Pa]
%     c_override      optional, speed of sound [m/s] (empty = computed)
%     rho_override    optional, air density [kg/m^3] (empty = computed)
%
%   Formulas (ISO 10534-2:1998, clause 4 / eq. (3),(4)):
%     c0   = 343.2 * sqrt(T / 293)                         [m/s]
%     rho0 = 1.186 * (pa / 101325) * (293 / T)             [kg/m^3]
%   with T in kelvin. Valid for dry-ish air near room conditions; the
%   humidity dependence of c (~0.1 %-0.3 %) is neglected and should be
%   accounted for in the uncertainty budget.
%
%   Returns struct: c [m/s], rho [kg/m^3], Z0 = rho*c [Pa*s/m], T_K, source.

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

c = 343.2 * sqrt(T_K / 293);
rho = 1.186 * (pa / 101325) * (293 / T_K);
src = 'ISO 10534-2 eq.(3),(4)';
if isfield(env, 'c_override') && ~isempty(env.c_override)
    c = env.c_override; src = [src ' (c overridden)'];
end
if isfield(env, 'rho_override') && ~isempty(env.rho_override)
    rho = env.rho_override; src = [src ' (rho overridden)'];
end

air = struct('c', c, 'rho', rho, 'Z0', rho * c, 'T_K', T_K, 'pressure_Pa', pa, 'source', src);
end
