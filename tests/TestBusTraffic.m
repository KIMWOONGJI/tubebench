classdef TestBusTraffic < matlab.unittest.TestCase
    %TESTBUSTRAFFIC The instrument bus traffic of a simulated session is unchanged.
    %
    %   WO-001 acceptance: refactoring the instrument drivers must not change
    %   what is sent to the instruments. The scenario below runs a simulated
    %   session through the protocol mocks; tim.instr.mockBusLog records every
    %   SCPI command and response (33220A mock), every REST request with its
    %   body (LAN-XI mock) and every stream open / close, in one ordered log.
    %   It is compared entry by entry with tests/fixtures/bus_traffic_sim.txt.
    %
    %   Scenario (sections '# ...' in the log): connect + prepareAcquisition +
    %   1 s signal check; switching calibration with the simulation default
    %   prompt (repeated configuration I, empty-tube check); one swept-sine
    %   measurement (2 repetitions); one stepped-sine measurement (5 steps,
    %   2 repetitions); one noise measurement; close.
    %
    %   Deterministic: fixed rng seed, SimulatedRig seed 1, mock stream seed
    %   7; the mocks change state at once (one status poll per wait) and the
    %   mock stream delivers a fixed block per read, so every scheduled
    %   generator command falls on the same block. Normalised: the body of
    %   PUT /rest/rec/module/time (the wall-clock time in ms) -> '<time ms>'.
    %   Not logged: stream reads (their number depends on the 0.3 s drain
    %   after a stop) and client time-outs (not sent on the bus).
    %
    %   After an INTENDED change of the bus traffic, regenerate the fixture:
    %       addpath tests; TestBusTraffic.writeFixture()

    properties
        tmp
    end

    methods (TestMethodSetup)
        function setup(tc)
            f = tc.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            tc.tmp = f.Folder;
        end
    end

    methods (Test)
        function trafficUnchanged(tc)
            [actual, info] = TestBusTraffic.record(tc.tmp);
            tc.assertTrue(info.emptyCheckPerformed, 'the scenario covers the empty-tube check (Test E) sweep');
            expected = TestBusTraffic.readFixture();
            msg = TestBusTraffic.firstDifference(expected, actual);
            tc.verifyTrue(isempty(msg), msg);
        end

        function recorderIsOffByDefault(tc)
            % normal simulation use keeps no bus log
            tim.instr.mockBusLog('stop');
            tr = tim.instr.MockScpiTransport();
            tr.query('*IDN?');
            tc.verifyEmpty(tim.instr.mockBusLog('lines'));
            tim.instr.mockBusLog('start');
            stop = onCleanup(@() tim.instr.mockBusLog('stop'));
            tr.write('OUTP OFF'); tr.close();
            tc.verifyEqual(tim.instr.mockBusLog('lines'), {'SCPI > OUTP OFF'; 'SCPI close'});
            clear stop
        end
    end

    methods (Static)
        function [lines, info] = record(folder)
            %RECORD Run the scenario in simulation (files go to folder) and
            %   return the normalised bus log (cellstr column).
            c = tim.app.defaultConfig();                    % simulation mode
            assert(strcmp(c.mode, 'simulation'), 'tim:test:mode', 'The bus-traffic scenario runs in simulation only.');
            c.geometry = c.simulation.Geometry;             % geometry known: the empty-tube check runs
            c.output.dataDir = fullfile(folder, 'data');
            c.output.calibrationDir = fullfile(folder, 'calibration');
            c.excitation.sweep.duration = 1;
            c.excitation.sweep.repetitions = 1;
            c.excitation.stepped = struct('fStart', 200, 'fStop', 4000, 'nPoints', 5, 'spacing', 'log', ...
                'amplitudeVpp', 0.2, 'settleTime', 0.2, 'recordTime', 0.3, 'nBlocks', 4, 'repetitions', 2);
            c.excitation.noise.duration = 2;
            prevRng = rng(1, 'twister');
            restoreRng = onCleanup(@() rng(prevRng));
            tim.instr.mockBusLog('start');
            stopLog = onCleanup(@() tim.instr.mockBusLog('stop'));
            mark = @(txt) tim.instr.mockBusLog('add', '#', txt);
            s = tim.app.MeasurementSession(c);
            closeSession = onCleanup(@() s.close());
            mark('connect + prepareAcquisition + signal check');
            s.connect();
            s.prepareAcquisition();
            s.signalCheck(1);
            mark('switching calibration (simulation default prompt) + empty-tube check');
            cal = tim.app.runCalibration(s);
            mark('swept-sine measurement, 2 repetitions');
            ex = s.Cfg.excitation; ex.sweep.repetitions = 2;
            s.setExcitation(ex);
            s.measure('sweep');
            mark('stepped-sine measurement, 5 steps, 2 repetitions');
            s.measure('stepped');
            mark('noise measurement');
            s.measure('noise');
            mark('close');
            s.close();
            lines = TestBusTraffic.normalise(tim.instr.mockBusLog('stop'));
            info = struct('emptyCheckPerformed', cal.meta.emptyCheck.performed);
            clear closeSession stopLog restoreRng
        end

        function lines = normalise(lines)
            %NORMALISE Replace the timing-dependent values (see class help).
            lines = regexprep(lines, '^(REST PUT /rest/rec/module/time) \d+$', '$1 <time ms>');
        end

        function file = fixtureFile()
            file = fullfile(fileparts(mfilename('fullpath')), 'fixtures', 'bus_traffic_sim.txt');
        end

        function lines = readFixture()
            %READFIXTURE Stored log without the comment lines ('% ...').
            txt = tim.app.readTextUtf8(TestBusTraffic.fixtureFile());
            lines = regexp(txt, '\r?\n', 'split').';
            lines = lines(~startsWith(lines, '%') & ~cellfun(@isempty, lines));
        end

        function writeFixture()
            %WRITEFIXTURE Record the scenario and store it as the fixture
            %   (only after an intended change of the bus traffic).
            folder = tempname; mkdir(folder);
            removeFolder = onCleanup(@() rmdir(folder, 's'));
            lines = TestBusTraffic.record(folder);
            [~, swi] = tim.app.softwareVersion();
            head = {'% Bus traffic of the simulated scenario of tests/TestBusTraffic.m (protocol mocks,'
                '% recorded by tim.instr.mockBusLog). One entry per line: "SCPI > command",'
                '% "SCPI < response", "REST METHOD path [body]", "STREAM open|close", "# section".'
                sprintf('%% Recorded %s with commit %s. Regenerate: TestBusTraffic.writeFixture()', ...
                char(datetime('now'), 'yyyy-MM-dd'), swi.commit)};
            fid = fopen(TestBusTraffic.fixtureFile(), 'w', 'n', 'UTF-8');
            closeFile = onCleanup(@() fclose(fid));
            fprintf(fid, '%s\n', head{:}, lines{:});
            clear closeFile removeFolder
        end

        function msg = firstDifference(expected, actual)
            %FIRSTDIFFERENCE '' if equal, else a readable description of the
            %   first entry that differs (with its section and the entry before).
            n = min(numel(expected), numel(actual));
            i = find(~strcmp(expected(1:n), actual(1:n)), 1);
            if isempty(i)
                msg = '';
                if numel(expected) == numel(actual), return; end
                i = n + 1;
            end
            at = @(L, k) entry(L, k);
            sec = expected(startsWith(expected(1:min(i, end)), '# '));
            if isempty(sec), sec = '(before the first section)'; else, sec = sec{end}(3:end); end
            e = at(expected, i); a = at(actual, i);
            m = min(numel(e), numel(a));
            col = find(e(1:m) ~= a(1:m), 1);                 % first differing character
            if isempty(col), col = m + 1; end
            msg = sprintf(['Bus traffic differs from tests/fixtures/bus_traffic_sim.txt at entry %d ' ...
                '(fixture %d entries, recorded %d), section "%s", character %d:\n' ...
                '  previous: %s\n  expected: %s\n  recorded: %s\n' ...
                'If the change of the bus traffic is intended: TestBusTraffic.writeFixture().'], ...
                i, numel(expected), numel(actual), sec, col, excerpt(at(expected, i - 1), 1), ...
                excerpt(e, col), excerpt(a, col));
        end
    end
end

function t = entry(lines, k)
% entry k of a log, or a marker beyond its ends
if k < 1
    t = '(start of the log)';
elseif k > numel(lines)
    t = '(end of the log)';
else
    t = lines{k};
end
end

function t = excerpt(t, col)
% at most 160 characters of a log entry around character col (long JSON bodies)
if numel(t) <= 160, return; end
i0 = max(1, min(col - 60, numel(t) - 159));
t = [repmat('...', 1, i0 > 1) t(i0:i0 + 159) repmat('...', 1, i0 + 159 < numel(t))];
end
