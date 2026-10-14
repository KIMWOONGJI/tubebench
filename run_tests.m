function results = run_tests(which, action)
%RUN_TESTS Run the automated test suite (simulation only, no hardware needed).
%
%   run_tests            % all tests
%   run_tests('fast')    % skip TestEndToEnd and the hidden-window app simulations
%                        % (TestGui/appSimulationWorkflow, TestGui/combinedDeviceAppSimulationWorkflow,
%                        % TestGuiTwoLoad/twoLoadAppSimulationWorkflow)
%   results = run_tests(...)
%   suite = run_tests(which, 'select')   % the selected tests only, not run (tests/TestSoftwareInfo)
%
%   A text report is written to tests/last_test_report.txt.

if nargin < 1, which = 'all'; end
if nargin < 2, action = 'run'; end
root = fileparts(mfilename('fullpath'));
addpath(root);
import matlab.unittest.TestSuite
import matlab.unittest.TestRunner
import matlab.unittest.plugins.TestReportPlugin %#ok<NASGU>

suite = TestSuite.fromFolder(fullfile(root, 'tests'));
if strcmpi(which, 'fast')
    % every hidden-window app run, whatever the case of its first letter
    suite = suite(~startsWith({suite.Name}, 'TestEndToEnd') & ~endsWith(lower({suite.Name}), 'appsimulationworkflow'));
end
if strcmpi(action, 'select')
    results = suite;
    return
end
runner = TestRunner.withTextOutput('Verbosity', 2);
results = runner.run(suite);

% ---- report
fid = fopen(fullfile(root, 'tests', 'last_test_report.txt'), 'w');
fprintf(fid, 'Test report  %s\nMATLAB %s\n%s\n\n', char(datetime('now')), version, tim.app.softwareVersion());
for r = results(:).'
    st = 'PASSED';
    if r.Failed, st = 'FAILED'; elseif r.Incomplete, st = 'INCOMPLETE'; end
    fprintf(fid, '%-10s %7.2f s  %s\n', st, r.Duration, r.Name);
end
fprintf(fid, '\nTotal: %d, passed: %d, failed: %d, incomplete: %d\n', numel(results), ...
    nnz([results.Passed]), nnz([results.Failed]), nnz([results.Incomplete]));
fprintf(fid, ['\nNOTE: all tests run in SIMULATION. They verify software behaviour, ' ...
    'not the physical accuracy of the measurement system.\n']);
fclose(fid);
disp(table(results));
end
