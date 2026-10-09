function r = testA_acquisition(session, duration)
%TESTA_ACQUISITION Electrical/acquisition checks without excitation (Test A).
%
%   r = tim.val.testA_acquisition(session, 2)
%   Checks: sample rate in stream, unit (no double sensitivity), packet
%   integrity (no corruption, no timestamp gaps, no overrun), overload,
%   DataQuality flags (cable fault / CCLD), dead channels, background level.
%   Criteria: integrity.ok must be true. Background level is reported in dB SPL
%   (using the sensitivity layer) for the operator to judge.

if nargin < 2, duration = 2; end
m = session.measureBackground(duration);
info = m.channelInfo{1};
x = m.records{1};
p = tim.acq.voltsToPascal(x - mean(x, 1), tim.app.MeasurementSession.micsByChannel(m.mics), 'V');   % column c = channel c
[P, f] = pwelch(p, hann(4096, 'periodic'), 2048, 4096, m.fs);
band = f >= 100 & f <= 5000;
lvl = 10 * log10(sum(P(band, :), 1) * (f(2) - f(1)) / (2e-5)^2);
r = struct('name', 'Test A - acquisition/electrical', 'passed', info.integrity.ok, ...
    'fatal', {info.integrity.fatal}, 'warnings', {info.integrity.warnings}, ...
    'fs', info.fs, 'unit', {info.unit}, 'scaleFactor', info.scaleFactor, ...
    'stats', info.stats, 'backgroundLevel_dB_100_5000Hz', lvl, 'meas', m);
r.criteria = 'stream integrity OK (no corrupt/missing data, no overload/INVALID/OVERRUN flags, unit V, fs as configured)';
end
