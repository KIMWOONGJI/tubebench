function mics = resolveSensitivities(mics, teds, policy)
%RESOLVESENSITIVITIES Decide the V/Pa sensitivity of each microphone chain.
%
%   mics = tim.cal.resolveSensitivities(mics, teds, policy)
%
%   mics   : struct array from the configuration (fields channel, position,
%            model, serial, nominalSensitivity_VperPa, certificateSensitivity_VperPa,
%            certificateDate)
%   teds   : 1xN cell from tim.instr.LanXi.detectTransducers ([] if absent)
%   policy : 'certificate>teds>nominal' (default) | 'teds>certificate>nominal'
%
%   Adds fields: sensitivity_VperPa (used), sensitivitySource, tedsSensitivity_VperPa,
%   tedsSerial, tedsType, serialMismatch (TEDS serial ~= configured serial).
%   Sensitivity is used ONLY to express levels in Pa / dB SPL. It is never a
%   substitute for the switching calibration (calibration factors C_k =
%   g_k / g_ref, tim.cal.*).

if nargin < 3 || isempty(policy), policy = 'certificate>teds>nominal'; end
order = strsplit(policy, '>');
for i = 1:numel(mics)
    ch = mics(i).channel;
    t = [];
    if ~isempty(teds) && numel(teds) >= ch, t = teds{ch}; end
    mics(i).tedsSensitivity_VperPa = NaN; mics(i).tedsSerial = NaN; mics(i).tedsType = '';
    mics(i).serialMismatch = false;
    if ~isempty(t)
        if strcmpi(strtrim(t.unit), 'Pa')
            mics(i).tedsSensitivity_VperPa = t.sensitivity;
        end
        mics(i).tedsSerial = t.serialNumber;
        mics(i).tedsType = t.typeNumber;
        cfgSerial = str2double(string(mics(i).serial));
        mics(i).serialMismatch = isfinite(cfgSerial) && cfgSerial ~= t.serialNumber;
    end
    cand = struct('certificate', mics(i).certificateSensitivity_VperPa, ...
        'teds', mics(i).tedsSensitivity_VperPa, 'nominal', mics(i).nominalSensitivity_VperPa);
    mics(i).sensitivity_VperPa = NaN; mics(i).sensitivitySource = 'none';
    for k = 1:numel(order)
        v = cand.(order{k});
        if ~isempty(v) && isfinite(v) && v > 0
            mics(i).sensitivity_VperPa = v;
            mics(i).sensitivitySource = order{k};
            break
        end
    end
    if ~(mics(i).sensitivity_VperPa > 0)
        error('tim:cal:sensitivity', 'No sensitivity available for ch%d (no certificate, TEDS or nominal value).', ch);
    end
end
end
