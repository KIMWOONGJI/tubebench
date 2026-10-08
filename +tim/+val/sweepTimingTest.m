function r = sweepTimingTest(session)
%SWEEPTIMINGTEST Verify that the BUS-triggered sweep lies inside the record.
%
%   Measures one sweep with the configured settings and reports: detected
%   excitation start/end, the latency between the software trigger (in
%   received samples) and the detected acoustic start, the estimated sweep
%   law (duration, rate, residual) and the margins to the record edges.
%   Criteria: excitation detected; pre-roll margin > 0.2 s before the
%   acoustic start; >= 0.3 s of post-roll after the sweep; estimated
%   duration within 2 % of nominal.

c = session.Cfg.excitation;
ex = c; ex.sweep.repetitions = 1;
session.setExcitation(ex);
cleanup = onCleanup(@() session.setExcitation(c));
m = session.measure('sweep');
s = m.settings; fs = m.fs; ref = session.Cfg.analysis.refChannel;
x = m.records{1}(:, ref);
exd = tim.dsp.detectExcitation(x, fs, [s.fStart s.fStop], 12, s.preRoll);
law = tim.dsp.estimateSweepLaw(x, fs, s.fStart, s.fStop, s.spacing, s.duration);
trig_s = m.events{1}.triggerSample / fs;
r = struct('name', 'Sweep timing (no shared clock)', 'detected', exd.detected, ...
    'excitationStart_s', exd.start_s, 'excitationEnd_s', exd.end_s, ...
    'softwareTrigger_s', trig_s, 'sweepStartFromLaw_s', law.startTime_s, ...
    'apparentLatency_s', law.startTime_s - trig_s, 'duration_s', law.duration_s, ...
    'durationError', law.duration_s / s.duration - 1, 'lawResidual', law.residual, ...
    'preMargin_s', law.startTime_s, 'postMargin_s', numel(x) / fs - (law.startTime_s + law.duration_s), 'meas', m);
r.passed = exd.detected && r.preMargin_s > 0.2 && r.postMargin_s > 0.3 && abs(r.durationError) < 0.02;
r.criteria = 'excitation detected, > 0.2 s pre-margin, > 0.3 s post-margin, duration within 2 %';
r.note = ['apparentLatency includes network/stream buffering and the generator trigger latency; it is ' ...
    'NOT used by the analysis (relative responses are excitation-timing independent).'];
end
