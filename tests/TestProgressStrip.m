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
            tc.verifyEqual(g.status, 'ok'); tc.verifyEmpty(g.right);
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
            % 1.6.2 (owner report 2026-11-05): the live limits grow only, on the
            % 1-2-5 series, with fixed ticks and number format and no exponent,
            % so the plot areas (and the strip above) do not move
            f = figure('Visible', 'off'); tc.addTeardown(@() close(f));
            ax = axes(f);
            L = tim.gui.liveAxis(ax, [], 0.31);
            tc.verifyEqual(L, 0.5);
            tc.verifyEqual(ax.YLim, [-0.5 0.5]); tc.verifyEqual(ax.XLim, [-0.5 0]);
            tc.verifyEqual(ax.YTick, [-0.5 -0.25 0 0.25 0.5]);
            tc.verifyEqual(double(ax.YAxis.Exponent), 0);
            tc.verifyEqual(ax.YAxis.TickLabelFormat, '%.2f');
            tc.verifyEqual(tim.gui.liveAxis(ax, L, 0.05), 0.5, 'a smaller peak keeps the limit');
            tc.verifyEqual(ax.YLim, [-0.5 0.5]);
            tc.verifyEqual(tim.gui.liveAxis(ax, L, 0.6), 1, 'a larger peak raises it');
            tc.verifyEqual(ax.YAxis.TickLabelFormat, '%.1f');
            tc.verifyEqual(tim.gui.liveAxis(ax, [], 0.0012), 0.002, 'mPa range');
            tc.verifyEqual(double(ax.YAxis.Exponent), 0, 'no ×10^n label above the axes');
            tc.verifyEqual(ax.YAxis.TickLabelFormat, '%.3f');
            tc.verifyEqual(tim.gui.liveAxis(ax, [], 0), 1e-3, 'nothing yet');
        end

        function windowShowsTheStripForSteppedOnly(tc)
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
            % a swept sine: no strip
            h.exMode.Value = 'sweep'; feval(h.exMode.ValueChangedFcn, h.exMode, struct('PreviousValue', 'stepped'));
            feval(h.start.ButtonPushedFcn, h.start, []);
            tc.verifyEqual(char(h.axP.Visible), 'off', 'swept sine: no strip');
        end
    end
end
