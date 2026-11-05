function g = stepProgress(prog, prefix)
%STEPPROGRESS State of the stepped-sine progress strip (pure function, no graphics).
%
%   g = tim.gui.stepProgress(prog)
%   g = tim.gui.stepProgress(prog, prefix)     prefix of the label, e.g. 'Load A (1 of 3) · '
%
%   prog is MeasurementSession.Progress of a stepped sine (1.6.1, owner
%   request 2026-11-05): .passes (names, e.g. {'Pre-measurement (-20 dB)',
%   'Measurement'}), .pass (index of the running pass, 0 before the first),
%   .rep / .nReps, .plan (tim.app.steppedPlan of one repetition), .fs,
%   .n (samples received in the running acquisition), .onSample (sample at
%   which the output went on, NaN before), .state 'running' | 'processing'
%   | 'done' | 'stopped'.
%
%   The time line of the action is every pass x every repetition, one
%   "group" of plan.total_s each (pre-roll, the steps, post-roll) in that
%   order; processing between the passes is not part of it. Every step is
%   one rectangle per part (settling, measuring), its width the planned
%   time, so the strip shows where the time goes (long steps at low
%   frequencies).
%
%   g.T          planned length of the time line [s]
%   g.x          position of "now" on it [s] (0 .. T)
%   g.rect       (m x 2) start / end [s] of every rectangle
%   g.part       (m x 1) 1 settling, 2 measuring
%   g.step       (m x 1) step index;  g.group (m x 1) group index
%   g.pass       (m x 1) pass index of the rectangle
%   g.groups     (G x 2) start / end of every group [s]; g.groupName {G x 1}
%   g.k          running step (0: none); g.phase 'starting' | 'settling' |
%                'measuring' | 'finishing' | 'processing' | 'done' | 'stopped'
%   g.state      prog.state
%   g.label      left text; g.right  right text (time); g.status 'run' |
%                'ok' | 'fail' (colour of the label)
%   g.tickF      (1 x n) frequencies [Hz] labelled under the steps of a group
%                (125, 250, 500, 1k, 2k, 4k where a step lies within 12 %)

if nargin < 2, prefix = ''; end
pl = prog.plan;
nS = numel(pl.freqs);
nP = max(1, numel(prog.passes));
nR = max(1, prog.nReps);
G = nP * nR;
Tg = pl.total_s;
g = struct('T', G * Tg, 'x', 0, 'rect', zeros(0, 2), 'part', zeros(0, 1), 'step', zeros(0, 1), ...
    'group', zeros(0, 1), 'pass', zeros(0, 1), 'groups', zeros(G, 2), 'groupName', {cell(G, 1)}, ...
    'k', 0, 'phase', 'starting', 'state', prog.state, 'label', '', 'right', '', 'status', 'run', ...
    'tickF', tickFrequencies(pl.freqs));
% ---- rectangles of every group
s0 = pl.pre_s + [0, cumsum(pl.step_s(1:end - 1))];      % step starts within a group
rect = zeros(2 * nS * G, 2); part = zeros(2 * nS * G, 1); step = part; grp = part; pas = part;
i = 0;
for p = 1:nP
    for r = 1:nR
        q = (p - 1) * nR + r;
        t0 = (q - 1) * Tg;
        g.groups(q, :) = [t0, t0 + Tg];
        g.groupName{q} = groupName(prog.passes, p, r, nP, nR);
        for k = 1:nS
            a = t0 + s0(k);
            i = i + 1; rect(i, :) = [a, a + pl.settle_s(k)]; part(i) = 1; step(i) = k; grp(i) = q; pas(i) = p;
            i = i + 1; rect(i, :) = [a + pl.settle_s(k), a + pl.step_s(k)]; part(i) = 2; step(i) = k; grp(i) = q; pas(i) = p;
        end
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
% running step and phase
ks = find(xIn >= s0, 1, 'last');
if prog.pass < 1 || xIn < pl.pre_s
    g.phase = 'starting';
elseif xIn >= pl.pre_s + sum(pl.step_s)
    g.phase = 'finishing'; g.k = nS;
else
    g.k = ks;
    if xIn < s0(ks) + pl.settle_s(ks), g.phase = 'settling'; else, g.phase = 'measuring'; end
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
        g.label = sprintf('%s%s · step %d of %d · %s · %s%s', prefix, pass, g.k, nS, hz(pl.freqs(g.k)), g.phase, rep);
    case 'finishing'
        g.label = sprintf('%s%s · %d steps played%s', prefix, pass, nS, rep);
    case 'processing'
        g.label = sprintf('%s%s done · processing it', prefix, pass);
    case 'done'
        g.status = 'ok';
        if nP > 1
            g.label = sprintf('%sDone · %s and %d steps · %.1f s', prefix, lower(firstWord(prog.passes{1})), nS, g.T);
        else
            g.label = sprintf('%sDone · %d steps · %.1f s', prefix, nS, g.T);
        end
    case 'stopped'
        g.status = 'fail';
        if g.k > 0
            g.label = sprintf('%sStopped at step %d of %d (%s%s)', prefix, g.k, nS, pass, rep);
        else
            g.label = sprintf('%sStopped (%s%s, before the first step)', prefix, pass, rep);
        end
end
switch g.phase
    case {'done'}
        g.right = '';
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

function s = hz(f)
if f >= 1000, s = sprintf('%.3g kHz', f / 1000); else, s = sprintf('%.0f Hz', f); end
end

function tf = tickFrequencies(f)
% the octave frequencies that have a step within 12 %
cand = [125 250 500 1000 2000 4000 8000];
tf = cand(arrayfun(@(c) any(abs(f / c - 1) <= 0.12), cand));
end
