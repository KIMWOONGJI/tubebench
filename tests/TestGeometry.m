classdef TestGeometry < matlab.unittest.TestCase
    %TESTGEOMETRY Coordinates [m] <-> distances [mm] without binary residue
    %   (user report 2026-10-09: s1/s2 showed 29.000000000000004 /
    %   28.999999999999986 while editing, although the CAD ports are exactly
    %   29 mm apart).

    methods (Test)
        function residueExists(tc)
            % documents the cause: these are NOT exactly 29 / 0.116 in IEEE doubles
            x = [-0.070 -0.041 0.116 0.145];
            tc.verifyNotEqual(1e3 * (x(2) - x(1)), 29);
            tc.verifyNotEqual(1e3 * (x(4) - x(3)), 29);
            tc.verifyNotEqual(0.075 + 0.041, 0.116);
        end

        function roundGeometrySnapsToDecimals(tc)
            g = struct('diameter', 29 / 1e3, 'micPositions', [-0.041 - 0.029, -0.041, 0.075 + 0.041, 0.075 + 0.041 + 0.029], ...
                'spacingUp', 29.000000000000004 / 1e3, 'spacingDown', 28.999999999999986 / 1e3, ...
                'xFront', 0, 'xRear', 0.075, 'note', 'CAD');
            r = tim.app.roundGeometry(g);
            tc.verifyEqual(r.micPositions, [-0.070 -0.041 0.116 0.145]);          % bit-exact
            tc.verifyEqual([r.spacingUp r.spacingDown r.diameter], [0.029 0.029 0.029]);
            tc.verifyEqual(r.note, 'CAD');
            tc.verifyLessThanOrEqual(max(abs(r.micPositions - g.micPositions)), 1e-12);   % only residue removed
            g.xRear = 0.0751234567; r = tim.app.roundGeometry(g);
            tc.verifyEqual(r.xRear, 0.075123457);                                   % 1 nm grid
            g.micPositions = nan(1, 4); g.xFront = NaN; g.xRear = NaN;
            r = tim.app.roundGeometry(g);
            tc.verifyTrue(all(isnan([r.micPositions r.xFront r.xRear])));
            tc.verifySize(r.micPositions, [1 4]);
        end

        function saveConfigWritesCleanGeometry(tc)
            f = tc.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            c = tim.app.defaultConfig();
            c.geometry.xFront = 0; c.geometry.xRear = 0.075;
            c.geometry.micPositions = [-0.041 - 0.029, -0.041, 0.075 + 0.041, 0.075 + 0.041 + 0.029];
            file = fullfile(f.Folder, 'c.json');
            tim.app.saveConfig(c, file);
            geo = regexp(fileread(file), '"geometry":\s*\{[^}]*\}', 'match', 'once');
            tc.verifyNotEmpty(geo);
            tc.verifyEmpty(regexp(geo, '\d(0{6,}|9{6,})\d', 'once'), geo);
            c2 = tim.app.loadConfig(file);
            tc.verifyEqual(c2.geometry.micPositions, [-0.070 -0.041 0.116 0.145]);
            tc.verifyEqual(c2.geometry.note, c.geometry.note);
        end
    end
end
