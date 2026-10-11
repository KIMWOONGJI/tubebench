function r = testC_calibrationConsistency(cal, measA, measB, cfg, channels)
%TESTC_CALIBRATIONCONSISTENCY Consistency before/after channel correction (Test C).
%
%   r = tim.val.testC_calibrationConsistency(cal, measA, measB, cfg, [a b])
%
%   measA : channel a at port pA, channel b at port pB
%   measB : the two microphones physically interchanged (a at pB, b at pA),
%           same acoustic field (same sample, termination, excitation).
%   With H_c = Y_c / Y_ref:
%     measA:  H_b/H_a = (c_b p_B)/(c_a p_A)     measB:  H_a/H_b = (c_a p_B)/(c_b p_A)
%   Both estimate the port ratio p_B/p_A; uncorrected they differ by
%   (c_b/c_a)^2, after correction they must agree. Reported: rms difference
%   (dB, deg) over the valid bins before and after correction.
%   Criteria: after correction < 0.05 dB and < 0.3 deg rms.
%   H is estimated as in the calibration and the measurements (sweep gate,
%   tim.dsp.sweepResponse with the sweep settings); r.gated tells per
%   repetition whether the gate was used, r.warnings lists the estimator's
%   warnings.
%   NOTE: if the calibration was derived from the very same two
%   measurements this test is circular; use an independent repetition.

a = cfg.analysis;
% the estimator of the calibration and the measurements it checks (sweep
% gate: generator on/off transients excluded; tim.app.processMeasurement)
opts = @(m) struct('refChannel', a.refChannel, 'fRange', [a.fMin a.fMax], 'df', a.df, ...
    'preRoll', m.settings.preRoll, 'excitationBand', [m.settings.fStart m.settings.fStop], ...
    'ringDown', min(m.settings.postRoll, 0.5), 'sweep', m.settings);
sA = tim.dsp.sweepResponse(measA.records, measA.fs, opts(measA));
sB = tim.dsp.sweepResponse(measB.records, measB.fs, opts(measB));
ca = channels(1); cb = channels(2);
f = sA.f;
rawA = sA.H(:, cb) ./ sA.H(:, ca);
rawB = sB.H(:, ca) ./ sB.H(:, cb);
[Hc, cv] = tim.cal.applyCalibration(f, sA.H, cal, a.refChannel);
Hd = tim.cal.applyCalibration(f, sB.H, cal, a.refChannel);
corA = Hc(:, cb) ./ Hc(:, ca);
corB = Hd(:, ca) ./ Hd(:, cb);
ok = cv & all(sA.coherence(:, [ca cb]) > a.coherenceMin, 2) & all(sB.coherence(:, [ca cb]) > a.coherenceMin, 2);
d0 = rawA ./ rawB; d1 = corA ./ corB;
r = struct('name', 'Test C - calibration consistency', 'channels', channels, 'validBins', nnz(ok), ...
    'before_rms_dB', rms(20 * log10(abs(d0(ok)))), 'before_rms_deg', rms(rad2deg(angle(d0(ok)))), ...
    'after_rms_dB', rms(20 * log10(abs(d1(ok)))), 'after_rms_deg', rms(rad2deg(angle(d1(ok)))));
r.gated = [sA.excitation.gated, sB.excitation.gated];   % sweep gate used per repetition (A, then B)
r.warnings = unique([sA.warnings, sB.warnings], 'stable');
r.passed = nnz(ok) > 0 && r.after_rms_dB < 0.05 && r.after_rms_deg < 0.3;
r.criteria = 'corrected estimates agree: < 0.05 dB and < 0.3 deg rms over valid bins';
end
