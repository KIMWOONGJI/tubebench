classdef TubeApp < handle
    %TUBEAPP Graphical interface (uifigure, R2022b) of the transfer-impedance tube.
    %
    %   app = tim.gui.TubeApp();                      % default / example config
    %   app = tim.gui.TubeApp('config/user_config.json');
    %   app = tim.gui.TubeApp(file, 'Visible', 'off')  % hidden window (automated tests)
    %
    %   Layout: menu bar (File, Help); control panel on the left in workflow
    %   order (INSTRUMENTS, IMPEDANCE TUBE, EXCITATION, CALIBRATION,
    %   MEASUREMENT, RESULTS); on the right two-level tabs (Setup >
    %   Connection | Tube setup, Calibration, Measurement > Time signals |
    %   Spectrum | Transfer functions, Results > Reflection and transmission |
    %   Transmission loss | Transfer impedance | Validity, Formula) and the
    %   message pane at the bottom. Every graph is drawn by a tim.plots view,
    %   the same function that draws the saved figures.
    %
    %   The GUI is a thin layer over tim.app.MeasurementSession; every
    %   action is also available from scripts (see start_here.m). It is
    %   built programmatically with App Designer components (uifigure,
    %   uigridlayout, uiaxes ...) so the source is plain text.

    properties (SetAccess = private)
        Fig
        Session = []
        Cfg struct
        LastMeas = []
        LastRes = []
        H struct = struct()     % UI handles
        Pages struct = struct() % tim.gui.ViewPage of every view
        WaveLines = gobjects(0) % lines of the time-signal view (live update)
        Saved logical = true    % the last measurement is saved (or there is nothing to save)
        SavedDir char = ''      % folder of the last save
        GainEntered logical = true  % the gain was entered after an amplifier was chosen
        LastCheck char = ''     % last configuration warnings (logged once)
        CalStep double = 0      % current / total operator steps of a calibration
        CalSteps double = 0
        Busy logical = false    % an action is running (control panel locked)
        LiveCount double = 0    % number of live-view refreshes (diagnostics / tests)
        ConnList = []           % tim.gui.Checklist of the connection steps
        CalList = []            % tim.gui.Checklist of the calibration steps
        CalKeys cell = {}       % checklist key of every calibration operator step
        CalMap = []             % microphone mapping of the current calibration step
        CalDrawn = []           % mapping the 3D calibration model currently shows
        CalDirty logical = true % geometry / config / TEDS changed: redraw the calibration model
        CalDrawCount double = 0 % number of 3D calibration draws (diagnostics / tests)
        PulseTimer = []         % highlights the calibration ports while the operator works
        CloseAfterBusy logical = false  % window close requested during a running action
        Closing logical = false % closeNow running: further close requests are ignored
        ClosingWin = []         % "Closing ..." progress dialog (steps of the shutdown)
        ClosingLog cell = {}    % texts shown in the closing dialog (also when hidden: tests)
        AboutFig = []           % Help > About window (one at a time)
        OutputUnconfirmed logical = false  % last read-back did not confirm the generator output off
        PendingStop logical = false % Stop / close before the connection has a session (gui-5)
    end
    properties
        ConfirmUnsaved logical = true   % ask before an unsaved measurement is replaced or lost
    end

    methods
        function app = TubeApp(cfgFile, opts)
            arguments
                cfgFile = ''
                opts.Visible (1,:) char = 'on'
            end
            if ~isempty(cfgFile)
                app.Cfg = tim.app.loadConfig(cfgFile);
            else
                app.Cfg = tim.app.defaultConfig();
            end
            app.build(opts.Visible);
            app.refreshFromCfg();
            app.refreshViews();
            app.updateEnable();
            app.log(['Ready (%s mode). Not connected - "Connect" switches the generator output OFF; it is ' ...
                'switched on only during a measurement or a calibration.'], app.Cfg.mode);
        end

        function delete(app)
            try, app.stopPulse(); catch, end
            try, app.disconnect(true); catch, end
            if ~isempty(app.AboutFig) && isvalid(app.AboutFig), delete(app.AboutFig); end
            if ~isempty(app.Fig) && isvalid(app.Fig), delete(app.Fig); end
        end

        function disconnect(app, quiet)
            % close the session (instruments to a safe state); quiet: no log line
            if nargin < 2, quiet = false; end
            if ~isempty(app.Session)
                try, app.Session.close(); catch, end
                app.Session = [];
                app.OutputUnconfirmed = false;
                if ~quiet, app.log('Disconnected.'); end
                if isfield(app.H, 'connHead') && isvalid(app.H.connHead)
                    app.H.connHead.Text = 'Disconnected. The list shows the last connection.';
                    app.H.connHead.FontColor = [0.3 0.3 0.3];
                end
            end
            if isfield(app.H, 'status') && isvalid(app.H.status), app.setStatus('Not connected', 'idle'); end
            if isfield(app.H, 'lamp') && all(isvalid(app.H.lamp))
                P = tim.gui.palette();
                set(app.H.lamp, 'Color', P.idle);
                for c = 1:4, app.H.card(c).lamp.Color = P.idle; app.H.card(c).state.Text = 'not connected'; end
            end
            if isfield(app.H, 'calLabel') && isvalid(app.H.calLabel), app.refreshCalLabel(); end
            if ~app.Busy && isfield(app.H, 'start') && isvalid(app.H.start), app.updateEnable(); end
        end
    end

    methods
        function unlockUi(app)
            %UNLOCKUI Restore the controls after a busy action (used by the run wrapper).
            app.setBusy(false);
        end

        function closeRequest(app)
            %CLOSEREQUEST Window close (tim.gui.closeApp). A "Closing" dialog appears
            %   at once in the window and shows the shutdown steps (its bar keeps
            %   moving while MATLAB waits for an instrument). During a running
            %   action STOP is requested first and the window closes when the
            %   action has stopped; a second request closes at once. An unsaved
            %   measurement is not lost silently.
            if app.Closing, return; end               % already closing (repeated click)
            if app.Busy && ~app.CloseAfterBusy
                app.CloseAfterBusy = true;
                if ~isempty(app.Session)
                    app.Session.log('Closing: window close requested while busy - STOP requested first.');
                    app.Session.requestStop();
                    try, app.Session.Gen.outputOff(); catch, end
                else
                    app.PendingStop = true;            % connection without a session yet
                end
                app.closingDialog({'Stopping the running action ...', ...
                    [app.outputOffText() ' The window closes as soon as the action has stopped.']});
                return
            end
            if ~app.Busy && ~app.confirmDiscard('Close the program')
                return
            end
            app.closeNow();
        end

        function [geom, env, msgs] = currentGeometry(app)
            %CURRENTGEOMETRY Geometry [m] and environment as entered in the
            %   IMPEDANCE TUBE fields (coordinates on a 1 nm grid).
            [geom, env, msgs] = app.readTube();
        end

        function sel = ask(app, msg, title, options, defaultIdx, cancelIdx, icon)
            %ASK Operator dialog that can never hang MATLAB: non-blocking
            %   uiconfirm and a wait loop. (A blocking uiconfirm does not return
            %   when the window is closed meanwhile - found in a test on
            %   2026-10-09.) Timers keep running while it waits (pulsing
            %   ports). Closing the window or STOP returns the cancel option; a
            %   hidden window (scripts, tests) returns the default option.
            if nargin < 7, icon = 'question'; end
            % STOP already pending (e.g. pressed during the microphone animation)
            % or window gone: do not open a dialog that nobody would close
            % (only INSIDE a running action: a flag left over from an earlier Stop must not
            % answer a later question - e.g. the unsaved-measurement question - unseen)
            if ~isvalid(app) || ~isvalid(app.Fig) || app.stopPending()
                sel = options{cancelIdx}; return
            end
            if ~strcmp(app.Fig.Visible, 'on'), sel = options{defaultIdx}; return; end
            answer = '';
            function setAnswer(s)
                answer = s;
            end
            uiconfirm(app.Fig, msg, title, 'Options', options, 'DefaultOption', defaultIdx, ...
                'CancelOption', cancelIdx, 'Icon', icon, 'CloseFcn', @(~, ev) setAnswer(ev.SelectedOption));
            while isempty(answer)
                if ~isvalid(app) || ~isvalid(app.Fig) || app.stopPending()
                    answer = options{cancelIdx};
                    break
                end
                pause(0.1);
            end
            sel = answer;
        end

        function alert(app, msg, ttl, icon)
            % message dialog; a hidden window (scripts, tests) only logs it
            % (uialert needs a visible figure)
            if nargin < 4, icon = 'info'; end
            if ~isempty(app.Fig) && isvalid(app.Fig) && strcmp(app.Fig.Visible, 'on')
                uialert(app.Fig, msg, ttl, 'Icon', icon);
            else
                app.log('%s: %s', ttl, msg);
            end
        end
        function tf = stopPending(app)
            % Stop pressed during the running action (the session keeps the flag
            % until the next action starts; outside an action it means nothing)
            s = app.Session;
            tf = ~isempty(s) && isvalid(s) && s.InOperation && s.StopRequested;
        end

        function drawCalSetup(app, mapping, msg, stepText, fromMapping)
            % Calibration diagram = the 3D model of the Tube setup view in its
            % calibration state (empty specimen section, absorbing termination,
            % calibration ports a/b glowing, microphones labelled with DAQ
            % channel + s/n; mapping(c) = port of channel c). The model is drawn
            % once (~1 s); the steps only change the text and move the
            % microphones (animateCalMics). With fromMapping the microphones are
            % shown where they were before this step.
            if nargin < 5 || isempty(fromMapping), fromMapping = mapping; end
            shown = fromMapping; if isempty(shown), shown = app.homeMapping(); end
            M = app.H.cal3D;
            if app.CalDirty || isempty(M) || ~all(isgraphics(M.micGroup(shown > 0))) || ~isequal(app.CalDrawn, shown)
                app.drawCalModel(shown);
            end
            app.setCalText(mapping, msg, stepText);
        end

        function showCal(app, cal)
            % calibration curves C_k + summary of the calibration view, label
            info = tim.plots.calibration(app.H.axCal, cal, app.plotOpts(cal));
            app.Pages.cal.show(info);
            app.refreshCalLabel();
        end
    end

    methods (Access = private)
        %% ----------------------------------------------------------- layout
        function build(app, visible)
            % window fills the screen (maximised); restored size = most of the screen
            P = tim.gui.palette();
            scr = get(groot, 'ScreenSize');
            W = max(1400, scr(3) - 80); Hh = max(800, scr(4) - 120);
            app.Fig = uifigure('Name', 'Transfer impedance tube', 'Position', [40 50 W Hh], 'Visible', visible, ...
                'Color', P.ui.panel, 'CloseRequestFcn', @(src, ~) tim.gui.closeApp(src, app));   % never gets stuck
            if strcmp(visible, 'on')
                try, app.Fig.WindowState = 'maximized'; catch, end
            end
            h = struct();
            % ---------------- menu bar (version + repository: Help > About)
            m = uimenu(app.Fig, 'Text', 'File');
            h.mLoadCfg = uimenu(m, 'Text', 'Load configuration…', 'MenuSelectedFcn', @(~, ~) app.onLoadConfig());
            h.mSaveCfg = uimenu(m, 'Text', 'Save configuration…', 'MenuSelectedFcn', @(~, ~) app.onSaveConfig());
            h.mExit = uimenu(m, 'Text', 'Exit', 'Separator', 'on', 'MenuSelectedFcn', @(~, ~) tim.gui.closeApp(app.Fig, app));
            m = uimenu(app.Fig, 'Text', 'Help');
            docs = {'User guide', 'user_guide.md'; 'Calibration procedure', 'calibration_procedure.md'; ...
                'Validation procedure', 'validation_procedure.md'; 'Installation (Windows)', 'installation_windows.md'};
            h.mHelp = gobjects(0);
            for i = 1:size(docs, 1)
                h.mHelp(end + 1) = uimenu(m, 'Text', docs{i, 1}, 'MenuSelectedFcn', @(~, ~) app.openDoc(docs{i, 2}));
            end
            h.mHelp(end + 1) = uimenu(m, 'Text', 'Source code on GitHub', 'Separator', 'on', ...
                'MenuSelectedFcn', @(~, ~) web(tim.app.repositoryUrl(), '-browser'));
            h.mAbout = uimenu(m, 'Text', 'About', 'Separator', 'on', 'MenuSelectedFcn', @(~, ~) app.showAbout());
            h.mHelp(end + 1) = h.mAbout;

            g = uigridlayout(app.Fig, [1 2], 'ColumnWidth', {412, '1x'}, 'Padding', [0 0 0 0], ...
                'ColumnSpacing', 0, 'BackgroundColor', P.ui.panel);
            % ---------------- control panel (left), workflow order. Fixed row
            % heights [px]: about 860 px -> no scrolling in the maximised window
            % on the lab screen (1920 x 1080: about 985 px); Scrollable stays on
            % as a fallback for small screens.
            bar = 26; rw = 24; sp = 4;
            rowH = {bar, 26, 22, 22, ...                    %  1- 4 INSTRUMENTS: bar, mode + connect, status, lamps
                sp, bar, rw, 16, rw, 30, ...                %  5-10 IMPEDANCE TUBE: spacer, bar, D/T/p, names, distances, info
                sp, bar, rw, rw, rw, rw, rw, rw, rw, 30, ...% 11-20 EXCITATION: spacer, bar, 7 field rows, drive
                sp, bar, 22, 28, ...                        % 21-24 CALIBRATION: spacer, bar, status, buttons
                sp, bar, rw, 36, 26, ...                    % 25-29 MEASUREMENT: spacer, bar, specimen, start / stop, background
                sp, bar, 22, 28};                           % 30-33 RESULTS: spacer, bar, status, buttons
            left = uigridlayout(g, [numel(rowH) 1], 'RowHeight', rowH, 'ColumnWidth', {'1x'}, ...
                'Scrollable', 'on', 'RowSpacing', 4, 'Padding', [10 8 10 8], 'BackgroundColor', P.ui.panel);
            left.Layout.Row = 1; left.Layout.Column = 1;
            h.left = left;
            LW = 106;                                 % label column of the two-column rows
            ex = {116, '1x', 104, '1x'};              % excitation rows: label, field, label, field
            r = 0;
            % ---------------- INSTRUMENTS
            r = r + 1; app.sectionBar(left, r, 'INSTRUMENTS');
            r = r + 1; rg = app.rowGrid(left, r, {LW, '1x', 86, 86});
            app.label(rg, 'Operating mode', 'Simulation: virtual tube for practice. Hardware: generator and LAN-XI module.');
            h.mode = uidropdown(rg, 'Items', {'Simulation', 'Hardware'}, 'ItemsData', {'simulation', 'hardware'}, ...
                'Tooltip', 'Simulation: virtual tube (practice, tests). Hardware: the real instruments. Fixed while connected.');
            h.connect = uibutton(rg, 'Text', 'Connect', 'ButtonPushedFcn', @(~, ~) app.onConnect(), ...
                'Tooltip', ['Connect the generator and the LAN-XI module (generator output off), read TEDS ' ...
                'and check every channel (Setup > Connection).']);
            h.disconnect = uibutton(rg, 'Text', 'Disconnect', 'ButtonPushedFcn', @(~, ~) app.onDisconnect(), ...
                'Tooltip', 'Generator output off, LAN-XI module back to Idle, connections closed.');
            r = r + 1; rg = app.rowGrid(left, r, {LW, '1x'});
            app.label(rg, 'Status');
            h.status = uilabel(rg, 'Text', 'Not connected', 'FontColor', P.ui.muted, 'FontWeight', 'bold');
            % status lamps: generator, LAN-XI, the four channels (details: Setup > Connection)
            r = r + 1; gl = app.rowGrid(left, r, {88, 70, '1x', '1x', '1x', '1x'});
            names = {'Generator', 'LAN-XI', 'ch1', 'ch2', 'ch3', 'ch4'};
            tips = {'function generator 33220A', 'LAN-XI module', 'channel 1', 'channel 2', 'channel 3', 'channel 4'};
            for i = 1:6
                gi = uigridlayout(gl, [1 2], 'Padding', [0 0 0 0], 'ColumnSpacing', 4, 'ColumnWidth', {13, '1x'}, ...
                    'BackgroundColor', P.ui.panel);
                h.lamp(i) = uilamp(gi, 'Color', P.idle, 'Tooltip', [tips{i} ' - details in Setup > Connection']);
                uilabel(gi, 'Text', names{i}, 'FontSize', 11, 'Tooltip', tips{i});
            end
            % ---------------- IMPEDANCE TUBE
            r = r + 2; app.sectionBar(left, r, 'IMPEDANCE TUBE', 'lengths in mm');
            r = r + 1; rg = app.rowGrid(left, r, {LW, '1x', 46, '1x', 50, '1x'});
            cb = @(~, ~) app.onTubeChanged();
            app.label(rg, 'Diameter [mm]', 'INNER diameter of the tube');
            h.tubeD = uieditfield(rg, 'numeric', 'Limits', [1 500], 'ValueDisplayFormat', '%.10g', ...
                'Tooltip', 'inner diameter of the tube [mm]', 'ValueChangedFcn', cb);
            app.label(rg, 'T [°C]', 'air temperature', 'right');
            h.temp = uieditfield(rg, 'numeric', 'Limits', [-20 60], 'Tooltip', 'air temperature [°C]', 'ValueChangedFcn', cb);
            app.label(rg, 'p [kPa]', 'static air pressure', 'right');
            h.pres = uieditfield(rg, 'numeric', 'Limits', [50 120], 'ValueDisplayFormat', '%.6g', ...
                'Tooltip', 'static air pressure [kPa]', 'ValueChangedFcn', cb);
            % distances between clearly defined points (port centres, specimen faces), in the
            % order of the tube (loudspeaker on the left); empty ('?') = not measured yet.
            tip = 'distance between microphone PORT CENTRES (centre of the port hole), in mm';
            nm = '  (empty = not measured: specimen results R, τ, Z_t, TL disabled)';
            dTips = {['s1, upstream spacing: ' tip], ...
                ['L1: from the centre of port M2 to the FRONT face of the specimen (the face towards the loudspeaker), in mm' nm], ...
                ['d: specimen thickness, from the front face to the rear face, in mm (0 for a thin screen)' nm], ...
                ['L2: from the REAR face of the specimen (towards the termination) to the centre of port M3, in mm' nm], ...
                ['s2, downstream spacing: ' tip]};
            dNames = {'s1  M1–M2', 'L1  M2–front', 'd  thickness', 'L2  rear–M3', 's2  M3–M4'};
            r = r + 1; rg = app.rowGrid(left, r, repmat({'1x'}, 1, 5));
            for i = 1:5
                uilabel(rg, 'Text', dNames{i}, 'HorizontalAlignment', 'center', 'FontSize', 11, ...
                    'FontColor', P.ui.muted, 'Tooltip', dTips{i});
            end
            r = r + 1; rg = app.rowGrid(left, r, repmat({'1x'}, 1, 5));
            h.s1 = uieditfield(rg, 'numeric', 'Limits', [1 1000], 'ValueDisplayFormat', '%.10g', ...
                'HorizontalAlignment', 'center', 'Tooltip', dTips{1}, 'ValueChangedFcn', cb);
            h.L1 = uieditfield(rg, 'text', 'Placeholder', '?', 'HorizontalAlignment', 'center', ...
                'Tooltip', dTips{2}, 'ValueChangedFcn', cb);
            h.dTh = uieditfield(rg, 'text', 'Placeholder', '?', 'HorizontalAlignment', 'center', ...
                'Tooltip', dTips{3}, 'ValueChangedFcn', cb);
            h.L2 = uieditfield(rg, 'text', 'Placeholder', '?', 'HorizontalAlignment', 'center', ...
                'Tooltip', dTips{4}, 'ValueChangedFcn', cb);
            h.s2 = uieditfield(rg, 'numeric', 'Limits', [1 1000], 'ValueDisplayFormat', '%.10g', ...
                'HorizontalAlignment', 'center', 'Tooltip', dTips{5}, 'ValueChangedFcn', cb);
            r = r + 1; h.fLimits = uilabel(left, 'Text', '', 'FontSize', 11, 'WordWrap', 'on', ...
                'VerticalAlignment', 'top', 'FontColor', P.ui.muted);
            h.fLimits.Layout.Row = r; h.fLimits.Layout.Column = 1;
            % ---------------- EXCITATION
            r = r + 2; app.sectionBar(left, r, 'EXCITATION');
            r = r + 1; rg = app.rowGrid(left, r, ex);
            app.label(rg, 'Signal');
            h.exMode = uidropdown(rg, 'Items', {'Swept sine', 'Stepped sine'}, 'ItemsData', {'sweep', 'stepped'}, 'Tooltip', ...
                'Swept sine: broadband measurement (default). Stepped sine: discrete frequencies, for cross-checks.', ...
                'ValueChangedFcn', @(~, ev) app.onExMode(ev.PreviousValue));
            h.exMode.Layout.Column = [2 4];
            r = r + 1; rg = app.rowGrid(left, r, ex);
            app.label(rg, 'Frequency [Hz]', 'Start and stop frequency of the excitation.');
            h.fStart = uieditfield(rg, 'numeric', 'Limits', [1 1e5], 'ValueDisplayFormat', '%.6g', ...
                'Tooltip', 'Start frequency of the excitation [Hz].', 'ValueChangedFcn', @(~, ~) app.updateDrive());
            app.label(rg, 'to', '', 'center');
            h.fStop = uieditfield(rg, 'numeric', 'Limits', [1 1e5], 'ValueDisplayFormat', '%.6g', ...
                'Tooltip', 'Stop frequency of the excitation [Hz]; at most 0.45 × sample rate.', ...
                'ValueChangedFcn', @(~, ~) app.updateDrive());
            r = r + 1; rg = app.rowGrid(left, r, ex);
            h.durLabel = app.label(rg, 'Sweep duration [s]');
            h.dur = uieditfield(rg, 'numeric', 'Limits', [0.001 500], 'ValueChangedFcn', @(~, ~) app.updateDrive());
            app.label(rg, 'Repetitions', 'Number of repetitions (averaged).');
            h.reps = uieditfield(rg, 'numeric', 'Limits', [1 100], 'RoundFractionalValues', 'on', ...
                'ValueChangedFcn', @(~, ~) app.updateDrive());
            r = r + 1; rg = app.rowGrid(left, r, ex);
            app.label(rg, 'Amplitude [Vpk]', 'Generator amplitude in Vpk (details: tooltip of the field).');
            h.amp = uieditfield(rg, 'numeric', 'Limits', [0.005 10], 'ValueChangedFcn', @(~, ~) app.updateDrive());
            app.label(rg, 'Duration', 'Expected duration of one measurement.');
            h.durEst = uilabel(rg, 'Text', '', 'FontColor', P.ui.muted);
            r = r + 1; rg = app.rowGrid(left, r, ex);
            app.label(rg, 'Amplifier', 'Power amplifier between the generator and the loudspeaker.');
            h.ampModel = uidropdown(rg, 'Editable', 'on', 'Items', {'none (direct drive)', 'power amplifier'}, ...
                'Tooltip', 'Select, or type the model of the power amplifier (typed models are added).', ...
                'ValueChangedFcn', @(~, ~) app.onAmpModel(true));
            h.ampModel.Layout.Column = [2 4];
            r = r + 1; rg = app.rowGrid(left, r, ex);
            app.label(rg, 'Amplifier gain', 'Voltage gain of the power amplifier as a factor (×10 = 20 dB).');
            h.ampGain = uieditfield(rg, 'numeric', 'Limits', [0 Inf], 'ValueDisplayFormat', '×%.4g', ...
                'Tooltip', 'Voltage gain of the power amplifier as a factor (×10 = 20 dB); used to estimate the loudspeaker drive.', ...
                'ValueChangedFcn', @(~, ~) app.onGainChanged());
            app.label(rg, 'Loudspeaker [Ω]', 'Nominal loudspeaker impedance.');
            h.spkZ = uieditfield(rg, 'numeric', 'Limits', [0.5 1000], 'ValueChangedFcn', @(~, ~) app.updateDrive(), ...
                'Tooltip', 'Nominal loudspeaker impedance [Ω].');
            r = r + 1; rg = app.rowGrid(left, r, ex);
            app.label(rg, 'Power limit [W]', 'Loudspeaker power limit.');
            h.spkP = uieditfield(rg, 'numeric', 'Limits', [1e-4 1000], 'ValueChangedFcn', @(~, ~) app.updateDrive(), ...
                'Tooltip', 'Loudspeaker power limit [W]: an excitation above this estimated loudspeaker power is refused.');
            r = r + 1; h.drive = uilabel(left, 'Text', '', 'FontSize', 11, 'WordWrap', 'on', 'VerticalAlignment', 'top');
            h.drive.Layout.Row = r; h.drive.Layout.Column = 1;
            % ---------------- CALIBRATION
            r = r + 2; app.sectionBar(left, r, 'CALIBRATION');
            r = r + 1; rg = app.rowGrid(left, r, {LW, '1x'});
            app.label(rg, 'Calibration');
            h.calLabel = uilabel(rg, 'Text', 'No calibration – results not valid', 'FontColor', P.fail, 'FontWeight', 'bold');
            r = r + 1; rg = app.rowGrid(left, r, {'1x', '1x'});
            h.loadCal = uibutton(rg, 'Text', 'Load calibration…', 'ButtonPushedFcn', @(~, ~) app.onLoadCal(), ...
                'Tooltip', 'Load a calibration file (CAL-*.mat) from the calibration folder.');
            h.runCal = uibutton(rg, 'Text', 'Run switching calibration…', 'ButtonPushedFcn', @(~, ~) app.onRunCal(), ...
                'Tooltip', 'Switching calibration with the empty specimen section; the operator steps are shown in the Calibration view.');
            % ---------------- MEASUREMENT
            r = r + 2; app.sectionBar(left, r, 'MEASUREMENT');
            r = r + 1; rg = app.rowGrid(left, r, {LW, '1x'});
            app.label(rg, 'Specimen', 'Name of the specimen; it becomes part of the name of the data folder.');
            h.specimen = uieditfield(rg, 'text', 'Placeholder', 'Name of the specimen (data folder)', ...
                'Tooltip', 'Name of the specimen; it becomes part of the name of the data folder.');
            r = r + 1; rg = app.rowGrid(left, r, {'1x', 116});
            h.start = uibutton(rg, 'Text', 'Start measurement', 'BackgroundColor', P.ui.start, 'FontColor', 'w', ...
                'FontWeight', 'bold', 'FontSize', 13, 'Icon', tim.gui.icon('start'), 'ButtonPushedFcn', @(~, ~) app.onStart(), ...
                'Tooltip', 'Measure the specimen with the selected signal (hardware mode: asks before the loudspeaker is driven).');
            h.stop = uibutton(rg, 'Text', 'Stop', 'BackgroundColor', P.ui.stop, 'FontColor', 'w', 'FontWeight', 'bold', ...
                'FontSize', 13, 'Icon', tim.gui.icon('stop'), 'ButtonPushedFcn', @(~, ~) app.onStop(), ...
                'Tooltip', 'Stop the running action; the generator output is switched off at once.');
            r = r + 1; rg = app.rowGrid(left, r, {'1x'});
            h.background = uibutton(rg, 'Text', 'Measure background noise', 'ButtonPushedFcn', @(~, ~) app.onBackground(), ...
                'Tooltip', 'Record 2 s without excitation (background noise level of every channel).');
            % ---------------- RESULTS
            r = r + 2; app.sectionBar(left, r, 'RESULTS');
            r = r + 1; rg = app.rowGrid(left, r, {LW, '1x'});
            app.label(rg, 'Last result');
            h.resultStatus = uilabel(rg, 'Text', 'No measurement', 'FontColor', P.ui.muted);
            r = r + 1; rg = app.rowGrid(left, r, {'1x', '1x'});
            h.save = uibutton(rg, 'Text', 'Save measurement', 'ButtonPushedFcn', @(~, ~) app.onSave(), ...
                'Tooltip', 'Raw data, results, configuration, metadata, CSV files and figures into a new folder under data/.');
            h.reprocess = uibutton(rg, 'Text', 'Reprocess', 'ButtonPushedFcn', @(~, ~) app.onReprocess(), ...
                'Tooltip', 'Recompute the results of the last measurement with the current fields and calibration.');
            assert(r == numel(rowH), 'layout: rowH must list exactly one height per control-panel row');
            % spacer rows
            for k = find(cellfun(@(x) isequal(x, sp), rowH))
                s = uilabel(left, 'Text', ''); s.Layout.Row = k; s.Layout.Column = 1;
            end

            % ---------------- views (right): two-level tabs + message pane
            right = uigridlayout(g, [2 1], 'RowHeight', {'1x', 124}, 'RowSpacing', 0, 'Padding', [0 0 0 0], ...
                'BackgroundColor', 'w');
            right.Layout.Row = 1; right.Layout.Column = 2;
            tabs = uitabgroup(right);
            tabs.Layout.Row = 1; tabs.Layout.Column = 1;
            h.tabs = tabs;
            mp = uigridlayout(right, [2 1], 'RowHeight', {20, '1x'}, 'Padding', [10 4 10 8], 'RowSpacing', 2, ...
                'BackgroundColor', P.ui.header);
            mp.Layout.Row = 2; mp.Layout.Column = 1;
            uilabel(mp, 'Text', 'Messages', 'FontWeight', 'bold', 'FontSize', 11, 'FontColor', P.ui.text);
            h.log = uitextarea(mp, 'Editable', 'off', 'FontName', 'Consolas', 'FontSize', 11);

            % Setup > Connection | Tube setup
            t = uitab(tabs, 'Title', 'Setup'); h.setupTab = t;
            h.setupTabs = app.subTabs(t);
            h.connTab = uitab(h.setupTabs, 'Title', 'Connection');
            pg = tim.gui.ViewPage(h.connTab, 'Connection', ['Every step of the connection: generator, LAN-XI, ' ...
                'TEDS, sensitivities and a 1 s signal check without excitation. The generator output stays OFF.'], ...
                'Summary', false);
            app.Pages.conn = pg;
            tg = uigridlayout(pg.Body, [4 1], 'RowHeight', {24, 290, 128, '1x'}, 'RowSpacing', 8, ...
                'Padding', [6 2 0 0], 'BackgroundColor', 'w');
            h.connHead = uilabel(tg, 'Text', 'Press "Connect": every step of the connection is checked here.', ...
                'FontWeight', 'bold', 'FontSize', 13);
            pc = uipanel(tg, 'Title', 'Connection checklist', 'FontWeight', 'bold', 'BackgroundColor', 'w');
            app.ConnList = tim.gui.Checklist(pc, app.connKeys(), app.connLabels(), struct('LabelWidth', 270));
            gc = uigridlayout(tg, [1 4], 'ColumnSpacing', 10, 'Padding', [0 0 0 0], 'BackgroundColor', 'w');
            for c = 1:4
                pnl = uipanel(gc, 'BackgroundColor', 'w', 'BorderType', 'line');
                g2 = uigridlayout(pnl, [5 3], 'RowHeight', {22, 20, 18, 18, 18}, 'ColumnWidth', {5, 16, '1x'}, ...
                    'Padding', [0 4 8 4], 'RowSpacing', 2, 'ColumnSpacing', 6, 'BackgroundColor', 'w');
                stripe = uilabel(g2, 'Text', '', 'BackgroundColor', P.ch(c, :));     % channel colour
                stripe.Layout.Row = [1 5]; stripe.Layout.Column = 1;
                hd = uilabel(g2, 'Text', sprintf('ch%d', c), 'FontWeight', 'bold', 'FontColor', P.ui.text);
                hd.Layout.Row = 1; hd.Layout.Column = [2 3];
                card = struct('head', hd, 'lamp', uilamp(g2, 'Color', P.idle), ...
                    'state', uilabel(g2, 'Text', 'not connected', 'FontWeight', 'bold'));
                card.lamp.Layout.Row = 2; card.lamp.Layout.Column = 2;
                card.state.Layout.Row = 2; card.state.Layout.Column = 3;
                for k = 3:5
                    l = uilabel(g2, 'Text', '', 'FontSize', 11, 'FontColor', P.ui.muted);
                    l.Layout.Row = k; l.Layout.Column = [2 3];
                    card.(sprintf('line%d', k - 2)) = l;
                end
                h.card(c) = card;
            end
            h.chanTable = uitable(tg, 'ColumnName', {'Channel', 'Port', 'Microphone', 'Sensitivity [mV/Pa]', ...
                'Source', 'TEDS s/n', 'Level [dB SPL]', 'Signal check'}, 'RowName', {}, 'FontSize', 11, ...
                'Data', cell(0, 8));
            h.tubeTab = uitab(h.setupTabs, 'Title', 'Tube setup');
            pg = tim.gui.ViewPage(h.tubeTab, 'Tube setup', ['3D model of the tube as entered in IMPEDANCE TUBE ' ...
                '(distances between port centres and specimen faces); microphones coloured by the channel in the port.'], ...
                'SummaryTitle', 'Geometry', 'ToolWidths', {72, 52, 92, 48, 14, 104, 96});
            app.Pages.tube = pg;
            views = {'Default', 'default'; 'Side', 'side'; 'Perspective', 'perspective'; 'Top', 'top'};
            for i = 1:4
                uibutton(pg.Tools, 'Text', views{i, 1}, 'ButtonPushedFcn', @(~, ~) app.tubeView(views{i, 2}), ...
                    'Tooltip', 'viewpoint (rotate / zoom freely with the toolbar of the drawing)');
            end
            uilabel(pg.Tools, 'Text', '');
            h.secChk = uicheckbox(pg.Tools, 'Text', 'Section view', 'Value', true, ...
                'Tooltip', 'remove the half towards the viewer: bore, specimen and microphone tips visible', ...
                'ValueChangedFcn', @(~, ~) app.onTubeChanged());
            h.dimChk = uicheckbox(pg.Tools, 'Text', 'Dimensions', 'Value', true, ...
                'ValueChangedFcn', @(~, ~) app.onTubeChanged());
            tg = uigridlayout(pg.Body, [2 1], 'RowHeight', {'1x', 0}, 'RowSpacing', 2, 'Padding', [0 0 0 0], ...
                'BackgroundColor', 'w');
            h.axTube3D = uiaxes(tg);
            axtoolbar(h.axTube3D, {'rotate', 'zoomin', 'zoomout', 'pan', 'restoreview'});
            h.tubeInfo = uilabel(tg, 'Text', '', 'FontSize', 11, 'FontColor', P.ui.muted, 'WordWrap', 'on', ...
                'VerticalAlignment', 'top');

            % Calibration: operator instruction, 3D diagram, step list, C_k curves
            t = uitab(tabs, 'Title', 'Calibration'); h.calTab = t;
            pg = tim.gui.ViewPage(t, 'Calibration', ['Switching calibration of the microphone channels with ' ...
                'the empty specimen section (ISO 10534-2): every microphone keeps its cable; only the microphones move.'], ...
                'SummaryTitle', 'Calibration', 'SummaryWidth', 450);
            app.Pages.cal = pg;
            tg = uigridlayout(pg.Body, [3 2], 'RowHeight', {50, '1.25x', '1x'}, 'ColumnWidth', {'1.15x', '1x'}, ...
                'RowSpacing', 6, 'ColumnSpacing', 10, 'Padding', [0 0 0 0], 'BackgroundColor', 'w');
            h.calText = uilabel(tg, 'Text', '', 'WordWrap', 'on', 'FontSize', 12, 'VerticalAlignment', 'top');
            h.calText.Layout.Row = 1; h.calText.Layout.Column = [1 2];
            h.axCalSetup = uiaxes(tg); h.axCalSetup.Layout.Row = 2; h.axCalSetup.Layout.Column = [1 2];
            axtoolbar(h.axCalSetup, {'rotate', 'zoomin', 'zoomout', 'pan', 'restoreview'});
            pcal = uipanel(tg, 'Title', 'Operator steps and quality of every measurement', 'FontWeight', 'bold', ...
                'BackgroundColor', 'w');
            pcal.Layout.Row = 3; pcal.Layout.Column = 1;
            app.CalList = tim.gui.Checklist(pcal, {}, {}, ...
                struct('LabelWidth', 250, 'RowHeight', 21, 'FontSize', 11));
            gk = uipanel(tg, 'BorderType', 'none', 'BackgroundColor', 'w');
            gk.Layout.Row = 3; gk.Layout.Column = 2;
            tl = tiledlayout(gk, 2, 1, 'TileSpacing', 'compact', 'Padding', 'compact');   % aligned plot areas
            for i = 1:2
                ax = nexttile(tl); tim.plots.style(ax);
                axtoolbar(ax, {'export', 'zoomin', 'zoomout', 'pan', 'restoreview'});
                h.axCal(i) = ax;
            end

            % Measurement > Time signals | Spectrum | Transfer functions
            % (titles and descriptions: tim.plots.viewText, shared with the saved figures)
            t = uitab(tabs, 'Title', 'Measurement'); h.measTab = t;
            h.measTabs = app.subTabs(t);
            [vt, vd] = tim.plots.viewText('waveforms');
            h.waveTab = uitab(h.measTabs, 'Title', vt);
            app.Pages.wave = tim.gui.ViewPage(h.waveTab, vt, vd, 'Axes', 4);
            h.axW = app.Pages.wave.Axes;
            [vt, vd] = tim.plots.viewText('spectrum');
            h.specTab = uitab(h.measTabs, 'Title', vt);
            app.Pages.spec = tim.gui.ViewPage(h.specTab, vt, vd, 'Axes', 1);
            h.axSpec = app.Pages.spec.Axes;
            [vt, vd] = tim.plots.viewText('transfer');
            h.tfTab = uitab(h.measTabs, 'Title', vt);
            app.Pages.tf = tim.gui.ViewPage(h.tfTab, vt, vd, 'Axes', 3);
            h.axH = app.Pages.tf.Axes;

            % Results > Reflection and transmission | Transmission loss | Transfer impedance | Validity
            t = uitab(tabs, 'Title', 'Results'); h.resTab = t;
            h.resTabs = app.subTabs(t);
            [vt, vd] = tim.plots.viewText('reflection');
            h.reflTab = uitab(h.resTabs, 'Title', vt);
            app.Pages.refl = tim.gui.ViewPage(h.reflTab, vt, vd, 'Axes', 2, 'AxesHeights', {'2x', '1x'}, ...
                'SummaryTitle', 'Octave bands');
            h.axR = app.Pages.refl.Axes;
            [vt, vd] = tim.plots.viewText('transmissionLoss');
            h.tlTab = uitab(h.resTabs, 'Title', vt);
            app.Pages.tl = tim.gui.ViewPage(h.tlTab, vt, vd, 'Axes', 1, 'SummaryTitle', 'Octave bands');
            h.axTL = app.Pages.tl.Axes;
            [vt, vd] = tim.plots.viewText('impedance');
            h.ztTab = uitab(h.resTabs, 'Title', vt);
            app.Pages.zt = tim.gui.ViewPage(h.ztTab, vt, vd, 'Axes', 2, 'SummaryTitle', 'Octave bands');
            h.axZ = app.Pages.zt.Axes;
            [vt, vd] = tim.plots.viewText('validity');
            h.validTab = uitab(h.resTabs, 'Title', vt);
            app.Pages.valid = tim.gui.ViewPage(h.validTab, vt, vd, 'Axes', 1, 'SummaryTitle', 'Criteria', ...
                'SummaryWidth', 470);
            h.axV = app.Pages.valid.Axes;

            % Formula: every equation used by the software
            t = uitab(tabs, 'Title', 'Formula'); h.formulaTab = t;
            tim.gui.equationsPanel(t);

            tabs.SelectionChangedFcn = @(~, ev) app.onTabChanged(ev);
            h.cal3D = []; h.calPaths = gobjects(0); h.calHi = gobjects(0);
            app.H = h;
            app.setCalText([], '', '');      % the 3D model is drawn when the tab is opened or at the first step
        end

        function tg = subTabs(~, tab)
            % second-level tab group inside a major tab
            gg = uigridlayout(tab, [1 1], 'Padding', [0 0 0 0], 'BackgroundColor', 'w');
            tg = uitabgroup(gg);
        end

        function k = connKeys(~)
            k = {'gen', 'lanxi', 'idle', 'open', 'teds', 'setup', 'sens', 'settle', 'signal'};
        end
        function l = connLabels(~)
            l = {'Function generator 33220A (SCPI)', 'LAN-XI module (REST)', 'LAN-XI recorder state Idle', ...
                'Open recorder', 'TEDS transducer detection', 'Channel setup → streaming', ...
                'Microphone sensitivities', 'Settling (CCLD + high-pass)', 'Signal check (no excitation)'};
        end

        function sectionBar(~, parent, row, txt, hint)
            % section title of the control panel: dark bar, white bold text
            P = tim.gui.palette();
            g = uigridlayout(parent, [1 2], 'ColumnWidth', {'1x', 'fit'}, 'RowHeight', {'1x'}, ...
                'Padding', [10 0 10 0], 'BackgroundColor', P.ui.bar);
            g.Layout.Row = row; g.Layout.Column = 1;
            uilabel(g, 'Text', txt, 'FontWeight', 'bold', 'FontSize', 12, 'FontColor', P.ui.barText);
            if nargin < 5, hint = ''; end
            uilabel(g, 'Text', hint, 'FontSize', 11, 'FontColor', [0.80 0.85 0.90], 'HorizontalAlignment', 'right');
        end
        function rg = rowGrid(~, parent, row, widths)
            % one row of the control panel: nested 1 x n grid; components created
            % in it fill the cells from left to right
            P = tim.gui.palette();
            rg = uigridlayout(parent, [1 numel(widths)], 'ColumnWidth', widths, 'RowHeight', {'1x'}, ...
                'Padding', [0 0 0 0], 'ColumnSpacing', 6, 'BackgroundColor', P.ui.panel);
            rg.Layout.Row = row; rg.Layout.Column = 1;
        end
        function l = label(~, parent, txt, tip, align)
            % field label of the control panel
            if nargin < 4, tip = ''; end
            if nargin < 5, align = 'left'; end
            l = uilabel(parent, 'Text', txt, 'Tooltip', tip, 'HorizontalAlignment', align, ...
                'FontColor', tim.gui.palette().ui.text);
        end

        %% ----------------------------------------------------------- state
        function refreshFromCfg(app)
            c = app.Cfg; h = app.H;
            h.mode.Value = c.mode;
            if any(strcmp(c.excitation.mode, h.exMode.ItemsData))
                h.exMode.Value = c.excitation.mode;
            else
                h.exMode.Value = 'sweep';     % 'noise' is script-only
            end
            % tube geometry [mm] and air
            gm = c.geometry;
            h.tubeD.Value = app.toMm(gm.diameter);
            % coordinates in the config -> distances s1, L1, d, L2, s2 in the GUI, on a
            % 1 nm grid (1e3*(-0.041 - (-0.07)) alone would be 29.000000000000004)
            x = gm.micPositions;
            if all(isfinite(x))
                h.s1.Value = app.toMm(x(2) - x(1)); h.s2.Value = app.toMm(x(4) - x(3));
            else
                h.s1.Value = app.toMm(gm.spacingUp); h.s2.Value = app.toMm(gm.spacingDown);
            end
            h.L1.Value = app.mm2txt(gm.xFront - x(2));
            h.dTh.Value = app.mm2txt(gm.xRear - gm.xFront);
            h.L2.Value = app.mm2txt(x(3) - gm.xRear);
            h.temp.Value = c.environment.temperature_C; h.pres.Value = c.environment.pressure_Pa / 1e3;
            ls = struct('impedance_ohm', 8, 'maxPower_W', 1);
            if isfield(c, 'loudspeaker'), ls = c.loudspeaker; end
            h.spkZ.Value = ls.impedance_ohm; h.spkP.Value = ls.maxPower_W;
            % frequency fields: up to 0.45 fs (validateConfig); amplitude up to the safety limit
            fMax = 0.45 * c.acquisition.sampleRate;
            h.fStart.Limits = [1 fMax]; h.fStop.Limits = [1 fMax];
            lim = c.generator.maxVpp / 2;
            h.amp.Limits = [min(0.005, lim / 2), lim];
            app.excitationToUi(h.exMode.Value);
            h.amp.Value = min(max(c.excitation.sweep.amplitudeVpp / 2, h.amp.Limits(1)), lim);
            h.amp.Tooltip = sprintf(['Generator amplitude [Vpk], %s; amplitude limit %.3g Vpk ' ...
                '(configuration generator.maxVpp = %.3g Vpp)'], loadText(c), lim, c.generator.maxVpp);
            items = c.amplifier.knownModels; if ischar(items), items = {items}; end
            if ~any(strcmp(items, 'none (direct drive)')), items = [{'none (direct drive)'}, items(:).']; end
            if ~isempty(c.amplifier.model) && ~any(strcmp(items, c.amplifier.model)), items{end+1} = c.amplifier.model; end
            h.ampModel.Items = items;
            if isempty(c.amplifier.model), h.ampModel.Value = items{1}; else, h.ampModel.Value = c.amplifier.model; end
            gf = c.amplifier.gainFactor; if ~(gf > 0), gf = 0; end      % 0 = gain not entered
            h.ampGain.Value = gf;
            app.GainEntered = gf > 0 || startsWith(lower(h.ampModel.Value), 'none');   % the configuration states the gain
            app.onAmpModel(false);
            app.onTubeChanged();
            if isempty(app.Session), app.refreshCards(); end
            app.buildCalSteps();
            app.refreshCalLabel();
        end

        function excitationToUi(app, mode)
            % frequency range / sweep time or number of steps / repetitions of the
            % selected excitation mode -> fields (stepped: "Steps" instead of "Sweep time")
            h = app.H; ex = app.Cfg.excitation;
            if strcmp(mode, 'stepped'), s = ex.stepped; else, s = ex.sweep; end
            clampF = @(v) min(max(v, h.fStart.Limits(1)), h.fStart.Limits(2));
            h.fStart.Value = clampF(s.fStart); h.fStop.Value = clampF(s.fStop);
            h.reps.Value = min(max(s.repetitions, 1), 100);
            if strcmp(mode, 'stepped')
                h.durLabel.Text = 'Number of steps';
                h.dur.Limits = [1 400]; h.dur.RoundFractionalValues = 'on'; h.dur.Value = min(max(s.nPoints, 1), 400);
                h.dur.Tooltip = sprintf(['number of frequency steps (%s spacing); each step: %g s settling + %g s ' ...
                    'recording'], s.spacing, s.settleTime, s.recordTime);
            else
                h.durLabel.Text = 'Sweep duration [s]';
                h.dur.RoundFractionalValues = 'off'; h.dur.Limits = [0.001 500]; h.dur.Value = min(max(s.duration, 0.001), 500);
                h.dur.Tooltip = 'duration of one sweep [s]';
            end
            app.updateDrive();
        end

        function uiToExcitation(app, mode)
            % fields -> app.Cfg.excitation.(mode); errors on invalid input
            h = app.H;
            fr = [h.fStart.Value h.fStop.Value];
            if fr(2) <= fr(1)
                error('tim:gui:input', 'EXCITATION: the stop frequency (%g Hz) must be higher than the start frequency (%g Hz).', fr(2), fr(1));
            end
            if strcmp(mode, 'stepped')
                s = app.Cfg.excitation.stepped;
                s.nPoints = round(h.dur.Value);
            else
                s = app.Cfg.excitation.sweep;
                s.duration = h.dur.Value;
            end
            s.fStart = fr(1); s.fStop = fr(2); s.repetitions = h.reps.Value;
            app.Cfg.excitation.(mode) = s;
        end

        function onExMode(app, previous)
            % keep what was typed for the previous signal, then show the new signal's values
            try
                app.uiToExcitation(previous);
            catch err
                app.log('Settings of the %s not kept: %s', app.signalName(previous), err.message);
            end
            app.excitationToUi(app.H.exMode.Value);
        end

        function n = signalName(~, mode)
            switch mode
                case 'stepped', n = 'stepped sine';
                case 'noise', n = 'random noise';
                case 'background', n = 'background noise';
                otherwise, n = 'swept sine';
            end
        end

        function v = toMm(~, x)
            % metres -> millimetres on a 1 nm (1e-6 mm) grid: removes the binary
            % residue of coordinate differences (29.000000000000004 -> 29)
            v = round(x * 1e9) / 1e6;
        end

        function v = mm2txt(app, x)
            if isfinite(x), v = sprintf('%.12g', app.toMm(x)); else, v = ''; end
        end

        function v = txt2m(~, s, name)
            % text field in mm -> metres; empty -> NaN; invalid -> message (char)
            s = strtrim(s);
            if isempty(s), v = NaN; return; end
            v = str2double(s);
            if isnan(v), v = sprintf('%s: "%s" is not a number', name, s); else, v = v / 1e3; end
        end

        function [geom, env, msgs] = readTube(app)
            % geometry (m) and environment from the IMPEDANCE TUBE fields.
            % Distances s1, L1, d, L2, s2 -> coordinates with x = 0 at the
            % specimen FRONT face (x increasing towards the termination):
            %   x_front = 0, x_rear = d, x_M2 = -L1, x_M1 = -L1 - s1,
            %   x_M3 = d + L2, x_M4 = d + L2 + s2.
            % Empty L1 / d / L2 = not measured -> positions unknown (NaN).
            h = app.H; msgs = {};
            env = app.Cfg.environment;
            env.temperature_C = h.temp.Value; env.pressure_Pa = 1e3 * h.pres.Value;
            geom = app.Cfg.geometry;
            geom.diameter = h.tubeD.Value / 1e3;
            s1 = h.s1.Value / 1e3; s2 = h.s2.Value / 1e3;
            L1 = app.txt2m(h.L1.Value, 'L1'); d = app.txt2m(h.dTh.Value, 'd'); L2 = app.txt2m(h.L2.Value, 'L2');
            for v = {L1, d, L2}
                if ischar(v{1}), msgs{end+1} = v{1}; end %#ok<AGROW>
            end
            if ~isempty(msgs), return; end
            if any([L1 d L2] < 0), msgs{end+1} = 'L1, d and L2 must not be negative'; end
            geom.spacingUp = s1; geom.spacingDown = s2;
            if all(isfinite([L1 d L2]))
                geom.xFront = 0; geom.xRear = d;
                geom.micPositions = [-L1 - s1, -L1, d + L2, d + L2 + s2];
            else
                geom.xFront = NaN; geom.xRear = NaN; geom.micPositions = nan(1, 4);
            end
            geom = tim.app.roundGeometry(geom);   % d + L2 = 0.075 + 0.041 -> 0.116, not 0.11599999999999999
        end

        function onTubeChanged(app)
            % live check of the tube entries: limits, consistency, drawing, geometry table
            app.CalDirty = true;                 % calibration model follows the geometry
            [geom, env, msgs] = app.readTube();
            P = tim.gui.palette(); dot = [' ' char(183) ' '];
            try
                air = tim.acoustics.airProperties(env);
                lim = tim.acoustics.frequencyLimits(geom.diameter, [geom.spacingUp geom.spacingDown], air);
                known = all(isfinite(geom.micPositions)) && isfinite(geom.xFront) && isfinite(geom.xRear);
                a = app.Cfg.analysis;
                txt = sprintf('c = %.1f m/s%sgeometry %.0f–%.0f Hz%sanalysis band %g–%g Hz', air.c, dot, ...
                    lim.fLower, lim.fUpper, dot, a.fMin, a.fMax);
                if ~known
                    txt = [txt '. L1, d, L2 not entered: specimen results (R, τ, Z_t, TL) disabled.'];
                end
                if ~isempty(msgs), txt = [txt '  CHECK: ' strjoin(msgs, '; ')]; end
                app.H.fLimits.Text = txt;
                if isempty(msgs), app.H.fLimits.FontColor = P.ui.muted; else, app.H.fLimits.FontColor = P.fail; end
                if known
                    app.Pages.tube.setNote('');
                else
                    app.Pages.tube.setNote(['Schematic: L1, d and L2 are not entered, so the specimen results ' ...
                        '(R, τ, Z_t, TL) are disabled.'], 'warn');
                end
                app.H.tubeInfo.Text = '';
                app.Pages.tube.setSummary(app.geometrySummary(geom, air, lim, known));
                tim.gui.drawTube3D(app.H.axTube3D, geom, app.drawingDims(), app.homeMapping(), ...
                    struct('section', app.H.secChk.Value, 'dimensions', app.H.dimChk.Value));
            catch err
                app.H.fLimits.Text = ['CHECK: ' err.message]; app.H.fLimits.FontColor = P.fail;
            end
            app.refreshCalLabel();
        end

        function s = geometrySummary(app, g, air, lim, known)
            % table of the Tube setup view
            mm = @(x) app.fmt(1e3 * x, '%.6g');
            x = g.micPositions;
            rows = {'Tube inner diameter', [mm(g.diameter) ' mm']; ...
                's1 (M1–M2)', [mm(g.spacingUp) ' mm']; 's2 (M3–M4)', [mm(g.spacingDown) ' mm']};
            if known
                rows = [rows; {'L1 (M2–front face)', [mm(g.xFront - x(2)) ' mm']; ...
                    'd (specimen thickness)', [mm(g.xRear - g.xFront) ' mm']; ...
                    'L2 (rear face–M3)', [mm(x(3) - g.xRear) ' mm']}];
                for k = 1:4, rows(end + 1, :) = {sprintf('x(M%d)', k), [mm(x(k)) ' mm']}; end %#ok<AGROW>
            else
                rows = [rows; {'L1, d, L2', 'not entered'}];
            end
            rows = [rows; {'Speed of sound', sprintf('%.1f m/s', air.c); ...
                'Geometric range', sprintf('%.0f–%.0f Hz', lim.fLower, lim.fUpper); ...
                '(1,1) mode cut-on', sprintf('%.0f Hz', lim.cutOn11); ...
                'Analysis band', sprintf('%g–%g Hz', app.Cfg.analysis.fMin, app.Cfg.analysis.fMax)}];
            s = struct('title', 'Geometry', 'columns', {{'Quantity', 'Value'}}, 'data', {rows}, ...
                'note', 'x = 0 at the specimen front face, x increasing towards the termination.');
        end

        function t = fmt(~, v, f)
            if isfinite(v), t = sprintf(f, v); else, t = '–'; end
        end

        function tubeView(app, name)
            tim.gui.drawTube3D(app.H.axTube3D, 'view', name);
        end

        function td = drawingDims(app)
            % tube dimensions used only for the drawings (cfg.tubeDrawing)
            td = tim.app.defaultConfig().tubeDrawing;
            if isfield(app.Cfg, 'tubeDrawing')
                for f = fieldnames(app.Cfg.tubeDrawing).'
                    td.(f{1}) = app.Cfg.tubeDrawing.(f{1});
                end
            end
        end

        function updateDrive(app)
            % live estimate of the loudspeaker drive from amplitude x gain, and the
            % expected duration of one measurement
            P = tim.gui.palette();
            c = app.Cfg;
            c.amplifier.model = app.H.ampModel.Value;
            c.amplifier.gainFactor = app.gainValue();
            c.loudspeaker.impedance_ohm = app.H.spkZ.Value; c.loudspeaker.maxPower_W = app.H.spkP.Value;
            d = tim.app.driveEstimate(c, 2 * app.H.amp.Value);
            lim = c.generator.maxVpp / 2;
            if isnan(d.P_W)
                txt = sprintf('Generator %.3g Vpk (limit %.3g Vpk). Amplifier gain not entered: no drive estimate.', ...
                    app.H.amp.Value, lim);
                col = P.fail;
            else
                txt = sprintf('Estimated loudspeaker drive: %.3g Vpk, %s peak, %s (limit %s). Generator limit %.3g Vpk.', ...
                    d.Vspk_pk, app.siText(d.Ipk, 'A'), app.siText(d.P_W, 'W'), app.siText(d.limit_W, 'W'), lim);
                col = P.ui.muted;
                if d.P_W > d.limit_W || app.H.amp.Value > lim, col = P.fail; txt = [txt ' Above the limit.']; end
                if ~app.GainEntered, col = P.fail; txt = [txt ' Enter the gain set on the amplifier.']; end
            end
            if isfield(c, 'loudspeaker') && isfield(c.loudspeaker, 'ratedPower_W') && app.H.spkP.Value > c.loudspeaker.ratedPower_W
                txt = sprintf('%s The power limit is above the rated power of the loudspeaker (%g W).', txt, c.loudspeaker.ratedPower_W);
                col = P.fail;
            end
            app.H.drive.Text = txt; app.H.drive.FontColor = col;
            app.H.durEst.Text = sprintf('about %s', app.durationText(app.expectedDuration()));
        end

        function t = siText(~, v, unit)
            % value with an SI prefix so that it lies between 0.1 and 999 ('12.3 mW', '1 W')
            if ~isfinite(v), t = ['– ' unit]; return; end
            p = {'µ', 1e-6; 'm', 1e-3; '', 1};
            for i = 1:size(p, 1)
                if abs(v) < 999.5 * p{i, 2} || i == size(p, 1)
                    t = sprintf('%.3g %s%s', v / p{i, 2}, p{i, 1}, unit); return
                end
            end
        end

        function T = expectedDuration(app)
            % seconds of one measurement with the values in the fields (MeasurementSession timing)
            h = app.H; ex = app.Cfg.excitation; n = h.reps.Value;
            if strcmp(h.exMode.Value, 'stepped')
                st = ex.stepped;
                T = n * (0.5 + h.dur.Value * (st.settleTime + st.recordTime) + 0.5);
            else
                sw = ex.sweep;
                T = n * (sw.preRoll + h.dur.Value + sw.postRoll + 0.2);
            end
        end

        function t = durationText(~, T)
            if T < 90, t = sprintf('%.0f s', T); else, t = sprintf('%.1f min', T / 60); end
        end

        function readCfgFromUi(app)
            % control-panel fields -> app.Cfg (validated); warnings are logged once.
            % app.Cfg changes only when the whole set of fields is valid.
            old = app.Cfg;
            try
                app.readFields();
            catch err
                app.Cfg = old;
                rethrow(err);
            end
        end

        function readFields(app)
            h = app.H;
            if isempty(app.Session), app.Cfg.mode = h.mode.Value; end   % fixed while connected
            app.Cfg.excitation.mode = h.exMode.Value;
            % f start/stop, sweep time or number of steps, repetitions of the selected signal
            app.uiToExcitation(h.exMode.Value);
            app.Cfg.excitation.sweep.amplitudeVpp = 2 * h.amp.Value;      % GUI in Vpk, config/generator in Vpp
            app.Cfg.excitation.stepped.amplitudeVpp = 2 * h.amp.Value;
            app.Cfg.excitation.noise.amplitudeVpp = 2 * h.amp.Value;
            app.Cfg.amplifier.model = h.ampModel.Value;
            app.Cfg.amplifier.gainFactor = app.gainValue();          % NaN = not entered
            app.Cfg.amplifier.gain_dB = 20 * log10(app.gainValue());
            app.Cfg.amplifier.gainSetting = '';
            app.Cfg.amplifier.knownModels = h.ampModel.Items;
            app.Cfg.loudspeaker.impedance_ohm = h.spkZ.Value;
            app.Cfg.loudspeaker.maxPower_W = h.spkP.Value;
            [geom, env, msgs] = app.readTube();
            if ~isempty(msgs)
                error('tim:gui:geometry', 'IMPEDANCE TUBE: %s.', strjoin(msgs, '; '));
            end
            app.Cfg.geometry = geom; app.Cfg.environment = env;
            rep = tim.app.validateConfig(app.Cfg);
            txt = strjoin(rep, ' | ');
            if ~strcmp(txt, app.LastCheck)
                for i = 1:numel(rep), app.log('CHECK: %s', rep{i}); end
                app.LastCheck = txt;
            end
        end

        function setStatus(app, txt, state)
            % status line of the control panel: 'ok' | 'busy' | 'warn' | 'idle'
            P = tim.gui.palette();
            switch state
                case 'ok', col = P.ok;
                case 'busy', col = P.run;
                case 'warn', col = 0.8 * P.warn;
                otherwise, col = P.ui.muted;
            end
            app.H.status.Text = txt; app.H.status.FontColor = col;
        end

        function log(app, varargin)
            line = sprintf(varargin{:});
            app.appendLog(sprintf('[%s] %s', char(datetime('now'), 'HH:mm:ss'), line));
        end
        function appendLog(app, line)
            if ~isvalid(app.H.log), fprintf('%s\n', line); return; end   % window closed
            v = app.H.log.Value;
            if ischar(v), v = {v}; end
            if isscalar(v) && isempty(v{1}), v = {}; end
            v{end+1} = line;
            if numel(v) > 1000, v = v(end-999:end); end
            app.H.log.Value = v;
            scroll(app.H.log, 'bottom');
            drawnow limitrate
        end

        function run(app, fn, busyWhat)
            % run an action with error reporting; never leaves the output on.
            % busyWhat: lock the GUI while the action runs - every input and
            % button is disabled except Stop, which then names the action.
            if nargin < 3, busyWhat = ''; end
            if app.Busy || app.Closing
                return      % an action is already running / the window closes (no re-entrance)
            end
            app.PendingStop = false;
            if ~isempty(busyWhat)
                % the stop flag is cleared ONCE here, before the first drawnow: a
                % STOP / window close arriving between this click and the first
                % measurement is not lost (requirePrepared keeps it while in an operation)
                op = app.Session;
                if ~isempty(op), op.beginOperation(); end
                opEnd = onCleanup(@() endOp(op));
                app.setBusy(true, busyWhat);
                unlock = onCleanup(@() safeUnlock(app));
            end
            try
                fn();
            catch err
                if ~isvalid(app), return; end     % closed meanwhile (second close request)
                hasGen = ~isempty(app.Session) && ~isempty(app.Session.Gen);
                if hasGen
                    try, app.Session.Gen.outputOff(); catch, end
                end
                what = busyWhat; if isempty(what), what = 'action'; end
                if strcmp(err.identifier, 'tim:session:notConfirmed')
                    app.log('%s cancelled by the operator: %s', app.capital(what), err.message);
                    msg = sprintf('%s cancelled: the loudspeaker was not driven. %s', app.capital(what), app.outputOffText());
                    icon = 'info'; ttl = sprintf('%s cancelled', app.capital(what));
                elseif any(strcmp(err.identifier, {'tim:session:stopped', 'tim:gui:abort'}))
                    app.log('%s stopped by the operator: %s', app.capital(what), err.message);
                    msg = sprintf('%s stopped by the operator. %s', app.capital(what), app.outputOffText());
                    icon = 'info'; ttl = sprintf('%s stopped', app.capital(what));
                elseif startsWith(err.identifier, {'tim:gui:input', 'tim:gui:geometry', 'tim:config:'})
                    app.log('Warning: %s', err.message);
                    msg = err.message; icon = 'warning'; ttl = 'Check the settings';
                else
                    app.log('Error (%s): %s', what, err.message);
                    msg = err.message; icon = 'error'; ttl = 'Error';
                    if hasGen
                        off = app.outputOffText(); app.log('%s', off);
                        msg = sprintf('%s\n\n%s', msg, off);
                    end
                end
                if isvalid(app.Fig) && ~app.CloseAfterBusy     % window may be closing
                    app.alert(msg, ttl, icon);
                end
                % a stopped / failed acquisition left partial live data: show the last result again
                if any(strcmp(busyWhat, {'measurement', 'background recording', 'calibration'}))
                    try, app.refreshViews(); catch, end
                end
            end
            if isvalid(app) && app.CloseAfterBusy          % close requested while busy
                clear unlock opEnd
                if ~isvalid(app), return; end
                if ~app.Saved && app.ConfirmUnsaved && strcmp(app.Fig.Visible, 'on')
                    % the action has stopped; an earlier unsaved measurement is not lost silently
                    if ~isempty(app.ClosingWin) && isvalid(app.ClosingWin), close(app.ClosingWin); end
                    if ~app.confirmDiscard('Close the program')
                        app.CloseAfterBusy = false;
                        app.log('Closing cancelled: the unsaved measurement is kept.');
                        return
                    end
                end
                if isvalid(app), app.closeNow(); end
            end
        end

        function s = capital(~, s)
            if ~isempty(s), s(1) = upper(s(1)); end
        end

        function txt = outputOffText(app)
            % read back OUTP? (1 s time-out): never claim "OFF" without confirmation
            txt = 'Generator output off (confirmed).';
            s = app.Session;
            if isempty(s) || isempty(s.Gen)
                txt = 'Generator not connected.'; app.OutputUnconfirmed = false; return
            end
            try
                if str2double(s.Gen.Transport.query('OUTP?', 1)) ~= 0
                    txt = 'The generator output could not be switched off. Switch it off at the generator.';
                end
            catch
                txt = 'The generator output could not be confirmed off. Check the output at the generator.';
            end
            app.OutputUnconfirmed = ~startsWith(txt, 'Generator output off');
        end

        function setBusy(app, tf, what)
            % Lock / unlock the control panel and the menus (the tabs stay usable).
            if isempty(app.Fig) || ~isvalid(app.Fig)
                app.Busy = false; return            % window closed during the action
            end
            h = app.H; P = tim.gui.palette();
            ctl = [app.inputControls(), {h.connect, h.disconnect, h.start, h.background, h.loadCal, h.runCal, ...
                h.save, h.reprocess, h.mLoadCfg, h.mSaveCfg}, num2cell(h.mHelp)];
            if tf
                app.Busy = true;
                for i = 1:numel(ctl), ctl{i}.Enable = 'off'; end
                % Stop only for actions it can stop (saving / loading cannot be interrupted)
                stoppable = any(strcmp(what, {'measurement', 'calibration', 'connection', 'background recording'}));
                h.stop.Text = 'Stop';
                h.stop.Enable = matlab.lang.OnOffSwitchState(stoppable);
                if stoppable
                    h.stop.Tooltip = sprintf('Stop the %s. The generator output is switched off at once.', what);
                end
                driven = any(strcmp(what, {'measurement', 'calibration'}));
                if driven && ~isempty(app.Session) && strcmp(app.Session.Cfg.mode, 'hardware')
                    h.lamp(1).Color = P.warn; h.lamp(1).Tooltip = 'Generator output enabled: the loudspeaker can be driven.';
                    app.setStatus(sprintf('%s – loudspeaker driven', app.capital(what)), 'busy');
                    h.status.Tooltip = 'Stop switches the generator output off at once.';
                else
                    app.setStatus(sprintf('Busy: %s', what), 'busy');
                    h.status.Tooltip = '';
                end
            else
                h.stop.Text = 'Stop';
                h.stop.Tooltip = 'Stop the running action. The generator output is switched off at once.';
                app.Busy = false;
                for i = 1:numel(ctl), ctl{i}.Enable = 'on'; end
                h.lamp(1).Tooltip = 'Generator (Keysight 33220A) – details in Setup > Connection';
                if app.OutputUnconfirmed
                    % the read-back after an error did not confirm the output off
                    h.lamp(1).Color = P.fail; h.lamp(1).Tooltip = 'Generator output NOT confirmed off – check the generator.';
                elseif ~isempty(app.Session) && ~isempty(app.Session.Gen) && isequal(h.lamp(1).Color, P.warn)
                    h.lamp(1).Color = P.ok;
                end
                app.updateEnable();
                app.readyStatus();
            end
            drawnow;
        end

        function readyStatus(app)
            % status line when no action runs: keeps the verdict of the connection
            % checks (failed / warnings) and an unconfirmed generator output
            s = app.Session; app.H.status.Tooltip = '';
            if app.OutputUnconfirmed
                app.setStatus('Generator output not confirmed off', 'warn');
                app.H.status.Tooltip = 'Check the output of the generator at the instrument.';
            elseif ~isempty(s) && s.Prepared
                st = app.ConnList.States;
                if any(strcmp(st, 'fail'))
                    app.setStatus(sprintf('Connected (%s) – a check failed', s.Cfg.mode), 'warn');
                elseif any(strcmp(st, 'warn'))
                    app.setStatus(sprintf('Ready (%s) – with warnings', s.Cfg.mode), 'warn');
                else
                    app.setStatus(sprintf('Ready (%s)', s.Cfg.mode), 'ok');
                end
            elseif ~isempty(s)
                app.setStatus('Not ready – connection incomplete', 'warn');
            else
                app.setStatus('Not connected', 'idle');
            end
        end

        function c = inputControls(app)
            % every field / selector of the control panel and the drawing options
            h = app.H;
            c = {h.mode, h.exMode, h.fStart, h.fStop, h.dur, h.amp, h.reps, h.ampModel, h.ampGain, h.spkZ, h.spkP, ...
                h.tubeD, h.s1, h.L1, h.dTh, h.L2, h.s2, h.temp, h.pres, h.specimen, ...
                h.secChk, h.dimChk};   % 3D redraw (~1 s) would stall the data stream
        end

        function updateEnable(app)
            % action buttons follow the state: connected, prepared, measurement present
            if app.Busy || isempty(app.Fig) || ~isvalid(app.Fig), return; end
            h = app.H; s = app.Session;
            connected = ~isempty(s); ready = connected && s.Prepared;
            onoff = @(tf) matlab.lang.OnOffSwitchState(tf);
            h.mode.Enable = onoff(~connected);         % the mode belongs to the connection
            h.connect.Enable = onoff(~connected);
            h.disconnect.Enable = onoff(connected);
            h.start.Enable = onoff(ready);
            h.background.Enable = onoff(ready);
            h.runCal.Enable = onoff(ready);
            h.stop.Enable = 'off';
            h.save.Enable = onoff(~isempty(app.LastMeas));
            h.reprocess.Enable = onoff(~isempty(app.LastMeas) && ~strcmp(app.LastMeas.kind, 'background'));
            h.ampGain.Enable = onoff(~startsWith(lower(h.ampModel.Value), 'none'));
            if connected
                h.mode.Tooltip = sprintf('connected in %s mode - Disconnect to change the mode', s.Cfg.mode);
            else
                h.mode.Tooltip = 'simulation: virtual tube (practice, tests); hardware: the real instruments. Fixed while connected.';
            end
        end

        function liveUpdate(app)
            % Called for every received data block: live time signals of the last
            % 0.5 s (about 5 refreshes per second) and processing of STOP.
            persistent lastT
            if isempty(lastT), lastT = tic; end
            if toc(lastT) < 0.2, drawnow('limitrate'); return; end
            lastT = tic;
            try
                daq = app.Session.Daq;
                p = daq.Parser;
                if isempty(p) || p.samplesAvailable() == 0, drawnow('limitrate'); return; end
                fs = daq.SampleRate; n = round(0.5 * fs);
                x = p.tail(n, 1:4);
                x = x - mean(x, 1, 'omitnan');                          % volts, slow drift removed
                t = ((1:n) - n) / fs;                                   % seconds before "now"
                total = p.samplesAvailable() / fs;
                [y, unit, sens] = app.toPressure(x, app.Session.Mics);
                P = tim.gui.palette(); lv = cell(1, 4);
                for c = 1:4
                    ax = app.H.axW(c);
                    if numel(app.WaveLines) < c || ~isgraphics(app.WaveLines(c))
                        cla(ax); app.WaveLines(c) = line(ax, NaN, NaN, 'Color', P.ch(c, :), 'LineWidth', 0.8, ...
                            'Tag', sprintf('timWave%d', c));
                    end
                    tim.plots.emptyState(ax, '');
                    set(app.WaveLines(c), 'XData', t, 'YData', y(:, c));
                    ylabel(ax, sprintf('ch%d (M%d) [%s]', c, app.portOf(c), unit));
                    pk = max(abs(y(:, c))); if ~(pk > 0), pk = 1; end
                    tim.plots.fitAxes(ax, 'XRange', [t(1) 0], 'YRange', [-pk pk]);
                    lv{c} = sprintf('ch%d %.1f dB', c, 20 * log10(sqrt(mean(x(:, c).^2, 'omitnan')) / sens(c) / 2e-5));
                end
                title(app.H.axW(1), sprintf('LIVE  %s  %.1f s recorded (%s)', char(183), total, app.Session.Status));
                xlabel(app.H.axW(4), 'Time relative to now [s]');
                app.Pages.wave.setNote(sprintf('Live level (last 0.5 s, dB SPL): %s', strjoin(lv, '   ')));
                app.LiveCount = app.LiveCount + 1;
            catch
            end
            drawnow('limitrate');
        end

        function prepareLive(app)
            % time-signal view in its live state: labels and units of the
            % connected microphones; liveUpdate then only sets the line data
            o = app.plotOpts(); o.mics = app.Session.Mics;
            o.emptyText = 'Waiting for data ...';
            info = tim.plots.timeSignals(app.H.axW, [], o);
            if isfield(info, 'lines'), app.WaveLines = info.lines; else, app.WaveLines = gobjects(0); end
            app.Pages.wave.setNote('');
        end

        function p = portOf(app, c)
            % port M1..M4 of DAQ channel c
            m = app.Cfg.mics; i = find([m.channel] == c, 1);
            if isempty(i), p = c; else, p = m(i).position; end
        end

        %% ----------------------------------------------------------- callbacks
        function ok = confirmDiscard(app, action)
            % an unsaved measurement must not be replaced or lost silently
            ok = true;
            if app.Saved || ~app.ConfirmUnsaved || isempty(app.LastMeas), return; end
            if ~strcmp(app.Fig.Visible, 'on'), return; end      % hidden window: scripts, tests
            sel = app.ask(sprintf(['The last measurement (%s, %s) has not been saved.\n\n' ...
                '%s anyway? The measurement is then lost.'], app.signalName(app.LastMeas.kind), ...
                app.LastMeas.timestamp, action), 'Unsaved measurement', ...
                {sprintf('%s', action), 'Cancel'}, 2, 2, 'warning');
            ok = strcmp(sel, action);
        end

        function onSaveConfig(app)
            app.run(@() app.doSaveConfig(), 'saving the configuration');
        end
        function doSaveConfig(app)
            app.readCfgFromUi();
            start = fullfile(tim.app.projectRoot(), 'config', 'user_config.json');
            if isfield(app.Cfg, 'configFile') && ~isempty(app.Cfg.configFile), start = app.Cfg.configFile; end
            [f, p] = uiputfile('*.json', 'Save configuration', start);
            figure(app.Fig);
            if isequal(f, 0), return; end
            c = app.Cfg; c = rmfield(c, intersect(fieldnames(c), {'configFile'}));
            tim.app.saveConfig(c, fullfile(p, f));
            app.Cfg.configFile = fullfile(p, f);
            app.log('Configuration saved to %s', fullfile(p, f));
        end

        function onLoadConfig(app)
            if ~app.confirmDiscard('Load a configuration'), return; end
            if ~isempty(app.Session)
                sel = app.ask(['Loading a configuration disconnects the instruments (mode, microphones and ' ...
                    'calibration settings belong to the connection). Continue?'], 'Load configuration', ...
                    {'Disconnect and load', 'Cancel'}, 2, 2, 'question');
                if ~strcmp(sel, 'Disconnect and load'), return; end
            end
            [f, p] = uigetfile('*.json', 'Configuration', fullfile(tim.app.projectRoot(), 'config'));
            figure(app.Fig);
            if isequal(f, 0), return; end
            app.run(@() app.doLoadConfig(fullfile(p, f)), 'loading the configuration');
        end
        function doLoadConfig(app, file)
            cfg = tim.app.loadConfig(file);
            if ~isempty(app.Session)
                % the connected session keeps its own configuration (mode, mics,
                % calibration settings): a new configuration needs a new connection
                app.disconnect(true);
                app.log('Disconnected: a new configuration was loaded - press Connect again.');
            end
            app.Cfg = cfg; app.LastCheck = '';
            app.LastMeas = []; app.LastRes = []; app.Saved = true;
            app.refreshFromCfg();
            app.refreshViews();
            app.setResultStatus();
            app.log('Loaded configuration %s', file);
        end

        function onConnect(app)
            app.run(@() app.doConnect(), 'connection');   % locked: no second Connect / START meanwhile
        end
        function onDisconnect(app)
            if isempty(app.Session), return; end
            app.disconnect();
            app.log('Instruments disconnected by the operator (generator output OFF, LAN-XI Idle).');
        end
        function doConnect(app)
            app.Cfg.mode = app.H.mode.Value;
            app.readCfgFromUi();                       % invalid fields: 'Check the settings', no connection
            app.disconnect(true);
            app.setStatus(sprintf('Connecting (%s)…', app.Cfg.mode), 'busy');
            % connection checklist: every step is shown while it runs (the
            % animated icon keeps turning during the slow LAN-XI setup)
            app.ConnList.reset();
            app.showTab(app.H.connTab);
            app.H.connHead.Text = sprintf('Connecting (%s mode)…', app.Cfg.mode);
            app.H.connHead.FontColor = [0.1 0.1 0.1];
            app.refreshCards();
            s = tim.app.MeasurementSession(app.Cfg);
            s.StatusCallback = @(line) app.appendLog(line);
            s.BlockCallback = @() app.liveUpdate();       % live time signals + keeps STOP responsive
            s.ProgressCallback = @(key, state, detail) app.onProgress(key, state, detail);
            L = app.Cfg.ui.language; yes = tim.app.msg(L, 'yesPlay');
            if strcmp(app.Cfg.mode, 'hardware')       % no real loudspeaker in simulation
                s.ExcitationConfirm = @(msg) strcmp(app.ask(msg, tim.app.msg(L, 'confirmTitle'), ...
                    {yes, tim.app.msg(L, 'cancel')}, 2, 2, 'warning'), yes);
            end
            app.Session = s;
            s.beginOperation();                        % Stop during the connection stays pending
            opEnd = onCleanup(@() endOp(s));
            if app.PendingStop, s.requestStop(); end    % Stop pressed before the session existed
            try
                s.connect();
                s.prepareAcquisition();
                chk = s.signalCheck(1);                % 1 s without excitation: level / fault flags per channel
            catch err
                % failed or stopped: no half-open session (Connect and the mode selector stay usable)
                try, s.close(true); catch, end
                app.Session = [];
                rethrow(err);
            end
            clear opEnd
            m = s.Mics;
            rows = cell(numel(m), 8);
            for i = 1:numel(m)
                k = chk([chk.channel] == m(i).channel);
                ts = '–'; if isfinite(m(i).tedsSerial), ts = sprintf('%d', m(i).tedsSerial); end
                if strcmp(k.state, 'fail'), sc = ['FAULT: ' k.text]; elseif strcmp(k.state, 'warn'), sc = ['check: ' k.text]; else, sc = 'OK'; end
                rows(i, :) = {sprintf('ch%d', m(i).channel), sprintf('M%d', m(i).position), m(i).model, ...
                    sprintf('%.2f', 1e3 * m(i).sensitivity_VperPa), m(i).sensitivitySource, ts, ...
                    sprintf('%.1f', k.spl_dB), sc};
            end
            app.H.chanTable.Data = rows;
            app.refreshCards(chk);
            P = tim.gui.palette();
            states = app.ConnList.States;
            if any(strcmp(states, 'fail'))
                app.H.connHead.Text = 'Connected, but a check failed – see the red items below.';
                app.H.connHead.FontColor = P.fail;
                app.setStatus(sprintf('Connected (%s) – a check failed', app.Cfg.mode), 'warn');
            elseif any(strcmp(states, 'warn'))
                app.H.connHead.Text = 'Connected with warnings – see the orange items below.';
                app.H.connHead.FontColor = 0.8 * P.warn;
                app.setStatus(sprintf('Ready (%s) – with warnings', app.Cfg.mode), 'warn');
            else
                app.H.connHead.Text = 'Connected - all checks passed.';
                app.H.connHead.FontColor = P.ok;
                app.setStatus(sprintf('Ready (%s)', app.Cfg.mode), 'ok');
            end
            if ~isempty(s.Calibration), app.showCal(s.Calibration); else, app.refreshCalLabel(); end
            app.CalDirty = true;                 % calibration labels pick up the TEDS serials
            app.buildCalSteps();
        end

        function onProgress(app, key, state, detail)
            % a connection step started / ended (MeasurementSession.ProgressCallback)
            app.ConnList.set(key, state, detail);
            col = app.stateColor(state);
            switch key
                case 'gen'
                    app.H.lamp(1).Color = col;
                case {'lanxi', 'idle', 'open', 'setup'}
                    app.H.lamp(2).Color = col;
                case 'teds'
                    if ~strcmp(state, 'run'), app.refreshCards(); end
            end
            if strcmp(state, 'fail')
                i = find(strcmp(app.connKeys(), key), 1); lbl = app.connLabels();
                app.H.connHead.Text = sprintf('Connection FAILED at "%s" - %s', lbl{i}, detail);
                app.H.connHead.FontColor = tim.gui.palette().fail;
                if strcmp(key, 'gen'), app.H.lamp(1).Color = col; else, app.H.lamp(2).Color = col; end
            end
        end

        function col = stateColor(~, state)
            P = tim.gui.palette();
            switch state
                case 'run', col = P.run;
                case 'ok', col = P.ok;
                case 'warn', col = P.warn;
                case 'fail', col = P.fail;
                otherwise, col = P.idle;
            end
        end

        function refreshCards(app, chk)
            % one card per channel: port, TEDS, sensitivity, signal check
            if nargin < 2, chk = []; end
            P = tim.gui.palette();
            mics = app.Cfg.mics; teds = {};
            if ~isempty(app.Session)
                mics = app.Session.Mics;
                if ~isempty(app.Session.Daq), teds = app.Session.Daq.Teds; end
            end
            for c = 1:4
                card = app.H.card(c);
                i = find([mics.channel] == c, 1);
                if isempty(i), continue; end
                m = mics(i);
                card.head.Text = sprintf('ch%d  →  port M%d', c, m.position);
                st = 'idle'; notes = {};
                if numel(teds) >= c && ~isempty(teds{c})
                    card.line1.Text = sprintf('TEDS  %s  s/n %d', teds{c}.typeNumber, teds{c}.serialNumber);
                    st = 'ok';
                elseif ~isempty(app.Session) && ~isempty(app.Session.Daq) && ~isempty(teds)
                    card.line1.Text = 'no TEDS found'; st = 'warn'; notes{end + 1} = 'no TEDS'; %#ok<AGROW>
                else
                    card.line1.Text = '';
                end
                if isfield(m, 'sensitivitySource')
                    card.line2.Text = sprintf('sensitivity %.4g mV/Pa (%s)', 1e3 * m.sensitivity_VperPa, tim.app.MeasurementSession.sourceName(m.sensitivitySource));
                    if ~any(strcmp(m.sensitivitySource, {'certificate', 'teds'}))
                        st = 'warn'; notes{end + 1} = 'nominal sensitivity'; %#ok<AGROW>
                    end
                    if m.serialMismatch
                        st = 'warn'; notes{end + 1} = 'TEDS serial differs from the configuration'; %#ok<AGROW>
                    end
                else
                    card.line2.Text = sprintf('nominal %.4g mV/Pa', 1e3 * m.nominalSensitivity_VperPa);
                end
                if ~isempty(chk)
                    k = chk([chk.channel] == c);
                    if strcmp(k.state, 'fail')
                        st = 'fail'; card.line3.Text = ['signal: ' k.text];
                        card.line3.FontColor = P.fail;
                    else
                        card.line3.Text = sprintf('level %.1f dB SPL (1 s, no excitation)', k.spl_dB);
                        card.line3.FontColor = P.ui.muted;
                    end
                else
                    card.line3.Text = '';
                end
                card.lamp.Color = app.stateColor(st);
                app.H.lamp(2 + c).Color = card.lamp.Color;
                switch st
                    case 'ok', card.state.Text = 'OK';
                    case 'warn', card.state.Text = ['check: ' strjoin(notes, ', ')];
                    case 'fail', card.state.Text = 'FAULT';
                    otherwise, card.state.Text = 'not connected';
                end
                card.state.FontColor = 0.8 * app.stateColor(st);
                card.state.Tooltip = card.state.Text;
            end
            drawnow;
        end

        function onStart(app)
            if isempty(app.Session) || ~app.Session.Prepared
                app.alert('The instruments are not connected. Press Connect first.', 'Not connected', 'info'); return
            end
            if ~app.confirmDiscard('Measure'), return; end
            app.run(@() app.doStart(), 'measurement');
        end
        function doStart(app)
            app.readCfgFromUi();
            app.requireGain();
            app.syncSession();
            app.log('Start: %s measurement of "%s" (started by the operator).', ...
                app.signalName(app.Cfg.excitation.mode), app.specimenName());
            app.showTab(app.H.waveTab);                   % live view
            app.prepareLive();
            m = app.Session.measure(app.Cfg.excitation.mode);
            app.LastMeas = m; app.LastRes = []; app.Saved = false; app.SavedDir = '';
            app.LastMeas.metadata.specimen = app.specimenName();   % name at Start (folder + metadata)
            app.process();
            app.setResultStatus();
            if ~m.integrityOk
                app.alert('Data-integrity problems were detected – see the messages.', 'Data integrity', 'warning');
            end
        end

        function requireGain(app)
            % an amplifier was chosen: its gain must be entered (power check, record)
            if ~startsWith(lower(app.H.ampModel.Value), 'none') && ~app.GainEntered
                error('tim:gui:input', ['EXCITATION: enter the voltage gain set on the amplifier "%s" ' ...
                    '("Amplifier gain", e.g. 10 for 20 dB); it is used for the loudspeaker power check.'], app.H.ampModel.Value);
            end
        end

        function n = specimenName(app)
            n = strtrim(app.H.specimen.Value);
            if isempty(n), n = 'unnamed specimen'; end
        end

        function onStop(app)
            if isempty(app.Session) && app.Busy
                app.PendingStop = true;                % the connection has no session yet
                app.log('Stop requested by the operator.');
                return
            end
            if ~isempty(app.Session)
                app.Session.requestStop();
                try, app.Session.Gen.outputOff(); catch, end
                app.log('Stop requested by the operator: generator output switched off.');
            end
        end

        function onBackground(app)
            if isempty(app.Session) || ~app.Session.Prepared
                app.alert('The instruments are not connected. Press Connect first.', 'Not connected', 'info'); return
            end
            if ~app.confirmDiscard('Record background noise'), return; end
            app.run(@() app.doBackground(), 'background recording');
        end
        function doBackground(app)
            app.showTab(app.H.waveTab);
            app.prepareLive();
            m = app.Session.measureBackground(2);
            app.LastMeas = m; app.LastRes = []; app.Saved = false; app.SavedDir = '';
            app.refreshViews();
            app.setResultStatus();
            integ = m.channelInfo{1}.integrity;
            if integ.ok, it = 'data integrity OK'; else, it = ['data integrity failed: ' strjoin(integ.fatal, ' | ')]; end
            app.log('Background noise: 2 s recorded without excitation; %s. %s', it, strjoin(integ.warnings, ' | '));
            app.showTab(app.H.specTab);
        end

        function onLoadCal(app)
            [f, p] = uigetfile('*.mat', 'Calibration', tim.app.resolvePath(app.Cfg.output.calibrationDir));
            figure(app.Fig);
            if isequal(f, 0), return; end
            app.run(@() app.doLoadCal(fullfile(p, f)), 'loading the calibration');
        end
        function doLoadCal(app, file)
            if ~isempty(app.Session)
                app.Session.loadCalibration(file);            % type check + log
                cal = app.Session.Calibration;
            else
                S = load(file);
                if ~isfield(S, 'cal') || ~isfield(S.cal, 'type') || ~strcmp(S.cal.type, 'tim.complexChannelCalibration')
                    error('tim:cal:file', '"%s" is not a calibration file (CAL-*.mat).', file);
                end
                cal = S.cal;
                app.log('Loaded calibration %s (%s) - used from the next connection on.', cal.version, file);
            end
            app.Cfg.calibration.file = file;
            app.showCal(cal);
        end

        function onRunCal(app)
            if isempty(app.Session) || ~app.Session.Prepared
                app.alert('The instruments are not connected. Press Connect first.', 'Not connected', 'info'); return
            end
            app.run(@() app.doRunCal(), 'calibration');
        end
        function syncSession(app)
            % pass all operator settings of the GUI to the session
            s = app.Session;
            s.setExcitation(app.Cfg.excitation);
            s.setLoudspeaker(app.Cfg.loudspeaker.impedance_ohm, app.Cfg.loudspeaker.maxPower_W);
            s.setGeometryEnvironment(app.Cfg.geometry, app.Cfg.environment);
            app.syncAmplifier();
        end

        function syncAmplifier(app)
            % pass the amplifier fields to the session; a change -> new confirmation
            a = app.Cfg.amplifier; sa = app.Session.Cfg.amplifier;
            sgf = NaN; if isfield(sa, 'gainFactor'), sgf = sa.gainFactor; end
            if ~strcmp(a.model, sa.model) || ~isequaln(a.gainFactor, sgf)
                app.Session.setAmplifierGain(a.model, a.gainFactor);
                app.Cfg.amplifier.knownModels = app.Session.Cfg.amplifier.knownModels;
            end
        end

        function onAmpModel(app, changed)
            % direct drive -> gain fixed to x1; a typed model is added to the list;
            % choosing an amplifier asks for its gain (power check)
            h = app.H; P = tim.gui.palette();
            v = h.ampModel.Value;
            if ~isempty(v) && ~any(strcmp(h.ampModel.Items, v))
                h.ampModel.Items{end+1} = v;
            end
            direct = startsWith(lower(v), 'none');
            if direct
                h.ampGain.Value = 1; app.GainEntered = true;
            elseif changed
                app.GainEntered = false; h.ampGain.Value = 0;   % the gain of the new amplifier is not known yet
            end
            h.ampGain.Enable = matlab.lang.OnOffSwitchState(~direct && ~app.Busy);
            if app.GainEntered, h.ampGain.BackgroundColor = 'w'; else, h.ampGain.BackgroundColor = P.ui.attention; end
            if ~direct
                h.ampGain.Tooltip = sprintf(['Voltage gain of "%s" as a factor (×10 = 20 dB). ' ...
                    'Generator voltage × gain = amplifier output; used for the loudspeaker power check.'], v);
            end
            if changed && ~direct && ~app.GainEntered
                app.log('Amplifier "%s" selected. Enter its voltage gain (Amplifier gain).', v);
            end
            app.updateDrive();
        end

        function g = gainValue(app)
            % amplifier gain of the field; 0 in the field = not entered -> NaN
            g = app.H.ampGain.Value; if ~(g > 0), g = NaN; end
        end

        function onGainChanged(app)
            app.GainEntered = app.H.ampGain.Value > 0;               % 0 = not entered
            if app.GainEntered, app.H.ampGain.BackgroundColor = 'w'; else, app.H.ampGain.BackgroundColor = tim.gui.palette().ui.attention; end
            app.updateDrive();
        end

        function buildCalSteps(app)
            % operator steps of the calibration (same order as tim.app.runCalibration):
            % shown as "pending" before the calibration starts
            c = app.Cfg;
            if ~isempty(app.Session), c = app.Session.Cfg; end   % what runCalibration will use
            ref = c.analysis.refChannel; ab = c.calibration.positions;
            dSec = NaN;
            if isfield(c, 'tubeDrawing') && isfield(c.tubeDrawing, 'specimenSectionLength'), dSec = c.tubeDrawing.specimenSectionLength; end
            secTxt = '';
            if isscalar(dSec) && isfinite(dSec) && dSec > 0, secTxt = sprintf('%g mm ', round(1e3 * dSec, 3)); end
            keys = {'prep'}; labels = {sprintf('Prepare: empty %sspecimen section', secTxt)};
            for k = setdiff(1:4, ref)
                keys{end + 1} = sprintf('ch%d_I', k); %#ok<AGROW>
                labels{end + 1} = sprintf('ch%d  configuration I   (ch%d in M%d, ch%d in M%d)', k, ref, ab(1), k, ab(2)); %#ok<AGROW>
                if c.calibration.repeatConfigI
                    keys{end + 1} = sprintf('ch%d_Irep', k); %#ok<AGROW>
                    labels{end + 1} = sprintf('ch%d  configuration I   repeated (remounted)', k); %#ok<AGROW>
                end
                keys{end + 1} = sprintf('ch%d_II', k); %#ok<AGROW>
                labels{end + 1} = sprintf('ch%d  configuration II  (microphones interchanged)', k); %#ok<AGROW>
            end
            doneLbl = 'Microphones back to M1–M4';
            if ~isfield(c.calibration, 'verifyEmptySection') || c.calibration.verifyEmptySection
                doneLbl = 'Back to M1–M4 + empty-tube check';
            end
            keys{end + 1} = 'done'; labels{end + 1} = doneLbl;
            keys{end + 1} = 'mount'; labels{end + 1} = 'Mount the specimen section again';
            if ~isequal(keys, app.CalKeys) || app.CalStep == 0
                app.CalKeys = keys; app.CalList.rebuild(keys, labels);
            end
            app.CalSteps = numel(keys);
        end

        function doRunCal(app)
            app.readCfgFromUi();
            app.requireGain();
            app.syncSession();
            sw = app.Session.Cfg.excitation.sweep;
            app.log('Calibration with the swept sine %g–%g Hz, %g s, %d repetition(s) (swept-sine settings of EXCITATION).', ...
                sw.fStart, sw.fStop, sw.duration, sw.repetitions);
            app.CalStep = 0; app.CalKeys = {};
            app.buildCalSteps();
            app.CalMap = app.homeMapping();
            app.CalDirty = true;                 % fresh model: current geometry and serials
            calBefore = app.Session.Calibration;
            try
                [cal, file] = tim.app.runCalibration(app.Session, struct( ...
                    'prompt', @(msg, mapping) app.calStep(msg, mapping), 'report', @(q) app.calReport(q)));
            catch err
                app.stopPulse();
                for k = app.CalList.runningKeys()
                    app.CalList.set(k{1}, 'fail', err.message);
                end
                % a calibration saved before the stop (from the "return the microphones"
                % step on) is active: show it
                c1 = app.Session.Calibration;
                if ~isempty(c1) && (isempty(calBefore) || ~strcmp(c1.version, calBefore.version))
                    if ~isempty(app.Session.CalibrationFile), app.Cfg.calibration.file = app.Session.CalibrationFile; end
                    app.showCal(c1);
                    app.log('Calibration %s was saved before the stop and is active.', c1.version);
                end
                rethrow(err);
            end
            app.Cfg.calibration.file = file;
            app.showCal(cal);
            app.refreshViews();                  % the live view showed the calibration sweeps
        end

        function calStep(app, msg, mapping)
            % One operator step of the switching calibration: the diagram shows
            % the microphones moving to their new ports, the calibration ports
            % pulse, then (hardware) the operator confirms or (simulation) the
            % virtual microphones are moved.
            app.CalStep = app.CalStep + 1;
            key = app.CalKeys{min(app.CalStep, end)};
            stepText = tim.app.msg(app.Cfg.ui.language, 'calStepHeader', app.CalStep, app.CalSteps);
            from = app.CalMap;
            app.drawCalSetup(mapping, msg, stepText, from);
            app.showTab(app.H.calTab);
            app.CalList.set(key, 'run', 'operator: place the microphones as shown');
            app.animateCalMics(from, mapping);
            app.CalMap = mapping;
            if strcmp(app.Session.Cfg.mode, 'hardware')       % the session's mode, never the selector
                L = app.Cfg.ui.language;
                if any(strcmp(key, {'prep', 'mount'})) || (strcmp(key, 'done') && ~strcmp(msg, tim.app.msg(L, 'calDone')))
                    done = tim.app.msg(L, 'calContinueButton');   % nothing is measured after this step
                else
                    done = tim.app.msg(L, 'calDoneButton');
                end
                app.startPulse();
                sel = app.ask(sprintf('%s\n\n%s\n%s', stepText, msg, tim.app.msg(L, 'calSeeDiagram')), ...
                    tim.app.msg(L, 'calStepTitle'), {done, tim.app.msg(L, 'abortButton')}, 1, 2, 'question');
                app.stopPulse();
                if ~strcmp(sel, done)
                    app.CalList.set(key, 'fail', 'cancelled by the operator');
                    error('tim:gui:abort', 'Calibration cancelled by the operator.');
                end
            else
                app.Session.setMicPositionsForSimulation(mapping);
            end
            if any(strcmp(key, {'prep', 'mount'}))
                app.CalList.set(key, 'ok', 'confirmed');
            elseif strcmp(key, 'done')
                % the result (or why there is no check) arrives with the 'verification' report
                app.CalList.set(key, 'run', 'saving + empty-tube check ...');
            else
                app.CalList.set(key, 'run', 'measuring (swept sine) ...');
            end
        end

        function calReport(app, q)
            % quality of the measurement just made (tim.app.runCalibration opts.report)
            key = app.CalKeys{min(app.CalStep, end)};
            switch q.kind
                case 'measurement'
                    if ~q.integrityOk || q.fracOk < 0.5
                        st = 'fail';
                    elseif q.fracOk < 0.9
                        st = 'warn';
                    else
                        st = 'ok';
                    end
                    txt = sprintf('%.0f %% OK · γ² %.4f · %.0f dB', ...
                        100 * q.fracOk, q.coherenceMedian, q.snrMedian_dB);
                    if ~q.integrityOk, txt = ['data integrity failed – ' txt]; end
                    app.CalList.set(key, st, txt);
                case 'channel'
                    txt = sprintf(' · C%d %d/%d valid', q.channel, q.nValid, q.Nf);
                    if ~isempty(q.repeatability)
                        txt = sprintf('%s · remount %.2f dB / %.1f°', txt, ...
                            q.repeatability.maxMag_dB, q.repeatability.maxPhase_deg);
                    end
                    app.CalList.appendDetail(key, txt);
                    if q.nValid < 0.9 * q.Nf && strcmp(app.CalList.state(key), 'ok')
                        app.CalList.set(key, 'warn');
                    end
                case 'verification'          % empty-tube check (Test E), 'done' row
                    k = q.check;
                    if ~k.performed      % disabled on purpose = ok; skipped / aborted / error = warn
                        st = 'warn'; if contains(k.text, 'disabled'), st = 'ok'; end
                        app.CalList.set(key, st, k.text);
                    elseif k.passed
                        app.CalList.set(key, 'ok', k.text);
                    else
                        app.CalList.set(key, 'warn', k.text);
                    end
            end
        end

        function drawCalModel(app, mapping)
            % 3D model of the tube in its calibration state (Tube setup model)
            [geom, ~, msgs] = app.readTube();
            if ~isempty(msgs), geom = app.Cfg.geometry; end
            M = tim.gui.drawTube3D(app.H.axCalSetup, geom, app.drawingDims(), mapping, ...
                struct('mode', 'calibration', 'section', true, ...
                'highlightPorts', app.Cfg.calibration.positions, 'micLabels', {app.calMicLabels()}));
            app.H.cal3D = M; app.H.calHi = M.glow; app.H.calPaths = gobjects(0);
            app.CalDrawn = mapping; app.CalDirty = false; app.CalDrawCount = app.CalDrawCount + 1;
        end

        function setCalText(app, mapping, msg, stepText)
            ab = app.Cfg.calibration.positions;
            if isempty(mapping)
                app.H.calText.Text = {sprintf(['Press "Run switching calibration…": every step shows here which microphone goes ' ...
                    'into which port. Calibration ports M%d (a) and M%d (b) glow yellow.'], ab(1), ab(2)), ...
                    ['The empty specimen section (no specimen) is mounted and the tube ends in the absorbing termination. ' ...
                    'Each microphone stays on its own cable and LAN-XI input; only the microphone bodies are moved.']};
            else
                app.H.calText.Text = {sprintf('%s:  %s', stepText, msg), ['Yellow glow = calibration ports a, b;  ' ...
                    'colour and label = channel of the microphone (it keeps its cable);  dashed = last moves.']};
            end
        end

        function L = calMicLabels(app)
            % {'ch1 (ref)', 's/n 1234567'} per DAQ channel
            m = app.Cfg.mics;
            if ~isempty(app.Session) && ~isempty(app.Session.Mics), m = app.Session.Mics; end
            L = cell(1, 4);
            for c = 1:4
                l = {sprintf('ch%d', c)};
                if c == app.Cfg.analysis.refChannel, l{1} = [l{1} ' (ref)']; end
                i = find([m.channel] == c, 1);
                if ~isempty(i)
                    if isfield(m, 'tedsSerial') && isfinite(m(i).tedsSerial)
                        l{end + 1} = sprintf('s/n %d', m(i).tedsSerial); %#ok<AGROW>
                    elseif ~isempty(m(i).serial)
                        l{end + 1} = ['s/n ' char(string(m(i).serial))]; %#ok<AGROW>
                    end
                end
                L{c} = l;
            end
        end

        function map = homeMapping(app)
            % mapping(c) = port of DAQ channel c in the measurement set-up
            map = zeros(1, 4); map([app.Cfg.mics.channel]) = [app.Cfg.mics.position];
        end

        function sideCalLabel(app, c, p)
            % channel label left of a microphone in an odd port, right in an even one
            M = app.H.cal3D; l = M.micLabel(c);
            if ~isgraphics(l), return; end
            s = M.labelSide(p); l.Position(1) = M.micX0(c) + s * M.labelGap;
            if s < 0, l.HorizontalAlignment = 'right'; else, l.HorizontalAlignment = 'left'; end
        end

        function onTabChanged(app, ev)
            % the calibration model is drawn the first time the view is opened
            if ev.NewValue == app.H.calTab && app.CalDirty && ~app.Busy
                app.drawCalSetup([], '', '');
            end
        end

        function showTab(app, tab)
            % select a view: its sub tab and the major tab that holds it
            tg = tab.Parent; tg.SelectedTab = tab;
            p = tg.Parent;
            while ~isempty(p) && ~isa(p, 'matlab.ui.container.Tab') && ~isa(p, 'matlab.ui.Figure')
                p = p.Parent;
            end
            if isa(p, 'matlab.ui.container.Tab')
                old = p.Parent.SelectedTab;
                p.Parent.SelectedTab = p;
                if old ~= p && p == app.H.calTab && app.CalDirty && ~app.Busy
                    app.drawCalSetup([], '', '');
                end
            elseif tab == app.H.calTab && app.CalDirty && ~app.Busy
                app.drawCalSetup([], '', '');
            end
        end

        function animateCalMics(app, from, to)
            % lift each moving microphone out of its holder above all others,
            % across, down. Every mover has its own height (+22 mm) and depth
            % (towards the viewer). Only the hgtransforms change - no redraw.
            delete(app.H.calPaths(isgraphics(app.H.calPaths))); app.H.calPaths = gobjects(0);
            M = app.H.cal3D;
            if isempty(M) || isempty(from) || isequal(from, to), app.CalDrawn = to; return; end
            if any((from > 0) ~= (to > 0)), app.drawCalModel(to); return; end   % a microphone (dis)appears
            moving = find(from ~= to & to > 0);
            moving = moving(isgraphics(M.micGroup(moving)));
            if isempty(moving), app.CalDrawn = to; return; end
            % time based (a uifigure frame takes 0.1-0.2 s): fixed duration
            T = 1.2; t0 = tic; last = false;
            while ~last
                tt = toc(t0); last = tt >= T;
                s = (1 - cos(pi * min(tt / T, 1))) / 2;           % ease in / out
                for i = 1:numel(moving)
                    c = moving(i);
                    [xx, dz] = calPath(s, M.portX(from(c)), M.portX(to(c)), 0, M.lift(i));
                    dy = -12 * (i - 1) * dz / M.lift(i);
                    M.micGroup(c).Matrix = makehgtform('translate', [xx - M.micX0(c), dy, dz]);
                end
                drawnow limitrate; pause(0.02);
            end
            for c = moving, app.sideCalLabel(c, to(c)); end
            app.CalDrawn = to;
            % keep the paths as dashed arrows in front of the cut plane (what was moved where)
            P = tim.gui.palette(); ax = app.H.axCalSetup; z0 = M.zHandle + 2;
            for i = 1:numel(moving)
                c = moving(i); xa = M.portX(from(c)); xb = M.portX(to(c));
                zl = M.zHandle + M.lift(i); y = -8 - 12 * (i - 1);
                hp = line(ax, [xa xa xb xb], y * [1 1 1 1], [z0 zl zl z0], 'LineStyle', '--', ...
                    'Color', P.ch(c, :), 'LineWidth', 1.2, 'Tag', 'calPath');
                ha = patch(ax, xb + [-2.5 2.5 0], y * [1 1 1], z0 + [6 6 0], P.ch(c, :), 'EdgeColor', 'none', 'Tag', 'calPath');
                app.H.calPaths = [app.H.calPaths, hp, ha];
            end
            drawnow;
        end

        function startPulse(app)
            % calibration ports pulse while MATLAB waits for the operator
            app.stopPulse();
            if ~isfield(app.H, 'calHi') || isempty(app.H.calHi), return; end
            app.PulseTimer = timer('ExecutionMode', 'fixedSpacing', 'Period', 0.35, 'BusyMode', 'drop', ...
                'Name', 'TubeApp-calibration-pulse', 'TimerFcn', @(~, ~) app.pulseStep());
            start(app.PulseTimer);
        end
        function pulseStep(app)
            try
                hi = app.H.calHi(isvalid(app.H.calHi));
                if isempty(hi), return; end
                if hi(1).FaceAlpha > 0.4, a = 0.12; else, a = 0.65; end
                set(hi, 'FaceAlpha', a);
                drawnow limitrate
            catch
            end
        end
        function stopPulse(app)
            if ~isempty(app.PulseTimer)
                try, stop(app.PulseTimer); delete(app.PulseTimer); catch, end
                app.PulseTimer = [];
            end
            if isfield(app.H, 'calHi')
                hi = app.H.calHi(isvalid(app.H.calHi));
                if ~isempty(hi), set(hi, 'FaceAlpha', 0.35); end
            end
        end

        function onSave(app)
            if isempty(app.LastMeas), app.alert('Nothing measured yet.', 'Save measurement', 'info'); return; end
            app.run(@() app.doSave(), 'saving the measurement');
        end
        function doSave(app)
            % saved figures = the views (background / unprocessed: time signals and spectrum)
            figs = tim.app.plotResults(app.LastRes, app.LastMeas, struct('Visible', 'off'));
            name = app.LastMeas.kind;
            sp = '';                     % the name entered at Start (metadata.specimen)
            if isfield(app.LastMeas.metadata, 'specimen') && ~strcmp(app.LastMeas.metadata.specimen, 'unnamed specimen')
                sp = app.LastMeas.metadata.specimen;
            end
            if ~isempty(sp), name = [name '_' sp]; end
            c = app.Cfg;                 % the mode of the DATA decides folder and label (not the selector)
            md = app.LastMeas.metadata;
            if isfield(md, 'mode'), c.mode = md.mode; elseif isfield(md, 'WARNING'), c.mode = 'simulation'; end
            d = tim.app.saveMeasurement(app.LastMeas, app.LastRes, c, name, figs);
            fc = struct2cell(figs); if ~isempty(fc), close(fc{:}); end
            app.Saved = true; app.SavedDir = d;
            app.setResultStatus();
            app.log('Saved to %s', d);
        end

        function onReprocess(app)
            if isempty(app.LastMeas) || strcmp(app.LastMeas.kind, 'background'), return; end
            app.run(@() app.doReprocess(), 're-processing');
        end
        function doReprocess(app)
            app.readCfgFromUi();                  % the fields as they are now (geometry, air)
            app.process();
            app.Saved = false; app.SavedDir = '';  % new results: not saved yet
            app.setResultStatus();
        end

        %% ----------------------------------------------------------- display
        function process(app)
            % results of the last measurement with the current configuration and
            % calibration (session; without a session the configured file)
            if strcmp(app.LastMeas.kind, 'background')
                app.LastRes = []; app.refreshViews(); return
            end
            [cal, src] = app.currentCalibration();
            c = app.Cfg;                 % the mode of the DATA (not the selector) for the calibration context
            md = app.LastMeas.metadata;
            if isfield(md, 'mode'), c.mode = md.mode; elseif isfield(md, 'WARNING'), c.mode = 'simulation'; end
            app.LastRes = tim.app.processMeasurement(app.LastMeas, c, cal);
            app.log('%s', app.LastRes.summary);
            app.log('Processed with calibration %s%s; L1/d/L2 = %s/%s/%s mm, T = %g °C.', ...
                app.LastRes.calibration.version, src, app.H.L1.Value, app.H.dTh.Value, app.H.L2.Value, app.H.temp.Value);
            for w = app.LastRes.calibration.context.warnings, app.log('CALIBRATION: %s', w{1}); end
            app.refreshViews();
        end

        function [cal, src] = currentCalibration(app)
            cal = []; src = '';
            if ~isempty(app.Session)
                cal = app.Session.Calibration;
            elseif isfield(app.Cfg.calibration, 'file') && ~isempty(app.Cfg.calibration.file)
                f = tim.app.resolvePath(app.Cfg.calibration.file);
                if isfile(f)
                    ws = warning('off', 'MATLAB:load:variableNotFound'); wsCleanup = onCleanup(@() warning(ws));
                    try
                        S = load(f, 'cal');
                        if isfield(S, 'cal') && isfield(S.cal, 'type') && strcmp(S.cal.type, 'tim.complexChannelCalibration')
                            cal = S.cal; src = ' (from file, not connected)';
                        end
                    catch
                    end
                end
            end
        end

        function o = plotOpts(app, src)
            % options of the tim.plots views
            a = app.Cfg.analysis;
            o = struct('band', [a.fMin a.fMax], 'coherenceMin', a.coherenceMin, 'anechoicRmax', a.anechoicRmax, ...
                'simulation', false);
            if nargin >= 2 && isstruct(src)
                if isfield(src, 'metadata') && isfield(src.metadata, 'WARNING'), o.simulation = true; end
                if isfield(src, 'meta') && isfield(src.meta, 'mode'), o.simulation = strcmp(src.meta.mode, 'simulation'); end
            end
        end

        function refreshViews(app)
            % every measurement / result view from LastMeas / LastRes (empty states
            % show labels, units and default limits)
            m = app.LastMeas; r = app.LastRes;
            o = app.plotOpts(m);
            if isempty(m)
                o.emptyText = 'No measurement yet – connect and press Start measurement';
            elseif strcmp(m.kind, 'background')
                o.emptyText = 'Last record: background noise (no specimen results)';
            elseif isempty(r)
                o.emptyText = 'Not processed';
            end
            pages = {'wave', 'spec', 'tf', 'refl', 'tl', 'zt', 'valid'};
            for i = 1:numel(pages)
                try
                    switch pages{i}
                        case 'wave'
                            info = tim.plots.timeSignals(app.H.axW, m, o);
                            if isfield(info, 'lines'), app.WaveLines = info.lines; else, app.WaveLines = gobjects(0); end
                        case 'spec', info = tim.plots.spectrum(app.H.axSpec, m, r, o);
                        case 'tf', info = tim.plots.transferFunctions(app.H.axH, r, o);
                        case 'refl', info = tim.plots.reflection(app.H.axR, r, o);
                        case 'tl', info = tim.plots.transmissionLoss(app.H.axTL, r, o);
                        case 'zt', info = tim.plots.transferImpedance(app.H.axZ, r, o);
                        case 'valid', info = tim.plots.validity(app.H.axV, r, o);
                    end
                    % notes of the measurement views are information, of the result views warnings
                    if ~isfield(info, 'status') && any(strcmp(pages{i}, {'wave', 'spec', 'tf'})), info.status = 'info'; end
                    app.Pages.(pages{i}).show(info);
                catch err
                    app.log('Display of the %s view failed: %s', pages{i}, err.message);
                end
            end
            if isempty(app.Session) || isempty(app.Session.Calibration)
                [cal, ~] = app.currentCalibration();
            else
                cal = app.Session.Calibration;
            end
            try
                info = tim.plots.calibration(app.H.axCal, cal, app.plotOpts(cal));
                app.Pages.cal.show(info);
            catch err
                app.log('Display of the calibration failed: %s', err.message);
            end
        end

        function setResultStatus(app)
            % RESULTS line: what the last measurement is and whether it is saved
            P = tim.gui.palette(); h = app.H;
            m = app.LastMeas;
            if isempty(m)
                h.resultStatus.Text = 'No measurement'; h.resultStatus.FontColor = P.ui.muted; h.resultStatus.Tooltip = '';
            elseif app.Saved
                [~, nm] = fileparts(app.SavedDir);
                h.resultStatus.Text = ['Saved: ' nm]; h.resultStatus.FontColor = P.ok;
                h.resultStatus.Tooltip = app.SavedDir;
            else
                ts = char(m.timestamp); if numel(ts) >= 19, ts = ts(12:19); end
                h.resultStatus.Text = sprintf('%s %s – not saved', app.capital(app.signalName(m.kind)), ts);
                h.resultStatus.FontColor = P.fail; h.resultStatus.Tooltip = 'Press Save measurement to keep it.';
            end
            app.updateEnable();
        end

        function refreshCalLabel(app)
            % CALIBRATION status: active calibration (session) or configured file,
            % empty-tube check, and whether it still fits the set-up in the fields
            P = tim.gui.palette(); h = app.H;
            if ~isfield(h, 'calLabel') || ~isvalid(h.calLabel), return; end
            cal = []; txt = ''; col = P.ok; tip = {};
            if ~isempty(app.Session) && ~isempty(app.Session.Calibration)
                cal = app.Session.Calibration; txt = cal.version;
            elseif isfield(app.Cfg.calibration, 'file') && ~isempty(app.Cfg.calibration.file)
                f = tim.app.resolvePath(app.Cfg.calibration.file);
                [~, nm] = fileparts(f);
                if isfile(f)
                    txt = sprintf('%s (used at Connect)', nm); col = P.ui.muted;
                    tip{end + 1} = f;
                else
                    txt = sprintf('%s not found', nm); col = P.fail;
                end
            end
            if isempty(txt)
                h.calLabel.Text = 'No calibration – results not valid'; h.calLabel.FontColor = P.fail;
                h.calLabel.Tooltip = 'Load a calibration or run the switching calibration.';
                return
            end
            if ~isempty(cal)
                if isfield(cal, 'meta') && isfield(cal.meta, 'emptyCheck') && cal.meta.emptyCheck.performed
                    if cal.meta.emptyCheck.passed
                        txt = [txt '  ✓ Test E'];
                    else
                        txt = [txt '  ✗ Test E failed']; col = 0.8 * P.warn;
                    end
                    tip{end + 1} = cal.meta.emptyCheck.text;
                end
                % does the calibration still fit the set-up in the fields?
                c = app.Cfg;
                [geom, env, msgs] = app.readTube();
                if isempty(msgs), c.geometry = geom; c.environment = env; end
                if ~isempty(app.Session), c.mode = app.Session.Cfg.mode; end
                ctx = tim.cal.calibrationContext(cal, c);
                if ~isempty(ctx.warnings)
                    txt = [txt '  – check']; col = 0.8 * P.warn;
                    tip = [tip, ctx.warnings];
                end
            end
            h.calLabel.Text = txt; h.calLabel.FontColor = col;
            h.calLabel.Tooltip = strjoin(tip, newline);
        end

        function [y, unit, sens] = toPressure(~, v, mics)
            % volts -> Pa with the resolved sensitivities (display only; the
            % raw data stay in volts). Falls back to mV without a sensitivity.
            sens = [mics.sensitivity_VperPa];
            if numel(sens) == size(v, 2) && all(isfinite(sens) & sens > 0)
                y = v ./ sens; unit = 'Pa';
            else
                y = 1e3 * v; unit = 'mV'; sens = nan(1, size(v, 2));
            end
        end

        function openDoc(app, name)
            % Help menu: a document of docs/ in the MATLAB Editor (plain Markdown text)
            f = fullfile(tim.app.projectRoot(), 'docs', name);
            if isfile(f)
                edit(f);
            else
                app.alert(sprintf('Document not found:\n%s', f), 'Help', 'warning');
            end
        end

        function fig = showAbout(app)
            % Help > About: program, version, release date, Git commit, MATLAB
            % release and the repository link (selectable text: can be copied)
            if ~isempty(app.AboutFig) && isvalid(app.AboutFig)
                figure(app.AboutFig); fig = app.AboutFig; return
            end
            [~, info] = tim.app.softwareVersion();
            p = app.Fig.Position; w = 470; hgt = 250;
            fig = uifigure('Name', 'About Transfer impedance tube', 'Resize', 'off', 'Visible', app.Fig.Visible, ...
                'Position', [p(1) + (p(3) - w) / 2, p(2) + (p(4) - hgt) / 2, w, hgt]);
            app.AboutFig = fig;
            gl = uigridlayout(fig, [5 2], 'RowHeight', {28, 22, '1x', 22, 30}, 'ColumnWidth', {'1x', 90}, ...
                'Padding', [16 12 16 12], 'RowSpacing', 6);
            l = uilabel(gl, 'Text', 'Transfer impedance tube', 'FontSize', 17, 'FontWeight', 'bold');
            l.Layout.Column = [1 2];
            l = uilabel(gl, 'Text', 'Four-microphone transfer-impedance tube measurement (MATLAB)', 'FontColor', [0.35 0.35 0.35]);
            l.Layout.Column = [1 2];
            lines = {sprintf('Program:      %s', info.name), ...
                sprintf('Version:      %s (released %s)', info.version, info.released), ...
                sprintf('Git commit:   %s (branch %s)', info.commit, info.branch), ...
                sprintf('MATLAB:       %s', version()), ...
                'The version and the commit are stored with every measurement and calibration.'};
            ta = uitextarea(gl, 'Value', lines, 'Editable', 'off', 'FontName', 'Consolas', 'FontSize', 11);
            ta.Layout.Column = [1 2];
            app.H.aboutText = ta;
            lk = uihyperlink(gl, 'Text', info.repository, 'URL', info.repository, ...
                'Tooltip', 'opens in the web browser - private repository: sign in with an account that has access');
            lk.Layout.Column = [1 2];
            app.H.aboutLink = lk;
            b = uibutton(gl, 'Text', 'OK', 'ButtonPushedFcn', @(~, ~) delete(fig));
            b.Layout.Row = 5; b.Layout.Column = 2;
        end

        function closingDialog(app, msg)
            % "Closing" progress dialog inside the (already rendered) window:
            % appears at once; its indeterminate bar is animated by the window
            % itself, so it keeps moving while MATLAB waits for an instrument
            msg = cellstr(msg);
            app.ClosingLog = [app.ClosingLog, msg(:).'];
            if isempty(app.Fig) || ~isvalid(app.Fig) || ~strcmp(app.Fig.Visible, 'on'), return; end
            if isempty(app.ClosingWin) || ~isvalid(app.ClosingWin)
                app.ClosingWin = uiprogressdlg(app.Fig, 'Title', 'Closing Transfer impedance tube', ...
                    'Message', msg, 'Indeterminate', 'on', 'Icon', 'info');
            else
                app.ClosingWin.Message = msg;
            end
            drawnow;
        end

        function closeNow(app)
            % shut down with short time-outs and delete the app; every step is
            % shown in the closing dialog
            if app.Closing, return; end
            app.Closing = true;
            app.stopPulse();
            s = app.Session;
            done = {};
            if ~isempty(s) && ~isempty(s.Gen)
                app.closingDialog([done, {'Switching the generator output OFF ...'}]);
                try, s.Gen.outputOff(); catch, end
                done{end + 1} = app.outputOffText();
                s.log('Closing: %s', done{end});
            end
            if ~isempty(s)
                app.closingDialog([done, {'Returning the LAN-XI to Idle (2 s time-out per request) ...'}]);
                try, s.close(true); catch, end
                app.Session = [];
                done{end + 1} = 'Instruments disconnected.';
                s.log('Closing: %s', done{end});
            end
            app.closingDialog([done, {'Closing the window ...'}]);
            if ~isempty(s), s.log('Closing: window deleted.'); end
            fig = app.Fig;
            delete(app);                         % deletes the main window and the dialog
            if isvalid(fig), delete(fig); end
        end
    end
end

function t = loadText(c)
% what the programmed generator amplitude means (generator.load)
if isfield(c.generator, 'load') && strcmp(c.generator.load, '50')
    t = 'voltage into 50 Ω (open circuit: twice)';
else
    t = 'open-circuit peak voltage';
end
end

function safeUnlock(app)
% end of a busy action: restore the controls unless the app was closed meanwhile
if isvalid(app), app.unlockUi(); end
end

function endOp(s)
% end of an operation on a session that may have been closed / deleted meanwhile
if ~isempty(s) && isvalid(s), s.endOperation(); end
end

function [x, y] = calPath(s, xa, xb, y0, yl)
% point at fraction s of the path up - across - down (calibration animation)
up = yl - y0; across = abs(xb - xa); d = s * (2 * up + across);
if d < up
    x = xa; y = y0 + d;
elseif d < up + across
    x = xa + sign(xb - xa) * (d - up); y = yl;
else
    x = xb; y = yl - (d - up - across);
end
end
