function results = run_tests(which)
%RUN_TESTS Run the automated test suite (simulation only, no hardware needed).
%
%   run_tests            % all tests
%   run_tests('fast')    % skip the end-to-end simulations (incl. the hidden-window app run)
%   results = run_tests(...)
%
%   A text report is written to tests/last_test_report.txt.

if nargin < 1, which = 'all'; end
root = fileparts(mfilename('fullpath'));
addpath(root);
import matlab.unittest.TestSuite
import matlab.unittest.TestRunner
import matlab.unittest.plugins.TestReportPlugin %#ok<NASGU>

suite = TestSuite.fromFolder(fullfile(root, 'tests'));
if strcmpi(which, 'fast')
    suite = suite(~startsWith({suite.Name}, 'TestEndToEnd') & ~endsWith({suite.Name}, 'appSimulationWorkflow'));
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
