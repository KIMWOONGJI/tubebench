classdef TestPlotsMeasurement < matlab.unittest.TestCase
    %TESTPLOTSMEASUREMENT Views of the Measurement tab: timeSignals, spectrum, transferFunctions.
    %
    %   Data: one short simulated data set (mock instruments, ~2 s): swept
    %   sine, stepped sine (6 steps), background noise; processed without a
    %   calibration (the views show H with 'NO calibration'). All figures are
    %   invisible and closed by the test.

    properties
        cfg
        mSweep
        mStep
        mBg
        rSweep
        rStep
    end

    methods (TestClassSetup)
        function simulate(tc)
            c = tim.app.defaultConfig();
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
            tc.mBg = s.measureBackground(1);
            tc.rSweep = tim.app.processMeasurement(tc.mSweep, c, []);
            tc.rStep = tim.app.processMeasurement(tc.mStep, c, []);
            tc.cfg = c;
            clear cleanup
        end
    end

    methods
        function ax = axesFor(tc, n)
            % n stacked axes in an invisible figure (closed after the test)
            fig = figure('Visible', 'off', 'Position', [50 50 1180 640]);
            tc.addTeardown(@() close(fig));
            tl = tiledlayout(fig, n, 1, 'TileSpacing', 'compact');
            ax = gobjects(1, n);
            for i = 1:n, ax(i) = nexttile(tl); end
        end
    end

    methods (Test)
        % ------------------------------------------------------------ time signals
        function timeSignalsInPascal(tc)
            ax = tc.axesFor(4);
            info = tim.plots.timeSignals(ax, tc.mSweep);
            P = tim.gui.palette();
            tc.verifyNumElements(info.lines, 4);
            tc.verifyEqual(info.unit, 'Pa');
            for c = 1:4
                tc.verifyEqual(info.lines(c).Tag, sprintf('timWave%d', c));
                tc.verifyEqual(findobj(ax(c), 'Tag', sprintf('timWave%d', c)), info.lines(c));
                tc.verifyEqual(info.lines(c).Color, P.ch(c, :));
                tc.verifySubstring(ax(c).YLabel.String, sprintf('ch%d (M%d) [Pa]', c, c));
                tc.verifyEqual(ax(c).TickDir, 'out');
                % half a tick interval beyond the outermost ticks (time and pressure)
                tc.verifyEqual(ax(c).XLim, [ax(c).XTick(1), ax(c).XTick(end)] + [-1 1] * diff(ax(c).XTick(1:2)) / 2, 'AbsTol', 1e-12);
                tc.verifyEqual(ax(c).YLim, [ax(c).YTick(1), ax(c).YTick(end)] + [-1 1] * diff(ax(c).YTick(1:2)) / 2, 'AbsTol', 1e-12);
            end
            tc.verifyEqual(ax(1).Title.String, tim.plots.dataTitle(tc.mSweep, struct('simulation', false)));
            tc.verifyEmpty(strtrim(ax(2).Title.String), 'multi-axes view: title on the top axes only');
            tc.verifyEmpty(ax(1).XTickLabel, 'shared time axis: labels on the bottom axes only');
            tc.verifyEqual(ax(4).XLabel.String, 'Time [s]');
            % summary: Pa = volts / sensitivity, level re 20 uPa
            S = info.summary;
            tc.verifyEqual(S.columns, {'Channel', 'Port', 'Peak [Pa]', 'Level [dB SPL]', 'Sensitivity [mV/Pa]', 'Source'});
            tc.verifySize(S.data, [4 6]);
            sens = [tc.mSweep.mics.sensitivity_VperPa];
            tc.verifyEqual(info.scale, 1 ./ sens, 'RelTol', 1e-12);
            tc.verifyEqual(str2double(S.data{2, 5}), 1e3 * sens(2), 'AbsTol', 0.006);
            tc.verifyEqual(S.data{1, 6}, 'TEDS');
            [b, a] = butter(2, 20 / (tc.mSweep.fs / 2), 'high');
            x = filtfilt(b, a, tc.mSweep.records{1} - mean(tc.mSweep.records{1}, 1));
            p = x(:, 3) / sens(3);
            tc.verifyEqual(str2double(S.data{3, 3}), max(abs(p)), 'RelTol', 1e-2);
            tc.verifyEqual(str2double(S.data{3, 4}), 20 * log10(sqrt(mean(p.^2)) / 2e-5), 'AbsTol', 0.06);
        end

        function timeSignalsColumnIsDaqChannel(tc)
            % column c of a record = DAQ channel c (as in processMeasurement), also
            % when the microphone list is not sorted by channel
            m = tc.mSweep;
            m.mics = m.mics([2 1 4 3]);
            m.mics(1).position = 3; m.mics(2).position = 4;    % ch2 in M3, ch1 in M4
            ax = tc.axesFor(4);
            info = tim.plots.timeSignals(ax, m);
            sens = [tc.mSweep.mics.sensitivity_VperPa];
            tc.verifyEqual(info.scale, 1 ./ sens, 'RelTol', 1e-12);
            tc.verifySubstring(ax(1).YLabel.String, 'ch1 (M4)');
            tc.verifySubstring(ax(2).YLabel.String, 'ch2 (M3)');
            tc.verifyEqual(info.summary.data(1, 1:2), {'ch1', 'M4'});
        end

        function timeSignalsWithoutSensitivityInMillivolts(tc)
            m = tc.mSweep;
            for c = 1:4, m.mics(c).sensitivity_VperPa = NaN; end
            ax = tc.axesFor(4);
            info = tim.plots.timeSignals(ax, m);
            tc.verifyEqual(info.unit, 'mV');
            tc.verifyEqual(info.scale, 1e3 * ones(1, 4));
            tc.verifySubstring(ax(1).YLabel.String, '[mV]');
            tc.verifyEqual(info.summary.columns{3}, 'Peak [mV]');
            tc.verifyEqual(info.summary.data(:, 4), repmat({'–'}, 4, 1), 'no SPL without a sensitivity');
            tc.verifySubstring(info.note, 'mV');
        end

        function timeSignalsEmptyAndLive(tc)
            ax = tc.axesFor(4);
            info = tim.plots.timeSignals(ax, []);
            tc.verifyNotEmpty(findobj(ax(1), 'Tag', 'timEmptyState'));
            tc.verifyEqual(findobj(ax(1), 'Tag', 'timEmptyState').String, 'No measurement yet');
            tc.verifySubstring(ax(2).YLabel.String, '[Pa]');
            tc.verifyTrue(all(isnan(info.lines(1).YData)));
            tc.verifyTrue(all(isnan(info.scale)), 'no microphones: no conversion factors');
            % empty view prepared from the microphones (live acquisition), own empty text
            info = tim.plots.timeSignals(ax, [], struct('mics', tc.mSweep.mics, 'emptyText', 'Waiting for data'));
            tc.verifyEqual(findobj(ax(1), 'Tag', 'timEmptyState').String, 'Waiting for data');
            tc.verifySubstring(ax(3).YLabel.String, 'ch3 (M3) [Pa]');
            tc.verifyEqual(info.scale, 1 ./ [tc.mSweep.mics.sensitivity_VperPa], 'RelTol', 1e-12);
            % live update as done by the GUI: set the line data, then fitAxes
            n = 4096; v = tc.mSweep.records{1}(end - n + 1:end, :); t = ((1:n) - n) / tc.mSweep.fs;
            for c = 1:4
                set(info.lines(c), 'XData', t, 'YData', v(:, c) * info.scale(c));
                tim.plots.fitAxes(info.axes(c));
            end
            tc.verifyLessThan(ax(1).XLim(1), t(1));
            tc.verifyGreaterThan(ax(1).XLim(2), 0);
            tc.verifyLessThanOrEqual(ax(2).YLim(1), min(v(:, 2) * info.scale(2)));
            % a new measurement replaces the lines (no accumulation)
            tim.plots.timeSignals(ax, tc.mStep);
            tc.verifyNumElements(findobj(ax(1), 'Type', 'line'), 1);
            tc.verifyEmpty(findobj(ax(1), 'Tag', 'timEmptyState'));
        end

        % ------------------------------------------------------------- spectrum
        function spectrumSweepFromResult(tc)
            ax = tc.axesFor(1);
            info = tim.plots.spectrum(ax, tc.mSweep, tc.rSweep, struct('band', [120 4500]));
            P = tim.gui.palette();
            tc.verifyNumElements(info.lines, 4);
            ps = tc.rSweep.pressureSpectrum;
            k = ps.f >= 20;
            for c = 1:4
                tc.verifyEqual(info.lines(c).Color, P.ch(c, :));
                tc.verifyEqual(info.lines(c).YData(:), 10 * log10(ps.PSD_Pa2perHz(k, c) / (2e-5)^2), 'AbsTol', 1e-9);
            end
            % analysis band: two dashed constant lines, not part of the limits
            cl = findobj(ax, 'Type', 'ConstantLine');
            tc.verifyEqual(sort([cl.Value]), [120 4500]);
            tc.verifyEqual(unique({cl.LineStyle}), {'--'});
            tc.verifyEqual(ax.XScale, 'log');
            tc.verifyLessThanOrEqual(ax.XLim(1), 20); tc.verifyGreaterThanOrEqual(ax.XLim(2), tc.mSweep.fs / 2);
            tc.verifyEqual(ax.XLim, [ax.XTick(1) / sqrt(2), ax.XTick(end) * sqrt(2)], 'RelTol', 1e-9);
            tc.verifyEqual(ax.YLabel.String, 'PSD [dB re (20 \muPa)^2/Hz]');
            tc.verifyEqual(ax.Title.String, tim.plots.dataTitle(tc.mSweep, struct('simulation', false)), ...
                'kind and time; no calibration tag (the PSD uses only the sensitivities)');
            tc.verifyEqual(ax.Legend.String, {'ch1 (M1)', 'ch2 (M2)', 'ch3 (M3)', 'ch4 (M4)', 'Analysis band 120 – 4500 Hz'});
            % same Welch estimate from the raw record when no result is given
            ax2 = tc.axesFor(1);
            info2 = tim.plots.spectrum(ax2, tc.mSweep, []);
            tc.verifyEqual(info2.lines(2).YData, info.lines(2).YData, 'AbsTol', 1e-9);
            % band level = PSD integrated over the band
            df = ps.f(2) - ps.f(1); in = ps.f >= 120 & ps.f <= 4500;
            tc.verifyEqual(str2double(info.summary.data{4, 3}), ...
                10 * log10(sum(ps.PSD_Pa2perHz(in, 4)) * df / 4e-10), 'AbsTol', 0.06);
        end

        function spectrumBackgroundLevelMatchesTimeSignal(tc)
            % formula check: the integrated one-sided PSD equals the mean square
            % (Parseval) - overall level vs rms level of the same record
            ax = tc.axesFor(1);
            info = tim.plots.spectrum(ax, tc.mBg, []);
            tc.verifySubstring(ax.Title.String, 'Background noise');
            x = tc.mBg.records{1}; x = x - mean(x, 1);
            p = x ./ [tc.mBg.mics.sensitivity_VperPa];
            nfft = min(8192, 2^nextpow2(size(p, 1)));
            [G, f] = pwelch(p, hann(nfft, 'periodic'), nfft / 2, nfft, tc.mBg.fs);
            tc.verifyEqual(sum(G) * (f(2) - f(1)), mean(p.^2), 'RelTol', 0.05);
            [b, a] = butter(4, 20 / (tc.mBg.fs / 2), 'high');
            ph = filtfilt(b, a, p);
            for c = 1:4
                tc.verifyEqual(str2double(info.summary.data{c, 4}), 20 * log10(sqrt(mean(ph(:, c).^2)) / 2e-5), 'AbsTol', 0.3);
            end
            % a flat noise floor is shown with at least 40 dB on the y axis
            tc.verifyGreaterThanOrEqual(diff(ax.YLim), 40);
        end

        function spectrumStepped(tc)
            ax = tc.axesFor(1);
            info = tim.plots.spectrum(ax, tc.mStep, tc.rStep);
            tl = tc.rStep.toneLevels;
            tc.verifyNumElements(info.lines, 4);
            for c = 1:4
                tc.verifyEqual(info.lines(c).Marker, 'o');
                tc.verifyEqual(info.lines(c).XData(:), tl.f, 'RelTol', 1e-12);
                tc.verifyEqual(info.lines(c).YData(:), tl.spl_dB(:, c), 'AbsTol', 1e-9);
            end
            dotted = findobj(ax, 'Type', 'line', 'LineStyle', ':');
            tc.verifyNumElements(dotted, 5, 'noise of 4 channels + legend sample');
            tc.verifyEqual(ax.YLabel.String, 'Tone level [dB SPL]');
            tc.verifyEqual(ax.Legend.String{end}, 'Noise in fit bandwidth');
            S = info.summary;
            tc.verifyEqual(S.columns(3:5), {'Min tone level [dB SPL]', 'Max tone level [dB SPL]', 'Median SNR [dB]'});
            tc.verifyEqual(str2double(S.data{1, 4}), max(tl.spl_dB(:, 1)), 'AbsTol', 0.06);
            tc.verifyEqual(str2double(S.data{2, 5}), median(tl.spl_dB(:, 2) - tl.noise_dB(:, 2)), 'AbsTol', 0.06);
            % before processing: the line spectrum in grey with the explanation
            info = tim.plots.spectrum(ax, tc.mStep, []);
            P = tim.gui.palette();
            tc.verifyEqual(info.lines(1).Color, P.invalid);
            tc.verifySubstring(strjoin(cellstr(findobj(ax, 'Tag', 'timEmptyState').String), ' '), 'line spectrum');
            tc.verifyEmpty(ax.Legend);
        end

        function spectrumWithoutSensitivityAndEmpty(tc)
            m = tc.mSweep;
            for c = 1:4, m.mics(c).sensitivity_VperPa = NaN; end
            ax = tc.axesFor(1);
            info = tim.plots.spectrum(ax, m, []);
            tc.verifyEqual(ax.YLabel.String, 'PSD [dB re 1 V^2/Hz]');
            tc.verifySubstring(info.summary.columns{3}, 'dB re 1 V');
            tc.verifyTrue(all(isfinite(info.lines(1).YData)));
            % empty view: labels, band, default limits, message
            info = tim.plots.spectrum(ax, [], []);
            tc.verifyNotEmpty(findobj(ax, 'Tag', 'timEmptyState'));
            tc.verifyEqual(ax.YLabel.String, 'PSD [dB re (20 \muPa)^2/Hz]');
            tc.verifyNumElements(findobj(ax, 'Type', 'ConstantLine'), 2);
            tc.verifyLessThanOrEqual(ax.XLim(1), 20);
            tc.verifySize(info.summary.data, [4 4]);
            tc.verifyEmpty(findobj(ax, 'Type', 'line'));
        end

        % ---------------------------------------------------- transfer functions
        function transferFunctionsSweep(tc)
            ax = tc.axesFor(3);
            r = tc.rSweep;
            info = tim.plots.transferFunctions(ax, r);
            P = tim.gui.palette();
            f = r.spectra.f;
            tc.verifyNumElements(info.lines, 4);
            for m = 1:4
                tc.verifyEqual(info.lines(m).Color, P.ch(r.channelOfPosition(m), :));
                tc.verifyEqual(info.lines(m).YData(:), 20 * log10(abs(r.Hposition(:, m))), 'AbsTol', 1e-9);
            end
            tc.verifyEqual(ax(1).Legend.String, {'M1 (ch1)', 'M2 (ch2)', 'M3 (ch3)', 'M4 (ch4)'});
            % phase unwrapped in degrees
            ph = findobj(ax(2), 'Type', 'line', 'Color', P.ch(4, :));
            tc.verifyEqual(ph.YData(:), rad2deg(unwrap(angle(r.Hposition(:, 4)))), 'AbsTol', 1e-9);
            % coherence: reference channel (1 by definition) not drawn, limit line
            tc.verifyNumElements(findobj(ax(3), 'Type', 'line'), 3);
            yl = findobj(ax(3), 'Tag', 'timCoherenceLimit');
            tc.verifyEqual(yl.Value, 0.98);
            tc.verifyEqual(yl.LineStyle, '--');
            tc.verifyLessThan(ax(3).YLim(1), 0.98);
            % axes, labels, title
            tc.verifyEqual({ax.XScale}, {'log', 'log', 'log'});
            tc.verifyEqual(ax(1).XLim, ax(3).XLim);
            tc.verifyLessThanOrEqual(ax(1).XLim(1), min(f)); tc.verifyGreaterThanOrEqual(ax(1).XLim(2), max(f));
            tc.verifyEqual(ax(1).YLabel.String, '|H| [dB]');
            tc.verifyEqual(ax(2).YLabel.String, 'Phase [\circ]');
            tc.verifyEqual(ax(3).YLabel.String, 'Coherence [–]');
            tc.verifyEqual(ax(1).Title.String, tim.plots.dataTitle(r, struct('simulation', false)));
            tc.verifySubstring(ax(1).Title.String, 'NO calibration');
            tc.verifySubstring(info.note, 'NOT calibrated');
            tc.verifyEmpty(strtrim(ax(2).Title.String));
            % summary: per port, share of bins meeting coherence AND SNR limits
            S = info.summary;
            tc.verifyEqual(S.columns, {'Port', 'Channel', 'Median coherence', 'Min SNR [dB]', 'Lines meeting limits [%]'});
            tc.verifyEqual(S.data{1, 3}, 'reference');
            in = f >= 120 & f <= 4500;
            c3 = r.spectra.coherence(in, 3); s3 = r.spectra.snr_dB(in, 3);
            tc.verifyEqual(str2double(S.data{3, 3}), median(c3), 'AbsTol', 1e-4);
            tc.verifyEqual(str2double(S.data{3, 4}), min(s3), 'AbsTol', 0.06);
            tc.verifyEqual(str2double(S.data{3, 5}), 100 * mean(~(c3 < 0.98) & ~(s3 < 20)), 'AbsTol', 0.06);
        end

        function transferFunctionsFollowChannelInPort(tc)
            % colour = DAQ channel in the port, legend 'M1 (ch3)', opts.coherenceMin
            r = tc.rSweep;
            r.channelOfPosition = [3 1 2 4];
            ax = tc.axesFor(3);
            info = tim.plots.transferFunctions(ax, r, struct('coherenceMin', 0.95));
            P = tim.gui.palette();
            tc.verifyEqual(info.lines(1).Color, P.ch(3, :));
            tc.verifyEqual(info.lines(2).Color, P.ch(1, :));
            tc.verifyEqual(ax(1).Legend.String{1}, 'M1 (ch3)');
            tc.verifyEqual(findobj(ax(3), 'Tag', 'timCoherenceLimit').Value, 0.95);
            tc.verifyEqual(info.summary.data{2, 3}, 'reference', 'channel 1 (reference) sits in M2');
        end

        function transferFunctionsStepped(tc)
            ax = tc.axesFor(3);
            r = tc.rStep;
            info = tim.plots.transferFunctions(ax, r);
            tc.verifyEqual(info.lines(1).Marker, 'o');
            ph = findobj(ax(2), 'Type', 'line');
            tc.verifyNumElements(ph, 4);
            for i = 1:4
                tc.verifyEqual(ph(i).LineStyle, 'none', 'wrapped phase: markers only');
                tc.verifyLessThanOrEqual(max(abs(ph(i).YData)), 180 + 1e-9);
            end
            tc.verifyEqual(ax(2).YLim, [-225 225]);
            tc.verifyEqual(ax(2).YTick, -180:90:180);
            coh = findobj(ax(3), 'Type', 'line');
            tc.verifyEqual(unique({coh.Marker}), {'o'});
            tc.verifySubstring(info.note, 'wrapped');
            tc.verifyEqual(info.lines(2).XData(:), r.spectra.f, 'RelTol', 1e-12);
        end

        function transferFunctionsEmpty(tc)
            ax = tc.axesFor(3);
            info = tim.plots.transferFunctions(ax, []);
            tc.verifyEqual(findobj(ax(1), 'Tag', 'timEmptyState').String, 'No processed measurement yet');
            tc.verifyNotEmpty(findobj(ax(3), 'Tag', 'timCoherenceLimit'));
            tc.verifyEqual(ax(2).YLim, [-225 225]);
            tc.verifyEqual(ax(1).YLabel.String, '|H| [dB]');
            tc.verifyLessThan(ax(1).XLim(1), 120); tc.verifyGreaterThan(ax(1).XLim(2), 4500);
            tc.verifySize(info.summary.data, [4 5]);
            info = tim.plots.transferFunctions(ax, [], struct('emptyText', 'Process a measurement'));
            tc.verifyEqual(findobj(ax(1), 'Tag', 'timEmptyState').String, 'Process a measurement');
            tc.verifyEmpty(info.lines);
        end

        % --------------------------------------------------------------- GUI axes
        function viewsWorkInUiaxes(tc)
            fig = uifigure('Visible', 'off', 'Position', [50 50 1180 640]);
            tc.addTeardown(@() delete(fig));
            g = uigridlayout(fig, [4 3]);
            axW = gobjects(1, 4);
            for c = 1:4, axW(c) = uiaxes(g); axW(c).Layout.Row = c; axW(c).Layout.Column = 1; end
            axS = uiaxes(g); axS.Layout.Row = [1 4]; axS.Layout.Column = 2;
            axT = gobjects(1, 3);
            for c = 1:3, axT(c) = uiaxes(g); axT(c).Layout.Row = c; axT(c).Layout.Column = 3; end
            i1 = tim.plots.timeSignals(axW, tc.mStep, struct('simulation', true));
            tc.verifySubstring(axW(1).Title.String, 'SIMULATION');
            tc.verifyNumElements(findobj(axW(2), 'Type', 'line'), 1);
            tc.verifyEqual(i1.axes, axW);
            tim.plots.spectrum(axS, tc.mStep, tc.rStep);
            tc.verifyNumElements(findobj(axS, 'Type', 'line', 'Marker', 'o'), 4);
            tim.plots.transferFunctions(axT, tc.rSweep);
            tim.plots.transferFunctions(axT, tc.rSweep);      % redraw: nothing accumulates
            tc.verifyNumElements(findobj(axT(1), 'Type', 'line'), 4);
            tc.verifyNumElements(findobj(axT(3), 'Type', 'ConstantLine'), 1);
        end
    end
end
