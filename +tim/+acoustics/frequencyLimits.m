function lim = frequencyLimits(diameter, spacing, air, opts)
%FREQUENCYLIMITS Geometric working-frequency limits of a two-microphone tube.
%
%   lim = tim.acoustics.frequencyLimits(d, s, air)
%   lim = tim.acoustics.frequencyLimits(d, s, air, 'LowerFraction', 0.01, ...)
%
%   d  inner diameter [m];  s  microphone spacing [m] (scalar or vector of
%   spacings, e.g. upstream and downstream pair); air from airProperties.
%
%   Criteria (all are rules of thumb from the standards, NOT uncertainty
%   statements; see docs/theory.md section "Frequency limits"):
%
%   * Plane-wave limit, circular duct: the first non-planar mode (1,1)
%     cuts on at  f_c = 1.8412 * c / (pi * d) = 0.586 * c / d  (zero of J1').
%     ISO 10534-2 recommends  f_u < 0.58 * c / d  (= 0.990 * f_c) as the
%     upper limit; it is therefore always the binding diameter rule
%     (lab, d = 29 mm, 20 degC: 6866 Hz vs f_c = 6938 Hz).
%   * The limits use the speed of sound c; with lossModel 'kirchhoff' the
%     phase speed is c/(1 + k''/k0), lower by 1 % at 120 Hz and by 0.15 %
%     near c/(2s) (D = 29 mm), which moves k*s = pi down by 0.15 %
%     (9 Hz for s = 29 mm). The near-singularity mask
%     (validityMasks) uses real(k) and therefore follows it exactly.
%   * Spacing singularity: wave decomposition is singular at k*s = n*pi,
%     first at  f_s = c / (2*s).
%   * Spacing upper limit: ASTM E1050 / E2611 recommend  f_u = K_u * c / s
%     with K_u = 0.40 (k*s <= 0.8*pi, i.e. 80 % of the singular frequency);
%     ISO 10534-2 uses  f_u*s < 0.45*c  (K_u = 0.45).  Default: 0.40.
%   * Spacing lower limit: ASTM E1050 recommends s > 1 % of the wavelength,
%     f_l = K_l * c / s with K_l = 0.01 (ISO 10534-2 suggests s > 5 % of
%     the wavelength for improved accuracy -> K_l = 0.05). Default: 0.01.
%
%   Output struct lim (all in Hz):
%     cutOn11, isoDiameterLimit, singular (per spacing), upperSpacing,
%     lowerSpacing, fLower (max of lower limits), fUpper (min of upper
%     limits), criteria (text)

arguments
    diameter (1,1) double {mustBePositive}
    spacing (1,:) double {mustBePositive}
    air struct
    opts.LowerFraction (1,1) double {mustBePositive} = 0.01
    opts.UpperFraction (1,1) double {mustBePositive} = 0.40
end
c = air.c;
lim.cutOn11 = 1.8412 * c / (pi * diameter);
lim.isoDiameterLimit = 0.58 * c / diameter;
lim.singular = c ./ (2 * spacing);
lim.upperSpacing = opts.UpperFraction * c ./ spacing;
lim.lowerSpacing = opts.LowerFraction * c ./ spacing;
lim.fLower = max(lim.lowerSpacing);
lim.fUpper = min([lim.upperSpacing, lim.isoDiameterLimit, lim.cutOn11]);
lim.lowerFraction = opts.LowerFraction;
lim.upperFraction = opts.UpperFraction;
lim.criteria = sprintf(['f_l = %.3g*c/s (spacing >= %.0f%% of wavelength); ' ...
    'f_u = min(%.2f*c/s, 0.58*c/D, (1,1)-mode cut-on)'], ...
    opts.LowerFraction, 100 * opts.LowerFraction, opts.UpperFraction);
end
