classdef TestTube3D < matlab.unittest.TestCase
    %TESTTUBE3D 3D tube drawing (tim.gui.drawTube3D) of the Tube setup and
    %   calibration views: returned struct, transparent annotation texts (no
    %   white boxes), GENERIC specimen (thick block / thin plate), calibration
    %   mode with the empty section, dimension values never crossed by an
    %   extension line and never overlapping each other (user requests
    %   2026-10-09), the corner radius of the swap paths over several tube
    %   configurations (owner request 2026-10-12). Invisible figures only.

    properties
        fig
        ax
        cfg
    end

    methods (TestMethodSetup)
        function newAxes(tc)
            tc.fig = figure('Visible', 'off', 'Units', 'pixels', 'Position', [50 50 1300 700]);
            tc.addTeardown(@() delete(tc.fig));
            tc.ax = axes(tc.fig, 'Units', 'normalized', 'Position', [0 0 1 1]);
            tc.cfg = tim.app.defaultConfig();
        end
    end

    methods (Test)
        function terminationsDrawn(tc)
            % WO-005: the model follows the termination load - the absorber, the
            % empty extension with the end cap, without it (open end), or at the
            % joint the extension removed, with a cap on the flange or open; the
            % label and the dimension M4 - termination follow; the load to mount
            % glows (two-load sequence)
            [g, td] = tc.lab();
            ext = @(ax) max(arrayfun(@(o) max(o.XData(:)), findobj(ax, 'Tag', 'tube')));   % end of the tube parts
            L = {'absorber', 'tubeEnd', true,  true,  'absorbing termination', 291, 145 + 291
                 'rigid',    'tubeEnd', false, true,  'rigid end cap',         291, 145 + 291
                 'open',     'tubeEnd', false, false, 'open end',              291, 145 + 291
                 'rigid',    'joint',   false, true,  'rigid cap at the joint', 41, 145 + 41
                 'open',     'joint',   false, false, 'open at the joint',      41, 145 + 41};
            for i = 1:size(L, 1)
                ld = struct('kind', L{i, 1}, 'place', L{i, 2});
                M = tim.gui.drawTube3D(tc.ax, g, td, 1:4, struct('termination', ld));
                id = sprintf('%s at %s', L{i, 1}, L{i, 2});
                tc.verifyEqual(~isempty(findobj(tc.ax, 'Tag', 'absorber')), L{i, 3}, [id ': absorber']);
                tc.verifyEqual(~isempty(findobj(tc.ax, 'Tag', 'endCap')), L{i, 4}, [id ': cap']);
                lab = findobj(tc.ax, 'Tag', 'endLabel'); s = cellstr(lab.String);
                tc.verifyEqual(s{1}, L{i, 5}, id);
                dd = findobj(tc.ax, 'Tag', 'dim_down', 'Type', 'text');
                tc.verifySubstring(strjoin(cellstr(dd.String), ' '), sprintf('termination: %g mm', L{i, 6}), id);
                tc.verifyEqual(ext(tc.ax), L{i, 7}, 'AbsTol', 1e-6, [id ': the tube ends at the termination']);
                tc.verifyEmpty(findobj(tc.ax, 'Tag', 'termGlow'), [id ': no glow unless asked']);
                tc.verifyEmpty(M.glow);
            end
            M = tim.gui.drawTube3D(tc.ax, g, td, 1:4, struct('termination', struct('kind', 'rigid', 'place', 'joint'), ...
                'highlightTermination', true));
            tc.verifyNumElements(M.glow, 1, 'the termination to mount glows');
            tc.verifyEqual(M.glow.Tag, 'termGlow');
            % without a load: as before (extension, end cap, no absorber without its length)
            tim.gui.drawTube3D(tc.ax, g, td, 1:4);
            tc.verifyEmpty(findobj(tc.ax, 'Tag', 'absorber'));
            tc.verifyNotEmpty(findobj(tc.ax, 'Tag', 'endCap'));
            lab = findobj(tc.ax, 'Tag', 'endLabel');
            tc.verifyEqual(cellstr(lab.String), {'termination'; '(absorber side)'});
        end

        function returnedStruct(tc)
            % fields used by Tubebench (calibration animation, labels, glow)
            [g, td] = tc.lab();
            M = tim.gui.drawTube3D(tc.ax, g, td, [2 1 3 4]);
            for f = {'micGroup', 'micLabel', 'micX0', 'portX', 'portLabel', 'lift', 'zHandle', ...
                    'labelSide', 'labelGap', 'glow', 'mapping', 'swapRadius'}
                tc.verifyTrue(isfield(M, f{1}), f{1});
            end
            tc.verifyEqual(M.swapRadius, 11.6, 'AbsTol', 1e-9, 'lab tube: 0.4 x 29 mm');
            tc.verifySize(M.micGroup, [1 4]); tc.verifySize(M.micLabel, [1 4]);
            tc.verifyEqual(M.portX, [-70 -41 116 145], 'AbsTol', 1e-9);
            tc.verifyEqual(M.micX0, [-41 -70 116 145], 'AbsTol', 1e-9, 'micX0(c) = port of channel c');
            tc.verifyEqual(M.mapping, [2 1 3 4]);
            tc.verifyEqual(M.labelSide, [-1 1 -1 1]); tc.verifyEqual(M.labelGap, 6);
            for c = 1:4
                tc.verifyClass(M.micGroup(c), 'matlab.graphics.primitive.Transform');
                tc.verifyEqual(M.micGroup(c).Matrix, eye(4));
                tc.verifyEqual(M.micLabel(c).Parent, M.micGroup(c), 'label travels with the microphone');
            end
            tc.verifyEqual(strjoin(cellstr(M.micLabel(1).String), ' '), 'M2 ch1');
            tc.verifyGreaterThan(diff(M.lift), 0, 'every mover has its own height');
            tc.verifyGreaterThan(M.zHandle, 0);
            tc.verifyEmpty(M.glow, 'no glow in the Tube setup');
            % a channel without a microphone: no group, grey port label
            M = tim.gui.drawTube3D(tc.ax, g, td, [1 2 3 0]);
            tc.verifyFalse(isgraphics(M.micGroup(4)));
            tc.verifyTrue(isnan(M.micX0(4)));
            tc.verifyEqual(findobj(tc.ax, 'Tag', 'label4').Color, [0.5 0.5 0.5]);
        end

        function textsHaveTransparentBackground(tc)
            % no text with a background or a frame, no patch used as a label
            % box - in every mode and view
            [g, td] = tc.lab(); [gt, ~] = tc.thin();
            gs = g; gs.micPositions = nan(1, 4); gs.xFront = NaN; gs.xRear = NaN;
            cases = {{g, struct()}, {g, struct('section', false)}, {gt, struct()}, {gs, struct()}, ...
                {g, struct('mode', 'calibration', 'highlightPorts', [1 2])}, ...
                {gt, struct('mode', 'calibration', 'highlightPorts', [1 2])}};
            for i = 1:numel(cases)
                tim.gui.drawTube3D(tc.ax, cases{i}{1}, td, 1:4, cases{i}{2});
                t = findall(tc.ax, 'Type', 'text');
                tc.assertNotEmpty(t);
                bg = get(t, 'BackgroundColor'); ed = get(t, 'EdgeColor');
                tc.verifyTrue(all(strcmp(bg, 'none')), sprintf('case %d: text with a background', i));
                tc.verifyTrue(all(strcmp(ed, 'none')), sprintf('case %d: text with a frame', i));
                tc.verifyEmpty(findall(tc.ax, 'Type', 'rectangle'), sprintf('case %d', i));
                p = findall(tc.ax, 'Type', 'patch');
                fc = get(p, 'FaceColor'); fc = fc(cellfun(@isnumeric, fc));
                tc.verifyFalse(any(cellfun(@(c) isequal(c, [1 1 1]), fc)), sprintf('case %d: white patch', i));
                fs = cell2mat(get(t, 'FontSize'));
                tc.verifyTrue(all(ismember(fs, [10 11])), sprintf('case %d: label font sizes 11 / 10 pt', i));
            end
        end

        function genericThickSpecimen(tc)
            % plain neutral block filling the section (no porous texture), labelled
            [g, td] = tc.lab();
            tim.gui.drawTube3D(tc.ax, g, td);
            spec = findobj(tc.ax, 'Tag', 'specimen');
            tc.assertNotEmpty(spec);
            xs = cell2mat(cellfun(@(X) X(:), get(spec, 'XData'), 'UniformOutput', false));
            tc.verifyEqual([min(xs) max(xs)], [0 75], 'AbsTol', 1e-9);
            zs = cell2mat(cellfun(@(Z) Z(:), get(spec, 'ZData'), 'UniformOutput', false));
            tc.verifyLessThanOrEqual(max(zs), 14.5, 'fills the bore (radius 14.5 mm)');
            fc = get(spec, 'FaceColor');
            tc.verifyFalse(any(strcmp(fc, 'texturemap')), 'no material texture');
            fc = cell2mat(fc(cellfun(@isnumeric, fc)));
            tc.verifyLessThan(max(fc, [], 2) - min(fc, [], 2), 0.25, 'neutral (low saturation) colour');
            tc.verifyNotEmpty(findobj(tc.ax, 'Tag', 'specimenEdge'), 'crisp outline');
            tc.verifyEqual(tc.textOf('specimenLabel'), 'specimen d = 75 mm');
            % also in the full view (specimen hidden in the section, label stays)
            tim.gui.drawTube3D(tc.ax, g, td, 1:4, struct('section', false));
            tc.verifyEqual(tc.textOf('specimenLabel'), 'specimen d = 75 mm');
        end

        function thinSpecimenPlate(tc)
            % d = 0 (and d < 1 mm): a thin plate clamped in the joint, proud
            % of the flanges (outer diameter 65 mm)
            [g, td] = tc.thin();
            tim.gui.drawTube3D(tc.ax, g, td);
            [x0, x1, zMax] = tc.specimenExtent();
            tc.verifyEqual([x0 x1], [-1 1], 'AbsTol', 1e-9, 'drawn 2 mm thick, centred on the joint');
            tc.verifyGreaterThan(zMax, 1e3 * td.outerDiameter / 2, 'clamped between the flanges');
            tc.verifyEmpty(findobj(tc.ax, 'Tag', 'specimenSection'));
            tc.verifyEqual(tc.textOf('specimenLabel'), 'thin specimen d = 0 mm');
            tc.verifyTrue(any(strcmp(tc.labels(), 'd = 0 mm')), 'thickness dimension');
            g.xRear = 0.0005; g.micPositions(3:4) = g.micPositions(3:4) + 0.0005;
            tim.gui.drawTube3D(tc.ax, g, td);
            [x0, x1] = tc.specimenExtent();
            tc.verifyEqual([x0 x1], [-0.75 1.25], 'AbsTol', 1e-9);
            tc.verifyEqual(tc.textOf('specimenLabel'), 'thin specimen d = 0.5 mm');
            % section and full view both show the plate
            tim.gui.drawTube3D(tc.ax, g, td, 1:4, struct('section', false));
            tc.verifyNotEmpty(findobj(tc.ax, 'Tag', 'specimen'));
        end

        function calibrationModeEmptySection(tc)
            [g, td] = tc.lab();
            lbl = {{'ch1 (ref)', 's/n 111'}, {'ch2'}, {'ch3'}, {'ch4'}};
            M = tim.gui.drawTube3D(tc.ax, g, td, 1:4, struct('mode', 'calibration', ...
                'highlightPorts', [1 2], 'micLabels', {lbl}));
            tc.verifyEmpty(findobj(tc.ax, 'Tag', 'specimen'), 'no specimen during the calibration');
            tc.verifyEmpty(findobj(tc.ax, 'Tag', 'specimenLabel'));
            o = findobj(tc.ax, 'Tag', 'specimenOutline');
            tc.assertNumElements(o, 1);
            tc.verifyEqual(o.LineStyle, '--', 'dashed outline of the empty section');
            tc.verifyEqual([min(o.XData) max(o.XData)], [0 75], 'AbsTol', 1e-9);
            tc.verifyEqual(tc.textOf('emptyLabel'), 'EMPTY 75 mm section (no specimen)');
            tc.verifyEmpty(findobj(tc.ax, '-regexp', 'Tag', '^dim'), 'no dimensions');
            tc.verifyNumElements(M.glow, 4);
            tc.verifyTrue(any(strcmp(tc.labels(), 'M1 (a)')));
            tc.verifyTrue(any(strcmp(tc.labels(), 'ch1 (ref) s/n 111')));
            tc.verifyGreaterThan(tc.ax.ZLim(2), M.zHandle + M.lift(end));
            % thin specimen removed
            [g, td] = tc.thin();
            tim.gui.drawTube3D(tc.ax, g, td, 1:4, struct('mode', 'calibration'));
            tc.verifyEmpty(findobj(tc.ax, 'Tag', 'specimen'));
            tc.verifyEqual(tc.textOf('emptyLabel'), 'thin specimen removed (empty tube at the joint)');
        end

        function dimensionValuesFree(tc)
            % regression 2026-10-09: 's1 = 29 mm' and 's2 = 29 mm' were crossed
            % by the M1 / M3 extension lines. Every extension line now ends
            % below the values above the tube (and above the values below it);
            % values in one row do not overlap - lab tube, thin screen, d = 20
            % mm, schematic, in a large and a small window
            [g, td] = tc.lab(); [gt, ~] = tc.thin();
            g20 = g; g20.xRear = 0.020; g20.micPositions(3:4) = [0.061 0.090];
            gs = g; gs.micPositions = nan(1, 4); gs.xFront = NaN; gs.xRear = NaN;
            for w = [1300 800]
                tc.fig.Position(3) = w;
                for G = {g, gt, g20, gs}
                    tim.gui.drawTube3D(tc.ax, G{1}, td, 1:4, struct('view', 'side'));
                    drawnow;
                    ext = findobj(tc.ax, 'Tag', 'dimExt');
                    tc.assertNotEmpty(ext);
                    z = get(ext, 'ZData'); up = cellfun(@(v) min(v) > 0, z);
                    zExtTop = max(cellfun(@max, z(up))); zExtBottom = min(cellfun(@min, z(~up)));
                    t = findobj(tc.ax, 'Type', 'text', '-regexp', 'Tag', '^dim_(s1|s2|L1|L2|d)$');
                    tc.assertNumElements(t, 5);
                    pos = cell2mat(get(t, 'Position'));
                    tc.verifyGreaterThan(min(pos(:, 3)), zExtTop, sprintf('w = %d: value crossed above', w));
                    tb = findobj(tc.ax, 'Type', 'text', 'Tag', 'dim_up');
                    tc.verifyLessThan(tb.Position(3), zExtBottom, sprintf('w = %d: value crossed below', w));
                    % no overlap of two values in the same row (side view: x extent valid)
                    e = cell2mat(get(t, 'Extent'));
                    for i = 1:5
                        for j = i + 1:5
                            if abs(pos(i, 3) - pos(j, 3)) < 1e-9
                                ov = min(e(i, 1) + e(i, 3), e(j, 1) + e(j, 3)) - max(e(i, 1), e(j, 1));
                                tc.verifyLessThan(ov, 0, sprintf('w = %d: %s overlaps %s', w, t(i).Tag, t(j).Tag));
                            end
                        end
                    end
                end
            end
            % labels the GUI test relies on
            tim.gui.drawTube3D(tc.ax, gs, td);
            tc.verifyTrue(any(strcmp(tc.labels(), 'L1 = ? (enter)')));
            tc.verifyEqual(tc.textOf('specimenLabel'), 'specimen d = ? (enter)');
        end

        function spacingsFromPositions(tc)
            % the analysis uses |x2 - x1| and |x4 - x3| when the positions are
            % known (validateConfig: 'positions are used'); the drawing shows
            % the same values, not stale spacingUp / spacingDown fields
            [g, td] = tc.lab();
            g.spacingUp = 0.031; g.spacingDown = 0.0275;
            tim.gui.drawTube3D(tc.ax, g, td);
            tc.verifyEqual(tc.textOf('dim_s1'), 's1 = 29 mm');
            tc.verifyEqual(tc.textOf('dim_s2'), 's2 = 29 mm');
            % positions unknown: the entered spacings (schematic drawing)
            g.micPositions = nan(1, 4); g.xFront = NaN; g.xRear = NaN;
            tim.gui.drawTube3D(tc.ax, g, td);
            tc.verifyEqual(tc.textOf('dim_s1'), 's1 = 31 mm');
            tc.verifyEqual(tc.textOf('dim_s2'), 's2 = 27.5 mm');
        end

        function swapRadiusOverTubeConfigurations(tc)
            % corner radius of the swap paths (owner request 2026-10-12): one per
            % drawing, min(0.4 sMin, h1/3, h1 - 8, sMin - 2 rho - 1, lift1 - zExit - 1),
            % 0 below 1 mm. Lab parts: lift1 74.5 mm (h1 72.5 mm) for every bore,
            % rho 3.6 mm (plug), tip 14.75 mm and holder top 29.5 mm above the axis
            [g, td] = tc.lab();
            gS1 = cell(1, 4); s1 = [0.001 0.009 0.010 0.200];      % M1 moved, M2..M4 as in the lab
            for k = 1:4, gS1{k} = g; gS1{k}.micPositions(1) = g.micPositions(2) - s1(k); end
            g200 = g; g200.micPositions = [-0.241 -0.041 0.116 0.316];
            gZero = g; gZero.xFront = 0; gZero.xRear = 0; gZero.micPositions = [-0.029 0 0 0.029];
            gD1 = g; gD1.diameter = 0.001; gD500 = g; gD500.diameter = 0.5;
            tdTall = td; tdTall.holderHeight = 0.08;
            cases = { ...
                'lab tube',                   g,          td,     11.6; ...
                's1 = 1 mm',                  gS1{1},     td,     0; ...
                's1 = 9 mm (0.8 mm: sharp)',  gS1{2},     td,     0; ...
                's1 = 10 mm',                 gS1{3},     td,     1.8; ...
                's1 = 200 mm (s2 29 mm)',     gS1{4},     td,     11.6; ...
                's1 = s2 = 200 mm (h1/3)',    g200,       td,     72.5 / 3; ...
                'L1 = d = L2 = 0',            gZero,      td,     11.6; ...
                'D = 1 mm',                   gD1,        td,     11.6; ...
                'D = 500 mm',                 gD500,      td,     11.6; ...
                'holder 80 mm high',          g,          tdTall, 0};
            for i = 1:size(cases, 1)
                [id, G, T, r] = cases{i, :};
                M = tim.gui.drawTube3D(tc.ax, G, T, 1:4, struct('mode', 'calibration'));
                tc.verifyEqual(M.swapRadius, r, 'AbsTol', 1e-9, id);
                % the bounds hold in every configuration
                rb = 1e3 * G.diameter / 2; rB = max(1e3 * T.bodyDiameter / 2, rb + 4);
                zExit = rB + 1e3 * T.holderHeight - (rb + 1e3 * T.micRecess);
                rho = max(1e3 * T.micDiameter / 2, 3.6);
                gp = diff(sort(M.portX)); sMin = min(gp(gp > 1e-3));
                h1 = M.lift(1) - 2;
                tc.verifyTrue(M.swapRadius == 0 || M.swapRadius >= 1, id);
                if M.swapRadius > 0
                    tc.verifyLessThanOrEqual(M.swapRadius - [0.4 * sMin, h1 / 3, sMin - 2 * rho - 1], 1e-9, id);
                    tc.verifyGreaterThanOrEqual(h1 - M.swapRadius, 8 - 1e-9, [id ': 8 mm straight end of the arrow']);
                    tc.verifyGreaterThanOrEqual(M.lift(1) - M.swapRadius, zExit + 1 - 1e-9, [id ': out of the holder']);
                end
            end
            % the same radius in the Tube setup drawing
            M = tim.gui.drawTube3D(tc.ax, g, td);
            tc.verifyEqual(M.swapRadius, 11.6, 'AbsTol', 1e-9);
            % the paths of a step with 3 movers stay between the plug top + 2 mm
            % and their lift, from the old to the new port (lab tube)
            from = [2 1 3 4]; to = [1 3 2 4];
            M = tim.gui.drawTube3D(tc.ax, g, td, from, struct('mode', 'calibration'));
            z0 = M.zHandle + 2;
            for c = 1:3
                xa = M.portX(from(c)); xb = M.portX(to(c));
                P = tim.gui.calSwapPath(xa, xb, z0, M.zHandle + M.lift(c), M.swapRadius);
                tc.verifyGreaterThanOrEqual(min(P(:, 2)), z0);
                tc.verifyLessThanOrEqual(max(P(:, 2)), M.zHandle + M.lift(c));
                tc.verifyEqual(P([1 end], 1), [xa; xb]);
                tc.verifyGreaterThan(size(P, 1), 4, 'rounded');
            end
        end

        function viewOnlyAndKeptRotation(tc)
            [g, td] = tc.lab();
            tim.gui.drawTube3D(tc.ax, g, td);
            tc.verifyEqual(tc.ax.View, [-10 9], 'default view');
            tim.gui.drawTube3D(tc.ax, 'view', 'top');
            tc.verifyEqual(tc.ax.View, [0 90]);
            view(tc.ax, [25 30]);
            tim.gui.drawTube3D(tc.ax, g, td, 1:4, struct('dimensions', false));
            tc.verifyEqual(tc.ax.View, [25 30], 'the user''s rotation is kept');
            tc.verifyEmpty(findobj(tc.ax, '-regexp', 'Tag', '^dim'));
            tc.verifyEqual(tc.textOf('specimenLabel'), 'specimen d = 75 mm', 'thickness also without dimensions');
        end

        function drawsInUiAxes(tc)
            % the GUI draws into uiaxes of a uifigure (1 pt = 1 px there)
            uf = uifigure('Visible', 'off', 'Position', [50 50 1200 500]);
            tc.addTeardown(@() delete(uf));
            ua = uiaxes(uf, 'Position', [1 1 1200 500]);
            [g, td] = tc.lab();
            M = tim.gui.drawTube3D(ua, g, td);
            tc.verifyNumElements(findobj(ua, 'Type', 'hgtransform'), 4);
            tc.verifyEqual(M.portX, [-70 -41 116 145], 'AbsTol', 1e-9);
            t = findall(ua, 'Type', 'text');
            tc.verifyTrue(all(strcmp(get(t, 'BackgroundColor'), 'none')));
            tc.verifyTrue(any(strcmp(get(findobj(ua, 'Tag', 'dim_d', 'Type', 'text'), 'String'), 'd = 75 mm')));
        end
    end

    methods
        function [g, td] = lab(tc)
            % CAD lab tube: s1 29, L1 41, d 75, L2 41, s2 29 mm, bore 29 mm
            g = tc.cfg.geometry; g.xFront = 0; g.xRear = 0.075;
            g.micPositions = [-0.070 -0.041 0.116 0.145];
            td = tc.cfg.tubeDrawing;
        end

        function [g, td] = thin(tc)
            % thin screen in the joint (d = 0)
            g = tc.cfg.geometry; g.xFront = 0; g.xRear = 0;
            g.micPositions = [-0.150 -0.121 0.071 0.100];
            td = tc.cfg.tubeDrawing;
        end

        function L = labels(tc)
            t = findall(tc.ax, 'Type', 'text');
            L = cellfun(@(s) strjoin(cellstr(s), ' '), get(t, 'String'), 'UniformOutput', false);
        end

        function s = textOf(tc, tag)
            t = findall(tc.ax, 'Type', 'text', 'Tag', tag);
            tc.assertNumElements(t, 1, tag);
            s = strjoin(cellstr(t.String), ' ');
        end

        function [x0, x1, zMax] = specimenExtent(tc)
            spec = findobj(tc.ax, 'Tag', 'specimen');
            tc.assertNotEmpty(spec);
            xs = cell2mat(cellfun(@(X) X(:), get(spec, 'XData'), 'UniformOutput', false));
            zs = cell2mat(cellfun(@(Z) Z(:), get(spec, 'ZData'), 'UniformOutput', false));
            x0 = min(xs); x1 = max(xs); zMax = max(zs);
        end
    end
end
