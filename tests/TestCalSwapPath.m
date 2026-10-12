classdef TestCalSwapPath < matlab.unittest.TestCase
    %TESTCALSWAPPATH Rounded swap paths of the Calibration view
    %   (tim.gui.calSwapPath, owner request 2026-10-12): up, across, down with
    %   circular fillets of radius min(r, |xb - xa|/2). r = 0 is the sharp
    %   path of 1.2.1; the arcs are smooth (turning <= 6 degrees per segment),
    %   stay inside the corner, keep the straight parts on xa, zl and xb with
    %   a straight end for the arrowhead, and two paths of the same span never
    %   cross. Pure numbers, no window.

    properties (Constant)
        % lab tube (drawTube3D): dashed path 72.5 mm high from the plug top + 2 mm,
        % animation 74.5 mm (lift(1)), corner radius 11.6 mm, ports 29 mm apart
        Lab = struct('xa', -70, 'xb', -41, 'h', 72.5, 'lift', 74.5, 'r', 11.6)
    end

    methods (Test)
        function sharpPathOfVersion121(tc)
            % (a) r = 0: the vertices and the points are those of the old
            % local calPath of Tubebench (copied below), to 1e-12
            s = 0:0.005:1;
            for c = {[-70 -41 0 74.5], [116 -70 10 84.5], [145 116 92.85 167.35], [0 1000 0 150], [3 3 0 20]}
                [xa, xb, z0, zl] = deal(c{1}(1), c{1}(2), c{1}(3), c{1}(4));
                P = tim.gui.calSwapPath(xa, xb, z0, zl, 0);
                V = [xa z0; xa zl; xb zl; xb z0];
                V = V([true; any(diff(V) ~= 0, 2)], :);           % xa = xb: up and down the same column
                tc.verifyEqual(P, V, 'AbsTol', 1e-12, mat2str(c{1}));
                p = tim.gui.calSwapPath(xa, xb, z0, zl, 0, s);
                q = zeros(numel(s), 2);
                for j = 1:numel(s), [q(j, 1), q(j, 2)] = oldCalPath(s(j), xa, xb, z0, zl); end
                tc.verifyEqual(p, q, 'AbsTol', 1e-12, mat2str(c{1}));
                [~, L] = tim.gui.calSwapPath(xa, xb, z0, zl, 0);
                tc.verifyEqual(L, 2 * (zl - z0) + abs(xb - xa), 'AbsTol', 1e-12);
            end
        end

        function exactEndPoints(tc)
            % (b) both directions, also outside 0..1 and with r limited by the width
            for c = {[-70 -41], [-41 -70], [116 145 + 1e-9], [0 7.2], [7.2 0]}
                xa = c{1}(1); xb = c{1}(2);
                for r = [0 0.5 11.6 100]
                    p = tim.gui.calSwapPath(xa, xb, 92.85, 165.35, r, [-0.5 0 1 1.5]);
                    tc.verifyEqual(p, [xa 92.85; xa 92.85; xb 92.85; xb 92.85], sprintf('%g -> %g, r %g', xa, xb, r));
                    P = tim.gui.calSwapPath(xa, xb, 92.85, 165.35, r);
                    tc.verifyEqual(P([1 end], :), [xa 92.85; xb 92.85]);
                end
            end
        end

        function continuousAndEvenlySpaced(tc)
            % (c) evenly spaced s gives points evenly spaced along the path;
            % no jump where a straight part meets an arc
            for c = {[-70 -41 0 74.5 11.6], [145 -70 0 94.5 11.6], [0 20 0 40 10], [0 1000 5 105 30]}
                [xa, xb, z0, zl, r] = deal(c{1}(1), c{1}(2), c{1}(3), c{1}(4), c{1}(5));
                [~, L] = tim.gui.calSwapPath(xa, xb, z0, zl, r);
                ru = min(r, abs(xb - xa) / 2);
                tc.verifyEqual(L, 2 * (zl - z0) + abs(xb - xa) - (4 - pi) * ru, 'RelTol', 1e-12, 'exact arc length');
                n = 2000; p = tim.gui.calSwapPath(xa, xb, z0, zl, r, (0:n) / n);
                d = sqrt(sum(diff(p) .^ 2, 2));
                tc.verifyLessThanOrEqual(max(d), L / n * (1 + 1e-9), mat2str(c{1}));
                tc.verifyGreaterThan(min(d), L / n * (1 - 1e-3), mat2str(c{1}));   % chord of an arc: slightly shorter
                % at the joints between the parts
                h = zl - z0; w = abs(xb - xa);
                joints = cumsum([h - ru, pi * ru / 2, w - 2 * ru, pi * ru / 2]) / L;
                e = 1e-9;
                for sj = joints
                    pp = tim.gui.calSwapPath(xa, xb, z0, zl, r, [sj - e, sj + e]);
                    tc.verifyLessThanOrEqual(norm(diff(pp)), 2 * e * L + 1e-9, sprintf('joint at s = %.4f', sj));
                end
                % the polygon of the vertices follows the arc (16 segments per quarter)
                P = tim.gui.calSwapPath(xa, xb, z0, zl, r);
                tc.verifyEqual(sum(sqrt(sum(diff(P) .^ 2, 2))), L, 'RelTol', 1e-3);
            end
        end

        function smoothTurning(tc)
            % (d) at most 6 degrees between consecutive segments of the
            % vertices (5.6 degrees per arc segment); points spaced ds along
            % the path turn by at most ds/r. The radius through three
            % consecutive vertices or points is never below r (no sharper
            % bend than the fillet).
            for c = {[-70 -41 0 74.5 11.6], [-70 -41 92.85 165.35 11.6], [145 -70 0 94.5 11.6], ...
                    [0 20 0 40 10], [0 7.2 0 74.5 11.6], [0 1000 5 105 30], [0 29 0 30 0.5]}
                [xa, xb, z0, zl, r] = deal(c{1}(1), c{1}(2), c{1}(3), c{1}(4), c{1}(5));
                ru = min(r, abs(xb - xa) / 2);
                [P, L] = tim.gui.calSwapPath(xa, xb, z0, zl, r);
                n = 1000; p = tim.gui.calSwapPath(xa, xb, z0, zl, r, (0:n) / n);
                tc.verifyLessThanOrEqual(max(turning(P)), 6, mat2str(c{1}));
                tc.verifyLessThanOrEqual(max(turning(p)), rad2deg(L / n / ru) * (1 + 1e-6), mat2str(c{1}));
                for Q = {P, p}
                    tc.verifyGreaterThanOrEqual(min(circumradius(Q{1})), ru * (1 - 1e-6), mat2str(c{1}));
                end
                % the arc vertices lie on the fillet circles
                sg = sign(xb - xa);
                k = P(:, 2) > zl - ru & P(:, 2) < zl;                 % strictly inside the corners
                c1 = [xa + sg * ru, zl - ru]; c2 = [xb - sg * ru, zl - ru];
                dist = min(hypot(P(k, 1) - c1(1), P(k, 2) - c1(2)), hypot(P(k, 1) - c2(1), P(k, 2) - c2(2)));
                tc.verifyEqual(dist, ru * ones(nnz(k), 1), 'AbsTol', 1e-9);
            end
            % the sharp path turns by 90 degrees (checks the check)
            tc.verifyEqual(max(turning(tim.gui.calSwapPath(0, 29, 0, 74.5, 0))), 90, 'AbsTol', 1e-9);
        end

        function insideTheSharpPath(tc)
            % (e) no overshoot: every point in the box of the sharp path, x
            % monotone towards the new port, z rising then falling (no loop)
            for c = {[-70 -41 0 74.5 11.6], [145 -70 0 94.5 11.6], [0 7.2 0 74.5 11.6], [0 1000 5 105 30], ...
                    [3 3 0 20 11.6], [0 29 0 30 100]}
                [xa, xb, z0, zl, r] = deal(c{1}(1), c{1}(2), c{1}(3), c{1}(4), c{1}(5));
                sg = sign(xb - xa); tol = 1e-9;
                P = tim.gui.calSwapPath(xa, xb, z0, zl, r);
                p = tim.gui.calSwapPath(xa, xb, z0, zl, r, (0:0.002:1).');
                for Q = {P, p}
                    q = Q{1};
                    tc.verifyGreaterThanOrEqual(q(:, 1), min(xa, xb) - tol); tc.verifyLessThanOrEqual(q(:, 1), max(xa, xb) + tol);
                    tc.verifyGreaterThanOrEqual(q(:, 2), z0 - tol); tc.verifyLessThanOrEqual(q(:, 2), zl + tol);
                    if sg ~= 0, tc.verifyGreaterThanOrEqual(sg * diff(q(:, 1)), -tol, 'x monotone'); end
                    [~, m] = max(q(:, 2));
                    tc.verifyGreaterThanOrEqual(diff(q(1:m, 2)), -tol, 'z rises ...');
                    tc.verifyLessThanOrEqual(diff(q(m:end, 2)), tol, '... then falls');
                end
            end
        end

        function straightPartsAndArrowShank(tc)
            % (f) the straight parts lie exactly on x = xa, z = zl and x = xb;
            % with the radius of drawTube3D the end is straight for >= 8 mm
            % (6 mm arrowhead + 2 mm shank)
            for c = {[-70 -41 92.85 165.35 11.6], [145 -70 0 94.5 11.6], [0 1000 5 105 30]}
                [xa, xb, z0, zl, r] = deal(c{1}(1), c{1}(2), c{1}(3), c{1}(4), c{1}(5));
                P = tim.gui.calSwapPath(xa, xb, z0, zl, r);
                tc.verifyNumElements(P, 2 * (2 + 2 * 17));
                tc.verifyEqual(P(1:2, 1), [xa; xa]); tc.verifyEqual(P(2, 2), zl - r);
                tc.verifyEqual(P(18:19, 2), [zl; zl]);                   % across
                tc.verifyEqual(P(end - 1:end, 1), [xb; xb]); tc.verifyEqual(P(end - 1, 2), zl - r);
                % the points of the straight parts (away from the joints)
                [~, L] = tim.gui.calSwapPath(xa, xb, z0, zl, r);
                h = zl - z0; w = abs(xb - xa);
                b = cumsum([h - r, pi * r / 2, w - 2 * r, pi * r / 2]) / L;
                s = (0:0.001:1).'; p = tim.gui.calSwapPath(xa, xb, z0, zl, r, s);
                e = 1e-9;
                k = s < b(1) - e; tc.verifyEqual(p(k, 1), xa * ones(nnz(k), 1));
                k = s > b(2) + e & s < b(3) - e; tc.verifyEqual(p(k, 2), zl * ones(nnz(k), 1));
                tc.verifyNotEmpty(find(k, 1));
                k = s > b(4) + e; tc.verifyEqual(p(k, 1), xb * ones(nnz(k), 1));
            end
            % straight end of the dashed arrow: r = min(h/3, h - 8) as in drawTube3D
            for h = [12 20 30 72.5 102.5 200]
                r = max(0, min(h / 3, h - 8));
                P = tim.gui.calSwapPath(0, 29, 0, h, r);
                tc.verifyEqual(P(end - 1:end, 1), [29; 29]);
                tc.verifyGreaterThanOrEqual(P(end - 1, 2) - P(end, 2), 8 - 1e-12, sprintf('h = %g', h));
            end
            % the lab tube (radius 11.6 mm, dashed path 72.5 mm high)
            P = tim.gui.calSwapPath(tc.Lab.xa, tc.Lab.xb, 0, tc.Lab.h, tc.Lab.r);
            tc.verifyEqual(P(end - 1, 2) - P(end, 2), 72.5 - 11.6, 'AbsTol', 1e-12);
        end

        function widthTimesRadiusTable(tc)
            % (g) the radius used is min(r, width/2), never NaN; the vertices
            % count 4 / 3 (sharp) or 36 / 35 (arcs that meet)
            z0 = 10; zl = 160;                                       % 150 mm high: the width limits r
            for w = [0 1 7.2 29 215 1000]
                for r = [0 0.5 11.6 100]
                    for dirn = [1 -1]
                        xa = 40; xb = xa + dirn * w;
                        id = sprintf('w %g, r %g, direction %+d', w, r, dirn);
                        [P, L] = tim.gui.calSwapPath(xa, xb, z0, zl, r);
                        p = tim.gui.calSwapPath(xa, xb, z0, zl, r, linspace(0, 1, 301));
                        tc.verifyFalse(any(isnan([P(:); L; p(:)])), id);
                        ru = min(r, w / 2);
                        tc.verifyEqual(L, 2 * (zl - z0) + w - (4 - pi) * ru, 'AbsTol', 1e-9, id);
                        if ru == 0
                            n = 4 - (w == 0);
                        else
                            n = 36 - (ru == w / 2);
                            % the first arc: centre (xa + sg*ru, zl - ru), radius ru
                            a = P(2:18, :); sg = sign(xb - xa);
                            tc.verifyEqual(hypot(a(:, 1) - xa - sg * ru, a(:, 2) - zl + ru), ru * ones(17, 1), ...
                                'AbsTol', 1e-9, id);
                        end
                        tc.verifySize(P, [n 2], id);
                        tc.verifyEqual(max(P(:, 2)), zl, id);
                        tc.verifyEqual(p([1 end], :), [xa z0; xb z0], id);
                    end
                end
            end
            % (outside the design range) a radius above the height is limited to it
            [~, L] = tim.gui.calSwapPath(0, 1000, 0, 50, 100);
            tc.verifyEqual(L, 2 * 50 + 1000 - (4 - pi) * 50, 'AbsTol', 1e-9);
            P = tim.gui.calSwapPath(0, 1000, 0, 50, 100);
            tc.verifyGreaterThanOrEqual(min(P(:, 2)), 0);
        end

        function pathsOfOneSpanNeverCross(tc)
            % (h) two paths over the same span, 10 mm apart in height (the
            % lifts of two movers), in the same or in opposite directions:
            % the higher one is 10 mm above the lower one everywhere between
            % the ports - they share only the vertical parts at the ports
            for c = {[-70 -41 11.6], [-41 116 11.6], [0 7.2 11.6], [0 1000 24.2], [0 29 0]}
                [xa, xb, r] = deal(c{1}(1), c{1}(2), c{1}(3));
                A = tim.gui.calSwapPath(xa, xb, 0, 74.5, r);
                xq = linspace(min(xa, xb), max(xa, xb), 503); xq = xq(2:end - 1);
                zA = across(A, xq);
                for B = {tim.gui.calSwapPath(xa, xb, 0, 84.5, r), tim.gui.calSwapPath(xb, xa, 0, 84.5, r)}
                    tc.verifyEqual(across(B{1}, xq) - zA, 10 * ones(size(xq)), 'AbsTol', 1e-9, mat2str(c{1}));
                end
            end
        end
    end
end

% ---------------------------------------------------------------- helpers
function [x, y] = oldCalPath(s, xa, xb, y0, yl)
% the local calPath of Tubebench 1.2.1 (sharp corners), unchanged
up = yl - y0; across = abs(xb - xa); d = s * (2 * up + across);
if d < up
    x = xa; y = y0 + d;
elseif d < up + across
    x = xa + sign(xb - xa) * (d - up); y = yl;
else
    x = xb; y = yl - (d - up - across);
end
end

function a = turning(P)
% angle [deg] between consecutive segments of the polygon P (zero-length
% segments skipped)
d = diff(P); d = d(any(d ~= 0, 2), :);
a = zeros(0, 1);
for i = 1:size(d, 1) - 1
    u = d(i, :); v = d(i + 1, :);
    a(end + 1, 1) = atan2d(abs(u(1) * v(2) - u(2) * v(1)), u * v.'); %#ok<AGROW>
end
end

function R = circumradius(P)
% radius of the circle through each three consecutive points (Inf if collinear)
R = inf(size(P, 1) - 2, 1);
for i = 1:size(P, 1) - 2
    a = P(i, :); b = P(i + 1, :); c = P(i + 2, :);
    u = b - a; v = c - a; ar = abs(u(1) * v(2) - u(2) * v(1)) / 2;
    if ar > 1e-12 * norm(u) * norm(v)
        R(i) = norm(b - a) * norm(c - b) * norm(c - a) / (4 * ar);
    end
end
end

function z = across(P, xq)
% height of the path P over x strictly between its ports (its part between
% the two vertical parts is a graph z(x))
k = P(:, 1) ~= P(1, 1) & P(:, 1) ~= P(end, 1);
k(find(k, 1) - 1) = true; k(find(k, 1, 'last') + 1) = true;   % the ends of the vertical parts
if ~any(k), k(2:end - 1) = true; end                          % sharp path: its two upper corners
x = P(k, 1); zz = P(k, 2);
[x, i] = sort(x); z = interp1(x, zz(i), xq);
end
