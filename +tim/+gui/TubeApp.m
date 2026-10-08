classdef TubeApp < handle
    %TUBEAPP Basic graphical interface (uifigure, R2022b) for the tube system.
    %
    %   app = tim.gui.TubeApp();                      % default / example config
    %   app = tim.gui.TubeApp('config/user_config.json');
    %   app = tim.gui.TubeApp(file, 'Visible', 'off')  % hidden window (automated tests)
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
        CalStep double = 0      % current / total operator steps of a calibration
        CalSteps double = 0
        Busy logical = false    % a measurement / calibration is running (GUI locked)
        LiveLast double = 0     % (reserved) live-view bookkeeping
        LiveCount double = 0    % number of live-view refreshes (diagnostics / tests)
        EnableState = []        % Enable states saved while busy
        ConnList = []           % tim.gui.Checklist of the connection steps
        CalList = []            % tim.gui.Checklist of the calibration steps
        CalKeys cell = {}       % checklist key of every calibration operator step
        CalMap = []             % microphone mapping of the current calibration step
        CalDrawn = []           % mapping the 3D calibration model currently shows
        CalDirty logical = true % geometry / config / TEDS changed: redraw the calibration model
        CalDrawCount double = 0 % number of 3D calibration draws (diagnostics / tests)
        PulseTimer = []         % highlights the calibration ports while the operator works
        CloseAfterBusy logical = false  % window close requested during a running action
        ClosingWin = []         % "Closing ..." progress dialog (steps of the shutdown)
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
            app.log('Ready. Mode: %s. Generator output is OFF until you press START.', app.Cfg.mode);
        end

        function delete(app)
            try, app.stopPulse(); catch, end
            try, app.disconnect(); catch, end
            if ~isempty(app.Fig) && isvalid(app.Fig), delete(app.Fig); end
        end

        function disconnect(app)
            if ~isempty(app.Session)
                try, app.Session.close(); catch, end
                app.Session = [];
                if isfield(app.H, 'connHead') && isvalid(app.H.connHead)
                    app.H.connHead.Text = 'Disconnected. The list shows the last connection.';
                    app.H.connHead.FontColor = [0.3 0.3 0.3];
                end
            end
            if isfield(app.H, 'status') && isvalid(app.H.status), app.setStatus('disconnected', false); end
            if isfield(app.H, 'lamp') && all(isvalid(app.H.lamp))
                P = tim.gui.palette();
                set(app.H.lamp, 'Color', P.idle);
                for c = 1:4, app.H.card(c).lamp.Color = P.idle; app.H.card(c).state.Text = 'not connected'; end
            end
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
            %   action has stopped; a second request closes at once.
            if app.Busy && ~app.CloseAfterBusy
                app.CloseAfterBusy = true;
                if ~isempty(app.Session)
                    app.Session.requestStop();
                    try, app.Session.Gen.outputOff(); catch, end
                end
                app.closingDialog({'Stopping the running measurement / calibration ...', ...
                    'Generator output is OFF. The window closes as soon as the action has stopped.'});
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
            %   ports). Closing the window or STOP returns the cancel option.
            if nargin < 7, icon = 'question'; end
            answer = '';
            function setAnswer(s)
                answer = s;
            end
            uiconfirm(app.Fig, msg, title, 'Options', options, 'DefaultOption', defaultIdx, ...
                'CancelOption', cancelIdx, 'Icon', icon, 'CloseFcn', @(~, ev) setAnswer(ev.SelectedOption));
            while isempty(answer)
                if ~isvalid(app) || ~isvalid(app.Fig) || (~isempty(app.Session) && app.Session.StopRequested)
                    answer = options{cancelIdx};
                    break
                end
                pause(0.1);
            end
            sel = answer;
        end

        function drawCalSetup(app, mapping, msg, stepText, fromMapping)
            % Calibration diagram = the 3D model of the Tube setup tab in its
            % calibration state (EMPTY specimen section, absorbing termination,
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
            app.H.calLabel.Text = cal.version; app.H.calLabel.FontColor = [0 0.5 0];
            if isfield(cal, 'meta') && isfield(cal.meta, 'emptyCheck') && cal.meta.emptyCheck.performed
                if cal.meta.emptyCheck.passed
                    app.H.calLabel.Text = [cal.version '  (Test E passed)'];
                else
                    app.H.calLabel.Text = [cal.version '  (Test E FAILED)']; app.H.calLabel.FontColor = [0.75 0.45 0];
                end
            end
            ax = app.H.axCal; cla(ax, 'reset'); hold(ax, 'on');
            P = tim.gui.palette(); col = P.ch; leg = {}; hl = gobjects(0);
            for k = 1:4
                if k == cal.refChannel, continue; end
                yyaxis(ax, 'left');
                hl(end+1) = plot(ax, cal.f, 20 * log10(abs(cal.C(:, k))), '-', 'Color', col(k, :), 'LineWidth', 1.2); %#ok<AGROW>
                yyaxis(ax, 'right');
                hl(end+1) = plot(ax, cal.f, rad2deg(unwrap(angle(cal.C(:, k)))), ':', 'Color', col(k, :), 'LineWidth', 1.5); %#ok<AGROW>
                leg = [leg, {sprintf('|C_%d| (ch%d/ch%d)', k, k, cal.refChannel), sprintf('\\angle C_%d', k)}]; %#ok<AGROW>
            end
            yyaxis(ax, 'left'); ylabel(ax, '|C_k| = |c_k/c_{ref}| [dB]  (solid)'); ax.YColor = [0.15 0.15 0.15];
            yyaxis(ax, 'right'); ylabel(ax, '\angle C_k [deg]  (dotted)'); ax.YColor = [0.15 0.15 0.15];
            set(ax, 'XScale', 'log'); grid(ax, 'on'); xlabel(ax, 'Frequency [Hz]');
            legend(ax, hl, leg, 'Location', 'eastoutside');   % explicit handles: yyaxis reorders children
            title(ax, sprintf('Complex channel calibration %s:  C_k = \\surd(H^I H^{II}),  corrected H_k = H_k / C_k', cal.version));
        end

    end

    methods (Access = private)
        %% ----------------------------------------------------------- layout
        function build(app, visible)
            % window fills the screen (maximised); restored size = most of the screen
            scr = get(groot, 'ScreenSize');
            W = max(1400, scr(3) - 80); Hh = max(760, scr(4) - 120);
            app.Fig = uifigure('Name', 'Transfer impedance tube', 'Position', [40 50 W Hh], 'Visible', visible, ...
                'CloseRequestFcn', @(src, ~) tim.gui.closeApp(src, app));   % never gets stuck
            if strcmp(visible, 'on')
                try, app.Fig.WindowState = 'maximized'; catch, end
            end
            g = uigridlayout(app.Fig, [1 2], 'ColumnWidth', {430, '1x'});
            % Left panel: ONE column; each row is a label or a small nested grid
            % (rowGrid) so that related fields share a row. Fixed row heights [px]:
            % about 720 px in total -> no scrolling in the maximised window (989 px
            % on a 1920 x 1080 screen) nor in the smallest window (760 - 2 x 10 px).
            % Scrollable stays on as a fallback for very small screens.
            hd = 26; rw = 24;                        % section header (text at the bottom) / control row
            rowH = {20, rw, rw, rw, rw, ...           %  1- 5 INSTRUMENTS: header, mode + config, connect, status, lamps
                hd, rw, rw, rw, rw, rw, 32, 28, ...   %  6-13 EXCITATION: header, 5 field rows, drive, START/STOP
                hd, rw, 18, rw, 46, ...               % 14-18 IMPEDANCE TUBE: header, D/T/p, names, distances, limits
                hd, rw, rw, ...                       % 19-21 CALIBRATION
                hd, rw};                              % 22-23 RESULTS
            left = uigridlayout(g, [numel(rowH) 1], 'RowHeight', rowH, 'ColumnWidth', {'1x'}, ...
                'Scrollable', 'on', 'RowSpacing', 5);
            left.Layout.Row = 1; left.Layout.Column = 1;
            h = struct();
            h.left = left;
            P = tim.gui.palette();
            ex = {112, '1x', 92, 76};                % excitation rows: label, field, label, field
            r = 0;
            % ---------------- instruments
            r = r + 1; app.header(left, r, 'INSTRUMENTS');
            r = r + 1; rg = app.rowGrid(left, r, {40, 98, '1x', '1x'});
            uilabel(rg, 'Text', 'Mode');
            h.mode = uidropdown(rg, 'Items', {'simulation', 'hardware'});
            h.loadCfg = uibutton(rg, 'Text', 'Load config...', 'ButtonPushedFcn', @(~, ~) app.onLoadConfig());
            h.saveCfg = uibutton(rg, 'Text', 'Save config...', 'ButtonPushedFcn', @(~, ~) app.onSaveConfig());
            r = r + 1; rg = app.rowGrid(left, r, {'1x', '1x'});
            h.connect = uibutton(rg, 'Text', 'Connect + TEDS', 'ButtonPushedFcn', @(~, ~) app.onConnect());
            h.disconnect = uibutton(rg, 'Text', 'Disconnect', 'ButtonPushedFcn', @(~, ~) app.disconnect());
            r = r + 1; rg = app.rowGrid(left, r, {44, '1x'});
            uilabel(rg, 'Text', 'Status');
            h.status = uilabel(rg, 'Text', 'disconnected', 'FontColor', [0.6 0 0]);
            % status lamps: generator, LAN-XI, the four channels (details: Connection tab)
            r = r + 1; gl = app.rowGrid(left, r, {92, 80, '1x', '1x', '1x', '1x'});
            names = {'Generator', 'LAN-XI', 'ch1', 'ch2', 'ch3', 'ch4'};
            tips = {'function generator 33220A', 'LAN-XI module', 'channel 1', 'channel 2', 'channel 3', 'channel 4'};
            for i = 1:6
                gi = uigridlayout(gl, [1 2], 'Padding', [0 0 0 0], 'ColumnSpacing', 4, 'ColumnWidth', {13, '1x'});
                h.lamp(i) = uilamp(gi, 'Color', P.idle, 'Tooltip', [tips{i} ' - details in the Connection tab']);
                uilabel(gi, 'Text', names{i}, 'FontSize', 11, 'Tooltip', tips{i});
            end
            % ---------------- excitation
            r = r + 1; app.header(left, r, 'EXCITATION');
            r = r + 1; rg = app.rowGrid(left, r, ex);
            uilabel(rg, 'Text', 'Mode');
            h.exMode = uidropdown(rg, 'Items', {'sweep', 'stepped'}, 'Tooltip', ...
                'sweep: broadband measurement (default).  stepped: discrete sine frequencies - cross-check / validation', ...
                'ValueChangedFcn', @(~, ev) app.onExMode(ev.PreviousValue));
            uilabel(rg, 'Text', 'Repetitions');
            h.reps = uieditfield(rg, 'numeric', 'Limits', [1 100], 'RoundFractionalValues', 'on');
            r = r + 1; rg = app.rowGrid(left, r, ex);
            uilabel(rg, 'Text', 'f start / stop [Hz]');
            h.fRange = uieditfield(rg, 'text', 'Tooltip', 'start and stop frequency in Hz, e.g. "80 5500"');
            h.durLabel = uilabel(rg, 'Text', 'Sweep time [s]');
            h.dur = uieditfield(rg, 'numeric', 'Limits', [0.001 500]);
            r = r + 1; rg = app.rowGrid(left, r, ex(1:2));
            uilabel(rg, 'Text', 'Amp model');
            h.ampModel = uidropdown(rg, 'Editable', 'on', 'Items', {'none (direct drive)', 'power amplifier'}, ...
                'Tooltip', 'select, or type the model of your power amplifier (typed models are added)', ...
                'ValueChangedFcn', @(~, ~) app.onAmpModel());
            r = r + 1; rg = app.rowGrid(left, r, ex);
            uilabel(rg, 'Text', 'Amplitude [Vpk]');
            h.amp = uieditfield(rg, 'numeric', 'Limits', [0.005 10], 'ValueChangedFcn', @(~, ~) app.updateDrive());
            uilabel(rg, 'Text', 'Amp gain [x]');
            h.ampGain = uieditfield(rg, 'numeric', 'Limits', [0 Inf], 'LowerLimitInclusive', 'off', 'ValueDisplayFormat', 'x %.4g', ...
                'Tooltip', 'voltage gain of the power amplifier as a multiplier (x10 = 20 dB); used to estimate the loudspeaker drive', ...
                'ValueChangedFcn', @(~, ~) app.updateDrive());
            r = r + 1; rg = app.rowGrid(left, r, ex);
            uilabel(rg, 'Text', 'Speaker [ohm]', 'Tooltip', 'nominal loudspeaker impedance');
            h.spkZ = uieditfield(rg, 'numeric', 'Limits', [0.5 1000], 'ValueChangedFcn', @(~, ~) app.updateDrive(), ...
                'Tooltip', 'nominal loudspeaker impedance [ohm]');
            uilabel(rg, 'Text', 'Power limit [W]', 'Tooltip', 'loudspeaker power limit');
            h.spkP = uieditfield(rg, 'numeric', 'Limits', [1e-4 1000], 'ValueChangedFcn', @(~, ~) app.updateDrive(), ...
                'Tooltip', 'power limit [W]: excitation is refused above this estimated power');
            r = r + 1; h.drive = uilabel(left, 'Text', '', 'FontSize', 11, 'WordWrap', 'on');
            h.drive.Layout.Row = r; h.drive.Layout.Column = 1;
            r = r + 1; rg = app.rowGrid(left, r, {'1x', '1x', 96});
            h.start = uibutton(rg, 'Text', 'START measurement', 'BackgroundColor', [0.75 0.9 0.75], ...
                'FontWeight', 'bold', 'ButtonPushedFcn', @(~, ~) app.onStart());
            h.stop = uibutton(rg, 'Text', 'STOP', 'BackgroundColor', [0.95 0.7 0.7], 'FontWeight', 'bold', ...
                'ButtonPushedFcn', @(~, ~) app.onStop());
            h.background = uibutton(rg, 'Text', 'Background', 'ButtonPushedFcn', @(~, ~) app.onBackground(), ...
                'Tooltip', 'background noise: 2 s recording without excitation');
            % ---------------- tube configuration
            r = r + 1; app.header(left, r, 'IMPEDANCE TUBE   (lengths in mm)');
            r = r + 1; rg = app.rowGrid(left, r, {84, '1x', 56, '1x', 50, '1x'});
            cb = @(~, ~) app.onTubeChanged();
            uilabel(rg, 'Text', 'Diameter [mm]', 'Tooltip', 'INNER diameter of the tube');
            h.tubeD = uieditfield(rg, 'numeric', 'Limits', [1 500], 'ValueDisplayFormat', '%.10g', ...
                'Tooltip', 'inner diameter of the tube [mm]', 'ValueChangedFcn', cb);
            uilabel(rg, 'Text', 'T [degC]', 'Tooltip', 'air temperature');
            h.temp = uieditfield(rg, 'numeric', 'Limits', [-20 60], 'Tooltip', 'air temperature [degC]', 'ValueChangedFcn', cb);
            uilabel(rg, 'Text', 'p [kPa]', 'Tooltip', 'static air pressure');
            h.pres = uieditfield(rg, 'numeric', 'Limits', [50 120], 'ValueDisplayFormat', '%.6g', ...
                'Tooltip', 'static air pressure [kPa]', 'ValueChangedFcn', cb);
            % distances between clearly defined points (port centres, specimen faces), in the
            % order of the tube (loudspeaker on the left); empty ('?') = not measured yet.
            % See the "Tube setup" tab for the drawing.
            tip = 'distance between microphone PORT CENTRES (centre of the port hole), in mm';
            nm = '  (empty = not measured: specimen results R, tau, Zt, TL disabled)';
            dTips = {['s1, upstream spacing: ' tip], ...
                ['L1: from the centre of port M2 to the FRONT face of the specimen (the face towards the loudspeaker), in mm' nm], ...
                ['d: specimen thickness, from the front face to the rear face, in mm (0 for a thin screen)' nm], ...
                ['L2: from the REAR face of the specimen (towards the termination) to the centre of port M3, in mm' nm], ...
                ['s2, downstream spacing: ' tip]};
            dNames = {'s1: M1-M2', 'L1: M2-front', 'd: thickness', 'L2: rear-M3', 's2: M3-M4'};
            r = r + 1; rg = app.rowGrid(left, r, repmat({'1x'}, 1, 5));
            for i = 1:5
                uilabel(rg, 'Text', dNames{i}, 'HorizontalAlignment', 'center', 'FontSize', 11, 'Tooltip', dTips{i});
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
            r = r + 1; h.fLimits = uilabel(left, 'Text', '', 'FontSize', 11, 'WordWrap', 'on', 'VerticalAlignment', 'top');
            h.fLimits.Layout.Row = r; h.fLimits.Layout.Column = 1;
            % ---------------- calibration
            r = r + 1; app.header(left, r, 'CALIBRATION');
            r = r + 1; rg = app.rowGrid(left, r, {'1x', '1x'});
            h.loadCal = uibutton(rg, 'Text', 'Load calibration...', 'ButtonPushedFcn', @(~, ~) app.onLoadCal());
            h.runCal = uibutton(rg, 'Text', 'Run switching cal.', 'ButtonPushedFcn', @(~, ~) app.onRunCal());
            r = r + 1; rg = app.rowGrid(left, r, {76, '1x'});
            uilabel(rg, 'Text', 'Calibration');
            h.calLabel = uilabel(rg, 'Text', 'none (results not valid)', 'FontColor', [0.6 0 0]);
            % ---------------- results
            r = r + 1; app.header(left, r, 'RESULTS');
            r = r + 1; rg = app.rowGrid(left, r, {'1x', '1x'});
            h.save = uibutton(rg, 'Text', 'Save measurement + export', 'ButtonPushedFcn', @(~, ~) app.onSave());
            h.reprocess = uibutton(rg, 'Text', 'Re-process (config/cal changed)', 'ButtonPushedFcn', @(~, ~) app.onReprocess());
            assert(r == numel(rowH), 'layout: rowH must list exactly one height per left-panel row');

            % ---------------- tabs (right column) + footer: version and source code link
            right = uigridlayout(g, [2 1], 'RowHeight', {'1x', 18}, 'RowSpacing', 2, 'Padding', [0 0 0 0]);
            right.Layout.Row = 1; right.Layout.Column = 2;
            foot = uigridlayout(right, [1 3], 'ColumnWidth', {'1x', 'fit', 'fit'}, 'Padding', [4 0 4 0], 'ColumnSpacing', 6);
            foot.Layout.Row = 2; foot.Layout.Column = 1;
            [swv, swi] = tim.app.softwareVersion();
            h.version = uilabel(foot, 'Text', swv, 'FontSize', 10, 'FontColor', [0.45 0.45 0.45], ...
                'Tooltip', 'software version (stored with every measurement and calibration)');
            uilabel(foot, 'Text', 'Source code:', 'FontSize', 10, 'FontColor', [0.45 0.45 0.45]);
            h.repoLink = uihyperlink(foot, 'Text', swi.repository, 'URL', swi.repository, 'FontSize', 10, ...
                'Tooltip', 'opens in the system web browser - private repository: sign in to GitHub with an account that has access');
            tabs = uitabgroup(right);
            tabs.Layout.Row = 1; tabs.Layout.Column = 1;
            t = uitab(tabs, 'Title', 'Log');
            tg = uigridlayout(t, [1 1]);
            h.log = uitextarea(tg, 'Editable', 'off', 'FontName', 'Consolas');
            % connection: checklist of every step, one card per channel, details table
            t = uitab(tabs, 'Title', 'Connection'); h.connTab = t;
            tg = uigridlayout(t, [4 1], 'RowHeight', {24, 276, 142, '1x'}, 'RowSpacing', 6);
            h.connHead = uilabel(tg, 'Text', 'Press "Connect + TEDS": every step of the connection is checked here.', ...
                'FontWeight', 'bold', 'FontSize', 13);
            pc = uipanel(tg, 'Title', 'Connection checklist', 'FontWeight', 'bold');
            app.ConnList = tim.gui.Checklist(pc, app.connKeys(), app.connLabels(), struct('LabelWidth', 270));
            gc = uigridlayout(tg, [1 4], 'ColumnSpacing', 8, 'Padding', [0 0 0 0]);
            for c = 1:4
                pnl = uipanel(gc);
                g2 = uigridlayout(pnl, [5 2], 'RowHeight', {24, 20, 20, 20, 20}, 'ColumnWidth', {16, '1x'}, ...
                    'Padding', [6 4 6 4], 'RowSpacing', 2, 'ColumnSpacing', 6);
                hd = uilabel(g2, 'Text', sprintf('  ch%d', c), 'FontWeight', 'bold', 'FontColor', 'w', ...
                    'BackgroundColor', P.ch(c, :));
                hd.Layout.Row = 1; hd.Layout.Column = [1 2];
                card = struct('head', hd, 'lamp', uilamp(g2, 'Color', P.idle), ...
                    'state', uilabel(g2, 'Text', 'not connected', 'FontWeight', 'bold'));
                card.lamp.Layout.Row = 2; card.lamp.Layout.Column = 1;
                card.state.Layout.Row = 2; card.state.Layout.Column = 2;
                for k = 3:5
                    l = uilabel(g2, 'Text', '', 'FontSize', 11, 'FontColor', [0.3 0.3 0.3]);
                    l.Layout.Row = k; l.Layout.Column = [1 2];
                    card.(sprintf('line%d', k - 2)) = l;
                end
                h.card(c) = card;
            end
            h.chanTable = uitable(tg);
            % tube setup: 3D model that follows the IMPEDANCE TUBE fields
            t = uitab(tabs, 'Title', 'Tube setup'); h.tubeTab = t;
            tg = uigridlayout(t, [2 1], 'RowHeight', {28, '1x'}, 'RowSpacing', 2);
            bar = uigridlayout(tg, [1 8], 'ColumnWidth', {80, 60, 100, 60, 16, 110, 100, '1x'}, ...
                'Padding', [4 2 4 2], 'ColumnSpacing', 6);
            views = {'Default', 'default'; 'Side', 'side'; 'Perspective', 'perspective'; 'Top', 'top'};
            for i = 1:4
                uibutton(bar, 'Text', views{i, 1}, 'ButtonPushedFcn', @(~, ~) app.tubeView(views{i, 2}), ...
                    'Tooltip', 'viewpoint (rotate / zoom freely with the toolbar of the drawing)');
            end
            uilabel(bar, 'Text', '');
            h.secChk = uicheckbox(bar, 'Text', 'Section view', 'Value', true, ...
                'Tooltip', 'remove the half towards the viewer: bore, specimen and microphone tips visible', ...
                'ValueChangedFcn', @(~, ~) app.onTubeChanged());
            h.dimChk = uicheckbox(bar, 'Text', 'Dimensions', 'Value', true, ...
                'ValueChangedFcn', @(~, ~) app.onTubeChanged());
            h.tubeInfo = uilabel(bar, 'Text', '', 'FontSize', 11, 'FontColor', [0.3 0.3 0.3]);
            h.axTube3D = uiaxes(tg);
            axtoolbar(h.axTube3D, {'rotate', 'zoomin', 'zoomout', 'pan', 'restoreview'});
            % waveforms: one graph per channel (shared time axis), also used for the live view
            t = uitab(tabs, 'Title', 'Waveforms'); h.waveTab = t;
            tg = uigridlayout(t, [4 1], 'RowSpacing', 2);
            for c = 1:4
                ax = uiaxes(tg); h.axW(c) = ax;
                h.waveLine(c) = plot(ax, NaN, NaN, '-', 'Color', P.ch(c, :), 'LineWidth', 0.8);
                ylabel(ax, sprintf('ch%d [Pa]', c)); grid(ax, 'on');
                if c < 4, ax.XTickLabel = {}; else, xlabel(ax, 'Time [s]'); end
            end
            linkaxes(h.axW, 'x');
            names = {'Spectrum', 'Relative responses', 'Calibration', 'R / tau', 'Transfer impedance', ...
                'Transmission loss', 'Validity'};
            keys = {'axSpec', 'axH', 'axCal', 'axR', 'axZ', 'axTL', 'axV'};
            for i = 1:numel(names)
                t = uitab(tabs, 'Title', names{i});
                if strcmp(keys{i}, 'axCal')
                    % calibration tab: step instruction, 3D set-up (the Tube setup model
                    % in its calibration state, animated microphone moves), list of the
                    % operator steps with their quality, C_k curves
                    tg = uigridlayout(t, [3 2], 'RowHeight', {58, '3x', '2x'}, 'ColumnWidth', {700, '1x'}, ...
                        'RowSpacing', 4, 'ColumnSpacing', 6);
                    h.calText = uilabel(tg, 'Text', '', 'WordWrap', 'on', 'FontSize', 12, 'VerticalAlignment', 'top');
                    h.calText.Layout.Row = 1; h.calText.Layout.Column = [1 2];
                    h.axCalSetup = uiaxes(tg); h.axCalSetup.Layout.Row = 2; h.axCalSetup.Layout.Column = [1 2];
                    axtoolbar(h.axCalSetup, {'rotate', 'zoomin', 'zoomout', 'pan', 'restoreview'});
                    pcal = uipanel(tg, 'Title', 'Calibration steps (quality of every measurement)', 'FontWeight', 'bold');
                    pcal.Layout.Row = 3; pcal.Layout.Column = 1;
                    app.CalList = tim.gui.Checklist(pcal, {}, {}, ...
                        struct('LabelWidth', 245, 'RowHeight', 21, 'FontSize', 11));
                    h.calTab = t;
                else
                    tg = uigridlayout(t, [1 1]);
                end
                h.(keys{i}) = uiaxes(tg);
                if strcmp(keys{i}, 'axCal'), h.axCal.Layout.Row = 3; h.axCal.Layout.Column = 2; end
            end
            h.tabs = tabs;
            tabs.SelectionChangedFcn = @(~, ev) app.onTabChanged(ev);
            t = uitab(tabs, 'Title', 'Equations');
            tim.gui.equationsPanel(t);
            h.cal3D = []; h.calPaths = gobjects(0); h.calHi = gobjects(0);
            app.H = h;
            app.setCalText([], '', '');      % the 3D model is drawn when the tab is opened or at the first step
        end

        function k = connKeys(~)
            k = {'gen', 'lanxi', 'idle', 'open', 'teds', 'setup', 'sens', 'settle', 'signal'};
        end
        function l = connLabels(~)
            l = {'Function generator 33220A (SCPI)', 'LAN-XI module (REST)', 'LAN-XI recorder state Idle', ...
                'Open recorder', 'TEDS transducer detection', 'Channel setup -> streaming', ...
                'Microphone sensitivities', 'Settling (CCLD + high-pass)', 'Signal check (no excitation)'};
        end

        function header(~, parent, row, txt)
            % section title; the text sits at the bottom of its taller row (gap above the section)
            l = uilabel(parent, 'Text', txt, 'FontWeight', 'bold', 'VerticalAlignment', 'bottom');
            l.Layout.Row = row; l.Layout.Column = 1;
        end
        function rg = rowGrid(~, parent, row, widths)
            % one row of the left panel: nested 1 x n grid; components created in it
            % fill the cells from left to right
            rg = uigridlayout(parent, [1 numel(widths)], 'ColumnWidth', widths, 'RowHeight', {'1x'}, ...
                'Padding', [0 0 0 0], 'ColumnSpacing', 4);
            rg.Layout.Row = row; rg.Layout.Column = 1;
        end

        %% ----------------------------------------------------------- state
        function refreshFromCfg(app)
            c = app.Cfg; h = app.H;
            h.mode.Value = c.mode;
            if any(strcmp(c.excitation.mode, h.exMode.Items))
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
            app.excitationToUi(h.exMode.Value);
            h.amp.Value = c.excitation.sweep.amplitudeVpp / 2;
            h.amp.Tooltip = sprintf(['generator open-circuit peak voltage [Vpk]; safety limit %.3g Vpk ' ...
                '(config generator.maxVpp = %.3g Vpp)'], c.generator.maxVpp / 2, c.generator.maxVpp);
            items = c.amplifier.knownModels; if ischar(items), items = {items}; end
            if ~any(strcmp(items, 'none (direct drive)')), items = [{'none (direct drive)'}, items(:).']; end
            if ~isempty(c.amplifier.model) && ~any(strcmp(items, c.amplifier.model)), items{end+1} = c.amplifier.model; end
            h.ampModel.Items = items;
            if isempty(c.amplifier.model), h.ampModel.Value = items{1}; else, h.ampModel.Value = c.amplifier.model; end
            gf = c.amplifier.gainFactor; if ~(gf > 0), gf = 1; end
            h.ampGain.Value = gf;
            app.onAmpModel();
            app.onTubeChanged();
            if isempty(app.Session), app.refreshCards(); end
        end

        function excitationToUi(app, mode)
            % frequency range / sweep time or number of steps / repetitions of the
            % selected excitation mode -> fields (stepped: "Steps" instead of "Sweep time")
            h = app.H; ex = app.Cfg.excitation;
            if strcmp(mode, 'stepped')
                s = ex.stepped;
                h.durLabel.Text = 'Steps';
                h.dur.Limits = [1 400]; h.dur.RoundFractionalValues = 'on'; h.dur.Value = s.nPoints;
                h.dur.Tooltip = sprintf(['number of frequency steps (%s spacing); each step: %g s settling + %g s ' ...
                    'recording'], s.spacing, s.settleTime, s.recordTime);
            else
                s = ex.sweep;
                h.durLabel.Text = 'Sweep time [s]';
                h.dur.RoundFractionalValues = 'off'; h.dur.Limits = [0.001 500]; h.dur.Value = s.duration;
                h.dur.Tooltip = 'duration of one sweep [s]';
            end
            h.fRange.Value = sprintf('%g %g', s.fStart, s.fStop);
            h.reps.Value = s.repetitions;
        end

        function uiToExcitation(app, mode)
            % fields -> app.Cfg.excitation.(mode); errors on invalid input
            h = app.H;
            fr = sscanf(h.fRange.Value, '%f');
            if numel(fr) ~= 2 || any(fr <= 0) || fr(2) <= fr(1)
                error('tim:gui:input', 'Enter "f_start f_stop" in Hz.');
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
            % keep what was typed for the previous mode, then show the new mode's values
            try
                app.uiToExcitation(previous);
            catch
            end
            app.excitationToUi(app.H.exMode.Value);
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
            % live check of the tube entries: limits, consistency, drawing
            app.CalDirty = true;                 % calibration model follows the geometry
            [geom, env, msgs] = app.readTube();
            try
                air = tim.acoustics.airProperties(env);
                lim = tim.acoustics.frequencyLimits(geom.diameter, [geom.spacingUp geom.spacingDown], air);
                known = all(isfinite(geom.micPositions)) && isfinite(geom.xFront) && isfinite(geom.xRear);
                txt = sprintf('c = %.1f m/s.  Geometric range %.0f - %.0f Hz (s = %g / %g mm, (1,1) cut-on %.0f Hz).', ...
                    air.c, lim.fLower, lim.fUpper, app.toMm(geom.spacingUp), app.toMm(geom.spacingDown), lim.cutOn11);
                if ~known
                    txt = [txt ' Positions incomplete: boundary results (R, tau, Zt, TL) disabled.'];
                end
                if ~isempty(msgs), txt = [txt ' CHECK: ' strjoin(msgs, '; ')]; end
                app.H.fLimits.Text = txt;
                if isempty(msgs), app.H.fLimits.FontColor = [0.2 0.2 0.2]; else, app.H.fLimits.FontColor = [0.75 0 0]; end
                if known
                    info = sprintf(['Distances between port CENTRES and specimen FACES.  Geometric range %.0f - %.0f Hz, ' ...
                        '(1,1) cut-on %.0f Hz.  Microphones coloured by the LAN-XI channel in the port.'], ...
                        lim.fLower, lim.fUpper, lim.cutOn11);
                else
                    info = ['SCHEMATIC - L1, d and L2 not entered: specimen results (R, tau, Zt, TL) are disabled.  ' ...
                        sprintf('Geometric range %.0f - %.0f Hz.', lim.fLower, lim.fUpper)];
                end
                app.H.tubeInfo.Text = info;
                tim.gui.drawTube3D(app.H.axTube3D, geom, app.drawingDims(), app.homeMapping(), ...
                    struct('section', app.H.secChk.Value, 'dimensions', app.H.dimChk.Value));
            catch err
                app.H.fLimits.Text = ['CHECK: ' err.message]; app.H.fLimits.FontColor = [0.75 0 0];
            end
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
            % live estimate of the loudspeaker drive from amplitude x gain
            c = app.Cfg;
            c.amplifier.model = app.H.ampModel.Value;
            c.amplifier.gainFactor = app.H.ampGain.Value;
            c.loudspeaker.impedance_ohm = app.H.spkZ.Value; c.loudspeaker.maxPower_W = app.H.spkP.Value;
            d = tim.app.driveEstimate(c, 2 * app.H.amp.Value);
            lim = c.generator.maxVpp / 2;
            if isnan(d.P_W)
                txt = sprintf('Generator %.3g Vpk (limit %.3g Vpk). Enter the amplifier gain!', app.H.amp.Value, lim);
                col = [0.75 0 0];
            else
                txt = sprintf('Generator %.3g Vpk (limit %.3g Vpk) -> loudspeaker %.3g Vpk, %.3g mA, %.3g mW (limit %.4g mW)', ...
                    app.H.amp.Value, lim, d.Vspk_pk, 1e3 * d.Ipk, 1e3 * d.P_W, 1e3 * d.limit_W);
                if d.P_W > d.limit_W || app.H.amp.Value > lim, col = [0.75 0 0]; txt = [txt '  EXCEEDS LIMIT']; else, col = [0.2 0.2 0.2]; end
            end
            app.H.drive.Text = txt; app.H.drive.FontColor = col;
        end

        function readCfgFromUi(app)
            h = app.H;
            app.Cfg.mode = h.mode.Value;
            app.Cfg.excitation.mode = h.exMode.Value;
            % f start/stop, sweep time or number of steps, repetitions of the selected mode
            % (before 2026-10-09 these fields reached the sweep settings only)
            app.uiToExcitation(h.exMode.Value);
            app.Cfg.excitation.sweep.amplitudeVpp = 2 * h.amp.Value;      % GUI in Vpk, config/generator in Vpp
            app.Cfg.excitation.stepped.amplitudeVpp = 2 * h.amp.Value;
            app.Cfg.excitation.noise.amplitudeVpp = 2 * h.amp.Value;
            app.Cfg.amplifier.model = h.ampModel.Value;
            app.Cfg.amplifier.gainFactor = h.ampGain.Value;
            app.Cfg.amplifier.gain_dB = 20 * log10(h.ampGain.Value);
            app.Cfg.amplifier.gainSetting = '';
            app.Cfg.amplifier.knownModels = h.ampModel.Items;
            app.Cfg.loudspeaker.impedance_ohm = h.spkZ.Value;
            app.Cfg.loudspeaker.maxPower_W = h.spkP.Value;
            [geom, env, msgs] = app.readTube();
            if ~isempty(msgs)
                error('tim:gui:geometry', 'Tube geometry: %s', strjoin(msgs, '; '));
            end
            app.Cfg.geometry = geom; app.Cfg.environment = env;
            tim.app.validateConfig(app.Cfg);
        end

        function setStatus(app, txt, ok)
            app.H.status.Text = txt;
            if ok, app.H.status.FontColor = [0 0.5 0]; else, app.H.status.FontColor = [0.6 0 0]; end
        end

        function log(app, varargin)
            line = sprintf(varargin{:});
            app.appendLog(sprintf('[%s] %s', char(datetime('now'), 'HH:mm:ss'), line));
        end
        function appendLog(app, line)
            if ~isvalid(app.H.log), fprintf('%s\n', line); return; end   % window closed
            v = app.H.log.Value;
            if ischar(v), v = {v}; end
            v{end+1} = line;
            if numel(v) > 500, v = v(end-499:end); end
            app.H.log.Value = v;
            scroll(app.H.log, 'bottom');
            drawnow limitrate
        end

        function run(app, fn, busyWhat)
            % run an action with error reporting; never leaves the output on.
            % busyWhat (optional): lock the GUI while the action runs - every
            % input and button is disabled except the STOP button, which is
            % relabelled "ABORT <busyWhat>".
            if nargin < 3, busyWhat = ''; end
            if app.Busy
                return      % an action is already running (no re-entrance)
            end
            if ~isempty(busyWhat)
                app.setBusy(true, busyWhat);
                unlock = onCleanup(@() safeUnlock(app));
            end
            try
                fn();
            catch err
                if ~isvalid(app), return; end     % closed meanwhile (second close request)
                if any(strcmp(err.identifier, {'tim:session:stopped', 'tim:gui:abort'}))
                    app.log('%s aborted by the operator: %s', busyWhat, err.message);
                    msg = sprintf('%s aborted. Generator output is OFF.', busyWhat);
                    icon = 'info';
                else
                    app.log('ERROR: %s', err.message);
                    msg = err.message; icon = 'error';
                end
                if ~isempty(app.Session) && ~isempty(app.Session.Gen)
                    try, app.Session.Gen.outputOff(); catch, end
                end
                if isvalid(app.Fig) && ~app.CloseAfterBusy     % window may be closing
                    uialert(app.Fig, msg, 'Stopped', 'Icon', icon);
                end
            end
            if isvalid(app) && app.CloseAfterBusy          % close requested while busy
                clear unlock
                app.closeNow();
            end
        end

        function setBusy(app, tf, what)
            % Disable / restore all interactive controls (tabs stay usable).
            if isempty(app.Fig) || ~isvalid(app.Fig)
                app.Busy = false; return            % window closed during the action
            end
            h = app.H;
            names = {'mode', 'loadCfg', 'saveCfg', 'connect', 'disconnect', 'exMode', 'fRange', 'dur', 'amp', 'reps', ...
                'ampModel', 'ampGain', 'spkZ', 'spkP', 'start', 'background', 'tubeD', 's1', 'L1', 'dTh', 'L2', 's2', ...
                'temp', 'pres', 'loadCal', 'runCal', 'save', 'reprocess'};
            if tf
                app.Busy = true;
                app.EnableState = struct();
                for i = 1:numel(names)
                    app.EnableState.(names{i}) = h.(names{i}).Enable;
                    h.(names{i}).Enable = 'off';
                end
                h.stop.Text = sprintf('ABORT %s', what);
                h.stop.Enable = 'on';
                app.setStatus(sprintf('BUSY: %s (only ABORT is active)', what), false);
            else
                if ~isempty(app.EnableState)
                    for i = 1:numel(names)
                        h.(names{i}).Enable = app.EnableState.(names{i});
                    end
                end
                h.stop.Text = 'STOP';
                app.Busy = false;
                if ~isempty(app.Session) && app.Session.Prepared
                    app.setStatus(sprintf('ready (%s)', app.Cfg.mode), true);
                end
            end
            drawnow;
        end

        function liveUpdate(app)
            % Called for every received data block: live waveforms of the last
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
                for c = 1:4
                    set(app.H.waveLine(c), 'XData', t, 'YData', y(:, c));
                    spl = 20 * log10(sqrt(mean(x(:, c).^2, 'omitnan')) / sens(c) / 2e-5);
                    title(app.H.axW(c), sprintf('ch%d   %.1f dB SPL (last 0.5 s)', c, spl), 'FontWeight', 'normal');
                    ylabel(app.H.axW(c), sprintf('ch%d [%s]', c, unit));
                end
                app.H.axW(1).XLim = [t(1) 0];
                app.LiveCount = app.LiveCount + 1;
                xlabel(app.H.axW(4), sprintf('Time relative to now [s]   -   LIVE, %.1f s recorded (%s)', total, app.Session.Status));
            catch
            end
            drawnow('limitrate');
        end

        %% ----------------------------------------------------------- callbacks
        function onSaveConfig(app)
            app.run(@() app.doSaveConfig());
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
            [f, p] = uigetfile('*.json', 'Configuration', fullfile(tim.app.projectRoot(), 'config'));
            if isequal(f, 0), return; end
            app.run(@() app.doLoadConfig(fullfile(p, f)));
        end
        function doLoadConfig(app, file)
            app.Cfg = tim.app.loadConfig(file);
            app.refreshFromCfg();
            app.log('Loaded configuration %s', file);
        end

        function onConnect(app)
            app.run(@() app.doConnect());
        end
        function doConnect(app)
            app.readCfgFromUi();
            app.disconnect();
            % connection checklist: every step is shown while it runs (the
            % animated icon keeps turning during the slow LAN-XI setup)
            app.ConnList.reset();
            app.H.tabs.SelectedTab = app.H.connTab;
            app.H.connHead.Text = sprintf('Connecting (%s mode) ...', app.Cfg.mode);
            app.H.connHead.FontColor = [0.1 0.1 0.1];
            app.refreshCards();
            s = tim.app.MeasurementSession(app.Cfg);
            s.StatusCallback = @(line) app.appendLog(line);
            s.BlockCallback = @() app.liveUpdate();       % live waveforms + keeps STOP responsive
            s.ProgressCallback = @(key, state, detail) app.onProgress(key, state, detail);
            L = app.Cfg.ui.language; yes = tim.app.msg(L, 'yesPlay');
            if strcmp(app.Cfg.mode, 'hardware')       % no real loudspeaker in simulation
                s.ExcitationConfirm = @(msg) strcmp(app.ask(msg, tim.app.msg(L, 'confirmTitle'), ...
                    {yes, tim.app.msg(L, 'cancel')}, 2, 2, 'warning'), yes);
            end
            app.Session = s;
            s.connect();
            s.prepareAcquisition();
            chk = s.signalCheck(1);                    % 1 s without excitation: level / fault flags per channel
            app.setStatus(sprintf('ready (%s)', app.Cfg.mode), true);
            m = s.Mics;
            app.H.chanTable.Data = table([m.channel].', [m.position].', {m.model}.', ...
                1e3 * [m.sensitivity_VperPa].', {m.sensitivitySource}.', [m.tedsSerial].', ...
                [chk.spl_dB].', {chk.text}.', ...
                'VariableNames', {'Channel', 'Position', 'Model', 'Sens_mV_per_Pa', 'Source', 'TEDS_serial', ...
                'Level_dB_SPL', 'Signal_check'});
            app.refreshCards(chk);
            states = app.ConnList.States;
            if any(strcmp(states, 'fail'))
                app.H.connHead.Text = 'Connected, but a check FAILED - see the red items below.';
                app.H.connHead.FontColor = tim.gui.palette().fail;
            elseif any(strcmp(states, 'warn'))
                app.H.connHead.Text = 'Connected with warnings - see the orange items below.';
                app.H.connHead.FontColor = 0.75 * tim.gui.palette().warn;
            else
                app.H.connHead.Text = 'Connected - all checks passed.';
                app.H.connHead.FontColor = tim.gui.palette().ok;
            end
            if ~isempty(s.Calibration), app.showCal(s.Calibration); end
            app.CalDirty = true;                 % calibration labels pick up the TEDS serials
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
                card.head.Text = sprintf('  ch%d  ->  port M%d', c, m.position);
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
                    card.line2.Text = sprintf('sensitivity %.4g mV/Pa (%s)', 1e3 * m.sensitivity_VperPa, m.sensitivitySource);
                    if ~any(strcmp(m.sensitivitySource, {'certificate', 'teds'}))
                        st = 'warn'; notes{end + 1} = 'nominal sensitivity'; %#ok<AGROW>
                    end
                    if m.serialMismatch
                        st = 'warn'; notes{end + 1} = 'TEDS serial differs from config'; %#ok<AGROW>
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
                        card.line3.FontColor = [0.3 0.3 0.3];
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
            end
            drawnow;
        end

        function onStart(app)
            if isempty(app.Session) || ~app.Session.Prepared
                uialert(app.Fig, 'Connect and prepare the instruments first.', 'Not ready'); return
            end
            app.run(@() app.doStart(), 'measurement');
        end
        function doStart(app)
            app.readCfgFromUi();
            app.syncSession();
            app.log('START: %s measurement (explicit user start; output armed).', app.Cfg.excitation.mode);
            app.H.tabs.SelectedTab = app.H.waveTab;       % live view
            app.LiveLast = 0;
            m = app.Session.measure(app.Cfg.excitation.mode);
            app.LastMeas = m;
            app.plotWave(m);
            app.process();
            if ~m.integrityOk
                uialert(app.Fig, 'Data-integrity problems were detected - see log.', 'Integrity', 'Icon', 'warning');
            end
        end

        function onStop(app)
            if ~isempty(app.Session)
                app.Session.requestStop();
                try, app.Session.Gen.outputOff(); catch, end
                app.log('%s requested: output switched off.', app.H.stop.Text);
            end
        end

        function onBackground(app)
            if isempty(app.Session) || ~app.Session.Prepared
                uialert(app.Fig, 'Connect and prepare the instruments first.', 'Not ready'); return
            end
            app.run(@() app.doBackground(), 'background');
        end
        function doBackground(app)
            m = app.Session.measureBackground(2);
            app.LastMeas = m; app.LastRes = [];
            app.plotWave(m);
            integ = m.channelInfo{1}.integrity;
            app.log('Background: integrity %d. %s %s', integ.ok, strjoin(integ.fatal, ' | '), strjoin(integ.warnings, ' | '));
        end

        function onLoadCal(app)
            [f, p] = uigetfile('*.mat', 'Calibration', tim.app.resolvePath(app.Cfg.output.calibrationDir));
            if isequal(f, 0), return; end
            app.run(@() app.doLoadCal(fullfile(p, f)));
        end
        function doLoadCal(app, file)
            S = load(file, 'cal');
            app.Cfg.calibration.file = file;
            if ~isempty(app.Session), app.Session.Calibration = S.cal; end
            app.showCal(S.cal);
        end

        function onRunCal(app)
            if isempty(app.Session) || ~app.Session.Prepared
                uialert(app.Fig, 'Connect and prepare the instruments first.', 'Not ready'); return
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

        function onAmpModel(app)
            % direct drive -> gain fixed to x1; a typed model is added to the list
            h = app.H;
            v = h.ampModel.Value;
            if ~isempty(v) && ~any(strcmp(h.ampModel.Items, v))
                h.ampModel.Items{end+1} = v;
            end
            direct = startsWith(lower(v), 'none');
            if direct, h.ampGain.Value = 1; end
            h.ampGain.Enable = matlab.lang.OnOffSwitchState(~direct);
            if ~direct
                h.ampGain.Tooltip = sprintf(['voltage gain of "%s" as a multiplier (x10 = 20 dB). ' ...
                    'Generator Vpk x gain = amplifier output; used for the loudspeaker power check.'], v);
            end
            app.updateDrive();
        end

        function doRunCal(app)
            app.readCfgFromUi();
            app.syncSession();
            % operator steps (same order as tim.app.runCalibration): preparation
            % checklist, per channel config I (+ repeat) + config II, return mics
            c = app.Cfg; ref = c.analysis.refChannel; ab = c.calibration.positions;
            dSec = c.geometry.xRear - c.geometry.xFront; secTxt = '';
            if isfinite(dSec) && dSec > 0, secTxt = sprintf('%g mm ', round(1e3 * dSec, 3)); end
            keys = {'prep'}; labels = {sprintf('Prepare: EMPTY %ssection, absorbing end', secTxt)};
            for k = setdiff(1:4, ref)
                keys{end + 1} = sprintf('ch%d_I', k); %#ok<AGROW>
                labels{end + 1} = sprintf('ch%d  config I    (ch%d in M%d, ch%d in M%d)', k, ref, ab(1), k, ab(2)); %#ok<AGROW>
                if c.calibration.repeatConfigI
                    keys{end + 1} = sprintf('ch%d_Irep', k); %#ok<AGROW>
                    labels{end + 1} = sprintf('ch%d  config I    repeated (re-mounted)', k); %#ok<AGROW>
                end
                keys{end + 1} = sprintf('ch%d_II', k); %#ok<AGROW>
                labels{end + 1} = sprintf('ch%d  config II   (interchanged)', k); %#ok<AGROW>
            end
            doneLbl = 'Microphones back to M1-M4';
            if c.calibration.verifyEmptySection, doneLbl = 'Mics back to M1-M4 + empty-tube check'; end
            keys{end + 1} = 'done'; labels{end + 1} = doneLbl;
            keys{end + 1} = 'mount'; labels{end + 1} = 'Mount the specimen section again';
            app.CalKeys = keys; app.CalList.rebuild(keys, labels);
            app.CalStep = 0; app.CalSteps = numel(keys);
            app.CalMap = app.homeMapping();
            app.CalDirty = true;                 % fresh model: current geometry and serials
            try
                [cal, file] = tim.app.runCalibration(app.Session, struct( ...
                    'prompt', @(msg, mapping) app.calStep(msg, mapping), 'report', @(q) app.calReport(q)));
            catch err
                app.stopPulse();
                for k = app.CalList.runningKeys()
                    app.CalList.set(k{1}, 'fail', err.message);
                end
                rethrow(err);
            end
            app.Cfg.calibration.file = file;
            app.showCal(cal);
        end

        function calStep(app, msg, mapping)
            % One operator step of the switching calibration: the diagram shows
            % the microphones moving to their new ports, the calibration ports
            % pulse, then (hardware) the operator confirms or (simulation) the
            % virtual microphones are moved.
            app.CalStep = app.CalStep + 1;
            key = app.CalKeys{min(app.CalStep, end)};
            stepText = sprintf('Calibration step %d of %d', app.CalStep, app.CalSteps);
            from = app.CalMap;
            app.drawCalSetup(mapping, msg, stepText, from);
            app.H.tabs.SelectedTab = app.H.calTab;
            app.CalList.set(key, 'run', 'operator: place the microphones as shown');
            app.animateCalMics(from, mapping);
            app.CalMap = mapping;
            if strcmp(app.Cfg.mode, 'hardware')
                L = app.Cfg.ui.language; done = tim.app.msg(L, 'calDoneButton');
                app.startPulse();
                sel = app.ask(sprintf('%s\n\n%s\n(see the diagram in the Calibration tab)', stepText, msg), ...
                    tim.app.msg(L, 'calStepTitle'), {done, tim.app.msg(L, 'abortButton')}, 1, 2, 'question');
                app.stopPulse();
                if ~strcmp(sel, done)
                    app.CalList.set(key, 'fail', 'aborted by the operator');
                    error('tim:gui:abort', 'Calibration aborted by user.');
                end
            else
                app.Session.setMicPositionsForSimulation(mapping);
            end
            if any(strcmp(key, {'prep', 'mount'}))
                app.CalList.set(key, 'ok', 'confirmed');
            elseif strcmp(key, 'done')
                if app.Cfg.calibration.verifyEmptySection
                    app.CalList.set(key, 'run', 'microphones back; empty-tube check (Test E) ...');
                else
                    app.CalList.set(key, 'ok', 'confirmed');
                end
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
                    txt = sprintf('%.0f%% bins OK, coh %.4f, SNR %.0f dB', ...
                        100 * q.fracOk, q.coherenceMedian, q.snrMedian_dB);
                    if ~q.integrityOk, txt = ['data integrity FAILED - ' txt]; end
                    app.CalList.set(key, st, txt);
                case 'channel'
                    txt = sprintf('  ->  C%d: %d/%d valid', q.channel, q.nValid, q.Nf);
                    if ~isempty(q.repeatability)
                        txt = sprintf('%s, re-mount %.2f dB/%.1f deg', txt, ...
                            q.repeatability.maxMag_dB, q.repeatability.maxPhase_deg);
                    end
                    app.CalList.appendDetail(key, txt);
                    if q.nValid < 0.9 * q.Nf && strcmp(app.CalList.state(key), 'ok')
                        app.CalList.set(key, 'warn');
                    end
                case 'verification'          % empty-section check (Test E), 'done' row
                    k = q.check;
                    if ~k.performed
                        st = 'ok'; if startsWith(k.text, 'skipped'), st = 'warn'; end
                        app.CalList.set(key, st, ['confirmed; empty-tube check ' k.text]);
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
                app.H.calText.Text = {sprintf(['Switching calibration: press "Run switching cal." - every step shows ' ...
                    'here which microphone goes into which port. Calibration ports M%d (a) and M%d (b) glow yellow.'], ab(1), ab(2)), ...
                    ['The original specimen section is mounted EMPTY (no specimen) and the tube ends in the absorbing termination. ' ...
                    'Each microphone stays on its own cable and LAN-XI input; only the microphone bodies are moved.']};
            else
                app.H.calText.Text = {sprintf('%s:  %s', stepText, msg), ['yellow glow = calibration ports a, b;  ' ...
                    'colour / label = DAQ channel of the microphone (it keeps its cable);  dashed = last moves']};
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
            % the calibration model is drawn the first time the tab is opened
            if ev.NewValue == app.H.calTab && app.CalDirty && ~app.Busy
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
            if isempty(app.LastMeas), uialert(app.Fig, 'Nothing measured yet.', 'Save'); return; end
            app.run(@() app.doSave());
        end
        function doSave(app)
            figs = struct();
            if ~isempty(app.LastRes)
                figs = tim.app.plotResults(app.LastRes, app.LastMeas, struct('Visible', 'off'));
            end
            d = tim.app.saveMeasurement(app.LastMeas, app.LastRes, app.Cfg, app.LastMeas.kind, figs);
            fc = struct2cell(figs); if ~isempty(fc), close(fc{:}); end
            app.log('Saved to %s', d);
        end

        function onReprocess(app)
            if isempty(app.LastMeas), return; end
            app.run(@() app.process());
        end

        %% ----------------------------------------------------------- display
        function process(app)
            cal = []; if ~isempty(app.Session), cal = app.Session.Calibration; end
            if ~strcmp(app.LastMeas.kind, 'background')
                app.LastRes = tim.app.processMeasurement(app.LastMeas, app.Cfg, cal);
                app.log('%s', app.LastRes.summary);
                for w = app.LastRes.calibration.context.warnings, app.log('CALIBRATION: %s', w{1}); end
                app.plotRes();
                if strcmp(app.LastMeas.kind, 'stepped'), app.plotSpectrum(app.LastMeas, app.LastRes); end
            end
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

        function plotWave(app, m)
            % one graph per channel, shared time axis, in Pa (voltage /
            % sensitivity); display high-pass 20 Hz removes the slow CCLD/DC
            % settling drift (raw data unchanged, stored in volts)
            P = tim.gui.palette();
            x = m.records{1}; t = (0:size(x, 1) - 1) / m.fs;
            [b, a] = butter(2, 20 / (m.fs / 2), 'high');
            xd = filtfilt(b, a, x - mean(x, 1));
            [y, unit, sens] = app.toPressure(xd, m.mics);
            for c = 1:4
                set(app.H.waveLine(c), 'XData', t, 'YData', y(:, c), 'Color', P.ch(c, :));
                pk = max(abs(y(:, c))); if ~(pk > 0), pk = 1; end
                app.H.axW(c).YLim = 1.1 * [-pk pk];
                ylabel(app.H.axW(c), sprintf('ch%d [%s]', c, unit));
                if strcmp(unit, 'Pa')
                    spl = 20 * log10(sqrt(mean(y(:, c).^2)) / 2e-5);
                    src = ''; if isfield(m.mics, 'sensitivitySource'), src = [' ' m.mics(c).sensitivitySource]; end
                    title(app.H.axW(c), sprintf('ch%d   peak %.3g Pa,  %.1f dB SPL rms   (%.4g mV/Pa%s)', ...
                        c, pk, spl, 1e3 * sens(c), src), 'FontWeight', 'normal');
                else
                    title(app.H.axW(c), sprintf('ch%d   peak %.3g mV  (no sensitivity: shown in volts)', c, pk), ...
                        'FontWeight', 'normal');
                end
            end
            app.H.axW(1).XLim = [0 t(end)];
            xlabel(app.H.axW(4), sprintf(['Time [s]   -   %s, %s.  p = voltage / sensitivity; raw data stored in V; ' ...
                'display high-passed at 20 Hz'], m.kind, m.timestamp));
            app.plotSpectrum(m);
        end

        function plotSpectrum(app, m, res)
            % Spectrum tab.
            %  sweep / noise / background: Welch PSD of repetition 1.
            %  stepped: the record holds one tone per step, so its PSD is a LINE
            %  spectrum (one narrow spike per step, level diluted by the number of
            %  steps). Shown instead: the level of every step and channel from the
            %  sine fit of the settled part (res.toneLevels) as markers at the step
            %  frequencies; dotted = residual noise in the fit bandwidth. Until
            %  processing has run (or if it failed) the PSD is drawn light grey
            %  with this explanation.
            if nargin < 3, res = []; end
            P = tim.gui.palette();
            ax = app.H.axSpec; cla(ax); hold(ax, 'on');
            names = {'ch1', 'ch2', 'ch3', 'ch4'};
            stepped = strcmp(m.kind, 'stepped');
            if stepped && ~isempty(res) && isfield(res, 'toneLevels')
                tl = res.toneLevels; hc = gobjects(1, 4);
                for c = 1:4
                    hc(c) = plot(ax, tl.f, tl.spl_dB(:, c), '-o', 'Color', P.ch(c, :), ...
                        'MarkerFaceColor', P.ch(c, :), 'MarkerSize', 5, 'LineWidth', 0.8);
                    plot(ax, tl.f, tl.noise_dB(:, c), ':', 'Color', P.ch(c, :), 'LineWidth', 0.8);
                end
                hn = plot(ax, NaN, NaN, ':', 'Color', P.grid);          % legend entry only
                hold(ax, 'off'); set(ax, 'XScale', 'log'); grid(ax, 'on');
                xlim(ax, [min(tl.f) / 1.2, max(tl.f) * 1.2]);
                xlabel(ax, 'Frequency [Hz]'); ylabel(ax, 'Tone level [dB SPL]');
                legend(ax, [hc hn], [names, {'noise in fit bandwidth'}], 'Location', 'best');
                title(ax, {sprintf('Stepped sine: level of each of the %d steps (sine fit of the settled part)', numel(tl.f)), ...
                    'The PSD of a stepped record is a line spectrum (one spike per step) and is not shown.'}, ...
                    'FontWeight', 'normal');
                return
            end
            x = m.records{1};
            p = tim.acq.voltsToPascal(x - mean(x, 1), m.mics, 'V');
            nfft = min(8192, 2^nextpow2(size(p, 1)));
            [Pxx, f] = pwelch(p, hann(nfft, 'periodic'), nfft / 2, nfft, m.fs);
            for c = 1:4
                if stepped, col = P.invalid; else, col = P.ch(c, :); end
                plot(ax, f, 10 * log10(Pxx(:, c) / 4e-10), 'Color', col, 'LineWidth', P.lineWidth);
            end
            hold(ax, 'off'); set(ax, 'XScale', 'log'); grid(ax, 'on'); xlim(ax, [20 m.fs / 2]);
            xlabel(ax, 'Frequency [Hz]'); ylabel(ax, 'PSD [dB re (20\muPa)^2/Hz]');
            if stepped
                legend(ax, 'off');
                title(ax, {'Stepped sine: PSD of the whole record = line spectrum (one spike per step)', ...
                    'Step levels are shown after processing.'}, 'FontWeight', 'normal');
            else
                legend(ax, names, 'Location', 'best');
                title(ax, '');                 % clear a previous stepped title
            end
        end

        function mk = stepMarkers(app, c, shape)
            % Stepped sine: results exist only at the step frequencies -> draw
            % markers (a plain line hides isolated valid steps and suggests
            % values between steps). Empty for sweep / noise (dense grid).
            mk = {};
            if isempty(app.LastRes) || ~strcmp(app.LastRes.kind, 'stepped'), return; end
            if nargin < 3, shape = 'o'; end
            mk = {'Marker', shape, 'MarkerSize', 4};
            if nargin >= 2 && ~isempty(c), mk = [mk, {'MarkerFaceColor', c, 'MarkerEdgeColor', c}]; end
        end

        function [thick, txt] = thickSpecimen(~, a)
            % The thin-element model (Zt, TL from Zt) is meaningless for a thick
            % specimen: for the empty 75 mm section Zt/rho c = 2j tan(kd/2) has a
            % pole at kd = pi (2.29 kHz). Its curves are then not drawn (they
            % would hide TL_tau); the velocity-mismatch mask rejects them anyway.
            thick = false; txt = '';
            if isfield(a.boundary, 'thickness') && a.boundary.available
                kd = max(real(a.k)) * a.boundary.thickness;
                thick = kd > 1;
                txt = sprintf(['Thin-element model not applicable: d = %g mm (k d up to %.1f). ' ...
                    'Use R / tau (anechoic termination) or the transfer matrix.'], round(1e3 * a.boundary.thickness, 3), kd);
            end
        end

        function plotRes(app)
            P = tim.gui.palette();
            r = app.LastRes; a = r.analysis; f = a.f; v = a.valid;
            ax = app.H.axH; cla(ax); hold(ax, 'on');
            for k = 1:4
                mk = app.stepMarkers(P.ch(k, :));
                plot(ax, f, 20 * log10(abs(r.Hposition(:, k))), 'Color', P.ch(k, :), 'LineWidth', P.lineWidth, mk{:});
            end
            hold(ax, 'off'); set(ax, 'XScale', 'log'); grid(ax, 'on');
            legend(ax, {'M1', 'M2', 'M3', 'M4'}, 'Location', 'best');
            ylabel(ax, '|p_m / p_{ref}| [dB]'); xlabel(ax, 'Frequency [Hz]');
            title(ax, sprintf('Calibrated relative pressures (%s)', r.calibration.version), 'FontWeight', 'normal');

            ax = app.H.axR; cla(ax); hold(ax, 'on');
            h1 = app.masked(ax, f, abs(a.R), v.validR, P.a);
            h2 = app.masked(ax, f, abs(a.tau), v.validTau, P.b);
            h3 = app.masked(ax, f, a.power.alpha, v.validTau, P.c);
            set(ax, 'XScale', 'log'); grid(ax, 'on'); ylim(ax, [-0.1 1.2]); xlabel(ax, 'Frequency [Hz]');
            legend(ax, [h1 h2 h3], {'|R|', '|\tau|', '\alpha = 1-|R|^2-|\tau|^2'}, 'Location', 'best');
            title(ax, 'Reflection / transmission (grey = not valid)', 'FontWeight', 'normal');

            ax = app.H.axZ; cla(ax); hold(ax, 'on');
            [thick, thickTxt] = app.thickSpecimen(a);
            if thick
                hold(ax, 'off'); set(ax, 'XScale', 'log'); grid(ax, 'on'); xlabel(ax, 'Frequency [Hz]');
                ylabel(ax, 'Z_t / \rho c'); legend(ax, 'off');
                title(ax, {'Thin-element transfer impedance', thickTxt}, 'FontWeight', 'normal', 'Interpreter', 'none');
            else
                h1 = app.masked(ax, f, real(a.thin.Zt_norm), v.validThinZt, P.a);
                h2 = app.masked(ax, f, imag(a.thin.Zt_norm), v.validThinZt, P.b);
                set(ax, 'XScale', 'log'); grid(ax, 'on'); xlabel(ax, 'Frequency [Hz]'); ylabel(ax, 'Z_t / \rho c');
                legend(ax, [h1 h2], {'Re\{Z_t\}/\rho c', 'Im\{Z_t\}/\rho c'}, 'Location', 'best');
                ok = v.validThinZt & isfinite(a.thin.Zt);
                if any(ok)
                    title(ax, sprintf(['Thin-element transfer impedance (grey = not valid):  median valid Re\\{Z_t\\} = %.0f Pa s/m, ' ...
                        '\\rho c = %.0f Pa s/m'], median(real(a.thin.Zt(ok))), a.air.Z0), 'FontWeight', 'normal');
                else
                    title(ax, 'Thin-element transfer impedance: no valid bins (calibration / geometry / velocity mismatch)', 'FontWeight', 'normal');
                end
            end

            ax = app.H.axTL; cla(ax); hold(ax, 'on');
            yv = a.power.TL_tau_dB; yv(~v.validTau) = NaN;
            mk = app.stepMarkers(P.b);
            h2 = plot(ax, f, yv, '--', 'Color', P.b, 'LineWidth', P.lineWidth, mk{:});
            set(ax, 'XScale', 'log'); grid(ax, 'on'); xlabel(ax, 'Frequency [Hz]'); ylabel(ax, 'TL [dB]');
            if thick
                legend(ax, h2, {'TL = -20log_{10}|\tau|  (anechoic termination)'}, 'Location', 'best');
                title(ax, {'Transmission loss (grey = not valid)', thickTxt}, 'FontWeight', 'normal', 'Interpreter', 'none');
            else
                h1 = app.masked(ax, f, a.thin.TL_dB, v.validThinZt, P.a);
                legend(ax, [h1 h2], {'TL from Z_t: 20log_{10}|1+Z_t/(2\rhoc)|', 'TL = -20log_{10}|\tau|  (anechoic termination)'}, ...
                    'Location', 'best');
                title(ax, 'Transmission loss (grey = not valid)', 'FontWeight', 'normal');
            end

            ax = app.H.axV; cla(ax); hold(ax, 'on');
            lv = {v.valid, v.qualityOK, v.geometryOK, v.measured};
            for i = 1:4
                yy = double(lv{i}) * 0.8 + (i - 1); yy(~lv{i}) = NaN;
                mk = app.stepMarkers(P.ch(i, :), 's');
                plot(ax, f, yy, '-', 'Color', P.ch(i, :), 'LineWidth', 3, mk{:});
                plot(ax, f, (i - 1) * ones(size(f)), '-', 'Color', P.invalid, 'LineWidth', 1);
            end
            hold(ax, 'off');
            set(ax, 'XScale', 'log', 'YTick', 0.4 + (0:3), 'YTickLabel', {'valid', 'quality OK', 'geometry OK', 'measured'}, ...
                'YLim', [-0.3 4]);
            grid(ax, 'on'); xlabel(ax, 'Frequency [Hz]'); title(ax, r.summary, 'FontSize', 9, 'FontWeight', 'normal');
        end

        function hv = masked(app, ax, f, y, ok, c)
            % whole curve thin grey, valid part in colour; returns the coloured line
            % (stepped sine: markers at the step frequencies)
            P = tim.gui.palette();
            mg = app.stepMarkers(P.invalid); mc = app.stepMarkers(c);
            plot(ax, f, y, '-', 'Color', P.invalid, 'LineWidth', 0.7, mg{:});
            yv = y; yv(~ok) = NaN;
            hv = plot(ax, f, yv, '-', 'Color', c, 'LineWidth', P.lineWidth + 0.3, mc{:});
        end

        function closingDialog(app, msg)
            % "Closing" progress dialog inside the (already rendered) window:
            % appears at once; its indeterminate bar is animated by the window
            % itself, so it keeps moving while MATLAB waits for an instrument
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
            app.stopPulse();
            s = app.Session;
            done = {};
            if ~isempty(s) && ~isempty(s.Gen)
                app.closingDialog([done, {'Switching the generator output OFF ...'}]);
                try, s.Gen.outputOff(); catch, end
                done{end + 1} = 'Generator output OFF.';
            end
            if ~isempty(s)
                app.closingDialog([done, {'Returning the LAN-XI to Idle (2 s time-out per request) ...'}]);
                try, s.close(true); catch, end
                app.Session = [];
                done{end + 1} = 'Instruments disconnected.';
            end
            app.closingDialog([done, {'Closing the window ...'}]);
            fig = app.Fig;
            delete(app);                         % deletes the main window and the dialog
            if isvalid(fig), delete(fig); end
        end
    end
end

function safeUnlock(app)
% end of a busy action: restore the controls unless the app was closed meanwhile
if isvalid(app), app.unlockUi(); end
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
