classdef TestPlotsResults < matlab.unittest.TestCase
    %TESTPLOTSRESULTS Result views (tim.plots.reflection, transmissionLoss,
    %   transferImpedance, validity) and their helpers (thickSpecimen,
    %   bandValues). The results are built from the analytic tube model
    %   (tim.sim.tubeModel -> tim.acoustics.analyzeFourMic, no DAQ
    %   simulation): lab tube with the 75 mm specimen section (thin-element
    %   model not applicable), thin screen (d = 0), stepped sine with a step
    %   without a value (120 Hz) and an invalid step, and a result without a
    %   calibration (nothing valid). All figures are invisible.

    properties
        lab        % swept sine, porous specimen d = 75 mm, calibrated
        thin       % swept sine, thin screen d = 0, calibrated
        step       % stepped sine (16 steps), d = 75 mm
        noCal      % lab result without a calibration
        fig
    end

    methods (TestClassSetup)
        function buildResults(tc)
            gLab = struct('diameter', 0.029, 'micPositions', [-0.070 -0.041 0.116 0.145], ...
                'spacingUp', 0.029, 'spacingDown', 0.029, 'xFront', 0, 'xRear', 0.075);
            gThin = struct('diameter', 0.029, 'micPositions', [-0.150 -0.121 0.071 0.100], ...
                'spacingUp', 0.029, 'spacingDown', 0.029, 'xFront', 0, 'xRear', 0);
            porous = struct('type', 'porous', 'sigma', 1e4);
            fs = (120:2:4500).';
            tc.lab = TestPlotsResults.result('sweep', fs, gLab, porous, 0.436, true);
            tc.noCal = TestPlotsResults.result('sweep', fs, gLab, porous, 0.436, false);
            tc.thin = TestPlotsResults.result('sweep', fs, gThin, struct('type', 'thin', 'R', 400, 'm', 0.05), 0.6, true);
            % stepped: same grid as MeasurementSession (logspace: the first step
            % lands a few 1e-14 Hz below 120 Hz), step 1 without a value (as with
            % a calibration that does not cover it), step 5 measured but invalid
            fq = logspace(log10(120), log10(4500), 16).';
            tc.step = TestPlotsResults.result('stepped', fq, gLab, porous, 0.436, true, 1, 5);
        end
    end

    methods (TestMethodSetup)
        function newFigure(tc)
            tc.fig = figure('Visible', 'off', 'Position', [50 50 1150 640]);
            tc.addTeardown(@() delete(tc.fig));
        end
    end

    methods (Static)
        function res = result(kind, f, geom, sample, xTerm, calibrated, nanStep, badStep, snr, geomAnalysis)
            % analytic four-microphone result in the layout of tim.app.processMeasurement
            % (snr: SNR [dB] per position M1..M4, default 60 dB everywhere;
            % geomAnalysis: geometry given to the analysis, default geom)
            env = struct('temperature_C', 20, 'pressure_Pa', 101325, 'c_override', [], 'rho_override', []);
            m = tim.sim.tubeModel(f, geom, env, sample, struct('R', 0.05, 'x', xTerm));
            H = m.p ./ m.p(:, 1);
            n = numel(f); coh = ones(n, 4);
            if nargin > 6 && ~isempty(nanStep), H(nanStep, :) = NaN; end
            if nargin > 7 && ~isempty(badStep), coh(badStep, :) = 0.5; end
            if nargin < 9 || isempty(snr), snr = [60 60 60 60]; end
            o = struct('fRange', [120 4500], 'quality', struct('coherence', coh, 'snr_dB', repmat(snr, n, 1)));
            if calibrated
                o.calValid = isfinite(H(:, 1));
                cal = struct('applied', true, 'version', 'CAL-20261009-120000');
            else
                cal = struct('applied', false, 'version', 'none');
            end
            if nargin < 10 || isempty(geomAnalysis), geomAnalysis = geom; end
            res = struct('kind', kind, 'timestamp', '2026-10-09 12:00:00', 'calibration', cal, ...
                'analysis', tim.acoustics.analyzeFourMic(f, H, geomAnalysis, env, o));
        end
    end

    methods
        function ax = axesRows(tc, heights)
            % stacked axes like an exported figure (tiledlayout)
            tl = tiledlayout(tc.fig, sum(heights), 1, 'TileSpacing', 'compact');
            ax = gobjects(1, numel(heights)); r = 1;
            for i = 1:numel(heights)
                ax(i) = nexttile(tl, r, [heights(i) 1]); r = r + heights(i);
            end
        end

        function verifyHouseStyle(tc, ax)
            % outward ticks and half a tick interval beyond the outermost ticks (x log, y linear)
            tc.verifyEqual(ax.TickDir, 'out');
            tc.verifyEqual(ax.XScale, 'log');
            r = ax.XTick(2) / ax.XTick(1);
            tc.verifyEqual(ax.XLim, [ax.XTick(1) / sqrt(r), ax.XTick(end) * sqrt(r)], 'RelTol', 1e-9);
            if strcmp(ax.YDir, 'normal')
                st = ax.YTick(2) - ax.YTick(1);
                tc.verifyEqual(ax.YLim, [ax.YTick(1) - st / 2, ax.YTick(end) + st / 2], 'AbsTol', 1e-9 * st);
            end
        end

        function verifyNoChannelColours(tc, ax)
            P = tim.gui.palette();
            ln = findobj(ax, 'Type', 'line');
            for i = 1:numel(ln)
                c = ln(i).Color;
                tc.verifyFalse(any(all(abs(P.ch - c) < 1e-6, 2)), 'result views use quantity colours, not channel colours');
            end
        end
    end

    methods (Test)
        function bandValuesMeanOverValidBinsOnly(tc)
            f = (100:100:5000).'; y = f; ok = true(size(f));
            ok(f == 200) = false;                        % 250 band keeps 300 only
            ok(f >= 400 & f <= 700) = false;             % 500 band (354 ... 707 Hz) without a valid bin
            y(f == 900) = NaN;                           % non-finite values are never averaged
            [m, n, txt] = tim.plots.bandValues(f, y, ok, [125 250 500 1000], '%.1f');
            tc.verifyEqual(m(1:2), [100; 300]);
            tc.verifyTrue(isnan(m(3)));
            tc.verifyEqual(n(3), 0);
            tc.verifyEqual(txt{3}, char(8211));
            in = f >= 1000 / sqrt(2) & f < 1000 * sqrt(2) & f ~= 900;
            tc.verifyEqual(m(4), mean(f(in)), 'RelTol', 1e-12);
            tc.verifyEqual(txt{1}, '100.0');
            % half-open edges: a bin exactly on an edge counts in the upper band only
            fe = 125 * sqrt(2);
            [m2, n2] = tim.plots.bandValues(fe, 1, true, [125 250]);
            tc.verifyEqual(n2, [0; 1]); tc.verifyEqual(m2(2), 1);
        end

        function thickSpecimenLabAndThin(tc)
            [thick, txt, kd] = tim.plots.thickSpecimen(tc.lab.analysis);
            a = tc.lab.analysis;
            tc.verifyTrue(thick);
            tc.verifyEqual(kd, max(real(a.k(a.valid.measured))) * 0.075, 'RelTol', 1e-12);   % Re(k) d over the measured lines (Kirchhoff: Re(k) > omega/c)
            tc.verifySubstring(txt, 'Thin-element model not applicable: d = 75 mm');
            tc.verifySubstring(txt, sprintf('d up to %.1f', kd));
            [thick, txt, kd] = tim.plots.thickSpecimen(tc.thin.analysis);
            tc.verifyFalse(thick); tc.verifyEmpty(txt); tc.verifyEqual(kd, 0);
            b = tc.lab.analysis; b.boundary = struct('available', false);
            tc.verifyFalse(tim.plots.thickSpecimen(b));
        end

        function reflectionLabSweep(tc)
            ax = tc.axesRows([2 1]);
            info = tim.plots.reflection(ax, tc.lab);
            P = tim.gui.palette(); a = tc.lab.analysis; v = a.valid;
            tc.verifyHouseStyle(ax(1)); tc.verifyHouseStyle(ax(2));
            tc.verifyEqual(ax(1).YLim, [-0.1 1.1], 'AbsTol', 1e-12);
            tc.verifyEqual(ax(2).YTick, -180:90:180);
            tc.verifyEqual(ax(1).XLim, [125 / sqrt(2), 4000 * sqrt(2)], 'RelTol', 1e-9);
            tc.verifyEqual(ax(1).Title.String, tim.plots.dataTitle(tc.lab));
            tc.verifyEmpty(ax(2).Title.String);
            tc.verifyEqual(ax(2).XLabel.String, 'Frequency [Hz]');
            lg = ax(1).Legend;
            tc.verifyEqual(numel(lg.String), 5);
            tc.verifyEqual(lg.String{1}, '|R|');
            tc.verifySubstring(lg.String{5}, 'limit (0.1)');
            tc.verifyEqual(info.lines(1).Color, P.q.first);
            tc.verifyEqual(info.lines(2).Color, P.q.second);
            tc.verifyEqual(info.lines(3).Color, P.q.third);
            tc.verifyEqual(info.lines(5).Value, a.options.anechoicRmax);
            % the coloured |R| curve holds exactly the valid bins
            yR = info.lines(1).YData(:);
            tc.verifyEqual(isfinite(yR), v.validR & isfinite(a.R));
            tc.verifyNoChannelColours(ax(1)); tc.verifyNoChannelColours(ax(2));
            % summary: octave means over the valid bins
            s = info.summary;
            tc.verifyEqual(s.columns, {'Band [Hz]', '|R|', '|τ|', 'α_d'});
            tc.verifyEqual(s.data(:, 1).', {'125*', '250', '500', '1000', '2000', '4000*'}, ...
                '125 and 4000 Hz bands only partly inside 120 ... 4500 Hz');
            tc.verifySubstring(s.note, '* = only partly inside the analysis band (120');
            tc.verifyTrue(startsWith(lg.String{3}, '\alpha_d = 1'), 'dissipation coefficient α_d (glossary)');
            in = v.validR & a.f >= 1000 / sqrt(2) & a.f < 1000 * sqrt(2);
            tc.verifyEqual(s.data{4, 2}, sprintf('%.2f', mean(abs(a.R(in)))));
            tc.verifyEmpty(info.note);
            % drawing again replaces everything (no duplicates)
            nc = numel(ax(1).Children);
            tim.plots.reflection(ax, tc.lab);
            tc.verifyEqual(numel(ax(1).Children), nc);
        end

        function transmissionLossThickShowsOnlyTau(tc)
            ax = tc.axesRows(1);
            info = tim.plots.transmissionLoss(ax, tc.lab);
            a = tc.lab.analysis;
            tc.verifyHouseStyle(ax);
            tc.verifyEqual(numel(info.lines), 1);
            tc.verifyEqual(numel(ax.Legend.String), 1);
            tc.verifyLessThanOrEqual(ax.YLim(1), 0);               % YInclude 0
            tc.verifySubstring(info.note, 'Thin-element model not applicable: d = 75 mm');
            tc.verifyEqual(info.summary.columns, {'Band [Hz]', 'TL [dB]'});
            in = a.valid.validTau & a.f >= 1000 / sqrt(2) & a.f < 1000 * sqrt(2);
            tl = -10 * log10(mean(abs(a.tau(in)).^2));             % energy mean of the band
            tc.verifyEqual(info.summary.data{4, 2}, sprintf('%.1f', tl));
            tc.verifyEqual(ax.YLabel.String, 'Transmission loss [dB]');
        end

        function thinSpecimenShowsZtAndBothTl(tc)
            ax = tc.axesRows(1);
            info = tim.plots.transmissionLoss(ax, tc.thin);
            P = tim.gui.palette(); a = tc.thin.analysis;
            tc.verifyEqual(numel(info.lines), 2);
            tc.verifyEqual(info.lines(2).Color, P.q.second);
            tc.verifyEqual(info.lines(2).LineStyle, '--');
            tc.verifyEqual(info.summary.columns, {'Band [Hz]', 'TL [dB]', 'TL from Z_t [dB]'});
            tc.verifyEmpty(info.note);
            % thin screen, anechoic termination: both TL agree (Test F)
            ok = a.valid.validTau & a.valid.validThinZt;
            tc.verifyGreaterThan(nnz(ok), 0.5 * numel(ok));
            tc.verifyEqual(a.thin.TL_dB(ok), a.power.TL_tau_dB(ok), 'AbsTol', 0.3);
            delete(ax);
            ax = tc.axesRows([1 1]);
            info = tim.plots.transferImpedance(ax, tc.thin);
            tc.verifyHouseStyle(ax(1)); tc.verifyHouseStyle(ax(2));
            tc.verifyEqual(numel(info.lines), 2);
            yRe = info.lines(1).YData(:); okZ = a.valid.validThinZt;
            tc.verifyEqual(yRe(okZ), real(a.thin.Zt_norm(okZ)));
            tc.verifyEqual(median(yRe(okZ)), 400 / a.air.Z0, 'RelTol', 1e-6);   % R = 400 Pa s/m
            tc.verifyEmpty(findobj(ax(1), 'Tag', 'timEmptyState'));
            tc.verifyEqual(info.summary.columns, {'Band [Hz]', 'Re{Z_t}/ρc', 'Im{Z_t}/ρc'});
            tc.verifySubstring(info.summary.note, sprintf('%.1f Pa', a.air.Z0));
            tc.verifySubstring(ax(1).YLabel.String, 'Re\{Z_t\}');
        end

        function transferImpedanceThickIsExplained(tc)
            ax = tc.axesRows([1 1]);
            info = tim.plots.transferImpedance(ax, tc.lab);
            tc.verifyEmpty(info.lines);
            es = findobj(ax(1), 'Tag', 'timEmptyState');
            tc.verifyNumElements(es, 1);
            tc.verifySubstring(strjoin(cellstr(es.String), ' '), 'Thin-element model not applicable: d = 75 mm');
            tc.verifySubstring(info.note, 'See Transmission loss or Reflection and transmission');
            tc.verifySubstring(ax(1).YLabel.String, '(\rho{}c)');
            tc.verifySubstring(ax(2).YLabel.String, 'Im\{Z_t\}');
            tc.verifyHouseStyle(ax(1)); tc.verifyHouseStyle(ax(2));
            tc.verifyEqual(ax(1).Title.String, tim.plots.dataTitle(tc.lab));
            tc.verifyTrue(all(strcmp(info.summary.data(:, 2), char(8211))));
        end

        function noCalibrationNothingValid(tc)
            r = tc.noCal; P = tim.gui.palette();
            views = {'reflection', [2 1]; 'transmissionLoss', 1; 'transferImpedance', [1 1]; 'validity', 1};
            for i = 1:size(views, 1)
                clf(tc.fig);
                ax = tc.axesRows(views{i, 2});
                info = tim.plots.(views{i, 1})(ax, r);
                tc.verifySubstring(info.note, 'No calibration applied', views{i, 1});
                if any(strcmp(views{i, 1}, {'reflection', 'transmissionLoss'}))
                    for h = info.lines(isgraphics(info.lines, 'line'))
                        tc.verifyTrue(all(isnan(h.YData)), [views{i, 1} ': no coloured value without a calibration']);
                    end
                    grey = findobj(ax(1), 'Type', 'line', 'Color', P.invalid);
                    tc.verifyNotEmpty(grey);
                    tc.verifyTrue(any(isfinite(grey(1).YData)), 'the grey curves are drawn');
                end
            end
            tc.verifyTrue(contains(r.calibration.version, 'none'));
        end

        function steppedShowsEveryStep(tc)
            r = tc.step; f = r.analysis.f; P = tim.gui.palette();
            tc.verifyLessThan(f(1), 120);                 % the 120 Hz step of a logspace grid
            ax = tc.axesRows([2 1]);
            info = tim.plots.reflection(ax, r);
            % grey markers under the coloured ones: every step with a value, invalid = hollow
            g = findobj(ax(1), 'Type', 'line', 'Color', P.invalid, 'Marker', 'o');
            tc.verifyNotEmpty(g);
            tc.verifyEqual(g(1).XData(:), f);
            tc.verifyEqual(g(1).MarkerFaceColor, [1 1 1]);
            tc.verifyTrue(isfinite(g(1).YData(5)), 'invalid step 5 keeps its (hollow) marker');
            tc.verifyTrue(isnan(info.lines(1).YData(5)), 'invalid step 5 is not drawn as valid');
            % the step without a value is marked on the x axis and named in the note
            mk = findobj(ax(1), 'Tag', 'timMissingStep');
            tc.verifyNumElements(mk, 1);
            tc.verifyEqual(mk.XData, f(1));
            tc.verifyGreaterThan(mk.YData, ax(1).YLim(1)); tc.verifyLessThan(mk.YData, ax(1).YLim(2));
            tc.verifyLessThan(ax(1).XLim(1), f(1));
            tc.verifySubstring(info.note, 'No value at 120 Hz');
            % validity: one square per step on every row, also for step 1
            clf(tc.fig); ax = tc.axesRows(1);
            info = tim.plots.validity(ax, r);
            sq = findobj(ax, 'Type', 'line', 'Marker', 's', 'MarkerFaceColor', [0.90 0.90 0.90]);
            tc.verifyEqual(numel(sq), numel(ax.YTick));
            for i = 1:numel(sq)
                tc.verifyEqual(sq(i).XData(:), f);
                tc.verifyLessThan(max(sq(i).MarkerEdgeColor), 0.7, 'a "false" step stays visible on white');
            end
            tc.verifyEqual(numel(info.lines), numel(ax.YTick));
            iMeasured = 1;
            tc.verifyTrue(isnan(info.lines(iMeasured).XData(1)), '120 Hz step outside the band (not measured)');
            tc.verifySubstring(info.note, 'Step 120 Hz not evaluated');
        end

        function validityRowsLineUpWithLabels(tc)
            ax = tc.axesRows(1);
            info = tim.plots.validity(ax, tc.noCal);
            a = tc.noCal.analysis;
            nFlags = numel(fieldnames(a.valid.flags));
            tc.verifyEqual(numel(ax.YTick), 9 + nFlags);
            tc.verifyEqual(numel(ax.YTickLabel), 9 + nFlags);
            tc.verifyEqual(ax.YDir, 'reverse');
            tickLab = cellstr(ax.YTickLabel);
            tc.verifyEqual(tickLab{1}, 'Measured (in band)');
            tc.verifyEqual(tickLab{8}, 'Valid thin Z_t');
            tc.verifyTrue(any(strcmp(tickLab, 'Rejected: no valid calibration')));
            tc.verifyTrue(any(strcmp(tickLab, 'Rejected: termination not anechoic')));
            P = tim.gui.palette();
            for i = 1:numel(info.lines)
                h = info.lines(i);
                yc = h.YData(:, all(isfinite(h.YData), 1));
                if isempty(yc), continue; end
                tc.verifyEqual(mean(yc(:)), ax.YTick(i), 'AbsTol', 1e-9, 'band centred on its label');
                tc.verifyFalse(any(all(abs(P.ch - h.FaceColor) < 1e-6, 2)), 'neutral colours');
            end
            % calInvalid rejects every bin, velocityMismatch / Valid thin Z_t rows exist
            iCal = find(strcmp(tickLab, 'Rejected: no valid calibration'));
            tc.verifyEqual(size(info.lines(iCal).XData, 2), 1, 'one contiguous run');
            tc.verifyEqual(info.lines(iCal).FaceColor, P.fail);
            s = info.summary;
            tc.verifyEqual(s.columns, {'Criterion', 'Passing', '%', 'Affects'});
            tc.verifyEqual(size(s.data, 1), 9 + nFlags);
            tc.verifyEqual(s.data{strcmp(s.data(:, 1), 'Rejected: no valid calibration'), 2}, 0);
            tc.verifyEqual(s.data{strcmp(s.data(:, 1), 'Rejected: velocity mismatch'), 4}, 'Z_t, TL from Z_t');
            tc.verifyEqual(s.data{strcmp(s.data(:, 1), 'Rejected: termination not anechoic'), 4}, '|τ|, α_d, TL');
            tc.verifyTrue(startsWith(s.note, a.valid.summary), 'table note = summary of the masks + R note');
            tc.verifySubstring(s.note, '(R: M1/M2) = R needs only the upstream pair');
            tc.verifyEqual(ax.XLim, [125 / sqrt(2), 4000 * sqrt(2)], 'RelTol', 1e-9);
        end

        function validityROnlyNeedsUpstreamPair(tc)
            % low SNR at M3/M4 (high-TL specimen): nothing valid for τ / TL / Z_t,
            % but R (upstream pair M1/M2) is valid - the view must not say otherwise
            gLab = struct('diameter', 0.029, 'micPositions', [-0.070 -0.041 0.116 0.145], ...
                'spacingUp', 0.029, 'spacingDown', 0.029, 'xFront', 0, 'xRear', 0.075);
            r = TestPlotsResults.result('sweep', (120:2:4500).', gLab, struct('type', 'porous', 'sigma', 1e4), ...
                0.436, true, [], [], [60 60 5 5]);
            v = r.analysis.valid;
            tc.assertFalse(any(v.valid)); tc.assertTrue(any(v.validR));
            ax = tc.axesRows(1);
            info = tim.plots.validity(ax, r);
            tc.verifySubstring(info.note, sprintf('R valid on %d lines (upstream pair M1/M2)', nnz(v.validR)));
            tc.verifyFalse(contains(info.note, 'No valid frequency line'), info.note);
            d = info.summary.data;
            row = @(name) find(strcmp(d(:, 1), name), 1);
            tc.verifyEqual(d{row('Valid R'), 2}, nnz(v.validR));
            for name = {'Measured (in band)', 'Geometry OK', 'Quality OK (coherence, SNR, cal.)', 'Rejected: low SNR', ...
                    'Rejected: low coherence', 'Rejected: below the spacing limit'}
                tc.verifyEqual(d{row(name{1}), 4}, '|τ|, α_d, TL, Z_t (R: M1/M2)', name{1});
            end
            tc.verifyEqual(d{row('Valid'), 4}, '|τ|, α_d, TL, Z_t');
            tc.verifyEqual(d{row('Rejected: no valid calibration'), 4}, '|τ|, α_d, TL, Z_t (R: M1/M2)', 'R needs only the calibration of M1/M2');
            tc.verifyFalse(any(contains(d(:, 4), 'all (')), 'no "all (...)": R has its own upstream masks');
            % reflection view: |R| drawn in colour on the valid lines
            clf(tc.fig); ax = tc.axesRows([2 1]);
            info = tim.plots.reflection(ax, r);
            tc.verifyEqual(nnz(isfinite(info.lines(1).YData)), nnz(v.validR));
        end

        function facePositionsUnknown(tc)
            % L1, d, L2 not entered: TL explains it in the axes (default limits),
            % Validity names the reason in its header note
            g = struct('diameter', 0.029, 'micPositions', [-0.070 -0.041 0.116 0.145], ...
                'spacingUp', 0.029, 'spacingDown', 0.029, 'xFront', 0, 'xRear', 0.075);
            gUnknown = g; gUnknown.xFront = NaN; gUnknown.xRear = NaN;
            r = TestPlotsResults.result('sweep', (120:2:4500).', g, struct('type', 'porous', 'sigma', 1e4), ...
                0.436, true, [], [], [], gUnknown);
            tc.assertFalse(r.analysis.boundary.available);
            ax = tc.axesRows(1);
            info = tim.plots.transmissionLoss(ax, r);
            es = findobj(ax, 'Tag', 'timEmptyState');
            tc.verifyNumElements(es, 1);
            tc.verifySubstring(es.String, 'Specimen face positions unknown');
            tc.verifyEmpty(info.lines);
            tc.verifyEqual(info.note, 'Specimen face positions unknown (L1, d, L2): the transmission loss is not available.');
            tc.verifyGreaterThanOrEqual(ax.YLim(2), 30, 'default limits, not a +-1.25 dB axis');
            tc.verifyHouseStyle(ax);
            tc.verifyEqual(ax.Title.String, tim.plots.dataTitle(r));
            tc.verifyTrue(all(strcmp(info.summary.data(:, 2), char(8211))));
            clf(tc.fig); ax = tc.axesRows(1);
            info = tim.plots.validity(ax, r);
            tc.verifySubstring(info.note, 'Specimen face positions unknown (L1, d, L2): R, τ, TL and Z_t');
            % without a calibration the missing calibration comes first
            r.calibration = struct('applied', false, 'version', 'none');
            clf(tc.fig); ax = tc.axesRows(1);
            info = tim.plots.transmissionLoss(ax, r);
            tc.verifyTrue(startsWith(info.note, 'No calibration applied'), info.note);
            tc.verifySubstring(findobj(ax, 'Tag', 'timEmptyState').String, 'face positions unknown');
        end

        function octaveBandsCoverTheAnalysisBand(tc)
            % every octave band that overlaps the analysis band is listed; partial ones are marked
            B = tim.plots.octaveBands([50 6300]);
            tc.verifyEqual(B.labels.', {'63*', '125', '250', '500', '1000', '2000', '4000', '8000*'});
            tc.verifyEqual(B.centres.', 1000 * 2.^(-4:3), 'RelTol', 1e-12);
            tc.verifyEqual(B.partial.', [true false(1, 6) true]);
            tc.verifySubstring(B.note, '50');
            B = tim.plots.octaveBands([1000 / sqrt(2), 2000 * sqrt(2)]);      % exactly two full bands
            tc.verifyEqual(B.labels.', {'1000', '2000'});
            tc.verifyEmpty(B.note);
            % the views use them: a wide band summarises every line
            ax = tc.axesRows([2 1]);
            info = tim.plots.reflection(ax, tc.lab, struct('band', [50 6300]));
            tc.verifyEqual(info.summary.data(:, 1).', {'63*', '125', '250', '500', '1000', '2000', '4000', '8000*'});
            tc.verifySubstring(info.summary.note, '* = only partly inside');
            clf(tc.fig); ax = tc.axesRows(1);
            info = tim.plots.transmissionLoss(ax, tc.lab);
            tc.verifyEqual(info.summary.data([1 end], 1).', {'125*', '4000*'});
            clf(tc.fig); ax = tc.axesRows([1 1]);
            info = tim.plots.transferImpedance(ax, tc.thin);
            tc.verifyEqual(info.summary.data([1 end], 1).', {'125*', '4000*'});
            tc.verifySubstring(info.summary.note, '* = only partly inside');
        end

        function maskedIsolatedValidLineVisible(tc)
            % a valid line between two invalid ones: a coloured dot (a one-point
            % segment of the coloured line is not drawn)
            ax = tc.axesRows(1);
            f = (100:100:1000).'; y = f / 1000;
            ok = logical([1 1 0 1 0 0 1 1 0 1]).';         % lines 4 and 10 isolated
            P = tim.gui.palette();
            h = tim.plots.masked(ax, f, y, ok, P.q.first);
            iso = findobj(ax, 'Tag', 'timIsolatedValid');
            tc.verifyNumElements(iso, 1);
            tc.verifyEqual(iso.XData(:), f([4 10]));
            tc.verifyEqual(iso.YData(:), y([4 10]));
            tc.verifyEqual(iso.Color, P.q.first);
            tc.verifyEqual(isfinite(h.YData(:)), ok);
            cla(ax);
            tim.plots.masked(ax, f, y, true(size(f)), P.q.first);
            tc.verifyEmpty(findobj(ax, 'Tag', 'timIsolatedValid'), 'no dot without an isolated line');
            cla(ax);
            tim.plots.masked(ax, f, y, ok, P.q.first, struct('stepped', true));
            tc.verifyEmpty(findobj(ax, 'Tag', 'timIsolatedValid'), 'stepped sine: markers anyway');
        end

        function emptyStates(tc)
            views = {'reflection', [2 1]; 'transmissionLoss', 1; 'transferImpedance', [1 1]; 'validity', 1};
            for i = 1:size(views, 1)
                clf(tc.fig);
                ax = tc.axesRows(views{i, 2});
                info = tim.plots.(views{i, 1})(ax, [], struct('emptyText', 'No measurement yet - press START'));
                es = findobj(ax(1), 'Tag', 'timEmptyState');
                tc.verifyNumElements(es, 1, views{i, 1});
                tc.verifyEqual(es.String, 'No measurement yet - press START');
                for k = 1:numel(ax)
                    tc.verifyEqual(ax(k).XLim, [125 / sqrt(2), 4000 * sqrt(2)], 'RelTol', 1e-9);
                    tc.verifyEqual(ax(k).TickDir, 'out');
                end
                tc.verifyEqual(ax(end).XLabel.String, 'Frequency [Hz]');
                if strcmp(views{i, 1}, 'validity')
                    tc.verifyEqual(numel(ax(1).YTickLabel), numel(ax(1).YTick));   % rows labelled before data
                else
                    tc.verifyNotEmpty(ax(1).YLabel.String);
                end
                tc.verifyNotEmpty(info.summary.data);
                tc.verifyEmpty(info.note);
            end
        end

        function bandOptionAndUiAxes(tc)
            % opts.band narrows the octave table; the views work in uiaxes (GUI)
            uf = uifigure('Visible', 'off', 'Position', [50 50 1100 640]);
            tc.addTeardown(@() delete(uf));
            ax = [uiaxes(uf, 'Position', [10 230 1080 400]), uiaxes(uf, 'Position', [10 10 1080 210])];
            info = tim.plots.reflection(ax, tc.lab, struct('band', [500 2000], 'simulation', true));
            tc.verifyEqual(info.summary.data(:, 1).', {'500*', '1000', '2000*'});
            tc.verifySubstring(ax(1).Title.String, 'SIMULATION');
            tc.verifyHouseStyle(ax(1));
            info = tim.plots.validity(ax(1), tc.step);
            tc.verifyEqual(numel(info.lines), numel(ax(1).YTick));
            info = tim.plots.transferImpedance(ax, tc.thin);
            tc.verifyEqual(numel(info.lines), 2);
            info = tim.plots.transmissionLoss(ax(1), tc.step);
            tc.verifyNumElements(findobj(ax(1), 'Tag', 'timMissingStep'), 1);
            tc.verifySubstring(info.note, 'Thin-element model not applicable');
        end
    end
end
