classdef TestProgressStrip < matlab.unittest.TestCase
    %TESTPROGRESSSTRIP The stepped-sine progress strip above the time signals
    %   (1.6.1, owner request 2026-11-05): the state from the session's
    %   Progress (tim.gui.stepProgress), its drawing (tim.gui.progressStrip) and
    %   the strip in a hidden window during stepped and swept measurements.

    properties
        tmp
    end

    methods (TestMethodSetup)
        function setup(tc)
            f = tc.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            tc.tmp = f.Folder;
        end
    end

    methods (Static)
        function prog = progress(nSteps, passes, nReps)
            st = struct('fStart', 200, 'fStop', 800, 'nPoints', nSteps, 'spacing', 'log', 'settleTime', 0.3, ...
                'settleCycles', 50, 'recordTime', 0.2, 'recordCycles', 100);
            prog = struct('kind', 'stepped', 'passes', {passes}, 'pass', 1, 'rep', 1, 'nReps', nReps, ...
                'plan', tim.app.steppedPlan(st), 'fs', 1000, 'n', 0, 'onSample', NaN, 'state', 'running');
        end
        function prog = at(prog, t)
            % the running acquisition t seconds after its start (output on at the planned pre-roll)
            prog.n = round(t * prog.fs);
            if t >= prog.plan.pre_s, prog.onSample = round(prog.plan.pre_s * prog.fs); else, prog.onSample = NaN; end
        end
    end

    methods (Test)
        function stateFollowsTheSchedule(tc)
            prog = TestProgressStrip.progress(3, {'Measurement'}, 1);
            pl = prog.plan;
            g = tim.gui.stepProgress(TestProgressStrip.at(prog, 0.2));
            tc.verifyEqual(g.phase, 'starting');
            tc.verifyEqual(g.label, 'Measurement · starting');
            tc.verifyEqual(g.T, pl.total_s, 'AbsTol', 1e-12);
            tc.verifySize(g.rect, [6 2], 'two parts per step');
            tc.verifyEqual(diff(g.rect(g.part == 2, :), 1, 2), pl.record_s(:), 'AbsTol', 1e-12, 'widths = planned times');
            % in the settling of step 2, then in its measurement
            t = pl.pre_s + pl.step_s(1) + pl.settle_s(2) / 2;
            g = tim.gui.stepProgress(TestProgressStrip.at(prog, t));
            tc.verifyEqual([g.k, g.x], [2, t], 'AbsTol', 1e-3);
            tc.verifyEqual(g.phase, 'settling');
            tc.verifyEqual(g.label, sprintf('Measurement · step 2 of 3 · %.0f Hz · settling', pl.freqs(2)));
            tc.verifySubstring(g.right, sprintf(' of %.1f s · about ', pl.total_s));
            g = tim.gui.stepProgress(TestProgressStrip.at(prog, t + pl.settle_s(2) / 2 + 0.01));
            tc.verifyEqual(g.phase, 'measuring');
            g = tim.gui.stepProgress(TestProgressStrip.at(prog, pl.total_s - 0.1));
            tc.verifyEqual(g.phase, 'finishing');
            % done / stopped
            p = TestProgressStrip.at(prog, pl.total_s); p.state = 'done';
            g = tim.gui.stepProgress(p);
            tc.verifyEqual(g.label, sprintf('Done · 3 steps · %.1f s', pl.total_s));
            tc.verifyEqual(g.status, 'ok');
            tc.verifyEqual(g.right, sprintf('%.1f s', pl.total_s), 'the right text keeps its line (1.6.3)');
            p = TestProgressStrip.at(prog, t); p.state = 'stopped';
            g = tim.gui.stepProgress(p, 'Load A (1 of 3) · ');
            tc.verifyEqual(g.label, 'Load A (1 of 3) · Stopped at step 2 of 3 (Measurement)');
            tc.verifyEqual(g.status, 'fail');
        end

        function passesAndRepetitionsShareOneTimeLine(tc)
            prog = TestProgressStrip.progress(4, {'Pre-measurement (-20 dB)', 'Measurement'}, 2);
            Tg = prog.plan.total_s;
            g = tim.gui.stepProgress(prog);
            tc.verifyEqual(g.T, 4 * Tg, 'AbsTol', 1e-12, 'two passes x two repetitions');
            tc.verifyEqual(g.groups(:, 1).', (0:3) * Tg, 'AbsTol', 1e-12);
            tc.verifyEqual(g.groupName.', {'Pre-measurement 1', 'Pre-measurement 2', 'Measurement 1', 'Measurement 2'});
            p = TestProgressStrip.at(prog, prog.plan.pre_s + 0.01); p.pass = 2; p.rep = 2;
            g = tim.gui.stepProgress(p);
            tc.verifyEqual(g.x, 3 * Tg + prog.plan.pre_s + 0.01, 'AbsTol', 1e-3, 'last group');
            tc.verifySubstring(g.label, 'Measurement · step 1 of 4');
            tc.verifySubstring(g.label, ' · rep 2 of 2');
            p.state = 'processing'; p.pass = 1;
            g = tim.gui.stepProgress(p);
            tc.verifyEqual(g.label, 'Pre-measurement (-20 dB) done · processing it');
            p.state = 'done';
            g = tim.gui.stepProgress(p);
            tc.verifyEqual(g.label, sprintf('Done · pre-measurement and 4 steps · %.1f s', 4 * Tg));
        end

        function octaveTicksOfTheDefaultSteps(tc)
            c = tim.app.defaultConfig();
            prog = TestProgressStrip.progress(3, {'Measurement'}, 1);
            prog.plan = tim.app.steppedPlan(c.excitation.stepped);
            g = tim.gui.stepProgress(prog);
            tc.verifyEqual(g.tickF, [125 250 500 1000 2000 4000]);
        end

        function drawingColoursTheSteps(tc)
            f = figure('Visible', 'off'); tc.addTeardown(@() close(f));
            ax = axes(f);
            P = tim.gui.palette();
            prog = TestProgressStrip.progress(3, {'Measurement'}, 1);
            pl = prog.plan;
            t = pl.pre_s + pl.step_s(1) + pl.settle_s(2) / 2;            % settling of step 2
            tim.gui.progressStrip(ax, TestProgressStrip.at(prog, t));
            hp = findobj(ax, 'Tag', 'timProgressSteps');
            tc.assertNumElements(hp, 1);
            C = hp.FaceVertexCData;
            % 1.6.2: the colours of the window - the slate of the section bars for
            % the steps done, the accent blue for the running step, no amber
            K = tim.gui.progressStrip('colours');
            tc.verifyEqual(K.done, P.ui.bar);
            tc.verifyEqual(K.running, P.ui.accent);
            tc.verifyEqual(C(2, :), P.ui.bar, 'AbsTol', 1e-12, 'step 1 measured: slate of the section bars');
            tc.verifyEqual(C(1, :), 1 - 0.45 * (1 - P.ui.bar), 'AbsTol', 1e-12, 'step 1 settled: lighter');
            tc.verifyEqual(C(5, :), K.track, 'AbsTol', 1e-12, 'step 3 to come: light grey');
            hf = findobj(ax, 'Tag', 'timProgressFill');
            tc.verifyEqual(hf.FaceColor, 1 - 0.45 * (1 - P.ui.accent), 'AbsTol', 1e-12, 'running step settling: light accent');
            tc.verifyEqual(max(hf.Vertices(:, 1)), t, 'AbsTol', 1e-3, 'filled up to now');
            tc.verifySubstring(ax.Title.String, 'step 2 of 3');
            tc.verifyEqual(ax.TitleHorizontalAlignment, 'left');
            tc.verifyEqual(ax.Title.FontWeight, 'normal', 'as the titles of the graphs');
            tc.verifyEqual([ax.FontSize, ax.Title.FontSize], [11 11], 'the 11 pt of the graphs');
            ht = findobj(ax, 'Tag', 'timProgressTime');
            tc.verifyNotEmpty(ht.String);
            tc.verifyEqual(ht.Position(2), ax.Title.Position(2), 'AbsTol', 1e-9, 'time on the line of the label');
            % the same objects updated: done = slate with a green label, stopped = light red rest
            p = TestProgressStrip.at(prog, pl.total_s); p.state = 'done';
            tim.gui.progressStrip(ax, p);
            tc.verifyNumElements(findobj(ax, 'Tag', 'timProgressSteps'), 1, 'objects reused');
            C = findobj(ax, 'Tag', 'timProgressSteps').FaceVertexCData;
            tc.verifyEqual(C(2:2:end, :), repmat(P.ui.bar, 3, 1), 'AbsTol', 1e-12);
            tc.verifyEqual(ax.Title.Color, K.ok, 'AbsTol', 1e-12);
            p = TestProgressStrip.at(prog, t); p.state = 'stopped';
            tim.gui.progressStrip(ax, p);
            C = findobj(ax, 'Tag', 'timProgressSteps').FaceVertexCData;
            tc.verifyEqual(C(end, :), K.notPlayed, 'AbsTol', 1e-12);
            tc.verifyEqual(ax.Title.Color, P.fail, 'AbsTol', 1e-12);
            tim.gui.progressStrip(ax, []);
            tc.verifyEmpty(findobj(ax, '-regexp', 'Tag', '^timProgress'));
            tc.verifyEqual(char(ax.Visible), 'off');
        end

        function liveAxesStayFixed(tc)
            % 1.6.2 / 1.6.3 (owner reports 2026-11-05): the live limits grow only,
            % on the 1-2-5 series from 0.1 Pa, with fixed ticks, no exponent and
            % tick labels of one width, so the plot areas (and the strip above)
            % do not move when the limit grows during a measurement
            f = figure('Visible', 'off'); tc.addTeardown(@() close(f));
            ax = axes(f);
            L = tim.gui.liveAxis(ax, [], 0.31);
            tc.verifyEqual(L, 0.5);
            tc.verifyEqual(ax.YLim, [-0.5 0.5]); tc.verifyEqual(ax.XLim, [-0.5 0]);
            tc.verifyEqual(ax.YTick, [-0.5 -0.25 0 0.25 0.5]);
            tc.verifyEqual(double(ax.YAxis.Exponent), 0);
            fig = char(8199); mn = char(8722);
            tc.verifyEqual(ax.YTickLabel(:).', {[mn fig fig '0.50'], [mn fig fig '0.25'], [fig fig fig '0.00'], ...
                [fig fig fig '0.25'], [fig fig fig '0.50']});
            tc.verifyEqual(tim.gui.liveAxis(ax, L, 0.05), 0.5, 'a smaller peak keeps the limit');
            tc.verifyEqual(ax.YLim, [-0.5 0.5]);
            tc.verifyEqual(tim.gui.liveAxis(ax, L, 0.6), 1, 'a larger peak raises it');
            tc.verifyEqual(tim.gui.liveAxis(ax, [], 0.0012), 0.1, 'from 0.1 Pa: noise before the output is on');
            tc.verifyEqual(tim.gui.liveAxis(ax, [], 0), 0.1, 'nothing yet');
            % every limit of a measurement up to 999 Pa: the same label pattern
            % (sign slot, three integer slots, two decimals) -> one width
            % (a figure space U+2007 is as wide as a digit)
            slot = ['[' mn fig ']' '[0-9' fig ']{3}' '\.' '[0-9]{2}'];
            for L = [0.1 0.2 0.5 1 2 5 10 20 50 100 200 500]
                s = tim.gui.liveAxis('labels', L);
                tc.verifyEqual(cellfun(@numel, s), 7 * ones(1, 5), sprintf('L = %g', L));
                tc.verifyTrue(all(cellfun(@(x) ~isempty(regexp(x, ['^' slot '$'], 'once')), s)), ...
                    sprintf('L = %g: sign slot, three integer slots, two decimals', L));
            end
            % 1.6.3 check: the axes of the view drawn before (tim.plots.fitAxes) took
            % every live limit change for a zoom and switched the ticks and labels to
            % automatic at the next drawnow, so the graphs jumped between updates
            % (the callback does not fire in an invisible figure: it is called here)
            ax2 = axes(f);
            plot(ax2, [0 1], [-1 1]); tim.plots.fitAxes(ax2);
            ax2.XTickLabel = {};                            % hidden labels of a stacked axes
            tim.gui.liveAxis(ax2, [], 0);
            tim.gui.liveAxis(ax2, 0.1, 3);                  % the limit grows during the action
            feval(ax2.YAxis.LimitsChangedFcn, ax2.YAxis, []);
            feval(ax2.XAxis.LimitsChangedFcn, ax2.XAxis, []);
            tc.verifyEqual(ax2.YTickLabelMode, 'manual', 'the fixed labels stay');
            tc.verifyEqual(ax2.YLim, [-5 5]);
            tc.verifyEqual(ax2.XTickLabelMode, 'manual', 'hidden x labels stay hidden');
            tc.verifyEmpty(ax2.XTickLabel);
        end

        function sweepFollowsTheSchedule(tc)
            % 1.6.3 (owner request 2026-11-05): the strip of a swept sine - one
            % block per repetition, the frequency of the sweep now, octave marks
            sw = struct('fStart', 100, 'fStop', 6400, 'spacing', 'LOG', 'duration', 2, 'repetitions', 3, ...
                'preRoll', 1, 'postRoll', 1);
            prog = tim.app.MeasurementSession.newSweepProgress(sw, 1000);
            pl = prog.plan;
            tc.verifyEqual(pl.total_s, 1 + 2 + 1.2, 'AbsTol', 1e-12, 'pre-roll, sweep, post-roll + 0.2 s');
            g = tim.gui.stepProgress(prog);
            tc.verifyEqual(g.T, 3 * pl.total_s, 'AbsTol', 1e-12);
            tc.verifySize(g.rect, [3 2], 'one block per repetition');
            tc.verifyEqual(g.tickF, [125 250 500 1000 2000 4000]);
            tc.verifyEqual(g.tickT(3), 1 + 2 * log(500 / 100) / log(64), 'AbsTol', 1e-12, '500 Hz when the sweep passes it');
            tc.verifyEqual(g.tickLabel, {'125', '250', '500', '1k', '2k', '4k'});
            tc.verifyEqual(g.label, 'Swept sine · rep 1 of 3 · starting');
            % half way through the second sweep: 800 Hz (log sweep 100 -> 6400 Hz)
            p = prog; p.rep = 2; p.n = 2000; p.onSample = 1000;
            g = tim.gui.stepProgress(p, 'Load A (1 of 3) · ');
            tc.verifyEqual(g.phase, 'sweeping');
            tc.verifyEqual(g.f, 800, 'AbsTol', 1e-9);
            tc.verifyEqual(g.x, pl.total_s + 1 + 1, 'AbsTol', 1e-9);
            tc.verifyEqual(g.label, 'Load A (1 of 3) · Swept sine · 800 Hz · sweeping · rep 2 of 3');
            p.state = 'done'; g = tim.gui.stepProgress(p);
            tc.verifyEqual(g.label, sprintf('Done · 3 sweeps · %.1f s', 3 * pl.total_s));
            p.state = 'stopped'; g = tim.gui.stepProgress(p);
            tc.verifyEqual(g.label, 'Stopped in swept sine, repetition 2 of 3');
            % drawn: one block per sweep, no separators between steps
            f = figure('Visible', 'off'); tc.addTeardown(@() close(f));
            ax = axes(f);
            p.state = 'running'; tim.gui.progressStrip(ax, p);
            tc.verifyEqual(size(findobj(ax, 'Tag', 'timProgressSteps').FaceVertexCData, 1), 3);
            tc.verifyTrue(all(isnan(findobj(ax, 'Tag', 'timProgressSep').XData)), 'no step separators');
            K = tim.gui.progressStrip('colours');
            tc.verifyEqual(findobj(ax, 'Tag', 'timProgressFill').FaceColor, K.running, 'the running sweep: accent');
        end

        function windowShowsTheStripForSteppedAndSwept(tc)
            c = tim.app.defaultConfig();
            c.mode = 'simulation';
            c.geometry = c.simulation.Geometry;
            c.output.dataDir = fullfile(tc.tmp, 'data'); c.output.calibrationDir = fullfile(tc.tmp, 'cal');
            c.excitation.mode = 'stepped';
            c.excitation.stepped = struct('fStart', 200, 'fStop', 4000, 'nPoints', 4, 'spacing', 'log', ...
                'amplitudeVpp', 0.2, 'settleTime', 0.1, 'recordTime', 0.2, 'nBlocks', 2, 'repetitions', 1);
            c.excitation.sweep.duration = 1; c.excitation.sweep.repetitions = 1;
            file = fullfile(tc.tmp, 'cfg.json'); tim.app.saveConfig(c, file);
            app = tim.gui.Tubebench(file, 'Visible', 'off'); tc.addTeardown(@() delete(app));
            h = app.H;
            tc.verifyEqual(char(h.axP.Visible), 'off', 'no strip before a stepped measurement');
            feval(h.connect.ButtonPushedFcn, h.connect, []);
            feval(h.start.ButtonPushedFcn, h.start, []);
            tc.assertNotEmpty(app.LastRes);
            tc.verifyEqual(char(h.axP.Visible), 'on');
            tc.verifySubstring(h.axP.Title.String, 'Done · 4 steps');
            tc.verifyEqual(app.Session.Progress.state, 'done');
            % the strip lines up with the time signals (same plot-area edges)
            drawnow;
            pw = h.axW(1).InnerPosition; pp = h.axP.InnerPosition;
            tc.verifyEqual(pp([1 3]), pw([1 3]), 'AbsTol', 1e-6, 'same left edge and width as the time signals');
            % the note row of the header keeps its height (1.6.3: KeepNote)
            tc.verifyEqual(app.Pages.wave.Grid.RowHeight{1}, 92);
            app.Pages.wave.setNote('');
            tc.verifyEqual(app.Pages.wave.Grid.RowHeight{1}, 92, 'no layout change when the note goes');
            % the live spectrum (2026-11-15): the default view of an action, with
            % the same strip, done at the end, lined up with its graph
            tc.verifyEqual(h.measTabs.SelectedTab, h.specTab, 'an action opens the Spectrum view');
            tc.verifyGreaterThan(app.LiveCount, 0, 'live refreshes during the measurement');
            tc.verifyEqual(char(h.axPSpec.Visible), 'on');
            tc.verifySubstring(h.axPSpec.Title.String, 'Done · 4 steps');
            ps = h.axSpec.InnerPosition; pq = h.axPSpec.InnerPosition;
            tc.verifyEqual(pq([1 3]), ps([1 3]), 'AbsTol', 1e-6, 'same left edge and width as the spectrum');
            tc.verifyEqual(app.Pages.spec.Grid.RowHeight{1}, 92, 'the note row is always there');
            % a swept sine: its strip too (1.6.3)
            h.exMode.Value = 'sweep'; feval(h.exMode.ValueChangedFcn, h.exMode, struct('PreviousValue', 'stepped'));
            feval(h.start.ButtonPushedFcn, h.start, []);
            tc.verifyEqual(char(h.axP.Visible), 'on', 'swept sine: strip');
            tc.verifySubstring(h.axP.Title.String, 'Done · 1 sweep');
            tc.verifySubstring(h.axPSpec.Title.String, 'Done · 1 sweep');
            tc.verifyEqual(app.Session.Progress.kind, 'sweep');
            % the result replaced the live curves: the Welch PSD of the record
            tc.verifyEmpty(findobj(h.axSpec, '-regexp', 'Tag', '^timLive'), 'no live curve left');
            tc.verifyEqual(h.axSpec.YLabel.String, 'Level [dB SPL]', 'the swept sine in dB SPL');
            tc.verifyNumElements(findobj(h.axSpec, 'Type', 'line', 'LineWidth', 1.1), 4);
            % background noise: no strip
            feval(h.background.ButtonPushedFcn, h.background, []);
            tc.verifyEqual(char(h.axP.Visible), 'off', 'background noise: no strip');
            tc.verifyEqual(char(h.axPSpec.Visible), 'off');
        end

        function liveSpectrumStaysFixed(tc)
            % 2026-11-15 (owner request): the live spectrum - the estimate of the
            % result view over the last 1 s, fixed frequency axis, a y range that
            % only grows on a 20 dB grid, labels of one width, axes not "fitted"
            fs = 16384; n = tim.gui.liveSpectrum('samples', fs);
            tc.verifyEqual(n, fs, 'the last 1 s');
            t = (0:n - 1).' / fs;
            rng(7);
            nz = 0.002 * randn(n, 2);
            tone = [sqrt(2) * sin(2 * pi * 1000 * t), zeros(n, 1)];        % 1 Pa rms tone in ch1
            x = tone + nz;
            [f, G] = tim.gui.liveSpectrum('psd', x, fs);
            [G0, f0] = pwelch(x - mean(x, 1), hann(8192, 'periodic'), 6144, 8192, fs);
            tc.verifyEqual(f, f0); tc.verifyEqual(G, G0, 'RelTol', 1e-12, 'the estimate of tim.plots.spectrum');
            df = f(2) - f(1);
            tc.verifyEqual(sum(G(:, 1)) * df, 1, 'RelTol', 0.01, 'Parseval: 1 Pa^2');
            fg = figure('Visible', 'off'); tc.addTeardown(@() close(fg));
            ax = axes(fg);
            plot(ax, [10 100], [0 1]); tim.plots.fitAxes(ax);          % the result drawn before
            o = struct('fs', fs, 'pa', true, 'names', {{'ch1 (M1)', 'ch2 (M2)'}}, 'colours', lines(2), 'band', [120 4500]);
            S = tim.gui.liveSpectrum('prepare', ax, o);
            tc.verifyFalse(isappdata(ax, 'timFitAxes'), 'no fitted record: the zoom handler is inert');
            xl = ax.XLim; tc.verifyEqual(ax.YLim, [-20 100]);
            tc.verifyNotEmpty(findobj(ax, 'Tag', 'timEmptyState'), 'waiting for data');
            src = @TestProgressStrip.source;
            S = tim.gui.liveSpectrum('update', S, src(x));
            tc.verifyEmpty(findobj(ax, 'Tag', 'timEmptyState'));
            tc.verifyEqual(S.level(1), 20 * log10(1 / 2e-5), 'AbsTol', 0.1, 'level of the 1 Pa tone');
            tc.verifyEqual(ax.XLim, xl, 'the frequency axis stays');
            yl = ax.YLim;
            tc.verifyEqual(mod(yl, 20), [0 0]); tc.verifyGreaterThanOrEqual(yl(2), max(S.L(:)) + 5);
            S = tim.gui.liveSpectrum('update', S, src(0.1 * tone + nz));     % quieter: the range stays
            tc.verifyEqual(ax.YLim, yl, 'the y range only grows');
            tim.gui.liveSpectrum('update', S, src(100 * tone + nz));         % louder: it grows
            tc.verifyGreaterThan(ax.YLim(2), yl(2));
            tc.verifyEqual(ax.YLim(1), yl(1), 'the bottom follows the noise floor, not the tone');
            feval(ax.YAxis.LimitsChangedFcn, ax.YAxis, []);
            tc.verifyEqual(ax.YTickLabelMode, 'manual', 'the fixed labels stay');
            fig = char(8199); mn = char(8722);
            tc.verifyEqual(tim.gui.liveSpectrum('labels', [-120 40]), {[mn '120'], [mn '100'], [fig mn '80'], ...
                [fig mn '60'], [fig mn '40'], [fig mn '20'], [fig fig fig '0'], [fig fig '20'], [fig fig '40']}, ...
                'right-aligned in four places, the minus next to the digits');
            s = tim.gui.liveSpectrum('labels', [-160 140]);
            tc.verifyEqual(unique(cellfun(@numel, s)), 4, 'one width from -160 to 140 dB');
            % on the axes of a swept-sine result with its right axis (incident
            % level): the right axis is emptied and hidden, the live curves on the left
            ax3 = axes(fg);
            plot(ax3, [100 1000], [0 1]); yyaxis(ax3, 'right'); plot(ax3, [100 1000], [80 90]); yyaxis(ax3, 'left');
            S3 = tim.gui.liveSpectrum('prepare', ax3, o);
            tc.verifyEqual(char(ax3.YAxis(2).Visible), 'off');
            tim.gui.liveSpectrum('update', S3, src(x));
            tc.verifyEqual(double(ax3.YAxis(1).Exponent), 0);
            tc.verifyNumElements(findobj(ax3, '-regexp', 'Tag', '^timLiveSpec'), 2);
        end

        function liveSweepGrowsToTheResult(tc)
            % 2026-11-15 (owner decisions): a swept sine live in dB SPL - the light
            % curve of the last 1 s, the full-colour result so far (Welch average
            % over repetition 1) that ends as the result view's sine-equivalent
            % level; a 1 Pa sweep reads 91 dB SPL, as a 1 Pa stepped sine
            fs = 16384; sw = struct('fStart', 80, 'fStop', 5500, 'duration', 5, 'spacing', 'LOG');
            pre = 1; T = sw.duration; N = round((pre + T + 1.2) * fs);
            t = (0:N - 1).' / fs; ts = t - pre; on = ts >= 0 & ts < T;
            K = T / log(sw.fStop / sw.fStart);
            s = zeros(N, 1); s(on) = sin(2 * pi * sw.fStart * K * (exp(ts(on) / K) - 1));
            rng(3); x = s * [1 0.5] + 1e-4 * randn(N, 2);                    % 1 Pa and 0.5 Pa peak
            fg = figure('Visible', 'off'); tc.addTeardown(@() close(fg));
            ax = axes(fg);
            o = struct('kind', 'sweep', 'fs', fs, 'pa', true, 'names', {{'ch1 (M1)', 'ch2 (M2)'}}, ...
                'colours', lines(2), 'band', [120 4500], 'sweep', sw);
            S = tim.gui.liveSpectrum('prepare', ax, o);
            tc.verifyEqual(ax.YLabel.String, 'Level [dB SPL]');
            tc.verifyEqual(ax.Legend.String, {'ch1 (M1)', 'ch2 (M2)', 'Last 1 s (live)', 'Analysis band 120 – 4500 Hz'});
            c1 = findobj(ax, 'Tag', 'timLiveSpec1'); r1 = findobj(ax, 'Tag', 'timLiveResult1');
            tc.verifyEqual(c1.Color, 0.35 * o.colours(1, :) + 0.65, 'AbsTol', 1e-12, 'live: the light channel colour');
            tc.verifyEqual(r1.Color, o.colours(1, :), 'result: the channel colour');
            tc.verifyEqual([c1.LineWidth r1.LineWidth], [0.8 1.1]);
            prog = struct('kind', 'sweep', 'rep', 1, 'pass', 1, 'onSample', round(pre * fs), 'state', 'running');
            src = @TestProgressStrip.source;
            % the planning pass of a device that plans first (simulation): an
            % acquisition of repetition 1 that is not the measurement - the
            % result so far starts again with the next acquisition
            xp = 1e-4 * randn(round(2 * fs), 2);
            for nNow = round(0.2 * fs):round(0.2 * fs):size(xp, 1)
                S = tim.gui.liveSpectrum('update', S, src(xp(1:nNow, :)), prog);
            end
            tc.verifyLessThan(max(S.R(:)), 60, 'the planning pass: noise only');
            nMid = round((pre + T / 2) * fs);
            for nNow = round(0.2 * fs):round(0.2 * fs):N
                S = tim.gui.liveSpectrum('update', S, src(x(1:nNow, :)), prog);
                if nNow <= nMid && nNow + round(0.2 * fs) > nMid
                    % half way: the last 1 s holds the sweep from 285 to 663 Hz at 91 dB
                    [~, i] = max(S.L(:, 1));
                    tc.verifyGreaterThan(S.f(i), 250); tc.verifyLessThan(S.f(i), 700);
                    in = S.f > 400 & S.f < 475;                             % swept at full window weight
                    tc.verifyEqual(median(S.L(in, 1)), 20 * log10(1 / sqrt(2) / 2e-5), 'AbsTol', 1, 'live level');
                    tc.verifyTrue(isempty(S.R) || all(isnan(S.R(S.f < 80, 1))));
                end
            end
            S = tim.gui.liveSpectrum('update', S, src(x), prog);
            % the result so far = the result view's sine-equivalent level of the record
            [G, f] = pwelch(x - mean(x, 1), hann(8192, 'periodic'), 6144, 8192, fs);
            k = f >= 20;
            Lr = 10 * log10(tim.dsp.sweepSineLevel(G(k, :), f(k), tim.dsp.welchDuration(N, 8192, fs), sw) / 4e-10);
            in = f(k) >= 200 & f(k) <= 4000;
            tc.verifyEqual(S.R(in, :), Lr(in, :), 'AbsTol', 0.2, 'the live result ends as the result view');
            tc.verifyEqual(median(S.R(in, 1)), 20 * log10(1 / sqrt(2) / 2e-5), 'AbsTol', 0.3, '1 Pa: 91 dB SPL');
            tc.verifyEqual(median(S.R(in, 2)), 20 * log10(0.5 / sqrt(2) / 2e-5), 'AbsTol', 0.3, '0.5 Pa: 85 dB SPL');
            % repetition 2: the result keeps repetition 1 (as the result view)
            R1 = S.R;
            prog.rep = 2;
            S = tim.gui.liveSpectrum('update', S, src(0.1 * x(1:round(3 * fs), :)), prog);
            tc.verifyEqual(S.R, R1, 'frozen after repetition 1');
            tc.verifyLessThanOrEqual(max(S.R(:)), ax.YLim(2));
        end

        function liveSteppedMarksEveryStep(tc)
            % 2026-11-15: a stepped sine live in dB SPL - the light power spectrum
            % of the last 0.25 s (a tone's peak = its level) and a full-colour marker
            % for every step whose measured part has ended (sine fit)
            fs = 16384;
            st = struct('fStart', 200, 'fStop', 2000, 'nPoints', 4, 'spacing', 'log', 'settleTime', 0.1, ...
                'settleCycles', 0, 'recordTime', 0.3, 'recordCycles', 0);
            pl = tim.app.steppedPlan(st);
            on = round(0.5 * fs);
            s0 = [0, cumsum(pl.step_s(1:end - 1))];
            N = on + round(sum(pl.step_s) * fs) + round(0.5 * fs);
            rng(5); x = 1e-4 * randn(N, 2);
            A = 0.1 * (1:4);                                                  % Pa peak of the steps
            for k = 1:4
                idx = on + round(s0(k) * fs) + (1:round(pl.step_s(k) * fs));
                t = (idx(:) - 1) / fs;
                x(idx, :) = x(idx, :) + A(k) * sin(2 * pi * pl.freqs(k) * t + 0.3) * [1 0.5];
            end
            fg = figure('Visible', 'off'); tc.addTeardown(@() close(fg));
            ax = axes(fg);
            o = struct('kind', 'stepped', 'fs', fs, 'pa', true, 'names', {{'ch1 (M1)', 'ch2 (M2)'}}, ...
                'colours', lines(2), 'band', [120 4500], 'plan', pl);
            S = tim.gui.liveSpectrum('prepare', ax, o);
            tc.verifyEqual(ax.YLabel.String, 'Tone level [dB SPL]');
            tc.verifyEqual(findobj(ax, 'Tag', 'timLiveResult1').Marker, 'o');
            prog = struct('kind', 'stepped', 'pass', 1, 'rep', 1, 'onSample', on, 'state', 'running');
            src = @TestProgressStrip.source;
            want = 20 * log10(A(:) / sqrt(2) / 2e-5) + [0, 20 * log10(0.5)];
            i3 = on + round((s0(3) + pl.settle_s(3) + pl.record_s(3)) * fs);
            % a planning pass first (noise only, as far as step 3): its markers go
            % when the measurement's acquisition starts
            for nNow = round(0.2 * fs):round(0.2 * fs):i3 + round(0.1 * fs)
                S = tim.gui.liveSpectrum('update', S, src(1e-4 * randn(nNow, 2)), prog);
            end
            tc.verifyLessThan(max(S.R(:)), 40, 'the planning pass: noise only');
            for nNow = round(0.2 * fs):round(0.2 * fs):N
                S = tim.gui.liveSpectrum('update', S, src(x(1:nNow, :)), prog);
                if nNow < i3 && nNow + round(0.2 * fs) >= i3
                    tc.verifyTrue(all(isnan(S.R(3:4, 1))), 'step 3 not done yet');
                    tc.verifyEqual(S.R(1:2, :), want(1:2, :), 'AbsTol', 0.05, 'steps 1 and 2 done');
                end
            end
            S = tim.gui.liveSpectrum('update', S, src(x), prog);
            tc.verifyEqual(S.R, want, 'AbsTol', 0.05, 'the tone level of every step');
            % repetition 2 at twice the amplitude: the mean amplitude of both
            % (as res.toneLevels), steps not yet measured in it keep repetition 1
            x2 = 1e-4 * randn(N, 2);
            for k = 1:4
                idx = on + round(s0(k) * fs) + (1:round(pl.step_s(k) * fs));
                t = (idx(:) - 1) / fs;
                x2(idx, :) = x2(idx, :) + 2 * A(k) * sin(2 * pi * pl.freqs(k) * t) * [1 0.5];
            end
            prog.rep = 2;
            S = tim.gui.liveSpectrum('update', S, src(x2(1:i3, :)), prog);
            tc.verifyEqual(S.R(1:3, :), want(1:3, :) + 20 * log10(1.5), 'AbsTol', 0.05, 'mean of both repetitions');
            tc.verifyEqual(S.R(4, :), want(4, :), 'AbsTol', 0.05, 'step 4: repetition 1 so far');
            S = tim.gui.liveSpectrum('update', S, src(x2), prog);
            tc.verifyEqual(S.R, want + 20 * log10(1.5), 'AbsTol', 0.05);
            % the live power spectrum of the last 0.25 s: the last tone's peak at its
            % level (within the scalloping of the Hann window)
            m = round((on + round((s0(4) + pl.step_s(4) - 0.05) * fs)));
            S = tim.gui.liveSpectrum('update', S, src(x(1:m, :)), prog);
            [pk, i] = max(S.L(:, 1));
            tc.verifyEqual(S.f(i), pl.freqs(4), 'AbsTol', 3);
            tc.verifyEqual(pk, want(4, 1), 'AbsTol', 1.5);
            % a new pass (the equalizer's measurement after its pre-measurement)
            % starts the markers again
            prog.pass = 2; prog.onSample = N;
            S = tim.gui.liveSpectrum('update', S, src(x), prog);
            tc.verifyTrue(all(isnan(S.R(:))), 'new pass: no step done yet');
        end
    end

    methods (Static)
        function get = source(x)
            % the 'get' of tim.gui.liveSpectrum on the samples x received so far
            get = @(n) TestProgressStrip.tail(x, n);
        end
        function [y, N] = tail(x, n)
            % the last <= n rows of x and the number of rows (as Daq.recent)
            N = size(x, 1);
            y = x(max(1, N - n + 1):N, :);
        end
    end
end
