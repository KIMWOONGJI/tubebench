classdef Checklist < handle
    %CHECKLIST List of steps with a status icon, detail text and duration.
    %
    %   cl = tim.gui.Checklist(parent, keys, labels)
    %   cl.set('teds', 'run', 'detecting ...')   % 'pending'|'run'|'ok'|'warn'|'fail'|'skip'
    %   cl.set('teds', 'ok', '4 of 4 inputs with TEDS')
    %   cl.rebuild(keys, labels)                 % new list (e.g. per calibration)
    %
    %   The 'run' icon is an animated GIF (tim.gui.icon): the figure window
    %   animates it, so it keeps turning while MATLAB waits for an instrument.
    %   The running row is highlighted and its duration is shown when it ends.

    properties (SetAccess = private)
        Grid
        Keys cell = {}
        States cell = {}
        Icons = gobjects(0)
        Labels = gobjects(0)
        Details = gobjects(0)
        Times = gobjects(0)
        Started = {}             % tic of the running step
    end
    properties
        RowHeight double = 24
        LabelWidth = 300
        FontSize double = 12
    end

    methods
        function obj = Checklist(parent, keys, labels, opts)
            if nargin >= 4
                for f = fieldnames(opts).', obj.(f{1}) = opts.(f{1}); end
            end
            obj.Grid = uigridlayout(parent, [1 4], 'ColumnWidth', {20, obj.LabelWidth, '1x', 60}, ...
                'RowSpacing', 3, 'ColumnSpacing', 8, 'Padding', [6 6 6 6], 'Scrollable', 'on');
            obj.rebuild(keys, labels);
        end

        function rebuild(obj, keys, labels)
            delete(obj.Grid.Children);
            n = numel(keys);
            obj.Keys = keys(:).'; obj.States = repmat({'pending'}, 1, n); obj.Started = cell(1, n);
            obj.Grid.RowHeight = repmat({obj.RowHeight}, 1, max(n, 1));
            obj.Icons = gobjects(1, n); obj.Labels = gobjects(1, n);
            obj.Details = gobjects(1, n); obj.Times = gobjects(1, n);
            for i = 1:n
                obj.Icons(i) = uiimage(obj.Grid, 'ImageSource', tim.gui.icon('pending'), 'ScaleMethod', 'fit');
                obj.Labels(i) = uilabel(obj.Grid, 'Text', labels{i}, 'FontSize', obj.FontSize);
                obj.Details(i) = uilabel(obj.Grid, 'Text', '', 'FontSize', obj.FontSize - 1, ...
                    'FontColor', [0.35 0.35 0.35]);
                obj.Times(i) = uilabel(obj.Grid, 'Text', '', 'FontSize', obj.FontSize - 1, ...
                    'HorizontalAlignment', 'right', 'FontColor', [0.45 0.45 0.45]);
                row = {obj.Icons(i), obj.Labels(i), obj.Details(i), obj.Times(i)};
                for k = 1:4
                    row{k}.Layout.Row = i; row{k}.Layout.Column = k;
                end
            end
        end

        function reset(obj)
            for i = 1:numel(obj.Keys)
                obj.paint(i, 'pending', '');
                obj.Times(i).Text = ''; obj.Started{i} = [];
            end
        end

        function set(obj, key, state, detail)
            i = find(strcmp(obj.Keys, key), 1);
            if isempty(i) || ~isvalid(obj.Icons(i)), return; end
            if nargin < 4, detail = []; end
            if strcmp(state, 'run')
                if ~strcmp(obj.States{i}, 'run'), obj.Started{i} = tic; end
                obj.Times(i).Text = '...';
            elseif ~isempty(obj.Started{i})
                obj.Times(i).Text = sprintf('%.1f s', toc(obj.Started{i}));
                obj.Started{i} = [];
            end
            obj.paint(i, state, detail);
            drawnow;
        end

        function appendDetail(obj, key, txt)
            i = find(strcmp(obj.Keys, key), 1);
            if isempty(i), return; end
            obj.Details(i).Text = [obj.Details(i).Text txt];
            obj.Details(i).Tooltip = obj.Details(i).Text;
        end

        function s = state(obj, key)
            i = find(strcmp(obj.Keys, key), 1);
            if isempty(i), s = ''; else, s = obj.States{i}; end
        end

        function k = runningKeys(obj)
            k = obj.Keys(strcmp(obj.States, 'run'));
        end
    end

    methods (Access = private)
        function paint(obj, i, state, detail)
            P = tim.gui.palette();
            obj.States{i} = state;
            obj.Icons(i).ImageSource = tim.gui.icon(state);
            if strcmp(state, 'run')
                bg = [0.88 0.94 1.00]; fw = 'bold';
            else
                bg = 'none'; fw = 'normal';
            end
            obj.Labels(i).BackgroundColor = bg; obj.Labels(i).FontWeight = fw;
            obj.Details(i).BackgroundColor = bg;
            switch state
                case 'fail', col = P.fail;
                case 'warn', col = 0.75 * P.warn;
                otherwise, col = [0.35 0.35 0.35];
            end
            obj.Details(i).FontColor = col;
            if ~isempty(detail)
                obj.Details(i).Text = detail;
                obj.Details(i).Tooltip = detail;      % full text when it does not fit
            elseif strcmp(state, 'pending')
                obj.Details(i).Text = ''; obj.Details(i).Tooltip = '';
            end
        end
    end
end
