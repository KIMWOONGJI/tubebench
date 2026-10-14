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
            tc.verifyEqual(sw.H.site.Text, 'kimwoongji.github.io', 'author site (user request 2026-10-10)');
            tc.verifyClass(sw.H.site, 'matlab.ui.control.Hyperlink');
            tc.verifyEqual(sw.H.site.URL, 'https://kimwoongji.github.io', 'site is a link');
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
            tc.verifyError(@() tim.gui.Tubebench(fullfile(tc.tmp, 'missing.json')), 'tim:io:open');
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
            % BuildDelay 600 s: the background preparation of the views does not
            % start during this test. Its 1-3 s steps would run inside the dialog's
            % opening and its wait (they take MATLAB's event loop), so the counting
            % timer got only 3 ticks in 2.5 s and the close came while uiconfirm
            % was still opening the dialog (2026-10-11, loaded PC)
            app = tim.gui.Tubebench('', 'Visible', 'on', 'BuildDelay', 600);
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
            t0 = tic;
            closer = timer('StartDelay', 2.5, 'UserData', NaN, ...
                'TimerFcn', @(t, ~) closeAndStamp(t, app, t0));
            tc.addTeardown(@() delete([tick closer]));
            tc.addTeardown(@() stop([tick closer]));
            start(tick); start(closer);
            sel = app.ask('Move the microphones', 'Step', {'Done', 'Abort'}, 1, 2, 'question');
            tReturned = toc(t0);
            stop(tick);
            tc.verifyEqual(sel, 'Abort');
            % Timed: only what this test guards - from the moment the window is
            % gone (end of the close request, which deletes it) to the return of
            % ask(). Its wait loop checks the window at every poll (pause 0.1 s),
            % so it returns at the next poll; 2 s (20 polls) leaves room for a
            % loaded PC and still fails a dialog that does not notice the closed
            % window. Not timed: the close itself (deleting the uifigure took
            % about 14 s on 2026-10-11 with 0.7 GB of free memory), which runs
            % inside the closer's callback and is not what ask() can influence.
            % Under load the close can also come while uiconfirm is still opening
            % the dialog (it lets timers run, e.g. a background view step): ask()
            % then returns the cancel option as well (found 2026-10-11, when
            % uiconfirm raised "invalid or deleted figure handle" in this test).
            tClosed = closer.UserData;
            tc.assertFalse(isnan(tClosed), 'the window was closed while the dialog waited');
            tc.verifyLessThan(tReturned - tClosed, 2, sprintf(['ask() returned %.2f s after the window was deleted ' ...
                '(close requested at %.1f s; returned at %.1f s)'], tReturned - tClosed, 2.5, tReturned));
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
            app = tim.gui.Tubebench(file, 'Visible', 'off'); tc.addTeardown(@() delete(app));
            ax = app.H.axCalSetup;
            tc.verifyEmpty(ax.Children, 'not drawn at start-up');
            tc.verifySubstring(strjoin(cellstr(app.H.calText.Text), ' '), 'Run switching calibration');
            app.drawCalSetup([], '', '');
            tc.verifyEqual(app.CalDrawCount, 1);
            tc.verifyEqual(numel(findobj(ax, 'Type', 'hgtransform')), 4);
            tc.verifyEqual(app.H.cal3D.portX, [-70 -41 116 145], 'AbsTol', 1e-9);
            app.drawCalSetup([], '', '');
            tc.verifyEqual(app.CalDrawCount, 1, 'no redraw when nothing changed');
            % a calibration step in which three microphones move (configuration II
            % of ch2 -> configuration I of ch3, ports a, b = M1, M2): the moves stay
            % as dashed arrows with rounded corners (owner request 2026-10-12;
            % tim.gui.calSwapPath, radius M.swapRadius)
            from = [2 1 3 4]; to = [1 3 2 4];
            app.drawCalSetup(to, 'move', 'step', from);
            app.animateCalMics(from, to);
            M = app.H.cal3D; z0 = M.zHandle + 2;
            tc.verifyEqual(app.CalDrawn, to);
            tc.verifyEqual(M.swapRadius, 11.6, 'AbsTol', 1e-9);
            tc.verifyNumElements(findobj(ax, 'Tag', 'calPath', 'Type', 'line'), 3, 'one dashed line per mover');
            tc.verifyNumElements(findobj(ax, 'Tag', 'calPath', 'Type', 'patch'), 3, 'one arrowhead per mover');
            tc.assertNumElements(app.H.calPaths, 6);
            for ch = 1:3                                     % movers ch1..ch3, in this order
                l = app.H.calPaths(2 * ch - 1); a = app.H.calPaths(2 * ch);
                x = l.XData(:); z = l.ZData(:);
                tc.verifyEqual([x(1) z(1)], [M.portX(from(ch)) z0], 'AbsTol', 1e-9, 'starts above the old port');
                tc.verifyEqual([x(end) z(end)], [M.portX(to(ch)) z0], 'AbsTol', 1e-9, 'ends at the new port');
                tc.verifyGreaterThanOrEqual(min(z), z0 - 1e-9, 'never below the start');
                tc.verifyEqual(max(z), M.zHandle + M.lift(ch), 'AbsTol', 1e-9, 'own height per mover');
                tc.verifyGreaterThan(numel(x), 4, 'rounded corners');
                d = diff([x z]); d = d(any(d ~= 0, 2), :);
                turn = atan2d(abs(d(1:end - 1, 1) .* d(2:end, 2) - d(1:end - 1, 2) .* d(2:end, 1)), ...
                    sum(d(1:end - 1, :) .* d(2:end, :), 2));
                tc.verifyLessThanOrEqual(max(turn), 6, 'turning per segment');
                tc.verifyEqual(mean(a.XData), M.portX(to(ch)), 'AbsTol', 1e-9, 'arrowhead at the new port');
                tc.verifyEqual(min(a.ZData), z0, 'AbsTol', 1e-9);
                T = M.micGroup(ch).Matrix;
                tc.verifyEqual(M.micX0(ch) + T(1, 4), M.portX(to(ch)), 'AbsTol', 1e-9);
                tc.verifyEqual(T(2:3, 4), [0; 0], 'AbsTol', 1e-9, 'lowered into the new port');
            end
            tc.verifyEqual(M.micGroup(4).Matrix, eye(4), 'ch4 stays');
        end

        function fileOfVersion110WithLevelsBelowTheMinimum(tc)
            % the window of 1.1.0 went down to 0.005 Vpk and wrote 0.01 Vpp into
            % all three signals: such a file still opens the window (a warning:
            % below the 33220A minimum of 20 mVpp at load INF), the amplitude
            % field starts at the generator's smallest level, and Connect then
            % works with the levels of the fields
            c = tim.app.defaultConfig(); c.mode = 'simulation';
            c.output.dataDir = fullfile(tc.tmp, 'data'); c.output.calibrationDir = fullfile(tc.tmp, 'cal');
            file = fullfile(tc.tmp, 'cfg.json'); tim.app.saveConfig(c, file);
            u = jsondecode(tim.app.readTextUtf8(file));
            for s = {'sweep', 'stepped', 'noise'}, u.excitation.(s{1}).amplitudeVpp = 0.01; end
            fid = fopen(file, 'w', 'n', 'UTF-8'); fwrite(fid, unicode2native(jsonencode(u), 'UTF-8')); fclose(fid);
            app = tc.verifyWarning(@() tim.gui.Tubebench(file, 'Visible', 'off'), 'tim:config:amplitude');
            tc.addTeardown(@() delete(app));
            tc.verifyEqual(app.H.amp.Value, 0.01, 'AbsTol', 1e-12, 'the smallest level of the generator, in Vpk');
            feval(app.H.connect.ButtonPushedFcn, app.H.connect, []);
            s = app.Session;
            tc.assertNotEmpty(s, 'connected');
            tc.verifyTrue(s.Connected);
            ex = s.Cfg.excitation;
            tc.verifyEqual([ex.sweep.amplitudeVpp ex.stepped.amplitudeVpp ex.noise.amplitudeVpp], [0.02 0.02 0.02], ...
                'AbsTol', 1e-12, 'the levels of the fields');
        end

        function closeShowsStepsAndDisconnects(tc)
            % user request 2026-10-09: closing was slow without feedback. The
            % window disappears at once, a small window shows the steps, the
            % instruments are released and everything is deleted.
            c = tim.app.defaultConfig(); c.mode = 'simulation';
            c.output.dataDir = fullfile(tc.tmp, 'data'); c.output.calibrationDir = fullfile(tc.tmp, 'cal');
            file = fullfile(tc.tmp, 'cfg.json'); tim.app.saveConfig(c, file);
            app = tim.gui.Tubebench(file, 'Visible', 'off'); tc.addTeardown(@() delete(app));
            feval(app.H.connect.ButtonPushedFcn, app.H.connect, []);
            s = app.Session; fig = app.Fig;
            tc.assertTrue(s.Connected);
            t0 = tic;
            stamps = stampLog(s, t0);
            tim.gui.closeApp(fig, app);
            tAll = toc(t0);
            tc.verifyFalse(isvalid(app)); tc.verifyFalse(isvalid(fig));
            tc.verifyFalse(s.Connected, 'instruments released');
            % Timed: only the closing steps this test guards - from the close
            % request to the last step, "Closing: window deleted.", logged right
            % before the window is deleted. closeNow waits at most for the
            % read-back of the generator output (isOutputOn, 1 s time-out) and, in
            % close(true), for one unanswered request per instrument at the
            % shortened 2 s time-out before it gives up on it; the mocks answer
            % every request at once. A close that takes longer than these
            % time-outs together (1 + 2 x 2 s) waited for something that never
            % answers. Not timed: deleting the window after that step (a uifigure
            % with every view; about 14 s on 2026-10-11 with 0.7 GB of free
            % memory, when the former limit of 10 s on the whole call failed at
            % 16.3 s although the steps took about 1 s).
            tSteps = stampOf(stamps, 'Closing: window deleted.');
            tc.verifyLessThan(tSteps, 1 + 2 * 2, sprintf(['closing steps took %.2f s (the whole call, deleting ' ...
                'the window included: %.1f s)'], tSteps, tAll));
            % the steps shown in the closing dialog are also logged by the session
            tc.verifyTrue(any(contains(s.LogLines, 'Closing: Generator output off (confirmed).')));
            tc.verifyTrue(any(contains(s.LogLines, 'Closing: Instruments disconnected.')));
            tc.verifyTrue(any(contains(s.LogLines, 'Closing: window deleted.')));
        end

        function closeDuringMeasurementStopsFirst(tc)
            % a close request while a measurement runs stops it first, then closes.
            % The request comes from INSIDE the acquisition (review 2026-10-11: the
            % former 1 s timer fired while the window was still preparing the
            % measurement, so the session stopped before 'Swept sine' and no
            % acquisition was running): from the session's block callback, once
            % the virtual rig has produced the pre-roll and a third of the sweep
            % of repetition 1 - a fixed sample count, as TestBusTraffic's
            % atSample, independent of the wall clock.
            c = tim.app.defaultConfig(); c.mode = 'simulation';
            c.geometry = c.simulation.Geometry;
            c.output.dataDir = fullfile(tc.tmp, 'data'); c.output.calibrationDir = fullfile(tc.tmp, 'cal');
            c.excitation.sweep.duration = 3; c.excitation.sweep.repetitions = 4;
            file = fullfile(tc.tmp, 'cfg.json'); tim.app.saveConfig(c, file);
            app = tim.gui.Tubebench(file, 'Visible', 'off'); tc.addTeardown(@() delete(app));
            feval(app.H.connect.ButtonPushedFcn, app.H.connect, []);
            s = app.Session; fig = app.Fig;
            tc.assertNotEmpty(s.Rig, 'simulation: the virtual rig counts the samples');
            sw = s.Cfg.excitation.sweep;
            n = round((sw.preRoll + sw.duration / 3) * s.Cfg.acquisition.sampleRate);
            t0 = tic;
            stamps = stampLog(s, t0);
            at = struct('first', NaN, 't', NaN, 'samples', NaN, 'log', {{}});
            live = s.BlockCallback;                        % the window's live view (keeps it as in use)
            s.BlockCallback = @closeInside;
            feval(app.H.start.ButtonPushedFcn, app.H.start, []);   % returns when stopped + closed
            tAll = toc(t0);
            tc.assertFalse(isnan(at.t), 'the close was requested inside the acquisition');
            tc.verifyTrue(any(contains(at.log, 'Swept sine')), 'the measurement had started');
            tc.verifyFalse(any(contains(at.log, 'Repetition 1:')), 'during repetition 1');
            tc.verifyGreaterThanOrEqual(at.samples, n, 'after the pre-roll: the sweep was running');
            % Timed: only what this test guards - from the close request to the
            % last closing step ("Closing: window deleted.", logged right before
            % the window is deleted): the acquisition stops at its next block, the
            % stopped action reads the generator output back and draws the last
            % result again, and the window closes as in
            % closeShowsStepsAndDisconnects. The mocks answer at once, so no
            % time-out is involved: this is window processing, about 2 s on the
            % lab laptop (2026-10-11); 6 s leaves room for a loaded PC. The
            % simulated acquisition runs faster than real time, so the time is
            % no proof that the measurement was stopped - the missing
            % 'Repetition 1:' line below is. Not timed: the preparation before
            % the request and deleting the window afterwards (the former limit
            % of 20 s on the whole Start call failed at 20.1 s on 2026-10-11
            % under memory pressure).
            tSteps = stampOf(stamps, 'Closing: window deleted.');
            tc.verifyLessThan(tSteps - at.t, 6, sprintf(['close request at %.1f s, last closing step %.2f s later ' ...
                '(the whole Start call, deleting the window included: %.1f s)'], at.t, tSteps - at.t, tAll));
            tc.verifyTrue(s.StopRequested, 'the running measurement was stopped first');
            tc.verifyFalse(isvalid(app)); tc.verifyFalse(isvalid(fig));
            tc.verifyFalse(s.Connected);
            tc.verifyTrue(any(contains(s.LogLines, 'Closing: window close requested while busy - STOP requested first.')));
            tc.verifyTrue(any(contains(s.LogLines, 'Error during swept sine, repetition 1: Measurement stopped by user.')), ...
                'stopped inside the acquisition of repetition 1 (its error path: output off, partial data kept)');
            tc.verifyTrue(any(contains(s.LogLines, 'Closing: Generator output off (confirmed).')));
            tc.verifyTrue(any(contains(s.LogLines, 'Closing: Instruments disconnected.')));
            % stopped inside repetition 1: it never completed (a close that waited
            % for the measurement would log 'Repetition 1:' ... 'Repetition 4:')
            tc.verifyFalse(any(contains(s.LogLines, 'Repetition 1:')), strjoin(s.LogLines, newline));
            function closeInside()
                if isnan(at.first) && any(contains(s.LogLines, 'Swept sine'))
                    at.first = s.Rig.SampleCounter;                 % the sweep measurement has started
                end
                if isnan(at.t) && ~isnan(at.first) && s.Rig.SampleCounter - at.first >= n
                    at.t = toc(t0); at.samples = s.Rig.SampleCounter - at.first; at.log = s.LogLines;
                    tim.gui.closeApp(fig, app);                     % first close request: during the acquisition
                end
                if ~isempty(live), live(); end
            end
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
            app = tim.gui.Tubebench(file, 'Visible', 'off'); tc.addTeardown(@() delete(app));
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
            app = tim.gui.Tubebench(file, 'Visible', 'off');
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

        function combinedDeviceAppSimulationWorkflow(tc)
            % WO-001 section 0 change B: the simulated combined device (one object
            % for generator and DAQ, shared clock, block acquisition, no TEDS)
            % selected in the configuration only; the hidden window connects,
            % calibrates and measures with it - its checklist, lamps and cards
            % come from the driver, the window has no code for it
            c = tim.app.defaultConfig();
            c.mode = 'simulation';
            c.generator.driver = 'simcombined'; c.daq.driver = 'simcombined';
            c.geometry = c.simulation.Geometry;
            c.output.dataDir = fullfile(tc.tmp, 'data');
            c.output.calibrationDir = fullfile(tc.tmp, 'cal');
            c.excitation.sweep.duration = 3; c.excitation.sweep.repetitions = 2;
            c.calibration.repeatConfigI = false;
            sens = [11.2 11.5 10.9 11.3] * 1e-3;     % no TEDS: certificate sensitivities
            for i = 1:4, c.mics(i).certificateSensitivity_VperPa = sens(c.mics(i).channel); end
            file = fullfile(tc.tmp, 'cfg.json');
            tim.app.saveConfig(c, file);
            app = tim.gui.Tubebench(file, 'Visible', 'off');
            cleanup = onCleanup(@() delete(app));
            h = app.H;
            feval(h.connect.ButtonPushedFcn, h.connect, []);
            s = app.Session;
            tc.assertNotEmpty(s, 'connected');
            tc.verifySameHandle(s.Gen, s.Daq, 'one object in both roles');
            tc.verifyEqual(app.ConnList.Keys, {'device', 'setup', 'sens', 'settle', 'signal'}, 'the driver''s steps');
            tc.verifyTrue(all(ismember(app.ConnList.States, {'ok', 'skip'})), strjoin(app.ConnList.States, ' '));
            P = tim.gui.palette();
            tc.verifyEqual(vertcat(h.lamp.Color), repmat(P.ok, 6, 1), 'all lamps green');
            tc.verifyEqual(h.card(3).state.Text, 'OK');
            tc.verifySubstring(h.connHead.Text, 'all checks passed');
            feval(h.runCal.ButtonPushedFcn, h.runCal, []);
            tc.verifyTrue(all(strcmp(app.CalList.States, 'ok')), strjoin(app.CalList.States, ' '));
            tc.verifySubstring(app.CalList.Details(end - 1).Text, 'passed', 'Test E verdict on the done row');
            tc.verifySubstring(h.calLabel.Text, 'CAL-');
            tc.verifyFalse(contains(h.calLabel.Text, 'check'), 'the calibration fits the connected device');
            feval(h.start.ButtonPushedFcn, h.start, []);
            tc.verifyNotEmpty(app.LastRes);
            tc.verifyEqual(app.LastMeas.metadata.daq.driver, 'simcombined');
            tc.verifyEqual(h.axW(1).YLabel.String, 'ch1 (M1) [Pa]');
            tc.verifyFalse(s.Gen.isOutputOn());
            % closing: the output state worded by the read-back kind of the device
            fig = app.Fig;
            tim.gui.closeApp(fig, app);
            tc.verifyFalse(isvalid(app)); tc.verifyFalse(isvalid(fig));
            tc.verifyTrue(any(contains(s.LogLines, 'Closing: Generator output stopped (device idle, 0 V).')), ...
                strjoin(s.LogLines(max(1, end - 4):end), newline));
            tc.verifyFalse(s.Connected);
            clear cleanup
        end

        function instrumentsShownFromTheDrivers(tc)
            % WO-001 section 0.2: no instrument selector; the window shows which
            % instruments are in use - before connecting the display names of the
            % configured drivers, after connecting the identity the instruments
            % reported (model, serial number, firmware) - in INSTRUMENTS (lamps,
            % "In use") and in Setup > Connection. The two lab drivers on their
            % protocol mocks keep today's texts and lamp labels.
            c = tim.app.defaultConfig();
            c.mode = 'simulation';
            c.geometry = c.simulation.Geometry;
            file = fullfile(tc.tmp, 'cfg.json');
            tim.app.saveConfig(c, file);
            app = tim.gui.Tubebench(file, 'Visible', 'off');
            cleanup = onCleanup(@() delete(app));
            h = app.H;
            g = tim.instr.driverInfo('keysight33220a'); d = tim.instr.driverInfo('lanxi');
            names = [g.displayName newline d.displayName];      % one line per instrument
            % before connecting: the configured drivers
            tc.verifyEqual({h.lampLabel.Text}, {'Generator', 'DAQ', 'ch1', 'ch2', 'ch3', 'ch4'});
            % the checklist: each driver step after the lamp label of its role (owner, 2026-10-13)
            tc.verifyEqual({app.ConnList.Labels(1:6).Text}, {'Generator: connect (33220A, SCPI)', ...
                'DAQ: connect (LAN-XI, REST)', 'DAQ: recorder state Idle', 'DAQ: open recorder', ...
                'DAQ: TEDS detection', 'DAQ: channel setup → streaming'});
            tc.verifyEqual(h.instr.Text, names);
            tc.verifySubstring(h.lamp(1).Tooltip, g.displayName);
            tc.verifySubstring(h.lamp(2).Tooltip, d.displayName);
            T = h.instrTable.Data;
            tc.verifyEqual(T(:, 1:3), {'Generator (signal source)', g.displayName, 'keysight33220a'; ...
                'DAQ (acquisition)', d.displayName, 'lanxi'});
            tc.verifyEqual(T(:, 4:7), repmat({'–'}, 2, 4), 'no identity before connecting');
            tc.verifyEqual(T{2, 8}, '16384 S/s, 10 Vpeak, high-pass 0.7 Hz, CCLD on');
            tc.verifySubstring(h.instrTable.Tooltip, '4096, 8192, 16384, 32768, 65536', 'rates the driver allows');
            % the texts of before for the lab drivers, composed from describe().texts
            tc.verifyEqual(h.connect.Tooltip, ['Connect the generator and the DAQ (generator output off), ' ...
                'read TEDS and check every channel (Setup > Connection).']);
            tc.verifyEqual(h.disconnect.Tooltip, 'Generator output off, DAQ back to Idle, connections closed.');
            tc.verifyEqual(h.modeLabel.Tooltip, 'Simulation: virtual tube for practice. Hardware: generator and DAQ.');
            % EXCITATION limits from the capabilities
            tc.verifyEqual(h.fStop.Limits, [1, 0.45 * c.acquisition.sampleRate]);
            tc.verifyEqual(h.amp.Limits(1), 0.01, 'AbsTol', 1e-12, '33220A: 20 mVpp at load INF');
            tc.verifyEqual(h.dur.Limits, [0.001 500], '33220A sweep times');
            % connected: the identity the instruments reported
            feval(h.connect.ButtonPushedFcn, h.connect, []);
            s = app.Session;
            tc.assertNotEmpty(s, 'connected');
            ig = s.Gen.identity(); id = s.Daq.identity();
            tc.verifyEqual({ig.model, ig.serial, id.model, id.serial}, {'33220A', 'MOCK0001', '3676-B-040', '110283'}, ...
                'identities of the protocol mocks');
            T = h.instrTable.Data;
            tc.verifyEqual(T(1, 4:7), {ig.vendor, ig.model, ig.serial, ig.firmware});
            tc.verifyEqual(T(2, 4:7), {id.vendor, id.model, id.serial, id.firmware});
            tc.verifyEqual(h.instr.Text, sprintf('Generator: 33220A s/n MOCK0001 (simulated)\nDAQ: 3676-B-040 s/n 110283 (simulated)'));
            tc.verifySubstring(h.lamp(1).Tooltip, sprintf('%s 33220A, s/n MOCK0001, firmware %s', ig.vendor, ig.firmware));
            tc.verifySubstring(h.lamp(2).Tooltip, sprintf('s/n 110283, firmware %s', id.firmware));
            tc.verifyEqual(h.lamp(1).Tooltip, app.LampTips{1}, 'kept after the action');
            % disconnected: the configured drivers again
            feval(h.disconnect.ButtonPushedFcn, h.disconnect, []);
            tc.verifyEqual(h.instr.Text, names);
            tc.verifyEqual(h.instrTable.Data(:, 5), {'–'; '–'});
            tc.verifyTrue(any(endsWith(h.log.Value, ...
                'Instruments disconnected by the operator (generator output off, DAQ back to Idle).')));
            clear cleanup
        end

        function combinedDeviceShownFromItsDriver(tc)
            % the simulated combined device (one object in both roles): one row of
            % the Instruments table, its lamp labels, checklist, texts and limits
            % before connecting and its identity after - all from its driver
            c = tim.app.defaultConfig();
            c.mode = 'simulation';
            c.generator.driver = 'simcombined'; c.daq.driver = 'simcombined';
            c.geometry = c.simulation.Geometry;
            file = fullfile(tc.tmp, 'cfg.json');
            tim.app.saveConfig(c, file);
            app = tim.gui.Tubebench(file, 'Visible', 'off');
            cleanup = onCleanup(@() delete(app));
            h = app.H;
            d = tim.instr.driverInfo('simcombined');
            tc.verifyEqual({h.lampLabel(1:2).Text}, {'Output', 'Inputs'});
            tc.verifyEqual(app.ConnList.Keys, {'device', 'setup', 'sens', 'settle', 'signal'}, 'checklist before connecting');
            tc.verifyEqual({app.ConnList.Labels(1:2).Text}, {'Output + Inputs: connect (simulated device)', ...
                'Inputs: channel setup'}, 'a step of both roles after both lamp labels');
            tc.verifyEqual(h.instr.Text, d.displayName);
            T = h.instrTable.Data;
            tc.verifySize(T, [1 8], 'one device');
            tc.verifyEqual(T(1, 1:3), {'Output + Inputs (both roles)', d.displayName, 'simcombined'});
            tc.verifyEqual(h.connect.Tooltip, 'Connect the simulated device (output off) and check every channel (Setup > Connection).');
            tc.verifyEqual(h.disconnect.Tooltip, 'Simulated device stopped, output at 0 V, connections closed.');
            for t = {h.modeLabel.Tooltip, h.connect.Tooltip, h.disconnect.Tooltip, h.instr.Tooltip, h.lamp(1).Tooltip, ...
                    h.lamp(2).Tooltip, h.instrTable.Tooltip}
                tc.verifyFalse(contains(t{1}, {'LAN-XI', '33220'}), t{1});
            end
            tc.verifyEqual(h.amp.Limits(1), 0.0005, 'AbsTol', 1e-12, 'its smallest level (1 mVpp)');
            tc.verifyEqual(h.dur.Limits, [0.1 300], 'its sweep times');
            feval(h.connect.ButtonPushedFcn, h.connect, []);
            s = app.Session;
            tc.assertNotEmpty(s, 'connected');
            id = s.Gen.identity();
            tc.verifyEqual({id.model, id.serial, id.firmware}, {'SIM-1AO-4AI', 'SIM-0001', '1.0'});
            tc.verifyEqual(h.instrTable.Data(1, 4:7), {id.vendor, id.model, id.serial, id.firmware});
            tc.verifyEqual(h.instr.Text, 'Output + Inputs: SIM-1AO-4AI s/n SIM-0001 (simulated)');
            tc.verifySubstring(h.lamp(1).Tooltip, 'SIM-1AO-4AI, s/n SIM-0001, firmware 1.0');
            tc.verifySubstring(h.lamp(2).Tooltip, 'SIM-1AO-4AI, s/n SIM-0001, firmware 1.0');
            clear cleanup
        end

        function noInstrumentNamesInWindowOrSession(tc)
            % WO-001 acceptance: the window and the session name no instrument;
            % every such text comes from the drivers (grep lanxi / lan-xi / 33220)
            for f = {fullfile('+tim', '+gui', 'Tubebench.m'), fullfile('+tim', '+app', 'MeasurementSession.m')}
                lines = strsplit(tim.app.readTextUtf8(fullfile(tim.app.projectRoot(), f{1})), newline);
                hit = find(~cellfun(@isempty, regexpi(lines, 'lanxi|lan-xi|33220', 'once')));
                tc.verifyEmpty(hit, sprintf('%s line(s) %s: %s', f{1}, mat2str(hit), strjoin(lines(hit), ' | ')));
            end
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
            app = tim.gui.Tubebench(file, 'Visible', 'off'); tc.addTeardown(@() delete(app));
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
            tc.assertNotEmpty(LH, 'relative responses drawn');      % all() of nothing would pass
            tc.verifyTrue(all(strcmp({LH.Marker}, 'o')), 'relative responses drawn as markers');
            % sweep afterwards: dense PSD, no markers, no stepped title
            h.exMode.Value = 'sweep'; feval(h.exMode.ValueChangedFcn, h.exMode, struct('PreviousValue', 'stepped'));
            feval(h.start.ButtonPushedFcn, h.start, []);
            L = findobj(h.axSpec, 'Type', 'line');
            tc.verifyTrue(all(strcmp({L.Marker}, 'none')));
            tc.verifyGreaterThan(max(arrayfun(@(l) numel(l.XData), L)), 1000);
            tc.verifyFalse(contains(strjoin(cellstr(h.axSpec.Title.String), ' '), 'Stepped'));
            LH = findobj(h.axH, 'Type', 'line');
            tc.assertNotEmpty(LH, 'relative responses drawn');
            tc.verifyTrue(all(strcmp({LH.Marker}, 'none')));
        end

        function tubeFieldsAreExactDistances(tc)
            % regression 2026-10-09: s1/s2 showed 29.000000000000004 / 28.999999999999986
            % while editing; Save config wrote 0.11599999999999999
            c = tim.app.defaultConfig();
            c.geometry.xFront = 0; c.geometry.xRear = 0.075;
            c.geometry.micPositions = [-0.070 -0.041 0.116 0.145];
            file = fullfile(tc.tmp, 'lab.json'); tim.app.saveConfig(c, file);
            app = tim.gui.Tubebench(file, 'Visible', 'off'); tc.addTeardown(@() delete(app));
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

        function analysisBandShownWithItsStandard(tc)
            % owner request 2026-10-13: the IMPEDANCE TUBE line says which standard
            % the analysis band follows; with analysis.bandMode 'geometry' the band
            % follows the tube fields (tim.app.analysisBand)
            c = tim.app.defaultConfig();
            file = fullfile(tc.tmp, 'fixed.json'); tim.app.saveConfig(c, file);
            app = tim.gui.Tubebench(file, 'Visible', 'off'); tc.addTeardown(@() delete(app));
            tc.verifySubstring(app.H.fLimits.Text, 'ASTM E1050/E2611 limits 118–4735 Hz');
            tc.verifySubstring(app.H.fLimits.Text, 'analysis band 120–4500 Hz (fixed)');
            tc.verifySubstring(app.H.fLimits.Tooltip, 'ASTM E1050 / E2611 limits of the tube');
            c.analysis.bandMode = 'geometry';
            file = fullfile(tc.tmp, 'geometry.json'); tim.app.saveConfig(c, file);
            app2 = tim.gui.Tubebench(file, 'Visible', 'off'); tc.addTeardown(@() delete(app2));
            h = app2.H;
            tc.verifySubstring(h.fLimits.Text, 'analysis band 120–4734 Hz (from the tube)');
            % wider microphone spacing in the fields: the band follows at once
            h.s1.Value = 40; h.s2.Value = 40; feval(h.s2.ValueChangedFcn, h.s2, []);
            air = tim.acoustics.airProperties(app2.Cfg.environment);
            f = [2 * ceil(0.01 * air.c / 0.04 / 2), 2 * floor(0.40 * air.c / 0.04 / 2)];
            tc.verifyEqual([app2.Cfg.analysis.fMin app2.Cfg.analysis.fMax], f);
            tc.verifySubstring(h.fLimits.Text, sprintf('analysis band %g–%g Hz (from the tube)', f));
            app2.ensureBuilt('tube');
            T = app2.Pages.tube.SummaryTable.Data;
            tc.verifyTrue(any(strcmp(T(:, 2), sprintf('%g–%g Hz (from the tube)', f))), 'Tube setup table');
        end

        function leftPanelFitsWithoutScrolling(tc)
            % user request 2026-10-09: no scrolling in the control panel on the lab screen
            % (window = work area of the 1920 x 1080 lab laptop screen: about 975 px inside the title and menu bars)
            app = tim.gui.Tubebench('', 'Visible', 'off'); tc.addTeardown(@() delete(app));
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
                    'ampModel','ampGain','genLoad','spkZ','spkP','ampAt','start','stop','background','tubeD','s1','L1','dTh','L2','s2', ...
                    'temp','pres','loadCal','runCal','save','reprocess','status','drive','drivePath','driveMax','spkState','genState','fLimits','calLabel', ...
                    'specimen','resultStatus','durEst','instr','ampRms','genLoadLabel','method'}
                tc.verifyTrue(isfield(app.H, n{1}) && isvalid(app.H.(n{1})), n{1});
            end
        end

        function steppedFieldsFollowTheMode(tc)
            % before 2026-10-09 f start/stop, duration and repetitions reached only the sweep
            app = tim.gui.Tubebench('', 'Visible', 'off'); tc.addTeardown(@() delete(app));
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
            app = tim.gui.Tubebench(file, 'Visible', 'off'); tc.addTeardown(@() delete(app));
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
            app = tim.gui.Tubebench(file, 'Visible', 'off'); tc.addTeardown(@() delete(app));
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
            % audit 2026-10-11: saved again without Reprocess - the new folder's
            % config.json describes its result.mat (the opened set-up), not the
            % window's set-up (L1 9 mm longer)
            feval(h.save.ButtonPushedFcn, h.save, []);
            dAgain = app.SavedDir;
            tc.assertNotEqual(dAgain, d);
            cAgain = tim.app.loadConfig(fullfile(dAgain, 'config.json'));
            tc.verifyEqual(cAgain.geometry.micPositions, c.geometry.micPositions, 'AbsTol', 1e-9);
            S = load(fullfile(dAgain, 'result.mat'), 'res');
            tc.verifyEqual(S.res.analysis.R, res.analysis.R);
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

        function openedMeasurementReprocessedWithItsRecordedMapping(tc)
            % owner decision 2026-10-11: when the channel-to-port mapping a
            % measurement was recorded with (meas.mics) differs from the
            % configuration's (re-cabled since, another file loaded), File > Open
            % measurement… asks "Use the recorded mapping" / "Keep the
            % configuration's mapping", like the tube set-up; the recorded one is
            % the default answer (a hidden window takes it). The configuration's
            % stays available to correct a mapping that was recorded wrongly; the
            % mismatch warning of processMeasurement then stays.
            c = tim.app.defaultConfig(); c.mode = 'simulation'; c.geometry = c.simulation.Geometry;
            c.output.dataDir = fullfile(tc.tmp, 'data'); c.output.calibrationDir = fullfile(tc.tmp, 'cal');
            c.output.exportFigures = false;
            c.excitation.sweep.duration = 1; c.excitation.sweep.repetitions = 1;
            s = tim.app.MeasurementSession(c);
            s.connect(); s.prepareAcquisition();
            meas = s.measure('sweep'); s.close();                  % recorded with ch1 M1, ch2 M2, ch3 M3, ch4 M4
            res = tim.app.processMeasurement(meas, c, []);
            d = tim.app.saveMeasurement(meas, res, c, 'sweep', []);
            c2 = c; c2.mics(1).position = 2; c2.mics(2).position = 1;   % the window's configuration: ch1/ch2 swapped
            file = fullfile(tc.tmp, 'cfg.json'); tim.app.saveConfig(c2, file);
            app = tim.gui.Tubebench(file, 'Visible', 'off'); tc.addTeardown(@() delete(app));
            h = app.H;
            logText = @() strjoin(cellstr(h.log.Value), newline);
            recordedText = 'ch1 M1, ch2 M2, ch3 M3, ch4 M4'; configuredText = 'ch1 M2, ch2 M1, ch3 M3, ch4 M4';
            app.openMeasurement(d);                                % asked; a hidden window takes the default
            tc.verifySubstring(logText(), sprintf(['Microphone mapping for Reprocess: the recorded one (%s); ' ...
                'the configuration has %s.'], recordedText, configuredText));
            % owner decision 2026-10-13 (WO-003 4.3): the question also names the
            % mapping of the saved results (config.json of the folder), and the log
            tc.verifySubstring(logText(), sprintf('The saved results were computed with the microphone mapping %s (the recorded one).', ...
                recordedText));
            tc.verifySubstring(logText(), 'and the microphone mapping the measurement was recorded with.');
            tc.verifyEqual(app.LastRes.analysis.R, res.analysis.R, 'the saved results are shown, not recomputed');
            feval(h.reprocess.ButtonPushedFcn, h.reprocess, []);
            tc.assertNotEmpty(app.LastRes, 'reprocessed');
            tc.verifyEqual(app.LastRes.channelOfPosition, 1:4, 'Reprocess used the recorded mapping');
            tc.verifyFalse(any(contains(app.LastRes.diagnostics.warnings, 'Microphone mapping')), 'no mismatch left');
            tc.verifyEqual(app.LastRes.analysis.R, res.analysis.R, 'AbsTol', 1e-6, 'the results of the recording');
            tc.verifySubstring(logText(), sprintf('Microphone mapping as recorded with the measurement: %s.', recordedText));
            % saved again: its config.json holds the mapping of its results (= raw.mat)
            feval(h.save.ButtonPushedFcn, h.save, []);
            [~, saved] = tim.app.useRecordedMapping(tim.app.loadConfig(fullfile(app.SavedDir, 'config.json')), meas.mics);
            tc.verifyFalse(saved.differs, 'config.json of the new folder: the recorded mapping');
            % the configuration's mapping chosen explicitly (a mapping recorded wrongly)
            app.openMeasurement(d, 'ask', false);
            tc.verifySubstring(logText(), sprintf(['Microphone mapping of the configuration kept for Reprocess (%s); ' ...
                'the measurement was recorded with %s.'], configuredText, recordedText));
            feval(h.reprocess.ButtonPushedFcn, h.reprocess, []);
            tc.verifyEqual(app.LastRes.channelOfPosition, [2 1 3 4], 'Reprocess used the configuration''s mapping');
            tc.verifySubstring(logText(), sprintf('Warning: Microphone mapping of the configuration (%s) differs', configuredText), ...
                'the mismatch is still reported');
            % saved after that deliberate correction: reopened, the question names
            % the corrected mapping as the one of the saved results
            feval(h.save.ButtonPushedFcn, h.save, []);
            d2 = app.SavedDir;
            app.openMeasurement(d2);
            tc.verifySubstring(logText(), sprintf(['The saved results were computed with the microphone mapping %s ' ...
                '(the configuration''s).'], configuredText));
            % the recorded mapping belongs to the opened measurement only: a new
            % measurement is processed with the configuration's (that of the connection)
            app.openMeasurement(d);
            feval(h.connect.ButtonPushedFcn, h.connect, []);
            tc.assertTrue(app.Session.Prepared);
            feval(h.start.ButtonPushedFcn, h.start, []);
            tc.assertNotEmpty(app.LastRes, 'measured');
            tc.verifyEqual(app.LastRes.channelOfPosition, [2 1 3 4], 'a new measurement: the configuration''s mapping');
            tc.verifyFalse(any(contains(app.LastRes.diagnostics.warnings, 'Microphone mapping')));
        end

        function openedResultDrawnWithItsOwnBandAndLimits(tc)
            % audit 2026-10-11: a result opened from its folder is drawn with the
            % band and limits it was analysed with (res.analysis.options), as in
            % its saved figures - not with those of the window's configuration
            % (one drawing code: window = saved figure)
            c = tim.app.defaultConfig(); c.mode = 'simulation'; c.geometry = c.simulation.Geometry;
            c.output.dataDir = fullfile(tc.tmp, 'data'); c.output.calibrationDir = fullfile(tc.tmp, 'cal');
            c.output.exportFigures = false;
            c.excitation.sweep.duration = 1; c.excitation.sweep.repetitions = 1;
            c.analysis.fMin = 120; c.analysis.fMax = 4500; c.analysis.coherenceMin = 0.98;
            s = tim.app.MeasurementSession(c);
            s.connect(); s.prepareAcquisition();
            meas = s.measure('sweep'); s.close();
            res = tim.app.processMeasurement(meas, c, []);
            d = tim.app.saveMeasurement(meas, res, c, 'sweep', []);
            c2 = c; c2.analysis.fMin = 200; c2.analysis.fMax = 3000; c2.analysis.coherenceMin = 0.9;
            file = fullfile(tc.tmp, 'cfg.json'); tim.app.saveConfig(c2, file);
            app = tim.gui.Tubebench(file, 'Visible', 'off'); tc.addTeardown(@() delete(app));
            h = app.H;
            app.openMeasurement(d, false);
            tc.assertEqual(app.LastRes.analysis.options.fRange, [120 4500]);
            figs = tim.app.plotResults(res, meas, struct('Visible', 'off'));
            tc.addTeardown(@() deleteFigs(figs));
            lim = findobj(h.axH(3), 'Tag', 'timCoherenceLimit');
            tc.assertNumElements(lim, 1);
            tc.verifyEqual(lim.Value, 0.98, 'AbsTol', 1e-12, 'coherence limit of the result');
            F = getappdata(figs.reflection, 'timSavedFrame');
            tc.verifyEqual(h.axR(1).XLim, F.axes(1).XLim, 'RelTol', 1e-9, 'band of the result (as saved)');
            views = {'spec', 'spectrum'; 'tf', 'transfer'; 'refl', 'reflection'; 'tl', 'transmissionLoss'; ...
                'zt', 'impedance'; 'valid', 'validity'};
            for i = 1:size(views, 1)
                info = getappdata(figs.(views{i, 2}), 'timViewInfo');
                p = app.Pages.(views{i, 1});
                note = ''; if isfield(info, 'note'), note = info.note; end
                tc.verifyEqual(string(p.Note.Text), string(note), sprintf('%s: note as in the saved figure', views{i, 1}));
                if isfield(info, 'summary') && isstruct(info.summary) && isfield(info.summary, 'data')
                    dat = info.summary.data; if isnumeric(dat), dat = num2cell(dat); end
                    tc.verifyEqual(p.SummaryTable.Data, dat, sprintf('%s: summary as in the saved figure', views{i, 1}));
                end
            end
        end

        function processingFailureLeavesTheMeasurementUnsaved(tc)
            % audit 2026-10-11: a new measurement whose processing fails is shown
            % as not saved (the RESULTS line kept the previous "Saved: <folder>")
            c = tim.app.defaultConfig(); c.mode = 'simulation'; c.geometry = c.simulation.Geometry;
            c.output.dataDir = fullfile(tc.tmp, 'data'); c.output.calibrationDir = fullfile(tc.tmp, 'cal');
            c.output.exportFigures = false;
            c.excitation.sweep.duration = 1; c.excitation.sweep.repetitions = 1;
            file = fullfile(tc.tmp, 'cfg.json'); tim.app.saveConfig(c, file);
            app = tim.gui.Tubebench(file, 'Visible', 'off'); tc.addTeardown(@() delete(app));
            h = app.H; P = tim.gui.palette();
            feval(h.connect.ButtonPushedFcn, h.connect, []);
            feval(h.start.ButtonPushedFcn, h.start, []);
            feval(h.save.ButtonPushedFcn, h.save, []);
            tc.assertTrue(startsWith(h.resultStatus.Text, 'Saved: '), h.resultStatus.Text);
            % a calibration made with another reference channel: the processing
            % of the next measurement fails (tim:cal:ref)
            f = (100:2:5000).';
            cal = struct('type', 'tim.complexChannelCalibration', 'version', 'CAL-TEST-REF2', 'refChannel', 2, ...
                'f', f, 'C', ones(numel(f), 4), 'valid', true(numel(f), 4), 'meta', struct('mode', 'simulation'));
            calFile = fullfile(tc.tmp, 'CAL-TEST-REF2.mat'); save(calFile, 'cal');
            app.Session.loadCalibration(calFile);
            feval(h.start.ButtonPushedFcn, h.start, []);
            tc.assertNotEmpty(app.LastMeas);
            tc.verifyEmpty(app.LastRes, 'processing failed');
            tc.verifySubstring(strjoin(cellstr(h.log.Value), newline), 'Reference channel of the calibration (ch2)');
            tc.verifyFalse(app.Saved);
            tc.verifySubstring(h.resultStatus.Text, 'not saved', 'the new measurement is not saved');
            tc.verifyEqual(h.resultStatus.FontColor, P.fail);
            tc.verifyEqual(h.save.Enable, matlab.lang.OnOffSwitchState.on, 'it can be saved');
        end

        function amplifierWithoutGainIsNeitherEstimatedNorDriven(tc)
            % audit 2026-10-11 (loudspeaker safety): an amplifier chosen without
            % its gain gives no drive estimate (the configured gain_dB of direct
            % drive was used, i.e. gain x1) and Start measurement / Run switching
            % calibration are refused until the gain is entered (user guide section 4)
            c = tim.app.defaultConfig(); c.mode = 'simulation'; c.geometry = c.simulation.Geometry;
            c.output.dataDir = fullfile(tc.tmp, 'data'); c.output.calibrationDir = fullfile(tc.tmp, 'cal');
            c.excitation.sweep.duration = 1; c.excitation.sweep.repetitions = 1;
            c.amplifier.model = 'none (direct drive)'; c.amplifier.gainFactor = 1; c.amplifier.gain_dB = 0;  % as the lab file
            file = fullfile(tc.tmp, 'cfg.json'); tim.app.saveConfig(c, file);
            app = tim.gui.Tubebench(file, 'Visible', 'off'); tc.addTeardown(@() delete(app));
            h = app.H;
            tc.assertEqual(h.spkState.Text, 'OK');
            h.ampModel.Value = 'power amplifier';
            feval(h.ampModel.ValueChangedFcn, h.ampModel, struct('PreviousValue', 'none (direct drive)'));
            tc.verifyFalse(app.GainEntered);
            tc.verifyEqual(h.spkState.Text, 'Gain?');
            tc.verifyEqual(app.DriveCheck.state, 'unknown');
            feval(h.connect.ButtonPushedFcn, h.connect, []);
            tc.assertTrue(app.Session.Prepared);
            refusal = 'enter the voltage gain set on the amplifier "power amplifier"';
            count = @() nnz(contains(cellstr(h.log.Value), refusal));
            tc.assertEqual(count(), 0);
            feval(h.start.ButtonPushedFcn, h.start, []);
            tc.verifyEmpty(app.LastMeas, 'Start refused: nothing measured');
            n = count();
            tc.verifyGreaterThan(n, 0, 'Start refused with the request for the gain');
            feval(h.runCal.ButtonPushedFcn, h.runCal, []);
            tc.verifyGreaterThan(count(), n, 'Run switching calibration refused as well');
            tc.verifyEmpty(app.Session.Calibration, 'no calibration ran');
            h.ampGain.Value = 10;
            feval(h.ampGain.ValueChangedFcn, h.ampGain, struct('PreviousValue', 0));
            tc.verifyTrue(app.GainEntered);
            tc.verifyEqual(h.spkState.Text, 'OK');
            tc.verifyEqual(app.DriveCheck.state, 'ok');
        end

        function excitationChainControls(tc)
            % owner requests 2026-10-12 (WO-003): the amplifier gain is a plain
            % number; the loudspeaker impedance and its power limit share one row;
            % in direct drive the amplitude may be given at the loudspeaker - the
            % generator level follows from the source impedance (50 ohm) and the
            % nominal loudspeaker impedance, and is what the configuration stores.
            % WO-004 (owner decisions 2026-10-12): with an amplifier its input
            % impedance (typed or chosen) is the generator load, High Z in direct
            % drive (fixed while connected); the level at the loudspeaker also with
            % an amplifier of known gain; below the fields the path, the loudspeaker
            % check at the nominal impedance (OK / near from 80 % / above: Start
            % refused) and the criterion of the largest level
            c = tim.app.defaultConfig(); c.mode = 'simulation'; c.geometry = c.simulation.Geometry;
            c.output.dataDir = fullfile(tc.tmp, 'data'); c.output.calibrationDir = fullfile(tc.tmp, 'cal');
            c.amplifier.model = 'none (direct drive)'; c.amplifier.gainFactor = 1; c.amplifier.gain_dB = 0;
            c.amplifier.knownModels = {'none (direct drive)'};               % as the lab file
            c.loudspeaker.impedance_ohm = 8; c.generator.maxVpp = 2; c.excitation.sweep.amplitudeVpp = 0.2;
            c.excitation.sweep.duration = 1; c.excitation.sweep.repetitions = 1;
            file = fullfile(tc.tmp, 'cfg.json'); tim.app.saveConfig(c, file);
            app = tim.gui.Tubebench(file, 'Visible', 'off'); tc.addTeardown(@() delete(app));
            h = app.H;
            texts = get(findall(app.Fig, 'Type', 'uilabel'), 'Text');
            for t = {'Amplifier gain [×]', 'Generator load', 'Loudspeaker [Ω]', 'Test limit [W]'}
                tc.verifyTrue(any(strcmp(texts, t{1})), ['label ' t{1}]);
            end
            tc.verifyFalse(any(strcmp(texts, 'Power limit [W]')) || any(strcmp(texts, 'Speaker limit [W]')), 'old labels');
            tc.verifyEqual(h.ampAt.Items, {'Speaker [Vpk]', 'Generator [Vpk]'}, 'the amplitude label is a list');
            tc.verifyEqual(h.ampGain.ValueDisplayFormat, '%.4g', 'a plain number, no "×" in the field');
            tc.verifySubstring(h.ampGain.Tooltip, '40 dB = ×100', 'the dB conversion of the gain');
            tc.verifySameHandle(h.spkZ.Parent, h.spkP.Parent, 'impedance and power limit on one row');
            tc.verifyTrue(all(ismember({'none (direct drive)', 'power amplifier'}, h.ampModel.Items)), ...
                'an amplifier can be chosen without typing');
            % direct drive: the generator load High Z, locked
            tc.verifyEqual(h.genLoad.Value, 'High Z');
            tc.verifyEqual(char(h.genLoad.Enable), 'off', 'direct drive: High Z');
            tc.verifyEqual(h.genLoadLabel.Text, 'Generator load');
            % an amplifier: its input impedance sets the load; no gain yet: the level at its input
            h.ampModel.Value = 'power amplifier';
            feval(h.ampModel.ValueChangedFcn, h.ampModel, struct('PreviousValue', 'none (direct drive)'));
            tc.verifyEqual(char(h.genLoad.Enable), 'on', 'with an amplifier');
            tc.verifyEqual(h.genLoadLabel.Text, 'Amp input [Ω]');
            tc.verifyTrue(all(ismember({'High Z', '50', '600', '10000'}, h.genLoad.Items)), 'typical inputs');
            tc.verifyEqual(h.ampAt.Items, {'Speaker [Vpk]', 'Amp input [Vpk]'});
            tc.verifyEqual(h.ampAt.Value, 'generator');
            tc.verifyEqual(char(h.ampAt.Enable), 'off', 'the loudspeaker level needs the gain');
            h.genLoad.Value = '600';
            feval(h.genLoad.ValueChangedFcn, h.genLoad, struct('PreviousValue', 'High Z'));
            tc.verifyEqual(app.Cfg.generator.load, '600');
            tc.verifyEqual(app.Cfg.amplifier.inputImpedance_ohm, 600);
            tc.verifyEqual(h.amp.Limits(1), 0.01 * 600 / 650, 'RelTol', 1e-9, 'smallest level at 600 Ω');
            tc.verifyTrue(any(contains(cellstr(h.log.Value), 'Amplifier input: 600 Ω, was High Z')));
            h.genLoad.Value = '20000';                                 % above the 33220A's 10 kΩ: INF
            feval(h.genLoad.ValueChangedFcn, h.genLoad, struct('PreviousValue', '600'));
            tc.verifyEqual(app.Cfg.generator.load, 'INF');
            tc.verifyEqual(app.Cfg.amplifier.inputImpedance_ohm, 20000);
            h.genLoad.Value = 'abc';                                   % not a number: refused
            feval(h.genLoad.ValueChangedFcn, h.genLoad, struct('PreviousValue', '20000'));
            tc.verifyEqual(h.genLoad.Value, '20000');
            tc.verifyTrue(any(contains(cellstr(h.log.Value), 'Amplifier input "abc"')));
            h.genLoad.Value = '600';
            feval(h.genLoad.ValueChangedFcn, h.genLoad, struct('PreviousValue', '20000'));
            tc.verifyEqual(h.amp.Value, 0.1, 'AbsTol', 1e-12, '0.1 Vpk at the amplifier input');
            % the gain entered: the level is shown at the loudspeaker (the default with a known gain)
            h.ampGain.Value = 10;
            feval(h.ampGain.ValueChangedFcn, h.ampGain, struct('PreviousValue', 0));
            tc.verifyEqual(h.ampAt.Value, 'loudspeaker');
            tc.verifyEqual(h.amp.Value, 1, 'RelTol', 1e-9, '0.1 Vpk x 10');
            tc.verifyEqual(h.ampRms.Text, sprintf('= %.3g Vrms', 1 / sqrt(2)));
            tc.verifyEqual(app.DriveCheck.state, 'ok');
            tc.verifyEqual(app.DriveCheck.binding, 'speaker', 'sqrt(2 x 1 W x 8 ohm) = 4 Vpk');
            tc.verifySubstring(h.drivePath.Text, 'Generator 0.2 Vpp into 600 Ω → ×10 → speaker 1 Vpk');
            tc.verifyEqual({h.spkState.Text, h.spkPct.Text, h.genState.Text}, {'OK', '6.25 %', 'OK'});
            tc.verifySubstring(h.driveMax.Text, 'Max 4 Vpk at the speaker, set by the loudspeaker test limit');
            for s = {3.79, 'near', 'Near'; 4.1, 'over', 'Above'}.'
                h.amp.Value = s{1};
                feval(h.amp.ValueChangedFcn, h.amp, struct('PreviousValue', 1));
                tc.verifyEqual(app.DriveCheck.state, s{2}, sprintf('%g Vpk', s{1}));
                tc.verifyEqual(h.spkState.Text, s{3});
            end
            % back to direct drive: High Z again, the same programmed level
            h.ampModel.Value = 'none (direct drive)';
            feval(h.ampModel.ValueChangedFcn, h.ampModel, struct('PreviousValue', 'power amplifier'));
            tc.verifyEqual(h.genLoad.Value, 'High Z', 'back to direct drive: High Z');
            tc.verifyEqual(app.Cfg.generator.load, 'INF');
            tc.verifyEqual(h.ampAt.Items, {'Speaker [Vpk]', 'Generator [Vpk]'});
            h.ampAt.Value = 'generator';
            feval(h.ampAt.ValueChangedFcn, h.ampAt, struct('PreviousValue', 'loudspeaker'));
            tc.verifyEqual(h.amp.Value, 0.41, 'RelTol', 1e-9, 'the programmed level of 4.1 Vpk / ×10');
            h.amp.Value = 0.1;
            feval(h.amp.ValueChangedFcn, h.amp, struct('PreviousValue', 0.41));
            % the level at the loudspeaker: 0.1 Vpk programmed = 0.1 * 8/58 Vpk at the loudspeaker
            h.ampAt.Value = 'loudspeaker';
            feval(h.ampAt.ValueChangedFcn, h.ampAt, struct('PreviousValue', 'generator'));
            tc.verifyEqual(h.amp.Value, 0.1 * 8 / 58, 'RelTol', 1e-9, 'the same level, at the loudspeaker');
            tc.verifyEqual(h.amp.Limits, [0.01 1] * 8 / 58, 'RelTol', 1e-9, 'the generator limits at the loudspeaker');
            h.amp.Value = 0.01;                                       % 10 mVpk at the loudspeaker
            feval(h.amp.ValueChangedFcn, h.amp, struct('PreviousValue', 0.1 * 8 / 58));
            tc.verifySubstring(h.drivePath.Text, 'Generator 0.145 Vpp open circuit → speaker 0.01 Vpk');
            tc.verifySubstring(h.driveMax.Text, 'set by generator.maxVpp (2 Vpp open circuit)', 'the maximum in direct drive');
            tc.verifyEqual(app.DriveCheck.maxSpeakerVpk, 8 / 58, 'RelTol', 1e-9);
            h.spkZ.Value = 4;                                         % the loudspeaker voltage is kept
            feval(h.spkZ.ValueChangedFcn, h.spkZ, struct('PreviousValue', 8));
            tc.verifyEqual(h.amp.Value, 0.01, 'AbsTol', 1e-12);
            tc.verifySubstring(h.drivePath.Text, 'Generator 0.27 Vpp');   % 2 x 0.01 * 54/4
            h.spkZ.Value = 8;
            feval(h.spkZ.ValueChangedFcn, h.spkZ, struct('PreviousValue', 4));
            feval(h.connect.ButtonPushedFcn, h.connect, []);            % reads the fields
            tc.assertTrue(app.Session.Prepared);
            tc.verifyEqual(app.Session.Cfg.excitation.sweep.amplitudeVpp, 2 * 0.01 * 58 / 8, 'RelTol', 1e-9, ...
                'the configuration stores the generator level');
            tc.verifyEqual(app.Session.Cfg.ui.amplitudeAt, 'loudspeaker');
            tc.verifyEqual(char(h.genLoad.Enable), 'off', 'fixed while connected');
            % a change after Connect reaches the record of the next measurement (hardware check 2026-10-12)
            h.ampAt.Value = 'generator';
            feval(h.ampAt.ValueChangedFcn, h.ampAt, struct('PreviousValue', 'loudspeaker'));
            tc.verifyEqual(h.amp.Value, 0.01 * 58 / 8, 'RelTol', 1e-9, 'the same level, as the generator''s');
            feval(h.start.ButtonPushedFcn, h.start, []);
            tc.assertNotEmpty(app.LastMeas);
            tc.verifyEqual(app.LastMeas.metadata.config.ui.amplitudeAt, 'generator');
            tc.verifyEqual(app.LastMeas.metadata.drive.Vspk_pk, 0.01, 'RelTol', 1e-9, 'metadata.drive: the loudspeaker level');
            tc.verifyEqual(app.LastMeas.metadata.drive.Voc_pp, 2 * 0.01 * 58 / 8, 'RelTol', 1e-9, 'and the generator level');
            tc.verifyEqual(app.LastMeas.metadata.drive.state, 'ok', 'and the loudspeaker check');
            tc.verifyEqual(app.LastMeas.metadata.drive.Vspk_rms, 0.01 / sqrt(2), 'RelTol', 1e-9);
            h.ampAt.Value = 'loudspeaker';
            feval(h.ampAt.ValueChangedFcn, h.ampAt, struct('PreviousValue', 'generator'));
            % choosing an amplifier shows the same generator level as the generator's
            h.ampModel.Value = 'power amplifier';
            feval(h.ampModel.ValueChangedFcn, h.ampModel, struct('PreviousValue', 'none (direct drive)'));
            tc.verifyEqual(h.ampAt.Value, 'generator');
            tc.verifyEqual(h.amp.Value, 0.01 * 58 / 8, 'RelTol', 1e-9);
        end

        function connectRefusedBeforeTheSessionExists(tc)
            % audit 2026-10-11: a Connect refused by the session's own checks
            % before any instrument is contacted (here a configured calibration
            % file that does not exist) says so in Setup > Connection instead of
            % "Connecting (... mode)…"
            c = tim.app.defaultConfig(); c.mode = 'simulation'; c.geometry = c.simulation.Geometry;
            c.output.dataDir = fullfile(tc.tmp, 'data'); c.output.calibrationDir = fullfile(tc.tmp, 'cal');
            c.calibration.file = fullfile(tc.tmp, 'CAL-missing.mat');
            file = fullfile(tc.tmp, 'cfg.json'); tim.app.saveConfig(c, file);
            app = tim.gui.Tubebench(file, 'Visible', 'off'); tc.addTeardown(@() delete(app));
            h = app.H;
            feval(h.connect.ButtonPushedFcn, h.connect, []);
            tc.verifyEmpty(app.Session, 'not connected');
            tc.verifyTrue(startsWith(h.connHead.Text, 'Connection refused: '), h.connHead.Text);
            tc.verifySubstring(h.connHead.Text, 'CAL-missing.mat');
            tc.verifyEqual(h.connHead.FontColor, tim.gui.palette().fail);
            tc.verifyTrue(all(strcmp(app.ConnList.States, 'pending')), 'no step ran');
            tc.verifySubstring(h.status.Text, 'Not connected');
            tc.verifyFalse(app.Busy);
        end

        function stopBeforeTheSessionExists(tc)
            % audit 2026-10-11 (gui-5, PendingStop): Stop pressed after Connect but
            % before the window has created the session. The window keeps the
            % request and the new session stops at its first connection step: no
            % instrument is contacted. A close request at that point closes the
            % window once the connection has stopped. The test-only hook TestHook
            % acts exactly at that point (owner decision 2026-10-11; a timer
            % fired before the window was busy and the test was flaky).
            c = tim.app.defaultConfig(); c.mode = 'simulation'; c.geometry = c.simulation.Geometry;
            c.output.dataDir = fullfile(tc.tmp, 'data'); c.output.calibrationDir = fullfile(tc.tmp, 'cal');
            file = fullfile(tc.tmp, 'cfg.json'); tim.app.saveConfig(c, file);
            app = tim.gui.Tubebench(file, 'Visible', 'off'); tc.addTeardown(@() delete(app));
            h = app.H;
            seen = struct('point', '', 'busy', false, 'session', true, 'pending', false);
            app.TestHook = @(point) pressStop(point);
            tim.instr.mockBusLog('start'); tc.addTeardown(@() tim.instr.mockBusLog('stop'));
            feval(h.connect.ButtonPushedFcn, h.connect, []);
            tc.assertEqual(seen.point, 'connect:beforeSession', 'the hook ran');
            tc.verifyTrue(seen.busy, 'Stop pressed while Connect was running');
            tc.verifyFalse(seen.session, 'before the session existed');
            tc.verifyTrue(seen.pending, 'the window kept the request');
            tc.verifyEmpty(app.Session, 'not connected');
            tc.verifyEmpty(tim.instr.mockBusLog('lines'), 'no instrument was contacted');
            log = strjoin(cellstr(h.log.Value), newline);
            tc.verifySubstring(log, 'Stop requested by the operator.');
            tc.verifySubstring(log, 'Connection stopped by the operator: Connection stopped by the operator.');
            first = app.ConnList.Keys{1};
            tc.verifyEqual(app.ConnList.state(first), 'fail', 'the first step stopped');
            tc.verifyEqual(app.ConnList.Details(1).Text, 'stopped by the operator');
            tc.verifyFalse(app.Busy);
            tc.verifySubstring(h.status.Text, 'Not connected');
            % the request belonged to that connection: Connect again connects
            app.TestHook = [];
            feval(h.connect.ButtonPushedFcn, h.connect, []);
            tc.assertNotEmpty(app.Session, 'connected the second time');
            tc.verifyTrue(app.Session.Prepared);
            tc.verifyNotEmpty(tim.instr.mockBusLog('lines'), 'the instruments were contacted this time');
            % close request at the same point: the connection stops, then the window closes
            app2 = tim.gui.Tubebench(file, 'Visible', 'off'); tc.addTeardown(@() delete(app2));
            fig2 = app2.Fig;
            app2.TestHook = @(~) tim.gui.closeApp(fig2, app2);
            tim.instr.mockBusLog('start');
            feval(app2.H.connect.ButtonPushedFcn, app2.H.connect, []);
            tc.verifyFalse(isvalid(app2), 'closed after the stopped connection');
            tc.verifyFalse(isvalid(fig2));
            tc.verifyEmpty(tim.instr.mockBusLog('lines'), 'no instrument was contacted');
            function pressStop(point)
                seen.point = point; seen.busy = app.Busy; seen.session = ~isempty(app.Session);
                feval(h.stop.ButtonPushedFcn, h.stop, []);
                seen.pending = app.PendingStop;
            end
        end

        function closeWhileOpeningAMeasurementCancelsItsQuestions(tc)
            % review 2026-10-11: in a window without a session (not connected:
            % offline reprocessing) a close request during File > Open measurement…
            % only set CloseAfterBusy / PendingStop, which ask() and askBar() did
            % not check: an open question (tube set-up, recorded microphone
            % mapping) kept waiting and only a second close request closed the
            % window (user guide section 3: the running action is stopped first;
            % a question counts as cancelled). The test-only hook acts just
            % before the questions. A hidden window answers with the default
            % unless the action is being stopped (stopPending, which a visible
            % dialog's wait loop polls too), so the answers show the cancel.
            c = tim.app.defaultConfig(); c.mode = 'simulation'; c.geometry = c.simulation.Geometry;
            c.output.dataDir = fullfile(tc.tmp, 'data'); c.output.calibrationDir = fullfile(tc.tmp, 'cal');
            c.output.exportFigures = false;
            c.excitation.sweep.duration = 1; c.excitation.sweep.repetitions = 1;
            s = tim.app.MeasurementSession(c);
            s.connect(); s.prepareAcquisition();
            meas = s.measure('sweep'); s.close();
            d = tim.app.saveMeasurement(meas, tim.app.processMeasurement(meas, c, []), c, 'sweep', []);
            % the window: another tube set-up (L1 9 mm longer), ch1/ch2 swapped; not connected
            c2 = c; c2.geometry.micPositions(1:2) = c.geometry.micPositions(1:2) - 0.009;
            c2.mics(1).position = 2; c2.mics(2).position = 1;
            file = fullfile(tc.tmp, 'cfg.json'); tim.app.saveConfig(c2, file);
            app = tim.gui.Tubebench(file, 'Visible', 'off'); tc.addTeardown(@() delete(app));
            fig = app.Fig;
            tc.assertEmpty(app.Session, 'not connected');
            seen = struct('point', '', 'pending', false, 'ask', '', 'askBar', '');
            app.TestHook = @(point) closeThere(point);
            app.openMeasurement(d);                                % returns after the window has closed
            tc.assertEqual(seen.point, 'open:beforeQuestions', 'the hook ran');
            tc.verifyTrue(seen.pending, 'the close request counts as a stop of the running action');
            tc.verifyEqual(seen.ask, 'Cancel', 'a question dialog is cancelled, not answered with its default');
            tc.verifyEqual(seen.askBar, 'Abort', 'a question in the calibration bar too');
            tc.verifyFalse(isvalid(app), 'closed after one close request');
            tc.verifyFalse(isvalid(fig));
            % a request left over after an action answers no later question: Stop
            % before the session existed (the connection stopped), then Open
            % measurement asks as usual (a hidden window: the default answers)
            app2 = tim.gui.Tubebench(file, 'Visible', 'off'); tc.addTeardown(@() delete(app2));
            h2 = app2.H;
            app2.TestHook = @(~) feval(h2.stop.ButtonPushedFcn, h2.stop, []);
            feval(h2.connect.ButtonPushedFcn, h2.connect, []);
            tc.assertEmpty(app2.Session, 'the connection was stopped');
            tc.assertTrue(app2.PendingStop, 'the request is still recorded after the action');
            app2.TestHook = [];
            tc.verifyEqual(app2.ask('Question?', 'Test', {'Answer', 'Cancel'}, 1, 2), 'Answer', 'outside an action');
            app2.openMeasurement(d);
            log = strjoin(cellstr(h2.log.Value), newline);
            tc.verifySubstring(log, 'IMPEDANCE TUBE fields set to the saved set-up');
            tc.verifySubstring(log, 'Microphone mapping for Reprocess: the recorded one');
            tc.verifyTrue(isvalid(app2), 'still open');
            function closeThere(point)
                seen.point = point;
                tim.gui.closeApp(fig, app);                        % first close request: during the action
                seen.pending = app.stopPending();
                seen.ask = app.ask('Question?', 'Test', {'Answer', 'Cancel'}, 1, 2);
                seen.askBar = app.askBar('Question?', {'Done', 'Abort'}, 1, 2);
            end
        end

        function outputNotConfirmedOffIsShown(tc)
            % audit 2026-10-11 (safety display): Stop while measuring and the
            % generator link lost at the same moment - the read-back cannot
            % confirm the output off: red Generator lamp and status "Generator
            % output not confirmed off". The message pane says the output was
            % commanded off and then the read-back, never "switched off".
            c = tim.app.defaultConfig(); c.mode = 'simulation'; c.geometry = c.simulation.Geometry;
            c.output.dataDir = fullfile(tc.tmp, 'data'); c.output.calibrationDir = fullfile(tc.tmp, 'cal');
            c.excitation.sweep.duration = 3; c.excitation.sweep.repetitions = 4;
            file = fullfile(tc.tmp, 'cfg.json'); tim.app.saveConfig(c, file);
            app = tim.gui.Tubebench(file, 'Visible', 'off'); tc.addTeardown(@() delete(app));
            h = app.H; P = tim.gui.palette();
            feval(h.connect.ButtonPushedFcn, h.connect, []);
            tc.assertTrue(app.Session.Prepared);
            hk = tim.instr.Keysight33220A.testHooks(app.Session.Gen);
            stopper = timer('StartDelay', 1.0, 'TimerFcn', @(~, ~) stopAndBreakLink(h, hk));
            tc.addTeardown(@() delete(stopper));
            start(stopper);
            ws = warning('off', 'tim:gen:outputOff'); tc.addTeardown(@() warning(ws));   % the lost link
            feval(h.start.ButtonPushedFcn, h.start, []);
            tc.verifyTrue(app.OutputUnconfirmed);
            tc.verifyEqual(h.lamp(1).Color, P.fail, 'Generator lamp red');
            tc.verifyEqual(h.status.Text, 'Generator output not confirmed off');
            log = strjoin(cellstr(h.log.Value), newline);
            tc.verifySubstring(log, 'Stop requested by the operator: generator output commanded off.');
            tc.verifySubstring(log, 'The generator output could not be confirmed off.', 'the read-back is logged');
            tc.verifyFalse(contains(log, 'output switched off'), 'never claimed off without a read-back');
        end

        function connectionCheckWhileIdle(tc)
            % WO-003 (owner decision 2026-10-12; the 33220A drops an idle
            % connection unnoticed): the window checks the connections while
            % idle - every 60 s in hardware mode, here called directly (a hidden
            % or simulation window has no idle timer). A dropped connection is
            % re-opened and logged; one that cannot be turns the lamp red, asks
            % for Disconnect / Connect and stops the idle check; Start then ends
            % before anything is armed, with the reason in English
            c = tim.app.defaultConfig(); c.mode = 'simulation'; c.geometry = c.simulation.Geometry;
            c.output.dataDir = fullfile(tc.tmp, 'data'); c.output.calibrationDir = fullfile(tc.tmp, 'cal');
            file = fullfile(tc.tmp, 'cfg.json'); tim.app.saveConfig(c, file);
            app = tim.gui.Tubebench(file, 'Visible', 'off'); tc.addTeardown(@() delete(app));
            h = app.H; P = tim.gui.palette();
            feval(h.connect.ButtonPushedFcn, h.connect, []);
            tc.assertTrue(app.Session.Prepared);
            tc.verifyEmpty(app.LinkTimer, 'no idle timer in a hidden window or in simulation');
            r = app.checkConnectionNow();
            tc.verifyEqual(unique({r.state}), {'ok'});
            hk = tim.instr.Keysight33220A.testHooks(app.Session.Gen);
            hk.dropConnection();
            r = app.checkConnectionNow();
            tc.verifyEqual(r(1).state, 'reconnected');
            log = strjoin(cellstr(h.log.Value), newline);
            tc.verifySubstring(log, 'Generator: connection re-opened (the instrument had closed it): 33220A s/n MOCK0001, output off.');
            tc.verifyNotEqual(h.lamp(1).Color, P.fail);
            hk.dropConnection(); hk.breakLink();
            ws = warning('off', 'tim:gen:outputOff'); tc.addTeardown(@() warning(ws));
            r = app.checkConnectionNow();
            tc.verifyEqual(r.state, 'lost');
            tc.verifyEqual(h.lamp(1).Color, P.fail, 'Generator lamp red');
            tc.verifyEqual(h.status.Text, 'Connection lost - Disconnect and Connect');
            tc.verifyFalse(app.LinkChecking);
            feval(h.start.ButtonPushedFcn, h.start, []);
            log = strjoin(cellstr(h.log.Value), newline);
            tc.verifySubstring(log, 'Error (measurement): The connection to the generator was lost and could not be re-opened');
            tc.verifySubstring(log, 'The connection to the generator is lost, so its output state cannot be read back.');
            tc.verifyFalse(any(strcmp(hk.traffic(), '> OUTP ON')), 'nothing armed');
        end

        function windowTitleMenusAndAbout(tc)
            % user request 2026-10-09: version and repository in Help > About of a
            % menu bar (as in other programs) instead of a footer; tab "Formula"
            n0 = numel(findall(groot, 'Type', 'figure'));
            app = tim.gui.Tubebench('', 'Visible', 'off'); tc.addTeardown(@() delete(app));
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
            nAbout = @() numel(findall(groot, 'Type', 'figure', 'Name', 'About tubebench'));
            n0 = nAbout();                     % About windows of other app instances (e.g. one the user has open)
            feval(app.H.mAbout.MenuSelectedFcn, app.H.mAbout, []);
            fig = app.AboutFig; tc.addTeardown(@() delete(fig));
            tc.verifyEqual(fig.Name, 'About tubebench');
            txt = strjoin(app.H.aboutText.Value, newline);
            [~, info] = tim.app.softwareVersion();
            tc.verifySubstring(txt, info.version);
            tc.verifySubstring(txt, info.commit);
            tc.verifySubstring(txt, 'MIT License - Copyright (c) 2026 Woongji Kim', 'the licence (owner 2026-10-13)');
            tc.verifyTrue(isfile(fullfile(fileparts(fileparts(mfilename('fullpath'))), 'LICENSE')), 'LICENSE in the project folder');
            % user request 2026-10-09: link to the author's portfolio site; 2026-10-10:
            % only the address, and no repository link (it is in Help > Source code on GitHub)
            tc.verifyEqual(app.H.aboutPortfolio.URL, 'https://kimwoongji.github.io');
            tc.verifyEqual(app.H.aboutPortfolio.Text, 'kimwoongji.github.io');
            tc.verifyFalse(isfield(app.H, 'aboutLink'), 'no repository link in About');
            tc.verifyNumElements(findall(fig, 'Type', 'uihyperlink'), 1);
            % user choice 2026-10-10: the light mark left of the name; window icons
            tc.verifyEqual(app.H.aboutLogo.ImageSource, tim.gui.logo(), 'About: light mark (SVG)');
            tc.verifyEqual(app.H.aboutLogo.Parent.ColumnWidth{1}, 46);
            tc.verifyEqual(fig.Icon, tim.gui.logo('icon'), 'About window icon');
            tc.verifyEqual(app.Fig.Icon, tim.gui.logo('icon'), 'main window icon');
            feval(app.H.mAbout.MenuSelectedFcn, app.H.mAbout, []);
            tc.verifyEqual(nAbout(), n0 + 1, 'one About window per app');
        end

        function deferredViewsBuiltWhenOpened(tc)
            % user choice 2026-10-10 (progressive start-up, "A"): the window appears
            % with the control panel, the message pane, every tab and Setup >
            % Connection; a view opened before the background has prepared it is
            % prepared at once (major tab: its selected sub tab)
            n0 = timersExceptOtherWindows();
            app = tim.gui.Tubebench(tc.labConfig(), 'Visible', 'off', 'Deferred', true, 'BuildDelay', 600);
            tc.addTeardown(@() delete(app));      % (600 s: the background queue does not start here)
            tag = app.TimerTag;
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
            tc.verifyEqual(timersExceptOtherWindows(tag), n0 + 1, 'one timer: the background queue');
            tc.verifySameHandle(timerfindall('Tag', tag), app.BuildTimer, 'tagged with the window');
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
            tc.verifyEqual(timersExceptOtherWindows(tag), n0, 'timer deleted with the window');
        end

        function deferredQueuePreparesEveryView(tc)
            % the background queue prepares every view, one step per timer tick,
            % with its first drawing; afterwards no timer is left
            n0 = timersExceptOtherWindows();
            app = tim.gui.Tubebench(tc.labConfig(), 'Visible', 'off', 'Deferred', true, 'BuildDelay', 0);
            tc.addTeardown(@() delete(app));
            tag = app.TimerTag;
            t0 = tic;
            while isnan(app.ReadyTime) && toc(t0) < 240, pause(0.1); end
            tc.assertFalse(isnan(app.ReadyTime), 'queue finished');
            for p = app.Parts, tc.verifyEqual(app.PartState.(p{1}), 'ready', p{1}); end
            tc.verifyEmpty(app.BuildQueue);
            tc.verifyEmpty(app.BuildTimer);
            tc.verifyEqual(timersExceptOtherWindows(tag), n0, 'timer deleted when the queue is done');
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
            app = tim.gui.Tubebench(file, 'Visible', 'off', 'Deferred', true, 'BuildDelay', 0.2);
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
            % timer left (the timer belongs to the window). Audit 2026-10-11:
            % only this window's timers are counted - another window (the user's,
            % in the same MATLAB) keeps its own preparation timer meanwhile
            other = tim.gui.Tubebench('', 'Visible', 'off', 'Deferred', true, 'BuildDelay', 600);
            tc.addTeardown(@() delete(other));
            tc.assertNotEmpty(timerfindall('Tag', other.TimerTag), 'the other window prepares its views');
            n0 = timersExceptOtherWindows();
            app = tim.gui.Tubebench('', 'Visible', 'off', 'Deferred', true, 'BuildDelay', 0);
            tag = app.TimerTag;
            tc.assertNotEqual(tag, other.TimerTag, 'one tag per window');
            fig = app.Fig;
            tc.addTeardown(@() delete(fig(isvalid(fig))));
            t0 = tic;
            while numel(app.BuildLog) < 3 && toc(t0) < 60, pause(0.05); end
            tc.assertTrue(isnan(app.ReadyTime), 'still preparing');
            tc.verifyWarningFree(@() closeAndWait(fig, app));
            tc.verifyFalse(isvalid(app)); tc.verifyFalse(isvalid(fig));
            tc.verifyEmpty(timerfindall('Tag', tag), 'no timer of the closed window left');
            tc.verifyEqual(timersExceptOtherWindows(tag), n0, 'no timer left');
            tc.verifyNumElements(timerfindall('Tag', other.TimerTag), 1, 'the other window''s timer untouched');
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

