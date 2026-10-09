classdef TestPlotsCalibration < matlab.unittest.TestCase
    %TESTPLOTSCALIBRATION Calibration view tim.plots.calibration and the
    %   saved figure tim.app.plotCalibration (hidden figures only).

    properties
        f = (120:5:4500).'
    end

    methods
        function cal = makeCal(tc, opts)
            % calibration from exact sensor-switching data (TestCalibration
            % scenario): channel k has a gain / phase mismatch growing with f
            if nargin < 2, opts = struct(); end
            fq = tc.f; s = 1j * fq / 3;
            cref = 11.2e-3 * s ./ (1 + s);
            pa = ones(size(fq)); pb = 0.9 * exp(-1j * 2 * pi * fq * 0.029 / 343);   % p_b / p_a: 29 mm apart
            gain = [1 1.05 0.96 1.03]; ph = [0 -4 3 -5];
            results = cell(1, 4);
            for k = 2:4
                if isfield(opts, 'skip') && any(opts.skip == k), continue; end
                ck = gain(k) * 11.2e-3 * exp(1j * deg2rad(ph(k)) * fq / 4500) .* s ./ (1 + s);
                HI = (ck .* pb) ./ (cref .* pa); HII = (ck .* pa) ./ (cref .* pb);
                o = struct();
                coh = ones(size(fq));
                if k == 2, coh(fq > 2000 & fq < 2300) = 0.5; end          % invalid bins on ch2
                o.cohI = coh; o.cohII = ones(size(fq));
                if k ~= 3, o.HIrepeat = HI * 10^(0.02 / 20) * exp(1j * deg2rad(0.1 * (k - 1))); end
                results{k} = tim.cal.switchingCorrection(fq, HI, HII, o);
            end
            meta = struct('mode', 'simulation', 'emptyCheck', struct('performed', true, 'passed', true, ...
                'text', 'Test E, empty specimen section (d = 75 mm): passed (|τ| error 0.002)'));
            cal = tim.cal.buildCalibration(fq, results, 1, meta);
        end

        function [ax, fig] = newAxes(tc)
            fig = figure('Visible', 'off');
            tc.addTeardown(@() close(fig));
            tl = tiledlayout(fig, 2, 1);
            ax = [nexttile(tl), nexttile(tl)];
        end
    end

    methods (Test)
        function curvesColoursLegendTitle(tc)
            cal = tc.makeCal();
            ax = tc.newAxes();
            info = tim.plots.calibration(ax, cal);
            P = tim.gui.palette();
            for k = 2:4
                hM = findobj(ax(1), 'Tag', sprintf('calMag%d', k));
                hP = findobj(ax(2), 'Tag', sprintf('calPhase%d', k));
                tc.verifyNumElements(hM, 1); tc.verifyNumElements(hP, 1);
                tc.verifyEqual(hM.Color, P.ch(k, :), 'colour of DAQ channel k');
                tc.verifyEqual(hP.Color, P.ch(k, :));
                ok = cal.valid(:, k);
                tc.verifyEqual(hM.YData(ok), 20 * log10(abs(cal.C(ok, k))).', 'AbsTol', 1e-12);
                tc.verifyEqual(hP.YData(ok), rad2deg(unwrap(angle(cal.C(ok, k)))).', 'AbsTol', 1e-9);
            end
            tc.verifyNumElements(findobj(ax(1), 'Type', 'line'), 6, 'grey + coloured curve per channel');
            tc.verifySize(info.lines, [2 3]);
            tc.verifyEqual(info.legend.String, {'ch2 / ch1', 'ch3 / ch1', 'ch4 / ch1'});
            tc.verifyEqual(ax(1).Title.String, tim.plots.dataTitle(cal, struct('simulation', true)), ...
                'a calibration made in simulation is marked SIMULATION');
            tc.verifyEmpty(ax(2).Title.String, 'only the top axes has a title');
            tc.verifyEqual(ax(1).YLabel.String, '|C_k| [dB]');
            tc.verifyEqual(ax(2).YLabel.String, '\angleC_k [\circ]');
            tc.verifyEqual(ax(2).XLabel.String, 'Frequency [Hz]');
            tc.verifyEqual({ax.XScale}, {'log', 'log'});
            tc.verifyEqual({ax.TickDir}, {'out', 'out'});
            tc.verifyEmpty(findobj(ax, 'Tag', 'timEmptyState'));
        end

        function invalidBinsGrey(tc)
            cal = tc.makeCal();
            bad = ~cal.valid(:, 2);
            tc.assertTrue(any(bad) && any(~bad));
            ax = tc.newAxes();
            tim.plots.calibration(ax, cal);
            hM = findobj(ax(1), 'Tag', 'calMag2');
            tc.verifyTrue(all(isnan(hM.YData(bad))), 'invalid bins are not drawn in colour');
            tc.verifyTrue(all(isfinite(hM.YData(~bad))));
            P = tim.gui.palette();
            grey = findobj(ax(1), 'Type', 'line', 'Color', P.invalid);
            tc.verifyNumElements(grey, 3, 'whole curve in grey underneath');
            tc.verifyTrue(any(cellfun(@(y) all(isfinite(y)), get(grey, 'YData'))));
        end

        function limitsHalfTickAndLinked(tc)
            cal = tc.makeCal();
            ax = tc.newAxes();
            tim.plots.calibration(ax, cal);
            for a = ax
                xt = a.XTick;
                tc.verifyEqual(a.XLim, [xt(1) / sqrt(2), xt(end) * sqrt(2)], 'RelTol', 1e-9, 'octave ticks, half a tick margin');
                yt = a.YTick; st = yt(2) - yt(1);
                tc.verifyEqual(a.YLim, [yt(1) - st / 2, yt(end) + st / 2], 'AbsTol', 1e-9);
                tc.verifyTrue(any(abs(yt) < 1e-12), '0 dB / 0 deg is always a tick');
                tc.verifyLessThanOrEqual(numel(yt), 7);
            end
            tc.verifyEqual(ax(1).XTick, [125 250 500 1000 2000 4000]);
            ax(1).XLim = [500 1000];                  % zoom in one axes zooms the other
            tc.verifyEqual(ax(2).XLim, [500 1000]);
        end

        function summaryTable(tc)
            cal = tc.makeCal();
            ax = tc.newAxes();
            info = tim.plots.calibration(ax, cal);
            s = info.summary;
            tc.verifyEqual(s.title, 'Calibration factors Ck = gk/gref', 'chain gain g_k, calibration factor C_k = g_k/g_ref');
            tc.verifyNumElements(s.columns, 5);
            tc.verifyFalse(any(contains(s.columns, '|')), 'a uitable splits headings at |');
            tc.verifySize(s.data, [3 5]);
            tc.verifyEqual(s.data(:, 1).', {'ch2 / ch1', 'ch3 / ch1', 'ch4 / ch1'});
            ok = cal.valid(:, 2);
            tc.verifyEqual(s.data{1, 2}, sprintf('%.1f', 100 * mean(ok)));
            m = 20 * log10(abs(cal.C(ok, 2)));
            tc.verifyEqual(s.data{1, 3}, sprintf('%.2f %s %.2f', min(m), char(8230), max(m)));
            r = cal.results{2}.repeatability;
            tc.verifyEqual(s.data{1, 5}, sprintf('%.2f / %.2f', r.maxMag_dB, r.maxPhase_deg));
            tc.verifyEqual(s.data{2, 5}, char(8211), 'configuration I not repeated for ch3');
            tc.verifySubstring(s.note, '120');
            tc.verifyEqual(info.note, cal.meta.emptyCheck.text);
            tc.verifyEqual(info.status, 'ok');
            tc.verifyTrue(info.emptyCheck.performed && info.emptyCheck.passed);
        end

        function emptyTubeCheckVariants(tc)
            cal = tc.makeCal();
            ax = tc.newAxes();
            c = cal; c.meta.emptyCheck.passed = false;
            c.meta.emptyCheck.text = ['Test E, empty specimen section (d = 75 mm): failed ' char(8211) ' check s1'];
            info = tim.plots.calibration(ax, c);
            tc.verifyEqual(info.status, 'fail'); tc.verifySubstring(info.note, 'failed');
            c = cal; c.meta.emptyCheck = struct('performed', true, 'passed', false);   % no text field
            info = tim.plots.calibration(ax, c);
            tc.verifyEqual(info.note, 'Empty-tube check (Test E): failed');
            c = cal; c.meta.emptyCheck = struct('performed', false, 'passed', false, 'text', ...
                ['stopped by the operator ' char(8211) ' calibration saved without the empty-tube check']);
            info = tim.plots.calibration(ax, c);
            tc.verifyEqual(info.status, 'warn');
            tc.verifyTrue(startsWith(info.note, 'Empty-tube check (Test E) stopped by the operator'), info.note);
            c = cal; c.meta.emptyCheck = struct('performed', false, 'passed', false, 'text', 'not performed: disabled');
            info = tim.plots.calibration(ax, c);
            tc.verifyEqual(info.status, 'warn');
            tc.verifyEqual(info.note, 'Empty-tube check (Test E) not performed: disabled');
            c = cal; c.meta = rmfield(c.meta, 'emptyCheck');               % file older than the check
            info = tim.plots.calibration(ax, c);
            tc.verifyEqual(info.status, 'warn'); tc.verifyFalse(info.emptyCheck.recorded);
            tc.verifySubstring(info.note, 'not recorded');
            c = cal; c.meta.emptyCheck = struct('performed', true, 'passed', true);   % no text field
            info = tim.plots.calibration(ax, c);
            tc.verifyEqual(info.note, 'Empty-tube check (Test E): passed');
            c = cal; c.meta = struct();                                     % no mode -> no SIMULATION mark
            tim.plots.calibration(ax, c);
            tc.verifyFalse(contains(ax(1).Title.String, 'SIMULATION'));
            tim.plots.calibration(ax, c, struct('simulation', true));
            tc.verifySubstring(ax(1).Title.String, 'SIMULATION');
        end

        function channelNotCalibrated(tc)
            cal = tc.makeCal(struct('skip', 3));
            ax = tc.newAxes();
            info = tim.plots.calibration(ax, cal);
            tc.verifyEmpty(findobj(ax, 'Tag', 'calMag3'));
            tc.verifyEqual(info.legend.String, {'ch2 / ch1', 'ch4 / ch1'});
            tc.verifyEqual(info.summary.data(2, :), {'ch3 / ch1', '0.0', char(8211), char(8211), char(8211)});
            tc.verifyEqual(info.status, 'fail');
            tc.verifySubstring(info.note, 'Not calibrated: ch3');
            % calibrated but no valid bin (e.g. reversed polarity): grey curve, still on the axes
            c = tc.makeCal(); c.C(:, 4) = -2 * c.C(:, 4); c.valid(:, 4) = false;
            info = tim.plots.calibration(ax, c);
            tc.verifyEqual(info.legend.String{3}, 'ch4 / ch1 (no valid frequency line)');
            tc.verifySubstring(info.note, 'No valid frequency line: ch4');
            tc.verifyGreaterThan(ax(1).YLim(2), 20 * log10(2), 'the implausible channel is visible');
            tc.verifyGreaterThan(max(abs(ax(2).YLim)), 170, 'phase near 180 deg is visible');
        end

        function emptyState(tc)
            ax = tc.newAxes();
            info = tim.plots.calibration(ax, []);
            tc.verifyEmpty(findobj(ax, 'Type', 'line'));
            h = findobj(ax(1), 'Tag', 'timEmptyState');
            tc.verifyNumElements(h, 1);
            tc.verifySubstring(h.String, 'No calibration loaded');
            tc.verifyNotEmpty(ax(1).Title.String, 'the empty view has a title');
            tc.verifyEqual(ax(1).YLabel.String, '|C_k| [dB]');
            tc.verifyEqual(ax(2).XLabel.String, 'Frequency [Hz]');
            tc.verifyEqual(ax(1).XTick, [125 250 500 1000 2000 4000], 'default band 120 ... 4500 Hz');
            tc.verifyEqual(ax(1).YTick, [-1 -0.5 0 0.5 1]);
            tc.verifyEmpty(info.summary.data);
            tc.verifyEqual(info.status, '');
            tim.plots.calibration(ax, [], struct('emptyText', 'Run the calibration first', 'band', [200 2000]));
            h = findobj(ax(1), 'Tag', 'timEmptyState');
            tc.verifyEqual(h.String, 'Run the calibration first');
            tc.verifyEqual(ax(1).XTick, [250 500 1000 2000]);
        end

        function redrawReplacesEverything(tc)
            cal = tc.makeCal();
            ax = tc.newAxes();
            tim.plots.calibration(ax, cal);
            tim.plots.calibration(ax, cal);
            tc.verifyNumElements(findobj(ax(1), 'Type', 'line'), 6, 'no accumulation');
            tim.plots.calibration(ax, []);
            tc.verifyEmpty(findobj(ax, 'Type', 'line'));
            tc.verifyEmpty(ax(1).Legend, 'legend removed in the empty state');
            tim.plots.calibration(ax, cal);
            tc.verifyEmpty(findobj(ax, 'Tag', 'timEmptyState'), 'message removed with data');
        end

        function formerYyaxisAxesCleaned(tc)
            % the old GUI drew the calibration with yyaxis into the same axes
            ax = tc.newAxes();
            yyaxis(ax(1), 'right'); plot(ax(1), 1:3, 1:3);
            tim.plots.calibration(ax, tc.makeCal());
            tc.verifyNumElements(ax(1).YAxis, 1, 'no second y axis left over');
            tc.verifyNumElements(findobj(ax(1), 'Type', 'line'), 6);
        end

        function steppedMarkers(tc)
            cal = tc.makeCal();
            idx = round(linspace(1, numel(cal.f), 12));
            cal.f = cal.f(idx); cal.C = cal.C(idx, :); cal.valid = cal.valid(idx, :);
            ax = tc.newAxes();
            tim.plots.calibration(ax, cal, struct('stepped', true));
            tc.verifyEqual(findobj(ax(1), 'Tag', 'calMag2').Marker, 'o');
        end

        function worksOnUiaxes(tc)
            uf = uifigure('Visible', 'off');
            tc.addTeardown(@() delete(uf));
            g = uigridlayout(uf, [2 1]);
            ax = [uiaxes(g), uiaxes(g)];
            info = tim.plots.calibration(ax, tc.makeCal());
            tc.verifyNumElements(info.legend.String, 3);
            tc.verifyEqual(ax(1).XScale, 'log');
            tim.plots.calibration(ax, []);
            tc.verifyNumElements(findobj(ax(1), 'Tag', 'timEmptyState'), 1);
        end

        function savedFigure(tc)
            cal = tc.makeCal();
            fig = tim.app.plotCalibration(cal, struct('Visible', 'off'));
            tc.addTeardown(@() close(fig));
            tc.verifyEqual(fig.Visible, matlab.lang.OnOffSwitchState('off'));
            ax = findobj(fig, 'Type', 'axes');
            tc.verifyNumElements(ax, 2);
            tc.verifyNotEmpty(findobj(fig, 'Tag', 'calMag2'));
            note = findall(fig, 'Tag', 'calFootnote');
            tc.verifyNumElements(note, 1);
            tc.verifyTrue(any(contains(note.String, 'Test E')), 'footnote holds the empty-tube check');
            tc.verifyTrue(any(contains(note.String, 'remounting repeatability')));
            fig2 = tim.app.plotCalibration([], struct('Visible', 'off'));
            tc.addTeardown(@() close(fig2));
            tc.verifyNumElements(findobj(fig2, 'Tag', 'timEmptyState'), 1);
        end
    end
end
