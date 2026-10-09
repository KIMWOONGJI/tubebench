classdef TestTube3D < matlab.unittest.TestCase
    %TESTTUBE3D 3D tube drawing (tim.gui.drawTube3D) of the Tube setup and
    %   calibration views: returned struct, transparent annotation texts (no
    %   white boxes), GENERIC specimen (thick block / thin plate), calibration
    %   mode with the empty section, dimension values never crossed by an
    %   extension line and never overlapping each other (user requests
    %   2026-10-09). Invisible figures only.

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
        function returnedStruct(tc)
            % fields used by TubeApp (calibration animation, labels, glow)
            [g, td] = tc.lab();
            M = tim.gui.drawTube3D(tc.ax, g, td, [2 1 3 4]);
            for f = {'micGroup', 'micLabel', 'micX0', 'portX', 'portLabel', 'lift', 'zHandle', ...
                    'labelSide', 'labelGap', 'glow', 'mapping'}
                tc.verifyTrue(isfield(M, f{1}), f{1});
            end
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
