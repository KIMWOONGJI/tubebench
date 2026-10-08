function drawTube3D(ax, geom, drawing, mapping, opts)
%DRAWTUBE3D Dimension-driven 3D model of the impedance tube.
%
%   tim.gui.drawTube3D(ax, geom, drawing)
%   tim.gui.drawTube3D(ax, geom, drawing, mapping, opts)
%   tim.gui.drawTube3D(ax, 'view', name)       % only change the view
%
%     geom      cfg.geometry (bore diameter, port and specimen positions [m])
%     drawing   cfg.tubeDrawing (parts of the lab CAD assembly, drawing only)
%     mapping   mapping(c) = port of DAQ channel c (default 1:4)
%     opts.section     true (default): half section - the half towards the
%                      viewer is removed, cut faces are hatched; the bore,
%                      the specimen and the microphone tips are visible
%     opts.dimensions  true (default): dimension lines s1, L1, d, L2, s2
%                      (black) and the overall lengths (grey)
%     opts.view        'keep' (default: keep the user's rotation), or
%                      'default' | 'side' | 'perspective' | 'top' | [az el]
%
%   x = tube axis (x = 0 at the specimen FRONT face, increasing towards the
%   termination), z = up (microphones), y = depth (side view seen from -y).
%   Positions follow the entered geometry immediately; part sizes come
%   from cfg.tubeDrawing (CAD assembly Assy_SIT). Microphones, holders and
%   bolts are drawn whole (not sectioned), as in a technical drawing.
%   Nothing drawn here is used by the analysis.

if ischar(geom) && strcmp(geom, 'view')
    setView(ax, drawing); return
end
if nargin < 4 || isempty(mapping), mapping = 1:4; end
if nargin < 5, opts = struct(); end
opts = fillOpts(opts);
P = tim.gui.palette();
td = drawing;
mm = @(v) 1e3 * v;

% ---------------------------------------------------------------- positions [mm]
known = all(isfinite(geom.micPositions)) && isfinite(geom.xFront) && isfinite(geom.xRear);
s1 = mm(geom.spacingUp); s2 = mm(geom.spacingDown);
if known
    x = mm(geom.micPositions); xF = mm(geom.xFront); xR = mm(geom.xRear);
else                                   % schematic until L1, d and L2 are entered
    xF = 0; xR = 40; x = [-40 - s1, -40, xR + 40, xR + 40 + s2];
end
rb = mm(geom.diameter) / 2;                       % bore
rB = max(mm(td.bodyDiameter) / 2, rb + 4);        % measurement tube body
ro = max(mm(td.outerDiameter) / 2, rB + 4);       % flanges, specimen section, extension
tf = mm(td.flangeThickness);
xS = x(1) - mm(td.upstreamLength);                % loudspeaker end of the bore
xJ = x(4) + mm(td.downstreamTubeEnd);             % downstream tube | extension
xT = x(4) + mm(td.downstreamLength);              % termination face (end cap)
tc = mm(td.endCapThickness);
rH = mm(td.speakerHousingDiameter) / 2; lH = mm(td.speakerHousingLength);
rSF = min(mm(td.speakerFlangeDiameter) / 2, rH - 2); tSF = mm(td.speakerFlangeThickness);
rCav = min(mm(td.speakerCavityDiameter) / 2, rSF - 4);
xH0 = xS + tSF - lH;                              % back of the loudspeaker housing
rHo = mm(td.holderDiameter) / 2; hHo = mm(td.holderHeight);
rM = mm(td.micDiameter) / 2; lM = mm(td.micLength); zTip = rb + mm(td.micRecess);
rbc = mm(td.boltCircleDiameter) / 2;

% ---------------------------------------------------------------- scene
keepView = strcmp(opts.view, 'keep') && isstruct(ax.UserData) && isfield(ax.UserData, 'tube3D');
oldView = ax.View;
cla(ax); hold(ax, 'on');
S = struct('ax', ax, 'section', opts.section, 'hatch', zeros(0, 3), 'edges', zeros(0, 3));
if opts.section, S.phi = [-pi / 2, pi / 2]; else, S.phi = [0, 2 * pi]; end
metal = [0.80 0.82 0.85];
portGaps = [x(:) - rHo * 0.75, x(:) + rHo * 0.75];  % holder spigots replace the wall here

% upstream tube: flange in the loudspeaker housing, body, joint flange
S = shell(S, xS, xS + tSF, rb, rSF, metal, [], 'tube');
S = shell(S, xS + tSF, xF - tf, rb, rB, metal, portGaps(1:2, :), 'tube');
S = shell(S, max(xF - tf, xS + tSF), xF, rb, ro, metal, [], 'tube');
% specimen section (the specimen fills it) and the specimen
if xR - xF >= 1
    S = shell(S, xF, xR, rb, ro, metal, [], 'specimenSection');
    S = solid(S, xF, xR, rb - 0.05, porous([0.86 0.70 0.42]), 'specimen');
else                                              % thin screen between two flanges
    S = solid(S, xF - 0.4, xF + 0.4, rb, porous([0.86 0.70 0.42]), 'specimen');
end
% downstream tube: joint flanges and body; extension; end cap
S = shell(S, xR, xR + tf, rb, ro, metal, [], 'tube');
S = shell(S, xR + tf, xJ - tf, rb, rB, metal, portGaps(3:4, :), 'tube');
S = shell(S, max(xJ - tf, xR + tf), xJ, rb, ro, metal, [], 'tube');
S = shell(S, xJ, xT, rb, ro, metal, [], 'tube');
S = solid(S, xT, xT + tc, ro, metal, 'endCap');
annulus(S, xT - 0.05, 0, rb, [0.55 0.57 0.60], 'termination');   % termination face
la = mm(td.absorberLength);
if isscalar(la) && isfinite(la) && la > 0
    S = solid(S, xT - la, xT - 0.1, rb - 0.1, porous([0.55 0.72 0.52]), 'absorber');
end
% loudspeaker housing (large end) with the loudspeaker (schematic)
S = solid(S, xH0, xH0 + 5, rH, [0.42 0.43 0.46], 'housing');
S = shell(S, xH0 + 5, xS, rCav, rH, [0.42 0.43 0.46], [], 'housing');
S = shell(S, xS, xS + tSF, rSF, rH, [0.42 0.43 0.46], [], 'housing');
loudspeaker(S, xS, rCav);
% bolts: 6 x M4 per joint (heads in counterbores), 4 on the housing front
ang = (0:5) * pi / 3;
bolts(S, xF - tf, -1, rbc, ang); bolts(S, xR + tf, +1, rbc, ang);
bolts(S, xJ - tf, -1, rbc, ang); bolts(S, xT + tc, +1, rbc, ang);
housingBolts(S, xS + tSF, (rSF + rH) / 2 - 2.5, (0:3) * pi / 2);
% microphone holders, microphones (coloured by the DAQ channel in the port), cables
zTop = 0;
for p = 1:4
    c = find(mapping == p, 1);
    col = [0.5 0.5 0.5]; lbl = sprintf('M%d', p);
    if ~isempty(c), col = P.ch(c, :); lbl = {sprintf('M%d', p), sprintf('ch%d', c)}; end
    S = holder(S, x(p), rb, rB, rHo, hHo, rM, metal);
    zc = microphone(S, x(p), rM, zTip, lM, col, sprintf('mic%d', p));
    zTop = max(zTop, zc);
    text(ax, x(p) + 5.5, 0, zTip + lM + 12, lbl, 'Color', col, 'FontWeight', 'bold', 'FontSize', 11, ...
        'VerticalAlignment', 'middle', 'Tag', sprintf('label%d', p));
end
% hatch and outline of the cut faces (one line object each)
if S.section && ~isempty(S.hatch)
    plot3(ax, S.hatch(:, 1), S.hatch(:, 2), S.hatch(:, 3), '-', 'Color', [0.45 0.47 0.52], 'LineWidth', 0.5);
end
if ~isempty(S.edges)
    % in front of the cut faces (y = -0.02) so that the outline is not hidden
    plot3(ax, S.edges(:, 1), S.edges(:, 2) - 0.06, S.edges(:, 3), '-', 'Color', [0.25 0.25 0.28], 'LineWidth', 0.6);
end

% ---------------------------------------------------------------- annotation
text(ax, xH0 + lH / 2, 0, rH + 9, 'loudspeaker (large end)', 'HorizontalAlignment', 'center', 'FontSize', 11);
if isscalar(la) && isfinite(la) && la > 0
    tl = {'termination', sprintf('absorber %g mm', round(la, 3))};
else
    tl = {'termination', '(absorber side)'};
end
text(ax, xT + tc / 2, 0, ro + 14, tl, 'HorizontalAlignment', 'center', 'FontSize', 11, 'Tag', 'endLabel');
if opts.dimensions
    if known, f = @(v) sprintf('%g mm', round(v, 3)); else, f = @(v) '? (enter)'; end
    z1 = zTop + 16; z2 = zTop + 33; k = [0.12 0.12 0.12];
    for xx = x, line3(ax, [xx xx], [zTop + 2, z2 + 3], [0.6 0.6 0.6], 0.5); end
    for xx = [xF xR], line3(ax, [xx xx], [ro + 1, z2 + 3], [0.6 0.6 0.6], 0.5); end
    dimH(ax, x(1), x(2), z1, sprintf('s1 = %g mm', round(s1, 3)), k, 12, 'dim_s1');
    dimH(ax, x(2), xF, z2, ['L1 = ' f(xF - x(2))], k, 12, 'dim_L1');
    dimH(ax, xF, xR, z1, ['d = ' f(xR - xF)], k, 12, 'dim_d');
    dimH(ax, xR, x(3), z2, ['L2 = ' f(x(3) - xR)], k, 12, 'dim_L2');
    dimH(ax, x(3), x(4), z1, sprintf('s2 = %g mm', round(s2, 3)), k, 12, 'dim_s2');
    % overall lengths (drawing values from the CAD assembly), below the tube
    g = [0.45 0.45 0.45]; zb = -ro - 14;
    for xx = [xS x(1) x(4) xT], line3(ax, [xx xx], [-rb - 1, zb - 3], [0.75 0.75 0.75], 0.5); end
    dimH(ax, xS, x(1), zb, sprintf('bore end -> M1  %g mm', round(x(1) - xS, 3)), g, 10, 'dim_up');
    dimH(ax, x(4), xT, zb, sprintf('M4 -> termination  %g mm', round(xT - x(4), 3)), g, 10, 'dim_down');
    if S.section
        dimV(ax, (xJ + xT) / 2, -rb, rb, sprintf('bore %s%g mm', char(216), round(2 * rb, 3)), g, 10);
    else
        text(ax, (xJ + xT) / 2, 0, zb - 12, sprintf('bore %s%g mm', char(216), round(2 * rb, 3)), ...
            'HorizontalAlignment', 'center', 'FontSize', 10, 'Color', g);
    end
end
hold(ax, 'off');

% ---------------------------------------------------------------- axes, light, view
axis(ax, 'equal');
ax.XLim = [xH0 - 20, xT + tc + 20];
ax.YLim = [-rH - 5, max(rH, 70) + 5];
ax.ZLim = [min(-rH, -ro - 42) - 8, zTop + 52];
ax.Visible = 'off'; ax.Projection = 'orthographic';
delete(findobj(ax, 'Type', 'light'));
light('Parent', ax, 'Position', [-0.35 -1 0.9], 'Style', 'infinite', 'Color', [1 1 1]);
light('Parent', ax, 'Position', [0.5 -0.4 -0.6], 'Style', 'infinite', 'Color', 0.35 * [1 1 1]);
ax.UserData = struct('tube3D', true);
if keepView
    ax.View = oldView;
elseif strcmp(opts.view, 'keep')
    setView(ax, 'default');
else
    setView(ax, opts.view);
end
end

% ====================================================================== parts
function o = fillOpts(o)
d = struct('section', true, 'dimensions', true, 'view', 'keep');
for f = fieldnames(d).'
    if ~isfield(o, f{1}), o.(f{1}) = d.(f{1}); end
end
end

function setView(ax, v)
if ischar(v) || isstring(v)
    switch char(v)
        case 'side',        v = [0 0];         % like a 2D drawing
        case 'perspective', v = [-30 20];
        case 'top',         v = [0 90];
        otherwise,          v = [-10 9];       % 'default': side view, slightly from above / the left
    end
end
view(ax, v);
end

function S = shell(S, x0, x1, rIn, rOut, col, gaps, tag)
% hollow cylinder x0..x1 (rIn = 0: solid); gaps = x-intervals left open in
% the upper cut face (ports)
if x1 - x0 <= 1e-6, return; end
ax = S.ax;
rev(ax, x0, x1, rOut, S.phi, col, 0.30, tag);
if rIn > 0
    rev(ax, x0, x1, rIn, S.phi, [0.90 0.91 0.93], 0.05, tag);
end
annulus(S, x0, rIn, rOut, col, tag); annulus(S, x1, rIn, rOut, col, tag);
if S.section
    if rIn > 0
        S = cutRect(S, x0, x1, rIn, rOut, gaps);
        S = cutRect(S, x0, x1, -rOut, -rIn, []);
    else
        S = cutRect(S, x0, x1, -rOut, rOut, []);
    end
end
end

function S = solid(S, x0, x1, r, col, tag)
% solid cylinder; col = RGB or a texture (m x n x 3)
if x1 - x0 <= 1e-6, return; end
ax = S.ax;
rev(ax, x0, x1, r, S.phi, col, 0.15, tag);
annulus(S, x0, 0, r, col, tag); annulus(S, x1, 0, r, col, tag);
if S.section
    [X, Z] = meshgrid([x0 x1], [-r r]);
    if ndims(col) == 3
        surf(ax, X, zeros(2) - 0.02, Z, 'FaceColor', 'texturemap', 'CData', col, 'EdgeColor', 'none', ...
            'FaceLighting', 'gouraud', 'AmbientStrength', 0.6, 'Tag', tag);
    else
        surf(ax, X, zeros(2) - 0.02, Z, 'FaceColor', col, 'EdgeColor', 'none', 'Tag', tag);
    end
    S.edges = [S.edges; x0 0 -r; x1 0 -r; x1 0 r; x0 0 r; x0 0 -r; NaN NaN NaN];
end
end

function rev(ax, x0, x1, r, phi, col, spec, tag)
% surface of revolution about the x axis; r = radius or [r(x0) r(x1)] (cone)
if isscalar(r), r = [r r]; end
n = max(8, ceil(abs(diff(phi)) / (2 * pi) * 96));
t = linspace(phi(1), phi(2), n + 1);
X = [x0; x1] * ones(1, n + 1); Y = r(:) * cos(t); Z = r(:) * sin(t);
if ndims(col) == 3
    surf(ax, X, Y, Z, 'FaceColor', 'texturemap', 'CData', col, 'EdgeColor', 'none', ...
        'FaceLighting', 'gouraud', 'AmbientStrength', 0.5, 'SpecularStrength', spec, 'Tag', tag);
else
    surf(ax, X, Y, Z, 'FaceColor', col, 'EdgeColor', 'none', 'FaceLighting', 'gouraud', ...
        'AmbientStrength', 0.45, 'DiffuseStrength', 0.65, 'SpecularStrength', spec, ...
        'SpecularExponent', 15, 'Tag', tag);
end
end

function annulus(S, x, rIn, rOut, col, tag)
if ndims(col) == 3, col = squeeze(mean(mean(col, 1), 2)).'; end
n = max(8, ceil(abs(diff(S.phi)) / (2 * pi) * 96));
t = linspace(S.phi(1), S.phi(2), n + 1);
Y = [rIn; rOut] * cos(t); Z = [rIn; rOut] * sin(t);
surf(S.ax, x * ones(size(Y)), Y, Z, 'FaceColor', col, 'EdgeColor', 'none', 'FaceLighting', 'gouraud', ...
    'AmbientStrength', 0.5, 'Tag', tag);
end

function S = cutRect(S, x0, x1, z0, z1, gaps)
% cut face in the plane y = 0 (split at the gaps), hatched at 45 degrees
xs = x0; xe = [];
for g = 1:size(gaps, 1)
    if gaps(g, 2) > x0 && gaps(g, 1) < x1
        xe(end + 1) = max(gaps(g, 1), x0); xs(end + 1) = min(gaps(g, 2), x1); %#ok<AGROW>
    end
end
xe(end + 1) = x1;
cutCol = [0.66 0.70 0.76];
for i = 1:numel(xs)
    a = xs(i); b = xe(i);
    if b - a < 1e-6, continue; end
    patch(S.ax, [a b b a], -0.02 * [1 1 1 1], [z0 z0 z1 z1], cutCol, 'EdgeColor', 'none', ...
        'FaceLighting', 'none', 'Tag', 'cut');
    S.edges = [S.edges; a 0 z0; b 0 z0; b 0 z1; a 0 z1; a 0 z0; NaN NaN NaN];
    sp = 4.5;                                      % hatch spacing [mm]
    for c0 = (ceil((a - z1) / sp) * sp):sp:(b - z0)
        xa = max(a, z0 + c0); xb = min(b, z1 + c0);
        if xb > xa
            S.hatch = [S.hatch; xa -0.05 xa - c0; xb -0.05 xb - c0; NaN NaN NaN];
        end
    end
end
end

function S = holder(S, xc, rb, rB, rHo, hHo, rM, col)
% microphone holder: spigot in the wall + flange on the tube body
z0 =sqrt(max(rB^2 - rHo^2, 0));                   % flange meets the curved body
S = vshell(S, xc, rb, z0, rM + 0.1, 0.72 * rHo, col);
S = vshell(S, xc, z0, rB + hHo, rM + 0.1, rHo, col);
end

function S = vshell(S, xc, z0, z1, rIn, rOut, col)
ax = S.ax;
if S.section, t = linspace(0, pi, 49); else, t = linspace(0, 2 * pi, 97); end
for r = [rOut rIn]
    X = xc + [r; r] * cos(t); Y = [r; r] * sin(t); Z = [z0; z1] * ones(size(t));
    surf(ax, X, Y, Z, 'FaceColor', col, 'EdgeColor', 'none', 'FaceLighting', 'gouraud', ...
        'AmbientStrength', 0.45, 'SpecularStrength', 0.3, 'Tag', 'holder');
end
Xa = xc + [rIn; rOut] * cos(t); Ya = [rIn; rOut] * sin(t);
surf(ax, Xa, Ya, z1 * ones(size(Xa)), 'FaceColor', col, 'EdgeColor', 'none', 'Tag', 'holder');
if S.section
    S = cutRectV(S, xc + rIn, xc + rOut, z0, z1);
    S = cutRectV(S, xc - rOut, xc - rIn, z0, z1);
end
end

function S = cutRectV(S, a, b, z0, z1)
patch(S.ax, [a b b a], -0.02 * [1 1 1 1], [z0 z0 z1 z1], [0.66 0.70 0.76], 'EdgeColor', 'none', ...
    'FaceLighting', 'none', 'Tag', 'cut');
S.edges = [S.edges; a 0 z0; b 0 z0; b 0 z1; a 0 z1; a 0 z0; NaN NaN NaN];
sp = 2.2;
for c0 = (ceil((a - z1) / sp) * sp):sp:(b - z0)
    xa = max(a, z0 + c0); xb = min(b, z1 + c0);
    if xb > xa, S.hatch = [S.hatch; xa -0.05 xa - c0; xb -0.05 xb - c0; NaN NaN NaN]; end
end
end

function zTop = microphone(S, xc, r, z0, len, col, tag)
% B&K 4957 (whole, not sectioned): grille, body, channel colour band,
% SMB plug and cable bent away from the viewer
ax = S.ax;
vcyl(ax, xc, r * 0.97, z0, z0 + 1.5, [0.35 0.36 0.38], tag);              % protection grid
vcyl(ax, xc, r, z0 + 1.5, z0 + len - 9, [0.82 0.83 0.85], tag);           % body
vcyl(ax, xc, r + 0.15, z0 + len - 9, z0 + len - 2, col, tag);             % channel colour
vcyl(ax, xc, r, z0 + len - 2, z0 + len, [0.82 0.83 0.85], tag);
zp = z0 + len;
vcyl(ax, xc, 3.45, zp, zp + 18, [0.12 0.12 0.13], [tag '_cable']);        % SMB plug
vcyl(ax, xc, 3.6, zp + 3, zp + 7, col, [tag '_cable']);
Rb = 16; th = linspace(pi, pi / 2, 16).';
path = [xc * ones(2, 1), [0; 0], [zp + 18; zp + 19]];
path = [path; xc * ones(size(th)), Rb + Rb * cos(th), zp + 19 + Rb * sin(th)];
path = [path; xc, Rb + 45, zp + 19 + Rb];
tubeAlong(ax, path, 1.4, [0.1 0.1 0.1], [tag '_cable']);
zTop = zp + 19 + Rb + 1.4;
end

function vcyl(ax, xc, r, z0, z1, col, tag)
t = linspace(0, 2 * pi, 41);
X = xc + [r; r] * cos(t); Y = [r; r] * sin(t); Z = [z0; z1] * ones(size(t));
surf(ax, X, Y, Z, 'FaceColor', col, 'EdgeColor', 'none', 'FaceLighting', 'gouraud', ...
    'AmbientStrength', 0.45, 'SpecularStrength', 0.5, 'SpecularExponent', 20, 'Tag', tag);
patch(ax, xc + r * cos(t), r * sin(t), z1 * ones(size(t)), col, 'EdgeColor', 'none', 'Tag', tag);
end

function tubeAlong(ax, Pth, r, col, tag)
n = size(Pth, 1); a = linspace(0, 2 * pi, 17);
X = zeros(n, numel(a)); Y = X; Z = X;
for i = 1:n
    T = Pth(min(i + 1, n), :) - Pth(max(i - 1, 1), :); T = T / norm(T);
    N1 = [1 0 0]; N2 = cross(T, N1); N2 = N2 / norm(N2);
    for j = 1:numel(a)
        q = Pth(i, :) + r * (cos(a(j)) * N1 + sin(a(j)) * N2);
        X(i, j) = q(1); Y(i, j) = q(2); Z(i, j) = q(3);
    end
end
surf(ax, X, Y, Z, 'FaceColor', col, 'EdgeColor', 'none', 'FaceLighting', 'gouraud', ...
    'SpecularStrength', 0.4, 'Tag', tag);
end

function loudspeaker(S, xS, rCav)
% schematic cone loudspeaker facing the tube (+x), drawn whole
ax = S.ax;
W = S; W.phi = [0, 2 * pi];
rF = rCav - 6;                                     % frame
x1 = xS - 2.4; x0 = xS - 6; xa = x0 - 0.45 * rF;   % front of frame, cone apex
rev(ax, x0, x1, rF, W.phi, [0.55 0.56 0.58], 0.4, 'loudspeaker');
annulus(W, x1, rF - 4, rF, [0.55 0.56 0.58], 'loudspeaker');
rev(ax, x0, xa, [rF - 4, 0.3 * rF], W.phi, [0.13 0.13 0.14], 0.1, 'loudspeaker');   % cone
[sx, sy, sz] = sphere(24);                          % dust cap
sx(sx < 0) = NaN;
surf(ax, xa + 0.25 * rF * sx, 0.3 * rF * sy, 0.3 * rF * sz, 'FaceColor', [0.2 0.2 0.21], ...
    'EdgeColor', 'none', 'FaceLighting', 'gouraud', 'Tag', 'loudspeaker');
rev(ax, xa - 26, xa - 4, 0.62 * rF, W.phi, [0.28 0.29 0.31], 0.6, 'loudspeaker');    % magnet
annulus(W, xa - 4, 0, 0.62 * rF, [0.28 0.29 0.31], 'loudspeaker');
annulus(W, xa - 26, 0, 0.62 * rF, [0.28 0.29 0.31], 'loudspeaker');
end

function bolts(S, xFace, dirSign, rbc, ang)
for a = ang
    yc = rbc * cos(a); zc = rbc * sin(a);
    if S.section && yc < -1e-6, continue; end
    t = linspace(0, 2 * pi, 25);
    patch(S.ax, (xFace + dirSign * 0.15) * ones(size(t)), yc + 4 * cos(t), zc + 4 * sin(t), ...
        [0.22 0.22 0.24], 'EdgeColor', 'none', 'Tag', 'bolt');
    patch(S.ax, (xFace + dirSign * 0.2) * ones(size(t)), yc + 3.4 * cos(t), zc + 3.4 * sin(t), ...
        [0.40 0.41 0.43], 'EdgeColor', 'none', 'Tag', 'bolt');
    h = linspace(0, 2 * pi, 7);
    patch(S.ax, (xFace + dirSign * 0.25) * ones(size(h)), yc + 1.5 * cos(h), zc + 1.5 * sin(h), ...
        [0.1 0.1 0.1], 'EdgeColor', 'none', 'Tag', 'bolt');
end
end

function housingBolts(S, xFace, rbc, ang)
for a = ang
    yc = rbc * cos(a); zc = rbc * sin(a);
    if S.section && yc < -1e-6, continue; end
    t = linspace(0, 2 * pi, 25);
    X = [xFace; xFace + 4] * ones(size(t)); Y = yc + 3.4 * [1; 1] * cos(t); Z = zc + 3.4 * [1; 1] * sin(t);
    surf(S.ax, X, Y, Z, 'FaceColor', [0.30 0.31 0.33], 'EdgeColor', 'none', 'Tag', 'bolt');
    patch(S.ax, (xFace + 4) * ones(size(t)), yc + 3.4 * cos(t), zc + 3.4 * sin(t), [0.36 0.37 0.39], ...
        'EdgeColor', 'none', 'Tag', 'bolt');
end
end

function tex = porous(base)
% deterministic speckle texture for porous materials
s = RandStream('mt19937ar', 'Seed', 7);
n = rand(s, 48, 160);
n = conv2(n, ones(2) / 4, 'same');
tex = zeros(48, 160, 3);
for c = 1:3, tex(:, :, c) = min(1, base(c) * (0.80 + 0.40 * n)); end
end

% ====================================================================== annotation
function line3(ax, xx, zz, col, w)
plot3(ax, xx, [0 0], zz, '-', 'Color', col, 'LineWidth', w);
end

function dimH(ax, xa, xb, z, label, col, fs, tag)
% horizontal dimension line with arrow heads (plane y = 0), label above
plot3(ax, [xa xb], [0 0], [z z], '-', 'Color', col, 'LineWidth', 0.8, 'Tag', tag);
ah = min(4, abs(xb - xa) / 3);
if ah > 0.5
    patch(ax, [xa xa + ah xa + ah], [0 0 0], [z z + 1.3 z - 1.3], col, 'EdgeColor', 'none');
    patch(ax, [xb xb - ah xb - ah], [0 0 0], [z z + 1.3 z - 1.3], col, 'EdgeColor', 'none');
end
if fs >= 12, fw = 'bold'; else, fw = 'normal'; end
text(ax, (xa + xb) / 2, 0, z + 4, label, 'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom', ...
    'FontSize', fs, 'FontWeight', fw, 'Color', col, 'BackgroundColor', 'w', 'Margin', 1, 'Tag', tag);
end

function dimV(ax, x, za, zb, label, col, fs)
plot3(ax, [x x], [0 0], [za zb], '-', 'Color', col, 'LineWidth', 0.8);
ah = min(3, abs(zb - za) / 4);
patch(ax, [x x - 1 x + 1], -0.1 * [1 1 1], [za za + ah za + ah], col, 'EdgeColor', 'none');
patch(ax, [x x - 1 x + 1], -0.1 * [1 1 1], [zb zb - ah zb - ah], col, 'EdgeColor', 'none');
text(ax, x + 3, -0.2, 0, label, 'FontSize', fs, 'Color', col, 'BackgroundColor', 'w', 'Margin', 1);
end
