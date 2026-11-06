function g = stepProgress(prog, prefix)
%STEPPROGRESS State of the progress strip of a stepped or swept sine (pure function).
%
%   g = tim.gui.stepProgress(prog)
%   g = tim.gui.stepProgress(prog, prefix)     prefix of the label, e.g. 'Load A (1 of 3) · '
%
%   prog is MeasurementSession.Progress (stepped sine 1.6.1, swept sine 1.6.3;
%   owner requests 2026-11-05): .kind 'stepped' | 'sweep', .passes (names,
%   e.g. {'Pre-measurement (−20 dB)', 'Measurement'}), .pass (index of the
%   running pass, 0 before the first), .rep / .nReps, .plan (stepped:
%   tim.app.steppedPlan of one repetition; sweep: .fStart, .fStop, .log,
%   .pre_s, .sweep_s, .post_s, .total_s), .fs, .n (samples received in the
%   running acquisition), .onSample (sample at which the output went on /
%   the sweep was triggered, NaN before), .state 'running' | 'processing' |
%   'done' | 'stopped'.
%
%   The time line of the action is every pass x every repetition, one
%   "group" of plan.total_s each (pre-roll, the steps or the sweep,
%   post-roll) in that order; processing between the passes is not part of
%   it. A step is one rectangle per part (settling, measured), its width the
%   planned time; a sweep is one rectangle.
%
%   g.T          planned length of the time line [s]
%   g.x          position of "now" on it [s] (0 .. T)
%   g.rect       (m x 2) start / end [s] of every rectangle
%   g.part       (m x 1) 1 settling, 2 measured (a sweep: 2)
%   g.step       (m x 1) step index;  g.group (m x 1) group index
%   g.pass       (m x 1) pass index of the rectangle
%   g.groups     (G x 2) start / end of every group [s]; g.groupName {G x 1}
%   g.k          running step (0: none; a sweep: 1 while it sweeps)
%   g.phase      'starting' | 'settling' | 'measuring' | 'sweeping' |
%                'finishing' | 'processing' | 'done' | 'stopped'
%   g.f          frequency now [Hz] (NaN when none)
%   g.state      prog.state
%   g.label      left text; g.right  right text (never empty: its line keeps
%                its place); g.status 'run' | 'ok' | 'fail' (colour of the label)
%   g.tickF      octave frequencies labelled in a group (125 … 4k Hz)
%   g.tickT      their times within a group [s];  g.tickLabel {1 x n}

if nargin < 2, prefix = ''; end
pl = prog.plan;
sweep = isfield(prog, 'kind') && strcmp(prog.kind, 'sweep');
nP = max(1, numel(prog.passes));
nR = max(1, prog.nReps);
G = nP * nR;
Tg = pl.total_s;
% ---- segments of one group: [start end part step], times within the group
if sweep
    seg = [pl.pre_s, pl.pre_s + pl.sweep_s, 2, 1];
    nS = 1;
    [tickF, tickT] = sweepTicks(pl);
