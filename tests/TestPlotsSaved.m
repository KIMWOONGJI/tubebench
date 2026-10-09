classdef TestPlotsSaved < matlab.unittest.TestCase
    %TESTPLOTSSAVED Saved figures of a measurement (tim.app.plotResults, tim.app.exportFigures).
    %
    %   One figure per view, drawn by the same views as the GUI (tim.plots.*),
    %   with a header (title, description, note of the view), the summary
    %   table of the view drawn with text objects, and a footer.
    %   Data: a short simulated swept sine and stepped sine (mock instruments,
    %   processed without a calibration, ~3 s) and an analytic thin-screen
    %   result (calibrated: Z_t valid). All figures are invisible and deleted
    %   by the tests.

    properties
        mSweep     % simulated swept sine (metadata.WARNING: simulated data)
        rSweep     % processed without a calibration (lab tube, d = 75 mm: thick)
        mStep      % simulated stepped sine, 6 steps
        rStep
        thin       % analytic thin screen (d = 0), calibrated, no measurement
        figs       % plotResults(rSweep, mSweep), shared by the read-only tests
    end

    properties (Constant)
        Fields = {'waveforms', 'spectrum', 'transfer', 'reflection', 'transmissionLoss', 'impedance', 'validity'}
        Titles = {'Time signals', 'Spectrum', 'Transfer functions', 'Reflection and transmission', ...
            'Transmission loss', 'Transfer impedance', 'Validity'}
        NumAxes = [4 1 3 2 1 2 1]
    end

    methods (TestClassSetup)
        function simulate(tc)
            c = tim.app.defaultConfig();
            % lab tube: 75 mm specimen section (k*d > 1: thin-element model not applicable)
            c.simulation.Geometry.micPositions = [-0.070 -0.041 0.116 0.145];
            c.simulation.Geometry.xRear = 0.075;
            c.geometry = c.simulation.Geometry;
            c.excitation.sweep.duration = 1; c.excitation.sweep.repetitions = 1;
            c.excitation.sweep.preRoll = 0.3; c.excitation.sweep.postRoll = 0.2;
            c.excitation.stepped = struct('fStart', 200, 'fStop', 4000, 'nPoints', 6, 'spacing', 'log', ...
                'amplitudeVpp', 0.2, 'settleTime', 0.1, 'recordTime', 0.15, 'nBlocks', 2, 'repetitions', 1);
            s = tim.app.MeasurementSession(c);
            cleanup = onCleanup(@() s.close());
            s.connect(); s.prepareAcquisition();
            tc.mSweep = s.measure('sweep');
            tc.mStep = s.measure('stepped');
            tc.rSweep = tim.app.processMeasurement(tc.mSweep, c, []);
            tc.rStep = tim.app.processMeasurement(tc.mStep, c, []);
            clear cleanup
            tc.thin = TestPlotsSaved.thinResult();
            tc.figs = tim.app.plotResults(tc.rSweep, tc.mSweep, struct('Visible', 'off'));
            tc.addTeardown(@() TestPlotsSaved.deleteFigs(tc.figs));
        end
    end

    methods (Static)
        function res = thinResult()
            % analytic thin screen (tube model -> four-microphone analysis), calibrated
            g = struct('diameter', 0.029, 'micPositions', [-0.150 -0.121 0.071 0.100], ...
                'spacingUp', 0.029, 'spacingDown', 0.029, 'xFront', 0, 'xRear', 0);
            env = struct('temperature_C', 20, 'pressure_Pa', 101325, 'c_override', [], 'rho_override', []);
            f = (120:4:4500).';
            m = tim.sim.tubeModel(f, g, env, struct('type', 'thin', 'R', 400, 'm', 0.05), struct('R', 0.05, 'x', 0.6));
            H = m.p ./ m.p(:, 1); n = numel(f);
            o = struct('fRange', [120 4500], 'calValid', true(n, 1), ...
                'quality', struct('coherence', ones(n, 4), 'snr_dB', 60 * ones(n, 4)));
            res = struct('kind', 'sweep', 'timestamp', '2026-10-09 12:00:00', ...
                'calibration', struct('applied', true, 'version', 'CAL-20261009-120000'), ...
                'analysis', tim.acoustics.analyzeFourMic(f, H, g, env, o));
        end

        function deleteFigs(figs)
            if ~isstruct(figs), return; end
            fc = struct2cell(figs);
            for i = 1:numel(fc), if isgraphics(fc{i}), delete(fc{i}); end, end
        end

        function s = plain(s)
            % text of a figure / view without TeX markup (for comparisons)
            s = strjoin(cellstr(s), ' ');
            s = strrep(s, '{\angle}', char(8736));
            s = regexprep(s, '\\color\[rgb\]\{[^}]*\}', '');
            s = regexprep(s, '[\\{}_^]', '');
        end

        function [right, top, innerRight] = plotArea(fig)
            % right and top edge (px) of the axes with their labels (plot box +
            % TightInset) and the right edge of the plot boxes
            W = fig.Position(3); H = fig.Position(4);
            ax = findobj(fig, 'Type', 'axes');
            right = 0; top = 0; innerRight = 0;
            for i = 1:numel(ax)
                u = ax(i).Units; ax(i).Units = 'pixels';
                p = ax(i).Position; ti = ax(i).TightInset;
                ax(i).Units = u;
                right = max(right, p(1) + p(3) + ti(3));
                top = max(top, p(2) + p(4) + ti(4));
                innerRight = max(innerRight, p(1) + p(3));
            end
            right = min(right, W); top = min(top, H);
        end

        function ax = viewAxes(fig)
            % the axes of the view, top to bottom
            ax = findobj(fig, 'Type', 'axes');
            y = arrayfun(@(a) a.Position(2), ax);
            [~, i] = sort(y, 'descend'); ax = ax(i).';
        end

        function x = legendWidth(lg)
            u = lg.Units; lg.Units = 'pixels'; x = lg.Position(3); lg.Units = u;
        end
    end

    methods
        function f = savedFigures(tc, res, meas, opts)
            if nargin < 4, opts = struct(); end
            opts.Visible = 'off';
            f = tim.app.plotResults(res, meas, opts);
            tc.addTeardown(@() TestPlotsSaved.deleteFigs(f));
        end

        function verifyHouseStyle(tc, ax, label)
            % outward ticks, half a tick interval beyond the outermost ticks
            tc.verifyEqual(ax.TickDir, 'out', label);
            if strcmp(ax.XScale, 'log') && numel(ax.XTick) > 1
                r = ax.XTick(end) / ax.XTick(end - 1);          % octave ticks (31.5 is nominal): 2 or 4
                if abs(r - 10) > 1e-9, r = 2^round(log2(r)); end
                tc.verifyEqual(ax.XLim, [ax.XTick(1) / sqrt(r), ax.XTick(end) * sqrt(r)], 'RelTol', 1e-9, label);
            elseif numel(ax.XTick) > 1
                st = ax.XTick(2) - ax.XTick(1);
                tc.verifyEqual(ax.XLim, [ax.XTick(1) - st / 2, ax.XTick(end) + st / 2], 'AbsTol', 1e-9 * st, label);
            end
            if strcmp(ax.YDir, 'normal') && numel(ax.YTick) > 1
                st = ax.YTick(2) - ax.YTick(1);
                tc.verifyEqual(ax.YLim, [ax.YTick(1) - st / 2, ax.YTick(end) + st / 2], 'AbsTol', 1e-9 * st, label);
            end
        end
    end

    methods (Test)
        function oneFigurePerView(tc)
            f = tc.figs;
            tc.verifyEqual(fieldnames(f).', TestPlotsSaved.Fields, 'field names used by saveMeasurement / exportFigures');
            for i = 1:numel(TestPlotsSaved.Fields)
                fig = f.(TestPlotsSaved.Fields{i});
                tc.assertTrue(isgraphics(fig, 'figure'));
                tc.verifyEqual(fig.Visible, matlab.lang.OnOffSwitchState('off'), 'opts.Visible respected');
                tc.verifyEqual(fig.Color, [1 1 1]);
                tc.verifyEqual(fig.Position(3:4), [1200 700]);
                tc.verifyEqual(fig.Name, TestPlotsSaved.Titles{i});
                tc.verifyNumElements(findobj(fig, 'Type', 'axes'), TestPlotsSaved.NumAxes(i), fig.Name);
                tc.verifyEqual(findall(fig, 'Tag', 'timHeaderTitle').String, TestPlotsSaved.Titles{i});
                tc.verifyNotEmpty(findall(fig, 'Tag', 'timHeaderDescription'));
                tc.verifySubstring(findall(fig, 'Tag', 'timFooter').String, 'transfer-impedance-tube-measurement');
                info = getappdata(fig, 'timViewInfo');
                tc.verifyTrue(isstruct(info) && isfield(info, 'summary'), fig.Name);
            end
            % figure size option
            g = tim.app.plotResults(tc.rSweep, tc.mSweep, struct('Visible', 'off', 'Size', [1000 640]));
            tc.addTeardown(@() TestPlotsSaved.deleteFigs(g));
            tc.verifyEqual(g.reflection.Position(3:4), [1000 640], 'opts.Size');
        end

        function drawnBySameViewsAsGui(tc)
            % the info of every saved figure equals a direct call of the view
            o = struct('simulation', true);
            fig = figure('Visible', 'off', 'Position', [50 50 1100 650]);
            tc.addTeardown(@() delete(fig));
            calls = {@(ax) tim.plots.timeSignals(ax, tc.mSweep, o), 4
                @(ax) tim.plots.spectrum(ax, tc.mSweep, tc.rSweep, o), 1
                @(ax) tim.plots.transferFunctions(ax, tc.rSweep, o), 3
                @(ax) tim.plots.reflection(ax, tc.rSweep, o), 2
                @(ax) tim.plots.transmissionLoss(ax, tc.rSweep, o), 1
                @(ax) tim.plots.transferImpedance(ax, tc.rSweep, o), 2
                @(ax) tim.plots.validity(ax, tc.rSweep, o), 1};
            for i = 1:size(calls, 1)
                clf(fig);
                tl = tiledlayout(fig, calls{i, 2}, 1);
                ax = gobjects(1, calls{i, 2});
                for k = 1:calls{i, 2}, ax(k) = nexttile(tl); end
                ref = calls{i, 1}(ax);
                saved = tc.figs.(TestPlotsSaved.Fields{i});
                info = getappdata(saved, 'timViewInfo');
                tc.verifyEqual(info.summary, ref.summary, saved.Name);
                tc.verifyEqual(info.note, ref.note, saved.Name);
                sax = TestPlotsSaved.viewAxes(saved);
                tc.verifyEqual(sax(1).Title.String, ax(1).Title.String, [saved.Name ': title (dataTitle)']);
                tc.verifyEqual(sax(end).XLabel.String, ax(end).XLabel.String);
                tc.verifyEqual(numel(findobj(sax(1), 'Type', 'line')), numel(findobj(ax(1), 'Type', 'line')), saved.Name);
            end
        end

        function summaryDrawnAsTextTable(tc)
            for i = 1:numel(TestPlotsSaved.Fields)
                fig = tc.figs.(TestPlotsSaved.Fields{i});
                S = getappdata(fig, 'timViewInfo').summary;
                cells = findall(fig, 'Tag', 'timSummaryCell');
                tc.verifyNumElements(cells, numel(S.data), fig.Name);
                for k = 1:numel(cells)
                    rc = cells(k).UserData;
                    v = S.data{rc(1), rc(2)};
                    if isnumeric(v), v = sprintf('%d', v); end
                    tc.verifyEqual(TestPlotsSaved.plain(cells(k).String), TestPlotsSaved.plain(v), fig.Name);
                end
                head = findall(fig, 'Tag', 'timSummaryHeading');
                tc.verifyNumElements(head, numel(S.columns), fig.Name);
                hText = sort(arrayfun(@(h) TestPlotsSaved.plain(h.String), head, 'UniformOutput', false));
                tc.verifyEqual(hText, sort(cellfun(@TestPlotsSaved.plain, S.columns(:), 'UniformOutput', false)), ...
                    [fig.Name ': headings (name, unit in the last line)']);
                tc.verifyEqual(findall(fig, 'Tag', 'timSummaryTitle').String, S.title);
                tc.verifyNumElements(findall(fig, 'Tag', 'timSummaryRule'), 3, 'rules: top, below the headings, bottom');
                if ~isempty(S.note)
                    tc.verifyEqual(TestPlotsSaved.plain(findall(fig, 'Tag', 'timSummaryNote').String), ...
                        TestPlotsSaved.plain(S.note), fig.Name);
                end
                note = getappdata(fig, 'timViewInfo').note;
                h = findall(fig, 'Tag', 'timHeaderNote');
                if isempty(note)
                    tc.verifyEmpty(h, fig.Name);
                else
                    tc.verifyEqual(TestPlotsSaved.plain(h.String), TestPlotsSaved.plain(note), fig.Name);
                end
                % numbers right-aligned (Validity: Passing), names left-aligned
                if strcmp(fig.Name, 'Validity')
                    c2 = cells(arrayfun(@(c) c.UserData(2) == 2, cells));
                    tc.verifyEqual(unique({c2.HorizontalAlignment}), {'right'});
                    c1 = cells(arrayfun(@(c) c.UserData(2) == 1, cells));
                    tc.verifyEqual(unique({c1.HorizontalAlignment}), {'left'});
                end
            end
        end

        function nothingOverlaps(tc)
            % header above the axes, table right of the axes and of the axes title,
            % every text inside the figure
            for i = 1:numel(TestPlotsSaved.Fields)
                fig = tc.figs.(TestPlotsSaved.Fields{i});
                W = fig.Position(3); H = fig.Position(4);
                ov = findall(fig, 'Tag', 'timSavedOverlay');
                tc.assertNumElements(ov, 1);
                tc.verifyEqual([ov.XLim ov.YLim], [0 W 0 H], 'overlay: data units = pixels');
                rules = findall(fig, 'Tag', 'timSummaryRule');
                xTable = min(arrayfun(@(r) min(r.XData), rules));
                tc.verifyEqual(max(arrayfun(@(r) max(r.XData), rules)), W - 18, 'AbsTol', 1e-6, 'table at the right margin');
                [right, top, innerRight] = TestPlotsSaved.plotArea(fig);
                tc.verifyLessThan(right, xTable - 8, [fig.Name ': axes and labels left of the table']);
                ax = TestPlotsSaved.viewAxes(fig);
                t = ax(1).Title; u = t.Units;
                t.Units = 'normalized'; en = t.Extent; t.Units = 'pixels'; ep = t.Extent; t.Units = u;
                tc.verifyLessThan(innerRight + (en(1) + en(3) - 1) * ep(3) / en(3), xTable, ...
                    [fig.Name ': axes title clear of the table']);
                txt = findall(ov, 'Type', 'text');
                for k = 1:numel(txt)
                    e = txt(k).Extent;
                    tc.verifyGreaterThanOrEqual(e(1), -0.5, [fig.Name ' ' txt(k).Tag]);
                    tc.verifyLessThanOrEqual(e(1) + e(3), W + 0.5, [fig.Name ' ' txt(k).Tag]);
                    tc.verifyGreaterThanOrEqual(e(2), -0.5, [fig.Name ' ' txt(k).Tag]);
                    tc.verifyLessThanOrEqual(e(2) + e(4), H + 0.5, [fig.Name ' ' txt(k).Tag]);
                end
                hr = findall(fig, 'Tag', 'timHeaderRule');
                tc.verifyLessThan(top, hr.YData(1), [fig.Name ': axes and title below the header']);
                tc.verifyLessThan(max(arrayfun(@(r) max(r.YData), rules)), hr.YData(1), 'table below the header');
                % stacked axes: plot boxes aligned left and right
                if numel(ax) > 1
                    p = vertcat(ax.Position);
                    tc.verifyEqual(p(:, 1), repmat(p(1, 1), numel(ax), 1), 'AbsTol', 1e-9, fig.Name);
                    tc.verifyEqual(p(:, 3), repmat(p(1, 3), numel(ax), 1), 'AbsTol', 1e-9, fig.Name);
                end
            end
        end

        function houseStyleOnEveryAxes(tc)
            for i = 1:numel(TestPlotsSaved.Fields)
                fig = tc.figs.(TestPlotsSaved.Fields{i});
                ax = TestPlotsSaved.viewAxes(fig);
                for k = 1:numel(ax)
                    tc.verifyHouseStyle(ax(k), sprintf('%s, axes %d', fig.Name, k));
                    tc.verifyEqual(ax(k).FontName, 'Arial', 'Arial: Greek letters and the minus sign in a vector PDF');
                end
                tc.verifyNotEmpty(ax(1).Title.String, 'dataTitle on the top axes');
                for k = 2:numel(ax)
                    tc.verifyEmpty(strtrim(ax(k).Title.String), 'multi-axes view: title on the top axes only');
                end
            end
            lg = findall(tc.figs.reflection, 'Type', 'legend');
            tc.verifyEqual(lg.FontName, 'Arial');
        end

        function simulatedDataMarked(tc)
            tc.verifyNotEmpty(findall(tc.figs.validity, 'Tag', 'timSimulationMark'));
            for i = 1:numel(TestPlotsSaved.Fields)
                ax = TestPlotsSaved.viewAxes(tc.figs.(TestPlotsSaved.Fields{i}));
                tc.verifySubstring(ax(1).Title.String, 'SIMULATION', TestPlotsSaved.Fields{i});
            end
            m = tc.mSweep; m.metadata = rmfield(m.metadata, 'WARNING');      % "hardware" data
            f = tc.savedFigures(tc.rSweep, m);
            tc.verifyEmpty(findall(f.reflection, 'Tag', 'timSimulationMark'));
            ax = TestPlotsSaved.viewAxes(f.reflection);
            tc.verifyFalse(contains(ax(1).Title.String, 'SIMULATION'));
            f = tc.savedFigures(tc.rSweep, m, struct('simulation', true));      % explicit option wins
            tc.verifyNotEmpty(findall(f.transmissionLoss, 'Tag', 'timSimulationMark'));
        end

        function thickAndThinSpecimen(tc)
            % lab tube (d = 75 mm): no Z_t curves, the reason in the axes and in the table note
            % (the header note gives priority to the missing calibration)
            info = getappdata(tc.figs.impedance, 'timViewInfo');
            tc.verifyEmpty(info.lines);
            ax = TestPlotsSaved.viewAxes(tc.figs.impedance);
            tc.verifySubstring(TestPlotsSaved.plain(findobj(ax(1), 'Tag', 'timEmptyState').String), ...
                'Thin-element model not applicable');
            tc.verifySubstring(findall(tc.figs.impedance, 'Tag', 'timSummaryNote').String{1}, 'Thin-element');
            tc.verifySubstring(TestPlotsSaved.plain(findall(tc.figs.impedance, 'Tag', 'timHeaderNote').String), ...
                'No calibration applied');
            tc.verifyNumElements(getappdata(tc.figs.transmissionLoss, 'timViewInfo').lines, 1, 'no TL from Z_t');
            % thin screen: Re / Im drawn, numbers in the table, TL from Z_t too
            f = tc.savedFigures(tc.thin, []);
            info = getappdata(f.impedance, 'timViewInfo');
            tc.verifyNumElements(info.lines, 2);
            tc.verifyTrue(any(~strcmp(info.summary.data(:, 2), char(8211))), 'valid band values');
            tc.verifyEmpty(findall(f.impedance, 'Tag', 'timHeaderNote'));
            tc.verifyNumElements(getappdata(f.transmissionLoss, 'timViewInfo').lines, 2);
            tc.verifyNumElements(findall(f.transmissionLoss, 'Tag', 'timSummaryHeading'), 3);
            % no measurement: the measurement views show their empty state, the results are drawn
            tc.verifyNotEmpty(findobj(f.waveforms, 'Tag', 'timEmptyState'));
            tc.verifyEmpty(findobj(f.reflection, 'Tag', 'timEmptyState'));
        end

        function steppedSineWithMarkers(tc)
            f = tc.savedFigures(tc.rStep, tc.mStep);
            L = findobj(f.spectrum, 'Type', 'line', 'Marker', 'o');
            tc.verifyNumElements(L, 4, 'one step-level series per channel');
            tc.verifyEqual(sort(L(1).XData(:)), tc.mStep.settings.frequencies(:), 'RelTol', 1e-12);
            tc.verifyEmpty(findobj(f.validity, 'Type', 'image'), 'log-spaced steps not drawn with imagesc');
            ax = TestPlotsSaved.viewAxes(f.reflection);
            tc.verifyNotEmpty(findobj(ax(1), 'Type', 'line', 'Marker', 'o'));
            tc.verifySubstring(ax(1).Title.String, 'Stepped sine');
            tc.verifyEqual(findall(f.spectrum, 'Tag', 'timSummaryTitle').String, 'Step levels');
        end

        function emptyInputs(tc)
            f = tc.verifyWarningFree(@() tim.app.plotResults([], [], struct('Visible', 'off')));
            tc.addTeardown(@() TestPlotsSaved.deleteFigs(f));
            tc.verifyEqual(fieldnames(f).', TestPlotsSaved.Fields);
            for i = 1:numel(TestPlotsSaved.Fields)
                fig = f.(TestPlotsSaved.Fields{i});
                tc.verifyNotEmpty(findobj(fig, 'Tag', 'timEmptyState'), fig.Name);
                tc.verifyEmpty(findall(fig, 'Tag', 'timSimulationMark'));
                tc.verifyNumElements(findobj(fig, 'Type', 'axes'), TestPlotsSaved.NumAxes(i));
            end
        end

        function failingViewDoesNotStopTheOthers(tc)
            bad = tc.rSweep; bad.analysis = rmfield(bad.analysis, 'valid');   % result views cannot draw
            f = tc.verifyWarning(@() tim.app.plotResults(bad, tc.mSweep, struct('Visible', 'off')), ...
                'tim:plotResults:view');
            tc.addTeardown(@() TestPlotsSaved.deleteFigs(f));
            tc.verifyEqual(fieldnames(f).', TestPlotsSaved.Fields);
            tc.verifySubstring(findobj(f.reflection, 'Tag', 'timEmptyState').String, 'could not be drawn');
            tc.verifyEmpty(findobj(f.waveforms, 'Tag', 'timEmptyState'), 'the time signals are still drawn');
        end

        function exportPngAndPdf(tc)
            d = tc.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture).Folder;
            f = tc.savedFigures(tc.thin, []);
            lg = findall(f.transmissionLoss, 'Type', 'legend');
            w0 = TestPlotsSaved.legendWidth(lg);
            files = tim.app.exportFigures(f, d, {'png', 'pdf'});
            tc.verifyNumElements(files, 2 * numel(TestPlotsSaved.Fields));
            for i = 1:numel(files)
                tc.verifyTrue(isfile(files{i}), files{i});
            end
            tc.verifyTrue(isfile(fullfile(d, 'fig_reflection.png')));
            tc.verifyTrue(isfile(fullfile(d, 'fig_transmissionLoss.pdf')));
            % regression: the export must not shrink the legend box below its text
            tc.verifyEqual(TestPlotsSaved.legendWidth(lg), w0, 'AbsTol', 1);
            im = imread(fullfile(d, 'fig_validity.png'));
            tc.verifyGreaterThan(size(im, 2), 1.5 * 1200, 'PNG at 200 dpi, not cropped to the axes');
        end

        function resizeArrangesAgain(tc)
            f = tc.savedFigures(tc.rSweep, tc.mSweep);
            fig = f.transfer;
            fig.Position(3:4) = [1000 760];
            fig.SizeChangedFcn(fig, []);                     % invisible figure: call it as on a resize
            ov = findall(fig, 'Tag', 'timSavedOverlay');
            tc.verifyEqual([ov.XLim ov.YLim], [0 1000 0 760]);
            rules = findall(fig, 'Tag', 'timSummaryRule');
            tc.verifyEqual(max(arrayfun(@(r) max(r.XData), rules)), 1000 - 18, 'AbsTol', 1e-6);
            tc.verifyEqual(findall(fig, 'Tag', 'timHeaderTitle').Position(2), 760 - 12, 'AbsTol', 1e-6);
            tc.verifyNumElements(findall(fig, 'Tag', 'timHeaderTitle'), 1, 'redrawn, not duplicated');
            tc.verifyLessThan(TestPlotsSaved.plotArea(fig), min(arrayfun(@(r) min(r.XData), rules)) - 8);
        end
    end
end
