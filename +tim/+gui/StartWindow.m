classdef StartWindow < handle
    %STARTWINDOW Small start window shown while the main window is built.
    %
    %   sw = tim.gui.StartWindow();                      % centred on the screen
    %   sw = tim.gui.StartWindow('Area', [l b w h]);     % centred in this screen area
    %   sw = tim.gui.StartWindow('Visible', 'off');      % hidden (tests)
    %   sw.update('Drawing the 3D tube model…', 0.3)     % current step, progress 0..1
    %   sw.close()                                       % (also delete(sw))
    %
    %   Program name, version, the current step and a progress bar. MATLAB
    %   cannot update a window during one long call (e.g. the first drawing of
    %   the main window), so the bar moves only from step to step; the turning
    %   icon (animated GIF, tim.gui.icon('run')) is animated by the window
    %   itself and keeps moving meanwhile. Closing the start window does not
    %   stop the start-up: update() then only records the step.

    properties (Constant)
        % logo left of the program name: the reverse mark (white tube, light
        % channel colours) for the dark header, SVG (tim.gui.logo); '' = no logo
        LogoFile = tim.gui.logo('reverse')
    end
    properties (SetAccess = private)
        Fig = []                % the start window (uifigure)
        Step char = ''          % current step
        Value double = 0        % progress 0..1
        Steps = struct('text', {}, 'value', {}, 'time', {})   % every step, time since the start [s]
        H struct = struct()     % UI handles
    end
    properties (Access = private)
        T0
    end

    methods
        function sw = StartWindow(opts)
            arguments
                opts.Area (1,4) double = get(groot, 'ScreenSize')
                opts.Visible (1,:) char = 'on'
            end
            sw.T0 = tic;
            P = tim.gui.palette();
            [~, info] = tim.app.softwareVersion();
            w = 460; hgt = 190; a = opts.Area;
            sw.Fig = uifigure('Name', 'tubebench', 'Resize', 'off', 'Visible', opts.Visible, ...
                'Position', [round(a(1) + (a(3) - w) / 2), round(a(2) + (a(4) - hgt) / 2), w, hgt], ...
                'Color', P.ui.panel, 'Icon', tim.gui.logo('icon'), ...
                'CloseRequestFcn', @(~, ~) sw.close());   % closing never stops the start-up
            g = uigridlayout(sw.Fig, [2 1], 'RowHeight', {78, '1x'}, 'Padding', [0 0 0 0], 'RowSpacing', 0, ...
                'BackgroundColor', P.ui.panel);
            % header: (logo), program name, version
            logo = sw.LogoFile; hasLogo = ~isempty(logo) && isfile(logo);
            hd = uigridlayout(g, [4 2], 'RowHeight', {'1x', 28, 20, '1x'}, 'ColumnWidth', {52 * hasLogo, '1x'}, ...
                'Padding', [22 0 22 0], 'ColumnSpacing', 14 * hasLogo, 'RowSpacing', 2, 'BackgroundColor', P.ui.bar);
            if hasLogo
                sw.H.logo = uiimage(hd, 'ImageSource', logo, 'ScaleMethod', 'fit');   % 52 x 52 px
                sw.H.logo.Layout.Row = [1 4]; sw.H.logo.Layout.Column = 1;
            end
            sw.H.title = uilabel(hd, 'Text', 'tubebench', 'FontSize', 20, 'FontWeight', 'bold', ...
                'FontColor', P.ui.barText);
            sw.H.title.Layout.Row = 2; sw.H.title.Layout.Column = 2;
            sw.H.version = uilabel(hd, 'Text', sprintf('Version %s  %s  released %s', info.version, char(183), ...
                info.released), 'FontSize', 12, 'FontColor', [0.80 0.85 0.90]);
            sw.H.version.Layout.Row = 3; sw.H.version.Layout.Column = 2;
            % body: turning icon + step, progress bar, note
            bd = uigridlayout(g, [5 2], 'RowHeight', {'1x', 24, 6, 18, '1x'}, 'ColumnWidth', {20, '1x'}, ...
                'Padding', [22 6 22 6], 'RowSpacing', 9, 'ColumnSpacing', 8, 'BackgroundColor', P.ui.panel);
            sw.H.spin = uiimage(bd, 'ImageSource', tim.gui.icon('run'), 'ScaleMethod', 'fit');
            sw.H.spin.Layout.Row = 2; sw.H.spin.Layout.Column = 1;
            sw.H.step = uilabel(bd, 'Text', 'Starting…', 'FontSize', 13, 'FontColor', P.ui.text);
            sw.H.step.Layout.Row = 2; sw.H.step.Layout.Column = 2;
            % bar: grid with the filled part (accent) in column 1 on a light track
            sw.H.bar = uigridlayout(bd, [1 2], 'ColumnWidth', {0, '1x'}, 'RowHeight', {'1x'}, ...
                'Padding', [0 0 0 0], 'ColumnSpacing', 0, 'BackgroundColor', [0.84 0.87 0.92]);
            sw.H.bar.Layout.Row = 3; sw.H.bar.Layout.Column = [1 2];
            sw.H.fill = uilabel(sw.H.bar, 'Text', '', 'BackgroundColor', P.ui.accent);
            % last row: note on the left, the author's site on the right (link, opens the browser)
            nr = uigridlayout(bd, [1 2], 'ColumnWidth', {'1x', 'fit'}, 'RowHeight', {'1x'}, ...
                'Padding', [0 0 0 0], 'ColumnSpacing', 8, 'BackgroundColor', P.ui.panel);
            nr.Layout.Row = 4; nr.Layout.Column = [1 2];
            sw.H.note = uilabel(nr, 'Text', 'The main window opens by itself when it is ready.', 'FontSize', 11, ...
                'FontColor', P.ui.muted);
            u = tim.app.portfolioUrl();
            sw.H.site = uihyperlink(nr, 'Text', regexprep(u, '^https?://', ''), 'URL', u, 'FontSize', 11, ...
                'HorizontalAlignment', 'right', 'Tooltip', 'portfolio of the author - opens in the web browser');
            sw.update('Starting…', 0);
            % wait until the window is on the screen (about 0.3 s; at most 10 s, e.g.
            % right after MATLAB has started): drawnow does not wait for a new
            % uifigure, and a busy MATLAB would show it only during a later step.
            % Its layout coming back from the window = shown.
            if strcmp(opts.Visible, 'on')
                p0 = sw.H.step.Position; t = tic;
                while sw.isOpen() && isequal(sw.H.step.Position, p0) && toc(t) < 10
                    pause(0.02);
                end
            end
        end

        function update(sw, step, value)
            % next step and progress (0..1), shown at once. The drawing of what the
            % previous step built (drawnow: all windows, also when the start window
            % was closed) still belongs to that step.
            if nargin < 3, value = sw.Value; end
            drawnow;
            sw.Step = char(step); sw.Value = min(max(value, 0), 1);
            sw.Steps(end + 1) = struct('text', sw.Step, 'value', sw.Value, 'time', toc(sw.T0));
            if ~sw.isOpen(), return; end                 % closed by the user: start-up goes on
            sw.H.step.Text = sw.Step;
            v = sw.Value;
            if v <= 0
                sw.H.bar.ColumnWidth = {0, '1x'};
            elseif v >= 1
                sw.H.bar.ColumnWidth = {'1x', 0};
            else
                sw.H.bar.ColumnWidth = {sprintf('%.4fx', v), sprintf('%.4fx', 1 - v)};
            end
            drawnow;
        end

        function tf = isOpen(sw)
            tf = ~isempty(sw.Fig) && isvalid(sw.Fig);
        end

        function close(sw)
            if sw.isOpen(), delete(sw.Fig); end
        end

        function delete(sw)
            sw.close();
        end
    end
end