else
    nS = numel(pl.freqs);
    s0 = pl.pre_s + [0, cumsum(pl.step_s(1:end - 1))];   % step starts within a group
    seg = zeros(2 * nS, 4);
    seg(1:2:end, :) = [s0.', (s0 + pl.settle_s).', ones(nS, 1), (1:nS).'];
    seg(2:2:end, :) = [(s0 + pl.settle_s).', (s0 + pl.step_s).', 2 * ones(nS, 1), (1:nS).'];
    [tickF, tickT] = steppedTicks(pl, s0);
end
g = struct('T', G * Tg, 'x', 0, 'rect', zeros(0, 2), 'part', zeros(0, 1), 'step', zeros(0, 1), ...
    'group', zeros(0, 1), 'pass', zeros(0, 1), 'groups', zeros(G, 2), 'groupName', {cell(G, 1)}, ...
    'k', 0, 'phase', 'starting', 'f', NaN, 'state', prog.state, 'label', '', 'right', '', 'status', 'run', ...
    'tickF', tickF, 'tickT', tickT, 'tickLabel', {arrayfun(@octaveName, tickF, 'UniformOutput', false)});
m = size(seg, 1);
rect = zeros(m * G, 2); part = zeros(m * G, 1); step = part; grp = part; pas = part;
for p = 1:nP
    for r = 1:nR
        q = (p - 1) * nR + r;
        t0 = (q - 1) * Tg;
        g.groups(q, :) = [t0, t0 + Tg];
        g.groupName{q} = groupName(prog.passes, p, r, nP, nR);
        i = (q - 1) * m + (1:m);
        rect(i, :) = t0 + seg(:, 1:2); part(i) = seg(:, 3); step(i) = seg(:, 4); grp(i) = q; pas(i) = p;
    end
end
g.rect = rect; g.part = part; g.step = step; g.group = grp; g.pass = pas;
% ---- position of "now"
p = min(max(prog.pass, 1), nP);
r = min(max(prog.rep, 1), nR);
q = (p - 1) * nR + r;
t0 = (q - 1) * Tg;
if prog.pass < 1
    xIn = 0;
elseif ~isfinite(prog.onSample)
    xIn = min(pl.pre_s, max(0, prog.n / prog.fs));       % pre-roll: the output is not on yet
else
    xIn = pl.pre_s + max(0, (prog.n - prog.onSample) / prog.fs);
end
xIn = min(xIn, Tg);
g.x = t0 + xIn;
% running step / sweep and phase
active = seg(end, 2);                                     % end of the steps / of the sweep
if prog.pass < 1 || xIn < pl.pre_s
    g.phase = 'starting';
elseif xIn >= active
    g.phase = 'finishing'; g.k = nS;
elseif sweep
    g.k = 1; g.phase = 'sweeping';
    u = (xIn - pl.pre_s) / pl.sweep_s;
    if pl.log, g.f = pl.fStart * (pl.fStop / pl.fStart)^u; else, g.f = pl.fStart + u * (pl.fStop - pl.fStart); end
else
    ks = find(xIn >= seg(1:2:end, 1), 1, 'last');
    g.k = ks; g.f = pl.freqs(ks);
    if xIn < seg(2 * ks - 1, 2), g.phase = 'settling'; else, g.phase = 'measuring'; end
end
switch prog.state
    case 'processing'
        g.phase = 'processing'; g.x = t0 + Tg;
    case 'done'
        g.phase = 'done'; g.x = g.T;
    case 'stopped'
        g.phase = 'stopped';
end
% ---- labels
pass = prog.passes{p};
rep = '';
if nR > 1, rep = sprintf(' · rep %d of %d', r, nR); end
switch g.phase
    case 'starting'
        g.label = sprintf('%s%s%s · starting', prefix, pass, rep);
    case {'settling', 'measuring'}
        g.label = sprintf('%s%s · step %d of %d · %s · %s%s', prefix, pass, g.k, nS, hz(g.f), g.phase, rep);
    case 'sweeping'
        g.label = sprintf('%s%s · %s · sweeping%s', prefix, pass, hz(g.f), rep);
    case 'finishing'
        if sweep
            g.label = sprintf('%s%s · sweep played%s', prefix, pass, rep);
        else
            g.label = sprintf('%s%s · %d steps played%s', prefix, pass, nS, rep);
        end
    case 'processing'
        g.label = sprintf('%s%s done · processing it', prefix, pass);
    case 'done'
        g.status = 'ok';
        if sweep
            what = sprintf('%d sweep%s', nR, plural(nR));
        else
            what = sprintf('%d steps', nS);
        end
        if nP > 1
            g.label = sprintf('%sDone · %s and %s · %.1f s', prefix, lower(firstWord(prog.passes{1})), what, g.T);
        else
            g.label = sprintf('%sDone · %s · %.1f s', prefix, what, g.T);
        end
    case 'stopped'
        g.status = 'fail';
        if sweep
            g.label = sprintf('%sStopped in %s%s', prefix, lower(pass), stoppedRep(r, nR));
        elseif g.k > 0
            g.label = sprintf('%sStopped at step %d of %d (%s%s)', prefix, g.k, nS, pass, rep);
        else
            g.label = sprintf('%sStopped (%s%s, before the first step)', prefix, pass, rep);
        end
end
switch g.phase
    case 'done'
        g.right = sprintf('%.1f s', g.T);
    case {'stopped', 'processing'}
        g.right = sprintf('%.1f s of %.1f s', g.x, g.T);
    otherwise
        g.right = sprintf('%.1f s of %.1f s · about %.0f s left', g.x, g.T, max(0, g.T - g.x));
end
end

function s = groupName(passes, p, r, nP, nR)
s = '';
if nP > 1, s = firstWord(passes{p}); end
if nR > 1
    if isempty(s), s = sprintf('rep %d', r); else, s = sprintf('%s %d', s, r); end
end
end

function w = firstWord(s)
w = strtok(char(s));
end

function s = plural(n)
if n == 1, s = ''; else, s = 's'; end
end

function s = stoppedRep(r, nR)
if nR > 1, s = sprintf(', repetition %d of %d', r, nR); else, s = ''; end
end

function s = hz(f)
if f >= 1000, s = sprintf('%.3g kHz', f / 1000); else, s = sprintf('%.0f Hz', f); end
end

function s = octaveName(f)
if f >= 1000, s = sprintf('%gk', f / 1000); else, s = sprintf('%g', f); end
end

function [tf, tt] = steppedTicks(pl, s0)
% the octave frequencies that have a step within 12 %, under the middle of that step
cand = [125 250 500 1000 2000 4000 8000];
tf = cand(arrayfun(@(c) any(abs(pl.freqs / c - 1) <= 0.12), cand));
tt = zeros(size(tf));
for i = 1:numel(tf)
    [~, k] = min(abs(pl.freqs - tf(i)));
    tt(i) = s0(k) + pl.step_s(k) / 2;
end
end

function [tf, tt] = sweepTicks(pl)
% the octave frequencies inside the sweep, at the time the sweep passes them
cand = [63 125 250 500 1000 2000 4000 8000 16000];
tf = cand(cand >= min(pl.fStart, pl.fStop) & cand <= max(pl.fStart, pl.fStop));
if pl.log
    u = log(tf / pl.fStart) / log(pl.fStop / pl.fStart);
else
    u = (tf - pl.fStart) / (pl.fStop - pl.fStart);
end
tt = pl.pre_s + u * pl.sweep_s;
end