function closeAndStamp(t, app, t0)
% timer callback: close the window, then record when it is gone (s after t0)
tim.gui.closeApp(app.Fig, app);
t.UserData = toc(t0);
end

function stamps = stampLog(s, t0)
% the session's log lines from now on with the time they were written (s
% after t0); stamps is a containers.Map (a handle the callback fills: 1, 2, ...
% -> struct t, line). The window's own callback still receives every line.
stamps = containers.Map('KeyType', 'double', 'ValueType', 'any');
cb = s.StatusCallback;
s.StatusCallback = @(line) addStamp(line, cb, stamps, t0);
end

function addStamp(line, cb, stamps, t0)
stamps(stamps.Count + 1) = struct('t', toc(t0), 'line', line); %#ok<NASGU> (a handle: the caller's Map)
if ~isempty(cb), cb(line); end
end

function t = stampOf(stamps, text)
% time of the first stamped log line that contains text (NaN: not logged)
t = NaN;
for k = 1:stamps.Count
    e = stamps(k);
    if contains(e.line, text), t = e.t; return; end
end
end

function stopAndBreakLink(h, hooks)
% Stop pressed, and the generator link lost at the same moment
feval(h.stop.ButtonPushedFcn, h.stop, []);
hooks.breakLink();
end

function deleteFigs(figs)
fc = struct2cell(figs);
for i = 1:numel(fc), if isgraphics(fc{i}), delete(fc{i}); end, end
end

function n = timersExceptOtherWindows(tag)
% number of timers in this MATLAB session without those of OTHER tubebench
% windows (every window tags its timers with its TimerTag): the user's own
% window may start or end its view-preparation or calibration timer while a
% test runs (tests may run in the user's MATLAB)
if nargin < 1, tag = ''; end
t = timerfindall;
if isempty(t), n = 0; return; end
tags = get(t, {'Tag'});
n = nnz(~(startsWith(tags, 'tubebench-') & ~strcmp(tags, tag)));
end

function L = labels(ax)
t = findobj(ax, 'Type', 'text');
L = cellfun(@(s) strjoin(cellstr(s), ' '), get(t, 'String'), 'UniformOutput', false);
end
