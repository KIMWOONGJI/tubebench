function drawTube3D(ax, geom, drawing, mapping)
%DRAWTUBE3D Simplified, dimension-driven 3D model of the impedance tube.
%
%   tim.gui.drawTube3D(ax, geom, drawing)
%   tim.gui.drawTube3D(ax, geom, drawing, mapping)   % mapping(c) = port of channel c
%
%   Built from primitives (cylinders, discs) so it follows the entered
%   dimensions immediately: geom (s1, L1, d, L2, s2 as coordinates, bore
%   diameter) and drawing (outer diameter, tube lengths, loudspeaker housing,
%   absorber). x = tube axis (x = 0 at the specimen front face), z = up.
%   The mouse can rotate / zoom (axes toolbar).

if nargin < 4 || isempty(mapping), mapping = 1:4; end
P = tim.gui.palette();
cla(ax); hold(ax, 'on');
rb = 1e3 * geom.diameter / 2;
ro = 1e3 * drawing.outerDiameter / 2;
known = all(isfinite(geom.micPositions)) && isfinite(geom.xFront) && isfinite(geom.xRear);
if known
    x = 1e3 * geom.micPositions; xF = 1e3 * geom.xFront; xR = 1e3 * geom.xRear;
else                                          % schematic placement until L1, d, L2 are entered
    s1 = 1e3 * geom.spacingUp; s2 = 1e3 * geom.spacingDown;
    xF = 0; xR = 40; x = [-40 - s1, -40, xR + 40, xR + 40 + s2];
end
xStart = x(1) - 1e3 * drawing.upstreamLength;          % loudspeaker end of the bore
xEnd = x(4) + 1e3 * drawing.downstreamLength;          % termination face
nSeg = 64;

% tube: outer shell (transparent) and bore
cyl(ax, xStart, xEnd, ro, [0.80 0.82 0.86], 0.25, nSeg);
cyl(ax, xStart, xEnd, rb, [0.70 0.74 0.80], 0.22, nSeg);
ring(ax, xStart, rb, ro, [0.6 0.62 0.66], 0.5);
% loudspeaker housing (large end)
rh = 1e3 * drawing.speakerHousingDiameter / 2; lh = 1e3 * drawing.speakerHousingLength;
cyl(ax, xStart - lh, xStart, rh, [0.45 0.45 0.48], 0.55, nSeg);
disc(ax, xStart - lh, rh, [0.35 0.35 0.38], 0.8);
ring(ax, xStart, ro, rh, [0.45 0.45 0.48], 0.6);
cone(ax, xStart - 0.8 * lh, xStart - 0.15 * lh, 0.8 * rh, rb, [0.2 0.2 0.2], 0.55, nSeg);
text(ax, xStart - lh / 2, 0, rh + 12, 'loudspeaker', 'HorizontalAlignment', 'center', 'FontSize', 11);
% termination (small end) and absorber
disc(ax, xEnd, ro, [0.25 0.25 0.25], 0.9);
la = 1e3 * drawing.absorberLength;
if isscalar(la) && isfinite(la) && la > 0
    cyl(ax, xEnd - la, xEnd, rb * 0.98, [0.55 0.75 0.55], 0.55, nSeg);
    disc(ax, xEnd - la, rb * 0.98, [0.55 0.75 0.55], 0.6);
    lab = sprintf('absorber %g mm', la);
else
    lab = 'absorber side';
end
text(ax, xEnd, 0, ro + 14, lab, 'HorizontalAlignment', 'center', 'FontSize', 11);
% specimen
if xR - xF > 0.5
    cyl(ax, xF, xR, rb * 0.995, [0.85 0.70 0.40], 0.85, nSeg);
    disc(ax, xF, rb * 0.995, [0.80 0.62 0.30], 0.9); disc(ax, xR, rb * 0.995, [0.80 0.62 0.30], 0.9);
else
    disc(ax, xF, rb, [0.80 0.62 0.30], 0.9);
end
text(ax, (xF + xR) / 2, 0, -ro - 14, sprintf('specimen  d = %g mm', round(xR - xF, 3)), ...
    'HorizontalAlignment', 'center', 'FontSize', 11);
% microphones on the ports (vertical, +z), coloured by the DAQ channel in that port
rp = 1e3 * drawing.portDiameter / 2; lm = 1e3 * drawing.micLength;
for port = 1:4
    c = find(mapping == port, 1);
    col = [0.5 0.5 0.5]; lbl = sprintf('M%d', port);
    if ~isempty(c), col = P.ch(c, :); end
    vcyl(ax, x(port), max(rp, 3.5), ro - 1, ro + lm, col, nSeg / 2);
    if ~isempty(c), lbl = {sprintf('M%d', port), sprintf('ch%d', c)}; end
    text(ax, x(port), 0, ro + lm + 6, lbl, 'HorizontalAlignment', 'center', ...
        'VerticalAlignment', 'bottom', 'FontSize', 11, 'FontWeight', 'bold', 'Color', col);
end
hold(ax, 'off');
axis(ax, 'equal');
ax.XLim = [xStart - lh - 20, xEnd + 25]; ax.YLim = [-rh - 10, rh + 10]; ax.ZLim = [-rh - 10, ro + lm + 30];
ax.Visible = 'off'; ax.Title.Visible = 'on';            % no axis box: the model speaks for itself
view(ax, [-28 18]);
camlight(ax, 'headlight'); lighting(ax, 'gouraud');
if known
    title(ax, '3D model from the entered dimensions (rotate with the mouse)', 'FontWeight', 'normal');
else
    title(ax, '3D model - schematic until L1, d and L2 are entered (rotate with the mouse)', 'FontWeight', 'normal');
end
end

% ---------------------------------------------------------------- primitives
function cyl(ax, x0, x1, r, col, alpha, n)
[Y, Z, X] = cylinder(r, n);                   % axis along x
X = x0 + X * (x1 - x0);
surf(ax, X, Y, Z, 'FaceColor', col, 'EdgeColor', 'none', 'FaceAlpha', alpha, 'FaceLighting', 'gouraud');
end

function cone(ax, x0, x1, r0, r1, col, alpha, n)
[Y, Z, X] = cylinder([r0 r1], n);
X = x0 + X * (x1 - x0);
surf(ax, X, Y, Z, 'FaceColor', col, 'EdgeColor', 'none', 'FaceAlpha', alpha);
end

function vcyl(ax, xc, r, z0, z1, col, n)
[X, Y, Z] = cylinder(r, n);                   % vertical cylinder at x = xc
X = X + xc; Z = z0 + Z * (z1 - z0);
surf(ax, X, Y, Z, 'FaceColor', col, 'EdgeColor', 'none', 'FaceLighting', 'gouraud');
t = linspace(0, 2 * pi, n + 1);
patch(ax, xc + r * cos(t), r * sin(t), z1 * ones(size(t)), col, 'EdgeColor', 'none');
end

function disc(ax, x0, r, col, alpha)
t = linspace(0, 2 * pi, 65);
patch(ax, x0 * ones(size(t)), r * cos(t), r * sin(t), col, 'EdgeColor', 'none', 'FaceAlpha', alpha);
end

function ring(ax, x0, r0, r1, col, alpha)
t = linspace(0, 2 * pi, 65);
Y = [r0 * cos(t); r1 * cos(t)]; Z = [r0 * sin(t); r1 * sin(t)];
surf(ax, x0 * ones(size(Y)), Y, Z, 'FaceColor', col, 'EdgeColor', 'none', 'FaceAlpha', alpha);
end
