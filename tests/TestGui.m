classdef TestGui < matlab.unittest.TestCase
    %TESTGUI GUI building blocks and a hidden-window run of the app in
    %   SIMULATION mode (connect -> calibration -> measurement). No hardware.

    properties
        tmp
    end

    methods (TestMethodSetup)
        function setup(tc)
            f = tc.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            tc.tmp = f.Folder;
        end
    end

    methods (Test)
        function statusIcons(tc)
            for s = {'pending', 'run', 'ok', 'warn', 'fail', 'skip'}
                tc.verifyTrue(isfile(tim.gui.icon(s{1})), s{1});
            end
            info = imfinfo(tim.gui.icon('run'));
            tc.verifyGreaterThan(numel(info), 4, 'running icon is an animated GIF');
        end

        function checklistStates(tc)
            f = uifigure('Visible', 'off'); cleanup = onCleanup(@() delete(f));
            cl = tim.gui.Checklist(f, {'a', 'b'}, {'step A', 'step B'});
            tc.verifyEqual(cl.States, {'pending', 'pending'});
            cl.set('a', 'run', 'working');
            tc.verifyEqual(cl.state('a'), 'run');
            tc.verifyEqual(cl.runningKeys(), {'a'});
            tc.verifyEqual(cl.Icons(1).ImageSource, tim.gui.icon('run'));
            cl.set('a', 'ok', 'done');
            tc.verifyMatches(cl.Times(1).Text, '^\d+\.\d s$');
            tc.verifyEqual(cl.Details(1).Text, 'done');
            cl.appendDetail('a', ' + more');
            tc.verifyEqual(cl.Details(1).Text, 'done + more');
            cl.set('unknown', 'fail', 'ignored');          % unknown keys are ignored
            cl.rebuild({'x', 'y', 'z'}, {'1', '2', '3'});
            tc.verifyEqual(numel(cl.States), 3);
            clear cleanup
        end

        function tube3DModelFollowsGeometry(tc)
            % 3D drawing: positions follow the geometry, channel labels follow
            % the mapping, section / full view, incomplete geometry
            fig = figure('Visible', 'off'); cleanup = onCleanup(@() close(fig));
            ax = axes(fig);
            c = tim.app.defaultConfig();
            g = c.geometry; g.xFront = 0; g.xRear = 0.075;
            g.micPositions = [-0.070 -0.041 0.116 0.145];
            td = c.tubeDrawing;
            M = tim.gui.drawTube3D(ax, g, td, [2 1 3 4]);
            tc.verifyClass(M.micGroup(1), 'matlab.graphics.primitive.Transform');
            tc.verifyEqual(M.micGroup(1).Matrix, eye(4));
            tc.verifyEqual(M.portX, [-70 -41 116 145], 'AbsTol', 1e-9);
            tc.verifyEqual(M.micX0, [-41 -70 116 145], 'AbsTol', 1e-9, 'micX0(c) = port of channel c');
            tc.verifyNotEmpty(findobj(M.micGroup(2), 'Tag', 'mic1'), 'channel 2 (port M1) is in its own group');
            tc.verifyEmpty(findobj(ax, 'Tag', 'portGlow'), 'no glow in the Tube setup');
            term = findobj(ax, 'Tag', 'termination');
            tc.verifyEqual(unique(term.XData(:)), 145 + 1e3 * td.downstreamLength - 0.05, 'AbsTol', 1e-9);
            spec = findobj(ax, 'Tag', 'specimen');
            xs = cell2mat(cellfun(@(X) X(:), get(spec, 'XData'), 'UniformOutput', false));
            tc.verifyEqual([min(xs) max(xs)], [0 75], 'AbsTol', 1e-9);
            mic1 = findobj(ax, 'Tag', 'mic1');
            xm = cell2mat(cellfun(@(X) X(:), get(mic1, 'XData'), 'UniformOutput', false));
            tc.verifyEqual(mean([min(xm) max(xm)]), -70, 'AbsTol', 1e-6);
            tc.verifyTrue(any(strcmp(labels(ax), 'M1 ch2')), 'port M1 shows the channel mounted in it');
            tc.verifyTrue(any(strcmp(labels(ax), 'd = 75 mm')));
            tc.verifyNotEmpty(findobj(ax, 'Tag', 'cut'), 'section view has cut faces');
            % the user's rotation is kept when the geometry changes
            view(ax, [30 40]);
            g.xRear = 0.020; g.micPositions(3:4) = [0.061 0.090];
            tim.gui.drawTube3D(ax, g, td, 1:4, struct('section', false));
            tc.verifyEqual(ax.View, [30 40]);
            tc.verifyEmpty(findobj(ax, 'Tag', 'cut'), 'full view has no cut faces');
            tc.verifyTrue(any(strcmp(labels(ax), 'd = 20 mm')));
            tim.gui.drawTube3D(ax, 'view', 'side');
            tc.verifyEqual(ax.View, [0 0]);
            % incomplete geometry -> schematic, absorber drawn when its length is given
            g.micPositions = nan(1, 4); g.xFront = NaN; g.xRear = NaN;
            td.absorberLength = 0.05;
            tim.gui.drawTube3D(ax, g, td);
            tc.verifyTrue(any(strcmp(labels(ax), 'termination absorber 50 mm')));
            tc.verifyTrue(any(strcmp(labels(ax), 'L1 = ? (enter)')));
            tc.verifyNotEmpty(findobj(ax, 'Tag', 'absorber'));
            clear cleanup
        end

        function dialogNeverHangsWhenWindowCloses(tc)
            % regression 2026-10-09: a blocking uiconfirm never returned after
            % the window was closed (MATLAB stuck). app.ask must return the
            % cancel option; timers keep running while it waits.
            % (uiconfirm needs a visible window: it appears for about 1 s)
            app = tim.gui.TubeApp('', 'Visible', 'on');
            tc.addTeardown(@() delete(app));
            tick = timer('ExecutionMode', 'fixedSpacing', 'Period', 0.1, 'UserData', 0, ...
                'TimerFcn', @(t, ~) set(t, 'UserData', t.UserData + 1));
            % (closer after 2.5 s: under load the dialog itself needs up to ~1 s to appear)
            closer = timer('StartDelay', 2.5, 'TimerFcn', @(~, ~) tim.gui.closeApp(app.Fig, app));
            tc.addTeardown(@() delete([tick closer]));
            tc.addTeardown(@() stop([tick closer]));
            start(tick); start(closer);
            t0 = tic;
            sel = app.ask('Move the microphones', 'Step', {'Done', 'Abort'}, 1, 2, 'question');
            stop(tick);
            tc.verifyEqual(sel, 'Abort');
            tc.verifyLessThan(toc(t0), 8);
            tc.verifyGreaterThan(tick.UserData, 3, 'timers run while the dialog waits');
        end

        function tube3DCalibrationMode(tc)
            % calibration diagram = Tube setup model with the EMPTY section,
            % absorber, glowing calibration ports, movable microphone groups
            fig = figure('Visible', 'off'); tc.addTeardown(@() close(fig));
            ax = axes(fig);
            c = tim.app.defaultConfig(); g = c.geometry; g.xFront = 0; g.xRear = 0.075;
            g.micPositions = [-0.070 -0.041 0.116 0.145]; td = c.tubeDrawing;      % absorberLength NaN
            lbl = {{'ch1 (ref)', 's/n 111'}, {'ch2'}, {'ch3'}, {'ch4'}};
            M = tim.gui.drawTube3D(ax, g, td, [1 2 3 4], struct('mode', 'calibration', ...
                'highlightPorts', [1 2], 'micLabels', {lbl}));
            tc.verifyEmpty(findobj(ax, 'Tag', 'specimen'), 'no specimen during the calibration');
            sec = findobj(ax, 'Tag', 'specimenSection');
            xs = cell2mat(cellfun(@(X) X(:), get(sec, 'XData'), 'UniformOutput', false));
            tc.verifyEqual([min(xs) max(xs)], [0 75], 'AbsTol', 1e-9, 'empty 75 mm section mounted');
            tc.verifyTrue(any(strcmp(labels(ax), 'EMPTY 75 mm section (no specimen)')));
            tc.verifyNotEmpty(findobj(ax, 'Tag', 'absorber'), 'schematic absorber in calibration mode');
            glow = findobj(ax, 'Tag', 'portGlow'); tc.verifyEqual(numel(glow), 4);
            xg = cellfun(@(X) mean(X(:)), get(glow, 'XData'));
            tc.verifyEqual(unique(round(xg)).', [-70 -41]);
            L = labels(ax);
            tc.verifyTrue(any(strcmp(L, 'ch1 (ref) s/n 111')));
            tc.verifyTrue(any(strcmp(L, 'M1 (a)'))); tc.verifyTrue(any(strcmp(L, 'M2 (b)')));
            tc.verifyEqual(M.micLabel(1).Parent, M.micGroup(1));
            tc.verifyEmpty(findobj(ax, 'Tag', 'dim_s1'), 'no dimension lines');
            n0 = numel(findobj(ax));
            M.micGroup(1).Matrix = makehgtform('translate', [M.portX(3) - M.micX0(1), 0, M.lift(1)]);
            tc.verifyEqual(numel(findobj(ax)), n0, 'moving = transform only');
            tc.verifyGreaterThan(ax.ZLim(2), M.zHandle + M.lift(end));
        end

        function calibrationDiagramDrawnOnDemand(tc)
            c = tim.app.defaultConfig();
            c.geometry.xFront = 0; c.geometry.xRear = 0.075;
            c.geometry.micPositions = [-0.070 -0.041 0.116 0.145];
            file = fullfile(tc.tmp, 'lab.json'); tim.app.saveConfig(c, file);
            app = tim.gui.TubeApp(file, 'Visible', 'off'); tc.addTeardown(@() delete(app));
            ax = app.H.axCalSetup;
            tc.verifyEmpty(ax.Children, 'not drawn at start-up');
            tc.verifySubstring(strjoin(cellstr(app.H.calText.Text), ' '), 'Run switching cal.');
            app.drawCalSetup([], '', '');
            tc.verifyEqual(app.CalDrawCount, 1);
            tc.verifyEqual(numel(findobj(ax, 'Type', 'hgtransform')), 4);
            tc.verifyEqual(app.H.cal3D.portX, [-70 -41 116 145], 'AbsTol', 1e-9);
            app.drawCalSetup([], '', '');
            tc.verifyEqual(app.CalDrawCount, 1, 'no redraw when nothing changed');
        end

        function closeShowsStepsAndDisconnects(tc)
            % user request 2026-10-09: closing was slow without feedback. The
            % window disappears at once, a small window shows the steps, the
            % instruments are released and everything is deleted.
            c = tim.app.defaultConfig(); c.mode = 'simulation';
            c.output.dataDir = fullfile(tc.tmp, 'data'); c.output.calibrationDir = fullfile(tc.tmp, 'cal');
            file = fullfile(tc.tmp, 'cfg.json'); tim.app.saveConfig(c, file);
            app = tim.gui.TubeApp(file, 'Visible', 'off'); tc.addTeardown(@() delete(app));
            feval(app.H.connect.ButtonPushedFcn, app.H.connect, []);
            s = app.Session; fig = app.Fig;
            tc.assertTrue(s.Connected);
            t0 = tic;
            tim.gui.closeApp(fig, app);
            tc.verifyLessThan(toc(t0), 10);
            tc.verifyFalse(isvalid(app)); tc.verifyFalse(isvalid(fig));
            tc.verifyFalse(s.Connected, 'instruments released');
            tc.verifyEmpty(findall(groot, 'Type', 'figure', 'Name', 'Closing - Transfer impedance tube'), 'closing window deleted');
        end

        function closeDuringMeasurementStopsFirst(tc)
            % a close request while a measurement runs stops it first, then closes
            c = tim.app.defaultConfig(); c.mode = 'simulation';
            c.geometry = c.simulation.Geometry;
            c.output.dataDir = fullfile(tc.tmp, 'data'); c.output.calibrationDir = fullfile(tc.tmp, 'cal');
            c.excitation.sweep.duration = 3; c.excitation.sweep.repetitions = 4;
            file = fullfile(tc.tmp, 'cfg.json'); tim.app.saveConfig(c, file);
            app = tim.gui.TubeApp(file, 'Visible', 'off'); tc.addTeardown(@() delete(app));
            feval(app.H.connect.ButtonPushedFcn, app.H.connect, []);
            s = app.Session; fig = app.Fig;
            closer = timer('StartDelay', 1.0, 'TimerFcn', @(~, ~) tim.gui.closeApp(fig, app));
            tc.addTeardown(@() delete(closer));
            start(closer);
            t0 = tic;
            feval(app.H.start.ButtonPushedFcn, app.H.start, []);   % returns when stopped + closed
            tc.verifyLessThan(toc(t0), 20);
            tc.verifyTrue(s.StopRequested, 'the running measurement was stopped first');
            tc.verifyFalse(isvalid(app)); tc.verifyFalse(isvalid(fig));
            tc.verifyFalse(s.Connected);
            tc.verifyEmpty(findall(groot, 'Type', 'figure', 'Name', 'Closing - Transfer impedance tube'));
        end

        function appSimulationWorkflow(tc)
            % hidden app window: connect (checklist + cards), switching
            % calibration (step list), measurement (waveforms in Pa)
            c = tim.app.defaultConfig();
            c.mode = 'simulation';
            c.geometry = c.simulation.Geometry;
            c.output.dataDir = fullfile(tc.tmp, 'data');
            c.output.calibrationDir = fullfile(tc.tmp, 'cal');
            c.excitation.sweep.duration = 3; c.excitation.sweep.repetitions = 2;
            c.calibration.repeatConfigI = false;
            file = fullfile(tc.tmp, 'cfg.json');
            tim.app.saveConfig(c, file);
            app = tim.gui.TubeApp(file, 'Visible', 'off');
            cleanup = onCleanup(@() delete(app));
            h = app.H;
            feval(h.connect.ButtonPushedFcn, h.connect, []);
            tc.verifyTrue(all(ismember(app.ConnList.States, {'ok', 'skip'})), strjoin(app.ConnList.States, ' '));
            P = tim.gui.palette();
            tc.verifyEqual(vertcat(h.lamp.Color), repmat(P.ok, 6, 1), 'all lamps green');
            tc.verifyEqual(h.card(3).state.Text, 'OK');
            tc.verifySubstring(h.connHead.Text, 'all checks passed');
            g = app.Cfg.geometry;      % GUI round trip keeps the coordinates bit-exact
            tc.verifyEqual(g.micPositions, c.geometry.micPositions);
            tc.verifyEqual([g.spacingUp g.spacingDown g.xRear], [c.geometry.spacingUp c.geometry.spacingDown c.geometry.xRear]);
            feval(h.runCal.ButtonPushedFcn, h.runCal, []);
            tc.verifyEqual(numel(app.CalList.States), 1 + 3 * 2 + 1 + 1);
            tc.verifyTrue(all(strcmp(app.CalList.States, 'ok')), strjoin(app.CalList.States, ' '));
            tc.verifySubstring(app.CalList.Details(end - 1).Text, 'passed', 'Test E verdict on the done row');
            hc = app.H; M = hc.cal3D; ax = hc.axCalSetup;
            tc.verifyEqual(app.CalDrawCount, 1, '3D model drawn once per calibration; steps move transforms');
            tc.verifyEmpty(findobj(ax, 'Tag', 'specimen'));
            tc.verifyEqual(numel(findobj(ax, 'Tag', 'portGlow')), 2 * numel(c.calibration.positions));
            tc.verifyEqual(app.CalDrawn, [1 2 3 4], 'microphones returned to M1-M4');
            for ch = 1:4
                T = M.micGroup(ch).Matrix;
                tc.verifyEqual(M.micX0(ch) + T(1, 4), M.portX(ch), 'AbsTol', 1e-9);
                tc.verifyEqual(T(2:3, 4), [0; 0], 'AbsTol', 1e-9, 'lowered back into the port');
            end
            tc.verifyEqual(M.glow(1).FaceAlpha, 0.35, 'AbsTol', 1e-12, 'glow at rest');
            tc.verifySubstring(h.calLabel.Text, 'CAL-');
            feval(h.start.ButtonPushedFcn, h.start, []);
            tc.verifyNotEmpty(app.LastRes);
            tc.verifyEqual(h.axW(1).YLabel.String, 'ch1 [Pa]');
            feval(h.background.ButtonPushedFcn, h.background, []);
            tc.verifyEqual(app.LastMeas.kind, 'background');
            tc.verifyEqual(h.stop.Text, 'STOP', 'busy label restored');
            tc.verifyEqual(h.start.Enable, matlab.lang.OnOffSwitchState.on, 'controls unlocked again');
            clear cleanup
        end

        function steppedDisplayShowsStepLevels(tc)
            % regression 2026-10-09: the Spectrum tab showed the PSD of the whole
            % stepped record (line spectrum -> one spike per step). It shows the
            % level of every step at the step frequencies; sweep display unchanged.
            c = tim.app.defaultConfig();
            c.mode = 'simulation';
            c.geometry = c.simulation.Geometry;
            c.output.dataDir = fullfile(tc.tmp, 'data'); c.output.calibrationDir = fullfile(tc.tmp, 'cal');
            c.excitation.mode = 'stepped';
            c.excitation.stepped = struct('fStart', 200, 'fStop', 4000, 'nPoints', 6, 'spacing', 'log', ...
                'amplitudeVpp', 0.2, 'settleTime', 0.1, 'recordTime', 0.2, 'nBlocks', 2, 'repetitions', 1);
            c.excitation.sweep.duration = 2; c.excitation.sweep.repetitions = 1;
            file = fullfile(tc.tmp, 'cfg.json'); tim.app.saveConfig(c, file);
            app = tim.gui.TubeApp(file, 'Visible', 'off'); tc.addTeardown(@() delete(app));
            h = app.H;
            tc.assertEqual(h.exMode.Value, 'stepped');
            feval(h.connect.ButtonPushedFcn, h.connect, []);
            feval(h.start.ButtonPushedFcn, h.start, []);
            tc.assertNotEmpty(app.LastRes);
            fk = app.LastMeas.settings.frequencies(:);
            tc.verifyEqual(numel(fk), 6, 'GUI Steps field used');
            L = findobj(h.axSpec, 'Type', 'line', 'Marker', 'o');
            tc.verifyNumElements(L, 4);
            for i = 1:numel(L)
                tc.verifyEqual(L(i).XData(:), fk, 'RelTol', 1e-12, 'markers only at the step frequencies');
                tc.verifyTrue(all(isfinite(L(i).YData)));
            end
            tc.verifySubstring(strjoin(cellstr(h.axSpec.Title.String), ' '), 'Stepped sine');
            LH = findobj(h.axH, 'Type', 'line');
            tc.verifyTrue(all(strcmp({LH.Marker}, 'o')), 'relative responses drawn as markers');
            % sweep afterwards: dense PSD, no markers, no stepped title
            h.exMode.Value = 'sweep'; feval(h.exMode.ValueChangedFcn, h.exMode, struct('PreviousValue', 'stepped'));
            feval(h.start.ButtonPushedFcn, h.start, []);
            L = findobj(h.axSpec, 'Type', 'line');
            tc.verifyTrue(all(strcmp({L.Marker}, 'none')));
            tc.verifyGreaterThan(max(arrayfun(@(l) numel(l.XData), L)), 1000);
            tc.verifyFalse(contains(strjoin(cellstr(h.axSpec.Title.String), ' '), 'Stepped'));
            LH = findobj(h.axH, 'Type', 'line');
            tc.verifyTrue(all(strcmp({LH.Marker}, 'none')));
        end

        function tubeFieldsAreExactDistances(tc)
            % regression 2026-10-09: s1/s2 showed 29.000000000000004 / 28.999999999999986
            % while editing; Save config wrote 0.11599999999999999
            c = tim.app.defaultConfig();
            c.geometry.xFront = 0; c.geometry.xRear = 0.075;
            c.geometry.micPositions = [-0.070 -0.041 0.116 0.145];
            file = fullfile(tc.tmp, 'lab.json'); tim.app.saveConfig(c, file);
            app = tim.gui.TubeApp(file, 'Visible', 'off'); tc.addTeardown(@() delete(app));
            h = app.H;
            tc.verifyEqual([h.tubeD.Value h.s1.Value h.s2.Value], [29 29 29]);      % bit-exact
            tc.verifyEqual({h.L1.Value, h.dTh.Value, h.L2.Value}, {'41', '75', '41'});
            tc.verifyEqual(char(h.s1.ValueDisplayFormat), '%.10g');
            g = app.currentGeometry();
            tc.verifyEqual(g.micPositions, [-0.070 -0.041 0.116 0.145]);
            tc.verifyEqual([g.spacingUp g.spacingDown g.xFront g.xRear g.diameter], [0.029 0.029 0 0.075 0.029]);
            h.L2.Value = '41.25'; g = app.currentGeometry();
            tc.verifyEqual(g.micPositions(3:4), [0.11625 0.14525]);
        end

        function leftPanelFitsWithoutScrolling(tc)
            % user request 2026-10-09: no scrolling in the left panel on the lab screen
            % (maximised 1920 x 1080 -> 989 px; restored window 960 - 20 = 940 px)
            app = tim.gui.TubeApp('', 'Visible', 'off'); tc.addTeardown(@() delete(app));
            L = app.H.left; g = L.Parent;
            rh = L.RowHeight;
            tc.verifyTrue(all(cellfun(@isnumeric, rh)), 'left panel uses fixed row heights only');
            content = sum([rh{:}]) + (numel(rh) - 1) * L.RowSpacing + L.Padding(2) + L.Padding(4);
            tc.verifyLessThanOrEqual(content, 740, sprintf('left panel content %g px (smallest window: 740 px)', content));
            ch = L.Children; rows = zeros(1, numel(ch));
            for i = 1:numel(ch), rows(i) = ch(i).Layout.Row; end
            tc.verifyEqual(sort(rows), 1:numel(rh), 'one child per row, every row used');
            W = g.ColumnWidth{1} - L.Padding(1) - L.Padding(3);
            for i = 1:numel(ch)
                if isa(ch(i), 'matlab.ui.container.GridLayout')
                    cw = ch(i).ColumnWidth; fixed = cellfun(@isnumeric, cw);
                    need = sum([cw{fixed}]) + (numel(cw) - 1) * ch(i).ColumnSpacing + 50 * sum(~fixed);
                    tc.verifyLessThanOrEqual(need, W, sprintf('row %d too wide', ch(i).Layout.Row));
                end
            end
            for n = {'mode','loadCfg','saveCfg','connect','disconnect','exMode','fRange','dur','amp','reps', ...
                    'ampModel','ampGain','spkZ','spkP','start','stop','background','tubeD','s1','L1','dTh','L2','s2', ...
                    'temp','pres','loadCal','runCal','save','reprocess','status','drive','fLimits','calLabel'}
                tc.verifyTrue(isfield(app.H, n{1}) && isvalid(app.H.(n{1})), n{1});
            end
        end

        function steppedFieldsFollowTheMode(tc)
            % before 2026-10-09 f start/stop, duration and repetitions reached only the sweep
            app = tim.gui.TubeApp('', 'Visible', 'off'); tc.addTeardown(@() delete(app));
            h = app.H; c = tim.app.defaultConfig();
            tc.verifyEqual(h.durLabel.Text, 'Sweep time [s]');
            h.exMode.Value = 'stepped'; feval(h.exMode.ValueChangedFcn, h.exMode, struct('PreviousValue', 'sweep'));
            tc.verifyEqual(h.durLabel.Text, 'Steps');
            tc.verifyEqual(h.dur.Value, c.excitation.stepped.nPoints);
            h.fRange.Value = '200 3000'; h.dur.Value = 12; h.reps.Value = 2;
            h.exMode.Value = 'sweep'; feval(h.exMode.ValueChangedFcn, h.exMode, struct('PreviousValue', 'stepped'));
            tc.verifyEqual(h.dur.Value, c.excitation.sweep.duration);
            s = app.Cfg.excitation.stepped;
            tc.verifyEqual([s.fStart s.fStop s.nPoints s.repetitions], [200 3000 12 2], 'typed stepped values kept');
        end

        function windowTitleAndRepositoryLink(tc)
            app = tim.gui.TubeApp('', 'Visible', 'off'); tc.addTeardown(@() delete(app));
            tc.verifyEqual(app.Fig.Name, 'Transfer impedance tube', 'no hyphen in the window name');
            tc.verifyClass(app.H.repoLink, 'matlab.ui.control.Hyperlink');
            tc.verifyEqual(app.H.repoLink.URL, tim.app.repositoryUrl());
            tc.verifySubstring(app.H.version.Text, 'transfer-impedance-tube-measurement 1.1.0');
        end
    end
end

function L = labels(ax)
t = findobj(ax, 'Type', 'text');
L = cellfun(@(s) strjoin(cellstr(s), ' '), get(t, 'String'), 'UniformOutput', false);
end
