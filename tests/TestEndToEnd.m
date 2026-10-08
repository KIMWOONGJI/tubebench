classdef TestEndToEnd < matlab.unittest.TestCase
    %TESTENDTOEND Complete simulated workflow through the mock instruments.
    %
    %   Tolerance rationale (simulated noise 2 mPa vs ~0.4 Pa incident, SNR
    %   per analysis band > 40 dB): relative response error dH ~ 0.3 %.
    %   First-order propagation |dR| <= 2*sqrt(2)*cond*dH*(1+|R|) gives
    %   ~0.03 for cond ~ 3 (f > 1 kHz) and up to ~0.3 at 120 Hz (cond ~ 31).
    %   Hence: f > 1 kHz -> max |dR| < 0.03; whole valid band -> median < 0.01.

    properties
        cfg
        tmp
    end

    methods (TestMethodSetup)
        function setup(tc)
            f = tc.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            tc.tmp = f.Folder;
            c = tim.app.defaultConfig();
            c.geometry = c.simulation.Geometry;            % simulated "measured" geometry
            c.output.dataDir = fullfile(tc.tmp, 'data');
            c.output.calibrationDir = fullfile(tc.tmp, 'cal');
            c.excitation.sweep.duration = 3;
            c.excitation.sweep.repetitions = 2;
            c.calibration.repeatConfigI = false;
            tc.cfg = c;
        end
    end

    methods
        function [s, cal] = calibratedSession(tc, c)
            if nargin < 2, c = tc.cfg; end
            s = tim.app.MeasurementSession(c);
            s.connect(); s.prepareAcquisition();
            cal = tim.app.runCalibration(s);
        end
    end

    methods (Test)
        function fullSweepWorkflow(tc)
            [s, cal] = tc.calibratedSession();
            cleanup = onCleanup(@() s.close());
            % calibration recovers the true chain mismatch (Test C, synthetic)
            Ct = s.Rig.chainResponse(cal.f); Ct = Ct ./ Ct(:, 1);
            ok = all(cal.valid, 2);
            tc.verifyGreaterThan(nnz(ok), 0.9 * numel(ok));
            tc.verifyLessThan(prctile(abs(cal.C(ok, :) ./ Ct(ok, :) - 1), 95, 'all'), 5e-3);

            meas = s.measure('sweep');
            tc.verifyTrue(meas.integrityOk);
            tc.verifyFalse(s.Gen.isOutputOn(), 'output must be off after the measurement');
            res = tim.app.processMeasurement(meas, tc.cfg, cal);
            a = res.analysis; v = a.valid.valid;
            tc.verifyGreaterThan(nnz(v), 0.5 * numel(v));
            truth = s.Rig.trueResponse(a.f).model;
            dR = abs(a.R - truth.R); dT = abs(a.tau - truth.tau);
            hi = v & a.f > 1000;
            tc.verifyLessThan(max(dR(hi)), 0.03);
            tc.verifyLessThan(max(dT(hi)), 0.03);
            tc.verifyLessThan(median(dR(v)), 0.01);
            tc.verifyLessThan(median(dT(v)), 0.01);
            % thick porous sample -> thin-element Zt must be flagged invalid
            tc.verifyLessThan(nnz(a.valid.validThinZt), 0.2 * nnz(v));
            % without calibration nothing is valid
            res0 = tim.app.processMeasurement(meas, tc.cfg, []);
            tc.verifyFalse(any(res0.analysis.valid.valid));

            % storage: two saves -> two folders, nothing overwritten
            figs = tim.app.plotResults(res, meas, struct('Visible', 'off'));
            tc.verifyNotEmpty(findobj(figs.validity, 'Type', 'image'), 'sweep: dense validity image unchanged');
            tc.verifyFalse(isfield(res, 'toneLevels'));
            d1 = tim.app.saveMeasurement(meas, res, tc.cfg, 'porous', figs);
            d2 = tim.app.saveMeasurement(meas, res, tc.cfg, 'porous', []);
            fc = struct2cell(figs); close(fc{:});
            tc.verifyNotEqual(d1, d2);
            for fn = {'raw.mat', 'result.mat', 'config.json', 'metadata.json', 'results.csv', 'spectra.csv', ...
                    'fig_reflection.png', 'fig_reflection.pdf'}
                tc.verifyTrue(isfile(fullfile(d1, fn{1})), fn{1});
            end
            S = load(fullfile(d1, 'raw.mat'));
            tc.verifyEqual(S.meas.records, meas.records);
            tc.verifyEqual(S.meas.metadata.daq.firmware, '2.10.0.610');
            % traceability: repository and commit of the code that produced the data
            md = jsondecode(tim.app.readTextUtf8(fullfile(d1, 'metadata.json')));
            tc.verifyEqual(md.softwareInfo.repository, tim.app.repositoryUrl());
            tc.verifyTrue(strcmp(md.softwareInfo.commit, 'unknown') || ~isempty(regexp(md.softwareInfo.commit, '^[0-9a-f]{40}$', 'once')));
            tc.verifySubstring(tim.app.readTextUtf8(fullfile(d1, 'README.txt')), ['Source: ' tim.app.repositoryUrl()]);
            T = readtable(fullfile(d1, 'results.csv'));
            tc.verifyEqual(height(T), numel(a.f));
            clear cleanup
        end

        function thinElementTransferImpedance(tc)
            c = tc.cfg;
            c.simulation.Sample = struct('type', 'thin', 'Zt', 300);       % resistive screen
            c.simulation.Geometry.xRear = 0; c.geometry.xRear = 0;
            c.simulation.Termination = struct('R', 0, 'x', 0.6);
            [s, cal] = tc.calibratedSession(c);
            cleanup = onCleanup(@() s.close());
            res = tim.app.processMeasurement(s.measure('sweep'), c, cal);
            a = res.analysis; ok = a.valid.validThinZt & a.f > 300;
            tc.verifyGreaterThan(nnz(ok), 0.5 * nnz(a.valid.valid));
            % Zt/rho c ~ 0.73; relative error bound as for R -> 5 % above 300 Hz
            tc.verifyLessThan(max(abs(a.thin.Zt(ok) / 300 - 1)), 0.05);
            tc.verifyLessThan(median(abs(a.thin.Zt(ok) / 300 - 1)), 0.01);
            clear cleanup
        end

        function steppedSineAndCrossMethod(tc)
            c = tc.cfg;
            c.excitation.stepped.nPoints = 8;
            c.excitation.stepped.fStart = 200; c.excitation.stepped.fStop = 4000;
            [s, cal] = tc.calibratedSession(c);
            cleanup = onCleanup(@() s.close());
            rs = tim.app.processMeasurement(s.measure('stepped'), c, cal);
            rw = tim.app.processMeasurement(s.measure('sweep'), c, cal);
            fq = rs.analysis.f;
            Rw = interp1(rw.analysis.f, rw.analysis.R, fq);
            tc.verifyLessThan(max(abs(rs.analysis.R - Rw)), 0.03);    % Test G (synthetic)
            truth = s.Rig.trueResponse(fq).model;
            tc.verifyLessThan(max(abs(rs.analysis.R - truth.R)), 0.03);
            clear cleanup
        end

        function steppedScheduleDoesNotDrift(tc)
            % regression: step starts used to accumulate the block overshoot
            % and the last steps ran past the end of the record
            c = tc.cfg;
            c.excitation.stepped = struct('fStart', 200, 'fStop', 4000, 'nPoints', 15, 'spacing', 'log', ...
                'amplitudeVpp', 0.2, 'settleTime', 0.1, 'recordTime', 0.15, 'nBlocks', 2, 'repetitions', 1);
            s = tim.app.MeasurementSession(c);
            cleanup = onCleanup(@() s.close());
            s.connect(); s.prepareAcquisition();
            m = s.measure('stepped');
            ev = m.events{1}; nStep = m.settings.settleSamples + m.settings.recordSamples;
            lag = ev.stepStart - (ev.onSample + (0:14) * nStep);
            tc.verifyGreaterThanOrEqual(min(lag), 0);
            tc.verifyLessThanOrEqual(max(lag), 2048);          % <= one mock block, no accumulation
            for k = 1:15
                tc.verifyNotEmpty(tim.app.steppedSegment(m, 1, k));
            end
            r = tim.app.processMeasurement(m, c, []);
            tc.verifyTrue(all(isfinite(r.spectra.H(:))));
            clear cleanup
        end

        function steppedToneLevelsAndFigures(tc)
            % regression 2026-10-09: stepped spectrum displayed as spikes. Step
            % levels from the sine fit; results only at the step frequencies;
            % CSV columns; saved figures use markers (no imagesc, no PSD comb).
            c = tc.cfg;
            c.excitation.stepped = struct('fStart', 200, 'fStop', 4000, 'nPoints', 8, 'spacing', 'log', ...
                'amplitudeVpp', 0.2, 'settleTime', 0.2, 'recordTime', 0.25, 'nBlocks', 2, 'repetitions', 1);
            s = tim.app.MeasurementSession(c);
            cleanup = onCleanup(@() s.close());
            s.connect(); s.prepareAcquisition();
            m = s.measure('stepped');
            r = tim.app.processMeasurement(m, c, []);
            fk = m.settings.frequencies(:);
            tc.verifyEqual(r.analysis.f, fk, 'no interpolation onto a dense grid');
            tl = r.toneLevels;
            tc.verifyEqual(tl.f, fk);
            tc.verifySize(tl.spl_dB, [8 4]);
            sens = [m.mics.sensitivity_VperPa];
            for k = 1:8
                idx = tim.app.steppedSegment(m, 1, k);
                x = m.records{1}(idx, :); x = x - mean(x, 1);
                lvl = 20 * log10(sqrt(mean(x.^2, 1)) ./ sens / 2e-5);   % noise 2 mPa << tone
                tc.verifyEqual(tl.spl_dB(k, :), lvl, 'AbsTol', 0.2);
            end
            tc.verifyTrue(all(tl.spl_dB - tl.noise_dB > 20, 'all'));
            tim.app.exportCsv(r, tc.tmp);
            S = readtable(fullfile(tc.tmp, 'spectra.csv'));
            tc.verifyEqual(S.level1_dB_SPL, tl.spl_dB(:, 1), 'AbsTol', 1e-6);
            figs = tim.app.plotResults(r, m, struct('Visible', 'off'));
            fc = struct2cell(figs); closeFigs = onCleanup(@() close(fc{:}));
            L = findobj(figs.spectrum, 'Type', 'line', 'Marker', 'o');
            tc.verifyNumElements(L, 4, 'one step-level series per channel');
            tc.verifyEqual(sort(L(1).XData(:)), fk, 'RelTol', 1e-12);
            tc.verifyEmpty(findobj(figs.validity, 'Type', 'image'), 'log-spaced steps not drawn with imagesc');
            clear closeFigs cleanup
        end

        function excitationRequiresOperatorConfirmation(tc)
            s = tim.app.MeasurementSession(tc.cfg);
            cleanup = onCleanup(@() s.close());
            s.connect(); s.prepareAcquisition();
            asked = {};
            s.ExcitationConfirm = @(msg) false;                       % operator says no
            tc.verifyError(@() s.measure('sweep'), 'tim:session:notConfirmed');
            tc.verifyFalse(s.Gen.isOutputOn());
            tc.verifyEmpty(s.Rig.TriggerLog, 'nothing may have been played');
            s.ExcitationConfirm = @(msg) recordYes(msg);
            s.setAmplifier('-20 dB', -20, 'test amp');
            s.measure('sweep'); s.measure('sweep');                    % same settings -> asked once
            tc.verifyNumElements(asked, 1);
            tc.verifyTrue(contains(asked{1}, '-20 dB'));
            s.setAmplifier('-10 dB', -10);                             % gain changed -> asked again
            m = s.measure('sweep');
            tc.verifyNumElements(asked, 2);
            tc.verifyEqual(m.metadata.amplifier.gain_dB, -10, 'AbsTol', 1e-9);
            tc.verifyEqual(m.metadata.amplifier.gainSetting, '-10 dB');
            % multiplier form (GUI): x10 -> message shows the gain and the amplifier output in Vpk
            s.setAmplifierGain('test amp', 10);
            s.measure('sweep');
            tc.verifyNumElements(asked, 3);
            tc.verifyTrue(contains(asked{3}, 'x10') && contains(asked{3}, 'Vpk'));
            % direct drive: gain forced to x1, message shows the 8-ohm current
            s.setAmplifierGain('none (direct drive)', 5);
            tc.verifyEqual(s.Cfg.amplifier.gainFactor, 1);
            s.measure('sweep');
            tc.verifyTrue(contains(asked{4}, 'mA peak'));
            clear cleanup
            function ok = recordYes(msg)
                asked{end+1} = msg; ok = true;
            end
        end

        function stopBetweenCalibrationStepsAborts(tc)
            % regression (GUI test 2026-10-08): a STOP pressed while the operator
            % moves microphones (between two measurements) was cleared by the
            % next measurement and the calibration continued.
            s = tim.app.MeasurementSession(tc.cfg);
            cleanup = onCleanup(@() s.close());
            s.connect(); s.prepareAcquisition();
            nStep = 0;
            function prompt(~, mapping)
                nStep = nStep + 1;
                s.setMicPositionsForSimulation(mapping);
                if nStep == 3, s.requestStop(); end     % operator presses ABORT during step 3
            end
            tc.verifyError(@() tim.app.runCalibration(s, struct('prompt', @prompt)), 'tim:session:stopped');
            tc.verifyLessThanOrEqual(nStep, 3, 'no further step after the abort');
            tc.verifyEqual(s.Rig.Sample.type, tc.cfg.simulation.Sample.type, 'specimen restored after the abort');
            tc.verifyFalse(s.Gen.isOutputOn());
            tc.verifyFalse(s.InOperation);
            tc.verifyEmpty(dir(fullfile(tc.cfg.output.calibrationDir, '*.mat')), 'nothing saved');
            % a later stand-alone measurement works again (flag cleared)
            m = s.measure('sweep');
            tc.verifyTrue(m.integrityOk);
            clear cleanup
        end

        function loudspeakerPowerLimit(tc)
            % drive estimate and refusal above loudspeaker.maxPower_W
            c = tc.cfg;
            c.loudspeaker = struct('impedance_ohm', 8, 'ratedPower_W', 25, 'maxPower_W', 0.05);
            d = tim.app.driveEstimate(setfield(c, 'amplifier', struct('model', 'none (direct drive)', ...
                'gainFactor', NaN, 'gain_dB', NaN)), 2.0); %#ok<SFLD>
            tc.verifyEqual(d.Vspk_pk, 1 * 8 / 58, 'RelTol', 1e-12);            % 50-ohm source divider
            tc.verifyEqual(d.P_W, (8 / 58)^2 / 16, 'RelTol', 1e-12);
            s = tim.app.MeasurementSession(c);
            cleanup = onCleanup(@() s.close());
            s.connect(); s.prepareAcquisition();
            s.setAmplifierGain('test amp', 10);                 % 0.1 Vpk x 10 = 1 Vpk -> 62.5 mW > 50 mW
            tc.verifyError(@() s.measure('sweep'), 'tim:session:speakerPower');
            tc.verifyFalse(s.Gen.isOutputOn());
            tc.verifyEmpty(s.Rig.TriggerLog, 'nothing may have been played');
            s.setAmplifierGain('test amp', 5);                  % 0.5 Vpk -> 15.6 mW: allowed
            m = s.measure('sweep');
            tc.verifyTrue(m.integrityOk);
            clear cleanup
        end

        function noiseExcitation(tc)
            c = tc.cfg; c.excitation.noise.duration = 15; c.excitation.noise.amplitudeVpp = 0.4;
            [s, cal] = tc.calibratedSession(c);
            cleanup = onCleanup(@() s.close());
            r = tim.app.processMeasurement(s.measure('noise'), c, cal);
            a = r.analysis; truth = s.Rig.trueResponse(a.f).model;
            hi = a.valid.valid & a.f > 500;
            tc.verifyGreaterThan(nnz(hi), 100);
            tc.verifyLessThan(median(abs(a.R(hi) - truth.R(hi))), 0.02);
            clear cleanup
        end

        function failureIsSafeAndPreservesData(tc)
            s = tim.app.MeasurementSession(tc.cfg);
            cleanup = onCleanup(@() s.close());
            s.connect(); s.prepareAcquisition();
            s.Http.StreamOptions = struct('StopAfterSamples', 40000);   % stream dies mid-sweep
            tc.verifyError(@() s.measure('sweep'), 'tim:lanxi:streamStalled');
            tc.verifyFalse(s.Gen.isOutputOn(), 'output must be switched off after an error');
            tc.verifyFalse(s.Gen.OutputArmed);
            tc.verifyNotEmpty(s.LastPartial);
            tc.verifyGreaterThanOrEqual(size(s.LastPartial.records{end}, 1), 40000 - 2048);
            em = dir(fullfile(tc.cfg.output.dataDir, 'emergency', '*.mat'));
            tc.verifyNumElements(em, 1);
            clear cleanup
        end

        function incompleteGeometryStillMeasures(tc)
            c = tc.cfg;
            c.geometry = tim.app.defaultConfig().geometry;   % positions unknown (as in the lab today)
            s = tim.app.MeasurementSession(c);
            cleanup = onCleanup(@() s.close());
            s.connect(); s.prepareAcquisition();
            r = tim.app.processMeasurement(s.measure('sweep'), c, []);
            tc.verifyFalse(r.analysis.boundary.available);
            tc.verifyTrue(all(isnan(r.analysis.thin.Zt)));
            tc.verifyTrue(all(isfinite(r.analysis.local.R_up_atM2)));
            tc.verifyTrue(all(isfinite(r.spectra.H(:))));
            clear cleanup
        end

        function configRoundTrip(tc)
            f = fullfile(tc.tmp, 'c.json');
            c = tc.cfg; c.geometry.micPositions = [NaN NaN NaN NaN];
            tim.app.saveConfig(c, f);
            c2 = tim.app.loadConfig(f);
            tc.verifyTrue(all(isnan(c2.geometry.micPositions)));
            tc.verifyEqual(size(c2.geometry.micPositions), [1 4]);
            tc.verifyEqual(c2.mics(3).position, 3);
            tc.verifyEqual(c2.acquisition.ccld, true(1, 4));
            tc.verifyEqual(c2.output.figureFormats, {'png', 'pdf'});
            bad = c; bad.excitation.sweep.amplitudeVpp = 5;
            tc.verifyError(@() tim.app.MeasurementSession(bad), 'tim:config:amplitude');
        end

        function connectionChecklistAndCalibrationReport(tc)
            % progress of every connection step (GUI checklist), signal check
            % without excitation, quality report of every calibration step
            s = tim.app.MeasurementSession(tc.cfg);
            cleanup = onCleanup(@() s.close());
            ev = cell(0, 3);
            function record(k, st, d)
                ev(end + 1, :) = {k, st, d};
            end
            s.ProgressCallback = @record;
            s.connect(); s.prepareAcquisition();
            chk = s.signalCheck(0.5);
            keys = {'gen', 'lanxi', 'idle', 'open', 'teds', 'setup', 'sens', 'settle', 'signal'};
            [~, first] = unique(ev(:, 1), 'stable');
            tc.verifyEqual(ev(first, 1).', keys, 'steps reported in checklist order');
            for k = keys
                rows = ev(strcmp(ev(:, 1), k{1}), :);
                final = rows{end, 2};
                tc.verifyTrue(any(strcmp(final, {'ok', 'skip'})), sprintf('%s ended "%s"', k{1}, final));
                if ~strcmp(final, 'skip'), tc.verifyEqual(rows{1, 2}, 'run', k{1}); end
            end
            tc.verifyEqual([chk.channel], 1:4);
            tc.verifyTrue(all(strcmp({chk.state}, 'ok')));
            tc.verifyTrue(all(isfinite([chk.spl_dB])));
            tc.verifyFalse(s.Gen.isOutputOn(), 'the signal check never drives the loudspeaker');
            % calibration: one report per measurement and one per channel
            q = {};
            function addq(r)
                q{end + 1} = r;
            end
            tim.app.runCalibration(s, struct('report', @addq));
            kinds = cellfun(@(r) r.kind, q, 'UniformOutput', false);
            tc.verifyEqual(nnz(strcmp(kinds, 'measurement')), 6);     % 3 channels x (I, II)
            tc.verifyEqual(nnz(strcmp(kinds, 'channel')), 3);
            tc.verifyEqual(nnz(strcmp(kinds, 'verification')), 1);
            vq = q{strcmp(kinds, 'verification')};
            tc.verifyTrue(vq.check.passed, vq.check.text);
            m = [q{strcmp(kinds, 'measurement')}];
            tc.verifyGreaterThan(min([m.fracOk]), 0.9);
            tc.verifyTrue(all([m.integrityOk]));
            clear cleanup
        end

        function calibrationUsesEmptySection(tc)
            % user request 2026-10-09: calibrate with the original 75 mm section
            % mounted EMPTY (tube continuous, same port positions); the geometry
            % (d = 75 mm) must be reflected in the calibration record and checks.
            c = tc.cfg;
            g = struct('diameter', 0.029, 'micPositions', [-0.070 -0.041 0.116 0.145], ...
                'spacingUp', 0.029, 'spacingDown', 0.029, 'xFront', 0, 'xRear', 0.075, 'note', 'lab');
            c.geometry = g; c.simulation.Geometry = rmfield(g, 'note');
            c.simulation.Sample = struct('type', 'porous', 'sigma', 1e4);
            c.simulation.Termination = struct('R', 0.05, 'x', 0.436);
            s = tim.app.MeasurementSession(c);
            cleanup = onCleanup(@() s.close());
            s.connect(); s.prepareAcquisition();
            types = {}; msgs = {};
            function prompt(msg, mapping)
                types{end + 1} = s.Rig.Sample.type; msgs{end + 1} = msg;
                s.setMicPositionsForSimulation(mapping);
            end
            [cal, file] = tim.app.runCalibration(s, struct('prompt', @prompt));
            tc.verifyTrue(all(strcmp(types(1:end - 1), 'air')), 'empty section during the calibration steps');
            tc.verifyEqual(types{end}, 'porous', 'specimen mounted again before the last prompt');
            tc.verifyEqual(s.Rig.Sample.type, 'porous');
            tc.verifyEqual(msgs{end}, tim.app.msg('en', 'calMountSpecimen'));
            tc.verifySubstring(msgs{1}, 'EMPTY specimen section (75 mm)');
            tc.verifyEqual(cal.meta.tube.specimenSection, 'empty');
            tc.verifyEqual(cal.meta.tube.sectionLength_m, 0.075, 'AbsTol', 1e-12);
            tc.verifyTrue(cal.meta.emptyCheck.performed);
            tc.verifyTrue(cal.meta.emptyCheck.passed, cal.meta.emptyCheck.text);
            tc.verifyEqual(cal.meta.emptyCheck.gap_m, 0.075, 'AbsTol', 1e-12);
            S = load(file, 'cal');
            tc.verifyEqual(S.cal.meta.tube.sectionLength_m, 0.075, 'AbsTol', 1e-12);
            % measurement with the 75 mm specimen
            res = tim.app.processMeasurement(s.measure('sweep'), c, cal);
            tc.verifyTrue(res.calibration.context.geometryMatch);
            tc.verifyEmpty(res.calibration.context.warnings);
            a = res.analysis; v = a.valid.valid;
            truth = s.Rig.trueResponse(a.f).model;
            tc.verifyLessThan(median(abs(a.R(v) - truth.R(v))), 0.01);
            tc.verifyLessThan(median(abs(a.tau(v) - truth.tau(v))), 0.01);
            tc.verifyLessThan(nnz(a.valid.validThinZt), 0.02 * numel(a.f), 'thin model not for 75 mm');
            clear cleanup
        end

        function emptyCheckDetectsRemovedSection(tc)
            % if the section were taken out and the tubes joined, M3/M4 move 75 mm:
            % the empty-section check (Test E) must fail with the 75 mm geometry
            c = tc.cfg;
            g = struct('diameter', 0.029, 'micPositions', [-0.070 -0.041 0.116 0.145], ...
                'spacingUp', 0.029, 'spacingDown', 0.029, 'xFront', 0, 'xRear', 0.075, 'note', 'lab');
            c.geometry = g;
            sg = rmfield(g, 'note'); sg.micPositions(3:4) = [0.041 0.070]; sg.xRear = 0;
            c.simulation.Geometry = sg;
            c.simulation.Termination = struct('R', 0.05, 'x', 0.436);
            s = tim.app.MeasurementSession(c);
            cleanup = onCleanup(@() s.close());
            s.connect(); s.prepareAcquisition();
            cal = tim.app.runCalibration(s);
            tc.verifyTrue(cal.meta.emptyCheck.performed);
            tc.verifyFalse(cal.meta.emptyCheck.passed, cal.meta.emptyCheck.text);
            tc.verifyGreaterThan(cal.meta.emptyCheck.tauPhaseError_deg_rms, 10);
            clear cleanup
        end

        function stopBeforeMeasurementIsKept(tc)
            % review 2026-10-09: a STOP / window close between the START click and
            % the first measurement was cleared by requirePrepared -> sweep played
            s = tim.app.MeasurementSession(tc.cfg);
            cleanup = onCleanup(@() s.close());
            s.connect(); s.prepareAcquisition();
            s.beginOperation();                 % what the GUI does when START is clicked
            s.requestStop();                    % STOP / close processed before measure()
            tc.verifyError(@() s.measure('sweep'), 'tim:session:stopped');
            tc.verifyFalse(s.Gen.isOutputOn());
            s.endOperation();
            m = s.measure('sweep');             % a new stand-alone measurement works again
            tc.verifyTrue(m.integrityOk);
            % nested operations: only the outermost clears the stop flag
            s.beginOperation(); s.requestStop(); s.beginOperation();
            tc.verifyTrue(s.StopRequested, 'inner beginOperation keeps a pending STOP');
            s.endOperation(); tc.verifyTrue(s.InOperation); s.endOperation(); tc.verifyFalse(s.InOperation);
            clear cleanup
        end

        function stopDuringEmptyCheckKeepsCalibration(tc)
            % review 2026-10-09: STOP or an error during the automatic Test E lost
            % the whole (already measured) calibration
            s = tim.app.MeasurementSession(tc.cfg);
            cleanup = onCleanup(@() s.close());
            s.connect(); s.prepareAcquisition();
            done = tim.app.msg('en', 'calDone');
            function prompt(msg, mapping)
                s.setMicPositionsForSimulation(mapping);
                if strcmp(msg, done), s.requestStop(); end    % ABORT while the check sweep starts
            end
            [cal, file] = tim.app.runCalibration(s, struct('prompt', @prompt));
            tc.verifyTrue(isfile(file), 'calibration saved');
            tc.verifyFalse(cal.meta.emptyCheck.performed);
            tc.verifySubstring(cal.meta.emptyCheck.text, 'aborted');
            S = load(file, 'cal');
            tc.verifyEqual(S.cal.C, cal.C);
            tc.verifySubstring(S.cal.meta.emptyCheck.text, 'aborted', 'saved file holds the final check result');
            tc.verifyEqual(s.Calibration.version, cal.version, 'new calibration active');
            tc.verifyFalse(s.Gen.isOutputOn());
            clear cleanup
        end

        function noEmptyCheckPromptWhenDisabled(tc)
            % the operator is not promised a check sweep that does not follow
            c = tc.cfg; c.calibration.verifyEmptySection = false;
            s = tim.app.MeasurementSession(c);
            cleanup = onCleanup(@() s.close());
            s.connect(); s.prepareAcquisition();
            msgs = {};
            function prompt(msg, mapping)
                msgs{end + 1} = msg; s.setMicPositionsForSimulation(mapping);
            end
            cal = tim.app.runCalibration(s, struct('prompt', @prompt));
            tc.verifyTrue(any(contains(msgs, 'No empty-tube check will be made (disabled')));
            tc.verifyFalse(any(strcmp(msgs, tim.app.msg('en', 'calDone'))));
            tc.verifySubstring(cal.meta.emptyCheck.text, 'disabled');
            tc.verifyEqual(cal.meta.tube.sectionLength_m, c.tubeDrawing.specimenSectionLength);
            tc.verifyEqual(cal.meta.tube.specimenThickness_m, c.geometry.xRear - c.geometry.xFront, 'AbsTol', 1e-12);
            tc.verifyEqual(cal.meta.softwareInfo.repository, tim.app.repositoryUrl());
            clear cleanup
        end

        function connectionFailureMarksStep(tc)
            % an error inside a step marks exactly that step as failed
            c = tc.cfg; c.acquisition.filter = 'no such filter';
            s = tim.app.MeasurementSession(c);
            cleanup = onCleanup(@() s.close());
            ev = cell(0, 3);
            function record(k, st, d)
                ev(end + 1, :) = {k, st, d};
            end
            s.ProgressCallback = @record;
            s.connect();
            tc.verifyError(@() s.prepareAcquisition(), 'tim:lanxi:filter');
            failed = ev(strcmp(ev(:, 2), 'fail'), :);
            tc.verifyEqual(size(failed, 1), 1);
            tc.verifyEqual(failed{1, 1}, 'setup');
            tc.verifySubstring(failed{1, 3}, 'no such filter');
            clear cleanup
        end
    end
end
