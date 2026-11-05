function plan = equalizerPlan(eq, freqs, preLevels, vPre, vMax, vMin)
%EQUALIZERPLAN Generator level of every step from the pre-measurement (1.6.0, WO-006).
%
%   plan = tim.app.equalizerPlan(eq, freqs, preLevels, vPre, vMax, vMin)
%
%   eq         tim.app.equalizerSettings (mode 'incidentPressure' | 'faceVelocity')
%   freqs      step frequencies [Hz] (tim.app.steppedPlan)
%   preLevels  res.levels of the pre-measurement (tim.app.processMeasurement):
%              incident_dB_SPL and faceVelocity_mm_s per step, played at vPre
%   vPre       generator level of the pre-measurement [Vpp]
%   vMax       the amplitude field (excitation.stepped.amplitudeVpp): the
%              MAXIMUM of every step [Vpp]
%   vMin       the smallest level of the source at its load [Vpp]
%              (tim.instr.SignalSource.levelRange)
%
%   Feedforward rule (owner decisions 2026-11-04): the transfer from the
%   generator voltage to the controlled quantity q is taken as linear, so per
%   step
%       V_k = min(vMax, vPre * t / q_k)
%   with q_k the controlled quantity the pre-measurement achieved at step k
%   and t the target, both linear: the incident pressure in Pa rms
%   (20 uPa x 10^(L/20)) or the face velocity in mm/s. A step that would need
%   more than vMax is played at vMax: the target is not reached there, which
%   is REPORTED (plan.limited 'max', res.equalizer.reached), never masked.
%   Below the source's minimum the step is played at its minimum ('min': above
%   the target); without a level from the pre-measurement (q not finite or
%   not positive) at vPre ('unknown'). The voltages lie on a 0.1 mVpp grid
%   (a level command with four decimals programs them exactly; at most
%   0.04 dB at 20 mVpp), rounded within [vMin, vMax]; vMax itself is kept as
%   it is. No step is ever above vMax.
%
%   plan.mode, .unit ('dB SPL' | 'mm/s'), .target, .tolerance_dB,
%   .preLevel_dB    the settings
%   plan.freqs      (1 x n) step frequencies [Hz]
%   plan.vpp        (1 x n) generator level of every step [Vpp]
%   plan.limited    (1 x n cellstr) '' | 'max' | 'min' | 'unknown'
%   plan.expected   (1 x n) the controlled quantity expected at vpp (unit)
%   plan.maxVpp, .minVpp, .preVpp
%   plan.pre        the pre-measurement result per step: f, vpp, achieved (in
%                   the unit of the mode), incident_dB_SPL, faceVelocity_mm_s,
%                   valid (validR of its lines); the session adds timestamp,
%                   integrityOk and calibration
%   plan.termination  (the session) the termination it was measured with
%   plan.chain        (the session) generator load and amplifier it was measured with
%   plan.reusedFrom   '' or the load whose plan it is ('A' for load A again)
%   plan.created      time of the plan

freqs = reshape(double(freqs), 1, []);
n = numel(freqs);
if ~(all(isfield(preLevels, {'incident_dB_SPL', 'faceVelocity_mm_s'})) && ...
        numel(preLevels.incident_dB_SPL) == n && numel(preLevels.faceVelocity_mm_s) == n)
    error('tim:equalizer:levels', 'Equalizer: the pre-measurement gives no level for each of the %d steps.', n);
end
L = reshape(double(preLevels.incident_dB_SPL), 1, []);
u = reshape(double(preLevels.faceVelocity_mm_s), 1, []);
switch eq.mode
    case 'incidentPressure'
        unit = 'dB SPL';
        q = 20e-6 * 10.^(L / 20);                % Pa rms
        t = 20e-6 * 10^(eq.target / 20);
        achieved = L;
    case 'faceVelocity'
        unit = 'mm/s';
        q = u;                                   % mm/s rms
        t = eq.target;
        achieved = u;
    otherwise
        error('tim:equalizer:mode', 'Equalizer mode ''%s'': no plan (incidentPressure or faceVelocity).', ...
            char(string(eq.mode)));
end
if ~(isscalar(vPre) && vPre > 0 && isscalar(vMax) && vMax >= vPre && isscalar(vMin) && vMin >= 0)
    error('tim:equalizer:levels', 'Equalizer: invalid levels (pre %g Vpp, maximum %g Vpp, minimum %g Vpp).', ...
        vPre, vMax, vMin);
end
dv = 1e-4;                                       % grid of the levels: 0.1 mVpp
vLo = min(vMax, ceil(vMin / dv - 1e-9) * dv);   % the smallest grid level at or above the minimum
vpp = zeros(1, n);
limited = repmat({''}, 1, n);
for k = 1:n
    if ~(isfinite(q(k)) && q(k) > 0)
        vpp(k) = vPre; limited{k} = 'unknown';
        continue
    end
    v = vPre * t / q(k);
    if v > vMax
        vpp(k) = vMax; limited{k} = 'max';       % target not reachable: reported only
    elseif v < vMin
        vpp(k) = vLo; limited{k} = 'min';
    else
        vpp(k) = min(vMax, max(vLo, round(v / dv) * dv));
    end
end
expected = nan(1, n);
ok = ~strcmp(limited, 'unknown');
if strcmp(eq.mode, 'incidentPressure')
    expected(ok) = L(ok) + 20 * log10(vpp(ok) / vPre);
else
    expected(ok) = u(ok) .* vpp(ok) / vPre;
end
valid = false(1, n);
if isfield(preLevels, 'valid') && numel(preLevels.valid) == n, valid = reshape(logical(preLevels.valid), 1, []); end
pre = struct('f', freqs, 'vpp', repmat(vPre, 1, n), 'achieved', achieved, 'incident_dB_SPL', L, ...
    'faceVelocity_mm_s', u, 'valid', valid, 'timestamp', '', 'integrityOk', true, 'calibration', '');
plan = struct('mode', eq.mode, 'unit', unit, 'target', eq.target, 'tolerance_dB', eq.tolerance_dB, ...
    'preLevel_dB', eq.preLevel_dB, 'freqs', freqs, 'vpp', vpp, 'limited', {limited}, 'expected', expected, ...
    'maxVpp', vMax, 'minVpp', vMin, 'preVpp', vPre, 'pre', pre, 'termination', [], 'chain', [], 'reusedFrom', '', ...
    'created', char(datetime('now'), 'yyyy-MM-dd HH:mm:ss.SSS'));
end
