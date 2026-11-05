classdef TestEqualizer < matlab.unittest.TestCase
    %TESTEQUALIZER Level equalizer of the stepped sine (1.6.0, WO-006 stage 2).
    %
    %   Owner decisions 2026-11-04: feedforward from a pre-measurement of the
    %   same steps at preLevel_dB (-20 dB) below the amplitude field; per step
    %   V_k = min(maximum, V_pre x target / achieved_k) (tim.app.equalizerPlan);
    %   the amplitude field is the MAXIMUM of every step and of the drive check;
    %   a step that misses the target is reported (res.equalizer), never
    %   masked; a signal source without capabilities().source.levelWhileOn is
    %   refused before anything is armed (tim:session:equalizer); two loads: a
    %   pre-measurement after every change of termination, load A again with
    %   the voltages of load A, the B level ignored.
    %
    %   Checked: the plan rule (pure), both controlled quantities reach the
    %   target in the virtual tube, steps capped at the maximum, the refusals,
    %   the stepped sine with the equalizer off (the same SCPI traffic as
    %   without the setting), the reuse of a plan, a Stop during the
    %   pre-measurement and after it (the recorded pre-measurement kept, no
    %   plan armed), the simulated combined device (planned output) and the
    %   two-load sequence (also stopped: no plan left armed). One switching calibration of the virtual tube is
    %   made for the class (the combined device uses it too: the chains of the
    %   virtual microphones are the same). Simulation: the virtual tube is
    %   linear, so the tests verify the mechanics, not physical accuracy.

    properties
        cfg     % the configuration of the class: stepped sine, 8 steps 200-4000 Hz, default timing
        cal     % switching calibration of the virtual tube
        tmp
    end

    methods (TestClassSetup)
        function calibrate(tc)
            f = tc.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            tc.tmp = f.Folder;
            c = tim.app.defaultConfig();
            c.geometry = c.simulation.Geometry;            % simulated "measured" geometry
            c.output.dataDir = fullfile(tc.tmp, 'data');
            c.output.calibrationDir = fullfile(tc.tmp, 'cal');
            c.excitation.sweep.duration = 3;
            c.excitation.sweep.repetitions = 2;
            c.calibration.repeatConfigI = false;
            c.excitation.mode = 'stepped';
            c.excitation.stepped.fStart = 200; c.excitation.stepped.fStop = 4000;
            c.excitation.stepped.nPoints = 8;
            s = tim.app.MeasurementSession(c);
            cleanup = onCleanup(@() s.close());
            s.connect(); s.prepareAcquisition();
            tc.cal = tim.app.runCalibration(s);
            clear cleanup
            tc.cfg = c;
        end
    end

    methods
        function [s, c] = session(tc, mode, target, edit)
            % a calibrated session in the virtual tube (a new rig: the
            % calibration moved the microphones of its own) with the equalizer
            % in mode; edit(c) changes the configuration first
            c = tc.cfg;
            c.excitation.stepped.equalizer.mode = mode;
            if nargin >= 3 && ~isempty(target), c.excitation.stepped.equalizer.target = target; end
            if nargin >= 4, c = edit(c); end
            s = tim.app.MeasurementSession(c);
            tc.addTeardown(@() s.close());
            s.connect(); s.prepareAcquisition();
            s.Calibration = tc.cal;
        end

        function d = subfolder(tc, name)
            d = fullfile(tc.tmp, name);
            if ~isfolder(d), mkdir(d); end
        end
    end

    methods (Test)
        function planRule(tc)
            % tim.app.equalizerPlan: V_k = vPre x target / achieved_k on the 0.1 mVpp
            % grid, capped at the maximum ('max', reported), raised to the minimum
            % ('min'), the pre-measurement level without a level ('unknown')
            eq = struct('mode', 'incidentPressure', 'target', 77, 'preLevel_dB', -20, 'tolerance_dB', 1);
            L = [70 75 80 NaN 55];
            lv = struct('incident_dB_SPL', L.', 'faceVelocity_mm_s', [1 2 4 NaN 0.1].', 'valid', true(5, 1));
            f = [200 400 800 1600 3200];
            p = tim.app.equalizerPlan(eq, f, lv, 0.02, 0.2, 0.02);
            % raw 0.02 x 10^((77 - L)/20): 0.044774, 0.025179, 0.014159, -, 0.25179
            tc.verifyEqual(p.vpp, [0.0448 0.0252 0.02 0.02 0.2], 'AbsTol', 1e-12);
            tc.verifyEqual(p.limited, {'', '', 'min', 'unknown', 'max'});
            tc.verifyEqual(p.unit, 'dB SPL');
            ok = [1 2 3 5];
            tc.verifyEqual(p.expected(ok), L(ok) + 20 * log10(p.vpp(ok) / 0.02), 'AbsTol', 1e-9);
            tc.verifyEqual(p.expected(1:2), [77 77], 'AbsTol', 0.02, 'the target within the grid');
            tc.verifyTrue(isnan(p.expected(4)));
            tc.verifyEqual(p.pre.achieved, L);
            tc.verifyEqual(p.pre.vpp, repmat(0.02, 1, 5));
            tc.verifyEqual(p.pre.f, f);
            tc.verifyEqual([p.preVpp p.maxVpp p.minVpp], [0.02 0.2 0.02]);
            tc.verifyEqual(p.reusedFrom, '');
            % face velocity [mm/s]: 0.02 x 3 / u = 0.06, 0.03, 0.015 (min), -, 0.6 (max)
            eq.mode = 'faceVelocity'; eq.target = 3;
            p = tim.app.equalizerPlan(eq, f, lv, 0.02, 0.2, 0.02);
            tc.verifyEqual(p.vpp, [0.06 0.03 0.02 0.02 0.2], 'AbsTol', 1e-12);
            tc.verifyEqual(p.limited, {'', '', 'min', 'unknown', 'max'});
            tc.verifyEqual(p.unit, 'mm/s');
            tc.verifyEqual(p.expected([1 2 3 5]), [3 3 4 1], 'RelTol', 1e-9);
            % a minimum off the grid (a load of 600 ohm: 20 mVpp x 600/650) and a maximum off the grid
            p = tim.app.equalizerPlan(eq, f, lv, 0.02, 0.23456, 0.02 * 600 / 650);
            tc.verifyEqual(p.vpp(3), 0.0185, 'AbsTol', 1e-12, 'the smallest grid level at or above the minimum');
            tc.verifyEqual(p.vpp(5), 0.23456, 'the maximum as it is');
            tc.verifyLessThanOrEqual(p.vpp, 0.23456);
            % refused: no mode, levels that do not fit the steps
            eq.mode = 'off';
            tc.verifyError(@() tim.app.equalizerPlan(eq, f, lv, 0.02, 0.2, 0.02), 'tim:equalizer:mode');
            eq.mode = 'faceVelocity';
            tc.verifyError(@() tim.app.equalizerPlan(eq, f(1:4), lv, 0.02, 0.2, 0.02), 'tim:equalizer:levels');
            tc.verifyError(@() tim.app.equalizerPlan(eq, f, lv, 0.3, 0.2, 0.02), 'tim:equalizer:levels', 'pre above the maximum');
        end

        function reachesTheTargetIncident(tc)
            % incident pressure 77 dB SPL (the virtual tube gives about 83 dB SPL at
            % the maximum 0.2 Vpp): every step reached, never above the maximum, the
            % rig followed every level change
            [s, c] = tc.session('incidentPressure', 77);
            asked = {};
            function ok = confirm(msg)
                asked{end + 1} = msg; ok = true;
            end
            s.ExcitationConfirm = @confirm;               % the operator confirmation, as in the window
            m = s.measure('stepped');
            r = tim.app.processMeasurement(m, c, tc.cal);
            p = m.equalizer; q = r.equalizer;
            tc.verifyTrue(all(q.reached), q.text);
            tc.verifyLessThan(max(abs(q.deviation_dB)), 0.3);
            tc.verifyTrue(all(strcmp(p.limited, '')), 'no step at a limit');
            % confirmed once for the pre-measurement and the measurement, at the maximum
            tc.verifyNumElements(asked, 1, 'one confirmation (the same signature: the maximum)');
            tc.verifySubstring(asked{1}, 'Generator: 0.1 Vpk (0.2 Vpp, open circuit)');
            tc.verifySubstring(asked{1}, 'Equalizer: a pre-measurement of the steps at -20 dB (0.01 Vpk)');
            tc.verifyLessThanOrEqual(p.vpp, 0.2);
            tc.verifyEqual(m.settings.stepAmplitudeVpp, p.vpp);
            tc.verifyEqual(r.levels.generatorVpp, p.vpp(:));
            tc.verifyEqual(q.vpp, p.vpp(:));
            tc.verifyEqual(q.achieved, r.levels.incident_dB_SPL);
            % what the generator received: the pre-measurement level and the plan
            h = tim.instr.Keysight33220A.testHooks(s.Gen);
            lv = h.levelHistory();
            tc.verifyLessThanOrEqual(lv, 0.2 * (1 + 1e-9), 'no level above the amplitude field');
            tc.verifyTrue(all(ismember(round(p.vpp * 1e7), round(lv * 1e7))), 'every level of the plan was programmed');
            tc.verifyTrue(any(abs(lv - p.preVpp) < 1e-9), 'the pre-measurement level');
            tc.verifyEqual(p.preVpp, 0.02, 'AbsTol', 1e-12, '-20 dB of 0.2 Vpp');
            tc.verifyFalse(h.outputOn()); tc.verifyFalse(s.Gen.OutputArmed);
            % the rig followed the level changes: the achieved level moved with the voltage
            tc.verifyEqual(q.achieved - p.pre.achieved(:), 20 * log10(p.vpp(:) / p.preVpp), 'AbsTol', 0.1);
            % the drive check and the confirmation used the maximum (owner decision 2026-11-04)
            tc.verifyEqual(m.settings.amplitudeVpp, 0.2);
            tc.verifyEqual(m.metadata.drive, tim.app.driveEstimate(s.Cfg, 0.2, 'stepped'));
            % traceability: the plan with the pre-measurement result, the summary in the metadata
            tc.verifyEqual(p.pre.f, m.settings.frequencies);
            tc.verifyEqual(p.pre.calibration, tc.cal.version);
            tc.verifyTrue(p.pre.integrityOk);
            tc.verifyNotEmpty(p.pre.timestamp);
            tc.verifyEqual(p.termination, s.Termination);
            tc.verifyEqual(m.metadata.equalizer.stepVpp, p.vpp);
            tc.verifyEqual(m.metadata.equalizer.nAtMaximum, 0);
            tc.verifyNotEmpty(jsonencode(m.metadata.equalizer));
            log = strjoin(s.LogLines, newline);
            tc.verifyNumElements(strfind(log, 'pre-measurement of the 8 steps'), 1, 'one pre-measurement');
            tc.verifySubstring(log, 'Equalizer plan: 8 steps between');
            tc.verifyEmpty(s.EqualizerPlan, 'the plan was consumed');
            % results.csv
            d = tc.subfolder('csvIncident');
            tim.app.exportCsv(r, d);
            T = readtable(fullfile(d, 'results.csv'));
            tc.verifyEqual(T.eqVoltage_Vpk, p.vpp(:) / 2, 'AbsTol', 1e-9);
            tc.verifyEqual(T.eqTarget, repmat(77, 8, 1));
            tc.verifyEqual(logical(T.eqReached), q.reached);
        end

        function reachesTheTargetFaceVelocity(tc)
            % particle velocity at the front face [mm/s]: a target between the
            % velocities of the virtual tube at the minimum and at the maximum
            % level, so that every step can reach it
            [s, c] = tc.session('faceVelocity', 1);
            freqs = tim.app.steppedPlan(c.excitation.stepped).freqs;
            t = s.Rig.trueResponse(freqs(:));
            u0 = 1e3 * abs(t.model.uL .* t.incidentPerVolt) * 0.1 / sqrt(2);   % mm/s rms at 0.2 Vpp
            tc.assertLessThan(max(u0) / min(u0), 9, 'the face velocity of the virtual tube varies by less than 19 dB');
            target = sqrt(min(u0) * 0.1 * max(u0));
            ex = s.Cfg.excitation; ex.stepped.equalizer.target = target;
            s.setExcitation(ex); c.excitation = ex;
            m = s.measure('stepped');
            r = tim.app.processMeasurement(m, c, tc.cal);
            p = m.equalizer; q = r.equalizer;
            tc.verifyEqual(q.unit, 'mm/s');
            tc.verifyTrue(all(q.reached), q.text);
            tc.verifyLessThan(max(abs(q.deviation_dB)), 0.3);
            tc.verifyTrue(all(strcmp(p.limited, '')));
            tc.verifyEqual(q.achieved, r.levels.faceVelocity_mm_s);
            tc.verifyEqual(max(p.vpp) / min(p.vpp), max(u0) / min(u0), 'RelTol', 0.1, 'the levels follow the face velocity');
            tc.verifyLessThanOrEqual(p.vpp, 0.2);
        end

        function cappedStepsReportedNotMasked(tc)
            % a loudspeaker high-pass at 400 Hz: the two lowest steps cannot reach
            % 80 dB SPL at 0.2 Vpp (about 71 and 77 dB SPL there); they are played
            % at the maximum and reported, never masked (owner decision 2026-11-04)
            [s, c] = tc.session('incidentPressure', 80, @(c) speakerHighPass(c, 400));
            m = s.measure('stepped');
            r = tim.app.processMeasurement(m, c, tc.cal);
            p = m.equalizer; q = r.equalizer;
            capped = strcmp(p.limited, 'max');
            tc.verifyEqual(capped, [true true false(1, 6)], 'the two lowest steps need more than the maximum');
            tc.verifyEqual(p.vpp(capped), [0.2 0.2]);
            tc.verifyLessThanOrEqual(p.vpp, 0.2);
            tc.verifyEqual(q.reached.', ~capped, 'not reached at the capped steps only');
            tc.verifyLessThan(q.deviation_dB(capped), -1);
            tc.verifyEqual(q.limited(capped), {'max'; 'max'});
            tc.verifySubstring(q.text, 'target reached at 6 of 8 steps; not reached at 200, 307 Hz (2 of them at the maximum)');
            tc.verifySubstring(strjoin(s.LogLines, newline), '2 at the maximum, the target not reachable there (200, 307 Hz)');
            tc.verifyEqual(m.metadata.equalizer.nAtMaximum, 2);
            % report only: no validity flag, the validity the same as without the equalizer
            tc.verifyFalse(any(contains(fieldnames(r.analysis.valid.flags), {'target', 'equal', 'reach'}, 'IgnoreCase', true)));
            r0 = tim.app.processMeasurement(rmfield(m, 'equalizer'), c, tc.cal);
            tc.verifyFalse(isfield(r0, 'equalizer'));
            tc.verifyEqual(r.analysis.valid.valid, r0.analysis.valid.valid, 'the equalizer masks nothing');
            tc.verifyTrue(any(r.analysis.valid.validR(capped)), 'a capped step is still a valid line');
            d = tc.subfolder('csvCapped');
            tim.app.exportCsv(r, d);
            T = readtable(fullfile(d, 'results.csv'));
            tc.verifyEqual(logical(T.eqReached).', ~capped);
            tc.verifyEqual(T.eqVoltage_Vpk(capped), [0.1; 0.1]);
        end

        function sourceWithoutLevelChangeRefused(tc)
            % owner decision 2026-11-04: a signal source without levelWhileOn (the
            % demo source) refuses the equalizer with a clear error before anything
            % is configured or armed
            c = tc.cfg;
            c.generator.driver = 'demo';
            c.excitation.stepped.equalizer.mode = 'incidentPressure';
            s = tim.app.MeasurementSession(c);
            tc.addTeardown(@() s.close());
            s.connect(); s.prepareAcquisition();
            s.Calibration = tc.cal;
            h = tim.instr.DemoSource.testHooks(s.Gen);
            n = numel(h.traffic());
            err = [];
            try
                s.measure('stepped');
            catch err
            end
            tc.assertNotEmpty(err, 'refused');
            tc.verifyEqual(err.identifier, 'tim:session:equalizer');
            tc.verifySubstring(err.message, tim.instr.driverInfo('demo').displayName);
            tc.verifySubstring(err.message, 'levelWhileOn');
            tc.verifyError(@() s.measureEqualizerPlan(), 'tim:session:equalizer');
            tc.verifyFalse(s.Gen.OutputArmed, 'never armed');
            tc.verifyFalse(h.outputOn());
            tc.verifyEmpty(h.levelHistory(), 'no level programmed');
            new = h.traffic(); new = new(n + 1:end);
            tc.verifyFalse(any(contains(new, {'VOLT', 'FREQ', 'STAT ON'})), 'nothing configured, never on');
            % the equalizer off: the demo source plays the stepped sine as before
            ex = s.Cfg.excitation; ex.stepped.equalizer.mode = 'off'; ex.stepped.nPoints = 3;
            s.setExcitation(ex);
            m = s.measure('stepped');
            tc.verifyFalse(isfield(m, 'equalizer'));
        end

        function refusedWithoutCalibrationOrGeometry(tc)
            % the levels at the specimen need the calibrated decomposition and the
            % positions of the microphones and of the front face: refused before
            % anything is configured
            [s, c] = tc.session('incidentPressure', 77);
            h = tim.instr.Keysight33220A.testHooks(s.Gen);
            n = numel(h.levelHistory());
            s.Calibration = [];
            tc.verifyError(@() s.measure('stepped'), 'tim:session:equalizer', 'no calibration');
            tc.verifyError(@() s.measureEqualizerPlan(), 'tim:session:equalizer', 'no calibration');
            s.Calibration = tc.cal;
            g = c.geometry; g.xFront = NaN;
            s.setGeometryEnvironment(g, c.environment);
            tc.verifyError(@() s.measure('stepped'), 'tim:session:equalizer', 'no front face');
            g = c.geometry; g.micPositions(2) = NaN;
            s.setGeometryEnvironment(g, c.environment);
            tc.verifyError(@() s.measure('stepped'), 'tim:session:equalizer', 'no microphone position');
            tc.verifyNumElements(h.levelHistory(), n, 'nothing configured');
            tc.verifyFalse(s.Gen.OutputArmed); tc.verifyFalse(h.outputOn());
            % no pre-measurement while the equalizer is off
            s.setGeometryEnvironment(c.geometry, c.environment);
            ex = s.Cfg.excitation; ex.stepped.equalizer.mode = 'off'; s.setExcitation(ex);
            tc.verifyError(@() s.measureEqualizerPlan(), 'tim:session:equalizer', 'the equalizer is off');
        end

        function offPathUnchanged(tc)
            % the equalizer off (the default) plays the stepped sine of 1.5: the
            % same SCPI traffic as a configuration without the setting (the
            % bus-traffic fixtures build excitation.stepped without it), one level
            % command, nothing of the equalizer in the measurement
            c = tc.cfg;
            c.excitation.stepped.nPoints = 4;
            logs = cell(1, 2); ms = cell(1, 2);
            for i = 1:2
                ci = c;
                if i == 2, ci.excitation.stepped = rmfield(ci.excitation.stepped, 'equalizer'); end
                s = tim.app.MeasurementSession(ci);
                tc.addTeardown(@() s.close());
                s.connect(); s.prepareAcquisition();
                s.Calibration = tc.cal;
                h = tim.instr.Keysight33220A.testHooks(s.Gen);
                n0 = numel(h.traffic());
                ms{i} = s.measure('stepped');
                L = h.traffic(); logs{i} = L(n0 + 1:end);
            end
            tc.verifyEqual(logs{1}, logs{2}, 'the same SCPI traffic with the equalizer off as without the setting');
            tc.verifyEqual(nnz(~cellfun(@isempty, regexp(logs{1}, '^> VOLT [0-9]', 'once'))), 1, ...
                'one level command (configureSine)');
            tc.verifyNumElements(find(startsWith(logs{1}, '> FREQ ')), 4, 'one frequency per step');
            m = ms{1};
            tc.verifyFalse(isfield(m, 'equalizer'));
            tc.verifyFalse(isfield(m.settings, 'stepAmplitudeVpp'));
            tc.verifyFalse(isfield(m.metadata, 'equalizer'));
            r = tim.app.processMeasurement(m, c, tc.cal);
            tc.verifyFalse(isfield(r, 'equalizer'));
            d = tc.subfolder('csvOff');
            tim.app.exportCsv(r, d);
            T = readtable(fullfile(d, 'results.csv'));
            tc.verifyFalse(any(startsWith(T.Properties.VariableNames, 'eq')), 'no equalizer columns');
        end

        function planReuseChecked(tc)
            % a plan armed by measureEqualizerPlan is consumed by the next stepped
            % measurement and discarded by another termination; setEqualizerPlan
            % arms a plan again only where it fits (termination, maximum, target,
            % amplifier) - never silently stale
            [s, c] = tc.session('incidentPressure', 80);
            p = s.measureEqualizerPlan();
            tc.verifyEqual(s.EqualizerPlan, p, 'armed');
            tc.verifyFalse(s.Gen.OutputArmed, 'disarmed after the pre-measurement');
            tc.verifyEqual(p.chain.load, 'INF');
            s.setTermination(struct('kind', 'rigid', 'place', 'tubeEnd'));
            tc.verifyEmpty(s.EqualizerPlan, 'another termination discards it');
            tc.verifySubstring(strjoin(s.LogLines, newline), 'Equalizer plan discarded: the termination changed');
            tc.verifyError(@() s.setEqualizerPlan(p), 'tim:session:equalizer', 'measured with another termination');
            s.setTermination(c.measurement.loadA);
            s.setEqualizerPlan(p);
            m = s.measure('stepped');
            tc.verifyEqual(m.equalizer.vpp, p.vpp, 'the armed plan was played');
            tc.verifyEqual(m.settings.stepAmplitudeVpp, p.vpp);
            tc.verifyEmpty(s.EqualizerPlan, 'consumed');
            log = strjoin(s.LogLines, newline);
            tc.verifyNumElements(strfind(log, 'pre-measurement of the 8 steps'), 1, 'no second pre-measurement');
            tc.verifySubstring(log, 'no new pre-measurement');
            % refused where it does not fit; nothing is programmed
            h = tim.instr.Keysight33220A.testHooks(s.Gen);
            n = numel(h.levelHistory());
            ex = s.Cfg.excitation; ex.stepped.amplitudeVpp = 0.1; s.setExcitation(ex);
            tc.verifyError(@() s.setEqualizerPlan(p), 'tim:session:equalizer', 'another maximum');
            ex.stepped.amplitudeVpp = 0.2; ex.stepped.equalizer.target = 78; s.setExcitation(ex);
            tc.verifyError(@() s.setEqualizerPlan(p), 'tim:session:equalizer', 'another target');
            ex.stepped.equalizer.target = 80; s.setExcitation(ex);
            s.setEqualizerPlan(p);
            ex.stepped.nPoints = 7; s.setExcitation(ex);
            tc.verifyEmpty(s.EqualizerPlan, 'another stepped sine discards it');
            tc.verifyError(@() s.setEqualizerPlan(p), 'tim:session:equalizer', 'other steps');
            ex.stepped.nPoints = 8; s.setExcitation(ex);
            s.setEqualizerPlan(p);
            % another calibration (review 2026-11-05): the levels of the plan came
            % from the calibrated decomposition; a refused start consumes the plan
            cal2 = tc.cal; cal2.version = [char(string(tc.cal.version)) '-other'];
            s.Calibration = cal2;
            tc.verifyError(@() s.setEqualizerPlan(p), 'tim:session:equalizer', 'another calibration');
            tc.verifyError(@() s.measure('stepped'), 'tim:session:equalizer', 'the armed plan, another calibration');
            tc.verifyEmpty(s.EqualizerPlan, 'a refused start consumes the plan');
            s.Calibration = tc.cal;
            s.setEqualizerPlan(p);
            s.setAmplifierGain('test amp', 2);
            tc.verifyEmpty(s.EqualizerPlan, 'another amplifier discards it');
            tc.verifyError(@() s.setEqualizerPlan(p), 'tim:session:equalizer', 'another amplifier');
            tc.verifyError(@() s.setEqualizerPlan(struct('vpp', 0.1)), 'tim:session:equalizer', 'not a plan');
            tc.verifyNumElements(h.levelHistory(), n, 'nothing programmed');
            tc.verifyFalse(h.outputOn());
            s.setEqualizerPlan([]);
            tc.verifyEmpty(s.EqualizerPlan);
        end

        function stopDuringPreMeasurement(tc)
            % a Stop while the pre-measurement plays: output off, disarmed, the
            % partial data kept, no plan and no main measurement
            [s, ~] = tc.session('incidentPressure', 77);
            calls = 0;
            function stopLater()
                calls = calls + 1;
                if calls == 12, s.requestStop(); end
            end
            s.BlockCallback = @stopLater;
            tc.verifyError(@() s.measure('stepped'), 'tim:session:stopped');
            s.BlockCallback = [];
            h = tim.instr.Keysight33220A.testHooks(s.Gen);
            tc.verifyFalse(h.outputOn(), 'output off');
            tc.verifyFalse(s.Gen.OutputArmed, 'disarmed');
            log = strjoin(s.LogLines, newline);
            tc.verifySubstring(log, 'pre-measurement of the 8 steps');
            tc.verifyFalse(contains(log, 'Equalizer plan:'), 'no plan, no main measurement');
            tc.verifyEmpty(s.EqualizerPlan);
            tc.verifyNotEmpty(s.LastPartial, 'the partial data of the pre-measurement kept');
            tc.verifyTrue(all(h.levelHistory() <= 0.02 + 1e-12), 'only the pre-measurement level was programmed');
        end

        function stopAfterPreMeasurementKeepsIt(tc)
            % review 2026-11-05: a Stop while the recorded pre-measurement is
            % processed - after its acquisition, before the steps are played -
            % keeps it (LastPartial and an emergency file, with its settings and
            % events) as every other error path keeps its data; no plan is armed
            % and no step is played with the equalizer
            [s, ~] = tc.session('incidentPressure', 77);
            d = fullfile(tim.app.outputDir(s.Cfg, 'data'), 'emergency');    % (tim.app.saveEmergency)
            n0 = numel(dir(fullfile(d, 'partial_*.mat')));
            nPre = 0;                     % pre-measurements logged before the call
            function k = preCount()
                k = numel(strfind(strjoin(s.LogLines, newline), 'pre-measurement of the 8 steps'));
            end
            function stopWhenRecorded()
                % a new pre-measurement was started and its acquisition ended (the
                % output is disarmed then): the Stop arrives while it is processed
                if ~s.Gen.OutputArmed && preCount() > nPre
                    s.requestStop();
                end
            end
            s.BlockCallback = @stopWhenRecorded;
            tc.verifyError(@() s.measure('stepped'), 'tim:session:stopped');
            s.BlockCallback = [];
            p = s.LastPartial;
            tc.assertNotEmpty(p, 'the pre-measurement kept');
            tc.verifyEqual(p.what, 'stepped sine (equalizer pre-measurement)');
            tc.verifyEqual(p.error, 'Measurement stopped by user.');
            tc.verifyNumElements(p.records, 1, 'its repetition');
            tc.verifyNumElements(p.events, 1);
            tc.verifyEqual(p.settings.stepAmplitudeVpp, repmat(0.02, 1, 8), 'AbsTol', 1e-12, 'played at -20 dB');
            tc.verifyNumElements(dir(fullfile(d, 'partial_*.mat')), n0 + 1, 'one emergency file');
            log = strjoin(s.LogLines, newline);
            tc.verifySubstring(log, 'Error after the equalizer pre-measurement: Measurement stopped by user');
            tc.verifyFalse(contains(log, 'Equalizer plan:'), 'no plan');
            tc.verifyEmpty(s.EqualizerPlan);
            h = tim.instr.Keysight33220A.testHooks(s.Gen);
            tc.verifyTrue(all(h.levelHistory() <= 0.02 + 1e-12), 'no step played with the equalizer');
            tc.verifyFalse(h.outputOn()); tc.verifyFalse(s.Gen.OutputArmed);
            % measureEqualizerPlan: the same, and no plan armed
            nPre = preCount();
            s.BlockCallback = @stopWhenRecorded;
            tc.verifyError(@() s.measureEqualizerPlan(), 'tim:session:stopped');
            s.BlockCallback = [];
            tc.verifyEqual(preCount(), nPre + 1, 'stopped after its pre-measurement');
            tc.verifyEmpty(s.EqualizerPlan, 'a Stop while it was processed arms no plan');
            tc.verifyNumElements(dir(fullfile(d, 'partial_*.mat')), n0 + 2, 'kept as well');
        end

        function twoLoadStopLeavesNoPlan(tc)
            % review 2026-11-05: a Stop right after the pre-measurement of load A,
            % before load A is measured, must not leave its plan armed - the next
            % stepped start (with load A still mounted) measures a new one
            [s, c] = tc.session('incidentPressure', 77);
            function note(q)
                if strcmp(q.kind, 'pre') && strcmp(q.state, 'done'), s.requestStop(); end
            end
            tc.verifyError(@() tim.app.runTwoLoad(s, struct('cfg', c, 'save', false, 'report', @note, ...
                'prompt', @(varargin) [])), 'tim:session:stopped');
            tc.verifyEmpty(s.EqualizerPlan, 'the plan of load A disarmed');
            dA = tim.app.describeLoad(c.measurement.loadA, c);
            tc.verifyEqual(s.Termination, struct('kind', dA.kind, 'place', dA.place), 'load A still mounted');
            m = s.measure('stepped');
            log = strjoin(s.LogLines, newline);
            tc.verifyNumElements(strfind(log, 'pre-measurement of the 8 steps'), 2, 'a new pre-measurement');
            tc.verifyFalse(contains(log, 'no new pre-measurement'));
            tc.verifyEqual(m.equalizer.reusedFrom, '');
        end

        function combinedDeviceEqualized(tc)
            % the simulated combined device (shared clock, planned output):
            % setAmplitude is scheduled in the planning pass with the frequency,
            % so every step plays its own level from its first sample
            c = tc.cfg;
            c.generator.driver = 'simcombined'; c.daq.driver = 'simcombined';
            sens = [11.2 11.5 10.9 11.3] * 1e-3;      % the virtual microphones; no TEDS: certificate values
            for i = 1:4, c.mics(i).certificateSensitivity_VperPa = sens(c.mics(i).channel); end
            c.excitation.stepped.equalizer.mode = 'incidentPressure';
            c.excitation.stepped.equalizer.target = 77;
            s = tim.app.MeasurementSession(c);
            tc.addTeardown(@() s.close());
            s.connect(); s.prepareAcquisition();
            s.Calibration = tc.cal;
            m = s.measure('stepped');
            r = tim.app.processMeasurement(m, c, tc.cal);
            p = m.equalizer; q = r.equalizer;
            tc.verifyTrue(all(q.reached), q.text);
            tc.verifyLessThan(max(abs(q.deviation_dB)), 0.3);
            h = tim.sim.SimulatedCombined.testHooks(s.Gen);
            lv = h.levelHistory();
            tc.verifyLessThanOrEqual(lv, 0.2 * (1 + 1e-9), 'no level above the amplitude field');
            tc.verifyTrue(all(ismember(round(p.vpp * 1e7), round(lv * 1e7))), 'every level of the plan was set');
            % the played output: every step at its level, from the planned sample on
            x = h.playedSignal(); ev = m.events{1}; st = m.settings;
            for k = 1:numel(ev.stepStart)
                seg = x(ev.stepStart(k) + (1:st.settleSamples(k)));
                tc.verifyEqual(max(abs(seg)), p.vpp(k) / 2, 'RelTol', 0.01, sprintf('step %d at its level', k));
            end
            tc.verifyFalse(s.Gen.isOutputOn(), 'output off after the measurement');
            tc.verifyEqual(s.Rig.OutputLog(end, 4), 0, 'the output ends at 0 V');
        end

        function twoLoadPreMeasurementPerLoad(tc)
            % owner decision 2026-11-04 (two loads): a pre-measurement after every
            % change of termination (A, B) as its own step, load A again with the
            % voltages of load A, the B level ignored while the equalizer is on
            [s, c] = tc.session('incidentPressure', 77);
            cc = c; cc.measurement.loadBLevel_dB = -6;
            steps = {};
            function note(q)
                if strcmp(q.kind, 'pre'), steps{end + 1} = sprintf('pre %s %s', q.role, q.state);
                else, steps{end + 1} = q.kind; end
            end
            out = tim.app.runTwoLoad(s, struct('cfg', cc, 'save', false, 'report', @note, 'prompt', @(varargin) []));
            tc.verifyEqual(steps, {'pre A start', 'pre A done', 'load', 'pre B start', 'pre B done', 'load', 'load', ...
                'result'});
            L = out.loads;
            tc.verifyEqual({L.role}, {'A', 'B', 'A2'});
            tc.verifyEqual(L(3).meas.equalizer.vpp, L(1).meas.equalizer.vpp, 'load A again with the voltages of load A');
            tc.verifyEqual(L(3).meas.equalizer.reusedFrom, 'A');
            tc.verifyEqual(L(3).meas.metadata.equalizer.reusedFrom, 'A');
            tc.verifyEqual(L(1).meas.equalizer.reusedFrom, '');
            tc.verifyNotEqual(L(2).meas.equalizer.created, L(1).meas.equalizer.created, 'load B has its own plan');
            tc.verifyEqual(L(2).meas.equalizer.termination, struct('kind', 'rigid', 'place', 'tubeEnd'));
            tc.verifyEqual(L(2).meas.settings.amplitudeVpp, L(1).meas.settings.amplitudeVpp, 'the B level ignored');
            for i = 1:3
                tc.verifyTrue(all(L(i).res.equalizer.reached), sprintf('load %s: %s', L(i).role, L(i).res.equalizer.text));
            end
            log = strjoin(s.LogLines, newline);
            tc.verifySubstring(log, 'Load B level (measurement.loadBLevel_dB = -6 dB) ignored');
            tc.verifyNumElements(strfind(log, 'pre-measurement of the 8 steps'), 2, 'loads A and B only');
            tc.verifySubstring(log, 'Load A again with the voltages of load A (no new pre-measurement)');
            tc.verifyEqual(s.Cfg.excitation, c.excitation, 'the excitation unchanged');
            tc.verifyEmpty(s.EqualizerPlan);
            tc.verifyNotEmpty(out.tl);
        end
    end
end

function c = speakerHighPass(c, fhp)
% the virtual loudspeaker with a high-pass at fhp [Hz] (default 60 Hz)
c.simulation.SpeakerFhp = fhp;
end
