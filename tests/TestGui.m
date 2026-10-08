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
            tim.gui.drawTube3D(ax, g, td, [2 1 3 4]);
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
            closer = timer('StartDelay', 1.0, 'TimerFcn', @(~, ~) tim.gui.closeApp(app.Fig, app));
            tc.addTeardown(@() delete([tick closer]));
            tc.addTeardown(@() stop([tick closer]));
            start(tick); start(closer);
            t0 = tic;
            sel = app.ask('Move the microphones', 'Step', {'Done', 'Abort'}, 1, 2, 'question');
            stop(tick);
            tc.verifyEqual(sel, 'Abort');
            tc.verifyLessThan(toc(t0), 5);
            tc.verifyGreaterThan(tick.UserData, 3, 'timers run while the dialog waits');
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
            tc.verifyEqual(numel(app.CalList.States), 1 + 3 * 2 + 1);
            tc.verifyTrue(all(strcmp(app.CalList.States, 'ok')), strjoin(app.CalList.States, ' '));
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
