function L = peakLevel(meas)
%PEAKLEVEL Highest sound pressure in the tube during a measurement (WO-005).
%
%   L = tim.app.peakLevel(meas)
%
%   L.peak_dB   (1 x C, DAQ channel order) 20 log10(max |p(t)| / 20 µPa) over
%               all repetitions: the PEAK level (not rms), from the
%               sensitivity layer; NaN without a sensitivity or for data in
%               full-scale units
%   L.max_dB    the highest channel
%   The two-load method compares the level the specimen meets with each
%   termination: a rigid cap raises it at the tube resonances, and a specimen
%   that is not linear at that level gives inconsistent loads.

C = 0;
if isfield(meas, 'records') && ~isempty(meas.records), C = size(meas.records{1}, 2); end
L = struct('peak_dB', nan(1, C), 'max_dB', NaN);
if C == 0, return; end
unit = 'V'; if isfield(meas, 'unit') && ~isempty(meas.unit), unit = char(meas.unit); end
if ~strcmp(unit, 'V') || ~isfield(meas, 'mics') || ~isfield(meas.mics, 'sensitivity_VperPa'), return; end
mics = tim.app.MeasurementSession.micsByChannel(meas.mics);
s = nan(1, C);
for i = 1:numel(mics)
    c = mics(i).channel;
    if c >= 1 && c <= C, s(c) = mics(i).sensitivity_VperPa; end
end
vmax = zeros(1, C);
for r = 1:numel(meas.records)
    x = meas.records{r};
    vmax = max(vmax, max(abs(x - mean(x, 1)), [], 1));
end
s(~(s > 0)) = NaN;
L.peak_dB = 20 * log10(vmax ./ s / 2e-5);
L.max_dB = max(L.peak_dB, [], 'omitnan');
if isempty(L.max_dB), L.max_dB = NaN; end
end
