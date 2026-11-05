classdef TestFileDialog < matlab.unittest.TestCase
    %TESTFILEDIALOG The file dialogs of the window (1.6.2, owner report
    %   2026-11-05: after Load calibration… the window disappeared for a
    %   moment). The dialog itself needs an operator and is not opened here.

    methods (Test)
        function helperLoadsOnWindows(tc)
            % the standard Windows dialog owned by the window: a .NET helper
            % compiled at run time (no C compiler); elsewhere uigetfile is used
            tc.assumeTrue(ispc, 'Windows only');
            tc.verifyTrue(tim.gui.fileDialog('check'));
        end

        function everyDialogOfTheWindowIsOwned(tc)
            % no uigetfile / uiputfile left in the window: every file dialog
            % goes through tim.gui.fileDialog (also those added later)
            src = fileread(which('tim.gui.Tubebench'));
            code = regexprep(src, '%[^\n]*', '');              % without comments
            tc.verifyEmpty(regexp(code, '\<ui(get|put)file\s*\(', 'once'), ...
                'a file dialog of the window without tim.gui.fileDialog');
            tc.verifyGreaterThanOrEqual(numel(regexp(code, 'tim\.gui\.fileDialog\(')), 5, ...
                'configuration open / save, measurement, calibration, combine');
        end
    end
end
