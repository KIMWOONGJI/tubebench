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
            % a swept sine: its strip too (1.6.3)
            h.exMode.Value = 'sweep'; feval(h.exMode.ValueChangedFcn, h.exMode, struct('PreviousValue', 'stepped'));
            feval(h.start.ButtonPushedFcn, h.start, []);
            tc.verifyEqual(char(h.axP.Visible), 'on', 'swept sine: strip');
            tc.verifySubstring(h.axP.Title.String, 'Done · 1 sweep');
            tc.verifyEqual(app.Session.Progress.kind, 'sweep');
            % background noise: no strip
            feval(h.background.ButtonPushedFcn, h.background, []);
            tc.verifyEqual(char(h.axP.Visible), 'off', 'background noise: no strip');
        end
    end
end
