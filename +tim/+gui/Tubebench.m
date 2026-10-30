classdef Tubebench < handle
    %TUBEBENCH Main window of tubebench (uifigure, R2022b) for the transfer-impedance tube.
    %
    %   app = tim.gui.Tubebench();                      % default / example config
    %   app = tim.gui.Tubebench('config/user_config.json');
    %   app = tim.gui.Tubebench(file, 'Visible', 'off')  % hidden window (automated tests)
    %   app = tim.gui.Tubebench(file, 'Deferred', false) % visible, every view built before it appears
    %   app.openMeasurement('data/20261009_111602_oneload_sweep_foam')  % show a saved measurement
    %   app.ensureBuilt('all')                         % wait until every view is prepared
    %
    %   Progressive start-up (visible window): a small start window
    %   (tim.gui.StartWindow) shows the steps while the menus, the control
    %   panel, the message pane, all tabs and the start view Setup >
    %   Connection are built; then the main window appears and can be used.
    %   The other views are prepared one at a time in the background by a
    %   timer (order: Tube setup, Calibration, Time signals, Spectrum,
    %   Transfer functions, the four Results views, Formula); each first
    %   shows "Preparing the view…". A view opened before it is ready is
    %   prepared at once, and every action prepares the views it uses before
    %   it starts. A background step NEVER runs while an action runs (Busy),
    %   a session operation or a data stream is active, or the window closes:
    %   it would stall the data stream of the acquisition. A hidden window
    %   builds every view at once (as before, no timer) unless 'Deferred' is
    %   true.
    %
    %   Instruments: the configuration selects the drivers (generator.driver,
    %   daq.driver); the window has no selector. Everything it says about the
    %   instruments comes from the drivers (tim.instr.driverInfo, the
    %   identity() of the connected objects): the INSTRUMENTS lamps, their
    %   labels and tooltips, the "In use" line and the Instruments table of
    %   Setup > Connection (display name before connecting; vendor, model,
    %   serial number and firmware as reported after connecting), the
    %   connection checklist, the Connect / Disconnect texts and the limits
    %   of the EXCITATION fields (docs/instrument_interface.md).
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
    %
    %   Copyright (c) 2026 Woongji Kim. MIT License (LICENSE in the project folder).

    properties (SetAccess = private)
        Fig
        Session = []
        Cfg struct
        LastMeas = []
        LastRes = []
        LastCfg = []            % configuration of LastMeas / LastRes: the one LastRes was computed with
                                % (process), or the opened folder's config.json; written by Save measurement
        H struct = struct()     % UI handles
        Pages struct = struct() % tim.gui.ViewPage of every view
        WaveLines = gobjects(0) % lines of the time-signal view (live update)
        Saved logical = true    % the last measurement is saved (or there is nothing to save)
        SavedDir char = ''      % folder of the last save (or of the opened measurement)
        Opened logical = false  % the last measurement was opened from its folder (File > Open measurement…)
        ReprocessMics = []      % microphones whose channel-to-port mapping Reprocess uses for LastMeas: the
                                % recorded ones of an opened measurement (operator's choice); [] = the configuration's
        GainEntered logical = true  % the gain was entered after an amplifier was chosen
        DriveCheck struct = struct()  % the drive check below the EXCITATION fields (updateDrive): state of the
                                % loudspeaker ('ok' | 'near' | 'over' | 'unknown'), binding criterion, ... (tests)
        LastCheck char = ''     % last configuration warnings (logged once)
        LastTM = []             % transfer-matrix result shown (tim.app.processTwoLoad): two loads, or one
                                % load of a symmetric specimen; [] = none (WO-005)
        LastLoads = []          % the loads of LastTM (role, load, meas, res, cfg, folder); [] = one load
        TwStep double = 0       % current / total operator steps of a two-load measurement
        TwSteps double = 0
        TwList = []             % tim.gui.Checklist of the two-load steps
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
        PulseHi = gobjects(0)   % the glow it pulses (calibration ports, or the termination of a two-load step)
        CloseAfterBusy logical = false  % window close requested during a running action
        Closing logical = false % closeNow running: further close requests are ignored
        ClosingWin = []         % "Closing ..." progress dialog (steps of the shutdown)
        ClosingLog cell = {}    % texts shown in the closing dialog (also when hidden: tests)
        ProgressWin = []        % progress dialog of Save measurement
        AboutFig = []           % Help > About window (one at a time)
        OutputUnconfirmed logical = false  % last read-back did not confirm the generator output off
        LampTips cell = {'', ''}  % tooltips of the two instrument lamps (driver display name, identity)
        PendingStop logical = false % Stop / close before the connection has a session (gui-5)
        BusyWhat char = ''      % the running action ('calibration', 'measurement', ...)
        PromptAnswer char = ''  % answer of the calibration bar (askBar)
        StartWin = []           % start window while the main window is built (tim.gui.StartWindow)
        StartSteps = []         % steps of the start window with their times (diagnostics / tests)
        LastPrompt struct = struct('text', '', 'options', {{}})   % last question of the bar (tests)
        % ---- progressive start-up: views prepared after the window is shown
        Deferred logical = false   % views built in the background (default: visible window)
        PartState struct = struct()% per view (Tubebench.Parts): 'none' | 'built' (controls exist) | 'ready' (drawn)
        BuildQueue cell = {}       % views still to prepare in the background, in this order
        BuildTimer = []            % timer that prepares the queue, one step per tick
        Building char = ''         % view being prepared now (background steps wait)
        Constructing char = ''     % view whose controls are being created now (no action starts meanwhile)
        BuildLog = struct('part', {}, 'stage', {}, 'how', {}, 'start', {}, 'time', {}, 'busy', {}, 'busyWhat', {})
        BuildSkips double = 0      % background ticks skipped: action / session operation / stream running
        ShownTime double = NaN     % s after the start of the constructor: main window shown
        ReadyTime double = NaN     % s after the start of the constructor: every view prepared
        TimerTag char = ''         % Tag of every timer of this window (tests count only their own window's)
        % ---- connection check while idle (the lab generator drops an idle connection unnoticed, 2026-10-12)
        LinkTimer = []             % checks the instruments' connections while idle (hardware, visible window)
        LinkCheckPeriod double = 60   % s between two idle checks
        LinkChecking logical = false  % a check is running: an action clicked meanwhile is not started
    end
    properties (Constant)
        % views prepared after the main window is shown, in this order (the
        % control panel, the message pane, the tabs and Setup > Connection are
        % built before)
        Parts = {'tube', 'cal', 'wave', 'spec', 'tf', 'twoload', 'refl', 'tl', 'zt', 'valid', 'tm', 'formula'}
    end
    properties (Access = private)
        T0                         % tic of the constructor
        Probe struct = struct()    % per view: object + pixel position before the layout (layout check)
    end
    properties
        ConfirmUnsaved logical = true   % ask before an unsaved measurement is replaced or lost
        PromptInSimulation logical = false  % practice: the calibration bar asks at every step in simulation too
    end
    properties (Hidden)
        TestHook = []   % TEST ONLY (tests/TestGui): @(point) called at a fixed point of an action
                        % ('connect:beforeSession', 'open:beforeQuestions'); empty in normal use,
                        % then nothing is called
    end

    methods
        function app = Tubebench(cfgFile, opts)
            arguments
                cfgFile = ''
                opts.Visible (1,:) char = 'on'
                opts.Deferred = []             % views in the background; [] = when visible
                opts.BuildDelay (1,1) double {mustBeNonnegative} = 0.5   % s before the first background step
            end
            % visible: a small start window shows the steps while the main window
            % is built hidden; it disappears when the main window appears, also
            % when the start-up fails. Every step is drawn at the next step.
            % Deferred (default when visible): only the control panel, the tabs and
            % Setup > Connection before the window appears; the other views
            % afterwards in the background (startBuild). Hidden (tests): no start
            % window, every view built here as before.
            app.T0 = tic;
            [~, id] = fileparts(tempname);
            app.TimerTag = ['tubebench-' id];  % unique: another window (the user's) has other timers
            show = strcmp(opts.Visible, 'on');
            deferred = opts.Deferred; if isempty(deferred), deferred = show; end
            app.Deferred = logical(deferred);
            if show
                sw = tim.gui.StartWindow('Area', workArea());
                closeStart = onCleanup(@() delete(sw));     % also on an error
                app.StartWin = sw;
            end
            if ~isempty(cfgFile)
                app.Cfg = tim.app.loadConfig(cfgFile);
            else
                app.Cfg = tim.app.defaultConfig();
            end
            app.startStep('Building the control panel…', 0.06);
            app.buildCore();                  % step: Connection view
            app.startStep('Filling in the settings…', 0.62);
            if show, app.applyRememberedLoads(); end      % the loads of the last two-load Start (WO-005)
            app.refreshFromCfg();
            if ~app.Deferred
                for p = app.Parts, app.ensureBuilt(p{1}, 'sync'); end   % every view now (hidden: tests)
            end
            app.updateEnable();
            app.log(['Ready (%s mode). Not connected - "Connect" switches the generator output OFF; it is ' ...
                'switched on only during a measurement or a calibration.'], app.Cfg.mode);
            if show
                app.startStep('Opening the main window…', 0.86);
                app.Fig.Visible = 'on';
                drawnow;
                app.ShownTime = toc(app.T0);
                app.startStep('Ready', 1);
                app.StartSteps = sw.Steps;
            end
            app.StartWin = [];
            if app.Deferred
                app.startBuild(opts.BuildDelay);
            else
                app.ReadyTime = toc(app.T0);
            end
        end

        function delete(app)
            app.Closing = true;               % background steps stop at once
            app.stopBuild();
            try, app.stopPulse(); catch, end
            try, app.disconnect(true); catch, end
            if ~isempty(app.AboutFig) && isvalid(app.AboutFig), delete(app.AboutFig); end
            if ~isempty(app.Fig) && isvalid(app.Fig), delete(app.Fig); end
        end

        function disconnect(app, quiet)
            % close the session (instruments to a safe state); quiet: no log line
            if nargin < 2, quiet = false; end
            app.stopLinkCheck();
            if ~isempty(app.Session)
                try, app.Session.close(); catch, end
                app.Session = [];
                app.OutputUnconfirmed = false;
                if ~quiet, app.log('Disconnected.'); end
                if isfield(app.H, 'connHead') && isvalid(app.H.connHead)
                    app.H.connHead.Text = 'Disconnected. The list shows the last connection.';
                    app.H.connHead.FontColor = [0.3 0.3 0.3];
                end
                if isfield(app.H, 'instr') && isvalid(app.H.instr), app.refreshInstruments(); end
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

        function r = checkConnectionNow(app)
            %CHECKCONNECTIONNOW Check the instruments' connections now: called by
            %   the idle timer every LinkCheckPeriod s in hardware mode (visible
            %   window), and by tests. Skipped (r = []) while an action, a
            %   session operation or a stream runs, while a view is being
            %   created, or while the window closes. A dropped connection is
            %   re-opened by its driver and the session logs it; a lost one
            %   turns the lamp red, the status line asks for Disconnect and
            %   Connect, and the idle check stops until the next Connect.
            r = [];
            if ~isvalid(app) || app.Busy || app.Closing || app.LinkChecking || ~isempty(app.Constructing) ...
                    || app.sessionActive()
                return
            end
            s = app.Session;
            if isempty(s) || ~isvalid(s) || ~s.Connected, return; end
            app.LinkChecking = true;
            done = onCleanup(@() endLinkCheck(app));
            try
                r = s.checkConnection();
            catch err
                app.stopLinkCheck();
                app.connectionLost(err);
                r = struct('role', s.LostRole, 'state', 'lost', 'detail', err.message);
            end
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

        function openMeasurement(app, folder, useSavedTube, useRecordedMapping)
            %OPENMEASUREMENT Show a measurement saved by Save measurement (also
            %   File > Open measurement…): raw.mat and result.mat of the folder in
            %   every view; Reprocess and Save measurement then work as after a
            %   measurement. The files are only read - a new save writes a new folder.
            %   useSavedTube: 'ask' (default; a hidden window answers yes) | true |
            %   false - put the tube set-up of the saved results (config.json of
            %   the folder) into the IMPEDANCE TUBE fields when it differs from them.
            %   useRecordedMapping: 'ask' (default; a hidden window answers yes) |
            %   true | false - Reprocess uses the channel-to-port mapping the
            %   measurement was recorded with (meas.mics, else the folder's
            %   config.json) when it differs from the configuration's; false keeps
            %   the configuration's (to correct a mapping recorded wrongly).
            if nargin < 3, useSavedTube = 'ask'; end
            if nargin < 4, useRecordedMapping = 'ask'; end
            app.run(@() app.doOpenMeasurement(folder, useSavedTube, useRecordedMapping), 'opening the measurement');
        end

        function sel = ask(app, msg, title, options, defaultIdx, cancelIdx, icon)
            %ASK Operator dialog that can never hang MATLAB: non-blocking
            %   uiconfirm and a wait loop. (A blocking uiconfirm does not return
            %   when the window is closed meanwhile - found in a test on
            %   2026-10-09.) Timers keep running while it waits (pulsing
            %   ports). Closing the window (also while the dialog is being
            %   opened) or STOP returns the cancel option; a hidden window
            %   (scripts, tests) returns the default option.
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
            try
                uiconfirm(app.Fig, msg, title, 'Options', options, 'DefaultOption', defaultIdx, ...
                    'CancelOption', cancelIdx, 'Icon', icon, 'CloseFcn', @(~, ev) setAnswer(ev.SelectedOption));
            catch err
                % the window was closed while the dialog was being opened (opening
                % it lets timers run, e.g. a close request): the cancel option, as
                % when it is closed while the dialog waits (found 2026-10-11 under load)
                if ~isvalid(app) || ~isvalid(app.Fig), sel = options{cancelIdx}; return; end
                rethrow(err);
            end
            while isempty(answer)
                if ~isvalid(app) || ~isvalid(app.Fig) || app.stopPending()
                    answer = options{cancelIdx};
                    break
                end
                pause(0.1);
            end
            sel = answer;
        end

        function sel = askBar(app, msg, options, defaultIdx, cancelIdx)
            %ASKBAR Operator question in the bar above the calibration model:
            %   no modal dialog (the window is not dimmed, nothing covers the
            %   model), buttons on the right of the bar. msg = '' keeps the step
            %   text of the bar. Same rules as ask(): Stop or closing the window
            %   returns the cancel option, a hidden window (scripts, tests) the
            %   default option.
            app.LastPrompt = struct('text', msg, 'options', {options});
            if ~isvalid(app) || ~isvalid(app.Fig) || app.stopPending()
                sel = options{cancelIdx}; return
            end
            if ~strcmp(app.Fig.Visible, 'on'), sel = options{defaultIdx}; return; end
            app.ensureBuilt('cal');
            h = app.H; old = h.calText.Text;
            if ~isempty(msg), h.calText.Text = strrep(htmlText(msg), newline, '<br>'); end
            app.LastPrompt.text = h.calText.Text;
            app.PromptAnswer = '';
            % two options: {action, cancel} - green action button, then the cancel button
            h.calOk.Text = options{1}; h.calCancel.Text = options{2};
            h.calOk.ButtonPushedFcn = @(~, ~) app.setPromptAnswer(options{1});
            h.calCancel.ButtonPushedFcn = @(~, ~) app.setPromptAnswer(options{2});
            app.promptBar(true);
            done = onCleanup(@() app.endPrompt(old, msg));
            while isempty(app.PromptAnswer)
                if ~isvalid(app) || ~isvalid(app.Fig) || app.stopPending()
                    sel = options{cancelIdx}; return
                end
                pause(0.1);
            end
            sel = app.PromptAnswer;
        end
        function sel = confirmExcitation(app, msg, yes, no, ttl)
            % confirmation before the loudspeaker is driven: in the calibration bar
            % during a calibration (no dimmed window), otherwise a dialog. Default = no.
            if strcmp(app.BusyWhat, 'calibration')
                sel = app.askBar(msg, {yes, no}, 2, 2);
            else
                sel = app.ask(msg, ttl, {yes, no}, 2, 2, 'warning');
            end
        end
        function setPromptAnswer(app, s)
            app.PromptAnswer = s;
        end
        function endPrompt(app, old, msg)
            if ~isvalid(app) || ~isvalid(app.Fig) || ~app.isBuilt('cal'), return; end
            if ~isempty(msg), app.H.calText.Text = old; end
            app.promptBar(false);
        end
        function promptBar(app, on)
            % calibration bar: highlighted with the buttons while it waits for the operator
            app.ensureBuilt('cal');
            P = tim.gui.palette(); h = app.H;
            if on
                h.calBar.ColumnWidth = {'1x', max(170, 8 * max(numel(h.calOk.Text), numel(h.calCancel.Text)) + 30)};
                h.calBar.BackgroundColor = P.ui.attention;
                h.calOk.Enable = 'on'; h.calCancel.Enable = 'on';
            else
                h.calBar.ColumnWidth = {'1x', 0};
                h.calBar.BackgroundColor = 'w';
            end
            app.fitCalBar();
            drawnow;
        end
        function fitCalBar(app)
            % the bar keeps its height (116 px: the model does not change size from
            % step to step); only a text longer than that makes it taller
            % (about 6.4 px per character at 12 pt, measured; the HTML tags not counted).
            % Calibration view not built yet: its first drawing calls this again.
            if ~app.isBuilt('cal'), return; end
            h = app.H;
            w = max(300, h.axCalSetup.Position(3) - h.calBar.ColumnWidth{2} - 50);
            t = regexp(regexprep(char(h.calText.Text), '<br>', newline), newline, 'split');
            t = regexprep(t, '<[^>]*>|&nbsp;', ' ');
            n = sum(cellfun(@(s) max(1, ceil(6.4 * numel(s) / w)), t));
            h.calTg.RowHeight{1} = min(max(116, 16 * n + 18), 170);
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
            % until the next action starts; outside an action it means nothing).
            % A window without a session (not connected, e.g. Open measurement for
            % offline reprocessing; or Connect before the session exists) keeps a
            % Stop or a close request in PendingStop / CloseAfterBusy: during an
            % action they count too, so a question of that action is cancelled
            % and the window closes after one request (review 2026-10-11).
            % run() clears PendingStop when an action starts, and CloseAfterBusy
            % is set only while busy, so neither answers a later question.
            s = app.Session;
            tf = ~isempty(s) && isvalid(s) && s.InOperation && s.StopRequested;
            tf = tf || (app.Busy && (app.PendingStop || app.CloseAfterBusy));
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
            app.ensureBuilt('cal');
            shown = fromMapping; if isempty(shown), shown = app.homeMapping(); end
            M = app.H.cal3D;
            if app.CalDirty || isempty(M) || ~all(isgraphics(M.micGroup(shown > 0))) || ~isequal(app.CalDrawn, shown)
                app.drawCalModel(shown);
            end
            app.setCalText(mapping, msg, stepText);
        end

        function showCal(app, cal)
            % calibration curves C_k + summary of the calibration view, label.
            % Calibration view not prepared yet: it shows the active calibration
            % when it is prepared (refreshPart).
            if app.isBuilt('cal')
                info = tim.plots.calibration(app.H.axCal, cal, setfield(app.plotOpts(cal), 'sideBySide', true));
                app.Pages.cal.show(info);
            end
            app.refreshCalLabel();
        end

        %% ------------------------------------------- progressive start-up
        function tf = isBuilt(app, part)
            %ISBUILT The controls of a view exist (Tubebench.Parts; its first
            %   drawing may still be pending in the background).
            tf = isfield(app.PartState, part) && ~strcmp(app.PartState.(part), 'none');
        end

        function ensureBuilt(app, parts, how)
            %ENSUREBUILT Prepare views now (controls + first drawing with the data
            %   of now), unless they are ready: a name of Tubebench.Parts, a cell
            %   array of names or 'all'. Every code path that uses the controls of
            %   a view calls it first; every action calls it BEFORE it acquires
            %   data, so nothing is built while the data stream runs.
            %   how (diagnostics): 'action' | 'tab' | 'demand' | 'sync' | 'background'.
            if nargin < 3, how = ''; end
            if ischar(parts) && strcmp(parts, 'all'), parts = app.Parts; end
            parts = cellstr(parts);
            for i = 1:numel(parts)
                p = parts{i};
                if ~isvalid(app), return; end
                if ~isfield(app.PartState, p)
                    error('tim:gui:part', 'Unknown view "%s" (Tubebench.Parts).', p);
                end
                if strcmp(app.PartState.(p), 'ready'), continue; end
                if strcmp(app.Constructing, p)
                    % only reachable from a timer that interrupted the creation of this view
                    error('tim:gui:notReady', 'The %s view is being prepared - try again in a moment.', app.partLabel(p));
                end
                if isempty(how)
                    w = 'demand'; if app.Busy, w = 'action'; end
                else
                    w = how;
                end
                prev = app.Building; app.Building = p;       % background steps wait meanwhile
                restore = onCleanup(@() restoreBuilding(app, prev));
                if strcmp(app.PartState.(p), 'none')
                    if ~isempty(app.StartWin)            % visible window built before it appears
                        k = find(strcmp(app.Parts, p), 1);
                        app.startStep(sprintf('Building the %s view…', app.partLabel(p)), ...
                            0.62 + 0.24 * (k - 1) / numel(app.Parts));
                    end
                    app.constructPart(p, w);
                    if ~isvalid(app), return; end
                end
                % the first drawing needs the laid-out size of the new controls
                % (3D labels, calibration bar, legends): wait for the layout (usually 1-2 s)
                if ~strcmp(w, 'sync'), app.waitLayout(p); end
                if ~isvalid(app), return; end
                if ~strcmp(app.PartState.(p), 'ready'), app.refreshPart(p, w); end
                clear restore
            end
        end
    end

    methods (Hidden)
        function animateCalMics(app, from, to)
            % lift each moving microphone out of its holder above all others,
            % across, down, with rounded corners (tim.gui.calSwapPath, radius
            % M.swapRadius of the drawing). Every mover has its own height
            % (+10 mm) and depth (towards the viewer). Only the hgtransforms
            % change - no redraw. (Hidden, not private: the tests drive one step.)
            delete(app.H.calPaths(isgraphics(app.H.calPaths))); app.H.calPaths = gobjects(0);
            M = app.H.cal3D;
            if isempty(M) || isempty(from) || isequal(from, to), app.CalDrawn = to; return; end
            if any((from > 0) ~= (to > 0)), app.drawCalModel(to); return; end   % a microphone (dis)appears
            moving = find(from ~= to & to > 0);
            moving = moving(isgraphics(M.micGroup(moving)));
            if isempty(moving), app.CalDrawn = to; return; end
            r = M.swapRadius;
            % time based (a uifigure frame takes 0.1-0.2 s): fixed duration
            T = 1.2; t0 = tic; last = false;
            while ~last
                tt = toc(t0); last = tt >= T;
                s = (1 - cos(pi * min(tt / T, 1))) / 2;           % ease in / out (fraction of the path length)
                for i = 1:numel(moving)
                    c = moving(i);
                    p = tim.gui.calSwapPath(M.portX(from(c)), M.portX(to(c)), 0, M.lift(i), r, s);
                    dy = -12 * (i - 1) * p(2) / M.lift(i);
                    M.micGroup(c).Matrix = makehgtform('translate', [p(1) - M.micX0(c), dy, p(2)]);
                end
                drawnow limitrate; pause(0.02);
            end
            for c = moving, app.sideCalLabel(c, to(c)); end
            app.CalDrawn = to;
            % keep the paths as dashed arrows in front of the cut plane (what was moved where)
            P = tim.gui.palette(); ax = app.H.axCalSetup; z0 = M.zHandle + 2;
            for i = 1:numel(moving)
                c = moving(i); xb = M.portX(to(c)); y = -8 - 12 * (i - 1);
                V = tim.gui.calSwapPath(M.portX(from(c)), xb, z0, M.zHandle + M.lift(i), r);
                hp = line(ax, V(:, 1), y * ones(size(V, 1), 1), V(:, 2), 'LineStyle', '--', ...
                    'Color', P.ch(c, :), 'LineWidth', 1.2, 'Tag', 'calPath');
                ha = patch(ax, xb + [-2.5 2.5 0], y * [1 1 1], z0 + [6 6 0], P.ch(c, :), 'EdgeColor', 'none', 'Tag', 'calPath');
                app.H.calPaths = [app.H.calPaths, hp, ha];
            end
            drawnow;
        end

        function testPoint(app, point)
            % TEST ONLY: calls TestHook at a fixed point of an action (a Stop
            % pressed exactly there, deterministically); nothing when it is empty
            if ~isempty(app.TestHook), app.TestHook(point); end
        end

        function setBuildingFlag(app, p)
            % (restoreBuilding: end of an on-demand preparation, also on an error)
            app.Building = p;
        end

        function setLinkChecking(app, tf)
            % (endLinkCheck: end of a connection check, also on an error)
            app.LinkChecking = tf;
        end

        function onBuildTick(app)
            %ONBUILDTICK One background step of the progressive start-up (timer):
            %   the controls of the next view, or (next tick, once laid out) its
            %   first drawing. Returns at once - and retries at the next tick -
            %   while an action runs (Busy), a session operation or a data stream
            %   is active, a view is being prepared or the window closes: a step
            %   takes 0.5-3 s and would stall the data stream of the acquisition.
            if app.Closing || isempty(app.Fig) || ~isvalid(app.Fig)
                app.stopBuild(); return
            end
            if app.Busy || ~isempty(app.Building) || app.sessionActive()
                app.BuildSkips = app.BuildSkips + 1; return
            end
            q = app.BuildQueue;
            q(cellfun(@(p) strcmp(app.PartState.(p), 'ready'), q)) = [];
            app.BuildQueue = q;
            if isempty(q)
                app.finishBuild(); return
            end
            % the first drawing of a built view as soon as it is laid out; while a
            % view waits for its layout, the controls of the next view
            st = cellfun(@(p) app.PartState.(p), q, 'UniformOutput', false);
            waiting = find(strcmp(st, 'built'));
            k = waiting(arrayfun(@(i) app.layoutDone(q{i}), waiting));
            if isempty(k), k = find(strcmp(st, 'none'), 1); end
            if isempty(k), return; end                  % only layouts to wait for
            p = q{k(1)};
            try
                if strcmp(app.PartState.(p), 'none')
                    app.constructPart(p, 'background');
                else
                    app.refreshPart(p, 'background');
                end
            catch err
                if ~isvalid(app), return; end
                app.BuildQueue(strcmp(app.BuildQueue, p)) = [];
                app.log('Preparing the %s view failed: %s', app.partLabel(p), err.message);
                app.setPlaceholder(p, sprintf('This view could not be prepared: %s', err.message));
            end
        end
    end

    methods (Access = private)
        %% ----------------------------------------------------------- layout
        function buildCore(app)
            % first part of the start-up, before the window appears: menus, control
            % panel, message pane, every major and sub tab and the start view
            % Setup > Connection (the other views: constructPart). Normal window (not
            % maximised) as large as the work area of the screen (the screen without
            % the taskbar), so it fills the laptop screen and can still be moved and
            % resized. Built hidden: the constructor shows it.
            P = tim.gui.palette();
            op = workArea();
            % Position is the inside of the window; a uifigure cannot set OuterPosition
            % (R2022b), so the title bar, menu bar and top border (53 px on Windows 11
            % at 100 % scaling, measured on a screen capture) are subtracted
            app.Fig = uifigure('Name', 'tubebench', 'Position', [op(1) op(2) op(3) op(4) - 53], ...
                'Visible', 'off', 'Color', P.ui.panel, 'Icon', tim.gui.logo('icon'), ...   % title-bar icon: the mark (PNG)
                'CloseRequestFcn', @(src, ~) tim.gui.closeApp(src, app));   % never gets stuck
            h = struct();
            % ---------------- menu bar (version + repository: Help > About)
            m = uimenu(app.Fig, 'Text', 'File');
            h.mOpenMeas = uimenu(m, 'Text', 'Open measurement…', 'MenuSelectedFcn', @(~, ~) app.onOpenMeasurement());
            h.mCombine = uimenu(m, 'Text', 'Combine two saved measurements (two loads)…', ...
                'MenuSelectedFcn', @(~, ~) app.onCombine());
            h.mLoadCfg = uimenu(m, 'Text', 'Load configuration…', 'Separator', 'on', ...
                'MenuSelectedFcn', @(~, ~) app.onLoadConfig());
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
            % heights [px]: about 900 px -> no scrolling in the window
            % on the lab screen (1920 x 1080: about 985 px); Scrollable stays on
            % as a fallback for small screens.
            bar = 26; rw = 24; sp = 4;
            rowH = {bar, 26, 22, 22, 45, ...                %  1- 5 INSTRUMENTS: bar, mode + connect, status, lamps, in use (3 lines)
                sp, bar, rw, 16, rw, 30, ...                %  6-11 IMPEDANCE TUBE: spacer, bar, D/T/p, names, distances, info
                sp, bar, rw, rw, rw, rw, rw, rw, rw, 45, ...% 12-21 EXCITATION: spacer, bar, 7 field rows, drive check (3 lines)
                sp, bar, 22, 28, ...                        % 22-25 CALIBRATION: spacer, bar, status, buttons
                sp, bar, rw, rw, 36, ...                    % 26-30 MEASUREMENT: spacer, bar, specimen, method + background, start / stop
                sp, bar, 22, 28};                           % 31-34 RESULTS: spacer, bar, status, buttons
            left = uigridlayout(g, [numel(rowH) 1], 'RowHeight', rowH, 'ColumnWidth', {'1x'}, ...
                'Scrollable', 'on', 'RowSpacing', 4, 'Padding', [10 8 10 8], 'BackgroundColor', P.ui.panel);
            left.Layout.Row = 1; left.Layout.Column = 1;
            h.left = left;
            LW = 106;                                 % label column of the two-column rows
            ex = {130, '1x', 104, '1x'};              % excitation rows: label (the amplitude label is a list), field, label, field
            r = 0;
            % ---------------- INSTRUMENTS (texts of the instruments: refreshInstruments,
            % from the drivers the configuration selects)
            r = r + 1; app.sectionBar(left, r, 'INSTRUMENTS');
            r = r + 1; rg = app.rowGrid(left, r, {LW, '1x', 86, 86});
            h.modeLabel = app.label(rg, 'Operating mode');
            h.mode = uidropdown(rg, 'Items', {'Simulation', 'Hardware'}, 'ItemsData', {'simulation', 'hardware'}, ...
                'Tooltip', 'Simulation: virtual tube (practice, tests). Hardware: the real instruments. Fixed while connected.');
            h.connect = uibutton(rg, 'Text', 'Connect', 'ButtonPushedFcn', @(~, ~) app.onConnect());
            h.disconnect = uibutton(rg, 'Text', 'Disconnect', 'ButtonPushedFcn', @(~, ~) app.onDisconnect());
            r = r + 1; rg = app.rowGrid(left, r, {LW, '1x'});
            app.label(rg, 'Status');
            h.status = uilabel(rg, 'Text', 'Not connected', 'FontColor', P.ui.muted, 'FontWeight', 'bold');
            % status lamps: signal source and acquisition (labels from the drivers), the
            % four channels (details: Setup > Connection)
            r = r + 1; gl = app.rowGrid(left, r, {88, 70, '1x', '1x', '1x', '1x'});
            h.lampGrid = gl;
            names = {'Generator', 'DAQ', 'ch1', 'ch2', 'ch3', 'ch4'};
            tips = {'', '', 'channel 1', 'channel 2', 'channel 3', 'channel 4'};
            for i = 1:6
                gi = uigridlayout(gl, [1 2], 'Padding', [0 0 0 0], 'ColumnSpacing', 4, 'ColumnWidth', {13, '1x'}, ...
                    'BackgroundColor', P.ui.panel);
                h.lamp(i) = uilamp(gi, 'Color', P.idle, 'Tooltip', [tips{i} ' - details in Setup > Connection']);
                h.lampLabel(i) = uilabel(gi, 'Text', names{i}, 'FontSize', 11, 'Tooltip', tips{i});
            end
            % the instruments in use: display names, after Connect the identity they reported
            r = r + 1; rg = app.rowGrid(left, r, {LW, '1x'});
            h.instrLabel = app.label(rg, 'In use');
            h.instrLabel.VerticalAlignment = 'top';
            h.instr = uilabel(rg, 'Text', '', 'FontSize', 11, 'WordWrap', 'on', 'VerticalAlignment', 'top', ...
                'FontColor', P.ui.muted);
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
                'Tooltip', 'Stop frequency of the excitation [Hz].', ...     % with its limit: refreshFromCfg
                'ValueChangedFcn', @(~, ~) app.updateDrive());
            r = r + 1; rg = app.rowGrid(left, r, ex);
            h.durLabel = app.label(rg, 'Sweep duration [s]');
            h.dur = uieditfield(rg, 'numeric', 'Limits', [0.001 500], 'ValueChangedFcn', @(~, ~) app.updateDrive());
            app.label(rg, 'Repetitions', 'Number of repetitions (averaged).');
            h.reps = uieditfield(rg, 'numeric', 'Limits', [1 100], 'RoundFractionalValues', 'on', ...
                'ValueChangedFcn', @(~, ~) app.updateDrive());
            % the chain from the generator to the loudspeaker, then the level
            % (owner requests 2026-10-12, WO-003: the gain as a plain number,
            % the generator load in the window, the loudspeaker's two values on
            % one row, the level also as the loudspeaker voltage in direct drive;
            % WO-004: the amplifier input sets the generator load, the level at
            % the loudspeaker also with an amplifier, its Vrms, and three lines
            % with the path, the loudspeaker check and the criterion of the maximum)
            r = r + 1; rg = app.rowGrid(left, r, ex);
            app.label(rg, 'Amplifier', ['Power amplifier between the generator and the loudspeaker. Type the model of ' ...
                'your amplifier into the list and press Enter to add it.']);
            h.ampModel = uidropdown(rg, 'Editable', 'on', 'Items', {'none (direct drive)', 'power amplifier'}, ...
                'ValueChangedFcn', @(~, ~) app.onAmpModel(true));   % tooltip: chainEnable
            h.ampModel.Layout.Column = [2 4];
            r = r + 1; rg = app.rowGrid(left, r, {ex{1}, 50, 90, '1x'});   % a short gain, room for the input list
            gainTip = ['Voltage gain of the power amplifier as a factor (Vout / Vin): 20 dB = ×10, 26 dB = ×20, ' ...
                '40 dB = ×100. Do not enter the dB value here.'];
            app.label(rg, 'Amplifier gain [×]', gainTip);
            h.ampGain = uieditfield(rg, 'numeric', 'Limits', [0 Inf], 'ValueDisplayFormat', '%.4g', ...
                'Tooltip', gainTip, 'ValueChangedFcn', @(~, ~) app.onGainChanged());
            % with an amplifier: its input impedance (data sheet), also the
            % generator's load setting; direct drive: the load, fixed at High Z
            h.genLoadLabel = app.label(rg, 'Amp input [Ω]', '');
            h.genLoad = uidropdown(rg, 'Editable', 'on', 'Items', loadItems(''), 'Value', 'High Z', ...
                'ValueChangedFcn', @(~, ev) app.onGenLoad(ev.PreviousValue));
            r = r + 1; rg = app.rowGrid(left, r, ex);
            app.label(rg, 'Loudspeaker [Ω]', 'Nominal (rated) impedance of the loudspeaker.');
            h.spkZ = uieditfield(rg, 'numeric', 'Limits', [0.5 1000], 'ValueChangedFcn', @(~, ~) app.onSpeakerChanged(), ...
                'Tooltip', ['Nominal (rated) impedance of the loudspeaker [Ω]: the loudspeaker voltage and power are ' ...
                'estimated at it (the real impedance varies with frequency).']);
            app.label(rg, 'Test limit [W]', 'Power limit of the loudspeaker for these measurements.');
            h.spkP = uieditfield(rg, 'numeric', 'Limits', [1e-4 1000], 'ValueChangedFcn', @(~, ~) app.updateDrive(), ...
                'Tooltip', ['Power limit of the loudspeaker for these measurements [W], at most its rated power: an ' ...
                'excitation above it (power at the nominal impedance) is refused; from 80 % on it is shown as near the limit.']);
            r = r + 1; rg = app.rowGrid(left, r, ex);
            % the label of the amplitude is a list: what the field gives - the
            % loudspeaker voltage, or the generator's level (open circuit in
            % direct drive, the amplifier input with an amplifier)
            h.ampAt = uidropdown(rg, 'Items', {'Speaker [Vpk]', 'Generator [Vpk]'}, ...
                'ItemsData', {'loudspeaker', 'generator'}, 'ValueChangedFcn', @(~, ev) app.onAmpAt(ev.PreviousValue));
            h.amp = uieditfield(rg, 'numeric', 'Limits', [0.005 10], 'ValueChangedFcn', @(~, ~) app.updateDrive());
            h.ampRms = uilabel(rg, 'Text', '', 'FontColor', P.ui.muted, 'Tooltip', 'The level of the field as rms voltage.');
            h.durEst = uilabel(rg, 'Text', '', 'FontColor', P.ui.muted, 'HorizontalAlignment', 'right', ...
                'Tooltip', 'Expected duration of one measurement.');
            % the drive check (WO-004) in a white box: the signal path; the
            % loudspeaker and the generator side by side, each with a bar of its
            % share of the limit (a tick at 80 %) and its state; the maximum and
            % the criterion that sets it (updateDrive)
            r = r + 1;
            h.drive = uigridlayout(left, [3 1], 'RowHeight', {14, 14, 14}, 'ColumnWidth', {'1x'}, 'RowSpacing', 1, ...
                'Padding', [5 0 5 0], 'BackgroundColor', [1 1 1]);
            h.drive.Layout.Row = r; h.drive.Layout.Column = 1;
            h.drivePath = uilabel(h.drive, 'Text', '', 'FontSize', 11, 'FontColor', P.ui.text);
            meters = uigridlayout(h.drive, [1 2], 'ColumnWidth', {'1x', '1x'}, 'ColumnSpacing', 12, ...
                'Padding', [0 0 0 0], 'BackgroundColor', [1 1 1]);
            [h.spkName, h.spkBar, h.spkPct, h.spkState] = app.meterRow(meters, 'Speaker');
            [h.genName, h.genBar, h.genPct, h.genState] = app.meterRow(meters, 'Generator');
            h.driveMax = uilabel(h.drive, 'Text', '', 'FontSize', 11, 'FontColor', P.ui.muted);
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
            % the method (WO-005; the panel is at its height limit: one row with
            % the background-noise button); the terminations: Setup > Tube setup
            r = r + 1; rg = app.rowGrid(left, r, {LW, '1x', 124});
            app.label(rg, 'Method', ['One load: the termination of Tube setup (τ and the TL from τ need an anechoic ' ...
                'termination). One load, symmetric: the transfer matrix from one load - only for a front-to-back ' ...
                'symmetric specimen. Two loads (ASTM E2611): load A, load B and (optionally) load A again, as set ' ...
                'in Setup > Tube setup.']);
            h.method = uidropdown(rg, 'Items', {'One load', 'One load, symmetric', 'Two loads'}, ...
                'ItemsData', {'oneLoad', 'oneLoadSymmetric', 'twoLoad'}, 'ValueChangedFcn', @(~, ~) app.onMethodChanged(), ...
                'Tooltip', ['One load: today''s measurement. One load, symmetric: T from one load, ASSUMING a symmetric, ' ...
                'reciprocal specimen. Two loads: the transfer matrix from two terminations (ASTM E2611); the ' ...
                'terminations are chosen in Setup > Tube setup.']);
            h.background = uibutton(rg, 'Text', 'Background noise', 'ButtonPushedFcn', @(~, ~) app.onBackground(), ...
                'Tooltip', 'Record 2 s without excitation (background noise level of every channel).');
            r = r + 1; rg = app.rowGrid(left, r, {'1x', 116});
            h.start = uibutton(rg, 'Text', 'Start measurement', 'BackgroundColor', P.ui.start, 'FontColor', 'w', ...
                'FontWeight', 'bold', 'FontSize', 13, 'Icon', tim.gui.icon('start'), 'ButtonPushedFcn', @(~, ~) app.onStart(), ...
                'Tooltip', 'Measure the specimen with the selected signal (hardware mode: asks before the loudspeaker is driven).');
            h.stop = uibutton(rg, 'Text', 'Stop', 'BackgroundColor', P.ui.stop, 'FontColor', 'w', 'FontWeight', 'bold', ...
                'FontSize', 13, 'Icon', tim.gui.icon('stop'), 'ButtonPushedFcn', @(~, ~) app.onStop(), ...
                'Tooltip', 'Stop the running action; the generator output is switched off at once.');
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

            app.startStep('Building the Connection view…', 0.40);   % start window (start-up only)
            % ---------------- every major and sub tab (titles; the content of the
            % views other than Connection: constructPart, after the window appears)
            % Setup > Connection | Tube setup
            t = uitab(tabs, 'Title', 'Setup'); h.setupTab = t;
            h.setupTabs = app.subTabs(t);
            h.connTab = uitab(h.setupTabs, 'Title', 'Connection');
            pg = tim.gui.ViewPage(h.connTab, 'Connection', ['The instruments in use and every step of the ' ...
                'connection: identification, input set-up, sensitivities and a 1 s signal check without excitation. ' ...
                'The generator output stays OFF.'], 'Summary', false);
            app.Pages.conn = pg;
            tg = uigridlayout(pg.Body, [5 1], 'RowHeight', {24, 76, 290, 128, '1x'}, 'RowSpacing', 8, ...
                'Padding', [6 2 0 0], 'BackgroundColor', 'w');
            h.connHead = uilabel(tg, 'Text', 'Press "Connect": every step of the connection is checked here.', ...
                'FontWeight', 'bold', 'FontSize', 13);
            % the instruments of the configuration (one row per role, one row for a
            % device that takes both): display name and driver; after Connect the
            % identity the instrument reported (refreshInstruments)
            h.instrTable = uitable(tg, 'ColumnName', {'Role', 'Instrument', 'Driver', 'Vendor', 'Model', ...
                'Serial number', 'Firmware', 'Settings'}, 'RowName', {}, 'FontSize', 11, 'Data', cell(0, 8), ...
                'ColumnWidth', {170, '4x', 100, 130, 100, 100, 110, '5x'});
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
            % Calibration: operator instruction, 3D diagram, step list, C_k curves
            h.calTab = uitab(tabs, 'Title', 'Calibration');
            % Measurement > Time signals | Spectrum | Transfer functions
            % (titles and descriptions: tim.plots.viewText, shared with the saved figures)
            h.measTab = uitab(tabs, 'Title', 'Measurement');
            h.measTabs = app.subTabs(h.measTab);
            h.waveTab = uitab(h.measTabs, 'Title', tim.plots.viewText('waveforms'));
            h.specTab = uitab(h.measTabs, 'Title', tim.plots.viewText('spectrum'));
            h.tfTab = uitab(h.measTabs, 'Title', tim.plots.viewText('transfer'));
            h.twoLoadTab = uitab(h.measTabs, 'Title', tim.plots.viewText('twoLoad'));   % WO-005
            % Results > Reflection and transmission | Transmission loss | Transfer impedance | Validity
            h.resTab = uitab(tabs, 'Title', 'Results');
            h.resTabs = app.subTabs(h.resTab);
            h.reflTab = uitab(h.resTabs, 'Title', tim.plots.viewText('reflection'));
            h.tlTab = uitab(h.resTabs, 'Title', tim.plots.viewText('transmissionLoss'));
            h.ztTab = uitab(h.resTabs, 'Title', tim.plots.viewText('impedance'));
            h.validTab = uitab(h.resTabs, 'Title', tim.plots.viewText('validity'));
            h.tmTab = uitab(h.resTabs, 'Title', tim.plots.viewText('transferMatrix'));   % WO-005
            % Formula: every equation used by the software
            h.formulaTab = uitab(tabs, 'Title', 'Formula');
            % a view is prepared when its tab is opened (major or sub tab)
            for tgp = [tabs, h.setupTabs, h.measTabs, h.resTabs]
                tgp.SelectionChangedFcn = @(~, ev) app.onTabChanged(ev);
            end
            h.cal3D = []; h.calPaths = gobjects(0); h.calHi = gobjects(0);
            h.placeholder = struct();
            app.H = h;
            for p = app.Parts
                app.PartState.(p{1}) = 'none';
                if app.Deferred      % "Preparing the view…" until the view is built
                    app.H.placeholder.(p{1}) = app.makePlaceholder(app.partTab(p{1}));
                end
            end
        end

        %% ------------------------------- views prepared after the window appears
        function [h, page, probe] = constructTube(app, tab)
            % Setup > Tube setup: 3D model of the tube as entered, geometry table
            P = tim.gui.palette(); h = struct();
            page = tim.gui.ViewPage(tab, 'Tube setup', ['3D model of the tube as entered in IMPEDANCE TUBE ' ...
                '(distances between port centres and specimen faces) with the termination chosen on the right; ' ...
                'microphones coloured by the channel in the port.'], ...
                'SummaryTitle', 'Geometry', 'ToolWidths', {72, 52, 92, 48, 14, 104, 96, 14, 40, 84});
            views = {'Default', 'default'; 'Side', 'side'; 'Perspective', 'perspective'; 'Top', 'top'};
            for i = 1:4
                uibutton(page.Tools, 'Text', views{i, 1}, 'ButtonPushedFcn', @(~, ~) app.tubeView(views{i, 2}), ...
                    'Tooltip', 'viewpoint (rotate / zoom freely with the toolbar of the drawing)');
            end
            uilabel(page.Tools, 'Text', '');
            h.secChk = uicheckbox(page.Tools, 'Text', 'Section view', 'Value', true, ...
                'Tooltip', 'remove the half towards the viewer: bore, specimen and microphone tips visible', ...
                'ValueChangedFcn', @(~, ~) app.onTubeChanged());
            h.dimChk = uicheckbox(page.Tools, 'Text', 'Dimensions', 'Value', true, ...
                'ValueChangedFcn', @(~, ~) app.onTubeChanged());
            % two loads: which load the model shows (WO-005)
            uilabel(page.Tools, 'Text', '');
            h.termShowLabel = uilabel(page.Tools, 'Text', 'Show', 'HorizontalAlignment', 'right');
            h.termShow = uidropdown(page.Tools, 'Items', {'Load A', 'Load B'}, 'ItemsData', {'A', 'B'}, ...
                'Tooltip', 'Two loads: the termination the 3D model shows', 'ValueChangedFcn', @(~, ~) app.refreshTube());
            % the termination (WO-005, owner decision 2026-10-14): a box above the
            % geometry table - one load: its termination; two loads: load A, load B,
            % the repeat of A and the level of B. Kind and place side by side, the
            % same in every row; a muted line says what is mounted and where
            sg = page.SummaryPanel;
            sg.RowHeight = {150, 22, '1x', 96};
            page.SummaryTitle.Layout.Row = 2; page.SummaryTable.Layout.Row = 3; page.SummaryNote.Layout.Row = 4;
            pt = uipanel(sg, 'Title', 'Termination', 'FontWeight', 'bold', 'BackgroundColor', 'w');
            pt.Layout.Row = 1; pt.Layout.Column = 1;
            h.termPanel = pt;
            gt = uigridlayout(pt, [4 4], 'RowHeight', {24, 24, 22, '1x'}, 'ColumnWidth', {74, '1x', 16, 84}, ...
                'Padding', [8 4 8 4], 'RowSpacing', 4, 'ColumnSpacing', 6, 'BackgroundColor', 'w');
            h.termGrid = gt;
            catL = tim.app.describeLoad();
            tipK = ['Absorber: the absorber in the extension tube, end cap on. Rigid cap: a rigid, sealed cap. Open ' ...
                'end: the tube left open. Two loads: any two different terminations; ASTM E2611 and Brüel & Kjær ' ...
                'use an open and an approximately anechoic termination.'];
            tipP = ['Tube end: the end of the extension tube (end cap, the distance tubeDrawing.downstreamLength behind ' ...
                'M4). Joint: the joint of the downstream tube, the extension tube removed (downstreamTubeEnd behind M4). ' ...
                'The absorber exists only at the tube end.'];
            for k = 'AB'
                h.(['termLabel' k]) = uilabel(gt, 'Text', ['Load ' k]);
                h.(['termKind' k]) = uidropdown(gt, 'Items', {catL.kinds.label}, 'ItemsData', {catL.kinds.value}, ...
                    'Tooltip', tipK, 'ValueChangedFcn', @(~, ~) app.onTermChanged());
                uilabel(gt, 'Text', 'at', 'HorizontalAlignment', 'center', 'FontColor', P.ui.muted);
                h.(['termPlace' k]) = uidropdown(gt, 'Items', {catL.places.label}, 'ItemsData', {catL.places.value}, ...
                    'Tooltip', tipP, 'ValueChangedFcn', @(~, ~) app.onTermChanged());
            end
            go = uigridlayout(gt, [1 3], 'ColumnWidth', {'1x', 44, 84}, 'Padding', [0 0 0 0], 'ColumnSpacing', 6, ...
                'BackgroundColor', 'w');
            go.Layout.Row = 3; go.Layout.Column = [1 4];
            h.termRepeat = uicheckbox(go, 'Text', 'Repeat load A at the end', 'ValueChangedFcn', @(~, ~) app.onTermChanged(), ...
                'Tooltip', ['A → B → A: T from A, B and T from A again, B are compared - a moved specimen or ' ...
                'microphone shows (a re-packed absorber does not)']);
            uilabel(go, 'Text', 'B level', 'HorizontalAlignment', 'right', 'Tooltip', ...
                'Generator level of load B relative to load A (only lower; raising it needs the owner''s approval)');
            h.termLevelB = uidropdown(go, 'Items', {'as A', '−3 dB', '−6 dB', '−10 dB', '−20 dB'}, ...
                'ItemsData', {0, -3, -6, -10, -20}, 'ValueChangedFcn', @(~, ~) app.onTermChanged(), 'Tooltip', ...
                ['Generator level of load B relative to load A. A rigid cap raises the sound pressure at the tube ' ...
                'resonances; a lower level keeps a specimen that is not linear at the level it meets with load A.']);
            h.termText = uilabel(gt, 'Text', '', 'FontSize', 11, 'FontColor', P.ui.muted, 'WordWrap', 'on', ...
                'VerticalAlignment', 'top');
            h.termText.Layout.Row = 4; h.termText.Layout.Column = [1 4];
            if app.Busy                % locked like the other inputs (a 3D redraw would stall the stream)
                h.secChk.Enable = 'off'; h.dimChk.Enable = 'off';
                for c = {'termKindA', 'termPlaceA', 'termKindB', 'termPlaceB', 'termRepeat', 'termLevelB', 'termShow'}
                    h.(c{1}).Enable = 'off';
                end
            end
            tg = uigridlayout(page.Body, [2 1], 'RowHeight', {'1x', 0}, 'RowSpacing', 2, 'Padding', [0 0 0 0], ...
                'BackgroundColor', 'w');
            h.axTube3D = uiaxes(tg);
            axtoolbar(h.axTube3D, {'rotate', 'zoomin', 'zoomout', 'pan', 'restoreview'});
            h.tubeInfo = uilabel(tg, 'Text', '', 'FontSize', 11, 'FontColor', P.ui.muted, 'WordWrap', 'on', ...
                'VerticalAlignment', 'top');
            probe = h.axTube3D;        % 3D labels are placed for the laid-out axes width
        end

        function [h, page, probe] = constructCal(~, tab)
            % Calibration: operator bar, 3D diagram, step list, C_k curves
            P = tim.gui.palette(); h = struct();
            page = tim.gui.ViewPage(tab, 'Calibration', ['Switching calibration of the microphone channels with ' ...
                'the empty specimen section (ISO 10534-2): every microphone keeps its cable; only the microphones move.'], ...
                'SummaryTitle', 'Calibration', 'SummaryWidth', 450);
            % body: operator bar (instruction; during a step also the buttons - no
            % modal dialog, nothing covers the model), the 3D model as large as
            % possible, the C_k curves side by side; the step list in the right column
            % fixed bar height (fits the longest step text): the model keeps its size
            % from step to step
            tg = uigridlayout(page.Body, [3 1], 'RowHeight', {116, '1x', 190}, ...
                'RowSpacing', 6, 'Padding', [0 0 0 0], 'BackgroundColor', 'w');
            h.calTg = tg;
            pb = uigridlayout(tg, [4 2], 'ColumnWidth', {'1x', 0}, 'RowHeight', {'1x', 36, 30, '1x'}, ...
                'Padding', [12 4 12 4], 'ColumnSpacing', 14, 'RowSpacing', 6, 'BackgroundColor', 'w');
            pb.Layout.Row = 1;
            h.calBar = pb;
            h.calText = uilabel(pb, 'Text', '', 'WordWrap', 'on', 'FontSize', 12, 'VerticalAlignment', 'center', ...
                'Interpreter', 'html');
            h.calText.Layout.Row = [1 4]; h.calText.Layout.Column = 1;
            h.calOk = uibutton(pb, 'Text', 'Continue', 'FontSize', 13, 'FontWeight', 'bold', ...
                'BackgroundColor', P.ui.start, 'FontColor', 'w');
            h.calCancel = uibutton(pb, 'Text', 'Abort', 'FontSize', 12);
            h.calOk.Layout.Row = 2; h.calOk.Layout.Column = 2;           % buttons stacked on the right
            h.calCancel.Layout.Row = 3; h.calCancel.Layout.Column = 2;
            h.axCalSetup = uiaxes(tg); h.axCalSetup.Layout.Row = 2;
            axtoolbar(h.axCalSetup, {'rotate', 'zoomin', 'zoomout', 'pan', 'restoreview'});
            sg = page.SummaryPanel;                  % right column: C_k table, note, step list
            sg.RowHeight = {22, 104, 66, '1x'};
            pcal = uipanel(sg, 'Title', 'Operator steps and quality of every measurement', 'FontWeight', 'bold', ...
                'BackgroundColor', 'w');
            pcal.Layout.Row = 4;
            h.CalList = tim.gui.Checklist(pcal, {}, {}, ...
                struct('RowHeight', 20, 'FontSize', 11, 'Stacked', true));
            gk = uipanel(tg, 'BorderType', 'none', 'BackgroundColor', 'w');
            gk.Layout.Row = 3;
            tl = tiledlayout(gk, 1, 2, 'TileSpacing', 'compact', 'Padding', 'compact');   % |C_k| | phase
            for i = 1:2
                ax = nexttile(tl); tim.plots.style(ax);
                axtoolbar(ax, {'export', 'zoomin', 'zoomout', 'pan', 'restoreview'});
                h.axCal(i) = ax;
            end
            probe = h.axCalSetup;      % bar height (fitCalBar) and 3D labels need the laid-out width
        end

        function [h, page, probe] = constructTwoLoad(app, tab)
            % Measurement > Two-load (WO-005), built like the Calibration view:
            % operator bar (the load to mount; the buttons only while it waits),
            % the 3D model with that termination glowing, the condition number of
            % the loads and the repeat of load A side by side; on the right the
            % loads and the operator steps. "Show load" picks the load whose
            % measurement and own results the other views show.
            P = tim.gui.palette(); h = struct();
            [vt, vd] = tim.plots.viewText('twoLoad');
            page = tim.gui.ViewPage(tab, vt, vd, 'SummaryTitle', 'Loads', 'SummaryWidth', 450, 'ToolWidths', {74, 96});
            uilabel(page.Tools, 'Text', 'Show load', 'HorizontalAlignment', 'right');
            h.twShow = uidropdown(page.Tools, 'Items', {'A'}, 'ItemsData', {'A'}, 'Enable', 'off', ...
                'ValueChangedFcn', @(~, ~) app.onShowLoad(), 'Tooltip', ['The load whose measurement (time signals, ' ...
                'spectrum, transfer functions) and own results (|R_term|, τ, the validity of the load) are shown.']);
            tg = uigridlayout(page.Body, [3 1], 'RowHeight', {116, '1x', 190}, ...
                'RowSpacing', 6, 'Padding', [0 0 0 0], 'BackgroundColor', 'w');
            h.twTg = tg;
            pb = uigridlayout(tg, [4 2], 'ColumnWidth', {'1x', 0}, 'RowHeight', {'1x', 36, 30, '1x'}, ...
                'Padding', [12 4 12 4], 'ColumnSpacing', 14, 'RowSpacing', 6, 'BackgroundColor', 'w');
            pb.Layout.Row = 1;
            h.twBar = pb;
            h.twText = uilabel(pb, 'Text', '', 'WordWrap', 'on', 'FontSize', 12, 'VerticalAlignment', 'center', ...
                'Interpreter', 'html');
            h.twText.Layout.Row = [1 4]; h.twText.Layout.Column = 1;
            h.twOk = uibutton(pb, 'Text', 'Measure', 'FontSize', 13, 'FontWeight', 'bold', ...
                'BackgroundColor', P.ui.start, 'FontColor', 'w');
            h.twCancel = uibutton(pb, 'Text', 'Abort', 'FontSize', 12);
            h.twOk.Layout.Row = 2; h.twOk.Layout.Column = 2;
            h.twCancel.Layout.Row = 3; h.twCancel.Layout.Column = 2;
            h.axTw3D = uiaxes(tg); h.axTw3D.Layout.Row = 2;
            axtoolbar(h.axTw3D, {'rotate', 'zoomin', 'zoomout', 'pan', 'restoreview'});
            sg = page.SummaryPanel;                  % right column: loads table, note, step list
            sg.RowHeight = {22, 104, 104, '1x'};
            ps = uipanel(sg, 'Title', 'Operator steps and quality of every load', 'FontWeight', 'bold', ...
                'BackgroundColor', 'w');
            ps.Layout.Row = 4;
            h.TwList = tim.gui.Checklist(ps, {}, {}, struct('RowHeight', 20, 'FontSize', 11, 'Stacked', true));
            gk = uipanel(tg, 'BorderType', 'none', 'BackgroundColor', 'w');
            gk.Layout.Row = 3;
            tl = tiledlayout(gk, 1, 2, 'TileSpacing', 'compact', 'Padding', 'compact');   % condQ | repeat of A
            for i = 1:2
                ax = nexttile(tl); tim.plots.style(ax);
                axtoolbar(ax, {'export', 'zoomin', 'zoomout', 'pan', 'restoreview'});
                h.axTwQ(i) = ax;
            end
            probe = h.axTw3D;          % bar height and 3D labels need the laid-out width
        end

        function [h, page, probe] = constructView(~, p, tab)
            % a measurement / result view: header, stacked axes, summary
            % (titles and descriptions: tim.plots.viewText, shared with the saved figures)
            spec = struct( ...
                'wave', {{'waveforms', 'axW', {'Axes', 4}}}, ...
                'spec', {{'spectrum', 'axSpec', {'Axes', 1}}}, ...
                'tf', {{'transfer', 'axH', {'Axes', 3}}}, ...
                'refl', {{'reflection', 'axR', {'Axes', 2, 'AxesHeights', {'2x', '1x'}, 'SummaryTitle', 'Octave bands'}}}, ...
                'tl', {{'transmissionLoss', 'axTL', {'Axes', 1, 'SummaryTitle', 'Octave bands'}}}, ...
                'zt', {{'impedance', 'axZ', {'Axes', 2, 'SummaryTitle', 'Octave bands'}}}, ...
                'valid', {{'validity', 'axV', {'Axes', 1, 'SummaryTitle', 'Criteria', 'SummaryWidth', 470}}}, ...
                'tm', {{'transferMatrix', 'axTM', {'Axes', 2, 'SummaryTitle', 'Octave bands', 'SummaryWidth', 380}}});
            s = spec.(p);
            [vt, vd] = tim.plots.viewText(s{1});
            page = tim.gui.ViewPage(tab, vt, vd, s{3}{:});
            h = struct(s{2}, page.Axes);
            probe = [];                % drawing independent of the laid-out size ...
            if strcmp(p, 'tf'), probe = page.Axes(1); end   % ... except the legend rows (results)
        end

        function l = makePlaceholder(~, tab)
            % "Preparing the view…" in the tab of a view that is not built yet
            % (deleted when the view is built)
            g = uigridlayout(tab, [3 1], 'RowHeight', {'1x', 30, '2x'}, 'BackgroundColor', 'w');
            l = uilabel(g, 'Text', 'Preparing the view…', 'FontSize', 13, 'HorizontalAlignment', 'center', ...
                'FontColor', tim.gui.palette().ui.muted);
            l.Layout.Row = 2;
        end

        function setPlaceholder(app, p, txt)
            if isfield(app.H, 'placeholder') && isfield(app.H.placeholder, p) && isvalid(app.H.placeholder.(p))
                app.H.placeholder.(p).Text = txt;
            end
        end

        function tab = partTab(app, p)
            % tab that holds a view
            names = struct('tube', 'tubeTab', 'cal', 'calTab', 'wave', 'waveTab', 'spec', 'specTab', ...
                'tf', 'tfTab', 'twoload', 'twoLoadTab', 'refl', 'reflTab', 'tl', 'tlTab', 'zt', 'ztTab', ...
                'valid', 'validTab', 'tm', 'tmTab', 'formula', 'formulaTab');
            tab = app.H.(names.(p));
        end

        function p = tabPart(app, tab)
            % view shown by a (major or sub) tab; '' = Setup > Connection
            h = app.H; p = '';
            if tab == h.setupTab, tab = h.setupTabs.SelectedTab;
            elseif tab == h.measTab, tab = h.measTabs.SelectedTab;
            elseif tab == h.resTab, tab = h.resTabs.SelectedTab;
            end
            for i = 1:numel(app.Parts)
                if tab == app.partTab(app.Parts{i}), p = app.Parts{i}; return; end
            end
        end

        function t = partLabel(app, p)
            t = app.partTab(p).Title;
        end

        function constructPart(app, p, how)
            % create the controls of a view: one background step without drawnow
            % (no other callback can run in between). Never half-built: on an error
            % everything created is deleted again and the view stays 'none'.
            tab = app.partTab(p);
            keep = tab.Children;                       % placeholder ("Preparing the view…")
            prevC = app.Constructing; prevB = app.Building;
            app.Constructing = p; app.Building = p;
            t0 = toc(app.T0); tt = tic; busy = app.Busy; bw = app.BusyWhat;
            try
                switch p
                    case 'tube', [h, page, probe] = app.constructTube(tab);
                    case 'cal', [h, page, probe] = app.constructCal(tab);
                    case 'twoload', [h, page, probe] = app.constructTwoLoad(tab);
                    case 'formula'
                        tim.gui.equationsPanel(tab); h = struct(); page = []; probe = [];
                    otherwise, [h, page, probe] = app.constructView(p, tab);
                end
            catch err
                if isvalid(app)
                    app.Constructing = prevC; app.Building = prevB;
                    if isvalid(tab)
                        made = tab.Children(~ismember(tab.Children, keep));
                        delete(made);
                    end
                end
                rethrow(err);
            end
            % commit in one go, after everything exists
            if isfield(h, 'CalList'), app.CalList = h.CalList; h = rmfield(h, 'CalList'); end
            if isfield(h, 'TwList'), app.TwList = h.TwList; h = rmfield(h, 'TwList'); end
            for f = fieldnames(h).'
                app.H.(f{1}) = h.(f{1});
            end
            if ~isempty(page), app.Pages.(p) = page; end
            pos = []; if ~isempty(probe), pos = getpixelposition(probe); end
            app.Probe.(p) = struct('obj', probe, 'pos', pos, 't', tic);
            if isfield(app.H.placeholder, p)
                if isvalid(app.H.placeholder.(p)), delete(app.H.placeholder.(p).Parent); end
                app.H.placeholder = rmfield(app.H.placeholder, p);
            end
            app.PartState.(p) = 'built';
            if strcmp(p, 'cal'), app.setCalText([], '', ''); end   % 3D model: when the tab is opened / first step
            if strcmp(p, 'tube'), app.termToUi(); end               % termination box from the configuration
            if strcmp(p, 'twoload'), app.setTwText('', ''); end
            app.Constructing = prevC; app.Building = prevB;
            app.logBuild(p, 'construct', how, t0, toc(tt), busy, bw);
        end

        function refreshPart(app, p, how)
            % first drawing of a view with the data of now (measurement, results,
            % calibration, IMPEDANCE TUBE fields); a failed drawing is reported in
            % the messages and the view stays usable
            prevB = app.Building; app.Building = p;
            t0 = toc(app.T0); tt = tic; busy = app.Busy; bw = app.BusyWhat;
            try
                switch p
                    case 'tube'
                        app.refreshTube();
                    case 'cal'
                        app.refreshViews({'cal'});     % C_k of the active calibration
                        app.buildCalSteps();
                        app.fitCalBar();               % bar height from the laid-out width of the model
                    case 'twoload'
                        app.refreshViews({'twoload'}); % loads and graphs of the last transfer-matrix result
                        app.buildTwSteps();
                        app.drawTwModel(app.Cfg.measurement.loadA, false);
                    case 'formula'
                    otherwise
                        app.refreshViews({p});
                end
            catch err
                if ~isvalid(app), return; end
                app.log('Display of the %s view failed: %s', app.partLabel(p), err.message);
            end
            if ~isvalid(app), return; end
            app.Building = prevB;
            app.PartState.(p) = 'ready';
            app.logBuild(p, 'refresh', how, t0, toc(tt), busy, bw);
        end

        function logBuild(app, p, stage, how, t0, dt, busy, bw)
            app.BuildLog(end + 1) = struct('part', p, 'stage', stage, 'how', how, 'start', t0, 'time', dt, ...
                'busy', busy, 'busyWhat', bw);
        end

        function tf = layoutDone(app, p)
            % the first drawing of a built view can be made: its controls have their
            % laid-out size (it arrives from the window 0.3-2 s after they were
            % created; hidden window under load: 4 s seen), or the drawing does not
            % depend on it, or 10 s have passed. Size-dependent: 3D labels (Tube
            % setup, Calibration), the calibration bar height (fitCalBar) and the
            % legend rows of the transfer functions.
            if ~isfield(app.Probe, p), tf = true; return; end
            pr = app.Probe.(p);
            tf = isempty(pr.obj) || ~isvalid(pr.obj) || (strcmp(p, 'tf') && isempty(app.LastRes)) || ...
                toc(pr.t) > 10 || ~isequal(getpixelposition(pr.obj), pr.pos);
        end

        function waitLayout(app, p)
            % wait for the layout of a view built on demand (at most 10 s; the
            % window stays usable meanwhile)
            while isvalid(app) && ~app.layoutDone(p)
                pause(0.02);
            end
        end

        function startBuild(app, delay)
            % background preparation of the views not built yet (progressive
            % start-up): one step per tick; the window stays usable in between
            app.BuildQueue = app.Parts(~cellfun(@(p) strcmp(app.PartState.(p), 'ready'), app.Parts));
            if isempty(app.BuildQueue), app.finishBuild(); return; end
            app.log('Preparing the views in the background… A view opened before it is ready is prepared at once.');
            app.BuildTimer = timer('Name', 'tubebench-build', 'ExecutionMode', 'fixedSpacing', 'Period', 0.1, ...
                'BusyMode', 'drop', 'StartDelay', delay, 'TimerFcn', @(t, ~) buildTimerFcn(t, app), 'Tag', app.TimerTag);
            start(app.BuildTimer);
        end

        function stopBuild(app)
            t = app.BuildTimer; app.BuildTimer = [];
            if ~isempty(t) && isvalid(t)
                try, stop(t); delete(t); catch, end
            end
        end

        function finishBuild(app)
            app.stopBuild();
            if isnan(app.ReadyTime)
                app.ReadyTime = toc(app.T0);
                app.log('All views ready (%.0f s after the start).', app.ReadyTime);
            end
        end

        function startLinkCheck(app)
            % hardware mode, visible window: check the connections every
            % LinkCheckPeriod s while idle (checkConnectionNow); a hidden window
            % (scripts, tests) has no idle timer
            app.stopLinkCheck();
            s = app.Session;
            if isempty(s) || ~strcmp(s.Cfg.mode, 'hardware') || ~strcmp(app.Fig.Visible, 'on'), return; end
            app.LinkTimer = timer('Name', 'tubebench-linkcheck', 'ExecutionMode', 'fixedSpacing', ...
                'Period', app.LinkCheckPeriod, 'StartDelay', app.LinkCheckPeriod, 'BusyMode', 'drop', ...
                'TimerFcn', @(~, ~) linkTimerFcn(app), 'Tag', app.TimerTag);
            start(app.LinkTimer);
        end

        function stopLinkCheck(app)
            t = app.LinkTimer; app.LinkTimer = [];
            if ~isempty(t) && isvalid(t)
                try, stop(t); delete(t); catch, end
            end
        end

        function connectionLost(app, err)
            % a connection the driver could not re-open: lamp red, status line
            P = tim.gui.palette();
            app.log('Connection check: %s', err.message);
            k = 1;
            if ~isempty(app.Session) && strcmp(app.Session.LostRole, 'acquisition'), k = 2; end
            if isfield(app.H, 'lamp') && isvalid(app.H.lamp(k))
                app.H.lamp(k).Color = P.fail;
                app.H.lamp(k).Tooltip = 'Connection lost - Disconnect and Connect.';
            end
            app.setStatus('Connection lost - Disconnect and Connect', 'warn');
        end

        function tf = sessionActive(app)
            % a session operation (e.g. a calibration from a script) or an
            % acquisition (data stream) is running
            s = app.Session; tf = false;
            if isempty(s) || ~isvalid(s), return; end
            tf = s.InOperation || (~isempty(s.Daq) && isvalid(s.Daq) && s.Daq.isAcquiring());
        end

        function startStep(app, txt, value)
            % next step in the start window (only while a visible window is built;
            % its drawnow also draws the part of the hidden window built so far)
            if ~isempty(app.StartWin), app.StartWin.update(txt, value); end
        end

        function tg = subTabs(~, tab)
            % second-level tab group inside a major tab
            gg = uigridlayout(tab, [1 1], 'Padding', [0 0 0 0], 'BackgroundColor', 'w');
            tg = uitabgroup(gg);
        end

        function k = connKeys(app)
            % checklist keys: the steps of the configured drivers, then the session's
            s = app.driverSteps();
            k = [{s.key}, {'sens', 'settle', 'signal'}];
        end
        function l = connLabels(app)
            % a driver step after the lamp label of its role ("DAQ: open recorder";
            % owner, 2026-10-13: the roles, not the product names), then the session's
            [s, settle] = app.driverSteps();
            r = app.instruments();
            role = struct('source', r(1).label, 'acquisition', r(2).label, 'both', strjoin({r.label}, ' + '));
            l = cell(1, numel(s));
            for i = 1:numel(s)
                l{i} = s(i).label;
                if isfield(role, s(i).role), l{i} = sprintf('%s: %s', role.(s(i).role), s(i).label); end
            end
            l = [l, {'Microphone sensitivities', settle, 'Signal check (no excitation)'}];
        end
        function [s, settle] = driverSteps(app)
            % connection steps of the drivers configured in app.Cfg (a combined
            % driver once) and the label of the settling step
            s = struct('key', {}, 'label', {}, 'role', {}, 'phase', {});
            settle = 'Settling';
            try
                g = tim.instr.driverInfo(app.Cfg.generator.driver);
                d = tim.instr.driverInfo(app.Cfg.daq.driver);
            catch
                return                              % unknown driver (opened folder of another set-up)
            end
            s = g.steps(:).';
            if ~strcmp(g.name, d.name), s = [s, d.steps(:).']; end
            if ~isempty(d.texts.settle)
                settle = sprintf('Settling (%s)', strtrim(strrep(d.texts.settle, '%s ', '')));
            end
        end

        function r = instruments(app)
            % the instruments of the configuration (of the connection while
            % connected), r(1) signal source, r(2) acquisition, from the drivers
            % only: registry name, display name, lamp label, the noun and the
            % closed state of the window texts (describe().texts), capabilities
            % ([] for an unknown driver: an opened folder of another set-up) and,
            % while connected, the identity the instrument reported
            c = app.Cfg; s = app.Session;
            if ~isempty(s) && isvalid(s), c = s.Cfg; else, s = []; end
            sections = {'generator', 'daq'};
            roles = {'source', 'acquisition'};
            fallback = struct('label', {{'Generator', 'DAQ'}}, 'noun', {{'generator', 'DAQ'}}, ...
                'closed', {{'output off', 'stopped'}});
            r = struct('role', roles, 'driver', '', 'known', false, 'displayName', '', 'label', fallback.label, ...
                'noun', fallback.noun, 'closed', fallback.closed, 'caps', [], 'identity', [], 'combined', false);
            for k = 1:2
                name = c.(sections{k}).driver;
                if isstring(name) && isscalar(name), name = char(name); end
                if ~ischar(name), name = '?'; end
                r(k).driver = name;
                r(k).displayName = sprintf('unknown driver "%s"', name);
                try
                    d = tim.instr.driverInfo(name);
                catch
                    continue                            % not registered here
                end
                r(k).known = true; r(k).displayName = d.displayName; r(k).caps = d.capabilities;
                if isfield(d.labels, roles{k}) && ~isempty(d.labels.(roles{k})), r(k).label = d.labels.(roles{k}); end
                r(k).noun = d.displayName;
                if isfield(d.texts, 'noun') && ~isempty(d.texts.noun), r(k).noun = d.texts.noun; end
                if isfield(d.texts, 'closed') && ~isempty(d.texts.closed), r(k).closed = d.texts.closed; end
            end
            [r.combined] = deal(strcmp(r(1).driver, r(2).driver));
            if ~isempty(s) && s.Connected
                obj = {s.Gen, s.Daq};
                for k = 1:2
                    try, r(k).identity = obj{k}.identity(); catch, end
                end
            end
        end

        function refreshInstruments(app)
            % which instruments are in use, from the drivers (no selection here:
            % the configuration selects them): lamp labels and tooltips, the "In
            % use" line of INSTRUMENTS, the Instruments table of Setup > Connection
            % (the display names before connecting, the identity each instrument
            % reported after connecting), the Connect / Disconnect texts; the
            % checklist follows the configured drivers while not connected
            h = app.H; P = tim.gui.palette();
            r = app.instruments();
            s = app.Session; if ~isempty(s) && ~isvalid(s), s = []; end
            c = app.Cfg; if ~isempty(s), c = s.Cfg; end
            one = r(1).combined;                         % one device takes both roles
            idx = 1:2; if one, idx = 1; end
            connected = ~isempty(r(1).identity) || ~isempty(r(2).identity);
            % lamps: label and tooltip per role
            tips = cell(1, 2);
            for k = 1:2
                tips{k} = sprintf('%s: %s', r(k).label, r(k).displayName);
                if ~isempty(r(k).identity), tips{k} = sprintf('%s – %s', tips{k}, idText(r(k).identity, true)); end
                tips{k} = [tips{k} ' – details in Setup > Connection'];
                h.lampLabel(k).Text = r(k).label; h.lampLabel(k).Tooltip = tips{k};
                h.lamp(k).Tooltip = tips{k};
            end
            app.LampTips = tips;
            w = h.lampGrid.ColumnWidth;
            w(1:2) = {max(88, 25 + 7 * numel(r(1).label)), max(70, 25 + 7 * numel(r(2).label))};
            h.lampGrid.ColumnWidth = w;
            % "In use", one line per instrument: display names, or the identities
            % with the lamp labels
            if connected
                parts = cell(1, numel(idx));
                for i = 1:numel(idx)
                    k = idx(i); lbl = r(k).label;
                    if one, lbl = strjoin({r.label}, ' + '); end
                    parts{i} = sprintf('%s: %s', lbl, idText(r(k).identity, false));
                    if strcmp(c.mode, 'simulation'), parts{i} = [parts{i} ' (simulated)']; end
                end
                h.instr.FontColor = P.ui.text;
            else
                parts = {r(idx).displayName};
                h.instr.FontColor = P.ui.muted;
            end
            h.instr.Text = strjoin(parts, newline);
            tip = sprintf(['The instruments selected in the configuration (generator.driver "%s", daq.driver "%s"); ' ...
                'after Connect, the model and serial number each instrument reported. Details: Setup > Connection. ' ...
                'Other instruments are chosen in the configuration file (user guide, section 9).'], r(1).driver, r(2).driver);
            h.instr.Tooltip = tip; h.instrLabel.Tooltip = tip;
            % Setup > Connection: one row per instrument
            roleText = {'signal source', 'acquisition'};
            rows = cell(numel(idx), 8);
            for i = 1:numel(idx)
                k = idx(i);
                if one
                    role = sprintf('%s (both roles)', strjoin({r.label}, ' + '));
                    st = [app.settingsText(1, c) '; ' app.settingsText(2, c)];
                else
                    role = sprintf('%s (%s)', r(k).label, roleText{k});
                    st = app.settingsText(k, c);
                end
                id = r(k).identity;
                if isempty(id), id = struct('vendor', '', 'model', '', 'serial', '', 'firmware', ''); end
                rows(i, :) = {role, r(k).displayName, r(k).driver, orDash(id.vendor), orDash(id.model), ...
                    orDash(id.serial), orDash(id.firmware), st};
            end
            h.instrTable.Data = rows;
            h.instrTable.Tooltip = app.choicesText(r);
            % Connect / Disconnect and the operating mode, worded with the drivers' nouns
            nouns = {r(idx).noun};
            teds = ~isempty(r(2).caps) && isfield(r(2).caps, 'acquisition') && r(2).caps.acquisition.teds;
            tedsText = ''; if teds, tedsText = ', read TEDS'; end
            h.modeLabel.Tooltip = sprintf('Simulation: virtual tube for practice. Hardware: %s.', strjoin(nouns, ' and '));
            if one
                h.connect.Tooltip = sprintf(['Connect the %s (output off)%s and check every channel ' ...
                    '(Setup > Connection).'], nouns{1}, tedsText);
            else
                h.connect.Tooltip = sprintf(['Connect the %s and the %s (%s output off)%s and check every channel ' ...
                    '(Setup > Connection).'], nouns{1}, nouns{2}, nouns{1}, tedsText);
            end
            h.disconnect.Tooltip = [app.capital(app.closedText(r)) ', connections closed.'];
            % checklist of the configured drivers (while connected: the connection's)
            if isempty(s) && ~isempty(app.ConnList)
                keys = app.connKeys();
                if ~isequal(keys, app.ConnList.Keys), app.ConnList.rebuild(keys, app.connLabels()); end
            end
        end

        function t = closedText(app, r)
            % '<noun> <closed>, <noun> <closed>' (e.g. 'generator output off'):
            % what closing the connection leaves each instrument in
            % (describe().texts of the drivers)
            if nargin < 2, r = app.instruments(); end
            idx = 1:2; if r(1).combined, idx = 1; end
            t = strjoin(arrayfun(@(k) sprintf('%s %s', r(k).noun, r(k).closed), idx, 'UniformOutput', false), ', ');
        end

        function t = settingsText(~, k, c)
            % the configured settings of a role: generator limit and load, or the
            % input settings of the acquisition
            if k == 1
                t = sprintf('limit %g Vpp (open circuit), load %s', c.generator.maxVpp, char(string(c.generator.load)));
            else
                a = c.acquisition; cc = logical(a.ccld);
                if all(cc), cl = 'on'; elseif ~any(cc), cl = 'off'; else, cl = ['on ch' sprintf('%d', find(cc))]; end
                t = sprintf('%g S/s, %s, high-pass %s, CCLD %s', a.sampleRate, char(string(a.range)), ...
                    char(string(a.filter)), cl);
            end
        end

        function t = choicesText(~, r)
            % tooltip of the Instruments table: what each driver allows for the
            % settings of the configuration (capabilities(); no selector here)
            lines = {'Settings from the configuration; the values the drivers allow:'};
            if ~isempty(r(1).caps) && isfield(r(1).caps, 'source')
                q = r(1).caps.source;
                lims = arrayfun(@(i) sprintf('%s %g–%g Vpp', q.loads{i}, q.minVpp(i), q.maxVpp(i)), ...
                    1:numel(q.loads), 'UniformOutput', false);
                if isfield(q, 'loadRange') && ~isempty(q.loadRange)
                    lims{end + 1} = sprintf('or any %g–%g Ω (the amplifier input)', q.loadRange);
                end
                lines{end + 1} = sprintf('%s – generator.load and level: %s; sweep %g–%g s; signals %s.', ...
                    r(1).displayName, strjoin(lims, ', '), q.sweepTime, strjoin(q.waveforms, ', '));
            end
            if ~isempty(r(2).caps) && isfield(r(2).caps, 'acquisition')
                q = r(2).caps.acquisition;
                if isempty(q.sampleRates)
                    rates = sprintf('%g–%g', q.sampleRateRange);
                else
                    rates = strjoin(arrayfun(@(x) sprintf('%g', x), q.sampleRates, 'UniformOutput', false), ', ');
                end
                yn = {'no', 'yes'};
                lines{end + 1} = sprintf(['%s – acquisition.sampleRate %s S/s; range %s; filter %s; switchable CCLD %s; ' ...
                    'TEDS %s.'], r(2).displayName, rates, strjoin(q.ranges, ', '), strjoin(q.filters, ', '), ...
                    yn{1 + q.ccld}, yn{1 + q.teds});
            end
            t = strjoin(lines, newline);
        end

        function L = excitationLimits(app)
            % limits of the EXCITATION fields from the configured drivers: the
            % highest frequency (usable band of the acquisition, source range),
            % the smallest level at the configured load and the sweep durations
            % of the source (today's values when a driver is unknown)
            c = app.Cfg; r = app.instruments();
            fs = c.acquisition.sampleRate;
            L = struct('fMin', 1, 'fMax', 0.45 * fs, 'minVpp', 0.01, 'sweepTime', [0.001 500], ...
                'fText', sprintf('0.45 × sample rate (%g S/s)', fs));
            if ~isempty(r(2).caps) && isfield(r(2).caps, 'acquisition')
                b = r(2).caps.acquisition.bandFraction;
                L.fMax = b * fs; L.fText = sprintf('%.2g × sample rate (%g S/s, %s)', b, fs, r(2).displayName);
            end
            if ~isempty(r(1).caps) && isfield(r(1).caps, 'source')
                q = r(1).caps.source;
                L.fMin = max(1, q.frequencyRange(1));
                if q.frequencyRange(2) < L.fMax
                    L.fMax = q.frequencyRange(2); L.fText = sprintf('the %s', r(1).displayName);
                end
                if isfinite(q.bandFraction) && q.bandFraction * fs < L.fMax     % shared clock
                    L.fMax = q.bandFraction * fs;
                    L.fText = sprintf('%.2g × sample rate (%g S/s, %s)', q.bandFraction, fs, r(1).displayName);
                end
                lo = tim.instr.SignalSource.levelRange(q, char(string(c.generator.load)));   % also a numeric load
                if isfinite(lo), L.minVpp = lo; end
                L.sweepTime = q.sweepTime;
            end
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
        function [nameL, bar, pct, st] = meterRow(~, parent, name)
            % one meter of the drive check: name, a bar of the share of a limit
            % (four plain panels in a grid: filled part, track, the 80 % tick,
            % track - setBar), the share in %, the state as a coloured box
            P = tim.gui.palette();
            g = uigridlayout(parent, [1 4], 'ColumnWidth', {'fit', '1x', 36, 40}, 'ColumnSpacing', 4, ...
                'Padding', [0 0 0 0], 'BackgroundColor', [1 1 1]);
            nameL = uilabel(g, 'Text', name, 'FontSize', 11, 'FontColor', P.ui.text);
            b = uigridlayout(g, [1 4], 'ColumnWidth', {'1x', '1x', 1, '1x'}, 'ColumnSpacing', 0, 'RowSpacing', 0, ...
                'Padding', [0 3 0 3], 'BackgroundColor', [1 1 1]);
            parts = gobjects(1, 4);
            for i = 1:4, parts(i) = uipanel(b, 'BorderType', 'none', 'BackgroundColor', P.idle); end
            bar = struct('grid', b, 'part', parts);
            pct = uilabel(g, 'Text', '', 'FontSize', 10, 'HorizontalAlignment', 'right', 'FontColor', P.ui.muted);
            st = uilabel(g, 'Text', '', 'FontSize', 10, 'FontWeight', 'bold', 'FontColor', [1 1 1], ...
                'HorizontalAlignment', 'center', 'BackgroundColor', P.idle);
        end

        function setMeter(~, bar, pct, st, f, state, tip)
            % one meter: the bar filled to the share f of the limit (0..1, the
            % tick at 0.8), its % text and the state box (ok / near / over /
            % unknown); the same tooltip on all of them
            P = tim.gui.palette();
            track = [0.89 0.90 0.93]; tick = [0.45 0.47 0.50];
            switch state
                case 'ok',   col = P.ok;   txt = 'OK';
                case 'near', col = P.warn; txt = 'Near';
                case 'over', col = P.fail; txt = 'Above';
                otherwise,   col = P.fail; txt = 'Gain?';
            end
            if isfinite(f)
                if f < 0.001, pct.Text = '<0.1 %'; else, pct.Text = sprintf('%.3g %%', 100 * f); end
            else
                pct.Text = '– %'; f = 0;
            end
            f = min(max(f, 0), 1);
            w = @(x) sprintf('%.6fx', max(x, 1e-6));
            if f <= 0.8
                bar.grid.ColumnWidth = {w(f), w(0.8 - f), 1, w(0.2)};
                c = {col, track, tick, track};
            else
                bar.grid.ColumnWidth = {w(0.8), 1, w(f - 0.8), w(1 - f)};
                c = {col, tick, col, track};
            end
            for i = 1:4, bar.part(i).BackgroundColor = c{i}; end
            st.Text = txt; st.BackgroundColor = col;
            pct.Tooltip = tip; st.Tooltip = tip; bar.grid.Tooltip = tip;
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
            app.tubeToUi(c.geometry, c.environment);     % tube geometry [mm] and air
            ls = struct('impedance_ohm', 8, 'maxPower_W', 1);
            if isfield(c, 'loudspeaker'), ls = c.loudspeaker; end
            h.spkZ.Value = ls.impedance_ohm; h.spkP.Value = ls.maxPower_W;
            % the instruments in use (lamps, In use, Setup > Connection, Connect texts)
            app.refreshInstruments();
            % frequency fields: up to the usable band of the configured drivers
            % (checkConfig); amplitude from the smallest level of the source at the
            % configured load up to the safety limit
            L = app.excitationLimits();
            h.fStart.Limits = [L.fMin L.fMax]; h.fStop.Limits = [L.fMin L.fMax];
            h.fStop.Tooltip = sprintf('Stop frequency of the excitation [Hz]; at most %.6g Hz = %s.', L.fMax, L.fText);
            % (a generic 'power amplifier' entry stays in the list, so that
            % choosing an amplifier never needs typing - owner request 2026-10-12)
            items = c.amplifier.knownModels; if ischar(items), items = {items}; end
            items = [{'none (direct drive)', 'power amplifier'}, ...
                reshape(items(~ismember(items, {'none (direct drive)', 'power amplifier'})), 1, [])];
            if ~isempty(c.amplifier.model) && ~any(strcmp(items, c.amplifier.model)), items{end+1} = c.amplifier.model; end
            h.ampModel.Items = items;
            if isempty(c.amplifier.model), h.ampModel.Value = items{1}; else, h.ampModel.Value = c.amplifier.model; end
            gf = c.amplifier.gainFactor; if ~(gf > 0), gf = 0; end      % 0 = gain not entered
            h.ampGain.Value = gf;
            app.GainEntered = gf > 0 || startsWith(lower(h.ampModel.Value), 'none');   % the configuration states the gain
            app.loadsToUi();                                   % amplifier input / generator load of the configuration
            at = 'generator';
            if isfield(c, 'ui') && isfield(c.ui, 'amplitudeAt'), at = char(c.ui.amplitudeAt); end
            % the level at the loudspeaker needs the gain with an amplifier (WO-004)
            if ~any(strcmp(at, h.ampAt.ItemsData)) || ~app.GainEntered, at = 'generator'; end
            app.ampAtItems();
            h.ampAt.Value = at;
            app.ampToUi(c.excitation.sweep.amplitudeVpp / 2);  % in the unit of the amplitude label, with its limits
            app.excitationToUi(h.exMode.Value);
            app.onAmpModel(false);
            % the method and the terminations (WO-005; the box: Setup > Tube setup)
            if isfield(c, 'measurement') && any(strcmp(c.measurement.method, h.method.ItemsData))
                h.method.Value = c.measurement.method;
            end
            app.updateStartText();
            app.termToUi();
            app.onTubeChanged();
            if isempty(app.Session), app.refreshCards(); end
            app.buildCalSteps();
            app.refreshCalLabel();
        end

        function loadsToUi(app)
            % the amplifier input / generator load list from the configuration:
            % direct drive High Z (fixed); with an amplifier its input impedance
            % (amplifier.inputImpedance_ohm), else the configured numeric load,
            % else High Z (WO-004)
            h = app.H; c = app.Cfg;
            v = 'High Z';
            if ~startsWith(lower(c.amplifier.model), 'none')
                zin = NaN;
                if isfield(c.amplifier, 'inputImpedance_ohm') && ~isempty(c.amplifier.inputImpedance_ohm)
                    zin = c.amplifier.inputImpedance_ohm;
                end
                R = tim.instr.SignalSource.loadOhm(c.generator.load);
                if zin > 0 && isfinite(zin), v = sprintf('%.10g', zin); elseif isfinite(R), v = sprintf('%.10g', R); end
            end
            h.genLoad.Items = loadItems(v);
            h.genLoad.Value = v;
        end

        function c = fieldsCfg(app)
            % the configuration with the drive chain as the EXCITATION fields
            % show it (amplifier, gain, amplifier input / load, loudspeaker)
            c = app.Cfg; h = app.H;
            c.amplifier.model = h.ampModel.Value;
            g = app.gainValue();
            if startsWith(lower(h.ampModel.Value), 'none'), g = 1; end
            c.amplifier.gainFactor = g; c.amplifier.gain_dB = 20 * log10(g);
            [c.generator.load, c.amplifier.inputImpedance_ohm] = app.loadFromUi();
            c.loudspeaker.impedance_ohm = h.spkZ.Value;
            c.loudspeaker.maxPower_W = h.spkP.Value;
        end

        function [load, zin] = loadFromUi(app)
            % generator.load and amplifier.inputImpedance_ohm of the list: direct
            % drive or High Z -> 'INF', NaN; an amplifier input of R ohm -> R as
            % text up to the generator's largest load setting (its loadRange,
            % e.g. 10 kΩ; INF above it), R. While connected: the load in use.
            load = 'INF'; zin = NaN;
            if ~isempty(app.Session), load = char(string(app.Cfg.generator.load)); end
            if startsWith(lower(app.H.ampModel.Value), 'none'), return; end
            R = loadValue(app.H.genLoad.Value);
            if ~(isfinite(R) && R > 0), return; end
            zin = R;
            if isempty(app.Session)
                rMax = 1e4;
                try
                    q = tim.instr.driverInfo(app.Cfg.generator.driver).capabilities.source;
                    if isfield(q, 'loadRange') && ~isempty(q.loadRange), rMax = q.loadRange(2); else, rMax = 0; end
                catch
                end
                if R <= rMax, load = sprintf('%.10g', R); end
            end
        end

        function k = speakerFactor(app)
            % loudspeaker voltage per volt of programmed generator amplitude,
            % from the fields (tim.app.driveEstimate): direct drive through the
            % source impedance and the nominal loudspeaker impedance; with an
            % amplifier its input and gain (NaN without a gain)
            d = tim.app.driveEstimate(app.fieldsCfg(), 2);      % 1 Vpk programmed
            k = d.Vspk_pk;
        end

        function [lo, lim] = generatorLimits(app)
            % generator amplitude range [Vpk]: the smallest level of the generator
            % at the load up to the safety limit generator.maxVpp (open circuit)
            % and the generator's largest level at the load (tim.app.driveLimits)
            c = app.fieldsCfg(); L = tim.app.driveLimits(c, app.H.exMode.Value);
            gen = L.criteria(~strcmp({L.criteria.key}, 'speaker'));
            lim = min([gen.maxVpp]) / 2;
            lo = L.minVpp / 2; if ~isfinite(lo), lo = app.excitationLimits().minVpp / 2; end
            if lo >= lim, lo = lim / 2; end
        end

        function ampToUi(app, genVpk)
            % generator amplitude [Vpk] -> the amplitude field, in the unit that
            % the amplitude label selects (the loudspeaker, or the generator's
            % level: open circuit in direct drive, the amplifier input with an
            % amplifier; WO-003, WO-004), with the generator's limits in that unit
            h = app.H; c = app.fieldsCfg();
            [lo, lim] = app.generatorLimits();
            genVpk = min(max(genVpk, lo), lim);
            direct = startsWith(lower(h.ampModel.Value), 'none');
            if strcmp(h.ampAt.Value, 'loudspeaker')
                k = app.speakerFactor();
                h.amp.Limits = [lo lim] * k;
                h.amp.Value = min(max(genVpk * k, h.amp.Limits(1)), h.amp.Limits(2));
                if direct
                    how = sprintf('direct drive through the %g Ω source impedance', app.sourceImpedance());
                else
                    how = sprintf('amplifier gain ×%.4g', app.gainValue());
                end
                h.amp.Tooltip = sprintf(['Loudspeaker voltage [Vpk] at the nominal %g Ω (%s); the generator is set to ' ...
                    'the matching level: %.3g to %.3g Vpk at the loudspeaker = %.3g to %.3g Vpk %s (generator.maxVpp = ' ...
                    '%.3g Vpp open circuit). The power check is shown below.'], h.spkZ.Value, how, lo * k, lim * k, lo, lim, ...
                    loadText(c), c.generator.maxVpp);
            else
                h.amp.Limits = [lo lim];
                h.amp.Value = genVpk;
                h.amp.Tooltip = sprintf(['Generator level [Vpk], %s; from %.3g Vpk (smallest level of the generator ' ...
                    'at load %s) up to %.3g Vpk (generator.maxVpp = %.3g Vpp open circuit)'], ...
                    loadText(c), lo, loadName(c.generator.load), lim, c.generator.maxVpp);
            end
        end

        function v = ampFromUi(app)
            % generator amplitude [Vpk] of the amplitude field (the programmed level)
            v = app.H.amp.Value;
            if strcmp(app.H.ampAt.Value, 'loudspeaker')
                v = v / app.speakerFactor();
                [~, lim] = app.generatorLimits();
                v = min(v, lim);                               % (rounding at the limit)
            end
        end

        function ampAtItems(app)
            % the items of the level reference: the loudspeaker, and the
            % generator's level as what it is - Generator (open circuit) in
            % direct drive, Amp input with an amplifier (WO-004)
            h = app.H;
            if startsWith(lower(h.ampModel.Value), 'none')
                h.ampAt.Items = {'Speaker [Vpk]', 'Generator [Vpk]'};
            else
                h.ampAt.Items = {'Speaker [Vpk]', 'Amp input [Vpk]'};
            end
            h.ampAt.ItemsData = {'loudspeaker', 'generator'};
        end

        function Rs = sourceImpedance(app)
            % source impedance of the configured generator driver [Ω] (0 = not known)
            Rs = 0;
            try, Rs = tim.instr.driverInfo(app.Cfg.generator.driver).capabilities.source.outputImpedance_ohm; catch, end
        end

        function onAmpAt(app, previous)
            % the amplitude label changed: the same physical level, in the other unit
            h = app.H; v = h.amp.Value;
            if strcmp(previous, 'loudspeaker'), v = v / app.speakerFactor(); end
            app.Cfg.ui.amplitudeAt = h.ampAt.Value;
            app.ampToUi(v);
            app.updateDrive();
        end

        function onSpeakerChanged(app)
            % loudspeaker impedance changed: an amplitude given at the loudspeaker
            % is kept (the generator level follows), and its limits follow
            if strcmp(app.H.ampAt.Value, 'loudspeaker'), app.ampToUi(app.ampFromUi()); end
            app.updateDrive();
        end

        function onGenLoad(app, previous)
            % amplifier input impedance changed (typed or chosen; not connected):
            % it is also the generator's load setting, sent at the next Connect
            % (WO-004). A level given at the loudspeaker is kept, otherwise the
            % number of the level field (now the voltage at the new input).
            h = app.H;
            typed = char(string(h.genLoad.Value));
            R = loadValue(typed);
            if ~(R > 0)
                h.genLoad.Value = previous;
                app.alert(sprintf(['Amplifier input "%s": enter the input impedance of the amplifier in ohm (data ' ...
                    'sheet), e.g. 600, or High Z.'], typed), 'Amplifier input', 'warning');
                return
            end
            v = 'High Z'; if isfinite(R), v = sprintf('%.10g', R); end
            h.genLoad.Items = loadItems(v); h.genLoad.Value = v;
            [app.Cfg.generator.load, app.Cfg.amplifier.inputImpedance_ohm] = app.loadFromUi();
            if strcmp(h.ampAt.Value, 'loudspeaker')
                app.ampToUi(h.amp.Value / app.speakerFactor());   % the loudspeaker level stays
            else
                app.ampToUi(h.amp.Value);                         % the number stays (the new input's voltage)
            end
            app.log('Amplifier input: %s, was %s - generator load %s (%s). Sent to the generator at the next Connect.', ...
                loadName(v), loadName(previous), loadName(app.Cfg.generator.load), loadText(app.Cfg));
            app.updateDrive();
        end

        function tubeToUi(app, gm, env)
            % geometry and air -> IMPEDANCE TUBE fields. Coordinates in the config ->
            % distances s1, L1, d, L2, s2 in the GUI, on a 1 nm grid
            % (1e3*(-0.041 - (-0.07)) alone would be 29.000000000000004)
            h = app.H;
            h.tubeD.Value = app.toMm(gm.diameter);
            x = gm.micPositions;
            if all(isfinite(x))
                h.s1.Value = app.toMm(x(2) - x(1)); h.s2.Value = app.toMm(x(4) - x(3));
            else
                h.s1.Value = app.toMm(gm.spacingUp); h.s2.Value = app.toMm(gm.spacingDown);
            end
            h.L1.Value = app.mm2txt(gm.xFront - x(2));
            h.dTh.Value = app.mm2txt(gm.xRear - gm.xFront);
            h.L2.Value = app.mm2txt(x(3) - gm.xRear);
            h.temp.Value = env.temperature_C; h.pres.Value = env.pressure_Pa / 1e3;
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
                T = app.excitationLimits().sweepTime;     % sweep durations of the generator
                h.durLabel.Text = 'Sweep duration [s]';
                h.dur.RoundFractionalValues = 'off'; h.dur.Limits = T; h.dur.Value = min(max(s.duration, T(1)), T(2));
                h.dur.Tooltip = sprintf('duration of one sweep [s], %g to %g s', T);
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
                % the analysis band and the standard it follows (owner decision
                % 2026-10-13): analysis.bandMode 'geometry' moves it with the fields
                b = app.bandOfFields();
                if strcmp(b.mode, 'geometry') && isempty(msgs)
                    app.Cfg.analysis.fMin = b.fMin; app.Cfg.analysis.fMax = b.fMax;
                end
                if all(isfinite(b.limits)), lims = b.limits; else, lims = [lim.fLower lim.fUpper]; end
                txt = sprintf('c = %.1f m/s%sASTM E1050/E2611 limits %.0f–%.0f Hz%sanalysis band %g–%g Hz (%s)', ...
                    air.c, dot, lims(1), lims(2), dot, b.fMin, b.fMax, bandSource(b));
                app.H.fLimits.Tooltip = sprintf(['Analysis band: %s. ASTM E1050 / E2611 limits of the tube: microphone ' ...
                    'spacing s from %g to %g of c/s (s at least %g %% of the wavelength, k·s at most %.1fπ) and plane ' ...
                    'waves (0.58·c/D); lines outside them are computed but not valid. analysis.bandMode in the ' ...
                    'configuration: ''geometry'' (the band follows the tube) or ''fixed''.'], b.text, ...
                    app.Cfg.analysis.lowerFraction, app.Cfg.analysis.upperFraction, 100 * app.Cfg.analysis.lowerFraction, ...
                    2 * app.Cfg.analysis.upperFraction);
                if ~known
                    txt = [txt '. L1, d, L2 not entered: specimen results (R, τ, Z_t, TL) disabled.'];
                end
                if ~isempty(msgs), txt = [txt '  CHECK: ' strjoin(msgs, '; ')]; end
                app.H.fLimits.Text = txt;
                if isempty(msgs), app.H.fLimits.FontColor = P.ui.muted; else, app.H.fLimits.FontColor = P.fail; end
                % Tube setup view (not built yet: its first drawing uses the fields of then)
                if app.isBuilt('tube'), app.refreshTube(); end
            catch err
                app.H.fLimits.Text = ['CHECK: ' err.message]; app.H.fLimits.FontColor = P.fail;
            end
            app.refreshCalLabel();
        end

        function refreshTube(app)
            % Tube setup view: note, geometry table and 3D model from the IMPEDANCE TUBE fields
            [geom, env] = app.readTube();
            air = tim.acoustics.airProperties(env);
            lim = tim.acoustics.frequencyLimits(geom.diameter, [geom.spacingUp geom.spacingDown], air);
            known = all(isfinite(geom.micPositions)) && isfinite(geom.xFront) && isfinite(geom.xRear);
            if known
                app.Pages.tube.setNote('');
            else
                app.Pages.tube.setNote(['Schematic: L1, d and L2 are not entered, so the specimen results ' ...
                    '(R, τ, Z_t, TL) are disabled.'], 'warn');
            end
            app.H.tubeInfo.Text = '';
            app.Pages.tube.setSummary(app.geometrySummary(geom, air, lim, known));
            tim.gui.drawTube3D(app.H.axTube3D, geom, app.drawingDims(), app.homeMapping(), ...
                struct('section', app.H.secChk.Value, 'dimensions', app.H.dimChk.Value, ...
                'termination', app.shownTermination()));
        end

        function b = bandOfFields(app)
            % the analysis band for the IMPEDANCE TUBE fields (tim.app.analysisBand;
            % the configuration's geometry while a field is invalid)
            c = app.Cfg;
            [geom, env, msgs] = app.readTube();
            if isempty(msgs), c.geometry = geom; c.environment = env; end
            [~, b] = tim.app.analysisBand(c);
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
                'Analysis band', sprintf('%g–%g Hz (%s)', app.Cfg.analysis.fMin, app.Cfg.analysis.fMax, ...
                    bandSource(app.bandOfFields()))}];
            s = struct('title', 'Geometry', 'columns', {{'Quantity', 'Value'}}, 'data', {rows}, ...
                'note', 'x = 0 at the specimen front face, x increasing towards the termination.');
        end

        function t = fmt(~, v, f)
            if isfinite(v), t = sprintf(f, v); else, t = '–'; end
        end

        function tubeView(app, name)
            app.ensureBuilt('tube');
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
            % the drive of the EXCITATION fields (WO-004, owner decisions
            % 2026-10-12) in a white box below them: (1) the signal path, the
            % generator in Vpp as its display shows it; (2) two meters side by
            % side - the loudspeaker (power at the nominal impedance against the
            % test limit: OK, Near from 80 %, Above) and the generator (its
            % open-circuit voltage against generator.maxVpp and its own range:
            % OK, Above), each a bar with a tick at 80 %, the share and the state;
            % (3) the largest level and the criterion that sets it
            % (tim.app.driveLimits). Also the Vrms of the level field and the
            % expected duration of one measurement.
            P = tim.gui.palette(); h = app.H;
            c = app.fieldsCfg();
            kind = h.exMode.Value;
            gen = app.ampFromUi();                                % programmed generator level [Vpk]
            d = tim.app.driveEstimate(c, 2 * gen, kind);
            L = tim.app.driveLimits(c, kind);
            direct = startsWith(lower(h.ampModel.Value), 'none');
            g = @(v) sprintf('%.3g', v);
            % Vrms of the field: the loudspeaker's, or the generator level's
            if strcmp(h.ampAt.Value, 'loudspeaker'), fv = d.Vspk_pk; else, fv = gen; end
            h.ampRms.Text = sprintf('= %s Vrms', g(fv / d.crest));
            % (1) the path
            if strcmp(d.load, 'INF'), where = 'open circuit'; else, where = sprintf('into %s Ω', d.load); end
            if direct
                l1 = sprintf('Generator %s Vpp %s → speaker %s Vpk', g(2 * gen), where, g(d.Vspk_pk));
            elseif isfinite(d.Vspk_pk)
                l1 = sprintf('Generator %s Vpp %s → ×%s → speaker %s Vpk', g(2 * gen), where, g(d.gain), g(d.Vspk_pk));
            else
                l1 = sprintf('Generator %s Vpp %s → × ? → speaker ?', g(2 * gen), where);
            end
            h.drivePath.Text = l1;
            h.drivePath.Tooltip = sprintf(['The generator''s display shows %s Vpp (load setting %s); open-circuit ' ...
                'voltage %s Vpp.'], g(2 * gen), loadName(d.load), g(d.Voc_pp));
            % (2) the meters: the loudspeaker ...
            rated = '';
            if isfinite(d.rated_W), rated = sprintf(', rated %s', app.siText(d.rated_W, 'W')); end
            if strcmp(d.state, 'unknown')
                tip = 'Loudspeaker: enter the amplifier gain (×) to check it.';
            else
                tip = sprintf(['Loudspeaker: %s Vpk (%s Vrms), %s at the nominal %s Ω = %s %% of the test limit %s%s. ' ...
                    'OK below 80 %%, near the limit from 80 %% (the real impedance can be 20 %% lower), refused above ' ...
                    '100 %%.'], g(d.Vspk_pk), g(d.Vspk_rms), app.siText(d.P_W, 'W'), g(d.Z), g(100 * d.fraction), ...
                    app.siText(d.limit_W, 'W'), rated);
            end
            app.setMeter(h.spkBar, h.spkPct, h.spkState, d.fraction, d.state, tip);
            % ... and the generator: its level against the smallest of its limits
            gen2 = L.criteria(~strcmp({L.criteria.key}, 'speaker'));
            [genMax, k] = min([gen2.maxVpp]);
            fg = 2 * gen / genMax;
            genOver = fg > 1 + 1e-6;
            gs = 'ok'; if genOver, gs = 'over'; end
            app.setMeter(h.genBar, h.genPct, h.genState, fg, gs, sprintf(['Generator: %s Vpp open circuit = %s %% of ' ...
                '%s.'], g(d.Voc_pp), g(100 * fg), gen2(k).text));
            % (3) the maximum and its criterion
            i = find(strcmp({L.criteria.key}, L.binding), 1);
            by = L.criteria(i).text;
            if isfinite(L.maxSpeakerVpk)
                mx = sprintf('%s Vpk at the speaker', g(L.maxSpeakerVpk));
            else
                mx = sprintf('%s Vpk at the amp input', g(L.maxVpp / 2));   % (an amplifier without a gain)
            end
            if L.limitAboveRated
                h.driveMax.Text = sprintf('Test limit %s above the rated %s', app.siText(d.limit_W, 'W'), app.siText(d.rated_W, 'W'));
                h.driveMax.FontColor = P.fail;
            elseif genOver
                h.driveMax.Text = sprintf('Above %s: max %s', by, mx);
                h.driveMax.FontColor = P.fail;
            else
                h.driveMax.Text = sprintf('Max %s, set by %s', mx, by);
                h.driveMax.FontColor = P.ui.muted;
            end
            h.driveMax.Tooltip = strjoin(arrayfun(@(q) sprintf('%s: up to %s Vpk at the loudspeaker (%s Vpp programmed)', ...
                q.text, g(q.maxSpeakerVpk), g(q.maxVpp)), L.criteria, 'UniformOutput', false), newline);
            app.DriveCheck = struct('state', d.state, 'binding', L.binding, 'generatorOver', genOver, ...
                'generatorFraction', fg, 'limitAboveRated', L.limitAboveRated, 'maxSpeakerVpk', L.maxSpeakerVpk, ...
                'genVpk', gen, 'drive', d);
            h.durEst.Text = sprintf('about %s', app.durationText(app.expectedDuration()));
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
            % GUI in Vpk (of the loudspeaker, or the generator's level: open
            % circuit / amplifier input), config / generator in Vpp of the generator
            gen = app.ampFromUi();
            app.Cfg.excitation.sweep.amplitudeVpp = 2 * gen;
            app.Cfg.excitation.stepped.amplitudeVpp = 2 * gen;
            app.Cfg.excitation.noise.amplitudeVpp = 2 * gen;
            app.Cfg.ui.amplitudeAt = h.ampAt.Value;
            % the amplifier input and the generator load it sets (the load is fixed while connected)
            [ld, zin] = app.loadFromUi();
            if isempty(app.Session), app.Cfg.generator.load = ld; end
            if ~startsWith(lower(h.ampModel.Value), 'none'), app.Cfg.amplifier.inputImpedance_ohm = zin; end
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
            app.Cfg = tim.app.analysisBand(app.Cfg);      % bandMode 'geometry': the band of these fields
            % connected: the limits of the drivers are errors (the fields stay as
            % they were); otherwise warnings, so that an older file can be saved again
            scope = '';
            if ~isempty(app.Session) && isvalid(app.Session), scope = 'instruments'; end
            rep = tim.app.validateConfig(app.Cfg, scope);
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
            if app.LinkChecking
                % (only from a click that interrupted the idle connection check: never
                % send instrument commands between its query and its answer)
                what = busyWhat; if isempty(what), what = 'action'; end
                app.log('Checking the instrument connections - the %s was not started; try again in a moment.', what);
                return
            end
            if ~isempty(app.Constructing)
                % (only from a timer that interrupted the creation of a view: never
                % start an action on half-created controls)
                app.log('The %s view is being prepared - %s not started; try again in a moment.', ...
                    app.partLabel(app.Constructing), busyWhat);
                return
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
                    off = app.outputOffText(); app.log('%s', off);     % the read-back, not only the command
                    msg = sprintf('%s cancelled: the loudspeaker was not driven. %s', app.capital(what), off);
                    icon = 'info'; ttl = sprintf('%s cancelled', app.capital(what));
                elseif any(strcmp(err.identifier, {'tim:session:stopped', 'tim:gui:abort'}))
                    app.log('%s stopped by the operator: %s', app.capital(what), err.message);
                    off = app.outputOffText(); app.log('%s', off);
                    msg = sprintf('%s stopped by the operator. %s', app.capital(what), off);
                    icon = 'info'; ttl = sprintf('%s stopped', app.capital(what));
                elseif startsWith(err.identifier, {'tim:gui:input', 'tim:gui:geometry', 'tim:config:'})
                    app.log('Warning: %s', err.message);
                    msg = err.message; icon = 'warning'; ttl = 'Check the settings';
                elseif strcmp(err.identifier, 'tim:gui:open')
                    app.log('Open measurement: %s', err.message);
                    msg = err.message; icon = 'warning'; ttl = 'Open measurement';
                else
                    app.log('Error (%s): %s', what, err.message);
                    if any(strcmp(err.identifier, {'tim:instr:connectionLost', 'tim:scpi:connectionLost'}))
                        app.stopLinkCheck();         % no idle re-open attempts until the next Connect
                    end
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
            % output state read back from the source (isOutputOn, 1 s time-out),
            % worded by the driver's read-back kind: never claim "OFF" without
            % confirmation (docs/instrument_interface.md section 3.2)
            s = app.Session;
            if isempty(s) || isempty(s.Gen)
                txt = 'Generator not connected.'; app.OutputUnconfirmed = false; return
            end
            kind = 'instrument';
            try, kind = s.driverInfo('source').capabilities.source.readback; catch, end
            unconfirmed = false;
            try
                if s.Gen.isOutputOn(1)
                    txt = 'The generator output could not be switched off. Switch it off at the generator.';
                    unconfirmed = true;
                elseif strcmp(kind, 'device')
                    txt = 'Generator output stopped (device idle, 0 V).';
                elseif strcmp(kind, 'none')
                    txt = 'Generator output switched off - this generator cannot report its state; check it at the instrument.';
                else
                    txt = 'Generator output off (confirmed).';
                end
            catch err
                if any(strcmp(err.identifier, {'tim:scpi:connectionLost', 'tim:instr:connectionLost', 'tim:scpi:closed'})) ...
                        || strcmp(s.LostRole, 'source')       % the connection check found it lost
                    txt = ['The connection to the generator is lost, so its output state cannot be read back. ' ...
                        'Check the output at the generator, then Disconnect and Connect.'];
                else
                    txt = 'The generator output could not be confirmed off. Check the output at the generator.';
                end
                unconfirmed = true;
            end
            app.OutputUnconfirmed = unconfirmed;
        end

        function setBusy(app, tf, what)
            % Lock / unlock the control panel and the menus (the tabs stay usable).
            if isempty(app.Fig) || ~isvalid(app.Fig)
                app.Busy = false; return            % window closed during the action
            end
            h = app.H; P = tim.gui.palette();
            ctl = [app.inputControls(), {h.connect, h.disconnect, h.start, h.background, h.loadCal, h.runCal, ...
                h.save, h.reprocess, h.mOpenMeas, h.mCombine, h.mLoadCfg, h.mSaveCfg}, num2cell(h.mHelp)];
            if tf
                app.Busy = true; app.BusyWhat = what;
                for i = 1:numel(ctl), ctl{i}.Enable = 'off'; end
                if app.isBuilt('twoload'), h.twShow.Enable = 'off'; end
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
                app.Busy = false; app.BusyWhat = '';
                for i = 1:numel(ctl), ctl{i}.Enable = 'on'; end
                if app.isBuilt('tube'), app.termLayout(); end   % the place of an absorber stays fixed
                if app.isBuilt('twoload')
                    h.twShow.Enable = matlab.lang.OnOffSwitchState(numel(app.LastLoads) > 1);
                end
                h.lamp(1).Tooltip = app.LampTips{1};     % display name and identity (refreshInstruments)
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
            c = {h.mode, h.exMode, h.fStart, h.fStop, h.dur, h.amp, h.reps, h.ampModel, h.ampGain, h.genLoad, ...
                h.spkZ, h.spkP, h.ampAt, h.tubeD, h.s1, h.L1, h.dTh, h.L2, h.s2, h.temp, h.pres, h.specimen, h.method};
            if app.isBuilt('tube')
                c = [c, {h.secChk, h.dimChk}];   % 3D redraw (~1 s) would stall the data stream
                % the terminations (termLayout sets them again after an action: the
                % place of an absorber stays fixed)
                c = [c, {h.termKindA, h.termPlaceA, h.termKindB, h.termPlaceB, h.termRepeat, h.termLevelB, h.termShow}];
            end
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
            app.chainEnable();
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
            % (the actions prepare the Time signals view before the data stream starts;
            % it is never built here, inside the stream)
            if toc(lastT) < 0.2 || ~app.isBuilt('wave'), drawnow('limitrate'); return; end
            lastT = tic;
            try
                daq = app.Session.Daq;
                fs = daq.SampleRate; n = round(0.5 * fs);
                [x, nTotal] = daq.recent(n);                            % no I/O
                if isempty(x), drawnow('limitrate'); return; end
                x = [nan(n - size(x, 1), size(x, 2)); x];               % fewer samples yet: aligned at the end
                x = x - mean(x, 1, 'omitnan');                          % volts, slow drift removed
                t = ((1:n) - n) / fs;                                   % seconds before "now"
                total = nTotal / fs;
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
            app.ensureBuilt('wave');
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
            app.LastMeas = []; app.LastRes = []; app.LastCfg = []; app.Saved = true; app.Opened = false;
            app.ReprocessMics = [];
            app.refreshFromCfg();
            app.refreshViews();
            app.setResultStatus();
            app.log('Loaded configuration %s', file);
        end

        function onOpenMeasurement(app)
            % File > Open measurement…: select raw.mat (or result.mat) in a folder
            % written by Save measurement
            if app.Busy || ~app.confirmDiscard('Open a measurement'), return; end
            c = app.Cfg; if isempty(app.Session), c.mode = app.H.mode.Value; end   % data\ or data\simulation\
            start = tim.app.outputDir(c, 'data');
            if ~isempty(app.SavedDir) && isfolder(fileparts(app.SavedDir)), start = fileparts(app.SavedDir); end
            if ~isfolder(start), start = tim.app.projectRoot(); end
            [f, p] = uigetfile({'raw.mat;result.mat;twoload.json', ...
                'Saved measurement or two-load result (raw.mat, result.mat, twoload.json)'}, ...
                'Open measurement – select raw.mat in a measurement folder (or a file of a two-load folder)', [start filesep]);
            figure(app.Fig);
            if isequal(f, 0), return; end
            app.openMeasurement(p);
        end
        function doOpenMeasurement(app, folder, useSavedTube, useRecordedMapping)
            folder = char(folder);
            if isfile(folder), folder = fileparts(folder); end       % raw.mat / result.mat given
            if endsWith(folder, filesep), folder = folder(1:end - 1); end
            if isfile(fullfile(folder, 'twoload.json'))
                app.doOpenTwoLoad(folder); return                     % a two-load pair folder (WO-005)
            end
            f = fullfile(folder, 'raw.mat');
            if ~isfile(f)
                error('tim:gui:open', 'No raw.mat in %s.\nSelect raw.mat in a folder written by Save measurement.', folder);
            end
            ws = [warning('off', 'MATLAB:load:variableNotFound'), warning('off', 'tim:config:unknownField')];
            wsEnd = onCleanup(@() warning(ws));      % older files: missing variables, renamed config fields
            S = load(f, 'meas');
            if ~isfield(S, 'meas') || ~isstruct(S.meas) || ~all(isfield(S.meas, {'kind', 'records', 'fs', 'timestamp', 'metadata'}))
                error('tim:gui:open', '%s does not hold a measurement of this program (variable "meas").', f);
            end
            res = [];
            if isfile(fullfile(folder, 'result.mat'))
                R = load(fullfile(folder, 'result.mat'), 'res');
                if isfield(R, 'res'), res = R.res; end
            end
            saved = [];                  % configuration at the save = set-up of the saved results
            if isfile(fullfile(folder, 'config.json'))
                try, saved = tim.app.loadConfig(fullfile(folder, 'config.json')); catch, end
            end
            m = S.meas; md = m.metadata;
            app.LastMeas = m; app.LastRes = res;
            app.LastLoads = []; app.LastTM = [];
            if isstruct(res) && isfield(res, 'transferMatrix'), app.LastTM = res.transferMatrix; end   % one load, symmetric
            app.LastCfg = saved;         % the set-up of the saved results (Save writes it again)
            app.Saved = true; app.SavedDir = folder; app.Opened = true;
            app.ReprocessMics = [];      % the configuration's mapping unless chosen below
            app.refreshViews();
            app.setResultStatus();
            [~, nm] = fileparts(folder);
            sp = '';
            if isfield(md, 'specimen') && ~strcmp(md.specimen, 'unnamed specimen'), sp = sprintf(', specimen "%s"', md.specimen); end
            if (isfield(md, 'mode') && strcmp(md.mode, 'simulation')) || isfield(md, 'WARNING'), sp = [sp ', SIMULATED DATA']; end
            app.log('Opened %s: %s of %s%s.', nm, app.signalName(m.kind), m.timestamp, sp);
            if ~isempty(res) && isfield(res, 'summary')
                app.log('Saved results (calibration %s): %s', res.calibration.version, res.summary);
            elseif ~strcmp(m.kind, 'background')
                app.log('No results were saved with it - press Reprocess to compute them.');
            end
            app.testPoint('open:beforeQuestions');      % (tests: a close request before the questions)
            % tube set-up of the saved results vs. the IMPEDANCE TUBE fields
            if ~isempty(saved)
                [g, e, msgs] = app.readTube();
                if ~isempty(msgs) || ~sameTube(g, e, saved.geometry, saved.environment)
                    txt = tubeText(saved.geometry, saved.environment);
                    use = useSavedTube;
                    if ~islogical(use)
                        sel = app.ask(sprintf(['The saved results were computed with this tube set-up:\n%s\n\n' ...
                            'The IMPEDANCE TUBE fields show another set-up. Put the saved set-up into the ' ...
                            'fields? (Reprocess uses the fields.)'], txt), 'Open measurement', ...
                            {'Use the saved set-up', 'Keep the current fields'}, 1, 2, 'question');
                        use = strcmp(sel, 'Use the saved set-up');
                    end
                    if use
                        app.tubeToUi(saved.geometry, saved.environment);
                        app.onTubeChanged();
                        app.log('IMPEDANCE TUBE fields set to the saved set-up: %s.', txt);
                    else
                        app.log('IMPEDANCE TUBE fields kept; the saved results used %s.', txt);
                    end
                end
            end
            % microphone mapping (DAQ channel -> port) the data were recorded with
            % vs the configuration's (owner decision 2026-10-11): asked like the
            % tube set-up; the recorded one is the default answer (also when the
            % dialog is dismissed). The configuration's stays available to correct
            % a mapping that was recorded wrongly - processMeasurement then reports
            % the difference.
            how = '';
            [rec, mp] = recordedMapping(app.Cfg, m, saved);
            % the mapping the saved results were computed with (config.json of the
            % folder; owner decision 2026-10-13, WO-003 4.3): a folder saved after a
            % deliberate correction holds the corrected one there
            sv = savedMapping(app.Cfg, saved, res);
            if ~strcmp(m.kind, 'background') && ~isempty(rec) && mp.differs
                svText = '';
                if ~isempty(sv)
                    whose = '';
                    if strcmp(sv, mp.recordedText), whose = ' (the recorded one)';
                    elseif strcmp(sv, mp.configuredText), whose = ' (the configuration''s)'; end
                    svText = sprintf('\n\nThe saved results were computed with:\n%s%s', sv, whose);
                    app.log('The saved results were computed with the microphone mapping %s%s.', sv, whose);
                end
                use = useRecordedMapping;
                if ~islogical(use)
                    sel = app.ask(sprintf(['This measurement was recorded with this microphone mapping (DAQ ' ...
                        'channel → port):\n%s\n\nThe configuration has another one:\n%s%s\n\nReprocess with the ' ...
                        'recorded mapping? Keep the configuration''s mapping only to correct a mapping that was ' ...
                        'recorded wrongly.'], mp.recordedText, mp.configuredText, svText), 'Open measurement', ...
                        {'Use the recorded mapping', 'Keep the configuration''s mapping'}, 1, 1, 'question');
                    use = strcmp(sel, 'Use the recorded mapping');
                end
                if use
                    app.ReprocessMics = rec;
                    how = ' and the microphone mapping the measurement was recorded with';
                    app.log('Microphone mapping for Reprocess: the recorded one (%s); the configuration has %s.', ...
                        mp.recordedText, mp.configuredText);
                else
                    how = ' and the configuration''s microphone mapping';
                    app.log('Microphone mapping of the configuration kept for Reprocess (%s); the measurement was recorded with %s.', ...
                        mp.configuredText, mp.recordedText);
                end
            elseif ~strcmp(m.kind, 'background') && ~isempty(rec) && ~isempty(sv) && ~strcmp(sv, mp.configuredText)
                % no question (recorded = configured), but the saved results used another
                app.log(['The saved results were computed with another microphone mapping (%s) than Reprocess will ' ...
                    'use (%s, as recorded and configured).'], sv, mp.configuredText);
            end
            [cal, ~] = app.currentCalibration();
            cv = 'none - results not valid'; if ~isempty(cal), cv = cal.version; end
            if ~strcmp(m.kind, 'background')
                app.log('Reprocess uses the IMPEDANCE TUBE fields and the active calibration (%s)%s.', cv, how);
            end
        end

        function onConnect(app)
            app.run(@() app.doConnect(), 'connection');   % locked: no second Connect / START meanwhile
        end
        function onDisconnect(app)
            if isempty(app.Session), return; end
            closed = app.closedText();                 % from the drivers, e.g. 'generator output off, ...'
            app.disconnect();
            app.log('Instruments disconnected by the operator (%s).', closed);
        end
        function doConnect(app)
            app.Cfg.mode = app.H.mode.Value;
            app.readCfgFromUi();                       % invalid fields: 'Check the settings', no connection
            app.disconnect(true);
            app.setStatus(sprintf('Connecting (%s)…', app.Cfg.mode), 'busy');
            % connection checklist: every step is shown while it runs (the
            % animated icon keeps turning during a slow input setup)
            keys = app.connKeys();                     % the steps of the configured drivers
            if ~isequal(keys, app.ConnList.Keys), app.ConnList.rebuild(keys, app.connLabels()); end
            app.ConnList.reset();
            app.showTab(app.H.connTab);
            app.H.connHead.Text = sprintf('Connecting (%s mode)…', app.Cfg.mode);
            app.H.connHead.FontColor = [0.1 0.1 0.1];
            app.refreshCards();
            app.testPoint('connect:beforeSession');    % (tests: a Stop / close here finds no session yet)
            try
                s = tim.app.MeasurementSession(app.Cfg);
            catch err
                % refused before any instrument was contacted (driver limits, an
                % unknown driver, a missing calibration file): no step ran
                app.H.connHead.Text = sprintf('Connection refused: %s', strjoin(splitlines(string(err.message)), ' '));
                app.H.connHead.FontColor = tim.gui.palette().fail;
                rethrow(err);
            end
            s.StatusCallback = @(line) app.appendLog(line);
            s.BlockCallback = @() app.liveUpdate();       % live time signals + keeps STOP responsive
            s.ProgressCallback = @(key, state, detail) app.onProgress(key, state, detail);
            L = app.Cfg.ui.language; yes = tim.app.msg(L, 'yesPlay');
            if strcmp(app.Cfg.mode, 'hardware')       % no real loudspeaker in simulation
                s.ExcitationConfirm = @(msg) strcmp(app.confirmExcitation(msg, yes, tim.app.msg(L, 'cancel'), ...
                    tim.app.msg(L, 'confirmTitle')), yes);
            end
            app.Session = s;
            s.beginOperation();                        % Stop during the connection stays pending
            opEnd = onCleanup(@() endOp(s));
            if app.PendingStop, s.requestStop(); end    % Stop pressed before the session existed
            try
                s.connect();
                app.refreshInstruments();              % the identity the instruments reported
                s.prepareAcquisition();
                chk = s.signalCheck(1);                % 1 s without excitation: level / fault flags per channel
            catch err
                % failed or stopped: no half-open session (Connect and the mode selector stay usable)
                try, s.close(true); catch, end
                app.Session = [];
                try, app.refreshInstruments(); catch, end
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
            app.startLinkCheck();                % hardware: the connections checked every minute while idle
        end

        function onProgress(app, key, state, detail)
            % a connection step started / ended (MeasurementSession.ProgressCallback).
            % The lamp of a role follows the steps of that role's driver (a step
            % of a combined device drives both lamps); the channel cards are
            % refreshed when a step of the input setup ends (TEDS).
            app.ConnList.set(key, state, detail);
            col = app.stateColor(state);
            steps = app.driverSteps();
            i = find(strcmp({steps.key}, key), 1);
            if ~isempty(i)
                role = steps(i).role;
                lamps = [any(strcmp(role, {'source', 'both'})), any(strcmp(role, {'acquisition', 'both'}))];
                set(app.H.lamp(lamps), 'Color', col);
                if strcmp(steps(i).phase, 'prepare') && ~strcmp(state, 'run'), app.refreshCards(); end
            end
            if strcmp(state, 'fail')
                k = find(strcmp(app.ConnList.Keys, key), 1);
                lbl = key; if ~isempty(k), lbl = app.ConnList.Labels(k).Text; end
                app.H.connHead.Text = sprintf('Connection FAILED at "%s" - %s', lbl, detail);
                app.H.connHead.FontColor = tim.gui.palette().fail;
                if isempty(i), app.H.lamp(2).Color = col; end   % a session step: the inputs
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
                    % no TEDS read (a device without TEDS, or detection off): the
                    % channel is connected once the inputs are set up
                    if ~isempty(app.Session) && app.Session.Prepared, st = 'ok'; end
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
            if strcmp(app.H.method.Value, 'twoLoad')
                app.run(@() app.doTwoLoad(), 'measurement');      % A -> B (-> A'), WO-005
            else
                app.run(@() app.doStart(), 'measurement');
            end
        end
        function doStart(app)
            app.readCfgFromUi();
            app.requireGain();
            app.syncSession();
            app.log('Start: %s measurement of "%s" (started by the operator).', ...
                app.signalName(app.Cfg.excitation.mode), app.specimenName());
            app.ensureBuilt('wave');                     % live view: prepared BEFORE the data stream
            app.showTab(app.H.waveTab);
            app.prepareLive();
            app.Session.setTermination(app.Cfg.measurement.loadA);   % recorded with the data (Tube setup, WO-005)
            m = app.Session.measure(app.Cfg.excitation.mode);
            app.LastLoads = []; app.LastTM = [];         % one measurement: no transfer matrix of earlier loads
            app.LastMeas = m; app.LastRes = []; app.LastCfg = app.Cfg; app.Saved = false; app.SavedDir = ''; app.Opened = false;
            app.ReprocessMics = [];                      % a new measurement: the configuration's mapping
            app.LastMeas.metadata.specimen = app.specimenName();   % name at Start (folder + metadata)
            app.setResultStatus();                       % 'not saved' also when the processing fails
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
                % commanded, not read back here: the stopped action logs the read-back
                app.log('Stop requested by the operator: generator output commanded off.');
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
            app.ensureBuilt({'wave', 'spec'});          % live view + result view, BEFORE the data stream
            app.showTab(app.H.waveTab);
            app.prepareLive();
            m = app.Session.measureBackground(2);
            app.LastMeas = m; app.LastRes = []; app.LastCfg = app.Cfg; app.Saved = false; app.SavedDir = ''; app.Opened = false;
            app.ReprocessMics = [];                      % a new measurement: the configuration's mapping
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
            s.setAmplitudeAt(app.Cfg.ui.amplitudeAt);
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
            % direct drive -> gain fixed to x1 and the generator load High Z; a
            % typed model is added to the list; choosing an amplifier asks for its
            % gain (power check) and offers its input impedance, which also sets
            % the generator load (WO-004). The programmed generator level stays.
            h = app.H; P = tim.gui.palette();
            gen0 = app.programmedVpk();                       % before the change
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
            if isempty(app.Session)
                % the list follows the amplifier: High Z in direct drive, the
                % amplifier's input impedance (kept from before) with an amplifier
                app.Cfg.amplifier.model = v;
                if direct, app.Cfg.generator.load = 'INF'; end
                app.loadsToUi();
                if ~direct, [app.Cfg.generator.load, app.Cfg.amplifier.inputImpedance_ohm] = app.loadFromUi(); end
                if changed && direct, app.log('Generator load: High Z for direct drive.'); end
            end
            app.ampAtItems();
            if strcmp(h.ampAt.Value, 'loudspeaker') && ~app.GainEntered
                % the loudspeaker voltage needs the gain: the same generator level,
                % now shown at the amplifier input
                h.ampAt.Value = 'generator'; app.Cfg.ui.amplitudeAt = 'generator';
                if changed, app.log('Level: at the amplifier input until its gain is entered.'); end
            end
            app.ampToUi(gen0);
            if app.GainEntered, h.ampGain.BackgroundColor = 'w'; else, h.ampGain.BackgroundColor = P.ui.attention; end
            app.chainEnable();
            if changed && ~direct && ~app.GainEntered
                app.log('Amplifier "%s" selected. Enter its voltage gain (Amplifier gain, ×) and its input impedance (Amp input).', v);
            end
            app.updateDrive();
        end

        function v = programmedVpk(app)
            % the programmed generator level of the fields [Vpk] as the last
            % drive check computed it (before a change of the chain), else now
            v = NaN;
            if isfield(app.DriveCheck, 'genVpk'), v = app.DriveCheck.genVpk; end
            if ~isfinite(v), v = app.H.amp.Value; end
        end

        function chainEnable(app)
            % amplifier gain, amplifier input / generator load and the level
            % reference follow the amplifier and the connection (all locked while
            % an action runs); the level at the loudspeaker needs the gain. The
            % amplifier is fixed while connected like its input (owner decision
            % 2026-10-30): another amplifier may need another generator load,
            % which is sent only at Connect.
            h = app.H;
            onoff = @(tf) matlab.lang.OnOffSwitchState(tf);
            direct = startsWith(lower(h.ampModel.Value), 'none');
            free = ~app.Busy;
            h.ampModel.Enable = onoff(isempty(app.Session) && free);
            if ~isempty(app.Session)
                h.ampModel.Tooltip = ['Fixed while connected - Disconnect to change the amplifier: its input impedance ' ...
                    'is the generator''s load setting, sent at Connect. The gain can be changed while connected.'];
            else
                h.ampModel.Tooltip = ['Select an entry, or type the model of your power amplifier and press Enter: it ' ...
                    'is added to the list and saved with the configuration (File > Save configuration).'];
            end
            h.ampGain.Enable = onoff(~direct && free);
            h.ampAt.Enable = onoff(free && (direct || app.GainEntered));
            h.genLoad.Enable = onoff(~direct && isempty(app.Session) && free);
            if direct
                h.genLoadLabel.Text = 'Generator load';
                h.genLoadLabel.Tooltip = 'Output load setting of the generator in direct drive: High Z (owner decision 2026-10-12).';
            else
                h.genLoadLabel.Text = 'Amp input [Ω]';
                h.genLoadLabel.Tooltip = 'Input impedance of the amplifier (data sheet); also the generator''s load setting.';
            end
            if ~isempty(app.Session)
                h.genLoad.Tooltip = sprintf(['Output load setting of the generator, sent to it at Connect: %s. Fixed while ' ...
                    'connected - Disconnect to change it.'], loadText(app.Cfg));
            elseif direct
                h.genLoad.Tooltip = ['Direct drive: High Z - the programmed level is the open-circuit voltage; the ' ...
                    'loudspeaker gets it through the generator''s source impedance.'];
            else
                h.genLoad.Tooltip = ['Input impedance of the amplifier in ohm, from its data sheet (e.g. 50, 600, 10000), ' ...
                    'or High Z. The generator''s load setting is set to it at the next Connect, so the programmed level ' ...
                    'is the voltage at the amplifier input (High Z or above 10 kΩ: the open-circuit voltage). The ' ...
                    'source impedance of the generator does not change.'];
            end
            if direct
                h.ampAt.Tooltip = sprintf(['Speaker [Vpk]: the voltage at the loudspeaker; the generator is set to it ' ...
                    'through its %g Ω source impedance and the nominal loudspeaker impedance (the real impedance varies ' ...
                    'with frequency). Generator [Vpk]: the programmed level (open-circuit voltage).'], app.sourceImpedance());
            else
                h.ampAt.Tooltip = ['Speaker [Vpk]: the voltage at the loudspeaker, from the amplifier gain (needs the gain). ' ...
                    'Amp input [Vpk]: the programmed level, the voltage at the amplifier input.'];
            end
        end

        function g = gainValue(app)
            % amplifier gain of the field; 0 in the field = not entered -> NaN
            g = app.H.ampGain.Value; if ~(g > 0), g = NaN; end
        end

        function onGainChanged(app)
            % the gain changed: a level at the loudspeaker stays (the generator
            % follows); without a gain the level is shown at the amplifier input;
            % when the gain is first entered the level is shown at the loudspeaker
            % (the default with a known gain, WO-004)
            h = app.H;
            gen0 = app.programmedVpk();
            was = app.GainEntered;
            app.GainEntered = h.ampGain.Value > 0;               % 0 = not entered
            if app.GainEntered, h.ampGain.BackgroundColor = 'w'; else, h.ampGain.BackgroundColor = tim.gui.palette().ui.attention; end
            direct = startsWith(lower(h.ampModel.Value), 'none');
            if strcmp(h.ampAt.Value, 'loudspeaker') && ~app.GainEntered
                h.ampAt.Value = 'generator'; app.Cfg.ui.amplitudeAt = 'generator';
                app.ampToUi(gen0);
            elseif strcmp(h.ampAt.Value, 'loudspeaker')
                app.ampToUi(h.amp.Value / app.speakerFactor());
            elseif ~direct && app.GainEntered && ~was
                h.ampAt.Value = 'loudspeaker'; app.Cfg.ui.amplitudeAt = 'loudspeaker';
                app.ampToUi(gen0);
                app.log('Level: at the loudspeaker (gain ×%.4g).', h.ampGain.Value);
            end
            app.chainEnable();
            app.updateDrive();
        end

        function buildCalSteps(app)
            % operator steps of the calibration (same order as tim.app.runCalibration):
            % shown as "pending" before the calibration starts (Calibration view not
            % built yet: its first drawing calls this)
            if ~app.isBuilt('cal'), return; end
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
            % Calibration view (bar, 3D model, step list) and the live time signals
            % BEFORE the first step / data stream (the model is drawn at the first step)
            app.ensureBuilt({'cal', 'wave'});
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
            app.ensureBuilt('cal');                % (prepared by doRunCal before the first step)
            app.CalStep = app.CalStep + 1;
            key = app.CalKeys{min(app.CalStep, end)};
            stepText = tim.app.msg(app.Cfg.ui.language, 'calStepHeader', app.CalStep, app.CalSteps);
            from = app.CalMap;
            app.drawCalSetup(mapping, msg, stepText, from);
            app.showTab(app.H.calTab);
            app.CalList.set(key, 'run', 'operator: place the microphones as shown');
            app.animateCalMics(from, mapping);
            app.CalMap = mapping;
            hw = strcmp(app.Session.Cfg.mode, 'hardware');      % the session's mode, never the selector
            if hw || app.PromptInSimulation
                % the question is in the bar above the model (no modal dialog: the
                % window is not dimmed and the model with the moves stays visible)
                L = app.Cfg.ui.language;
                if any(strcmp(key, {'prep', 'mount'})) || (strcmp(key, 'done') && ~strcmp(msg, tim.app.msg(L, 'calDone')))
                    done = tim.app.msg(L, 'calContinueButton');   % nothing is measured after this step
                else
                    done = tim.app.msg(L, 'calDoneButton');
                end
                app.startPulse();
                sel = app.askBar('', {done, tim.app.msg(L, 'abortButton')}, 1, 2);
                app.stopPulse();
                if ~strcmp(sel, done)
                    app.CalList.set(key, 'fail', 'cancelled by the operator');
                    error('tim:gui:abort', 'Calibration cancelled by the operator.');
                end
            end
            if ~hw, app.Session.setMicPositionsForSimulation(mapping); end
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
            app.ensureBuilt('cal');
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
            if ~app.isBuilt('cal'), return; end   % (set when the Calibration view is built)
            ab = app.Cfg.calibration.positions;
            % (HTML label: step in bold, the explanation of the drawing small and grey)
            note = @(s) ['<br><span style="color:#5f6368;font-size:11px">' htmlText(s) '</span>'];
            if isempty(mapping)
                app.H.calText.Text = [htmlText(sprintf(['Press "Run switching calibration…": every step shows here which ' ...
                    'microphone goes into which port. Calibration ports M%d (a) and M%d (b) glow yellow.'], ab(1), ab(2))), ...
                    note(['The empty specimen section (no specimen) is mounted and the tube ends in the absorbing termination. ' ...
                    'Each microphone stays on its own cable and input channel; only the microphone bodies are moved.'])];
            else
                app.H.calText.Text = ['<b>' htmlText(stepText) ':</b>&nbsp; ' htmlText(msg), ...
                    note(['Yellow: calibration ports a, b  ' char(183) '  colour / label: channel of the microphone ' ...
                    '(keeps its cable)  ' char(183) '  dashed: last moves'])];
            end
            app.fitCalBar();
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

        %% ------------------------------------------- method and terminations (WO-005)
        function onMethodChanged(app)
            % MEASUREMENT > Method: the Start button, the termination box (one row or
            % loads A and B); choosing two loads opens Setup > Tube setup, where the
            % loads are chosen
            app.Cfg.measurement.method = app.H.method.Value;
            app.updateStartText();
            if app.isBuilt('tube'), app.termLayout(); app.refreshTube(); end
            if strcmp(app.H.method.Value, 'twoLoad') && ~app.Busy
                if strcmp(app.Fig.Visible, 'on'), app.showTab(app.H.tubeTab); end
                ms = app.Cfg.measurement;
                app.log('Two loads: load A "%s", load B "%s" - choose them in Setup > Tube setup (Termination).', ...
                    tim.app.describeLoad(ms.loadA).label, tim.app.describeLoad(ms.loadB).label);
            end
        end

        function updateStartText(app)
            if strcmp(app.Cfg.measurement.method, 'twoLoad')
                app.H.start.Text = 'Start two-load measurement';
                app.H.start.Tooltip = ['Measure the specimen with load A, load B and (Repeat) load A again; every load ' ...
                    'is saved at once, then the transfer matrix (hardware mode: asks before the loudspeaker is driven).'];
            else
                app.H.start.Text = 'Start measurement';
                app.H.start.Tooltip = ['Measure the specimen with the selected signal (hardware mode: asks before the ' ...
                    'loudspeaker is driven).'];
            end
        end

        function termToUi(app)
            % the termination box of Setup > Tube setup from app.Cfg.measurement
            if ~app.isBuilt('tube'), return; end
            h = app.H; ms = app.Cfg.measurement;
            h.termKindA.Value = char(ms.loadA.kind); h.termPlaceA.Value = char(ms.loadA.place);
            h.termKindB.Value = char(ms.loadB.kind); h.termPlaceB.Value = char(ms.loadB.place);
            h.termRepeat.Value = logical(ms.repeatLoadA);
            lv = double(ms.loadBLevel_dB);
            if ~any(cellfun(@(v) isequal(v, lv), h.termLevelB.ItemsData))     % a value set in the file
                h.termLevelB.Items{end + 1} = sprintf('%s%g dB', char(8722), abs(lv));
                h.termLevelB.ItemsData{end + 1} = lv;
            end
            h.termLevelB.Value = lv;
            app.termLayout();
        end

        function onTermChanged(app)
            % a termination field changed: the configuration, the box and the model
            h = app.H; ms = app.Cfg.measurement;
            for k = 'AB'
                kd = h.(['termKind' k]).Value; pl = h.(['termPlace' k]).Value;
                if strcmp(kd, 'absorber'), pl = 'tubeEnd'; h.(['termPlace' k]).Value = pl; end   % only at the tube end
                ms.(['load' k]) = struct('kind', kd, 'place', pl);
            end
            ms.repeatLoadA = h.termRepeat.Value;
            ms.loadBLevel_dB = h.termLevelB.Value;
            app.Cfg.measurement = ms;
            app.termLayout();
            app.refreshTube();
            if app.isBuilt('twoload') && app.TwStep == 0, app.buildTwSteps(); end
        end

        function termLayout(app)
            % one load: one row "Termination"; two loads: load A, load B, the
            % repeat and the level of B. The place of an absorber is fixed (tube end).
            if ~app.isBuilt('tube'), return; end
            h = app.H; ms = app.Cfg.measurement; P = tim.gui.palette();
            two = strcmp(ms.method, 'twoLoad');
            if two
                h.termLabelA.Text = 'Load A'; h.termGrid.RowHeight = {24, 24, 22, '1x'};
                app.Pages.tube.SummaryPanel.RowHeight{1} = 176;
            else
                h.termLabelA.Text = 'Termination'; h.termGrid.RowHeight = {24, 0, 0, '1x'};
                app.Pages.tube.SummaryPanel.RowHeight{1} = 118;
            end
            onoff = @(tf) matlab.lang.OnOffSwitchState(tf);
            set([h.termLabelB, h.termKindB, h.termPlaceB, h.termRepeat, h.termLevelB], 'Visible', onoff(two));
            free = ~app.Busy;
            h.termKindA.Enable = onoff(free); h.termKindB.Enable = onoff(free);
            h.termPlaceA.Enable = onoff(free && ~strcmp(ms.loadA.kind, 'absorber'));
            h.termPlaceB.Enable = onoff(free && ~strcmp(ms.loadB.kind, 'absorber'));
            h.termRepeat.Enable = onoff(free); h.termLevelB.Enable = onoff(free);
            h.termShow.Enable = onoff(two && free); h.termShowLabel.Enable = onoff(two);
            if ~two, h.termShow.Value = 'A'; end
            % what is mounted and where (English, as every window text)
            dA = tim.app.describeLoad(ms.loadA, app.Cfg); dB = tim.app.describeLoad(ms.loadB, app.Cfg);
            mt = @(d) tim.app.msg('en', ['tlMount_' d.kind '_' d.place], distText(d.distance_m));
            col = P.ui.muted;
            if ~two
                txt = [capital1(mt(dA)) '.'];
            elseif strcmp(dA.tag, dB.tag)
                txt = sprintf('Load A and load B are both "%s": choose two different terminations.', dA.label);
                col = P.fail;
            else
                txt = sprintf('A: %s.\nB: %s.', mt(dA), mt(dB));
                if ms.loadBLevel_dB < 0
                    txt = sprintf('%s\nLoad B at %s%g dB of the level of load A.', txt, char(8722), abs(ms.loadBLevel_dB));
                end
            end
            h.termText.Text = txt; h.termText.FontColor = col;
        end

        function d = shownTermination(app)
            % the load the Tube setup model shows: one load - its termination;
            % two loads - load A or B (Show)
            ms = app.Cfg.measurement; d = ms.loadA;
            if strcmp(ms.method, 'twoLoad') && app.isBuilt('tube') && strcmp(app.H.termShow.Value, 'B'), d = ms.loadB; end
        end

        function k = prefKey(app)
            % the remembered loads belong to the configuration file (the lab and the
            % virtual tube do not overwrite each other)
            f = ''; if isfield(app.Cfg, 'configFile') && ~isempty(app.Cfg.configFile), f = app.Cfg.configFile; end
            [~, n] = fileparts(char(f)); if isempty(n), n = 'default'; end
            k = matlab.lang.makeValidName(['loads_' lower(n)]);
        end

        function applyRememberedLoads(app)
            % load A, load B and the repeat of the last two-load Start with this
            % configuration file (MATLAB preferences of the Windows user; owner
            % decision 2026-10-14). Visible windows only: a hidden one (tests)
            % neither reads nor writes them. The method is not remembered.
            try
                k = app.prefKey();
                if ~ispref('tubebench', k), return; end
                r = getpref('tubebench', k);
                ms = app.Cfg.measurement;
                tim.app.describeLoad(r.loadA); tim.app.describeLoad(r.loadB);     % a damaged record is ignored
                ms.loadA = struct('kind', char(r.loadA.kind), 'place', char(r.loadA.place));
                ms.loadB = struct('kind', char(r.loadB.kind), 'place', char(r.loadB.place));
                ms.repeatLoadA = logical(r.repeatLoadA);
                app.Cfg.measurement = ms;
                app.log('Terminations of the last two-load measurement with this configuration: load A "%s", load B "%s".', ...
                    tim.app.describeLoad(ms.loadA).label, tim.app.describeLoad(ms.loadB).label);
            catch
            end
        end

        function rememberLoads(app)
            if ~strcmp(app.Fig.Visible, 'on'), return; end        % a hidden window (tests) writes nothing
            try
                ms = app.Cfg.measurement;
                setpref('tubebench', app.prefKey(), struct('loadA', ms.loadA, 'loadB', ms.loadB, ...
                    'repeatLoadA', logical(ms.repeatLoadA)));
            catch
            end
        end

        %% ------------------------------------------------ two-load measurement
        function doTwoLoad(app)
            % A -> B (-> A') with the operator bar of the Two-load view, every load
            % saved at once (tim.app.runTwoLoad); the loads measured so far stay
            % shown and saved after a Stop or an error
            app.ensureBuilt({'twoload', 'wave'});
            app.readCfgFromUi();
            app.requireGain();
            app.syncSession();
            ms = app.Cfg.measurement;
            dA = tim.app.describeLoad(ms.loadA, app.Cfg); dB = tim.app.describeLoad(ms.loadB, app.Cfg);
            if strcmp(dA.tag, dB.tag)
                error('tim:gui:input', ['Two loads: load A and load B are both "%s". Choose two different ' ...
                    'terminations in Setup > Tube setup (Termination).'], dA.label);
            end
            % no calibration: every line of every load is invalid (owner 2026-10-14:
            % a whole A -> B -> A' run was made so) - asked before anything starts
            if isempty(app.currentCalibration())
                go = 'Start without calibration';
                sel = app.ask(['No calibration is loaded (CALIBRATION: Load calibration… or Run switching ' ...
                    'calibration…). Without one, no frequency line of any load is valid, and neither T nor the ' ...
                    'repeat of load A can be judged during the run.' newline newline 'The raw data are saved ' ...
                    'and can be reprocessed later: load a calibration, open the pair folder (File > Open ' ...
                    'measurement…) and press Reprocess.'], 'Two-load measurement', {go, 'Cancel'}, 2, 2, 'warning');
                if ~strcmp(sel, go)
                    app.log('Two-load measurement not started: no calibration loaded.');
                    return
                end
                app.log(['Two-load measurement started WITHOUT a calibration (operator): no line is valid ' ...
                    'until the pair is reprocessed with one.']);
            end
            app.rememberLoads();
            rep = ''; if ms.repeatLoadA, rep = ', load A repeated at the end'; end
            app.log('Start: two-load measurement of "%s" (%s): load A "%s", load B "%s"%s (started by the operator).', ...
                app.specimenName(), app.signalName(app.Cfg.excitation.mode), dA.label, dB.label, rep);
            app.LastLoads = []; app.LastTM = []; app.LastMeas = []; app.LastRes = []; app.LastCfg = app.Cfg;
            app.Saved = true; app.SavedDir = ''; app.Opened = false; app.ReprocessMics = [];
            app.TwStep = 0; app.buildTwSteps();
            app.showTab(app.H.twoLoadTab);
            app.refreshViews();
            figOpt = struct('Visible', 'off');
            out = tim.app.runTwoLoad(app.Session, struct('cfg', app.Cfg, 'specimen', app.specimenName(), ...
                'prompt', @(msg, load, k, n) app.twStep(msg, load, k, n), 'report', @(q) app.twReport(q), ...
                'figures', @(res, meas) tim.app.plotResults(res, meas, figOpt), ...
                'pairFigures', @(tm, loads) tim.app.plotResults(loads(1).res, loads(1).meas, ...
                setfield(figOpt, 'transferMatrix', tm))));
            app.LastLoads = out.loads; app.LastTM = out.tl;
            app.Saved = true; app.SavedDir = out.folder; app.Opened = false;
            app.showLoad('A');
            app.setResultStatus();
        end

        function twStep(app, msg, load, k, n)
            % one operator step: the model shows the termination to mount (glowing),
            % then (hardware, or practice) the operator confirms in the bar; in
            % simulation the virtual rig mounts the load
            app.ensureBuilt('twoload');
            app.TwStep = k;
            key = app.twKey(k);
            L = app.Cfg.ui.language;
            app.drawTwModel(load, true);
            app.setTwText(msg, tim.app.msg(L, 'tlStepHeader', k, n));
            app.showTab(app.H.twoLoadTab);
            app.TwList.set(key, 'run', 'operator: terminate the tube as shown');
            hw = strcmp(app.Session.Cfg.mode, 'hardware');
            if hw || app.PromptInSimulation
                ok = tim.app.msg(L, 'tlMeasureButton');
                app.startPulse(app.H.twHi);
                sel = app.askTwBar({ok, tim.app.msg(L, 'tlAbortButton')}, 1, 2);
                app.stopPulse();
                if ~strcmp(sel, ok)
                    app.TwList.set(key, 'fail', 'cancelled by the operator');
                    error('tim:gui:abort', 'Two-load measurement cancelled by the operator.');
                end
            end
            app.TwList.set(key, 'run', sprintf('measuring (%s) ...', app.signalName(app.Session.Cfg.excitation.mode)));
            % the live time signals while the load is measured; back to the
            % Two-load view when it is done (twReport; owner 2026-10-14)
            app.showTab(app.H.waveTab);
            app.testPoint('twoload:measuring');
            app.prepareLive();
        end

        function twReport(app, q)
            % after every load (quality, saved folder; shown at once) and at the end
            app.ensureBuilt('twoload');
            switch q.kind
                case 'load'
                    v = q.res.analysis.valid; inB = ~v.flags.outsideBand;
                    frac = nnz(v.valid & inB) / max(1, nnz(inB));
                    pk = tim.app.peakLevel(q.meas).max_dB;
                    st = 'ok';
                    if ~q.meas.integrityOk || frac < 0.5, st = 'fail'; elseif frac < 0.9, st = 'warn'; end
                    [~, fn] = fileparts(q.folder);
                    txt = sprintf('%.0f %% valid · peak %.0f dB', 100 * frac, pk);
                    if ~q.res.calibration.applied, txt = sprintf('0 %% valid: no calibration · peak %.0f dB', pk); end
                    if ~isempty(fn), txt = [txt ' · saved ' fn]; end
                    if ~q.meas.integrityOk, txt = ['data integrity failed – ' txt]; end
                    app.TwList.set(app.twKey(q.k), st, txt);
                    Lq = struct('role', q.role, 'load', q.load, 'meas', q.meas, 'res', q.res, 'folder', q.folder, ...
                        'cfg', q.cfg);
                    if isempty(app.LastLoads), app.LastLoads = Lq; else, app.LastLoads(end + 1) = Lq; end
                    app.LastMeas = q.meas; app.LastRes = q.res; app.LastCfg = q.cfg;
                    app.Saved = true; app.SavedDir = q.folder;
                    app.refreshViews({'wave', 'spec', 'tf'});
                    app.setResultStatus();
                    app.showTab(app.H.twoLoadTab);       % the load measured: back from the time signals
                case 'saving'
                    app.TwList.set('result', 'run', q.text);
                case 'result'
                    tm = q.tl; st = 'ok';
                    if ~isempty(tm.checks.errors) || tm.valid.nValid == 0
                        st = 'fail';
                    elseif ~isempty(tm.warnings)
                        st = 'warn';
                    end
                    txt = tm.valid.summary;
                    if ~isempty(app.LastLoads) && ~app.LastLoads(1).res.calibration.applied
                        txt = ['no calibration: ' txt ' – load one and Reprocess'];
                    end
                    if ~isempty(tm.checks.errors), txt = ['not combined: ' tm.checks.errors{1}]; end
                    [~, fn] = fileparts(q.folder);
                    if ~isempty(fn), txt = [txt ' · saved ' fn]; end
                    app.TwList.set('result', st, txt);
            end
        end

        function k = twKey(app, i)
            ks = app.twKeys(); k = ks{min(i, end)};
        end

        function ks = twKeys(app)
            ks = {'A', 'B'}; if app.Cfg.measurement.repeatLoadA, ks{end + 1} = 'A2'; end
        end

        function buildTwSteps(app)
            % operator steps of the two-load measurement (same order as
            % tim.app.runTwoLoad), "pending" until it starts
            if ~app.isBuilt('twoload'), return; end
            ms = app.Cfg.measurement;
            dA = tim.app.describeLoad(ms.loadA, app.Cfg); dB = tim.app.describeLoad(ms.loadB, app.Cfg);
            lb = ''; if ms.loadBLevel_dB < 0, lb = sprintf(' (%s%g dB)', char(8722), abs(ms.loadBLevel_dB)); end
            keys = [app.twKeys(), {'result'}];
            labels = {['Load A: ' dA.label], ['Load B: ' dB.label lb]};
            if ms.repeatLoadA, labels{end + 1} = ['Load A again: ' dA.label]; end
            labels{end + 1} = 'Transfer matrix, figures and the pair folder';
            app.TwList.rebuild(keys, labels);
            app.TwSteps = numel(keys) - 1;
        end

        function sel = askTwBar(app, options, defaultIdx, cancelIdx)
            %ASKTWBAR Operator question in the bar of the Two-load view (as askBar
            %   in the Calibration view): no modal dialog; Stop or closing the
            %   window returns the cancel option, a hidden window the default.
            app.LastPrompt = struct('text', '', 'options', {options});
            if ~isvalid(app) || ~isvalid(app.Fig) || app.stopPending()
                sel = options{cancelIdx}; return
            end
            if ~strcmp(app.Fig.Visible, 'on'), sel = options{defaultIdx}; return; end
            h = app.H; P = tim.gui.palette();
            app.LastPrompt.text = h.twText.Text;
            app.PromptAnswer = '';
            h.twOk.Text = options{1}; h.twCancel.Text = options{2};
            h.twOk.ButtonPushedFcn = @(~, ~) app.setPromptAnswer(options{1});
            h.twCancel.ButtonPushedFcn = @(~, ~) app.setPromptAnswer(options{2});
            h.twBar.ColumnWidth = {'1x', max(150, 8 * max(numel(options{1}), numel(options{2})) + 30)};
            h.twBar.BackgroundColor = P.ui.attention;
            h.twOk.Enable = 'on'; h.twCancel.Enable = 'on';
            drawnow;
            done = onCleanup(@() endTwPrompt(app));
            while isempty(app.PromptAnswer)
                if ~isvalid(app) || ~isvalid(app.Fig) || app.stopPending()
                    sel = options{cancelIdx}; return
                end
                pause(0.1);
            end
            sel = app.PromptAnswer;
        end

        function endTwPrompt(app)
            if ~isvalid(app) || ~isvalid(app.Fig) || ~app.isBuilt('twoload'), return; end
            app.H.twBar.ColumnWidth = {'1x', 0}; app.H.twBar.BackgroundColor = 'w';
        end

        function setTwText(app, msg, stepText)
            if ~app.isBuilt('twoload'), return; end
            note = @(s) ['<br><span style="color:#5f6368;font-size:11px">' htmlText(s) '</span>'];
            if isempty(msg)
                app.H.twText.Text = [htmlText(['Method "Two loads" and "Start two-load measurement": every step ' ...
                    'shows here which termination to mount; it glows yellow in the model. The loads are chosen in ' ...
                    'Setup > Tube setup.']), note(['The specimen section and the microphones stay untouched for all ' ...
                    'loads. Every load is saved at once; the transfer matrix follows (ASTM E2611).'])];
            else
                app.H.twText.Text = ['<b>' htmlText(stepText) ':</b>&nbsp; ' htmlText(msg), ...
                    note('Yellow: the termination to mount now  ·  the specimen and the microphones stay as they are')];
            end
        end

        function drawTwModel(app, load, highlight)
            % 3D model of the Two-load view with a termination (glowing: the one to mount now)
            if ~app.isBuilt('twoload'), return; end
            [geom, ~, msgs] = app.readTube();
            if ~isempty(msgs), geom = app.Cfg.geometry; end
            M = tim.gui.drawTube3D(app.H.axTw3D, geom, app.drawingDims(), app.homeMapping(), ...
                struct('termination', load, 'highlightTermination', highlight, 'section', true, 'dimensions', false));
            app.H.tw3D = M; app.H.twHi = M.glow;
        end

        function onShowLoad(app)
            app.showLoad(app.H.twShow.Value);
        end

        function showLoad(app, role)
            % the measurement and the own results of one load in the views (the
            % transfer matrix stays); "Show load" lists the loads there are
            L = app.LastLoads;
            if isempty(L), return; end
            i = find(strcmp({L.role}, role), 1); if isempty(i), i = 1; end
            app.LastMeas = L(i).meas; app.LastRes = L(i).res;
            if ~isempty(L(i).cfg), app.LastCfg = L(i).cfg; end
            if app.isBuilt('twoload')
                names = struct('A', 'A', 'B', 'B', 'A2', ['A' char(8242)], 'oneLoad', '1');
                app.H.twShow.Items = cellfun(@(r) names.(r), {L.role}, 'UniformOutput', false);
                app.H.twShow.ItemsData = {L.role};
                app.H.twShow.Value = L(i).role;
                app.H.twShow.Enable = matlab.lang.OnOffSwitchState(numel(L) > 1);
            end
            app.refreshViews();
        end

        function onCombine(app)
            % File > Combine two saved measurements…: load A, then load B
            if app.Busy || ~app.confirmDiscard('Combine two measurements'), return; end
            c = app.Cfg; if isempty(app.Session), c.mode = app.H.mode.Value; end
            start = tim.app.outputDir(c, 'data'); if ~isfolder(start), start = tim.app.projectRoot(); end
            f = cell(1, 2);
            for i = 1:2
                [fn, p] = uigetfile({'raw.mat', 'Saved measurement (raw.mat)'}, ...
                    sprintf('Combine two measurements – select raw.mat of load %c', 'A' + i - 1), [start filesep]);
                figure(app.Fig);
                if isequal(fn, 0), return; end
                f{i} = p; start = fileparts(fileparts(p));
            end
            app.combineMeasurements(f{1}, f{2});
        end
    end

    methods
        function combineMeasurements(app, folderA, folderB)
            %COMBINEMEASUREMENTS Two saved measurements of the same specimen with
            %   different terminations as loads A and B (File > Combine two saved
            %   measurements…): both are reprocessed with the IMPEDANCE TUBE
            %   fields and the active calibration, then the transfer matrix
            %   (tim.app.processTwoLoad). Save measurement writes a pair folder;
            %   the measurement folders are only read.
            app.run(@() app.doCombine(folderA, folderB), 'combining two measurements');
        end
    end

    methods (Access = private)
        function doCombine(app, folderA, folderB)
            app.ensureBuilt({'twoload', 'tm'});
            app.readCfgFromUi();
            p = tim.app.loadTwoLoad({char(folderA), char(folderB)});
            [cal, src] = app.currentCalibration();
            L = struct('role', {}, 'load', {}, 'meas', {}, 'res', {}, 'folder', {}, 'cfg', {});
            for i = 1:numel(p.loads)
                q = p.loads(i);
                c = app.Cfg; md = q.meas.metadata;
                if isfield(md, 'mode'), c.mode = md.mode; elseif isfield(md, 'WARNING'), c.mode = 'simulation'; end
                res = tim.app.processMeasurement(q.meas, c, cal);
                if isempty(q.load)
                    app.log('Load %s (%s): the termination was not recorded (saved before 1.4.0).', q.role, q.folder);
                end
                L(end + 1) = struct('role', q.role, 'load', q.load, 'meas', q.meas, 'res', res, 'folder', q.folder, ...
                    'cfg', q.cfg); %#ok<AGROW>
            end
            app.LastLoads = L;
            app.LastTM = tim.app.processTwoLoad(L, app.Cfg);
            app.Saved = false; app.SavedDir = ''; app.Opened = false; app.ReprocessMics = [];
            app.logTwoLoad(app.LastTM, sprintf('Combined %s (A) and %s (B), calibration %s%s', ...
                folderName(folderA), folderName(folderB), L(1).res.calibration.version, src));
            app.showLoad('A');
            app.setResultStatus();
            app.showTab(app.H.twoLoadTab);
        end

        function doOpenTwoLoad(app, folder)
            % a pair folder (tim.app.saveTwoLoad): its loads with their saved results
            % and the saved transfer matrix; Reprocess reprocesses every load
            p = tim.app.loadTwoLoad(folder);
            for w = reshape(p.warnings, 1, []), app.log('Warning: %s.', w{1}); end
            L = struct('role', {}, 'load', {}, 'meas', {}, 'res', {}, 'folder', {}, 'cfg', {});
            for i = 1:numel(p.loads)
                q = p.loads(i);
                L(end + 1) = struct('role', q.role, 'load', q.load, 'meas', q.meas, 'res', q.res, 'folder', q.folder, ...
                    'cfg', q.cfg); %#ok<AGROW>
            end
            app.LastLoads = L; app.LastTM = p.tl;
            app.Saved = true; app.SavedDir = folder; app.Opened = true; app.ReprocessMics = [];
            app.logTwoLoad(app.LastTM, sprintf('Opened %s', folderName(folder)));
            app.showLoad('A');
            app.setResultStatus();
        end

        function reprocessLoads(app)
            % Reprocess of a transfer-matrix result: every load with the fields
            % and the active calibration, then T again
            [cal, src] = app.currentCalibration();
            L = app.LastLoads;
            for i = 1:numel(L)
                c = app.Cfg; md = L(i).meas.metadata;
                if isfield(md, 'mode'), c.mode = md.mode; elseif isfield(md, 'WARNING'), c.mode = 'simulation'; end
                L(i).res = tim.app.processMeasurement(L(i).meas, c, cal);
            end
            app.LastLoads = L;
            app.LastTM = tim.app.processTwoLoad(L, app.Cfg);
            app.logTwoLoad(app.LastTM, sprintf('Reprocessed every load with calibration %s%s', ...
                L(1).res.calibration.version, src));
            shown = 'A'; if app.isBuilt('twoload'), shown = app.H.twShow.Value; end
            app.showLoad(shown);
        end

        function logTwoLoad(app, tm, head)
            app.log('%s: transfer matrix %s.', head, tm.valid.summary);
            if tm.repeat.performed, app.log('%s.', capital1(tm.repeat.text)); end
            if ~isempty(tm.level.text), app.log('%s.', capital1(tm.level.text)); end
            for w = reshape(tm.checks.warnings, 1, []), app.log('Warning: %s.', w{1}); end
            for e = reshape(tm.checks.errors, 1, []), app.log('Error: %s - no transfer matrix.', e{1}); end
        end

        function onTabChanged(app, ev)
            % (major or sub tab) a view opened before it is ready is prepared now -
            % but never during a running action (1-3 s would stall the data
            % stream): then it is prepared first when the action has finished.
            % The calibration model is drawn the first time the view is opened.
            p = app.tabPart(ev.NewValue);
            if ~isempty(p) && ~strcmp(app.PartState.(p), 'ready')
                if app.Busy || app.sessionActive() || ~isempty(app.Building)
                    if isempty(app.BuildTimer), app.startBuild(0.1); end
                    app.BuildQueue = [{p}, app.BuildQueue(~strcmp(app.BuildQueue, p))];   % next
                    if app.Busy || app.sessionActive()
                        app.setPlaceholder(p, 'This view is prepared when the running action has finished.');
                    end
                    return
                end
                try
                    app.ensureBuilt(p, 'tab');
                catch err
                    if ~isvalid(app), return; end
                    app.log('Preparing the %s view failed: %s', app.partLabel(p), err.message);
                    return
                end
                if ~isvalid(app), return; end           % window closed meanwhile
            end
            if ev.NewValue == app.H.calTab && app.isBuilt('cal') && app.CalDirty && ~app.Busy
                app.drawCalSetup([], '', '');
            end
        end

        function showTab(app, tab)
            % select a view: its sub tab and the major tab that holds it (the view is
            % prepared first if needed - the actions prepare theirs before they start)
            p = app.tabPart(tab);
            if ~isempty(p), app.ensureBuilt(p); end
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

        function startPulse(app, hi)
            % the glow pulses while MATLAB waits for the operator: the calibration
            % ports (default) or the termination of a two-load step (hi)
            app.stopPulse();
            if nargin < 2
                hi = gobjects(0); if isfield(app.H, 'calHi'), hi = app.H.calHi; end
            end
            if isempty(hi), return; end
            app.PulseHi = hi;
            app.PulseTimer = timer('ExecutionMode', 'fixedSpacing', 'Period', 0.35, 'BusyMode', 'drop', ...
                'Name', 'Tubebench-calibration-pulse', 'TimerFcn', @(~, ~) app.pulseStep(), 'Tag', app.TimerTag);
            start(app.PulseTimer);
        end
        function pulseStep(app)
            try
                hi = app.PulseHi(isvalid(app.PulseHi));
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
            hi = app.PulseHi;
            if isfield(app.H, 'calHi'), hi = [hi(:); app.H.calHi(:)]; end
            hi = hi(isvalid(hi));
            if ~isempty(hi), set(hi, 'FaceAlpha', 0.35); end
            app.PulseHi = gobjects(0);
        end

        function onSave(app)
            if isempty(app.LastMeas), app.alert('Nothing measured yet.', 'Save measurement', 'info'); return; end
            app.run(@() app.doSave(), 'saving the measurement');
        end
        function doSave(app)
            % Progress dialog in the window (same style as the closing dialog): the
            % steps done so far and the running one, with a progress bar. Data
            % files first, then the figures one by one (the slow part).
            if numel(app.LastLoads) > 1 && ~isempty(app.LastTM)
                app.doSaveTwoLoad(); return           % a transfer matrix of two loads: a new pair folder
            end
            done = {};
            dlgEnd = onCleanup(@() app.closeProgress());
            app.progressDialog('Saving the measurement', {'Drawing the figures …'}, 0.03);
            % saved figures = the views (background / unprocessed: time signals and spectrum)
            figs = tim.app.plotResults(app.LastRes, app.LastMeas, struct('Visible', 'off'));
            figEnd = onCleanup(@() closeFigures(figs));
            names = fieldnames(figs);
            done{end + 1} = sprintf('%d figures drawn.', numel(names));
            % method, signal and the name entered at Start (metadata.specimen), e.g.
            % oneload_sweep_foam / oneload-symmetric_sweep_foam (owner 2026-10-14)
            name = tim.app.measurementName(app.LastMeas, app.LastRes);
            % config.json describes the results it is saved with: the configuration
            % they were computed with (an opened folder: its config.json), not the
            % window's set-up of now; folder and exports follow the window
            c = app.Cfg;
            if ~isempty(app.LastCfg), c = app.LastCfg; c.output = app.Cfg.output; end
            md = app.LastMeas.metadata;          % the mode of the DATA decides folder and label (not the selector)
            if isfield(md, 'mode'), c.mode = md.mode; elseif isfield(md, 'WARNING'), c.mode = 'simulation'; end
            app.progressDialog('Saving the measurement', [done, {'Writing raw data, results, configuration and CSV files …'}], 0.25);
            d = tim.app.saveMeasurement(app.LastMeas, app.LastRes, c, name, []);   % figures below, with progress
            [~, folder] = fileparts(d);
            done{end + 1} = sprintf('Data written to %s.', folder);
            if c.output.exportFigures
                n = numel(names);
                for i = 1:n
                    app.progressDialog('Saving the measurement', [done, {sprintf('Exporting figure %d of %d (%s) …', ...
                        i, n, figs.(names{i}).Name)}], 0.3 + 0.68 * (i - 1) / n);
                    tim.app.exportFigures(struct(names{i}, figs.(names{i})), d, c.output.figureFormats);
                end
                done{end + 1} = sprintf('%d figures exported (%s).', n, strjoin(cellstr(c.output.figureFormats), ', '));
            end
            app.progressDialog('Saving the measurement', [done, {'Done.'}], 1);
            clear figEnd
            app.Saved = true; app.SavedDir = d; app.Opened = false;
            app.setResultStatus();
            app.log('Saved to %s', d);
        end

        function doSaveTwoLoad(app)
            % the transfer matrix of the loads in a NEW pair folder (the load
            % folders are not touched: their raw data are the source)
            dlgEnd = onCleanup(@() app.closeProgress());
            app.progressDialog('Saving the two-load result', {'Drawing the figures …'}, 0.05);
            L = app.LastLoads;
            i = find(strcmp({L.role}, 'A'), 1); if isempty(i), i = 1; end
            figs = tim.app.plotResults(L(i).res, L(i).meas, struct('Visible', 'off', 'transferMatrix', app.LastTM));
            figEnd = onCleanup(@() closeFigures(figs));
            c = app.Cfg; md = L(i).meas.metadata;
            if isfield(md, 'mode'), c.mode = md.mode; elseif isfield(md, 'WARNING'), c.mode = 'simulation'; end
            sp = ''; if isfield(md, 'specimen'), sp = md.specimen; end
            app.progressDialog('Saving the two-load result', {sprintf('%d figures drawn.', numel(fieldnames(figs))), ...
                'Writing the pair folder (result, CSV, figures) …'}, 0.4);
            d = tim.app.saveTwoLoad(app.LastTM, L, c, sp, figs);
            clear figEnd
            app.progressDialog('Saving the two-load result', {'Done.'}, 1);
            app.Saved = true; app.SavedDir = d; app.Opened = false;
            app.setResultStatus();
            app.log('Two-load result saved to %s (the loads stay in their folders).', d);
        end

        function onReprocess(app)
            if isempty(app.LastMeas) || strcmp(app.LastMeas.kind, 'background'), return; end
            app.run(@() app.doReprocess(), 're-processing');
        end
        function doReprocess(app)
            app.readCfgFromUi();                  % the fields as they are now (geometry, air)
            if numel(app.LastLoads) > 1
                app.reprocessLoads();             % a transfer matrix of two loads: every load, then T
            else
                app.process();
            end
            app.Saved = false; app.SavedDir = ''; app.Opened = false;  % new results: not saved yet
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
            recorded = '';
            if ~isempty(app.ReprocessMics)
                % an opened measurement: the mapping it was recorded with (operator's choice)
                [c, mp] = tim.app.useRecordedMapping(c, app.ReprocessMics);
                recorded = mp.recordedText;
            end
            app.LastRes = tim.app.processMeasurement(app.LastMeas, c, cal);
            app.LastCfg = c;             % saved as config.json with these results
            app.LastTM = [];
            if strcmp(app.Cfg.measurement.method, 'oneLoadSymmetric')
                % the transfer matrix from this one load, ASSUMING a symmetric,
                % reciprocal specimen (WO-005); saved with the results
                ld = [];
                md0 = app.LastMeas.metadata;
                if isfield(md0, 'termination'), ld = struct('kind', md0.termination.kind, 'place', md0.termination.place); end
                app.LastTM = tim.app.processTwoLoad(struct('role', 'oneLoad', 'res', app.LastRes, 'load', ld, ...
                    'meas', app.LastMeas, 'cfg', c, 'folder', ''), c);
                app.LastRes.transferMatrix = app.LastTM;
                app.log('One load, symmetric specimen ASSUMED: transfer matrix %s.', app.LastTM.valid.summary);
            end
            app.log('%s', app.LastRes.summary);
            app.log('Processed with calibration %s%s; L1/d/L2 = %s/%s/%s mm, T = %g °C.', ...
                app.LastRes.calibration.version, src, app.H.L1.Value, app.H.dTh.Value, app.H.L2.Value, app.H.temp.Value);
            if ~isempty(recorded)
                app.log('Microphone mapping as recorded with the measurement: %s.', recorded);
            end
            for w = app.LastRes.calibration.context.warnings, app.log('CALIBRATION: %s', w{1}); end
            if isfield(app.LastRes, 'diagnostics') && isfield(app.LastRes.diagnostics, 'warnings')
                for w = reshape(app.LastRes.diagnostics.warnings, 1, []), app.log('Warning: %s', w{1}); end
            end
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

        function o = plotOpts(app, src, res)
            % options of the tim.plots views. A result is drawn with the band and
            % limits it was analysed with (res.analysis.options, the views' default),
            % as in the saved figures (tim.app.plotResults); the configuration's
            % only without one (empty states, an unprocessed measurement) - an
            % opened measurement may have been analysed with other settings
            a = app.Cfg.analysis;
            o = struct('band', [a.fMin a.fMax], 'coherenceMin', a.coherenceMin, 'anechoicRmax', a.anechoicRmax, ...
                'simulation', false);
            if nargin >= 3 && isstruct(res) && isfield(res, 'analysis') && isfield(res.analysis, 'options')
                o.band = []; o.coherenceMin = []; o.anechoicRmax = [];
            end
            if nargin >= 2 && isstruct(src)
                if isfield(src, 'metadata') && isfield(src.metadata, 'WARNING'), o.simulation = true; end
                if isfield(src, 'meta') && isfield(src.meta, 'mode'), o.simulation = strcmp(src.meta.mode, 'simulation'); end
            end
        end

        function refreshViews(app, pages)
            % every measurement / result view from LastMeas / LastRes (empty states
            % show labels, units and default limits) and the calibration curves.
            % pages: some of them ('cal' = calibration curves). Views not built
            % yet are skipped - never built here: their first drawing shows the
            % data of then (progressive start-up).
            if nargin < 2, pages = {'wave', 'spec', 'tf', 'twoload', 'refl', 'tl', 'zt', 'valid', 'tm', 'cal'}; end
            pages = pages(cellfun(@(p) app.isBuilt(p), pages));
            m = app.LastMeas; r = app.LastRes;
            o = app.plotOpts(m, r);
            % the transfer matrix (two loads, or one load of a symmetric specimen;
            % WO-005): the result views show it first; its own views use their
            % own empty texts
            ot = app.plotOpts(m, r);
            if ~isempty(app.LastTM)
                o.transferMatrix = app.LastTM; ot.transferMatrix = app.LastTM;
                ot.band = app.LastTM.band;
            end
            if isempty(m)
                o.emptyText = 'No measurement yet – connect and press Start measurement';
            elseif strcmp(m.kind, 'background')
                o.emptyText = 'Last record: background noise (no specimen results)';
            elseif isempty(r)
                o.emptyText = 'Not processed';
            end
            views = setdiff(pages, {'cal'}, 'stable');
            for i = 1:numel(views)
                try
                    switch views{i}
                        case 'wave'
                            ow = o; [ow.gate, ow.gateEnds] = tim.plots.analysisGate(r);   % grey: not analysed
                            info = tim.plots.timeSignals(app.H.axW, m, ow);
                            if isfield(info, 'lines'), app.WaveLines = info.lines; else, app.WaveLines = gobjects(0); end
                        case 'spec', info = tim.plots.spectrum(app.H.axSpec, m, r, o);
                        case 'tf', info = tim.plots.transferFunctions(app.H.axH, r, o);
                        case 'refl', info = tim.plots.reflection(app.H.axR, r, o);
                        case 'tl', info = tim.plots.transmissionLoss(app.H.axTL, r, o);
                        case 'zt', info = tim.plots.transferImpedance(app.H.axZ, r, o);
                        case 'valid', info = tim.plots.validity(app.H.axV, r, o);
                        case 'twoload', info = tim.plots.twoLoad(app.H.axTwQ, app.LastTM, setfield(ot, 'sideBySide', true));
                        case 'tm', info = tim.plots.transferMatrix(app.H.axTM, app.LastTM, ot);
                    end
                    % notes of the measurement views are information, of the result views warnings
                    if ~isfield(info, 'status') && any(strcmp(views{i}, {'wave', 'spec', 'tf'})), info.status = 'info'; end
                    app.Pages.(views{i}).show(info);
                catch err
                    app.log('Display of the %s view failed: %s', views{i}, err.message);
                end
            end
            if ~any(strcmp(pages, 'cal')), return; end
            if isempty(app.Session) || isempty(app.Session.Calibration)
                [cal, ~] = app.currentCalibration();
            else
                cal = app.Session.Calibration;
            end
            try
                info = tim.plots.calibration(app.H.axCal, cal, setfield(app.plotOpts(cal), 'sideBySide', true));
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
                verb = 'Saved: '; if app.Opened, verb = 'Opened: '; end
                h.resultStatus.Text = [verb nm]; h.resultStatus.FontColor = P.ok;
                h.resultStatus.Tooltip = app.SavedDir;
            else
                ts = char(m.timestamp); if numel(ts) >= 19, ts = ts(12:19); end
                h.resultStatus.Text = sprintf('%s %s – not saved', app.capital(app.signalName(m.kind)), ts);
                h.resultStatus.FontColor = P.fail; h.resultStatus.Tooltip = 'Press Save measurement to keep it.';
                if numel(app.LastLoads) > 1 && ~isempty(app.LastTM)
                    h.resultStatus.Text = 'Two-load result – not saved';
                    h.resultStatus.Tooltip = 'Press Save measurement: a new pair folder (the loads stay in their folders).';
                end
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
                cur = [];                    % connected: the DAQ module and input settings in use
                if ~isempty(app.Session) && app.Session.Connected, cur = app.Session.acquisitionChain(); end
                ctx = tim.cal.calibrationContext(cal, c, cur);
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
            % Help > About: the mark, program, version, release date, Git commit,
            % MATLAB release, the licence (MIT, owner 2026-10-13) and the author's
            % portfolio (selectable text: can be copied; the repository is in
            % Help > Source code on GitHub)
            if ~isempty(app.AboutFig) && isvalid(app.AboutFig)
                figure(app.AboutFig); fig = app.AboutFig; return
            end
            [~, info] = tim.app.softwareVersion();
            p = app.Fig.Position; w = 500; hgt = 266;
            fig = uifigure('Name', 'About tubebench', 'Resize', 'off', 'Visible', app.Fig.Visible, ...
                'Position', [p(1) + (p(3) - w) / 2, p(2) + (p(4) - hgt) / 2, w, hgt], 'Icon', tim.gui.logo('icon'));
            app.AboutFig = fig;
            gl = uigridlayout(fig, [4 2], 'RowHeight', {52, '1x', 22, 30}, 'ColumnWidth', {'1x', 90}, ...
                'Padding', [16 12 16 12], 'RowSpacing', 6);
            % header: the mark (light version, 46 px) left of the name and the subtitle
            hd = uigridlayout(gl, [2 2], 'RowHeight', {28, 22}, 'ColumnWidth', {46, '1x'}, 'Padding', [0 0 0 0], ...
                'RowSpacing', 2, 'ColumnSpacing', 14);
            hd.Layout.Row = 1; hd.Layout.Column = [1 2];
            app.H.aboutLogo = uiimage(hd, 'ImageSource', tim.gui.logo(), 'ScaleMethod', 'fit');
            app.H.aboutLogo.Layout.Row = [1 2]; app.H.aboutLogo.Layout.Column = 1;
            l = uilabel(hd, 'Text', 'tubebench', 'FontSize', 17, 'FontWeight', 'bold');
            l.Layout.Row = 1; l.Layout.Column = 2;
            l = uilabel(hd, 'Text', 'Four-microphone transfer-impedance tube measurement (MATLAB)', 'FontColor', [0.35 0.35 0.35]);
            l.Layout.Row = 2; l.Layout.Column = 2;
            lines = {sprintf('Program:      %s', info.name), ...
                sprintf('Version:      %s (released %s)', info.version, info.released), ...
                sprintf('Git commit:   %s (branch %s)', info.commit, info.branch), ...
                sprintf('MATLAB:       %s', version()), ...
                'License:      MIT License - Copyright (c) 2026 Woongji Kim (file LICENSE)', ...
                'The version and the commit are stored with every measurement and calibration.'};
            ta = uitextarea(gl, 'Value', lines, 'Editable', 'off', 'FontName', 'Consolas', 'FontSize', 11);
            ta.Layout.Row = 2; ta.Layout.Column = [1 2];
            app.H.aboutText = ta;
            u = tim.app.portfolioUrl();
            lk = uihyperlink(gl, 'Text', regexprep(u, '^https?://', ''), 'URL', u, ...
                'Tooltip', 'portfolio of the author - opens in the web browser');
            lk.Layout.Row = 3; lk.Layout.Column = [1 2];
            app.H.aboutPortfolio = lk;
            b = uibutton(gl, 'Text', 'OK', 'ButtonPushedFcn', @(~, ~) delete(fig));
            b.Layout.Row = 4; b.Layout.Column = 2;
        end

        function progressDialog(app, title, msg, value)
            % progress dialog inside the window with a determinate bar (Save
            % measurement); same look as the "Closing" dialog: the steps done so
            % far and the running one. A hidden window (scripts, tests) shows nothing.
            if isempty(app.Fig) || ~isvalid(app.Fig) || ~strcmp(app.Fig.Visible, 'on'), return; end
            msg = cellstr(msg);
            if isempty(app.ProgressWin) || ~isvalid(app.ProgressWin)
                app.ProgressWin = uiprogressdlg(app.Fig, 'Title', title, 'Message', msg, 'Value', value, 'Icon', 'info');
            else
                app.ProgressWin.Title = title; app.ProgressWin.Message = msg; app.ProgressWin.Value = value;
            end
            drawnow;
        end

        function closeProgress(app)
            if isvalid(app) && ~isempty(app.ProgressWin) && isvalid(app.ProgressWin)
                close(app.ProgressWin);
            end
        end

        function closingDialog(app, msg)
            % "Closing" progress dialog inside the (already rendered) window:
            % appears at once; its indeterminate bar is animated by the window
            % itself, so it keeps moving while MATLAB waits for an instrument
            msg = cellstr(msg);
            app.ClosingLog = [app.ClosingLog, msg(:).'];
            if isempty(app.Fig) || ~isvalid(app.Fig) || ~strcmp(app.Fig.Visible, 'on'), return; end
            if isempty(app.ClosingWin) || ~isvalid(app.ClosingWin)
                app.ClosingWin = uiprogressdlg(app.Fig, 'Title', 'Closing tubebench', ...
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
            app.stopLinkCheck();
            s = app.Session;
            done = {};
            if ~isempty(s) && ~isempty(s.Gen)
                app.closingDialog([done, {'Switching the generator output OFF ...'}]);
                try, s.Gen.outputOff(); catch, end
                done{end + 1} = app.outputOffText();
                s.log('Closing: %s', done{end});
            end
            if ~isempty(s)
                closed = 'instruments to their safe state'; try, closed = app.closedText(); catch, end
                app.closingDialog([done, {sprintf('Closing the connections: %s (2 s time-out per request) ...', closed)}]);
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

function t = loadName(ld)
% a generator output load as the window shows it: 'INF' / 'High Z' -> 'High Z', '50' -> '50 Ω'
ld = char(string(ld));
if any(strcmpi(ld, {'INF', 'High Z'})), t = 'High Z'; else, t = [ld ' Ω']; end
end

function t = loadText(c)
% what the programmed generator amplitude means (generator.load): the
% open-circuit voltage at 'INF', the voltage across R (the amplifier input)
% at a load of R ohm (WO-004)
ld = 'INF'; if isfield(c.generator, 'load'), ld = char(string(c.generator.load)); end
if isfinite(tim.instr.SignalSource.loadOhm(ld))
    t = sprintf('the voltage into %s Ω, the amplifier input', ld);
else
    t = 'the open-circuit voltage';
end
end

function items = loadItems(v)
% the amplifier input list: High Z, typical inputs of laboratory amplifiers
% (data sheets: 50 Ω, 600 Ω, 10 kΩ) and the current value when typed
items = {'High Z', '50', '600', '10000'};
if ~isempty(v) && ~any(strcmp(v, items)), items{end + 1} = v; end
end

function R = loadValue(v)
% the amplifier input of the list [Ω]: 'High Z' / 'INF' / empty -> Inf, a
% number (also '600 Ω', '10k') -> its value, anything else NaN
t = lower(strtrim(char(string(v))));
t = strtrim(regexprep(t, '(ω|ohm)$', ''));
if any(strcmp(t, {'', 'high z', 'highz', 'inf'})), R = Inf; return; end
k = 1; if endsWith(t, 'k'), k = 1e3; t = t(1:end - 1); end
R = str2double(t) * k;
if ~(isfinite(R) && R > 0), R = NaN; end
end

function t = idText(id, long)
% an identity() as text: short '<model> s/n <serial>' (In use) or long
% '<vendor> <model>, s/n <serial>, firmware <firmware>' (lamp tooltips);
% fields the instrument did not report are left out
f = @(v) strtrim(char(string(v)));
model = f(id.model); serial = f(id.serial);
if long
    parts = {strtrim([f(id.vendor) ' ' model])};
    if ~isempty(serial), parts{end + 1} = ['s/n ' serial]; end
    if ~isempty(f(id.firmware)), parts{end + 1} = ['firmware ' f(id.firmware)]; end
    t = strjoin(parts(~cellfun(@isempty, parts)), ', ');
else
    if isempty(model), model = f(id.vendor); end
    t = model;
    if ~isempty(serial), t = strtrim([t ' s/n ' serial]); end
end
if isempty(t), t = 'no identity reported'; end
end

function s = orDash(v)
% table cell: the text, or '–' when empty (not reported / not connected)
s = strtrim(char(string(v)));
if isempty(s), s = '–'; end
end

function op = workArea()
% [left bottom width height] of the work area of the primary
% screen (screen without the taskbar) in MATLAB coordinates (origin bottom left)
scr = get(groot, 'ScreenSize');
op = [1, 49, scr(3), scr(4) - 48];                         % fallback: 48 px taskbar at the bottom
try
    r = java.awt.GraphicsEnvironment.getLocalGraphicsEnvironment().getMaximumWindowBounds();
    s = java.awt.Toolkit.getDefaultToolkit().getScreenSize();
    k = scr(3) / double(s.width);                            % Java pixels -> MATLAB pixels (display scaling)
    op = [double(r.x) * k + 1, scr(4) - double(r.y + r.height) * k + 1, double(r.width) * k, double(r.height) * k];
catch
end
op(3) = max(op(3), 1200); op(4) = max(op(4), 760);        % smallest usable window
end

function s = htmlText(s)
% plain text for an HTML uilabel (& < > escaped)
s = strrep(strrep(strrep(char(s), '&', '&amp;'), '<', '&lt;'), '>', '&gt;');
end

function tf = sameTube(g1, e1, g2, e2)
% same tube set-up within 0.1 µm, 0.001 °C and 0.01 Pa (not entered = NaN matches NaN)
a = [g1.diameter, g1.spacingUp, g1.spacingDown, g1.micPositions(:).', g1.xFront, g1.xRear];
b = [g2.diameter, g2.spacingUp, g2.spacingDown, g2.micPositions(:).', g2.xFront, g2.xRear];
tf = numel(a) == numel(b) && all((isnan(a) & isnan(b)) | abs(a - b) <= 1e-7) && ...
    abs(e1.temperature_C - e2.temperature_C) <= 1e-3 && abs(e1.pressure_Pa - e2.pressure_Pa) <= 1e-2;
end

function t = tubeText(g, e)
% "D 29, s1 29, L1 41, d 75, L2 41, s2 29 mm, 20 °C, 101.325 kPa"
mm = @(v) num2str(round(1e3 * v, 3));
x = g.micPositions;
if all(isfinite(x)) && isfinite(g.xFront) && isfinite(g.xRear)
    t = sprintf('D %s, s1 %s, L1 %s, d %s, L2 %s, s2 %s mm', mm(g.diameter), mm(x(2) - x(1)), ...
        mm(g.xFront - x(2)), mm(g.xRear - g.xFront), mm(x(3) - g.xRear), mm(x(4) - x(3)));
else
    t = sprintf('D %s, s1 %s, s2 %s mm, L1 / d / L2 not entered', mm(g.diameter), mm(g.spacingUp), mm(g.spacingDown));
end
t = sprintf('%s, %g °C, %g kPa', t, e.temperature_C, e.pressure_Pa / 1e3);
end

function closeFigures(figs)
% close the (hidden) saved-figure windows of Save measurement
fc = struct2cell(figs);
for i = 1:numel(fc)
    if ~isempty(fc{i}) && isgraphics(fc{i}), close(fc{i}); end
end
end

function [mics, info] = recordedMapping(cfg, meas, saved)
% the microphones a measurement was recorded with - meas.mics, else the mics of
% its folder's config.json (saved) - and their mapping compared with cfg
% (tim.app.useRecordedMapping); mics = [] when neither holds a complete mapping
mics = []; info = [];
src = {};
if isfield(meas, 'mics'), src{end + 1} = meas.mics; end
if isstruct(saved) && isfield(saved, 'mics'), src{end + 1} = saved.mics; end
for i = 1:numel(src)
    try
        [~, info] = tim.app.useRecordedMapping(cfg, src{i});
        mics = src{i};
        return
    catch
    end
end
end

function t = bandSource(b)
% where the analysis band comes from, in a few words (tim.app.analysisBand)
if strcmp(b.mode, 'geometry') && all(isfinite(b.limits))
    t = 'from the tube';
elseif b.outside
    t = 'fixed, beyond the ASTM limits';
else
    t = 'fixed';
end
end

function t = savedMapping(cfg, saved, res)
% the mapping (DAQ channel -> port) the saved results were computed with, as
% text: the mics of the folder's config.json, which Save writes with the
% results ('' without saved results or a complete mapping)
t = '';
if isempty(res) || ~isstruct(saved) || ~isfield(saved, 'mics'), return; end
try
    [~, info] = tim.app.useRecordedMapping(cfg, saved.mics);
    t = info.recordedText;
catch
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

function linkTimerFcn(app)
% idle connection check of the window (Tubebench.startLinkCheck); never throws
try
    if isvalid(app), app.checkConnectionNow(); end
catch
end
end

function endLinkCheck(app)
% end of a connection check (Tubebench.checkConnectionNow), also on an error
if isvalid(app), app.setLinkChecking(false); end
end

function buildTimerFcn(t, app)
% TimerFcn of the progressive start-up; the app may be gone (window closed)
if ~isvalid(app)
    try, stop(t); delete(t); catch, end
    return
end
try
    app.onBuildTick();
catch err
    warning('tim:gui:build', 'Preparing the views in the background: %s', err.message);
end
end

function restoreBuilding(app, prev)
% end of an on-demand preparation of a view (also on an error / closed window)
if isvalid(app), app.setBuildingFlag(prev); end
end

function t = distText(d)
% distance of a termination face behind M4 as text (the operator texts of tim.app.msg)
if isfinite(d), t = sprintf('%g mm', round(1e3 * d, 1)); else, t = '?'; end
end

function s = capital1(s)
if ~isempty(s), s(1) = upper(s(1)); end
end

function n = folderName(f)
% the name of a data folder (the last part of its path)
[~, n, e] = fileparts(char(f)); n = [n e];
if isempty(n), [~, n] = fileparts(fileparts(char(f))); end
end
