function [P, L] = calSwapPath(xa, xb, z0, zl, r, s)
%CALSWAPPATH Path of a microphone swap in the Calibration view: up, across, down.
%
%   [P, L] = tim.gui.calSwapPath(xa, xb, z0, zl, r)       % vertices, length
%   p      = tim.gui.calSwapPath(xa, xb, z0, zl, r, s)    % point(s) on the path
%
%   The path rises from (xa, z0) to the height zl, crosses to xb and goes down
%   to (xb, z0). Its two corners are circular fillets of radius r (quarter
%   arcs): the turning radius is bounded, the arcs stay inside their corner
%   (no overshoot, no loop), the straight parts lie on x = xa, z = zl and
%   x = xb, and two paths of the same span at different heights never cross.
%   r = 0 gives the sharp path of version 1.2.1 and earlier. The radius used
%   is min(r, |xb - xa|/2) (the two arcs meet in the middle of a narrow
%   swap), and never more than zl - z0.
%
%     xa, xb   x of the port the microphone leaves and of its new port [mm]
%     z0, zl   height of the two ends and of the crossing, zl >= z0 [mm]
%     r        corner radius [mm] (tim.gui.drawTube3D: M.swapRadius)
%     s        fraction(s) of the arc length; s <= 0 and s >= 1 give the exact
%              end points. The caller eases s (Tubebench: cosine ease in / out,
%              as with the sharp path).
%
%     P        vertices [x z], one row each: the straight parts and each arc in
%              16 segments (5.6 degrees per segment); no repeated vertex
%              (r = 0: the 4 corners; xa = xb: up and down the same column)
%     L        arc length of the path (exact, not of the polygon) [mm]
%     p        numel(s) x 2 points [x z] on the exact path (straight parts and
%              true circle arcs), evenly spaced in arc length for evenly
%              spaced s
%
%   Pure function, no graphics. Tubebench draws the dashed arrow of a move
%   with it (z0 = M.zHandle + 2) and animates the microphone (the translation:
%   z0 = 0, zl = M.lift(i)), both with the same radius M.swapRadius.

nArc = 16;                                         % segments per quarter arc
w = abs(xb - xa); sg = sign(xb - xa); h = zl - z0;
r = max(0, min([r, w / 2, h]));
% up, corner, across, corner, down
segL = [h - r, pi * r / 2, w - 2 * r, pi * r / 2, h - r];
L = sum(segL);
if nargin < 6
    % corner points: z = zl - r(1 - sin) and x = xb - r(1 - sin) are exact at
    % the ends of an arc (cospi / sinpi are exact at 0 and 1/2), so the
    % straight parts lie exactly on x = xa, z = zl and x = xb
    u = (0:nArc).' / (2 * nArc);                   % angle / pi, 0 .. 1/2
    cu = cospi(u); su = sinpi(u);
    a1 = [xa + sg * r * (1 - cu), zl - r * (1 - su)];   % from going up to going across
    a2 = [xb - sg * r * (1 - su), zl - r * (1 - cu)];   % from going across to going down
    P = [xa z0; a1; a2; xb z0];
    tol = 1e-9 * max([1, abs([xa xb z0 zl])]);
    P = P([true; any(abs(diff(P)) > tol, 2)], :);
    return
end
cum = cumsum(segL); start = [0, cum(1:4)];
P = zeros(numel(s), 2);
for j = 1:numel(s)
    if s(j) <= 0
        P(j, :) = [xa z0];
        continue
    elseif s(j) >= 1
        P(j, :) = [xb z0];
        continue
    end
    d = s(j) * L;
    k = find(d < cum, 1); if isempty(k), k = 5; end
    t = min(max(d - start(k), 0), segL(k));       % distance into part k
    switch k
        case 1                                     % up
            P(j, :) = [xa, z0 + t];
        case 2                                     % first corner
            f = t / r;
            P(j, :) = [xa + sg * r * (1 - cos(f)), zl - r * (1 - sin(f))];
        case 3                                     % across
            P(j, :) = [xa + sg * (r + t), zl];
        case 4                                     % second corner
            f = t / r;
            P(j, :) = [xb - sg * r * (1 - sin(f)), zl - r * (1 - cos(f))];
        otherwise                                  % down
            P(j, :) = [xb, zl - r - t];
    end
end
end
