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
            for s = {'pending', 'run', 'ok', 'warn', 'fail', 'skip', 'start', 'stop'}
                tc.verifyTrue(isfile(tim.gui.icon(s{1})), s{1});
            end
            info = imfinfo(tim.gui.icon('run'));
            tc.verifyGreaterThan(numel(info), 4, 'running icon is an animated GIF');
            tc.verifyTrue(all([info.TransparentColor] > 0), 'transparent background (start window panel)');
        end

        function logoFiles(tc)
            % user choice 2026-10-10: mark "four ports" - tube with the specimen block,
            % four microphones in the channel colours; light and reverse SVG (master)
            % and PNG for the uifigure 'Icon' (R2022b: no SVG there)
            P = tim.gui.palette();
            folder = fullfile(tim.app.projectRoot(), 'resources', 'logo');
            tc.verifyEqual(tim.gui.logo(), fullfile(folder, 'tubebench-mark.svg'));
            tc.verifyEqual(tim.gui.logo('reverse'), fullfile(folder, 'tubebench-mark-reverse.svg'));
            hexOf = @(c) upper(sprintf('#%02X%02X%02X', round(255 * c)));
            for v = {'light', 'reverse'}
                f = tim.gui.logo(v{1});
                tc.assertTrue(isfile(f), f);
                svg = tim.app.readTextUtf8(f);
                tc.verifySubstring(svg, 'viewBox="0 0 64 64"');
                lines = regexp(svg, '<line [^>]*stroke="(#[0-9A-F]{6})"', 'tokens');
                circles = regexp(svg, '<circle [^>]*fill="(#[0-9A-F]{6})"', 'tokens');
                tc.verifyEqual([lines{:}], [circles{:}], [v{1} ': microphone and its cap in the same colour']);
                tc.verifyNumElements(lines, 4, v{1});
                if strcmp(v{1}, 'light')
                    tc.verifyEqual([lines{:}], arrayfun(@(c) hexOf(P.ch(c, :)), 1:4, 'UniformOutput', false), ...
                        'light mark: microphones in the channel colours ch1..ch4');
                    tc.verifySubstring(svg, ['stroke="' hexOf(P.ui.bar) '"'], 'tube in the header colour');
                else
                    tc.verifyEqual([lines{:}], {'#5AB0F0', '#F06A9F', '#33C99A', '#E8C547'}, 'reverse mark');
                    tc.verifySubstring(svg, 'stroke="#FFFFFF"', 'white tube on the dark header');
                end
                for n = [16 32 48 256]
                    f = tim.gui.logo(v{1}, n);
                    tc.verifyTrue(isfile(f), f);
                    [img, ~, alpha] = imread(f);
                    tc.verifySize(img, [n n 3], f);
                    tc.verifyEqual(size(alpha), [n n], [f ': transparent background']);
                    tc.verifyEqual(double(alpha([1 end], [1 end])), zeros(2), [f ': corners transparent']);
                end
            end
            icon = tim.gui.logo('icon');
            tc.verifyEqual(icon, tim.gui.logo('light', 32), 'window icon: light mark, 32 px PNG');
            [~, ~, ext] = fileparts(icon);
            tc.verifyEqual(ext, '.png');
            tc.verifyError(@() tim.gui.logo('dark'), 'tim:gui:logo');
        end

        function startWindowStepsAndClose(tc)
            % user request 2026-10-10: a small start window (name, version, step,
            % progress bar, turning icon) while the main window is built; closing
            % it by the user does not stop the start-up
            sw = tim.gui.StartWindow('Visible', 'off'); tc.addTeardown(@() delete(sw));
            f = sw.Fig;
            tc.verifyEqual(f.Name, 'tubebench');   % program name since 2026-10-10
            tc.verifyEqual(f.Position(3:4), [460 190]);
            tc.verifyFalse(logical(f.Resize));
            [~, info] = tim.app.softwareVersion();
            tc.verifyEqual(sw.H.title.Text, 'tubebench');
            tc.verifySubstring(sw.H.version.Text, info.version);
            tc.verifySubstring(sw.H.version.Text, info.released);
            tc.verifyEqual(sw.H.spin.ImageSource, tim.gui.icon('run'), 'turning icon (animated by the window)');
            % user choice 2026-10-10: the reverse mark on the dark header, 52 px column
            tc.verifyEqual(tim.gui.StartWindow.LogoFile, tim.gui.logo('reverse'));
            tc.verifyTrue(isfile(tim.gui.StartWindow.LogoFile));
            tc.verifyEqual(sw.H.logo.ImageSource, tim.gui.logo('reverse'), 'logo shown (SVG)');
            tc.verifyEqual(sw.H.logo.Parent.ColumnWidth{1}, 52);
            tc.verifyEqual(f.Icon, tim.gui.logo('icon'), 'window icon');
            tc.verifyEqual(sw.Step, 'Starting…');
            frac = @() str2double(erase(sw.H.bar.ColumnWidth{1}, 'x')) / ...
                (str2double(erase(sw.H.bar.ColumnWidth{1}, 'x')) + str2double(erase(sw.H.bar.ColumnWidth{2}, 'x')));
            sw.update('Drawing the 3D tube model…', 0.4);
            tc.verifyEqual(sw.H.step.Text, 'Drawing the 3D tube model…');
            tc.verifyEqual(sw.Value, 0.4);
            tc.verifyEqual(frac(), 0.4, 'AbsTol', 1e-3, 'filled part of the bar');
            sw.update('Ready', 1.5);
            tc.verifyEqual(sw.Value, 1, 'progress limited to 0..1');
            tc.verifyEqual(sw.H.bar.ColumnWidth, {'1x', 0});
            tc.verifyEqual({sw.Steps.text}, {'Starting…', 'Drawing the 3D tube model…', 'Ready'});
            tc.verifyTrue(issorted([sw.Steps.time]));
            feval(f.CloseRequestFcn, f, []);              % closed by the user
            tc.verifyFalse(isvalid(f));
            sw.update('Drawing the graphs of the views…', 0.8);   % start-up goes on: no error
            tc.verifyEqual(sw.Step, 'Drawing the graphs of the views…');
            sw2 = tim.gui.StartWindow('Visible', 'off'); f2 = sw2.Fig;
            sw2.close();
            tc.verifyFalse(isvalid(f2));
            delete(sw2);
        end

        function startWindowGoesOnError(tc)
            % the start window always disappears, also when the start-up fails
            % (a visible start: the start window appears for about 1 s)
            n0 = numel(findall(groot, 'Type', 'figure'));
            tc.verifyError(@() tim.gui.TubeApp(fullfile(tc.tmp, 'missing.json')), 'tim:io:open');
            tc.verifyEqual(numel(findall(groot, 'Type', 'figure')), n0, 'no window left');
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
            n0 = numel(findall(groot, 'Type', 'figure'));
            app = tim.gui.TubeApp('', 'Visible', 'on');
            tc.addTeardown(@() delete(app));
            % start window (user request 2026-10-10): steps shown while the main
            % window was built hidden, closed when the main window appeared.
            % Progressive start-up (user choice 2026-10-10): only the control panel,
            % the tabs and Setup > Connection before the window appears; the other
            % views in the background (this test closes the window meanwhile)
            s = app.StartSteps;
            tc.verifyEqual({s.text}, {'Starting…', 'Building the control panel…', 'Building the Connection view…', ...
                'Filling in the settings…', 'Opening the main window…', 'Ready'});
            tc.verifyTrue(issorted([s.value]), 'the bar only moves forward');
            tc.verifyEqual(s(end).value, 1);
            tc.verifyTrue(strcmp(app.Fig.Visible, 'on'));
            tc.verifyTrue(app.Deferred, 'visible window: views prepared in the background');
            tc.verifyGreaterThan(app.ShownTime, 0);
            tc.verifyEqual(app.BuildTimer.Name, 'tubebench-build');
            tc.verifyEmpty(app.StartWin);
            tc.verifyEqual(numel(findall(groot, 'Type', 'figure')), n0 + 1, 'start window closed');
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
            tc.verifySubstring(strjoin(cellstr(app.H.calText.Text), ' '), 'Run switching calibration');
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
            % the steps shown in the closing dialog are also logged by the session
            tc.verifyTrue(any(contains(s.LogLines, 'Closing: Generator output off (confirmed).')));
            tc.verifyTrue(any(contains(s.LogLines, 'Closing: Instruments disconnected.')));
            tc.verifyTrue(any(contains(s.LogLines, 'Closing: window deleted.')));
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
            tc.verifyTrue(any(contains(s.LogLines, 'Closing: window close requested while busy - STOP requested first.')));
            tc.verifyTrue(any(contains(s.LogLines, 'Closing: Instruments disconnected.')));
            % stopped (inside the acquisition, or before it started - a close request
            % before the first measurement is honoured too), never completed
            tc.verifyFalse(any(contains(s.LogLines, 'Repetition 4:')), strjoin(s.LogLines, newline));
        end

        function staleStopDoesNotAnswerLaterQuestions(tc)
            % final review 2026-10-09 (gui-1): the session keeps the Stop flag after a
            % stopped measurement; ask() must honour it only DURING an action, else
            % the unsaved-measurement question (Start, Close ...) is answered 'Cancel'
            % without a dialog and the button silently does nothing
            c = tim.app.defaultConfig(); c.mode = 'simulation';
            c.geometry = c.simulation.Geometry;
            c.output.dataDir = fullfile(tc.tmp, 'data'); c.output.calibrationDir = fullfile(tc.tmp, 'cal');
            c.excitation.sweep.duration = 3; c.excitation.sweep.repetitions = 4;
            file = fullfile(tc.tmp, 'cfg.json'); tim.app.saveConfig(c, file);
            app = tim.gui.TubeApp(file, 'Visible', 'off'); tc.addTeardown(@() delete(app));
            h = app.H;
            feval(h.connect.ButtonPushedFcn, h.connect, []);
            stopper = timer('StartDelay', 1.0, 'TimerFcn', @(~, ~) feval(h.stop.ButtonPushedFcn, h.stop, []));
            tc.addTeardown(@() delete(stopper));
            start(stopper);
            feval(h.start.ButtonPushedFcn, h.start, []);            % stopped after about 1 s
            tc.assertTrue(app.Session.StopRequested, 'the flag stays set after the action');
            tc.verifyFalse(app.Busy);
            tc.verifyEqual(app.ask('Measure anyway?', 'Unsaved measurement', {'Measure', 'Cancel'}, 1, 2), 'Measure', ...
                'a stale Stop flag must not answer a later question');
            tc.verifySubstring(h.status.Text, 'Ready', 'status restored after the stop');
            tc.verifyEqual(h.stop.Enable, matlab.lang.OnOffSwitchState.off, 'Stop only during an action');
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
            tc.verifyEqual(h.axW(1).YLabel.String, 'ch1 (M1) [Pa]');
            tc.verifySubstring(h.resultStatus.Text, 'not saved', 'RESULTS line: unsaved measurement');
            feval(h.background.ButtonPushedFcn, h.background, []);
            tc.verifyEqual(app.LastMeas.kind, 'background');
            tc.verifyEqual(h.stop.Text, 'Stop', 'busy label restored');
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
            % values typed in the GUI (different from the configuration) must be used
            h.dur.Value = 5; h.fStart.Value = 300; h.fStop.Value = 3000; h.reps.Value = 2;
            feval(h.start.ButtonPushedFcn, h.start, []);
            tc.assertNotEmpty(app.LastRes);
            fk = app.LastMeas.settings.frequencies(:);
            tc.verifyEqual(numel(fk), 5, 'GUI Steps field used');
            tc.verifyEqual(fk([1 end]).', [300 3000], 'RelTol', 1e-9, 'GUI frequency range used');
            tc.verifyNumElements(app.LastMeas.records, 2, 'GUI repetitions used');
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
            % user request 2026-10-09: no scrolling in the control panel on the lab screen
            % (window = work area of the 1920 x 1080 lab laptop screen: about 975 px inside the title and menu bars)
            app = tim.gui.TubeApp('', 'Visible', 'off'); tc.addTeardown(@() delete(app));
            L = app.H.left; g = L.Parent;
            rh = L.RowHeight;
            tc.verifyTrue(all(cellfun(@isnumeric, rh)), 'left panel uses fixed row heights only');
            content = sum([rh{:}]) + (numel(rh) - 1) * L.RowSpacing + L.Padding(2) + L.Padding(4);
            tc.verifyLessThanOrEqual(content, 930, sprintf('control panel content %g px (restored window on the lab screen: 935 px)', content));
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
            for n = {'mode','connect','disconnect','exMode','fStart','fStop','dur','amp','reps', ...
                    'ampModel','ampGain','spkZ','spkP','start','stop','background','tubeD','s1','L1','dTh','L2','s2', ...
                    'temp','pres','loadCal','runCal','save','reprocess','status','drive','fLimits','calLabel', ...
                    'specimen','resultStatus','durEst'}
                tc.verifyTrue(isfield(app.H, n{1}) && isvalid(app.H.(n{1})), n{1});
            end
        end

        function steppedFieldsFollowTheMode(tc)
            % before 2026-10-09 f start/stop, duration and repetitions reached only the sweep
            app = tim.gui.TubeApp('', 'Visible', 'off'); tc.addTeardown(@() delete(app));
            h = app.H; c = tim.app.defaultConfig();
            tc.verifyEqual(h.durLabel.Text, 'Sweep duration [s]');
            h.exMode.Value = 'stepped'; feval(h.exMode.ValueChangedFcn, h.exMode, struct('PreviousValue', 'sweep'));
            tc.verifyEqual(h.durLabel.Text, 'Number of steps');
            tc.verifyEqual(h.dur.Value, c.excitation.stepped.nPoints);
            h.fStart.Value = 200; h.fStop.Value = 3000; h.dur.Value = 12; h.reps.Value = 2;
            h.exMode.Value = 'sweep'; feval(h.exMode.ValueChangedFcn, h.exMode, struct('PreviousValue', 'stepped'));
            tc.verifyEqual(h.dur.Value, c.excitation.sweep.duration);
            s = app.Cfg.excitation.stepped;
            tc.verifyEqual([s.fStart s.fStop s.nPoints s.repetitions], [200 3000 12 2], 'typed stepped values kept');
        end

        function calibrationPromptBar(tc)
            % user request 2026-10-09: no modal dialog (dimmed window) at the
            % calibration steps - the question is in the bar above the 3D model,
            % which nothing covers; the model is larger (step list in the right
            % column, C_k curves side by side, less room for lifted microphones)
            c = tim.app.defaultConfig(); c.mode = 'simulation'; c.geometry = c.simulation.Geometry;
            c.output.dataDir = fullfile(tc.tmp, 'data'); c.output.calibrationDir = fullfile(tc.tmp, 'cal');
            c.excitation.sweep.duration = 1; c.excitation.sweep.repetitions = 1;
            c.calibration.repeatConfigI = false;
            file = fullfile(tc.tmp, 'cfg.json'); tim.app.saveConfig(c, file);
            app = tim.gui.TubeApp(file, 'Visible', 'off'); tc.addTeardown(@() delete(app));
            app.PromptInSimulation = true;                      % ask at every step, as with hardware
            h = app.H;
            tc.verifyEqual(h.calText.Interpreter, 'html');
            tc.verifyGreaterThanOrEqual(h.calTg.RowHeight{1}, 116, 'bar height at least 116 px (fixed unless a text needs more)');
            tc.verifyLessThanOrEqual(h.calTg.RowHeight{1}, 170);
            tc.verifyEqual(h.calBar.ColumnWidth{2}, 0, 'no buttons outside a question');
            tc.verifyTrue(app.CalList.Grid.Parent.Parent == app.Pages.cal.SummaryPanel, 'step list in the right column');
            tc.verifyTrue(app.CalList.Stacked);
            tc.verifyLessThan(h.axCal(1).Position(1), h.axCal(2).Position(1), 'C_k curves side by side');
            tc.verifyEqual(h.axCal(1).XLabel.String, 'Frequency [Hz]');
            feval(h.connect.ButtonPushedFcn, h.connect, []);
            feval(h.runCal.ButtonPushedFcn, h.runCal, []);
            tc.verifyTrue(all(strcmp(app.CalList.States, 'ok')), strjoin(app.CalList.States, ' '));
            tc.verifyEqual(app.LastPrompt.options, {tim.app.msg('en', 'calContinueButton'), ...
                tim.app.msg('en', 'abortButton')}, 'the last step (mount the specimen) was asked in the bar');
            tc.verifyEqual(h.calBar.ColumnWidth{2}, 0, 'buttons hidden again');
            M = app.H.cal3D;
            tc.verifyLessThanOrEqual(max(diff(M.lift)), 10, 'lifted microphones: +10 mm per mover');
            tc.verifySubstring(char(h.calText.Text), '<b>');
        end

        function openSavedMeasurement(tc)
            % user request 2026-10-09: File > Open measurement… shows a saved
            % measurement again (views, RESULTS line), offers the tube set-up of the
            % saved results, allows Reprocess / Save; the opened files never change
            c = tim.app.defaultConfig();
            c.mode = 'simulation';
            c.geometry = c.simulation.Geometry;
            c.output.dataDir = fullfile(tc.tmp, 'data');
            c.output.calibrationDir = fullfile(tc.tmp, 'cal');
            c.output.exportFigures = false;
            c.excitation.sweep.duration = 1; c.excitation.sweep.repetitions = 1;
            s = tim.app.MeasurementSession(c);
            s.connect(); s.prepareAcquisition();
            meas = s.measure('sweep'); s.close();
            meas.metadata.specimen = 'demo';
            res = tim.app.processMeasurement(meas, c, []);
            d = tim.app.saveMeasurement(meas, res, c, 'sweep_demo', []);
            raw0 = dir(fullfile(d, 'raw.mat'));
            % the app starts with another set-up (L1 9 mm longer) and no measurement
            c2 = c; c2.geometry.micPositions(1:2) = c.geometry.micPositions(1:2) - 0.009;
            file = fullfile(tc.tmp, 'cfg.json'); tim.app.saveConfig(c2, file);
            app = tim.gui.TubeApp(file, 'Visible', 'off'); tc.addTeardown(@() delete(app));
            h = app.H;
            L1 = h.L1.Value;
            app.openMeasurement(d, false);                         % keep the fields
            tc.verifyEqual(app.LastMeas.timestamp, meas.timestamp);
            tc.verifyEqual(app.LastRes.analysis.R, res.analysis.R, 'saved results shown, not recomputed');
            tc.verifyTrue(app.Saved); tc.verifyTrue(app.Opened);
            [~, nm] = fileparts(d);
            tc.verifyEqual(h.resultStatus.Text, ['Opened: ' nm]);
            tc.verifyEqual(h.L1.Value, L1, 'fields kept');
            tc.verifyNotEmpty(findobj(h.axR, 'Type', 'line'), 'result views drawn');
            tc.verifyEqual(h.reprocess.Enable, matlab.lang.OnOffSwitchState.on);
            log = strjoin(cellstr(h.log.Value), newline);
            tc.verifySubstring(log, 'specimen "demo", SIMULATED DATA');
            g = c.geometry;
            tc.verifySubstring(log, sprintf('IMPEDANCE TUBE fields kept; the saved results used D 29, s1 29, L1 %g,', ...
                round(1e3 * (g.xFront - g.micPositions(2)), 3)));
            app.openMeasurement(fullfile(d, 'raw.mat'), true);      % file given; saved set-up into the fields
            g = app.currentGeometry();
            tc.verifyEqual(g.micPositions, c.geometry.micPositions, 'AbsTol', 1e-12);
            % Reprocess -> new results, not saved; Save -> a NEW folder; raw.mat unchanged
            feval(h.reprocess.ButtonPushedFcn, h.reprocess, []);
            tc.verifyFalse(app.Saved); tc.verifySubstring(h.resultStatus.Text, 'not saved');
            feval(h.save.ButtonPushedFcn, h.save, []);
            tc.verifyTrue(app.Saved); tc.verifyFalse(app.Opened);
            tc.verifyNotEqual(app.SavedDir, d);
            tc.verifySubstring(h.resultStatus.Text, 'Saved: ');
            raw1 = dir(fullfile(d, 'raw.mat'));
            tc.verifyEqual([raw1.bytes raw1.datenum], [raw0.bytes raw0.datenum], 'opened raw.mat unchanged');
            % a folder without raw.mat: message only, the measurement shown is kept
            before = app.LastMeas.timestamp;
            app.openMeasurement(tc.tmp);
            tc.verifyEqual(app.LastMeas.timestamp, before);
            tc.verifySubstring(strjoin(cellstr(h.log.Value), newline), 'Open measurement: No raw.mat in');
            tc.verifyEqual(h.save.Enable, matlab.lang.OnOffSwitchState.on, 'controls unlocked again');
        end

        function windowTitleMenusAndAbout(tc)
            % user request 2026-10-09: version and repository in Help > About of a
            % menu bar (as in other programs) instead of a footer; tab "Formula"
            n0 = numel(findall(groot, 'Type', 'figure'));
            app = tim.gui.TubeApp('', 'Visible', 'off'); tc.addTeardown(@() delete(app));
            tc.verifyEqual(numel(findall(groot, 'Type', 'figure')), n0 + 1, 'hidden window: no start window');
            tc.verifyEmpty(app.StartSteps);
            tc.verifyEqual(app.Fig.Name, 'tubebench', 'program name (user decision 2026-10-10)');
            top = findall(app.Fig, 'Type', 'uimenu', 'Parent', app.Fig);
            tc.verifyEqual(sort({top.Text}), {'File', 'Help'});
            file = top(strcmp({top.Text}, 'File'));
            tc.verifyEqual(flip({file.Children.Text}), {'Open measurement…', 'Load configuration…', ...
                'Save configuration…', 'Exit'}, 'File menu');
            tc.verifyEmpty(findall(app.Fig, 'Type', 'uihyperlink'), 'no footer link any more');
            tc.verifyEqual(app.H.formulaTab.Title, 'Formula');
            % user request 2026-10-09: tabs grouped by the workflow (major tab > sub tab)
            tc.verifyEqual({app.H.tabs.Children.Title}, {'Setup', 'Calibration', 'Measurement', 'Results', 'Formula'});
            tc.verifyEqual({app.H.setupTabs.Children.Title}, {'Connection', 'Tube setup'});
            tc.verifyEqual({app.H.measTabs.Children.Title}, {'Time signals', 'Spectrum', 'Transfer functions'});
            tc.verifyEqual({app.H.resTabs.Children.Title}, {'Reflection and transmission', 'Transmission loss', ...
                'Transfer impedance', 'Validity'});
            feval(app.H.mAbout.MenuSelectedFcn, app.H.mAbout, []);
            fig = app.AboutFig; tc.addTeardown(@() delete(fig));
            tc.verifyEqual(fig.Name, 'About tubebench');
            txt = strjoin(app.H.aboutText.Value, newline);
            [~, info] = tim.app.softwareVersion();
            tc.verifySubstring(txt, info.version);
            tc.verifySubstring(txt, info.commit);
            tc.verifyEqual(app.H.aboutLink.URL, tim.app.repositoryUrl());
            % user request 2026-10-09: link to the author's portfolio site
            tc.verifyEqual(app.H.aboutPortfolio.URL, 'https://kimwoongji.github.io');
            tc.verifyEqual(app.H.aboutPortfolio.Text, 'Portfolio – kimwoongji.github.io');
            % user choice 2026-10-10: the light mark left of the name; window icons
            tc.verifyEqual(app.H.aboutLogo.ImageSource, tim.gui.logo(), 'About: light mark (SVG)');
            tc.verifyEqual(app.H.aboutLogo.Parent.ColumnWidth{1}, 46);
            tc.verifyEqual(fig.Icon, tim.gui.logo('icon'), 'About window icon');
            tc.verifyEqual(app.Fig.Icon, tim.gui.logo('icon'), 'main window icon');
            feval(app.H.mAbout.MenuSelectedFcn, app.H.mAbout, []);
            tc.verifyNumElements(findall(groot, 'Type', 'figure', 'Name', 'About tubebench'), 1, 'one About window');
        end

        function deferredViewsBuiltWhenOpened(tc)
            % user choice 2026-10-10 (progressive start-up, "A"): the window appears
            % with the control panel, the message pane, every tab and Setup >
            % Connection; a view opened before the background has prepared it is
            % prepared at once (major tab: its selected sub tab)
            n0 = numel(timerfindall);
            app = tim.gui.TubeApp(tc.labConfig(), 'Visible', 'off', 'Deferred', true, 'BuildDelay', 600);
            tc.addTeardown(@() delete(app));      % (600 s: the background queue does not start here)
            tc.verifyTrue(app.Deferred);
            for p = app.Parts
                tc.verifyEqual(app.PartState.(p{1}), 'none', p{1});
                tc.verifyFalse(app.isBuilt(p{1}), p{1});
            end
            tc.verifyFalse(isfield(app.H, 'axW') || isfield(app.H, 'axTube3D') || isfield(app.H, 'axCalSetup'));
            tc.verifyFalse(isfield(app.Pages, 'refl'));
            tc.verifyTrue(isvalid(app.H.chanTable) && isvalid(app.H.card(4).state), 'Connection view built');
            tc.verifyNumElements(app.ConnList.States, 9);
            tc.verifyEqual({app.H.tabs.Children.Title}, {'Setup', 'Calibration', 'Measurement', 'Results', 'Formula'});
            tc.verifyEqual({app.H.resTabs.Children.Title}, {'Reflection and transmission', 'Transmission loss', ...
                'Transfer impedance', 'Validity'});
            ph = app.H.placeholder;
            tc.verifyEqual(sort(fieldnames(ph)).', sort(app.Parts));
            tc.verifyEqual(ph.zt.Text, 'Preparing the view…');
            tc.verifyEqual(app.BuildTimer.Running, 'on');
            tc.verifyEqual(numel(timerfindall), n0 + 1, 'one timer: the background queue');
            % major tab Results -> its selected sub tab (Reflection and transmission)
            feval(app.H.tabs.SelectionChangedFcn, app.H.tabs, struct('NewValue', app.H.resTab, 'OldValue', app.H.setupTab));
            tc.verifyEqual(app.PartState.refl, 'ready');
            tc.verifyFalse(app.isBuilt('zt'), 'only the view that was opened');
            tc.verifyFalse(isvalid(ph.refl), 'placeholder removed');
            tc.verifyNotEmpty(findobj(app.H.axR(1), 'Tag', 'timEmptyState'), 'first drawing: empty state');
            feval(app.H.resTabs.SelectionChangedFcn, app.H.resTabs, struct('NewValue', app.H.ztTab, 'OldValue', app.H.reflTab));
            tc.verifyEqual(app.PartState.zt, 'ready');
            tc.verifyNumElements(app.H.axZ, 2);
            % Calibration: built, laid out, then its 3D model drawn (first opening)
            feval(app.H.tabs.SelectionChangedFcn, app.H.tabs, struct('NewValue', app.H.calTab, 'OldValue', app.H.resTab));
            tc.verifyEqual(app.PartState.cal, 'ready');
            tc.verifyEqual(app.CalDrawCount, 1, '3D calibration model drawn when the view is opened');
            tc.verifyEqual(app.H.calTg.RowHeight{1}, 116, 'bar height from the laid-out model width');
            tc.verifyNumElements(app.CalList.States, 1 + 3 * 3 + 2, 'operator steps listed');
            L = app.BuildLog;
            tc.verifyEqual(unique({L.part}), sort({'cal', 'refl', 'zt'}));
            tc.verifyTrue(all(strcmp({L.how}, 'tab')));
            % a method that needs a view prepares it (Tube setup: 3D model of the fields)
            app.ensureBuilt('tube');
            tc.verifyNotEmpty(findobj(app.H.axTube3D, 'Tag', 'specimen'), 'tube model drawn');
            tc.verifyError(@() app.ensureBuilt('nonsense'), 'tim:gui:part');
            delete(app);
            tc.verifyEqual(numel(timerfindall), n0, 'timer deleted with the window');
        end

        function deferredQueuePreparesEveryView(tc)
            % the background queue prepares every view, one step per timer tick,
            % with its first drawing; afterwards no timer is left
            n0 = numel(timerfindall);
            app = tim.gui.TubeApp(tc.labConfig(), 'Visible', 'off', 'Deferred', true, 'BuildDelay', 0);
            tc.addTeardown(@() delete(app));
            t0 = tic;
            while isnan(app.ReadyTime) && toc(t0) < 240, pause(0.1); end
            tc.assertFalse(isnan(app.ReadyTime), 'queue finished');
            for p = app.Parts, tc.verifyEqual(app.PartState.(p{1}), 'ready', p{1}); end
            tc.verifyEmpty(app.BuildQueue);
            tc.verifyEmpty(app.BuildTimer);
            tc.verifyEqual(numel(timerfindall), n0, 'timer deleted when the queue is done');
            tc.verifyEmpty(fieldnames(app.H.placeholder), 'every placeholder removed');
            h = app.H;
            tc.verifyNumElements(h.axW, 4); tc.verifyNumElements(h.axH, 3); tc.verifyNumElements(h.axR, 2);
            tc.verifyNumElements(h.axCal, 2);
            for f = {'axSpec', 'axTL', 'axV', 'axCalSetup', 'axTube3D', 'calText', 'secChk'}
                tc.verifyTrue(isvalid(h.(f{1})), f{1});
            end
            tc.verifyNotEmpty(findobj(h.axTube3D, 'Tag', 'specimen'), 'Tube setup: 3D model of the fields');
            tc.verifyNotEmpty(findobj(h.axW(1), 'Tag', 'timEmptyState'), 'Time signals: empty state');
            tc.verifyNotEmpty(findall(h.formulaTab, 'Type', 'uilabel', 'Interpreter', 'latex'), 'Formula built');
            tc.verifyEqual(h.calTg.RowHeight{1}, 116);
            L = app.BuildLog;
            tc.verifyTrue(all(strcmp({L.how}, 'background')));
            tc.verifyFalse(any([L.busy]), 'no background step during an action');
            tc.verifyEqual(sort(unique({L.part})), sort(app.Parts));
            c = {L(strcmp({L.stage}, 'construct')).part};
            tc.verifyEqual(c, app.Parts, 'order: Tube setup, Calibration, Measurement, Results, Formula');
            tc.verifySubstring(strjoin(cellstr(h.log.Value), newline), 'All views ready');
        end

        function measurementBeforeViewsAreReady(tc)
            % SAFETY: no background step while an action runs - a 1-3 s step would
            % stall the LAN-XI data stream. The measurement prepares the Time
            % signals view BEFORE it acquires; a tab opened during the measurement
            % is prepared only afterwards; views prepared later show the result.
            c = tim.app.defaultConfig(); c.mode = 'simulation'; c.geometry = c.simulation.Geometry;
            c.output.dataDir = fullfile(tc.tmp, 'data'); c.output.calibrationDir = fullfile(tc.tmp, 'cal');
            c.excitation.sweep.duration = 2; c.excitation.sweep.repetitions = 2;
            file = fullfile(tc.tmp, 'cfg.json'); tim.app.saveConfig(c, file);
            app = tim.gui.TubeApp(file, 'Visible', 'off', 'Deferred', true, 'BuildDelay', 0.2);
            tc.addTeardown(@() delete(app));
            h = app.H;
            feval(h.connect.ButtonPushedFcn, h.connect, []);
            tc.assertTrue(app.Session.Prepared);
            % a tab opened during the measurement (timer callback = like a click
            % processed inside the acquisition loop)
            seen = struct('busy', false, 'built', true, 'text', '');
            function openTab()
                seen.busy = app.Busy;
                feval(h.resTabs.SelectionChangedFcn, h.resTabs, struct('NewValue', h.validTab, 'OldValue', h.reflTab));
                seen.built = app.isBuilt('valid');
                if isfield(app.H.placeholder, 'valid'), seen.text = app.H.placeholder.valid.Text; end
            end
            opener = timer('StartDelay', 1.5, 'TimerFcn', @(~, ~) openTab());
            tc.addTeardown(@() delete(opener));
            start(opener);
            feval(h.start.ButtonPushedFcn, h.start, []);
            tc.assertNotEmpty(app.LastRes, 'measurement completed');
            L = app.BuildLog;
            w = L(strcmp({L.part}, 'wave') & strcmp({L.stage}, 'construct'));
            tc.verifyEqual(w.how, 'action', 'Time signals prepared by the measurement itself');
            tc.verifyEqual(w.busyWhat, 'measurement');
            tc.verifyEqual(app.H.axW(1).YLabel.String, 'ch1 (M1) [Pa]', 'live view used');
            tc.verifyTrue(seen.busy, 'the tab was opened during the measurement');
            tc.verifyFalse(seen.built, 'not prepared during the measurement');
            tc.verifyEqual(seen.text, 'This view is prepared when the running action has finished.');
            tc.verifyGreaterThan(app.BuildSkips, 0, 'background ticks came during the actions and waited');
            t0 = tic;
            while isnan(app.ReadyTime) && toc(t0) < 240, pause(0.1); end
            tc.assertFalse(isnan(app.ReadyTime), 'queue finished');
            L = app.BuildLog;
            bg = L(strcmp({L.how}, 'background'));
            tc.verifyFalse(any([bg.busy]), 'no background step while an action ran');
            v = L(strcmp({L.part}, 'valid') & strcmp({L.stage}, 'construct'));
            tc.verifyEqual(v.how, 'background');
            % views prepared after the measurement show its result (data of then)
            tc.verifyNotEmpty(findobj(app.H.axR, 'Type', 'line'), 'Reflection view: result drawn');
            tc.verifyNotEmpty(findobj(app.H.axSpec, 'Type', 'line'), 'Spectrum view: measurement drawn');
            tc.verifyEmpty(findobj(app.H.axR, 'Tag', 'timEmptyState'));
        end

        function closeWhileViewsArePrepared(tc)
            % closing the window during the background preparation: no error, no
            % timer left (the timer belongs to the window)
            n0 = numel(timerfindall);
            app = tim.gui.TubeApp('', 'Visible', 'off', 'Deferred', true, 'BuildDelay', 0);
            fig = app.Fig;
            tc.addTeardown(@() delete(fig(isvalid(fig))));
            t0 = tic;
            while numel(app.BuildLog) < 3 && toc(t0) < 60, pause(0.05); end
            tc.assertTrue(isnan(app.ReadyTime), 'still preparing');
            tc.verifyWarningFree(@() closeAndWait(fig, app));
            tc.verifyFalse(isvalid(app)); tc.verifyFalse(isvalid(fig));
            tc.verifyEmpty(timerfindall('Name', 'tubebench-build'));
            tc.verifyEqual(numel(timerfindall), n0, 'no timer left');
        end
    end

    methods
        function file = labConfig(tc)
            % lab geometry (L1, d, L2 entered): the 3D model has a specimen
            c = tim.app.defaultConfig();
            c.geometry.xFront = 0; c.geometry.xRear = 0.075;
            c.geometry.micPositions = [-0.070 -0.041 0.116 0.145];
            file = fullfile(tc.tmp, 'lab.json'); tim.app.saveConfig(c, file);
        end
    end
end

function closeAndWait(fig, app)
tim.gui.closeApp(fig, app);
pause(0.5);                     % a pending timer tick would run here
end

function L = labels(ax)
t = findobj(ax, 'Type', 'text');
L = cellfun(@(s) strjoin(cellstr(s), ' '), get(t, 'String'), 'UniformOutput', false);
end
