classdef TestTwoLoad < matlab.unittest.TestCase
    %TESTTWOLOAD Two-load transfer matrix of WO-005 (1.4.0): the analysis
    %   against the analytic tube model (noise-free: round-off tolerances), the
    %   termination loads, the pair checks, the repeat of load A, and the loads
    %   in the simulated session.

    properties
        env = struct('temperature_C', 20, 'pressure_Pa', 101325, 'relativeHumidity', 50, ...
            'c_override', [], 'rho_override', [])
        f = (150:10:4500).'
        geom
        porous = struct('type', 'porous', 'sigma', 1.5e4)
    end

    methods (TestMethodSetup)
        function setup(tc)
            % the lab tube with its 75 mm specimen section (CAD values)
            tc.geom = struct('diameter', 0.029, 'micPositions', [-0.070 -0.041 0.116 0.145], ...
                'spacingUp', 0.029, 'spacingDown', 0.029, 'xFront', 0, 'xRear', 0.075);
        end
    end

    methods
        function [res, m] = load(tc, sample, termination, varargin)
            % one noise-free load, processed like a measurement (calibrated, 'sweep')
            o = struct('version', 'CAL-TEST', 'scale', 1, 'geom', tc.geom, 'time', '2026-10-14 10:00:00.000');
            for i = 1:2:numel(varargin), o.(varargin{i}) = varargin{i + 1}; end
            m = tim.sim.tubeModel(tc.f, o.geom, tc.env, sample, termination);
            a = tim.acoustics.analyzeFourMic(tc.f, o.scale * m.p, o.geom, tc.env, ...
                struct('calValid', true(size(tc.f)), 'fRange', [tc.f(1) tc.f(end)]));
            res = struct('kind', 'sweep', 'timestamp', o.time, 'calibration', struct('version', o.version), ...
                'channelOfPosition', 1:4, 'analysis', a);
        end

        function L = loads(~, roles, ress, terms)
            L = struct('role', roles, 'res', ress, 'load', terms, 'meas', [], 'cfg', [], 'folder', '');
        end
    end

    methods (Test)
        function condQDoesNotDependOnTheScaleOfALoad(tc)
            % decision 6: the columns of Q are scaled to unit length - the level and
            % the reference microphone of a load must not change condQ (nor T)
            rA = tc.load(tc.porous, struct('R', 0.05, 'x', 0.436));
            rB = tc.load(tc.porous, struct('R', 1, 'x', 0.436));
            rBs = tc.load(tc.porous, struct('R', 1, 'x', 0.436), 'scale', 1e3 * exp(0.7j));
            t1 = tim.acoustics.transferMatrix('twoLoad', rA.analysis, rB.analysis);
            t2 = tim.acoustics.transferMatrix('twoLoad', rA.analysis, rBs.analysis);
            tc.verifyEqual(t2.condQ, t1.condQ, 'RelTol', 1e-9);
            tc.verifyEqual(t2.T12, t1.T12, 'RelTol', 1e-9);
            tc.verifyGreaterThanOrEqual(min(t1.condQ), 1 - 1e-12);
        end

        function rigidAndOpenAtOnePlaceAreNearlyOrthogonal(tc)
            % section 2 of the work order: R = +1 and R ~ -1 at the same plane
            rig = tc.load(tc.porous, struct('R', 1, 'x', 0.436));
            opn = tc.load(tc.porous, struct('R', -1, 'x', 0.436, 'model', 'unflangedOpenEnd'));
            t = tim.acoustics.transferMatrix('twoLoad', rig.analysis, opn.analysis);
            tc.verifyLessThan(max(t.condQ(tc.f < 500)), 1.12);   % end correction: 2k(0.6133a) = 0.16 rad at 500 Hz
            tc.verifyLessThan(max(t.condQ), 3);
            % the open-end model: |R| = exp(-(ka)^2/2), a reflection 0.6133 a beyond the end
            m = tim.sim.tubeModel(tc.f, tc.geom, tc.env, tc.porous, struct('R', -1, 'x', 0.436, 'model', 'unflangedOpenEnd'));
            ka = real(m.k) * 0.0145;
            tc.verifyEqual(abs(m.Rterm), exp(-ka.^2 / 2) .* abs(exp(-2j * m.k * (0.436 - 0.075 + 0.6133 * 0.0145))), 'RelTol', 1e-9);
        end

        function twoLoadRecoversTheSpecimen(tc)
            % the porous layer and an ASYMMETRIC specimen (thin screen + 40 mm
            % air gap): T, the anechoic and the hard-backed values of the model
            air = tim.acoustics.airProperties(tc.env);
            [k, Zc] = tim.acoustics.wavenumber(tc.f, air, 0.029);
            kd = k * 0.040;
            asym = struct('type', 'matrix', 'T', @(f) cascade(400 + 0 * f, kd, Zc));
            for s = {tc.porous, asym}
                rA = tc.load(s{1}, struct('R', 0.05, 'x', 0.436));
                rB = tc.load(s{1}, struct('R', 1, 'x', 0.436));
                tl = tim.app.processTwoLoad(tc.loads({'A', 'B'}, {rA, rB}, ...
                    {struct('kind', 'absorber', 'place', 'tubeEnd'), struct('kind', 'rigid', 'place', 'tubeEnd')}), ...
                    tim.app.defaultConfig());
                m0 = tim.sim.tubeModel(tc.f, tc.geom, tc.env, s{1}, struct('R', 0, 'x', 0.436));   % anechoic
                tc.verifyEmpty(tl.checks.errors);
                for e = {'T11', 'T12', 'T21', 'T22'}
                    i = find(strcmp(e{1}, {'T11', 'T12', 'T21', 'T22'}));
                    tc.verifyEqual(tl.T.(e{1}), m0.T(:, i), 'RelTol', 1e-7, e{1});
                end
                tc.verifyEqual(tl.anechoic.tau, m0.tau, 'AbsTol', 1e-8);
                tc.verifyEqual(tl.anechoic.R, m0.R, 'AbsTol', 1e-8);
                % hard-backed: a rigid wall at the rear face (termination at xRear)
                mh = tim.sim.tubeModel(tc.f, tc.geom, tc.env, s{1}, struct('R', 1, 'x', 0.075));
                tc.verifyEqual(tl.hard.R, mh.R, 'AbsTol', 1e-8);
                tc.verifyEqual(tl.hard.alpha, 1 - abs(mh.R).^2, 'AbsTol', 1e-8);
                tc.verifyLessThan(max(tl.reciprocityError), 1e-7);
                tc.verifyEqual(tl.valid.nValid, nnz(tl.valid.base & tl.condQ <= 10));
                tc.verifyGreaterThan(tl.valid.nValid, 0.8 * numel(tc.f));
            end
            % the asymmetric specimen shows its asymmetry; the thin screen + gap is
            % no thin element (T21 ~= 0)
            tc.verifyGreaterThan(median(tl.symmetryError), 0.05);
            tc.verifyGreaterThan(median(tl.thin.T21Zc), 0.1);
        end

        function savedFiguresWithATransferMatrix(tc)
            % section 6: the same views draw the window and the saved figures - with
            % a transfer matrix two more figures (Two-load, Transfer matrix), and TL,
            % reflection, impedance and validity show T first; without one nothing
            % changes (seven figures)
            ab = {struct('kind', 'absorber', 'place', 'tubeEnd'), struct('kind', 'rigid', 'place', 'tubeEnd')};
            rA = tc.load(tc.porous, struct('R', 0.05, 'x', 0.436));
            rB = tc.load(tc.porous, struct('R', 1, 'x', 0.436));
            tl = tim.app.processTwoLoad(tc.loads({'A', 'B'}, {rA, rB}, ab), tim.app.defaultConfig());
            f = tim.app.plotResults(rA, [], struct('Visible', 'off', 'transferMatrix', tl));
            tc.addTeardown(@() structfun(@(h) delete(h), f));
            tc.verifyEqual(fieldnames(f).', {'waveforms', 'spectrum', 'transfer', 'twoLoad', 'reflection', ...
                'transmissionLoss', 'impedance', 'validity', 'transferMatrix'});
            ti = getappdata(f.transmissionLoss, 'timViewInfo');
            tc.verifyEqual(ti.summary.columns(1:3), {'Band [Hz]', 'TL from T [dB]', 'TL from τ [dB]'});
            tc.verifySubstring(ti.note, 'TL from T (two loads)');
            ri = getappdata(f.reflection, 'timViewInfo');
            tc.verifyEqual(ri.summary.columns, {'Band [Hz]', '|R_a|', '|τ_a|', 'α_d', 'α_h'});
            vi = getappdata(f.validity, 'timViewInfo');
            tc.verifyTrue(any(strcmp(vi.summary.data(:, 1), 'Valid T')));
            zi = getappdata(f.impedance, 'timViewInfo');
            tc.verifySubstring(zi.note, 'Not a thin element', 'the 75 mm porous layer');
            mi = getappdata(f.transferMatrix, 'timViewInfo');
            tc.verifyEqual(mi.summary.columns, {'Band [Hz]', '|T11|', '|T12|/Zc', '|Zc T21|', '|T22|'});
            wi = getappdata(f.twoLoad, 'timViewInfo');
            tc.verifyEqual(wi.summary.data(:, 2).', {'Absorber at tube end', 'Rigid cap at tube end'});
            g = tim.app.plotResults(rA, [], struct('Visible', 'off'));
            tc.addTeardown(@() structfun(@(h) delete(h), g));
            tc.verifyNumElements(fieldnames(g), 7, 'no transfer matrix: as before');
            % empty states of the new views
            ax = axes(figure('Visible', 'off')); tc.addTeardown(@() delete(ancestor(ax, 'figure')));
            ax(2) = axes(ancestor(ax, 'figure'));
            e = tim.plots.twoLoad(ax, []);
            tc.verifyEmpty(e.summary.data);
            e = tim.plots.transferMatrix(ax, []);
            tc.verifyNumElements(findobj(ax(1), 'Tag', 'timEmptyState'), 1);
            tc.verifyEqual(e.note, '');
        end

        function oneLoadSymmetricIsAnAssumption(tc)
            % decision 1: exact for a symmetric reciprocal specimen, wrong for an
            % asymmetric one - and marked as an assumption
            r = tc.load(tc.porous, struct('R', 0.05, 'x', 0.436));
            tl = tim.app.processTwoLoad(tc.loads({'oneLoad'}, {r}, {[]}), tim.app.defaultConfig());
            m = tim.sim.tubeModel(tc.f, tc.geom, tc.env, tc.porous, struct('R', 0, 'x', 0.436));
            tc.verifyEqual(tl.method, 'oneLoadSymmetric');
            tc.verifySubstring(tl.assumption, 'ASSUMED');
            tc.verifyEqual(tl.T.T12, m.T(:, 2), 'RelTol', 1e-7);
            tc.verifyEqual(tl.anechoic.tau, m.tau, 'AbsTol', 1e-8);
            tc.verifyTrue(all(isnan(tl.condQ)));
            air = tim.acoustics.airProperties(tc.env);
            [k, Zc] = tim.acoustics.wavenumber(tc.f, air, 0.029);
            asym = struct('type', 'matrix', 'T', @(f) cascade(400 + 0 * f, k * 0.040, Zc));
            r = tc.load(asym, struct('R', 0.05, 'x', 0.436));
            tl = tim.app.processTwoLoad(tc.loads({'oneLoad'}, {r}, {[]}), tim.app.defaultConfig());
            m = tim.sim.tubeModel(tc.f, tc.geom, tc.env, asym, struct('R', 0, 'x', 0.436));
            tc.verifyGreaterThan(median(abs(tl.anechoic.tau - m.tau)), 0.01, 'an asymmetric specimen breaks the assumption');
        end

        function similarLoadsAreMasked(tc)
            % two nearly equal loads: condQ above analysis.condQMax, the lines masked
            rA = tc.load(tc.porous, struct('R', 0.30, 'x', 0.436));
            rB = tc.load(tc.porous, struct('R', 0.32, 'x', 0.436));
            tl = tim.app.processTwoLoad(tc.loads({'A', 'B'}, {rA, rB}, {[], []}), tim.app.defaultConfig());
            tc.verifyGreaterThan(min(tl.condQ), 10);
            tc.verifyEqual(tl.valid.nValid, 0);
            tc.verifySubstring(tl.valid.summary, 'loads differ, condQ <= 10: 0');
        end

        function pairChecks(tc)
            % decision 6: another calibration, geometry or excitation kind -> nothing
            % computed; the same termination twice -> refused; temperature and time
            % -> warnings
            ab = {struct('kind', 'absorber', 'place', 'tubeEnd'), struct('kind', 'rigid', 'place', 'tubeEnd')};
            rA = tc.load(tc.porous, struct('R', 0.05, 'x', 0.436));
            rB = tc.load(tc.porous, struct('R', 1, 'x', 0.436), 'version', 'CAL-OTHER');
            tl = tim.app.processTwoLoad(tc.loads({'A', 'B'}, {rA, rB}, ab), tim.app.defaultConfig());
            tc.verifyNotEmpty(tl.checks.errors);
            tc.verifySubstring(tl.checks.errors{1}, 'CAL-OTHER');
            tc.verifyTrue(all(isnan(tl.T.T11)));
            tc.verifyEqual(tl.valid.nValid, 0);
            g = tc.geom; g.xRear = 0.070;
            rB = tc.load(tc.porous, struct('R', 1, 'x', 0.436), 'geom', g);
            tl = tim.app.processTwoLoad(tc.loads({'A', 'B'}, {rA, rB}, ab), tim.app.defaultConfig());
            tc.verifySubstring(strjoin(tl.checks.errors, ' '), 'another tube geometry');
            rB = tc.load(tc.porous, struct('R', 1, 'x', 0.436)); rB.kind = 'stepped';
            tl = tim.app.processTwoLoad(tc.loads({'A', 'B'}, {rA, rB}, ab), tim.app.defaultConfig());
            tc.verifySubstring(strjoin(tl.checks.errors, ' '), 'stepped measurement');
            rB = tc.load(tc.porous, struct('R', 1, 'x', 0.436));
            tl = tim.app.processTwoLoad(tc.loads({'A', 'B'}, {rA, rB}, {ab{1}, ab{1}}), tim.app.defaultConfig());
            tc.verifySubstring(strjoin(tl.checks.errors, ' '), 'both "Absorber at tube end"');
            % warnings only: 2 K and 45 min apart
            c = tim.app.defaultConfig(); cB = c; cB.environment.temperature_C = 22;
            rB = tc.load(tc.porous, struct('R', 1, 'x', 0.436), 'time', '2026-10-14 10:45:00.000');
            L = tc.loads({'A', 'B'}, {rA, rB}, ab); L(1).cfg = c; L(2).cfg = cB;
            tl = tim.app.processTwoLoad(L, c);
            tc.verifyEmpty(tl.checks.errors);
            w = strjoin(tl.warnings, ' | ');
            tc.verifySubstring(w, 'more than 1 K apart');
            tc.verifySubstring(w, '45 min after load A');
            tc.verifyGreaterThan(tl.valid.nValid, 0);
        end

        function repeatOfLoadAFindsAMovedSpecimen(tc)
            % decision 5: T(A,B) against T(A',B). A re-packed absorber (another
            % R_term) is no change; another specimen state is
            ab = {struct('kind', 'absorber', 'place', 'tubeEnd'), struct('kind', 'rigid', 'place', 'tubeEnd'), ...
                struct('kind', 'absorber', 'place', 'tubeEnd')};
            rA = tc.load(tc.porous, struct('R', 0.05, 'x', 0.436));
            rB = tc.load(tc.porous, struct('R', 1, 'x', 0.436));
            rA2 = tc.load(tc.porous, struct('R', 0.12, 'x', 0.436));        % the absorber packed differently
            tl = tim.app.processTwoLoad(tc.loads({'A', 'B', 'A2'}, {rA, rB, rA2}, ab), tim.app.defaultConfig());
            tc.verifyTrue(tl.repeat.performed);
            tc.verifyTrue(tl.repeat.ok);
            tc.verifyLessThan(tl.repeat.median, 1e-8);
            tc.verifySubstring(tl.repeat.text, 'nothing moved');
            moved = struct('type', 'porous', 'sigma', 2.5e4);                % compressed specimen
            rA2 = tc.load(moved, struct('R', 0.05, 'x', 0.436));
            tl = tim.app.processTwoLoad(tc.loads({'A', 'B', 'A2'}, {rA, rB, rA2}, ab), tim.app.defaultConfig());
            tc.verifyFalse(tl.repeat.ok);
            tc.verifyGreaterThan(tl.repeat.median, 0.05);
            tc.verifySubstring(strjoin(tl.warnings, ' '), 'may have moved');
        end

        function loadsAndTerminations(tc)
            % decision 2: kind x place, the absorber only at the tube end; the
            % virtual terminations at the CAD distances behind M4
            c = tim.app.defaultConfig();
            d = tim.app.describeLoad(struct('kind', 'rigid', 'place', 'tubeEnd'), c);
            tc.verifyEqual({d.label, d.tag, d.distance_m}, {'Rigid cap at tube end', 'rigid-end', 0.291});
            d = tim.app.describeLoad(struct('kind', 'open', 'place', 'joint'), c);
            tc.verifyEqual({d.label, d.distance_m}, {'Open end at joint', 0.041});
            cat = tim.app.describeLoad();
            tc.verifyEqual({cat.kinds.label}, {'Absorber', 'Rigid cap', 'Open end'});
            tc.verifyEqual({cat.places.label}, {'Tube end', 'Joint'});
            tc.verifyError(@() tim.app.describeLoad(struct('kind', 'absorber', 'place', 'joint')), 'tim:config:termination');
            tc.verifyError(@() tim.app.describeLoad(struct('kind', 'foam', 'place', 'joint')), 'tim:config:termination');
            m4 = max(c.simulation.Geometry.micPositions);
            t = tim.app.terminationModel(c, struct('kind', 'rigid', 'place', 'tubeEnd'));
            tc.verifyEqual([t.R, t.x], [1, m4 + 0.291], 'AbsTol', 1e-12);
            t = tim.app.terminationModel(c, struct('kind', 'open', 'place', 'joint'));
            tc.verifyEqual({t.model, t.x}, {'unflangedOpenEnd', m4 + 0.041});
            tc.verifyEqual(tim.app.terminationModel(c, struct('kind', 'absorber', 'place', 'tubeEnd')), ...
                c.simulation.Termination);
            % configuration: defaults, identical loads with two loads, a higher level for B
            tc.verifyEqual(c.measurement.method, 'oneLoad');
            tc.verifyEqual([c.analysis.condQMax, c.analysis.reciprocityTol], [10, 0.1]);
            c2 = c; c2.measurement.method = 'twoLoad'; c2.measurement.loadB = c2.measurement.loadA;
            tc.verifyError(@() tim.app.validateConfig(c2), 'tim:config:termination');
            c2 = c; c2.measurement.loadBLevel_dB = 3;
            tc.verifyError(@() tim.app.validateConfig(c2), 'tim:config:measurement');
            c2 = c; c2.measurement.method = 'threeLoad';
            tc.verifyError(@() tim.app.validateConfig(c2), 'tim:config:method');
        end

        function sessionRecordsAndSimulatesTheTermination(tc)
            % decision 9: every measurement records its termination; in simulation
            % the rig gets the selected load
            c = tim.app.defaultConfig();
            c.geometry = c.simulation.Geometry;
            c.excitation.sweep.duration = 1; c.excitation.sweep.repetitions = 1;
            s = tim.app.MeasurementSession(c);
            cleanup = onCleanup(@() s.close());
            s.connect(); s.prepareAcquisition();
            tc.verifyEqual(s.Rig.Termination, c.simulation.Termination, 'the absorber: the configured termination');
            prev = s.setTermination(struct('kind', 'rigid', 'place', 'joint'));
            tc.verifyEqual(prev, c.measurement.loadA);
            tc.verifyEqual(s.Rig.Termination.R, 1);
            m = s.measure('sweep');
            tc.verifyEqual(m.metadata.termination.label, 'Rigid cap at joint');
            tc.verifyEqual(m.metadata.termination.faceBehindM4_m, 0.041);
            tc.verifyEqual(m.metadata.simulationTruth.Termination.R, 1);
            js = jsonencode(m.metadata);             % metadata.json stays encodable (open end: no function handle)
            s.setTermination(struct('kind', 'open', 'place', 'tubeEnd'));
            m = s.measure('sweep');
            tc.verifyEqual(m.metadata.simulationTruth.Termination.model, 'unflangedOpenEnd');
            tc.verifyNotEmpty(jsonencode(m.metadata)); tc.verifyNotEmpty(js);
            tc.verifySubstring(strjoin(s.LogLines, newline), 'termination "Open end at tube end" mounted');
            clear cleanup
        end

        function sequenceSavesEveryLoadAndThePair(tc)
            % section 5: A -> B (6 dB lower) -> A' in the virtual tube, every load
            % saved at once, the pair folder, reopened and recombined
            tmp = tc.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture).Folder;
            c = tim.app.defaultConfig();
            c.geometry = c.simulation.Geometry;
            c.output.dataDir = fullfile(tmp, 'data'); c.output.calibrationDir = fullfile(tmp, 'cal');
            c.excitation.sweep.duration = 2; c.excitation.sweep.repetitions = 2;
            c.measurement.loadBLevel_dB = -6;
            s = tim.app.MeasurementSession(c);
            cleanup = onCleanup(@() s.close());
            s.connect(); s.prepareAcquisition();
            cal = tim.app.runCalibration(s);
            steps = {};
            out = tim.app.runTwoLoad(s, struct('specimen', 'porous 1', 'prompt', @(varargin) [], ...
                'report', @note));
            function note(q), steps{end+1} = q.kind; end
            tc.verifyEqual(steps, {'load', 'load', 'load', 'saving', 'result'});
            tc.verifyEqual({out.loads.role}, {'A', 'B', 'A2'});
            for i = 1:3
                L = out.loads(i);
                tc.verifyTrue(isfile(fullfile(L.folder, 'raw.mat')), L.folder);
                tc.verifyEqual(L.meas.metadata.twoLoad.role, L.role);
                tc.verifyEqual(L.meas.metadata.specimen, 'porous 1');
            end
            tc.verifyEqual(out.loads(2).meas.metadata.termination.label, 'Rigid cap at tube end');
            tc.verifyEqual(out.loads(3).meas.metadata.termination.label, 'Absorber at tube end');
            tc.verifySubstring(out.loads(2).folder, '_porous_1_loadB_rigid-end');
            tc.verifyEqual(out.loads(2).meas.settings.amplitudeVpp, out.loads(1).meas.settings.amplitudeVpp * 10^(-6/20), ...
                'RelTol', 1e-12, 'load B 6 dB lower');
            tc.verifyEqual(s.Cfg.excitation, c.excitation, 'the level of load A again afterwards');
            % the transfer matrix of the virtual specimen
            tl = out.tl;
            truth = s.Rig.trueResponse(tl.f).model;
            v = tl.valid.valid;
            tc.verifyGreaterThan(nnz(v), 0.5 * numel(v));
            n = @(T) [T(:, 1), T(:, 2) ./ tl.Zc, tl.Zc .* T(:, 3), T(:, 4)];
            Tm = [tl.T.T11, tl.T.T12, tl.T.T21, tl.T.T22];
            err = sqrt(sum(abs(n(Tm) - n(truth.T)).^2, 2)) ./ sqrt(sum(abs(n(truth.T)).^2, 2));
            tc.verifyLessThan(median(err(v)), 0.02);
            tc.verifyTrue(tl.repeat.performed && tl.repeat.ok, tl.repeat.text);
            tc.verifyTrue(all(isfinite(tl.level.peak_dB)));
            % the pair folder names the load folders; reopened, the same result
            info = jsondecode(tim.app.readTextUtf8(fullfile(out.folder, 'twoload.json')));
            [~, fA] = fileparts(out.loads(1).folder);
            tc.verifyEqual(info.loads(1).folder, fA);
            tc.verifyEqual(strlength(info.loads(1).rawSha256), 64);
            tc.verifyEqual(height(readtable(fullfile(out.folder, 'results.csv'))), numel(tl.f));
            p = tim.app.loadTwoLoad(out.folder);
            tc.verifyEmpty(p.warnings);
            tc.verifyEqual(p.tl.T.T12, tl.T.T12);
            for i = 1:3, p.loads(i).res = tim.app.processMeasurement(p.loads(i).meas, p.loads(i).cfg, cal); end
            tl2 = tim.app.processTwoLoad(p.loads, c);
            tc.verifyEqual(tl2.T.T12, tl.T.T12, 'RelTol', 1e-12);
            % two saved folders combined (File > Combine): the loads from their metadata
            q = tim.app.loadTwoLoad({out.loads(1).folder, out.loads(2).folder});
            tc.verifyEqual({q.loads.role}, {'A', 'B'});
            tc.verifyEqual(q.loads(2).load, struct('kind', 'rigid', 'place', 'tubeEnd'));
            clear cleanup
        end
    end
end

function T = cascade(Zt, kd, Zc)
% thin series screen at the front face, then an air gap of length d: asymmetric
Ta = [cos(kd), 1j * Zc .* sin(kd), 1j * sin(kd) ./ Zc, cos(kd)];
T = [Ta(:, 1) + Zt .* Ta(:, 3), Ta(:, 2) + Zt .* Ta(:, 4), Ta(:, 3), Ta(:, 4)];
end
