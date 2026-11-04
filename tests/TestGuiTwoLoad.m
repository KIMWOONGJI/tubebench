classdef TestGuiTwoLoad < matlab.unittest.TestCase
    %TESTGUITWOLOAD The two-load transfer matrix in the window (WO-005, 1.4.0):
    %   the Method row (control panel height unchanged), the Termination box of
    %   Setup > Tube setup, the remembered loads (never in a hidden window), and
    %   a hidden-window run of A -> B -> A' in SIMULATION with the Two-load view,
    %   the result views, Reprocess, Save, Open and Combine. No hardware.

    properties
        tmp
    end

    methods (TestMethodSetup)
        function setup(tc)
            f = tc.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            tc.tmp = f.Folder;
        end
    end

    methods
        function file = config(tc, varargin)
            % a simulation configuration with short sweeps in the temporary folder
            c = tim.app.defaultConfig();
            c.mode = 'simulation';
            c.geometry = c.simulation.Geometry;
            c.output.dataDir = fullfile(tc.tmp, 'data');
            c.output.calibrationDir = fullfile(tc.tmp, 'cal');
            c.excitation.sweep.duration = 1; c.excitation.sweep.repetitions = 1;
            c.calibration.repeatConfigI = false;
            for i = 1:2:numel(varargin), c = setfield(c, varargin{i}{:}, varargin{i + 1}); end %#ok<SFLD>
            file = fullfile(tc.tmp, 'twoload_cfg.json');
            tim.app.saveConfig(c, file);
        end
    end

    methods (Test)
        function methodRowAndTerminationBox(tc)
            % decision 8: the Method row shares the background-noise row (930 px
            % panel); the terminations in Setup > Tube setup, the same two lists in
            % every row, the absorber only at the tube end, two equal loads named
            app = tim.gui.Tubebench(tc.config(), 'Visible', 'off');
            tc.addTeardown(@() delete(app));
            h = app.H;
            L = h.left; rh = L.RowHeight;
            tc.verifyLessThanOrEqual(sum([rh{:}]) + (numel(rh) - 1) * L.RowSpacing + L.Padding(2) + L.Padding(4), 930, ...
                'control panel within 930 px (1.5.1: a cycles row, thinner section bars)');
            tc.verifyEqual(h.method.Parent, h.background.Parent, 'Method and Background noise in one row');
            tc.verifyEqual(h.method.ItemsData, {'oneLoad', 'oneLoadSymmetric', 'twoLoad'});
            tc.verifyEqual(h.method.Value, 'oneLoad', 'the default method');
            tc.verifyEqual(h.start.Text, 'Start measurement');
            % one load: one row "Termination", the configured absorber
            tc.verifyEqual(h.termLabelA.Text, 'Termination');
            tc.verifyEqual(h.termGrid.RowHeight(2:3), {0, 0});
            tc.verifyEqual({h.termKindA.Value, h.termPlaceA.Value}, {'absorber', 'tubeEnd'});
            tc.verifyEqual(h.termPlaceA.Enable, matlab.lang.OnOffSwitchState.off, 'absorber: place fixed');
            tc.verifySubstring(h.termText.Text, 'absorber inside');
            tc.verifyEqual(h.termKindA.Items, h.termKindB.Items, 'the same kinds in both rows');
            tc.verifyEqual(h.termPlaceA.Items, h.termPlaceB.Items, 'the same places in both rows');
            % a rigid cap at the joint: configuration, text, model
            h.termKindA.Value = 'rigid'; feval(h.termKindA.ValueChangedFcn, h.termKindA, []);
            tc.verifyEqual(h.termPlaceA.Enable, matlab.lang.OnOffSwitchState.on);
            h.termPlaceA.Value = 'joint'; feval(h.termPlaceA.ValueChangedFcn, h.termPlaceA, []);
            tc.verifyEqual(app.Cfg.measurement.loadA, struct('kind', 'rigid', 'place', 'joint'));
            tc.verifySubstring(h.termText.Text, 'rigid cap sealed on the joint flange (face 41 mm behind M4)');
            lab = findobj(h.axTube3D, 'Tag', 'endLabel'); s = cellstr(lab.String);
            tc.verifyEqual(s{1}, 'rigid cap at the joint');
            % the absorber again: the place goes back to the tube end
            h.termKindA.Value = 'absorber'; feval(h.termKindA.ValueChangedFcn, h.termKindA, []);
            tc.verifyEqual(app.Cfg.measurement.loadA.place, 'tubeEnd');
            % two loads: rows A, B and the options; the model draws load A at
            % first, then the load changed last (owner 2026-11-03: no Show selector)
            h.method.Value = 'twoLoad'; feval(h.method.ValueChangedFcn, h.method, []);
            tc.verifyEqual(h.start.Text, 'Start two-load measurement');
            tc.verifyEqual(h.termLabelA.Text, 'Load A');
            tc.verifyEqual(h.termGrid.RowHeight(2:3), {24, 22});
            tc.verifyFalse(isfield(h, 'termShow'), 'no Show selector');
            tc.verifySubstring(h.termText.Text, 'B: the extension tube empty (absorber removed)');
            lab = findobj(h.axTube3D, 'Tag', 'endLabel'); s = cellstr(lab.String);
            tc.verifyEqual(s{1}, 'absorbing termination', 'load A at first');
            h.termPlaceB.Value = 'joint'; feval(h.termPlaceB.ValueChangedFcn, h.termPlaceB, []);
            tc.verifyEqual(app.TermShown, 'B');
            lab = findobj(h.axTube3D, 'Tag', 'endLabel'); s = cellstr(lab.String);
            tc.verifyEqual(s{1}, 'rigid cap at the joint', 'a changed load B is drawn');
            h.termKindA.Value = 'open'; feval(h.termKindA.ValueChangedFcn, h.termKindA, []);
            tc.verifyEqual(app.TermShown, 'A');
            lab = findobj(h.axTube3D, 'Tag', 'endLabel'); s = cellstr(lab.String);
            tc.verifyEqual(s{1}, 'open end', 'a changed load A is drawn');
            h.termKindA.Value = 'absorber'; feval(h.termKindA.ValueChangedFcn, h.termKindA, []);
            h.termPlaceB.Value = 'tubeEnd'; feval(h.termPlaceB.ValueChangedFcn, h.termPlaceB, []);
            tc.verifyEqual(app.Cfg.measurement.loadA, struct('kind', 'absorber', 'place', 'tubeEnd'));
            tc.verifyEqual(app.Cfg.measurement.loadB, struct('kind', 'rigid', 'place', 'tubeEnd'));
            lab = findobj(h.axTube3D, 'Tag', 'endLabel'); s = cellstr(lab.String);
            tc.verifyEqual(s{1}, 'rigid end cap', 'load B changed last');
            h.termRepeat.Value = false; feval(h.termRepeat.ValueChangedFcn, h.termRepeat, []);
            tc.verifyEqual(app.TermShown, 'B', 'the repeat option does not switch the model');
            h.termRepeat.Value = true; feval(h.termRepeat.ValueChangedFcn, h.termRepeat, []);
            h.termLevelB.Value = -6; feval(h.termLevelB.ValueChangedFcn, h.termLevelB, []);
            tc.verifyEqual(app.Cfg.measurement.loadBLevel_dB, -6);
            tc.verifySubstring(h.termText.Text, 'Load B at −6 dB');
            % equal loads: named in red; Start refuses them
            h.termKindB.Value = 'absorber'; feval(h.termKindB.ValueChangedFcn, h.termKindB, []);
            tc.verifySubstring(h.termText.Text, 'are both "Absorber at tube end"');
            tc.verifyEqual(h.termText.FontColor, tim.gui.palette().fail);
            % the steps of the Two-load view follow the loads
            tc.verifyEqual(app.TwList.Keys, {'A', 'B', 'A2', 'result'});
            h.termRepeat.Value = false; feval(h.termRepeat.ValueChangedFcn, h.termRepeat, []);
            tc.verifyEqual(app.TwList.Keys, {'A', 'B', 'result'});
        end

        function twoLoadAppSimulationWorkflow(tc)
            % hidden app window: connect, calibration, Method "Two loads" (load B
            % 6 dB lower), Start: A -> B -> A' with the step list, every load and the
            % pair saved; the result views; Show load; Reprocess; Save; Open; Combine
            file = tc.config({'measurement', 'loadBLevel_dB'}, -6);
            app = tim.gui.Tubebench(file, 'Visible', 'off');
            cleanup = onCleanup(@() delete(app));
            h = app.H;
            feval(h.connect.ButtonPushedFcn, h.connect, []);
            feval(h.runCal.ButtonPushedFcn, h.runCal, []);
            tc.assertTrue(all(strcmp(app.CalList.States, 'ok')), strjoin(app.CalList.States, ' '));
            tc.verifyEqual(app.Session.Termination, struct('kind', 'absorber', 'place', 'tubeEnd'), ...
                'the calibration records the absorber');
            h.method.Value = 'twoLoad'; feval(h.method.ValueChangedFcn, h.method, []);
            % the time signals while a load is measured, then the Two-load view
            % again (owner 2026-10-14)
            shown = {};
            app.TestHook = @(p) recordTab(p);
            feval(h.start.ButtonPushedFcn, h.start, []);
            app.TestHook = [];
            tc.verifyEqual(shown, repmat({h.waveTab}, 1, 3), 'Time signal view while each load is measured');
            tc.verifyEqual(h.measTabs.SelectedTab, h.twoLoadTab, 'the Two-load view at the end');
            % the sequence
            tc.verifyEqual(app.TwList.Keys, {'A', 'B', 'A2', 'result'});
            % (load B 6 dB lower with pressure nodes of the rigid cap at M3 / M4:
            % fewer valid lines, 'warn' below 90 %)
            tc.verifyFalse(any(strcmp(app.TwList.States, 'fail')), strjoin(app.TwList.States, ' '));
            tc.verifyEqual(app.TwList.States([1 3 4]), {'ok', 'ok', 'ok'}, strjoin(app.TwList.States, ' '));
            tc.verifyEqual({app.LastLoads.role}, {'A', 'B', 'A2'});
            for i = 1:3
                tc.verifyTrue(isfile(fullfile(app.LastLoads(i).folder, 'raw.mat')), app.LastLoads(i).folder);
                tc.verifyNotEmpty(dir(fullfile(app.LastLoads(i).folder, 'fig_*.png')), 'figures of every load');
            end
            tc.verifyEqual(app.LastLoads(2).meas.settings.amplitudeVpp, ...
                app.LastLoads(1).meas.settings.amplitudeVpp * 10^(-6/20), 'RelTol', 1e-12, 'load B 6 dB lower');
            tc.verifyTrue(isfile(fullfile(app.SavedDir, 'twoload.json')), 'the pair folder');
            tc.verifyNotEmpty(dir(fullfile(app.SavedDir, 'fig_transferMatrix.png')));
            tc.verifySubstring(h.resultStatus.Text, 'Saved: ');
            tc.verifySubstring(h.resultStatus.Text, '_twoload');
            tm = app.LastTM;
            tc.verifyEqual(tm.method, 'twoLoad');
            tc.verifyGreaterThan(tm.valid.nValid, 0.5 * tm.valid.nBand);
            tc.verifyTrue(tm.repeat.performed && tm.repeat.ok, tm.repeat.text);
            % the views
            tc.verifyEqual(h.twShow.ItemsData, {'A', 'B', 'A2'});
            tc.verifyEqual(h.twShow.Enable, matlab.lang.OnOffSwitchState.on);
            tc.verifyEqual(app.Pages.twoload.SummaryTable.Data(:, 1).', {'A', 'B', ['A' char(8242)]});
            tc.verifyNotEmpty(findobj(h.axTw3D, 'Tag', 'termGlow'), 'the last load glowed');
            lg = h.axTL.Legend;
            tc.verifyEqual(lg.String{1}, 'TL from T (two loads)');
            tc.verifySubstring(h.axR(1).Title.String, 'Two loads: Absorber at tube end / Rigid cap at tube end');
            tc.verifySubstring(strjoin(cellstr(h.axV.YTickLabel), '|'), 'Valid T');
            tc.verifyEqual(h.axTM(1).Legend.String{1}, '|T_{11}|');
            tc.verifyEqual(app.LastMeas.metadata.twoLoad.role, 'A', 'load A shown');
            h.twShow.Value = 'B'; feval(h.twShow.ValueChangedFcn, h.twShow, []);
            tc.verifyEqual(app.LastMeas.metadata.termination.label, 'Rigid cap at tube end');
            tc.verifyEqual(h.axTL.Legend.String{1}, 'TL from T (two loads)', 'the transfer matrix stays');
            % Reprocess: every load, then T; not saved
            feval(h.reprocess.ButtonPushedFcn, h.reprocess, []);
            tc.verifyEqual(h.resultStatus.Text, 'Two-load result – not saved');
            tc.verifyEqual(app.LastTM.T.T12, tm.T.T12, 'RelTol', 1e-9, 'the same data and calibration');
            % Save: a new pair folder
            first = app.LastLoads(1).folder;
            feval(h.save.ButtonPushedFcn, h.save, []);
            d = app.SavedDir;
            tc.verifyTrue(isfile(fullfile(d, 'twoload.json')));
            info = jsondecode(tim.app.readTextUtf8(fullfile(d, 'twoload.json')));
            [~, fA] = fileparts(first);
            tc.verifyEqual(info.loads(1).folder, fA, 'the pair names the load folders');
            % Open the pair folder
            app.openMeasurement(d, false, false);
            tc.verifySubstring(h.resultStatus.Text, 'Opened: ');
            tc.verifyEqual({app.LastLoads.role}, {'A', 'B', 'A2'});
            tc.verifyEqual(app.LastTM.T.T12, tm.T.T12, 'RelTol', 1e-9);
            % Combine two load folders
            app.combineMeasurements(app.LastLoads(1).folder, app.LastLoads(2).folder);
            tc.verifyEqual({app.LastLoads.role}, {'A', 'B'});
            tc.verifyFalse(app.LastTM.repeat.performed);
            tc.verifyEqual(h.resultStatus.Text, 'Two-load result – not saved');
            % one load afterwards: no transfer matrix any more
            h.method.Value = 'oneLoad'; feval(h.method.ValueChangedFcn, h.method, []);
            feval(h.start.ButtonPushedFcn, h.start, []);
            tc.verifyEmpty(app.LastTM); tc.verifyEmpty(app.LastLoads);
            tc.verifyEqual(h.axTL.Legend.String{1}, ['TL = ' char(8722) '20 log_{10}|\tau|']);
            clear cleanup

            function recordTab(p)
                if strcmp(p, 'twoload:measuring'), shown{end + 1} = h.measTabs.SelectedTab; end
            end
        end

        function noCalibrationAskedBeforeStart(tc)
            % owner 2026-10-14: a whole run was made without a calibration (0 %
            % valid everywhere). The window asks first; Cancel (the default, also
            % of a hidden window) starts nothing
            app = tim.gui.Tubebench(tc.config(), 'Visible', 'off');
            cleanup = onCleanup(@() delete(app));
            h = app.H;
            feval(h.connect.ButtonPushedFcn, h.connect, []);
            tc.assertEmpty(app.Session.Calibration);
            h.method.Value = 'twoLoad'; feval(h.method.ValueChangedFcn, h.method, []);
            feval(h.start.ButtonPushedFcn, h.start, []);
            tc.verifyEmpty(app.LastLoads, 'nothing measured');
            tc.verifyEmpty(dir(fullfile(tc.tmp, 'data', '*_sweep_*')), 'nothing saved');
            tc.verifyTrue(any(contains(h.log.Value, 'Two-load measurement not started: no calibration loaded.')));
            clear cleanup
        end

        function oneLoadSymmetricInTheWindow(tc)
            % decision 1: T from one load, ASSUMING a symmetric specimen; saved
            % with the results and shown again when the folder is opened
            app = tim.gui.Tubebench(tc.config(), 'Visible', 'off');
            cleanup = onCleanup(@() delete(app));
            h = app.H;
            feval(h.connect.ButtonPushedFcn, h.connect, []);
            h.method.Value = 'oneLoadSymmetric'; feval(h.method.ValueChangedFcn, h.method, []);
            tc.verifyEqual(h.start.Text, 'Start measurement');
            feval(h.start.ButtonPushedFcn, h.start, []);
            tc.verifyEqual(app.LastTM.method, 'oneLoadSymmetric');
            tc.verifyEqual(app.LastRes.transferMatrix.method, 'oneLoadSymmetric');
            tc.verifyEqual(h.axTL.Legend.String{1}, 'TL from T (one load, symmetric specimen assumed)');
            tc.verifySubstring(h.axTM(1).Title.String, 'symmetric specimen ASSUMED');
            feval(h.save.ButtonPushedFcn, h.save, []);
            d = app.SavedDir;
            % the folder names the method (owner 2026-10-14), like ..._twoload_...
            [~, n] = fileparts(d);
            tc.verifyTrue(endsWith(n, '_oneload-symmetric_sweep'), n);
            h.method.Value = 'oneLoad'; feval(h.method.ValueChangedFcn, h.method, []);
            app.openMeasurement(d, false, false);
            tc.verifyEqual(app.LastTM.method, 'oneLoadSymmetric', 'the saved T is shown again');
            % one load
            h.specimen.Value = 'foam 25';
            feval(h.start.ButtonPushedFcn, h.start, []);
            feval(h.save.ButtonPushedFcn, h.save, []);
            [~, n] = fileparts(app.SavedDir);
            tc.verifyTrue(endsWith(n, '_oneload_sweep_foam_25'), n);
            clear cleanup
        end
    end
end
