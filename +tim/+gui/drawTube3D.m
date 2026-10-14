function out = drawTube3D(ax, geom, drawing, mapping, opts)
%DRAWTUBE3D Dimension-driven 3D model of the impedance tube.
%
%   M = tim.gui.drawTube3D(ax, geom, drawing)
%   M = tim.gui.drawTube3D(ax, geom, drawing, mapping, opts)
%   tim.gui.drawTube3D(ax, 'view', name)       % only change the view
%
%     geom      cfg.geometry (bore diameter, port and specimen positions [m])
%     drawing   cfg.tubeDrawing (parts of the lab CAD assembly, drawing only)
%     mapping   mapping(c) = port of DAQ channel c (default 1:4; 0 = not mounted)
%     opts.section     true (default): half section - the half towards the
%                      viewer is removed, cut faces are hatched; the bore,
%                      the specimen and the microphone tips are visible
%     opts.dimensions  true (default): chain dimension s1, L1, d, L2, s2 on
%                      one line above the microphones (the extension lines
%                      end at that line, so no value is ever crossed; a value
%                      wider than its span goes outside (s1, s2) or one row
%                      up (L1, d, L2)) and the overall lengths (lighter grey)
%     opts.view        'keep' (default: keep the user's rotation), or
%                      'default' | 'side' | 'perspective' | 'top' | [az el]
%     opts.mode        'setup' (default) | 'calibration': the specimen section
%                      is mounted EMPTY (no specimen), absorbing termination,
%                      fixed port names, channel labels travel with the
%                      microphones, no dimension lines, room above the tube
%                      for lifted microphones
%     opts.highlightPorts  ports with a yellow glow (calibration ports a, b)
%     opts.micLabels   1x4 cell, label of DAQ channel c (calibration mode)
%     opts.absorberLength  [m] absorber drawn in calibration mode when
%                      drawing.absorberLength is not given (schematic, 0.06)
%     opts.termination (kind, place) of the termination load (WO-005,
%                      tim.app.describeLoad): the absorber, the empty extension
%                      tube with the end cap, without it (open end), or at the
%                      joint the extension removed, with a rigid cap on the
%                      flange or open; the label and the dimension "M4 –
%                      termination" follow. [] (default): extension, end cap
%                      and the absorber as before
%     opts.highlightTermination  yellow sleeve around the termination (the
%                      two-load sequence: the load to mount now; in M.glow)
%
%   Output M (units: mm, the drawing's data units):
%     M.micGroup(c)  hgtransform holding the microphone of DAQ channel c
%                    (body, plug, cable, label); identity Matrix after drawing.
%                    Move channel c to port p, lifted by dz:
%                    M.micGroup(c).Matrix = makehgtform('translate', [M.portX(p) - M.micX0(c), 0, dz])
%     M.micLabel(c), M.micX0(c) (port x it was drawn at), M.portX (M1..M4),
%     M.glow (glow surfaces, FaceAlpha can be pulsed), M.lift (1x4 travel
%     heights: the first clears every microphone), M.zHandle (plug top),
%     M.labelSide(p) (-1 left / +1 right), M.labelGap, M.mapping,
%     M.swapRadius (corner radius of the swap paths, tim.gui.calSwapPath;
%     0 = sharp corners).
%
%   x = tube axis (x = 0 at the specimen FRONT face, increasing towards the
%   termination), z = up (microphones), y = depth (side view seen from -y).
%   Positions follow the entered geometry immediately; part sizes come
%   from cfg.tubeDrawing (CAD assembly Assy_SIT). Microphones, holders and
%   bolts are drawn whole (not sectioned), as in a technical drawing.
%   The specimen is GENERIC (perforated plate, screen, membrane or porous
%   layer alike): a plain blue-grey block (Tag 'specimen'), d < 1 mm a thin
%   plate clamped in the joint, labelled 'specimen' with d below the tube.
%   Every text has a transparent background (no boxes) and sits where no
%   geometry is behind it; texts are 11 pt like the axes (secondary 10 pt).
%   Nothing drawn here is used by the analysis.

out = struct();
if ischar(geom) && strcmp(geom, 'view')
    setView(ax, drawing); return
end
if nargin < 4 || isempty(mapping), mapping = 1:4; end
if nargin < 5, opts = struct(); end
opts = fillOpts(opts);
cal = strcmp(opts.mode, 'calibration');
if cal, opts.dimensions = false; end         % the lifted microphones travel through that space
hiP = opts.highlightPorts(:).'; hiP = hiP(hiP >= 1 & hiP <= 4);
P = tim.gui.palette();
C = colours();
td = drawing;
mm = @(v) 1e3 * v;

% ---------------------------------------------------------------- positions [mm]
known = all(isfinite(geom.micPositions)) && isfinite(geom.xFront) && isfinite(geom.xRear);
s1 = mm(geom.spacingUp); s2 = mm(geom.spacingDown);
if known
    x = mm(geom.micPositions); xF = mm(geom.xFront); xR = mm(geom.xRear);
    % the spacings the analysis uses (analyzeFourMic: |x2 - x1|, |x4 - x3|
    % when the positions are known) - also what the dimension lines span
    s1 = abs(x(2) - x(1)); s2 = abs(x(4) - x(3));
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
% specimen section (the specimen fills it) and the specimen: GENERIC look
% (plain blue-grey block, no material texture - perforated plates, screens,
% membranes and porous layers are all drawn alike); d < 1 mm: a thin plate
% clamped between the two joint flanges (drawn at least 2 mm thick and
% proud of the flanges, so that it stays visible)
d = xR - xF; thin = d < 1;
if ~thin
    S = shell(S, xF, xR, rb, ro, metal, [], 'specimenSection');
    if ~cal, S = specimenSolid(S, xF, xR, rb - 0.05, C, -0.03); end
elseif ~cal
    tv = max(d, 2); xc = (xF + xR) / 2;
    S = specimenSolid(S, xc - tv / 2, xc + tv / 2, ro + 1.2, C, -0.07);
end
if ~cal                                           % part label below the tube (white background)
    if ~known, dl = 'd = ? (enter)'; else, dl = sprintf('d = %g mm', round(d, 3)); end
    if thin && known, sl = 'thin specimen'; else, sl = 'specimen'; end
    text(ax, (xF + xR) / 2, 0, -ro - 5, {sl, dl}, 'HorizontalAlignment', 'center', 'VerticalAlignment', 'top', ...
        'FontSize', C.fs, 'FontWeight', 'bold', 'Color', C.specText, 'Tag', 'specimenLabel');
end
if cal                                            % calibration: the section is mounted EMPTY
    plot3(ax, [xF xR xR xF xF], -0.3 * ones(1, 5), [-rb -rb rb rb -rb], '--', 'Color', C.specEdge, ...
        'LineWidth', 1.2, 'Tag', 'specimenOutline');
    if known && ~thin
        t1 = {sprintf('EMPTY %g mm section', round(d, 3)), '(no specimen)'};
    elseif known
        t1 = {'thin specimen removed', '(empty tube at the joint)'};
    else
        t1 = {'EMPTY specimen section', '(no specimen)'};
    end
    text(ax, (xF + xR) / 2, 0, -ro - 5, t1, 'HorizontalAlignment', 'center', ...
        'VerticalAlignment', 'top', 'FontSize', C.fs, 'FontWeight', 'bold', 'Color', C.specText, 'Tag', 'emptyLabel');
end
% downstream tube: joint flanges and body; then the termination. opts.termination
% (kind, place; WO-005): the extension tube up to the end cap, or nothing beyond
% the joint (extension removed); the end cap, a rigid cap on the joint flange, or
% an open end; the absorber (schematic length unless drawing.absorberLength).
% Without it: extension, end cap and - length known, or calibration - the absorber
S = shell(S, xR, xR + tf, rb, ro, metal, [], 'tube');
S = shell(S, xR + tf, xJ - tf, rb, rB, metal, portGaps(3:4, :), 'tube');
S = shell(S, max(xJ - tf, xR + tf), xJ, rb, ro, metal, [], 'tube');
tk = ''; atJoint = false;
if ~isempty(opts.termination)
    tk = char(opts.termination.kind); atJoint = strcmp(char(opts.termination.place), 'joint');
end
xEnd = xT; if atJoint, xEnd = xJ; end               % termination face
if ~atJoint, S = shell(S, xJ, xT, rb, ro, metal, [], 'tube'); end
if ~strcmp(tk, 'open')
    S = solid(S, xEnd, xEnd + tc, ro, metal, 'endCap');
    annulus(S, xEnd - 0.05, 0, rb, [0.55 0.57 0.60], 'termination');   % termination face
end
la = mm(td.absorberLength); laGiven = isscalar(la) && isfinite(la) && la > 0;
if (cal || strcmp(tk, 'absorber')) && ~laGiven, la = mm(opts.absorberLength); end
if (isempty(tk) || strcmp(tk, 'absorber')) && isscalar(la) && isfinite(la) && la > 0
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
bolts(S, xJ - tf, -1, rbc, ang);
if ~strcmp(tk, 'open'), bolts(S, xEnd + tc, +1, rbc, ang); end
housingBolts(S, xS + tSF, (rSF + rH) / 2 - 2.5, (0:3) * pi / 2);
% microphone holders, microphones (coloured by the DAQ channel in the port), cables;
% each channel's microphone + label in its own hgtransform (moved without redraw)
out.micGroup = gobjects(1, 4); out.micLabel = gobjects(1, 4); out.micX0 = nan(1, 4);
out.portLabel = gobjects(1, 4); out.labelSide = [-1 1 -1 1]; out.labelGap = 6;
zTop = 0;
for p = 1:4
    c = find(mapping == p, 1);
    col = [0.5 0.5 0.5]; if ~isempty(c), col = P.ch(c, :); end
    S = holder(S, x(p), rb, rB, rHo, hHo, rM, metal);
    [zc, hm] = microphone(S, x(p), rM, zTip, lM, col, sprintf('mic%d', p));
    zTop = max(zTop, zc);
    if cal       % port name fixed below the tube; the channel label moves with the microphone
        pl = sprintf('M%d', p); k = find(hiP == p, 1);
        if ~isempty(k), pl = sprintf('M%d (%c)', p, 'a' + k - 1); end
        % neighbouring ports are only s apart: the labels of a pair point away
        % from each other (M1 / M3 to the left, M2 / M4 to the right) so they
        % never overlap, however small the drawing is
        sp = out.labelSide(p); hp = {'right', 'left'};
        out.portLabel(p) = text(ax, x(p) - sp * 2, 0, -rB - 3, pl, 'HorizontalAlignment', hp{(sp > 0) + 1}, ...
            'VerticalAlignment', 'top', 'FontWeight', 'bold', 'FontSize', C.fs, 'Color', C.text, ...
            'Tag', sprintf('portLabel%d', p));
        if isempty(c)
            lbl = 'plug';
        elseif numel(opts.micLabels) >= c && ~isempty(opts.micLabels{c})
            lbl = opts.micLabels{c};
        else
            lbl = sprintf('ch%d', c);
        end
        s = out.labelSide(p); ha = {'right', 'left'};
        ht = text(ax, x(p) + s * out.labelGap, 0, zTip + lM + 10, lbl, 'Color', col, 'FontWeight', 'bold', ...
            'FontSize', C.fs, 'HorizontalAlignment', ha{(s > 0) + 1}, 'VerticalAlignment', 'middle', 'Tag', 'chLabel');
    else         % Tube setup: port name and channel right of the plug (the cable bends away)
        lbl = sprintf('M%d', p); if ~isempty(c), lbl = {sprintf('M%d', p), sprintf('ch%d', c)}; end
        ht = text(ax, x(p) + 5.5, 0, zTip + lM + 12, lbl, 'Color', col, 'FontWeight', 'bold', 'FontSize', C.fs, ...
            'VerticalAlignment', 'middle', 'Tag', sprintf('label%d', p));
    end
    if ~isempty(c)
        g = hgtransform('Parent', ax, 'Tag', sprintf('micGroup%d', c));
        set([hm, ht], 'Parent', g);
        out.micGroup(c) = g; out.micLabel(c) = ht; out.micX0(c) = x(p);
    end
end
out.glow = gobjects(0);
for p = hiP
    out.glow = [out.glow, portGlow(ax, x(p), rHo + 2.5, rB - 2, rB + hHo + 12, rM + 1)];
end
out.portX = x; out.mapping = mapping;
out.zHandle = zTip + lM + 18;                        % plug top
out.lift = (zTop - zTip + 4) + 10 * (0:3);           % the first lift clears every microphone and cable; +10 mm per further mover (they also move apart in depth)
out.swapRadius = swapRadius(x, out.lift(1), max(rM, 3.6), rB + hHo - zTip);   % (3.6 mm: plug, see microphone)
% hatch and outline of the cut faces (one line object each)
if S.section && ~isempty(S.hatch)
    plot3(ax, S.hatch(:, 1), S.hatch(:, 2), S.hatch(:, 3), '-', 'Color', [0.45 0.47 0.52], 'LineWidth', 0.5);
end
if ~isempty(S.edges)
    % in front of the cut faces (y = -0.02) so that the outline is not hidden
    plot3(ax, S.edges(:, 1), S.edges(:, 2) - 0.06, S.edges(:, 3), '-', 'Color', [0.25 0.25 0.28], 'LineWidth', 0.6);
end

% ---------------------------------------------------------------- annotation
% transparent texts only (no background boxes), each placed on white
% background: part labels above / below the parts, dimension values above
% the ends of their extension lines
xl = [xH0 - 20, xT + tc + 20];                       % x limits of the drawing
T = drawScale(ax, xl);                               % screen scale for the label layout
% left-aligned on the housing back: stays inside the drawing, above the tube
text(ax, xH0, 0, rH + 6, 'loudspeaker (large end)', 'HorizontalAlignment', 'left', 'VerticalAlignment', 'bottom', ...
    'FontSize', C.fs, 'Color', C.text, 'Tag', 'speakerLabel');
absTxt = '(absorber schematic)'; if laGiven, absTxt = sprintf('absorber %g mm', round(la, 3)); end
switch [tk '|' char(string(atJoint))]
    case {'absorber|false', 'absorber|true'}, tl = {'absorbing termination', absTxt};
    case 'rigid|false', tl = {'rigid end cap', '(absorber removed)'};
    case 'open|false', tl = {'open end', '(end cap and absorber removed)'};
    case 'rigid|true', tl = {'rigid cap at the joint', '(extension removed)'};
    case 'open|true', tl = {'open at the joint', '(extension removed)'};
    otherwise
        if cal && laGiven
            tl = {'absorbing termination', absTxt};
        elseif cal
            tl = {'absorbing / anechoic termination', absTxt};
        elseif laGiven
            tl = {'termination', absTxt};
        else
            tl = {'termination', '(absorber side)'};
        end
end
if atJoint
    % in the space of the removed extension tube, at the height of the tube
    text(ax, xEnd + tc + 10, 0, 0, tl, 'HorizontalAlignment', 'left', 'VerticalAlignment', 'middle', ...
        'FontSize', C.fs, 'Color', C.text, 'Tag', 'endLabel');
else
    % right-aligned on the end cap: stays inside the drawing, above the extension tube
    text(ax, xT + tc, 0, ro + 6, tl, 'HorizontalAlignment', 'right', 'VerticalAlignment', 'bottom', ...
        'FontSize', C.fs, 'Color', C.text, 'Tag', 'endLabel');
end
if opts.highlightTermination        % the termination the operator changes now (two-load sequence)
    out.glow = [out.glow, termGlow(ax, xEnd - 22, xEnd + tc + 4, ro + 4)];
end
zDimTop = zTop;
zDimBottom = min(-rH, -ro - 5 - 2 * rowHeight(C.fs, T));   % two-line specimen / empty-section label
if opts.dimensions
    if known, f = @(v) sprintf('%g mm', round(v, 3)); else, f = @(v) '? (enter)'; end
    % chain dimension on ONE line above the microphones; every extension line
    % ends just above it, so it never crosses a value
    z1 = zTop + 14;
    for xx = x, line3(ax, [xx xx], [zTop + 3, z1 + 1.2], C.ext, 0.5, 'dimExt'); end
    for xx = unique([xF xR]), line3(ax, [xx xx], [ro + 2, z1 + 1.2], C.ext, 0.5, 'dimExt'); end
    D = struct('xa', {x(1), x(3), x(2), xR, xF}, 'xb', {x(2), x(4), xF, x(3), xR}, ...
        'label', {sprintf('s1 = %g mm', round(s1, 3)), sprintf('s2 = %g mm', round(s2, 3)), ...
        ['L1 = ' f(xF - x(2))], ['L2 = ' f(x(3) - xR)], ['d = ' f(xR - xF)]}, ...
        'tag', {'dim_s1', 'dim_s2', 'dim_L1', 'dim_L2', 'dim_d'}, ...
        'outside', {-1, +1, 0, 0, 0});               % s1 / s2: value outside when it does not fit
    zDimTop = chainDims(ax, D, z1, C, T);
    % overall lengths (drawing values from the CAD assembly) below the tube,
    % values under their lines (white background), clear of the housing
    zb = -ro - 10; r2 = rowHeight(C.fs2, T);
    line3(ax, [xS xS], [-rb - 1, zb - 1], C.ext, 0.5, 'dimExt');
    for xx = x([1 4]), line3(ax, [xx xx], [-rB - 1.5, zb - 1], C.ext, 0.5, 'dimExt'); end
    line3(ax, [xEnd xEnd], [-ro - 1.5, zb - 1], C.ext, 0.5, 'dimExt');
    xHousing = xS + tSF + 14;                      % right of the loudspeaker housing (also in the full view)
    dimBelow(ax, xS, x(1), zb, sprintf('bore end %s M1: %g mm', char(8211), round(x(1) - xS, 3)), ...
        C.dim2, C.fs2, 'dim_up', xHousing, T);
    dimBelow(ax, x(4), xEnd, zb, sprintf('M4 %s termination: %g mm', char(8211), round(xEnd - x(4), 3)), ...
        C.dim2, C.fs2, 'dim_down', xHousing, T);
    zDimBottom = min(zDimBottom, zb - 1.5 - r2);
    if S.section
        xBore = (xJ + xT) / 2; if atJoint, xBore = (xR + x(3)) / 2; end   % in the extension, else between the rear face and M3
        dimV(ax, xBore, -rb, rb, sprintf('bore %s%g mm', char(216), round(2 * rb, 3)), C.dim2, C.fs2);
    else                                           % (bore hidden) one row below the overall length
        text(ax, (x(4) + xT) / 2, 0, zb - 1.5 - r2, sprintf('bore %s%g mm', char(216), round(2 * rb, 3)), ...
            'HorizontalAlignment', 'center', 'VerticalAlignment', 'top', 'FontSize', C.fs2, 'Color', C.dim2, 'Tag', 'dim_bore');
        zDimBottom = min(zDimBottom, zb - 1.5 - 2 * r2);
    end
end
hold(ax, 'off');

% ---------------------------------------------------------------- axes, light, view
axis(ax, 'equal');
ax.XLim = xl;
ax.YLim = [-rH - 5, max(rH, 70) + 5];
if cal
    ax.ZLim = [zDimBottom - 8, zTop + out.lift(end) + 8];
else
    ax.ZLim = [min(-ro - 42, zDimBottom) - 8, max(zTop + 24, zDimTop + 8)];
end
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
d = struct('section', true, 'dimensions', true, 'view', 'keep', 'mode', 'setup', ...
    'highlightPorts', [], 'micLabels', {{}}, 'absorberLength', 0.06, 'termination', [], ...
    'highlightTermination', false);
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
% "Restore view" of the toolbar must return to THIS drawing, not to the view
% stored at the first zoom of an earlier drawing
if isappdata(ax, 'matlab_graphics_resetplotview'), rmappdata(ax, 'matlab_graphics_resetplotview'); end
end

function r = swapRadius(x, lift1, rho, zExit)
% corner radius of the swap paths of the Calibration view (one per drawing;
% each path uses min(r, |xb - xa|/2), tim.gui.calSwapPath) [mm]:
%   0.4 sMin, h1/3     the corner stays small against the port spacing and
%                      the height of the path
%   h1 - 8             the dashed arrow (h1 high, from the plug top + 2 mm)
%                      ends straight: 6 mm arrowhead + 2 mm shank
%   sMin - 2 rho - 1   a microphone turning towards the next column stays
%                      1 mm clear of the microphone (or plug) standing there
%   lift1 - zExit - 1  the microphone tip has left its holder by 1 mm before
%                      it turns
% sMin = smallest non-zero port spacing (a zero gap, e.g. L1 = d = L2 = 0,
% does not count, nor a rounding residue below 1 um), h1 = lift1 - 2, rho =
% microphone or plug radius, zExit = lift at which the tip leaves the
% holder. Below 1 mm the corners stay sharp (r = 0).
g = diff(sort(x(:).')); sMin = min([g(g > 1e-3), Inf]);
h1 = lift1 - 2;
r = max(0, min([0.4 * sMin, h1 / 3, h1 - 8, sMin - 2 * rho - 1, lift1 - zExit - 1]));
if ~(r >= 1), r = 0; end
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

function [zTop, h] = microphone(S, xc, r, z0, len, col, tag)
% B&K 4957 (whole, not sectioned): grille, body, channel colour band,
% SMB plug and cable bent away from the viewer; h = all graphics objects
ax = S.ax;
h = vcyl(ax, xc, r * 0.97, z0, z0 + 1.5, [0.35 0.36 0.38], tag);              % protection grid
h = [h, vcyl(ax, xc, r, z0 + 1.5, z0 + len - 9, [0.82 0.83 0.85], tag)];      % body
h = [h, vcyl(ax, xc, r + 0.15, z0 + len - 9, z0 + len - 2, col, tag)];        % channel colour
h = [h, vcyl(ax, xc, r, z0 + len - 2, z0 + len, [0.82 0.83 0.85], tag)];
zp = z0 + len;
h = [h, vcyl(ax, xc, 3.45, zp, zp + 18, [0.12 0.12 0.13], [tag '_cable'])];   % SMB plug
h = [h, vcyl(ax, xc, 3.6, zp + 3, zp + 7, col, [tag '_cable'])];
Rb = 16; th = linspace(pi, pi / 2, 16).';
path = [xc * ones(2, 1), [0; 0], [zp + 18; zp + 19]];
path = [path; xc * ones(size(th)), Rb + Rb * cos(th), zp + 19 + Rb * sin(th)];
path = [path; xc, Rb + 45, zp + 19 + Rb];
h = [h, tubeAlong(ax, path, 1.4, [0.1 0.1 0.1], [tag '_cable'])];
zTop = zp + 19 + Rb + 1.4;
end

function h = vcyl(ax, xc, r, z0, z1, col, tag)
t = linspace(0, 2 * pi, 41);
X = xc + [r; r] * cos(t); Y = [r; r] * sin(t); Z = [z0; z1] * ones(size(t));
hs = surf(ax, X, Y, Z, 'FaceColor', col, 'EdgeColor', 'none', 'FaceLighting', 'gouraud', ...
    'AmbientStrength', 0.45, 'SpecularStrength', 0.5, 'SpecularExponent', 20, 'Tag', tag);
hp = patch(ax, xc + r * cos(t), r * sin(t), z1 * ones(size(t)), col, 'EdgeColor', 'none', 'Tag', tag);
h = [hs, hp];
end

function h = portGlow(ax, xc, r, z0, z1, rIn)
% translucent yellow cylinder + ring around a calibration port (whole, also
% in the section view); Tubebench pulses FaceAlpha while the operator works
yel = [1 0.85 0.25]; t = linspace(0, 2 * pi, 49);
X = xc + [r; r] * cos(t); Y = [r; r] * sin(t); Z = [z0; z1] * ones(size(t));
h = surf(ax, X, Y, Z, 'FaceColor', yel, 'EdgeColor', 'none', 'FaceAlpha', 0.35, ...
    'FaceLighting', 'none', 'PickableParts', 'none', 'Tag', 'portGlow');
Xa = xc + [rIn; r] * cos(t); Ya = [rIn; r] * sin(t);
h(2) = surf(ax, Xa, Ya, z1 * ones(size(Xa)), 'FaceColor', yel, 'EdgeColor', 'none', 'FaceAlpha', 0.35, ...
    'FaceLighting', 'none', 'PickableParts', 'none', 'Tag', 'portGlow');
end

function h = termGlow(ax, x0, x1, r)
% translucent yellow sleeve around the termination the operator changes now
% (two-load sequence; pulsed like the port glow)
yel = [1 0.85 0.25]; t = linspace(0, 2 * pi, 49);
X = [x0; x1] * ones(size(t)); Y = [r; r] * cos(t); Z = [r; r] * sin(t);
h = surf(ax, X, Y, Z, 'FaceColor', yel, 'EdgeColor', 'none', 'FaceAlpha', 0.35, ...
    'FaceLighting', 'none', 'PickableParts', 'none', 'Tag', 'termGlow');
end

function h = tubeAlong(ax, Pth, r, col, tag)
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
h = surf(ax, X, Y, Z, 'FaceColor', col, 'EdgeColor', 'none', 'FaceLighting', 'gouraud', ...
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

function S = specimenSolid(S, x0, x1, r, C, yFace)
% GENERIC specimen: plain blue-grey solid with a crisp outline, no material
% texture (Tag 'specimen'; outline 'specimenEdge'). yFace: depth of the cut
% face (a thin plate lies in front of the flange hatching: -0.07)
ax = S.ax;
rev(ax, x0, x1, r, S.phi, C.spec, 0.10, 'specimen');
annulus(S, x0, 0, r, C.spec, 'specimen'); annulus(S, x1, 0, r, C.spec, 'specimen');
if S.section
    [X, Z] = meshgrid([x0 x1], [-r r]);
    surf(ax, X, yFace + zeros(2), Z, 'FaceColor', C.specCut, 'EdgeColor', 'none', 'FaceLighting', 'none', ...
        'Tag', 'specimen');
    plot3(ax, [x0 x1 x1 x0 x0], (yFace - 0.03) * ones(1, 5), [-r -r r r -r], '-', 'Color', C.specEdge, ...
        'LineWidth', 0.9, 'Tag', 'specimenEdge');
else                                               % rim of the specimen (visible for a thin plate)
    t = linspace(0, 2 * pi, 97);
    plot3(ax, [x0 * ones(size(t)), NaN, x1 * ones(size(t))], (r + 0.02) * [cos(t), NaN, cos(t)], ...
        (r + 0.02) * [sin(t), NaN, sin(t)], '-', 'Color', C.specEdge, 'LineWidth', 0.6, 'Tag', 'specimenEdge');
end
end

% ====================================================================== annotation
function C = colours()
% annotation and specimen colours (calm technical-drawing style)
C.fs = 11;                          % every label (parts, microphones, dimensions; = axes font)
C.fs2 = 10;                         % secondary values (overall lengths, bore)
C.text = [0.22 0.23 0.26];          % part labels
C.dim = [0.30 0.34 0.40];           % chain dimension: lines, arrows, values (muted slate)
C.dim2 = [0.50 0.52 0.56];          % overall lengths, bore (lighter)
C.ext = [0.70 0.72 0.75];           % extension lines
C.spec = [0.55 0.62 0.70];          % specimen body (neutral blue-grey, lit)
C.specCut = [0.50 0.57 0.66];       % specimen cut face (unlit, darker than the metal cut)
C.specEdge = [0.20 0.27 0.36];      % specimen outline, empty-section outline
C.specText = [0.18 0.26 0.36];      % specimen / empty-section label
end

function line3(ax, xx, zz, col, w, tag)
plot3(ax, xx, [0 0], zz, '-', 'Color', col, 'LineWidth', w, 'Tag', tag);
end

function arrows(ax, xa, xb, z, col, tag)
% filled arrow heads at both ends of a horizontal dimension line (inside)
ah = min(3.5, abs(xb - xa) / 3); s = sign(xb - xa);
if ah > 0.5
    patch(ax, [xa xa + s * ah xa + s * ah], [0 0 0], [z z + 1.1 z - 1.1], col, 'EdgeColor', 'none', 'Tag', tag);
    patch(ax, [xb xb - s * ah xb - s * ah], [0 0 0], [z z + 1.1 z - 1.1], col, 'EdgeColor', 'none', 'Tag', tag);
end
end

function zTopText = chainDims(ax, D, z, C, T)
% chain dimension: all segments on ONE line at height z, values above it.
% A value wider than its segment is drawn OUTSIDE (D.outside = -1 left of xa,
% +1 right of xb, on an extension of the dimension line) or, for the inner
% segments, one row higher when it would overlap a value already placed
% (with a thin leader when the path down to the line is free).
% Returns the top of the highest value [mm].
rowH = rowHeight(C.fs, T);                         % text row [mm]
gap = 8 / T.pxmm;                                  % free space between two values [mm]
zt = z + 1.5;
placed = zeros(0, 3);                              % [row, left, right]
for i = 1:numel(D)
    xa = min(D(i).xa, D(i).xb); xb = max(D(i).xa, D(i).xb);
    w = textWidth(D(i).label, C.fs, T);
    if xb - xa > 1e-6
        plot3(ax, [xa xb], [0 0], [z z], '-', 'Color', C.dim, 'LineWidth', 0.7, 'Tag', D(i).tag);
        arrows(ax, xa, xb, z, C.dim, D(i).tag);
    end
    o = D(i).outside;
    if o ~= 0 && w > xb - xa - 2 * gap
        % value outside the segment, on an extension of the dimension line
        if o < 0
            xt = xa - 1.5; xe = xt - w; xs = [xe xa]; ha = 'right';
        else
            xt = xb + 1.5; xe = xt + w; xs = [xb xe]; ha = 'left';
        end
        plot3(ax, xs, [0 0], [z z], '-', 'Color', C.dim, 'LineWidth', 0.7, 'Tag', D(i).tag);
        text(ax, xt, 0, zt, D(i).label, 'HorizontalAlignment', ha, 'VerticalAlignment', 'bottom', ...
            'FontSize', C.fs, 'Color', C.dim, 'Tag', D(i).tag);
        placed(end + 1, :) = [1, sort([xt, xe])]; %#ok<AGROW>
        continue
    end
    xc = (xa + xb) / 2; l = xc - w / 2; r = xc + w / 2;
    row = 1;
    while any(placed(:, 1) == row & placed(:, 2) < r + gap & placed(:, 3) > l - gap)
        row = row + 1;
    end
    if row > 1 && ~any(placed(:, 1) < row & placed(:, 2) < xc + gap & placed(:, 3) > xc - gap)
        % thin leader from the dimension line up to a raised value (free path only)
        plot3(ax, [xc xc], [0 0], [z + 1.5, zt + (row - 1) * rowH - 1], '-', 'Color', C.ext, ...
            'LineWidth', 0.5, 'Tag', 'dimLeader');
    end
    placed(end + 1, :) = [row, l, r]; %#ok<AGROW>
    text(ax, xc, 0, zt + (row - 1) * rowH, D(i).label, 'HorizontalAlignment', 'center', ...
        'VerticalAlignment', 'bottom', 'FontSize', C.fs, 'Color', C.dim, 'Tag', D(i).tag);
end
zTopText = zt + max(placed(:, 1)) * rowH;
end

function w = textWidth(s, fs, T)
% estimated width of a one-line label [mm] (Helvetica / Arial metrics)
s = char(s); em = 0.56 * ones(size(s));
em(isstrprop(s, 'upper')) = 0.67;
em(ismember(s, ' .,:;()[]il|')) = 0.28;
em(ismember(s, 'mwMW')) = 0.84;
w = (fs * T.ptpx * sum(em) + 4) / T.pxmm;
end

function T = drawScale(ax, xl)
% screen scale of the drawing for the label layout: T.pxmm [px/mm] from the
% axes width (the long tube fills the width), at most 1.6 px/mm so that the
% layout also holds when the window is made smaller after drawing;
% T.ptpx [px/pt] (a uifigure draws 1 pt as 1 px, a figure as 96/72 px)
p = getpixelposition(ax);
w = p(3); if w < 300, w = 1100; end                % not laid out yet
T.pxmm = min(1.6, 0.92 * w / diff(xl));
T.ptpx = 96 / 72;
try
    if matlab.ui.internal.isUIFigure(ancestor(ax, 'figure')), T.ptpx = 1; end
catch                                              % internal function missing: conservative
end
end

function h = rowHeight(fs, T)
% height of one text row [mm]
h = 1.45 * fs * T.ptpx / T.pxmm;
end

function dimBelow(ax, xa, xb, z, label, col, fs, tag, xMin, T)
% horizontal dimension with the value BELOW the line (under the tube), kept
% right of xMin (the loudspeaker housing) when it is wider than the span
plot3(ax, [xa xb], [0 0], [z z], '-', 'Color', col, 'LineWidth', 0.7, 'Tag', tag);
arrows(ax, xa, xb, z, col, tag);
w = textWidth(label, fs, T); xc = (xa + xb) / 2;
if xc - w / 2 < xMin, xc = xMin + w / 2; end
text(ax, xc, 0, z - 1.5, label, 'HorizontalAlignment', 'center', 'VerticalAlignment', 'top', ...
    'FontSize', fs, 'Color', col, 'Tag', tag);
end

function dimV(ax, x, za, zb, label, col, fs)
% vertical dimension (bore) in the cut plane, value right of it, inside the bore
plot3(ax, [x x], -0.1 * [1 1], [za zb], '-', 'Color', col, 'LineWidth', 0.7, 'Tag', 'dim_bore');
ah = min(3, abs(zb - za) / 4);
patch(ax, [x x - 1 x + 1], -0.1 * [1 1 1], [za za + ah za + ah], col, 'EdgeColor', 'none', 'Tag', 'dim_bore');
patch(ax, [x x - 1 x + 1], -0.1 * [1 1 1], [zb zb - ah zb - ah], col, 'EdgeColor', 'none', 'Tag', 'dim_bore');
text(ax, x + 3, -0.2, 0, label, 'FontSize', fs, 'Color', col, 'VerticalAlignment', 'middle', 'Tag', 'dim_bore');
end
