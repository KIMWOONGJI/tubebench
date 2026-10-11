classdef TestBusTraffic < matlab.unittest.TestCase
    %TESTBUSTRAFFIC The instrument bus traffic of a simulated session is unchanged.
    %
    %   WO-001 acceptance: refactoring the instrument drivers must not change
    %   what is sent to the instruments. The scenarios below run a simulated
    %   session through the protocol mocks; tim.instr.mockBusLog records every
    %   SCPI command and response (33220A mock), every REST request with its
    %   body (LAN-XI mock) and every stream open / close, in one ordered log.
    %   Each log is compared entry by entry with its fixture.
    %
    %   Normal path (tests/fixtures/bus_traffic_sim.txt, sections '# ...' in
    %   the log): connect + prepareAcquisition + 1 s signal check; switching
    %   calibration with the simulation default prompt (repeated configuration
    %   I, empty-tube check); one swept-sine measurement (2 repetitions); one
    %   stepped-sine measurement (5 steps, 2 repetitions); one noise
    %   measurement; close.
    %
    %   Fault paths (tests/fixtures/bus_traffic_faults_sim.txt): the stream
    %   stalls in the middle of a sweep (error raised by the acquisition
    %   driver); operator Stop in the middle of a sweep; the operator cancels
    %   the excitation confirmation; the loudspeaker power limit refuses the
    %   drive; the window is closed twice inside a sweep (output off +
    %   close(true) from inside the acquisition). The error that ends each
    %   scenario is part of the log ('# -> error <identifier>'). These are the
    %   Stop / output-off paths WO-001 §6.2 names as the highest refactoring
    %   risk: an intended change of their order is an explicit, owner-approved
    %   fixture update. First recorded on the code before WO-001 changed the
    %   drivers; regenerated on 2026-10-11 with the owner's approval (D24: the
    %   session sets AbortFcn, so OUTP OFF comes before the REST stop on the
    %   abnormal end of an acquisition; outputOffBeforeTheStopOnAnAbnormalEnd),
    %   with no hand edit left. A Stop during the LAN-XI connect step
    %   (stopDuringConnectReturnsTheModuleToIdle) is checked against an
    %   explicit list: the status request moved from the window's close to the
    %   driver (review of 2026-10-11; order approved by the owner 2026-10-11).
    %
    %   Deterministic: fixed rng seed, SimulatedRig seed 1, mock stream seed
    %   7; the mocks change state at once (one status poll per wait) and the
    %   mock stream delivers a fixed block per read, so every scheduled
    %   generator command falls on the same block. Faults are placed on the
    %   number of samples the virtual rig has produced, not on wall-clock
    %   time. Normalised: the body of PUT /rest/rec/module/time (the
    %   wall-clock time in ms) -> '<time ms>'. Not logged: stream reads (their
    %   number depends on the 0.3 s drain after a stop) and client time-outs
    %   (not sent on the bus).
    %
    %   After an INTENDED, owner-approved change of the bus traffic, regenerate
    %   a fixture (an optional note goes into its header):
    %       addpath tests; TestBusTraffic.writeFixture()           % normal path
    %       addpath tests; TestBusTraffic.writeFixture('faults')   % fault paths

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

        function faultTrafficUnchanged(tc)
            [actual, info] = TestBusTraffic.recordFaults(tc.tmp);
            tc.assertEqual(info.errors, {'tim:lanxi:streamStalled', 'tim:session:stopped', ...
                'tim:session:notConfirmed', 'tim:session:speakerPower', 'tim:instr:closed'}, ...
                'every fault scenario ends with its error (closing inside the sweep: tim:instr:closed)');
            expected = TestBusTraffic.readFixture('faults');
            msg = TestBusTraffic.firstDifference(expected, actual, 'faults');
            tc.verifyTrue(isempty(msg), msg);
        end

        function registryConnectSendsTheSame(tc)
            % tim.instr.create (used by the session from WO-001 stage B) sends
            % exactly what MeasurementSession.connect sends, and reports the
            % same checklist steps
            c = TestBusTraffic.scenarioConfig(tc.tmp);
            steps = cell(0, 3);
            function record(key, state, detail)
                steps(end + 1, :) = {key, state, detail};
            end
            tim.instr.mockBusLog('start');
            stopLog = onCleanup(@() tim.instr.mockBusLog('stop'));
            s = tim.app.MeasurementSession(c);
            s.ProgressCallback = @record;
            s.connect();
            viaSession = tim.instr.mockBusLog('lines'); stepsSession = steps;
            s.close();
            tim.instr.mockBusLog('start'); steps = cell(0, 3);
            ctx = struct('mode', 'simulation', 'rig', tim.sim.SimulatedRig(c), 'progress', @record);
            src = tim.instr.create('source', c, ctx);
            acq = tim.instr.create('acquisition', c, ctx, src);
            viaRegistry = tim.instr.mockBusLog('lines');
            src.close(); acq.close();
            tc.verifyEqual(viaRegistry, viaSession, 'same requests in the same order');
            tc.verifyEqual(steps, stepsSession, 'same checklist steps and texts');
            expected = TestBusTraffic.readFixture();
            n = numel(viaRegistry);
            tc.verifyEqual(viaRegistry, expected(2:n + 1), 'the connect section of the fixture');
            tc.verifyEqual(expected{n + 2}, 'REST GET /rest/rec/module/info', 'prepareAcquisition follows');
            clear stopLog
        end

        function stopDuringConnectReturnsTheModuleToIdle(tc)
            % operator Stop while the LAN-XI connect step runs (after module/info
            % answered): the driver returns the module to Idle (status request)
            % before the error propagates, as the object is never returned. The
            % code before WO-001 sent the same request from the window's
            % close(true), after the generator's close lines; now it comes before
            % them - an intended change of order (review 2026-10-11, approved by
            % the owner 2026-10-11), checked here; the faults fixture has no
            % scenario of the connect step
            c = TestBusTraffic.scenarioConfig(tc.tmp);
            tim.instr.mockBusLog('start');
            stopLog = onCleanup(@() tim.instr.mockBusLog('stop'));
            s = tim.app.MeasurementSession(c);
            s.ProgressCallback = @(key, state, detail) stopWhen(s, key, state, 'lanxi', 'ok');
            tc.verifyError(@() s.connect(), 'tim:session:stopped');
            s.close(true);                                   % the window after a failed connection
            actual = tim.instr.mockBusLog('stop');
            expected = TestBusTraffic.readFixture();
            k = find(strcmp(expected, 'REST GET /rest/rec/module/info'), 1);
            tc.verifyEqual(actual, [expected(2:k); {'REST GET /rest/rec/onchange'; 'SCPI > OUTP OFF'; ...
                'SCPI > SWE:STAT OFF'; 'SCPI > SYST:LOC'; 'SCPI close'}], ...
                'connect up to module/info, the status request of the driver, then the generator closed');
            clear stopLog
        end

        function outputOffBeforeTheStopOnAnAbnormalEnd(tc)
            % D24 (approved by the owner 2026-10-11): connect sets the
            % acquisition's AbortFcn = @() Gen.outputOff(), so on the abnormal
            % end of an acquisition the generator output goes off BEFORE the
            % LAN-XI stop request - after a stalled stream (error of the driver)
            % and after a Stop (error out of onBlock, after the session's own
            % OUTP OFF) - and the session's disarm follows the stop sequence.
            % Before D24 both OUTP OFF of the error path came after STREAM close.
            c = TestBusTraffic.scenarioConfig(tc.tmp);
            quiet = warning('off', 'tim:emergency');
            restoreWarn = onCleanup(@() warning(quiet));
            s = tim.app.MeasurementSession(c);
            closeSession = onCleanup(@() s.close());
            s.connect(); s.prepareAcquisition();
            tc.verifyClass(s.Daq.AbortFcn, 'function_handle', 'set by connect');
            midSweep = round((c.excitation.sweep.preRoll + 0.5 * c.excitation.sweep.duration) * c.acquisition.sampleRate);
            tim.instr.mockBusLog('start');
            stopLog = onCleanup(@() tim.instr.mockBusLog('stop'));
            s.Daq.Http.StreamOptions = struct('StopAfterSamples', midSweep);
            tc.verifyError(@() s.measure('sweep'), 'tim:lanxi:streamStalled');
            s.Daq.Http.StreamOptions = struct();
            stalled = tim.instr.mockBusLog('lines');
            tim.instr.mockBusLog('start');
            atSample(s, midSweep, @() s.requestStop());
            tc.verifyError(@() s.measure('sweep'), 'tim:session:stopped');
            s.BlockCallback = [];
            stopped = tim.instr.mockBusLog('stop');
            afterTrigger = @(L) L(find(strcmp(L, 'SCPI > *TRG'), 1, 'last') + 1:end);
            stopSequence = {'REST PUT /rest/rec/measurements/stop'; 'REST GET /rest/rec/onchange'; 'STREAM close'};
            tc.verifyEqual(afterTrigger(stalled), [{'SCPI > OUTP OFF'}; stopSequence; {'SCPI > OUTP OFF'}], ...
                'stalled stream: output off (AbortFcn), the stop sequence, then the disarm');
            tc.verifyEqual(afterTrigger(stopped), [{'SCPI > OUTP OFF'; 'SCPI > OUTP OFF'}; stopSequence; {'SCPI > OUTP OFF'}], ...
                'Stop: output off (session, then AbortFcn), the stop sequence, then the disarm');
            s.close();
            tc.verifyEmpty(s.Daq.AbortFcn, 'released by close');
            clear stopLog closeSession restoreWarn
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
        function c = scenarioConfig(folder)
            %SCENARIOCONFIG Simulation configuration of the scenarios (files go to folder).
            c = tim.app.defaultConfig();                    % simulation mode
            assert(strcmp(c.mode, 'simulation'), 'tim:test:mode', 'The bus-traffic scenarios run in simulation only.');
            c.geometry = c.simulation.Geometry;             % geometry known: the empty-tube check runs
            c.output.dataDir = fullfile(folder, 'data');
            c.output.calibrationDir = fullfile(folder, 'calibration');
            c.excitation.sweep.duration = 1;
            c.excitation.sweep.repetitions = 1;
            c.excitation.stepped = struct('fStart', 200, 'fStop', 4000, 'nPoints', 5, 'spacing', 'log', ...
                'amplitudeVpp', 0.2, 'settleTime', 0.2, 'recordTime', 0.3, 'nBlocks', 4, 'repetitions', 2);
            c.excitation.noise.duration = 2;
        end

        function [lines, info] = record(folder)
            %RECORD Run the normal-path scenario in simulation (files go to
            %   folder) and return the normalised bus log (cellstr column).
            c = TestBusTraffic.scenarioConfig(folder);
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

        function [lines, info] = recordFaults(folder)
            %RECORDFAULTS Run the fault-path scenario in simulation (files go to
            %   folder) and return the normalised bus log and info.errors (the
            %   identifier of the error that ended each fault scenario).
            c = TestBusTraffic.scenarioConfig(folder);
            prevRng = rng(1, 'twister');
            restoreRng = onCleanup(@() rng(prevRng));
            tim.instr.mockBusLog('start');
            stopLog = onCleanup(@() tim.instr.mockBusLog('stop'));
            mark = @(txt) tim.instr.mockBusLog('add', '#', txt);
            quiet = warning('off', 'tim:emergency');
            restoreWarn = onCleanup(@() warning(quiet));
            s = tim.app.MeasurementSession(c);
            closeSession = onCleanup(@() s.close());
            fs = c.acquisition.sampleRate;
            midSweep = round((c.excitation.sweep.preRoll + 0.5 * c.excitation.sweep.duration) * fs);
            errors = cell(1, 5);
            mark('connect + prepareAcquisition');
            s.connect();
            s.prepareAcquisition();

            mark('stream stalls in the middle of a sweep (error raised by the acquisition driver)');
            s.Daq.Http.StreamOptions = struct('StopAfterSamples', midSweep);
            errors{1} = measureError(s, mark);
            s.Daq.Http.StreamOptions = struct();

            mark('operator Stop in the middle of a sweep');
            atSample(s, midSweep, @() s.requestStop());
            errors{2} = measureError(s, mark);
            s.BlockCallback = [];

            mark('operator cancels the excitation confirmation');
            s.ExcitationConfirm = @(msg) false;
            errors{3} = measureError(s, mark);
            s.ExcitationConfirm = [];

            mark('loudspeaker power limit below the drive (direct drive, 1 uW limit)');
            s.setAmplifierGain('none (direct drive)', 1);
            s.setLoudspeaker(c.loudspeaker.impedance_ohm, 1e-6);
            errors{4} = measureError(s, mark);
            s.setLoudspeaker(c.loudspeaker.impedance_ohm, c.loudspeaker.maxPower_W);

            mark('window closed twice inside a sweep: output off + close(true) from inside the acquisition');
            atSample(s, midSweep, @() closeFast(s));
            errors{5} = measureError(s, mark);
            s.BlockCallback = [];

            mark('close (session already closed)');
            s.close();
            lines = TestBusTraffic.normalise(tim.instr.mockBusLog('stop'));
            info = struct('errors', {errors});
            clear closeSession restoreWarn stopLog restoreRng
        end

        function lines = normalise(lines)
            %NORMALISE Replace the timing-dependent values (see class help).
            lines = regexprep(lines, '^(REST PUT /rest/rec/module/time) \d+$', '$1 <time ms>');
        end

        function file = fixtureFile(which)
            %FIXTUREFILE Fixture of the normal path ('main', default) or the fault paths ('faults').
            if nargin < 1, which = 'main'; end
            names = struct('main', 'bus_traffic_sim.txt', 'faults', 'bus_traffic_faults_sim.txt');
            file = fullfile(fileparts(mfilename('fullpath')), 'fixtures', names.(which));
        end

        function lines = readFixture(which)
            %READFIXTURE Stored log without the comment lines ('% ...').
            if nargin < 1, which = 'main'; end
            txt = tim.app.readTextUtf8(TestBusTraffic.fixtureFile(which));
            lines = regexp(txt, '\r?\n', 'split').';
            lines = lines(~startsWith(lines, '%') & ~cellfun(@isempty, lines));
        end

        function writeFixture(which, note)
            %WRITEFIXTURE Record a scenario and store it as its fixture (only
            %   after an intended, owner-approved change of the bus traffic):
            %   which = 'main' (default, normal path) or 'faults' (fault paths);
            %   note (char or cellstr, optional): comment lines for the header,
            %   e.g. the approval and the change it records.
            if nargin < 1, which = 'main'; end
            if nargin < 2, note = {}; end
            note = cellstr(note);
            folder = tempname; mkdir(folder);
            removeFolder = onCleanup(@() rmdir(folder, 's'));
            switch which
                case 'main'
                    lines = TestBusTraffic.record(folder);
                    what = 'the simulated normal-path scenario of tests/TestBusTraffic.m (record)';
                    regen = 'TestBusTraffic.writeFixture()';
                case 'faults'
                    lines = TestBusTraffic.recordFaults(folder);
                    what = 'the simulated fault-path scenario of tests/TestBusTraffic.m (recordFaults)';
                    regen = 'TestBusTraffic.writeFixture(''faults'')';
                otherwise
                    error('tim:test:fixture', 'Unknown fixture "%s" (main or faults).', which);
            end
            [~, swi] = tim.app.softwareVersion();
            head = {sprintf('%% Bus traffic of %s', what)
                '% (protocol mocks, recorded by tim.instr.mockBusLog). One entry per line: "SCPI > command",'
                '% "SCPI < response", "REST METHOD path [body]", "STREAM open|close", "# section".'
                sprintf('%% Recorded %s with commit %s. Regenerate: %s', ...
                char(datetime('now'), 'yyyy-MM-dd'), swi.commit, regen)};
            for i = 1:numel(note), head{end + 1, 1} = ['% ' note{i}]; end
            fid = fopen(TestBusTraffic.fixtureFile(which), 'w', 'n', 'UTF-8');
            closeFile = onCleanup(@() fclose(fid));
            fprintf(fid, '%s\n', head{:}, lines{:});
            clear closeFile removeFolder
        end

        function msg = firstDifference(expected, actual, which)
            %FIRSTDIFFERENCE '' if equal, else a readable description of the
            %   first entry that differs (with its section and the entry before).
            if nargin < 3, which = 'main'; end
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
            [~, name, ext] = fileparts(TestBusTraffic.fixtureFile(which));
            regen = 'TestBusTraffic.writeFixture()';
            if ~strcmp(which, 'main'), regen = sprintf('TestBusTraffic.writeFixture(''%s'')', which); end
            msg = sprintf(['Bus traffic differs from tests/fixtures/%s%s at entry %d ' ...
                '(fixture %d entries, recorded %d), section "%s", character %d:\n' ...
                '  previous: %s\n  expected: %s\n  recorded: %s\n' ...
                'If the change of the bus traffic is intended: %s.'], ...
                name, ext, i, numel(expected), numel(actual), sec, col, excerpt(at(expected, i - 1), 1), ...
                excerpt(e, col), excerpt(a, col), regen);
        end
    end
end

function id = measureError(s, mark)
% one sweep that must end with an error; its identifier goes into the log
id = '';
try
    s.measure('sweep');
catch err
    id = err.identifier;
    if isempty(id), id = '(no identifier)'; end
end
if isempty(id), mark('-> no error'); else, mark(['-> error ' id]); end
end

function atSample(s, n, action)
% run action once from the session's block callback when the virtual rig has
% produced n more samples (a fixed block: independent of wall-clock timing)
start = s.Rig.SampleCounter; done = false;
    function check()
        if ~done && s.Rig.SampleCounter - start >= n
            done = true;
            action();
        end
    end
s.BlockCallback = @check;
end

function stopWhen(s, key, state, atKey, atState)
% the operator presses Stop when the checklist step atKey reports atState
if strcmp(key, atKey) && strcmp(state, atState), s.requestStop(); end
end

function closeFast(s)
% what the window does on a second close request (Tubebench.closeNow)
try, s.Gen.outputOff(); catch, end
s.close(true);
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
