function [cfg, band] = analysisBand(cfg)
%ANALYSISBAND The analysis band of a configuration: fixed, or the ASTM limits of the tube.
%
%   [cfg, band] = tim.app.analysisBand(cfg)
%
%   cfg.analysis.bandMode (owner decision 2026-10-13):
%     'fixed'    (default) analysis.fMin / fMax as configured;
%     'geometry' the geometric limits of ASTM E1050 / E2611 for the tube in
%                cfg.geometry (tim.acoustics.frequencyLimits: spacing
%                analysis.lowerFraction..upperFraction x c/s, default
%                0.01-0.40 c/s, and the plane-wave limit 0.58 c/D) at the speed
%                of sound of cfg.environment, rounded inward to the line
%                spacing analysis.df, are written into analysis.fMin / fMax. They
%                follow the microphone spacings, the diameter and the
%                temperature. With incomplete geometry (diameter or a spacing
%                not a positive number) the configured values stay.
%   Called by loadConfig, validateConfig, processMeasurement and
%   runCalibration, and by the window when the IMPEDANCE TUBE fields change,
%   so every part uses the band of the geometry it works with. A calibration
%   covers the band it was made with; lines of a later, wider band have no
%   calibration there and are not valid (tim.cal.interpolateCalibration).
%
%   band: fMin, fMax (the band used), mode, limits ([fLower fUpper] of the
%   geometry, NaN if unknown), outside (a fixed band beyond those limits),
%   text (which standard the band follows, for the window and messages).

a = cfg.analysis;
mode = 'fixed';
if isfield(a, 'bandMode') && (ischar(a.bandMode) || isstring(a.bandMode)), mode = lower(char(a.bandMode)); end
band = struct('fMin', a.fMin, 'fMax', a.fMax, 'mode', mode, 'limits', [NaN NaN], 'outside', false, 'text', '');
g = cfg.geometry;
known = all(isfield(g, {'diameter', 'spacingUp', 'spacingDown'})) && ...
    all(cellfun(@(v) isnumeric(v) && isscalar(v) && isfinite(v) && v > 0, {g.diameter, g.spacingUp, g.spacingDown}));
astm = 'ASTM E1050 / E2611';
if known
    try
        air = tim.acoustics.airProperties(cfg.environment);
        lim = tim.acoustics.frequencyLimits(g.diameter, [g.spacingUp g.spacingDown], air, ...
            'LowerFraction', a.lowerFraction, 'UpperFraction', a.upperFraction);
        band.limits = [lim.fLower lim.fUpper];
    catch
        known = false;
    end
end
rule = sprintf('%g–%g c/s', a.lowerFraction, a.upperFraction);
if strcmp(mode, 'geometry') && known
    df = a.df;
    if ~(isnumeric(df) && isscalar(df) && isfinite(df) && df > 0), df = 1; end
    band.fMin = df * ceil(band.limits(1) / df - 1e-9);
    band.fMax = df * floor(band.limits(2) / df + 1e-9);
    cfg.analysis.fMin = band.fMin; cfg.analysis.fMax = band.fMax;
    band.text = sprintf('%s limits of this tube (%s)', astm, rule);
elseif strcmp(mode, 'geometry')
    band.text = sprintf('configured: the tube geometry is incomplete for the %s limits', astm);
else
    band.outside = known && (band.fMin < band.limits(1) * (1 - 1e-9) || band.fMax > band.limits(2) * (1 + 1e-9));
    if known
        band.text = sprintf('fixed in the configuration; %s limits of this tube %.0f–%.0f Hz', astm, ...
            band.limits(1), band.limits(2));
    else
        band.text = 'fixed in the configuration';
    end
end
end
