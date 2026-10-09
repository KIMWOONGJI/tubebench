classdef ViewPage < handle
    %VIEWPAGE One view of the right-hand side of the window.
    %   A header strip (title, one-line description, optional note, optional
    %   tools on the right), the body (stacked axes or custom content) and an
    %   optional summary panel (title, table, note) on the right.
    %
    %   p = tim.gui.ViewPage(tab, 'Reflection & transmission', 'R at the front face ...', ...
    %           'Axes', 2, 'AxesHeights', {'2x', '1x'});
    %   info = tim.plots.reflection(p.Axes, res, opts);
    %   p.show(info)                 % summary table + note of a tim.plots view
    %   p.Body                       % grid for custom content ('Axes', 0)
    %   p.Tools                      % grid in the header for buttons / check boxes
    %
    %   The axes are styled with tim.plots.style and get a small toolbar
    %   (zoom, pan, restore view, export).

    properties (SetAccess = private)
        Grid
        Header
        Title
        Description
        Note
        Tools = []
        Body
        Axes = gobjects(0)
        SummaryPanel = []
        SummaryTitle = []
        SummaryTable = []
        SummaryNote = []
    end

    methods
        function p = ViewPage(parent, title, description, opts)
            arguments
                parent
                title (1,:) char
                description (1,:) char = ''
                opts.Axes double = 0
                opts.AxesHeights cell = {}
                opts.Summary logical = true
                opts.SummaryWidth double = 320
                opts.SummaryTitle (1,:) char = 'Summary'
                opts.ToolWidths cell = {}
            end
            P = tim.gui.palette();
            p.Grid = uigridlayout(parent, [2 1], 'RowHeight', {72, '1x'}, 'Padding', [0 0 0 0], ...
                'RowSpacing', 0, 'BackgroundColor', 'w');
            % ---- header strip
            nt = numel(opts.ToolWidths);
            p.Header = uigridlayout(p.Grid, [3 2], 'RowHeight', {24, 18, 0}, 'ColumnWidth', {'1x', 'fit'}, ...
                'Padding', [14 8 14 6], 'RowSpacing', 2, 'ColumnSpacing', 12, 'BackgroundColor', P.ui.header);
            p.Title = uilabel(p.Header, 'Text', title, 'FontSize', 15, 'FontWeight', 'bold', 'FontColor', P.ui.text);
            p.Title.Layout.Row = 1; p.Title.Layout.Column = 1;
            p.Description = uilabel(p.Header, 'Text', description, 'FontSize', 11, 'FontColor', P.ui.muted);
            p.Description.Layout.Row = 2; p.Description.Layout.Column = 1;
            p.Note = uilabel(p.Header, 'Text', '', 'FontSize', 11, 'FontColor', [0.62 0.36 0.00], 'FontWeight', 'bold');
            p.Note.Layout.Row = 3; p.Note.Layout.Column = [1 2];
            if nt > 0
                p.Tools = uigridlayout(p.Header, [1 nt], 'ColumnWidth', opts.ToolWidths, 'RowHeight', {26}, ...
                    'Padding', [0 0 0 0], 'ColumnSpacing', 6, 'BackgroundColor', P.ui.header);
                p.Tools.Layout.Row = [1 2]; p.Tools.Layout.Column = 2;
            end
            % ---- body (+ summary on the right)
            if opts.Summary
                bg = uigridlayout(p.Grid, [1 2], 'ColumnWidth', {'1x', opts.SummaryWidth}, ...
                    'Padding', [8 6 12 8], 'ColumnSpacing', 12, 'BackgroundColor', 'w');
            else
                bg = uigridlayout(p.Grid, [1 1], 'Padding', [8 6 12 8], 'BackgroundColor', 'w');
            end
            bg.Layout.Row = 2; bg.Layout.Column = 1;
            p.Body = uigridlayout(bg, [1 1], 'Padding', [0 0 0 0], 'BackgroundColor', 'w');
            p.Body.Layout.Row = 1; p.Body.Layout.Column = 1;
            if opts.Axes > 0
                % stacked axes in a tiledlayout: the plot areas line up although the
                % tick labels of the axes differ in width (a grid of uiaxes does not)
                pnl = uipanel(p.Body, 'BorderType', 'none', 'BackgroundColor', 'w');
                n = opts.Axes;
                w = ones(1, n);
                for i = 1:min(n, numel(opts.AxesHeights))
                    v = sscanf(char(opts.AxesHeights{i}), '%fx');
                    if ~isempty(v) && v > 0, w(i) = round(v); end
                end
                tl = tiledlayout(pnl, sum(w), 1, 'TileSpacing', 'compact', 'Padding', 'compact');
                for i = 1:n
                    ax = nexttile(tl, [w(i) 1]);
                    tim.plots.style(ax);
                    axtoolbar(ax, {'export', 'zoomin', 'zoomout', 'pan', 'restoreview'});
                    p.Axes(i) = ax;
                end
            end
            if opts.Summary
                sg = uigridlayout(bg, [3 1], 'RowHeight', {22, '1x', 96}, 'Padding', [0 0 0 0], ...
                    'RowSpacing', 4, 'BackgroundColor', 'w');
                sg.Layout.Row = 1; sg.Layout.Column = 2;
                p.SummaryPanel = sg;
                p.SummaryTitle = uilabel(sg, 'Text', opts.SummaryTitle, 'FontWeight', 'bold', 'FontSize', 12, ...
                    'FontColor', P.ui.text);
                p.SummaryTable = uitable(sg, 'Data', {}, 'ColumnName', {}, 'RowName', {}, 'FontSize', 11, ...
                    'ColumnSortable', false, 'RowStriping', 'on');
                p.SummaryNote = uilabel(sg, 'Text', '', 'FontSize', 11, 'FontColor', P.ui.muted, ...
                    'WordWrap', 'on', 'VerticalAlignment', 'top');
            end
        end

        function setNote(p, txt, status)
            % highlighted line under the description (empty = hidden);
            % status 'ok' | 'warn' (default) | 'fail' | 'info' sets the colour
            if nargin < 3 || isempty(status), status = 'warn'; end
            P = tim.gui.palette();
            switch status
                case 'ok', col = 0.85 * P.ok;
                case 'fail', col = P.fail;
                case 'info', col = P.ui.muted;
                otherwise, col = [0.62 0.36 0.00];
            end
            if nargin < 2 || isempty(txt)
                p.Note.Text = ''; p.Header.RowHeight{3} = 0; p.Grid.RowHeight{1} = 72;
            else
                p.Note.Text = txt; p.Note.FontColor = col; p.Header.RowHeight{3} = 18; p.Grid.RowHeight{1} = 92;
            end
        end

        function setDescription(p, txt)
            p.Description.Text = txt;
        end

        function setSummary(p, s)
            % s: struct('title', ..., 'columns', {...}, 'data', {...}, 'note', ...)
            if isempty(p.SummaryTable), return; end
            if nargin < 2 || isempty(s) || ~isstruct(s)
                p.SummaryTable.Data = {}; p.SummaryTable.ColumnName = {}; p.SummaryNote.Text = ''; return
            end
            if isfield(s, 'title') && ~isempty(s.title), p.SummaryTitle.Text = s.title; end
            cols = {}; if isfield(s, 'columns'), cols = s.columns; end
            dat = {}; if isfield(s, 'data'), dat = s.data; end
            if isnumeric(dat), dat = num2cell(dat); end
            % a uitable splits a column name at '|': |R| -> ∣R∣ (U+2223)
            cols = cellfun(@(s) strrep(char(s), '|', char(8739)), cellstr(cols), 'UniformOutput', false);
            p.SummaryTable.ColumnName = cols;
            p.SummaryTable.Data = dat;
            if ~isempty(cols), p.SummaryTable.ColumnWidth = p.columnWidths(cols, dat); end
            nt = ''; if isfield(s, 'note'), nt = s.note; end
            p.SummaryNote.Text = nt;
        end

        function w = columnWidths(p, cols, dat)
            % widths from the longest text of every column (about 7 px per character
            % at 11 pt), scaled down to the width of the summary panel if needed
            n = numel(cols); len = zeros(1, n);
            for c = 1:n
                len(c) = numel(cols{c});
                for r = 1:size(dat, 1)
                    if c <= size(dat, 2)
                        v = dat{r, c};
                        if isnumeric(v), v = num2str(v); end
                        len(c) = max(len(c), numel(char(v)));
                    end
                end
            end
            px = 7 * len + 14;
            avail = p.SummaryPanel.Parent.ColumnWidth{2} - 4;
            if sum(px) > avail
                px = max(30, floor(px * avail / sum(px)));
                ex = sum(px) - avail;                 % the 30 px floor can exceed the panel:
                if ex > 0, [~, i] = max(px); px(i) = max(30, px(i) - ex); end   % take it from the widest column
            end
            w = num2cell(px);
        end

        function show(p, info)
            % summary table and header note of a tim.plots view
            if isfield(info, 'summary'), p.setSummary(info.summary); else, p.setSummary([]); end
            st = 'warn'; if isfield(info, 'status') && ~isempty(info.status), st = info.status; end
            if isfield(info, 'note'), p.setNote(info.note, st); else, p.setNote(''); end
        end
    end
end
