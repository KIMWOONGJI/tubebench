classdef TubeApp < handle
    %TUBEAPP Basic graphical interface (uifigure, R2022b) for the tube system.
    %
    %   app = tim.gui.TubeApp();                      % default / example config
    %   app = tim.gui.TubeApp('config/user_config.json');
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
    end

    methods
        function app = TubeApp(cfgFile)
            if nargin >= 1 && ~isempty(cfgFile)
                app.Cfg = tim.app.loadConfig(cfgFile);
            else
                app.Cfg = tim.app.defaultConfig();
            end
            app.build();
            app.refreshFromCfg();
            app.log('Ready. Mode: %s. Generator output is OFF until you press START.', app.Cfg.mode);
        end

        function delete(app)
            try, app.disconnect(); catch, end
            if ~isempty(app.Fig) && isvalid(app.Fig), delete(app.Fig); end
        end

        function disconnect(app)
            if ~isempty(app.Session)
                try, app.Session.close(); catch, end
                app.Session = [];
            end
            if isfield(app.H, 'status') && isvalid(app.H.status), app.setStatus('disconnected', false); end
        end
    end

    methods
        function drawCalSetup(app, mapping, msg, stepText)
            % Schematic of the tube: loudspeaker, ports M1..M4, sample holder,
            % and which DAQ channel's microphone sits in which port.
            ax = app.H.axCalSetup; cla(ax); hold(ax, 'on');
            axis(ax, [0 10.4 0.2 4.6]); axis(ax, 'off'); ax.DataAspectRatioMode = 'auto';
            px = [2.4 3.2 7.0 7.8];                                   % schematic port positions
            calPorts = app.Cfg.calibration.positions;
            rectangle(ax, 'Position', [1.0 1.5 8.6 1.0], 'FaceColor', [0.93 0.93 0.93], 'EdgeColor', [0.4 0.4 0.4]);
            patch(ax, [0.3 0.75 1.0 1.0 0.75 0.3], [1.2 1.6 1.6 2.4 2.4 2.8], [0.55 0.55 0.55], 'EdgeColor', 'none');
            text(ax, 0.6, 0.85, 'loud-speaker', 'HorizontalAlignment', 'center', 'FontSize', 9);
            if isempty(mapping)
                rectangle(ax, 'Position', [5.05 1.5 0.3 1.0], 'FaceColor', [0.85 0.75 0.55], 'EdgeColor', 'none');
                text(ax, 5.2, 1.15, 'test specimen', 'HorizontalAlignment', 'center', 'FontSize', 9);
                plot(ax, [9.6 9.6], [1.5 2.5], 'k-', 'LineWidth', 3);
                text(ax, 9.95, 2.0, 'termination', 'Rotation', 90, 'HorizontalAlignment', 'center', 'FontSize', 11);
            else
                % calibration: specimen removed, anechoic / absorbing termination
                rectangle(ax, 'Position', [5.05 1.5 0.3 1.0], 'FaceColor', 'none', 'EdgeColor', [0.8 0.2 0.2], ...
                    'LineStyle', '--', 'LineWidth', 1.2);
                plot(ax, [5.05 5.35], [1.5 2.5], '-', 'Color', [0.8 0.2 0.2]);
                plot(ax, [5.05 5.35], [2.5 1.5], '-', 'Color', [0.8 0.2 0.2]);
                text(ax, 5.2, 1.15, 'test specimen REMOVED', 'HorizontalAlignment', 'center', 'FontSize', 9, ...
                    'FontWeight', 'bold', 'Color', [0.8 0.2 0.2]);
                patch(ax, [9.0 9.6 9.6 9.0], [1.5 1.5 2.5 2.5], [0.6 0.75 0.6], 'EdgeColor', 'none', 'FaceAlpha', 0.7);
                plot(ax, [9.6 9.6], [1.5 2.5], 'k-', 'LineWidth', 3);
                text(ax, 9.95, 2.0, 'anechoic / absorbing', 'Rotation', 90, 'HorizontalAlignment', 'center', 'FontSize', 11);
            end
            P = tim.gui.palette(); col = P.ch;
            for p = 1:4
                if ismember(p, calPorts) && ~isempty(mapping)
                    rectangle(ax, 'Position', [px(p) - 0.33 2.5 0.66 1.75], 'FaceColor', [1 0.96 0.7], 'EdgeColor', 'none');
                end
                rectangle(ax, 'Position', [px(p) - 0.08 2.5 0.16 0.35], 'FaceColor', [0.3 0.3 0.3], 'EdgeColor', 'none');
                text(ax, px(p), 1.95, sprintf('M%d', p), 'HorizontalAlignment', 'center', 'FontWeight', 'bold');
                if isempty(mapping), continue; end
                c = find(mapping == p, 1);
                if isempty(c), continue; end
                lbl = sprintf('ch%d', c);
                try
                    t = app.Session.Daq.Teds{c};
                    if ~isempty(t), lbl = sprintf('ch%d\n%d', c, t.serialNumber); end
                catch
                end
                if c == app.Cfg.analysis.refChannel, lbl = [lbl sprintf('\n(ref)')]; end
                plot(ax, px(p), 3.15, 'o', 'MarkerSize', 22, 'MarkerFaceColor', col(c, :), 'MarkerEdgeColor', 'k');
                text(ax, px(p), 3.15, sprintf('%d', c), 'Color', 'w', 'FontWeight', 'bold', 'HorizontalAlignment', 'center');
                text(ax, px(p), 3.95, lbl, 'HorizontalAlignment', 'center', 'FontSize', 9);
            end
            if isempty(mapping)
                title(ax, {'Switching calibration: press "Run switching cal." - every step shows here which microphone goes into which port', ...
                    'Each microphone stays on its own cable and LAN-XI input; only the microphone bodies are moved.'}, 'FontSize', 10);
            else
                words = strsplit(msg, ' '); wrapped = {''};
                for w = words           % wrap long instructions (~150 characters per line)
                    if strlength(wrapped{end}) + strlength(w{1}) > 150, wrapped{end+1} = ''; end %#ok<AGROW>
                    wrapped{end} = strtrim([wrapped{end} ' ' w{1}]);
                end
                title(ax, [{stepText}, wrapped, {'yellow = calibration ports a, b;  circles = DAQ channel of the microphone in that port'}], ...
                    'FontSize', 10, 'Interpreter', 'none');
            end
            hold(ax, 'off');
        end

        function showCal(app, cal)
            app.H.calLabel.Text = cal.version; app.H.calLabel.FontColor = [0 0.5 0];
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
        function build(app)
            % window fills the screen (maximised); restored size = most of the screen
            scr = get(groot, 'ScreenSize');
            W = max(1400, scr(3) - 80); Hh = max(760, scr(4) - 120);
            app.Fig = uifigure('Name', 'Transfer-impedance tube', 'Position', [40 50 W Hh], ...
                'CloseRequestFcn', @(src, ~) tim.gui.closeApp(src, app));   % never gets stuck
            try, app.Fig.WindowState = 'maximized'; catch, end
            g = uigridlayout(app.Fig, [1 2], 'ColumnWidth', {430, '1x'});
            nRows = 36;
            left = uigridlayout(g, [nRows 2], 'RowHeight', repmat({24}, 1, nRows), 'ColumnWidth', {205, '1x'}, ...
                'Scrollable', 'on', 'RowSpacing', 6);
            h = struct();
            r = 0;
            % ---------------- instruments
            r = r + 1; app.header(left, r, 'INSTRUMENTS');
            r = r + 1; app.lab(left, r, 'Mode');
            h.mode = uidropdown(left, 'Items', {'simulation', 'hardware'}); app.place(h.mode, r);
            r = r + 1; h.loadCfg = uibutton(left, 'Text', 'Load config...', 'ButtonPushedFcn', @(~, ~) app.onLoadConfig());
            h.loadCfg.Layout.Row = r; h.loadCfg.Layout.Column = 1;
            h.saveCfg = uibutton(left, 'Text', 'Save config...', 'ButtonPushedFcn', @(~, ~) app.onSaveConfig()); app.place(h.saveCfg, r);
            r = r + 1; h.connect = uibutton(left, 'Text', 'Connect + TEDS', 'ButtonPushedFcn', @(~, ~) app.onConnect());
            h.connect.Layout.Row = r; h.connect.Layout.Column = 1;
            h.disconnect = uibutton(left, 'Text', 'Disconnect', 'ButtonPushedFcn', @(~, ~) app.disconnect()); app.place(h.disconnect, r);
            r = r + 1; app.lab(left, r, 'Status');
            h.status = uilabel(left, 'Text', 'disconnected', 'FontColor', [0.6 0 0]); app.place(h.status, r);
            % ---------------- excitation
            r = r + 1; app.header(left, r, 'EXCITATION');
            r = r + 1; app.lab(left, r, 'Mode');
            h.exMode = uidropdown(left, 'Items', {'sweep', 'stepped'}, 'Tooltip', ...
                'sweep: broadband measurement (default).  stepped: discrete sine frequencies - cross-check / validation'); app.place(h.exMode, r);
            r = r + 1; app.lab(left, r, 'f start / stop [Hz]');
            h.fRange = uieditfield(left, 'text'); app.place(h.fRange, r);
            r = r + 1; app.lab(left, r, 'Sweep time [s]');
            h.dur = uieditfield(left, 'numeric', 'Limits', [0.001 500]); app.place(h.dur, r);
            r = r + 1; app.lab(left, r, 'Amplitude [Vpk]');
            h.amp = uieditfield(left, 'numeric', 'Limits', [0.005 10], 'ValueChangedFcn', @(~, ~) app.updateDrive()); app.place(h.amp, r);
            r = r + 1; app.lab(left, r, 'Repetitions');
            h.reps = uieditfield(left, 'numeric', 'Limits', [1 100], 'RoundFractionalValues', 'on'); app.place(h.reps, r);
            r = r + 1; app.lab(left, r, 'Amp model');
            h.ampModel = uidropdown(left, 'Editable', 'on', 'Items', {'none (direct drive)', 'power amplifier'}, ...
                'Tooltip', 'select, or type the model of your power amplifier (typed models are added)', ...
                'ValueChangedFcn', @(~, ~) app.onAmpModel()); app.place(h.ampModel, r);
            r = r + 1; app.lab(left, r, 'Amp gain [x]');
            h.ampGain = uieditfield(left, 'numeric', 'Limits', [0 Inf], 'LowerLimitInclusive', 'off', 'ValueDisplayFormat', 'x %.4g', ...
                'Tooltip', 'voltage gain of the power amplifier as a multiplier (x10 = 20 dB); used to estimate the loudspeaker drive', ...
                'ValueChangedFcn', @(~, ~) app.updateDrive()); app.place(h.ampGain, r);
            r = r + 1; app.lab(left, r, 'Speaker [ohm] / limit [W]');
            gs = uigridlayout(left, [1 2], 'Padding', [0 0 0 0], 'ColumnSpacing', 4); gs.Layout.Row = r; gs.Layout.Column = 2;
            h.spkZ = uieditfield(gs, 'numeric', 'Limits', [0.5 1000], 'ValueChangedFcn', @(~, ~) app.updateDrive(), ...
                'Tooltip', 'nominal loudspeaker impedance [ohm]');
            h.spkP = uieditfield(gs, 'numeric', 'Limits', [1e-4 1000], 'ValueChangedFcn', @(~, ~) app.updateDrive(), ...
                'Tooltip', 'power limit [W]: excitation is refused above this estimated power');
            r = r + 1; h.drive = uilabel(left, 'Text', '', 'FontSize', 11, 'WordWrap', 'on');
            h.drive.Layout.Row = [r r + 1]; h.drive.Layout.Column = [1 2]; r = r + 1;
            r = r + 1; h.start = uibutton(left, 'Text', 'START measurement', 'BackgroundColor', [0.75 0.9 0.75], ...
                'FontWeight', 'bold', 'ButtonPushedFcn', @(~, ~) app.onStart());
            h.start.Layout.Row = r; h.start.Layout.Column = 1;
            h.stop = uibutton(left, 'Text', 'STOP', 'BackgroundColor', [0.95 0.7 0.7], 'FontWeight', 'bold', ...
                'ButtonPushedFcn', @(~, ~) app.onStop()); app.place(h.stop, r);
            r = r + 1; h.background = uibutton(left, 'Text', 'Background noise (2 s, no excitation)', ...
                'ButtonPushedFcn', @(~, ~) app.onBackground());
            h.background.Layout.Row = r; h.background.Layout.Column = [1 2];
            % ---------------- tube configuration
            r = r + 1; app.header(left, r, 'IMPEDANCE TUBE');
            r = r + 1; app.lab(left, r, 'Inner diameter [mm]');
            h.tubeD = uieditfield(left, 'numeric', 'Limits', [1 500], 'ValueChangedFcn', @(~, ~) app.onTubeChanged()); app.place(h.tubeD, r);
            % distances between clearly defined points (port centres, specimen faces);
            % empty = not measured yet. See the "Tube setup" tab for the drawing.
            tip = 'distance between microphone PORT CENTRES (centre of the port hole), in mm';
            r = r + 1; app.lab(left, r, 's1   M1 -> M2 [mm]');
            h.s1 = uieditfield(left, 'numeric', 'Limits', [1 1000], 'Tooltip', ['upstream spacing: ' tip], ...
                'ValueChangedFcn', @(~, ~) app.onTubeChanged()); app.place(h.s1, r);
            r = r + 1; app.lab(left, r, 'L1   M2 -> specimen front [mm]');
            h.L1 = uieditfield(left, 'text', 'Placeholder', 'not measured', 'HorizontalAlignment', 'right', ...
                'Tooltip', 'from the centre of port M2 to the FRONT face of the specimen (the face towards the loudspeaker)', ...
                'ValueChangedFcn', @(~, ~) app.onTubeChanged()); app.place(h.L1, r);
            r = r + 1; app.lab(left, r, 'd    specimen thickness [mm]');
            h.dTh = uieditfield(left, 'text', 'Placeholder', 'not measured', 'HorizontalAlignment', 'right', ...
                'Tooltip', 'from the front face to the rear face of the specimen (0 for a thin screen)', ...
                'ValueChangedFcn', @(~, ~) app.onTubeChanged()); app.place(h.dTh, r);
            r = r + 1; app.lab(left, r, 'L2   specimen rear -> M3 [mm]');
            h.L2 = uieditfield(left, 'text', 'Placeholder', 'not measured', 'HorizontalAlignment', 'right', ...
                'Tooltip', 'from the REAR face of the specimen (towards the termination) to the centre of port M3', ...
                'ValueChangedFcn', @(~, ~) app.onTubeChanged()); app.place(h.L2, r);
            r = r + 1; app.lab(left, r, 's2   M3 -> M4 [mm]');
            h.s2 = uieditfield(left, 'numeric', 'Limits', [1 1000], 'Tooltip', ['downstream spacing: ' tip], ...
                'ValueChangedFcn', @(~, ~) app.onTubeChanged()); app.place(h.s2, r);
            r = r + 1; app.lab(left, r, 'Temp [degC] / p [kPa]');
            ge = uigridlayout(left, [1 2], 'Padding', [0 0 0 0], 'ColumnSpacing', 4); ge.Layout.Row = r; ge.Layout.Column = 2;
            h.temp = uieditfield(ge, 'numeric', 'Limits', [-20 60], 'ValueChangedFcn', @(~, ~) app.onTubeChanged());
            h.pres = uieditfield(ge, 'numeric', 'Limits', [50 120], 'ValueChangedFcn', @(~, ~) app.onTubeChanged());
            r = r + 1; h.fLimits = uilabel(left, 'Text', '', 'FontSize', 11, 'WordWrap', 'on');
            h.fLimits.Layout.Row = [r r + 1]; h.fLimits.Layout.Column = [1 2]; r = r + 1;
            % ---------------- calibration
            r = r + 1; app.header(left, r, 'CALIBRATION');
            r = r + 1; h.loadCal = uibutton(left, 'Text', 'Load calibration...', 'ButtonPushedFcn', @(~, ~) app.onLoadCal());
            h.loadCal.Layout.Row = r; h.loadCal.Layout.Column = 1;
            h.runCal = uibutton(left, 'Text', 'Run switching cal.', 'ButtonPushedFcn', @(~, ~) app.onRunCal()); app.place(h.runCal, r);
            r = r + 1; app.lab(left, r, 'Calibration');
            h.calLabel = uilabel(left, 'Text', 'none (results not valid)', 'FontColor', [0.6 0 0]); app.place(h.calLabel, r);
            % ---------------- results
            r = r + 1; app.header(left, r, 'RESULTS');
            r = r + 1; h.save = uibutton(left, 'Text', 'Save measurement + export', 'ButtonPushedFcn', @(~, ~) app.onSave());
            h.save.Layout.Row = r; h.save.Layout.Column = [1 2];
            r = r + 1; h.reprocess = uibutton(left, 'Text', 'Re-process (config/cal changed)', 'ButtonPushedFcn', @(~, ~) app.onReprocess());
            h.reprocess.Layout.Row = r; h.reprocess.Layout.Column = [1 2];
            assert(r <= nRows, 'layout: increase nRows');

            % ---------------- tabs
            tabs = uitabgroup(g);
            t = uitab(tabs, 'Title', 'Log');
            tg = uigridlayout(t, [1 1]);
            h.log = uitextarea(tg, 'Editable', 'off', 'FontName', 'Consolas');
            t = uitab(tabs, 'Title', 'Channels / TEDS');
            tg = uigridlayout(t, [1 1]);
            h.chanTable = uitable(tg);
            t = uitab(tabs, 'Title', 'Tube setup');
            tg = uigridlayout(t, [1 1]);
            h.axTube = uiaxes(tg); h.tubeTab = t;
            % waveforms: one graph per channel (shared time axis), also used for the live view
            t = uitab(tabs, 'Title', 'Waveforms'); h.waveTab = t;
            tg = uigridlayout(t, [4 1], 'RowSpacing', 2);
            P = tim.gui.palette();
            for c = 1:4
                ax = uiaxes(tg); h.axW(c) = ax;
                h.waveLine(c) = plot(ax, NaN, NaN, '-', 'Color', P.ch(c, :), 'LineWidth', 0.8);
                ylabel(ax, sprintf('ch%d [mV]', c)); grid(ax, 'on');
                if c < 4, ax.XTickLabel = {}; else, xlabel(ax, 'Time [s]'); end
            end
            linkaxes(h.axW, 'x');
            names = {'Spectrum', 'Relative responses', 'Calibration', 'R / tau', 'Transfer impedance', ...
                'Transmission loss', 'Validity'};
            keys = {'axSpec', 'axH', 'axCal', 'axR', 'axZ', 'axTL', 'axV'};
            for i = 1:numel(names)
                t = uitab(tabs, 'Title', names{i});
                if strcmp(keys{i}, 'axCal')
                    % calibration tab: set-up diagram (which mic in which port) + curves
                    tg = uigridlayout(t, [2 1], 'RowHeight', {260, '1x'});
                    h.axCalSetup = uiaxes(tg);
                    h.calTab = t;
                else
                    tg = uigridlayout(t, [1 1]);
                end
                h.(keys{i}) = uiaxes(tg);
            end
            h.tabs = tabs;
            t = uitab(tabs, 'Title', 'Equations');
            tim.gui.equationsPanel(t);
            app.H = h;
            app.drawCalSetup([], '', '');
        end

        function header(~, parent, row, txt)
            l = uilabel(parent, 'Text', txt, 'FontWeight', 'bold');
            l.Layout.Row = row; l.Layout.Column = [1 2];
        end
        function lab(~, parent, row, txt)
            l = uilabel(parent, 'Text', txt); l.Layout.Row = row; l.Layout.Column = 1;
        end
        function place(~, c, row)
            c.Layout.Row = row; c.Layout.Column = 2;
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
            h.tubeD.Value = 1e3 * gm.diameter;
            % coordinates in the config -> distances s1, L1, d, L2, s2 in the GUI
            x = gm.micPositions;
            if all(isfinite(x))
                h.s1.Value = 1e3 * (x(2) - x(1)); h.s2.Value = 1e3 * (x(4) - x(3));
            else
                h.s1.Value = 1e3 * gm.spacingUp; h.s2.Value = 1e3 * gm.spacingDown;
            end
            h.L1.Value = app.mm2txt(gm.xFront - x(2));
            h.dTh.Value = app.mm2txt(gm.xRear - gm.xFront);
            h.L2.Value = app.mm2txt(x(3) - gm.xRear);
            h.temp.Value = c.environment.temperature_C; h.pres.Value = c.environment.pressure_Pa / 1e3;
            ls = struct('impedance_ohm', 8, 'maxPower_W', 1);
            if isfield(c, 'loudspeaker'), ls = c.loudspeaker; end
            h.spkZ.Value = ls.impedance_ohm; h.spkP.Value = ls.maxPower_W;
            s = c.excitation.sweep;
            h.fRange.Value = sprintf('%g %g', s.fStart, s.fStop);
            h.dur.Value = s.duration; h.amp.Value = s.amplitudeVpp / 2; h.reps.Value = s.repetitions;
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
        end

        function v = mm2txt(~, x)
            if isfinite(x), v = sprintf('%g', round(1e3 * x, 6)); else, v = ''; end
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
        end

        function onTubeChanged(app)
            % live check of the tube entries: limits, consistency, drawing
            [geom, env, msgs] = app.readTube();
            try
                air = tim.acoustics.airProperties(env);
                lim = tim.acoustics.frequencyLimits(geom.diameter, [geom.spacingUp geom.spacingDown], air);
                known = all(isfinite(geom.micPositions)) && isfinite(geom.xFront) && isfinite(geom.xRear);
                txt = sprintf('c = %.1f m/s.  Geometric range %.0f - %.0f Hz (s = %.1f / %.1f mm, (1,1) cut-on %.0f Hz).', ...
                    air.c, lim.fLower, lim.fUpper, 1e3 * geom.spacingUp, 1e3 * geom.spacingDown, lim.cutOn11);
                if ~known
                    txt = [txt ' Positions incomplete: boundary results (R, tau, Zt, TL) disabled.'];
                end
                if ~isempty(msgs), txt = [txt ' CHECK: ' strjoin(msgs, '; ')]; end
                app.H.fLimits.Text = txt;
                if isempty(msgs), app.H.fLimits.FontColor = [0.2 0.2 0.2]; else, app.H.fLimits.FontColor = [0.75 0 0]; end
                app.drawTube(geom, lim);
            catch err
                app.H.fLimits.Text = ['CHECK: ' err.message]; app.H.fLimits.FontColor = [0.75 0 0];
            end
        end

        function drawTube(app, geom, lim)
            % Drawing of the impedance tube with the dimension lines s1, L1, d,
            % L2, s2 (to scale when all distances are entered).
            ax = app.H.axTube; cla(ax); hold(ax, 'on'); P = tim.gui.palette();
            D = 1e3 * geom.diameter;
            s1 = 1e3 * geom.spacingUp; s2 = 1e3 * geom.spacingDown;
            known = all(isfinite(geom.micPositions)) && isfinite(geom.xFront) && isfinite(geom.xRear);
            if known
                L1 = -1e3 * geom.micPositions(2); dd = 1e3 * (geom.xRear - geom.xFront);
                L2 = 1e3 * geom.micPositions(3) - 1e3 * geom.xRear;
                txt = @(v) sprintf('%g mm', round(v, 3));
            else
                L1 = max(3 * s1, 60); dd = max(0.4 * s1, 8); L2 = L1;      % schematic only
                txt = @(v) '? (enter)';
            end
            % coordinates: x = 0 at the specimen front face
            xF = 0; xR = dd; x = [-L1 - s1, -L1, dd + L2, dd + L2 + s2];
            x0 = x(1) - max(60, 0.4 * L1); x1 = x(4) + max(60, 0.4 * L2);
            % tube, loudspeaker, termination, specimen
            patch(ax, [x0 x1 x1 x0], [-D/2 -D/2 D/2 D/2], [0.95 0.95 0.95], 'EdgeColor', [0.35 0.35 0.35], 'LineWidth', 1);
            patch(ax, [x0 - 25, x0, x0, x0 - 25], [-D/2 - 8, -D/2, D/2, D/2 + 8], [0.55 0.55 0.55], 'EdgeColor', 'none');
            text(ax, x0 - 12, -D/2 - 14, 'loudspeaker', 'HorizontalAlignment', 'center', 'FontSize', 12);
            plot(ax, [x1 x1], [-D/2 D/2], 'k-', 'LineWidth', 3);
            text(ax, x1, -D/2 - 14, 'termination', 'HorizontalAlignment', 'center', 'FontSize', 12);
            patch(ax, [xF max(xR, xF + 1.5) max(xR, xF + 1.5) xF], [-D/2 -D/2 D/2 D/2], [0.85 0.72 0.45], 'EdgeColor', [0.45 0.35 0.15]);
            text(ax, (xF + xR) / 2, 0, 'specimen', 'Rotation', 90, 'HorizontalAlignment', 'center', 'FontSize', 11);
            text(ax, xF, -D/2 - 5, 'front ', 'HorizontalAlignment', 'right', 'FontSize', 11, 'Color', [0.35 0.35 0.35]);
            text(ax, xR, -D/2 - 5, ' rear', 'HorizontalAlignment', 'left', 'FontSize', 11, 'Color', [0.35 0.35 0.35]);
            % microphone ports (centre lines)
            for k = 1:4
                plot(ax, [x(k) x(k)], [D/2 D/2 + 7], '-', 'Color', P.ch(k, :), 'LineWidth', 4);
                plot(ax, [x(k) x(k)], [-D/2 D/2], ':', 'Color', P.ch(k, :));
                text(ax, x(k), D/2 + 12, sprintf('M%d', k), 'HorizontalAlignment', 'center', 'FontWeight', 'bold', 'FontSize', 13, 'Color', P.ch(k, :));
            end
            % dimension lines (two rows above the tube)
            y1 = D/2 + 28; y2 = D/2 + 46;
            app.dimLine(ax, x(1), x(2), y1, sprintf('s1 = %s', sprintf('%g mm', round(s1, 3))));
            app.dimLine(ax, x(2), xF, y2, sprintf('L1 = %s', txt(L1)));
            app.dimLine(ax, xF, xR, y1, sprintf('d = %s', txt(dd)));
            app.dimLine(ax, xR, x(3), y2, sprintf('L2 = %s', txt(L2)));
            app.dimLine(ax, x(3), x(4), y1, sprintf('s2 = %s', sprintf('%g mm', round(s2, 3))));
            for xx = [x(1) x(2) xF xR x(3) x(4)]
                plot(ax, [xx xx], [D/2 + 17, y2 + 3], '-', 'Color', [0.7 0.7 0.7], 'LineWidth', 0.5);
            end
            text(ax, (x0 + x1) / 2, -D/2 - 24, sprintf('inner diameter %g mm', D), 'HorizontalAlignment', 'center', 'FontSize', 12);
            axis(ax, 'equal'); ax.YLim = [-D/2 - 34, y2 + 16]; ax.XLim = [x0 - 35, x1 + 15];
            ax.YTick = []; ax.XColor = 'none'; ax.YColor = 'none';
            if known
                title(ax, {sprintf(['Impedance tube (to scale).  Distances between port CENTRES and specimen FACES.  ' ...
                    'Geometric range %.0f - %.0f Hz, (1,1) cut-on %.0f Hz'], lim.fLower, lim.fUpper, lim.cutOn11)}, 'FontWeight', 'normal');
            else
                title(ax, {'Impedance tube (schematic - L1, d, L2 not entered yet).  Distances between port CENTRES and specimen FACES.', ...
                    sprintf('Without L1, d and L2 the specimen results (R, tau, Zt, TL) are disabled.   Geometric range %.0f - %.0f Hz', ...
                    lim.fLower, lim.fUpper)}, 'FontWeight', 'normal');
            end
            hold(ax, 'off');
        end

        function dimLine(~, ax, xa, xb, y, label)
            % horizontal dimension line with arrow heads and a label above it
            plot(ax, [xa xb], [y y], '-', 'Color', [0.2 0.2 0.2], 'LineWidth', 0.8);
            ah = min(4, abs(xb - xa) / 3);
            if ah > 0.5
                plot(ax, [xa xa + ah xa + ah], [y y + 1.5 y - 1.5], '-', 'Color', [0.2 0.2 0.2]);
                plot(ax, [xb xb - ah xb - ah], [y y + 1.5 y - 1.5], '-', 'Color', [0.2 0.2 0.2]);
            end
            text(ax, (xa + xb) / 2, y + 4, label, 'HorizontalAlignment', 'center', 'FontSize', 13, 'FontWeight', 'bold', ...
                'BackgroundColor', 'w', 'Margin', 1);
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
            fr = sscanf(h.fRange.Value, '%f');
            if numel(fr) ~= 2 || any(fr <= 0) || fr(2) <= fr(1)
                error('tim:gui:input', 'Enter "f_start f_stop" in Hz.');
            end
            app.Cfg.excitation.sweep.fStart = fr(1); app.Cfg.excitation.sweep.fStop = fr(2);
            app.Cfg.excitation.sweep.duration = h.dur.Value;
            app.Cfg.excitation.sweep.amplitudeVpp = 2 * h.amp.Value;      % GUI in Vpk, config/generator in Vpp
            app.Cfg.excitation.stepped.amplitudeVpp = 2 * h.amp.Value;
            app.Cfg.excitation.noise.amplitudeVpp = 2 * h.amp.Value;
            app.Cfg.excitation.sweep.repetitions = h.reps.Value;
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
                unlock = onCleanup(@() app.setBusy(false));
            end
            try
                fn();
            catch err
                if any(strcmp(err.identifier, {'tim:session:stopped', 'tim:gui:abort'}))
                    app.log('%s aborted by the operator: %s', busyWhat, err.message);
                    msg = sprintf('%s aborted. Generator output is OFF.', busyWhat);
                    icon = 'info';
                else
                    app.log('ERROR: %s', err.message);
                    msg = err.message; icon = 'error';
                end
                if ~isempty(app.Session) && ~isempty(app.Session.Gen)
                    app.Session.Gen.outputOff();
                end
                uialert(app.Fig, msg, 'Stopped', 'Icon', icon);
            end
        end

        function setBusy(app, tf, what)
            % Disable / restore all interactive controls (tabs stay usable).
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
                x = (x - mean(x, 1, 'omitnan')) * 1e3;                 % mV, slow drift removed
                t = ((1:n) - n) / fs;                                   % seconds before "now"
                total = p.samplesAvailable() / fs;
                sens = [app.Session.Mics.sensitivity_VperPa];
                for c = 1:4
                    set(app.H.waveLine(c), 'XData', t, 'YData', x(:, c));
                    spl = 20 * log10(sqrt(mean(x(:, c).^2, 'omitnan')) / 1e3 / sens(c) / 2e-5);
                    title(app.H.axW(c), sprintf('ch%d   %.1f dB SPL (last 0.5 s)', c, spl), 'FontWeight', 'normal');
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
            s = tim.app.MeasurementSession(app.Cfg);
            s.StatusCallback = @(line) app.appendLog(line);
            s.BlockCallback = @() app.liveUpdate();       % live waveforms + keeps STOP responsive
            L = app.Cfg.ui.language; yes = tim.app.msg(L, 'yesPlay');
            if strcmp(app.Cfg.mode, 'hardware')       % no real loudspeaker in simulation
                s.ExcitationConfirm = @(msg) strcmp(uiconfirm(app.Fig, msg, tim.app.msg(L, 'confirmTitle'), ...
                    'Options', {yes, tim.app.msg(L, 'cancel')}, 'DefaultOption', 2, 'CancelOption', 2, 'Icon', 'warning'), yes);
            end
            app.Session = s;
            s.connect();
            s.prepareAcquisition();
            app.setStatus(sprintf('ready (%s)', app.Cfg.mode), true);
            m = s.Mics;
            app.H.chanTable.Data = table([m.channel].', [m.position].', {m.model}.', ...
                1e3 * [m.sensitivity_VperPa].', {m.sensitivitySource}.', [m.tedsSerial].', ...
                'VariableNames', {'Channel', 'Position', 'Model', 'Sens_mV_per_Pa', 'Source', 'TEDS_serial'});
            if ~isempty(s.Calibration), app.showCal(s.Calibration); end
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
            app.run(@() app.doBackground(), 'background recording');
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
            % steps: preparation checklist + per channel config I (+ repeat) + config II
            % + the final "return mics"
            nCh = 3; per = 2 + double(app.Cfg.calibration.repeatConfigI);
            app.CalStep = 0; app.CalSteps = 1 + nCh * per + 1;
            [cal, file] = tim.app.runCalibration(app.Session, struct('prompt', @(msg, mapping) app.calStep(msg, mapping)));
            app.Cfg.calibration.file = file;
            app.showCal(cal);
        end

        function calStep(app, msg, mapping)
            % One operator step of the switching calibration: draw where every
            % microphone must be, then (hardware) wait for confirmation or
            % (simulation) move the virtual microphones.
            app.CalStep = app.CalStep + 1;
            stepText = sprintf('Calibration step %d of %d', app.CalStep, app.CalSteps);
            app.drawCalSetup(mapping, msg, stepText);
            app.H.tabs.SelectedTab = app.H.calTab; drawnow;
            if strcmp(app.Cfg.mode, 'hardware')
                L = app.Cfg.ui.language; done = tim.app.msg(L, 'calDoneButton');
                sel = uiconfirm(app.Fig, sprintf('%s\n\n%s\n(see the diagram in the Calibration tab)', stepText, msg), ...
                    tim.app.msg(L, 'calStepTitle'), 'Options', {done, tim.app.msg(L, 'abortButton')}, ...
                    'DefaultOption', 1, 'CancelOption', 2);
                if ~strcmp(sel, done)
                    error('tim:gui:abort', 'Calibration aborted by user.');
                end
            else
                app.Session.setMicPositionsForSimulation(mapping);
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
                app.plotRes();
            end
        end

        function plotWave(app, m)
            % one graph per channel, shared time axis; display high-pass 20 Hz
            % removes the slow CCLD/DC settling drift (raw data unchanged)
            P = tim.gui.palette();
            x = m.records{1}; t = (0:size(x, 1) - 1) / m.fs;
            [b, a] = butter(2, 20 / (m.fs / 2), 'high');
            xd = filtfilt(b, a, x - mean(x, 1)) * 1e3;
            for c = 1:4
                set(app.H.waveLine(c), 'XData', t, 'YData', xd(:, c), 'Color', P.ch(c, :));
                pk = max(abs(xd(:, c))); if ~(pk > 0), pk = 1; end
                app.H.axW(c).YLim = 1.1 * [-pk pk];
                title(app.H.axW(c), sprintf('ch%d   peak %.3g mV', c, pk), 'FontWeight', 'normal');
            end
            app.H.axW(1).XLim = [0 t(end)];
            xlabel(app.H.axW(4), sprintf('Time [s]   -   %s, %s (display high-passed at 20 Hz)', m.kind, m.timestamp));
            ax = app.H.axSpec; cla(ax); hold(ax, 'on');
            p = tim.acq.voltsToPascal(x - mean(x, 1), m.mics, 'V');
            nfft = min(8192, 2^nextpow2(size(p, 1)));
            [Pxx, f] = pwelch(p, hann(nfft, 'periodic'), nfft / 2, nfft, m.fs);
            for c = 1:4
                plot(ax, f, 10 * log10(Pxx(:, c) / 4e-10), 'Color', P.ch(c, :), 'LineWidth', P.lineWidth);
            end
            hold(ax, 'off'); set(ax, 'XScale', 'log'); grid(ax, 'on'); xlim(ax, [20 m.fs / 2]);
            xlabel(ax, 'Frequency [Hz]'); ylabel(ax, 'PSD [dB re (20\muPa)^2/Hz]');
            legend(ax, {'ch1', 'ch2', 'ch3', 'ch4'}, 'Location', 'best');
        end

        function plotRes(app)
            P = tim.gui.palette();
            r = app.LastRes; a = r.analysis; f = a.f; v = a.valid;
            ax = app.H.axH; cla(ax); hold(ax, 'on');
            for k = 1:4
                plot(ax, f, 20 * log10(abs(r.Hposition(:, k))), 'Color', P.ch(k, :), 'LineWidth', P.lineWidth);
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

            ax = app.H.axTL; cla(ax); hold(ax, 'on');
            h1 = app.masked(ax, f, a.thin.TL_dB, v.validThinZt, P.a);
            yv = a.power.TL_tau_dB; yv(~v.validTau) = NaN;
            h2 = plot(ax, f, yv, '--', 'Color', P.b, 'LineWidth', P.lineWidth);
            set(ax, 'XScale', 'log'); grid(ax, 'on'); xlabel(ax, 'Frequency [Hz]'); ylabel(ax, 'TL [dB]');
            legend(ax, [h1 h2], {'TL from Z_t: 20log_{10}|1+Z_t/(2\rhoc)|', 'TL = -20log_{10}|\tau|  (anechoic termination)'}, ...
                'Location', 'best');
            title(ax, 'Transmission loss (grey = not valid)', 'FontWeight', 'normal');

            ax = app.H.axV; cla(ax); hold(ax, 'on');
            lv = {v.valid, v.qualityOK, v.geometryOK, v.measured};
            for i = 1:4
                yy = double(lv{i}) * 0.8 + (i - 1); yy(~lv{i}) = NaN;
                plot(ax, f, yy, '-', 'Color', P.ch(i, :), 'LineWidth', 3);
                plot(ax, f, (i - 1) * ones(size(f)), '-', 'Color', P.invalid, 'LineWidth', 1);
            end
            hold(ax, 'off');
            set(ax, 'XScale', 'log', 'YTick', 0.4 + (0:3), 'YTickLabel', {'valid', 'quality OK', 'geometry OK', 'measured'}, ...
                'YLim', [-0.3 4]);
            grid(ax, 'on'); xlabel(ax, 'Frequency [Hz]'); title(ax, r.summary, 'FontSize', 9, 'FontWeight', 'normal');
        end

        function hv = masked(~, ax, f, y, ok, c)
            % whole curve thin grey, valid part in colour; returns the coloured line
            P = tim.gui.palette();
            plot(ax, f, y, '-', 'Color', P.invalid, 'LineWidth', 0.7);
            yv = y; yv(~ok) = NaN;
            hv = plot(ax, f, yv, '-', 'Color', c, 'LineWidth', P.lineWidth + 0.3);
        end

        function onClose(app)
            app.disconnect();
            delete(app.Fig);
        end
    end
end
