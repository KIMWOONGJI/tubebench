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
            feval(h.runCal.ButtonPushedFcn, h.runCal, []);
            tc.verifyEqual(numel(app.CalList.States), 1 + 3 * 2 + 1);
            tc.verifyTrue(all(strcmp(app.CalList.States, 'ok')), strjoin(app.CalList.States, ' '));
            tc.verifySubstring(h.calLabel.Text, 'CAL-');
            feval(h.start.ButtonPushedFcn, h.start, []);
            tc.verifyNotEmpty(app.LastRes);
            tc.verifyEqual(h.axW(1).YLabel.String, 'ch1 [Pa]');
            clear cleanup
        end
    end
end

function L = labels(ax)
t = findobj(ax, 'Type', 'text');
L = cellfun(@(s) strjoin(cellstr(s), ' '), get(t, 'String'), 'UniformOutput', false);
end
