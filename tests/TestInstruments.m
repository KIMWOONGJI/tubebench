classdef TestInstruments < matlab.unittest.TestCase
    %TESTINSTRUMENTS Drivers against the mock instruments (simulation mode).

    methods (Test)
        %% ---------------- 33220A ----------------
        function generatorConnectsWithOutputOff(tc)
            tr = tim.instr.MockScpiTransport();
            g = tim.instr.Keysight33220A(tr, 'MaxVpp', 1);
            tc.verifyEqual(g.Identity.model, '33220A');
            tc.verifyFalse(g.isOutputOn());
            tc.verifyTrue(any(strcmp(tr.Log, '> OUTP OFF')));
        end

        function sweepConfigurationOrderAndReadback(tc)
            tr = tim.instr.MockScpiTransport();
            g = tim.instr.Keysight33220A(tr, 'MaxVpp', 1);
            s = struct('fStart', 80, 'fStop', 5500, 'duration', 5, 'spacing', 'LOG', 'amplitudeVpp', 0.2);
            g.configureSweep(s);
            L = tr.Log;
            iStat = find(strcmp(L, '> SWE:STAT ON'), 1);
            iSour = find(strcmp(L, '> TRIG:SOUR BUS'), 1);
            iTime = find(startsWith(L, '> SWE:TIME'), 1);
            tc.verifyTrue(iSour < iStat && iTime < iStat, 'SWE:STAT ON must be sent last (manual p.219)');
            tc.verifyFalse(any(startsWith(L, '> APPL')), 'APPLy must never be used');
            tc.verifyFalse(g.isOutputOn());
            tc.verifyEqual(tr.State.SWE_SPAC, 'LOG');
        end

        function outputRequiresExplicitArm(tc)
            tr = tim.instr.MockScpiTransport();
            g = tim.instr.Keysight33220A(tr, 'MaxVpp', 1);
            g.configureSine(1000, 0.1);
            tc.verifyError(@() g.outputOn(), 'tim:gen:notArmed');
            g.armOutput(true); g.outputOn();
            tc.verifyTrue(g.isOutputOn());
            g.armOutput(false);
            tc.verifyFalse(g.isOutputOn(), 'disarming must switch the output off');
        end

        function amplitudeSafetyLimit(tc)
            tr = tim.instr.MockScpiTransport();
            g = tim.instr.Keysight33220A(tr, 'MaxVpp', 0.5);
            tc.verifyError(@() g.configureSine(1000, 0.8), 'tim:gen:amplitude');
            % amplitude changed behind the driver's back -> outputOn refuses
            g.configureSine(1000, 0.3); g.armOutput(true);
            tr.write('VOLT 2');
            tc.verifyError(@() g.outputOn(), 'tim:gen:amplitude');
            tc.verifyFalse(g.isOutputOn());
        end

        function generatorAtTheAmplifierInput(tc)
            % WO-004: the load setting is the amplifier input (1 .. 10000 ohm,
            % manual p.189), sent and read back; MaxVpp limits the OPEN-CIRCUIT
            % voltage: at 600 ohm a level of 0.95 Vpp is 1.03 Vpp open circuit
            tr = tim.instr.MockScpiTransport();
            g = tim.instr.Keysight33220A(tr, 'MaxVpp', 1, 'Load', '600');
            L = tr.Log;
            tc.verifyTrue(any(strcmp(L, '> OUTP:LOAD 600')), 'load sent');
            tc.verifyTrue(any(strcmp(L, '> OUTP:LOAD?')), 'a numeric load is read back');
            tc.verifyEqual(g.metadata().load, '600');
            g.configureSine(1000, 0.9);                                % 0.975 Vpp open circuit
            tc.verifyError(@() g.configureSine(1000, 0.95), 'tim:gen:amplitude', 'open circuit above MaxVpp');
            g.configureSine(1000, 0.9); g.armOutput(true); tr.write('VOLT 0.95');
            tc.verifyError(@() g.outputOn(), 'tim:gen:amplitude', 'the re-check before OUTP ON too');
            tc.verifyFalse(g.isOutputOn());
            % the smallest level scales with the load: 20 mVpp x 600 / 650
            tc.verifyError(@() g.configureSine(1000, 0.018), 'tim:gen:amplitude');
            g.configureSine(1000, 0.019);
            % '600.0' is stored as '600'; 'INF' is unchanged (no read-back query: same bus traffic as 1.2.1)
            tr2 = tim.instr.MockScpiTransport();
            g2 = tim.instr.Keysight33220A(tr2, 'MaxVpp', 1, 'Load', '600.0');
            tc.verifyEqual(g2.Load, '600');
            tr3 = tim.instr.MockScpiTransport();
            tim.instr.Keysight33220A(tr3, 'MaxVpp', 1, 'Load', 'INF');
            tc.verifyFalse(any(strcmp(tr3.Log, '> OUTP:LOAD?')));
            % outside the range or another spelling of INF: refused before any I/O
            for bad = {'0.5', '20000', 'inf', '600 ohm'}
                tr4 = tim.instr.MockScpiTransport();
                tc.verifyError(@() tim.instr.Keysight33220A(tr4, 'MaxVpp', 1, 'Load', bad{1}), 'tim:gen:load', bad{1});
            end
        end

        function scpiErrorsSurface(tc)
            tr = tim.instr.MockScpiTransport();
            g = tim.instr.Keysight33220A(tr, 'MaxVpp', 1);
            tr.InjectError = '-222,"Data out of range"';
            tc.verifyError(@() g.configureSine(1000, 0.1), 'tim:gen:scpiError');
            g.configureSine(1000, 0.1);                       % queue drained -> OK now
            tc.verifyError(@() g.triggerSweep(), 'tim:gen:mode');
            tr.write('*TRG');                                  % not in BUS sweep -> -211
            errs = g.readErrors();
            tc.verifyTrue(any(contains(errs, '-211')));
        end

        function wrongInstrumentRejected(tc)
            tr = tim.instr.MockScpiTransport();
            tr.IdnString = 'Rigol,DG1022,123,1.0';
            tc.verifyError(@() tim.instr.Keysight33220A(tr), 'tim:gen:identity');
        end

        function timeoutPropagates(tc)
            tr = tim.instr.MockScpiTransport();
            g = tim.instr.Keysight33220A(tr, 'MaxVpp', 1);
            tr.FailNextQuery = true;
            tc.verifyError(@() g.identify(), 'tim:scpi:timeout');
            g.close();
            tc.verifyFalse(tr.isOpen());
        end

        function outputGuardOnInterrupt(tc)
            % session output guard (tim.app.outputGuard): an exit that skips
            % try/catch (Ctrl+C) switches the output off and disarms; a
            % dismissed guard sends nothing
            tr = tim.instr.MockScpiTransport();
            g = tim.instr.Keysight33220A(tr, 'MaxVpp', 1);
            g.configureSine(1000, 0.1); g.armOutput(true); g.outputOn();
            guard = tim.app.outputGuard(g);
            n = numel(tr.Log);
            guard.dismiss(); delete(guard);
            tc.verifyEqual(numel(tr.Log), n, 'a dismissed guard sends nothing');
            tc.verifyTrue(g.isOutputOn());
            guard = tim.app.outputGuard(g);
            delete(guard);                                     % destroyed before it was dismissed
            tc.verifyFalse(g.isOutputOn(), 'output switched off');
            tc.verifyFalse(g.OutputArmed, 'output disarmed');
            % the guard as a local variable of a function that ends without dismissing it
            g.armOutput(true); g.outputOn();
            tc.verifyError(@() guardedThenAborted(g), 'test:abort');
            tc.verifyFalse(g.isOutputOn());
            tc.verifyFalse(g.OutputArmed);
            g.close();
        end

        %% ---------------- LAN-XI ----------------
        function lanxiStateMachine(tc)
            [daq, http] = tc.makeDaq();
            c = tc.daqCfg();
            daq.prepare(c);
            tc.verifyEqual(http.State, 'RecorderStreaming');
            tc.verifyEqual(numel(daq.Teds), 4);
            tc.verifyEqual(daq.Teds{2}.typeNumber, '4957');
            [d, info] = daq.acquire(16384);
            tc.verifyEqual(size(d), [16384 4]);
            tc.verifyTrue(info.integrity.ok);
            tc.verifyEqual(http.State, 'RecorderStreaming');
            % wrong-state request is refused like the real module (HTTP 403)
            tc.verifyError(@() http.request('PUT', '/rest/rec/create'), 'tim:lanxi:http');
            daq.shutdown();
            tc.verifyEqual(http.State, 'Idle');
        end

        function lanxiSetupValidation(tc)
            [daq, ~] = tc.makeDaq();
            c = tc.daqCfg(); c.sampleRate = 48000;
            tc.verifyError(@() daq.prepare(c), 'tim:lanxi:rate');
            daq.shutdown();
            c = tc.daqCfg(); c.range = '31.6 Vpeak';
            tc.verifyError(@() daq.prepare(c), 'tim:lanxi:range');
            daq.shutdown();
            c = tc.daqCfg(); c.connector = 'XLR';
            tc.verifyError(@() daq.prepare(c), 'tim:lanxi:connector');
            daq.shutdown();
        end

        function tedsVariants(tc)
            [daq, http] = tc.makeDaq();
            http.TedsPresent = false(1, 4);            % real module: [null,null,null,null]
            daq.prepare(tc.daqCfg());
            tc.verifyEqual(numel(daq.Teds), 4);
            tc.verifyTrue(all(cellfun(@isempty, daq.Teds)));
            daq.shutdown();
            http.TedsPresent = [true false true false];
            daq.prepare(tc.daqCfg());
            tc.verifyEqual(cellfun(@isempty, daq.Teds), [false true false true]);
            daq.shutdown();
        end

        function streamFaults(tc)
            % random chunking: must be transparent
            [daq, http] = tc.makeDaq();
            http.StreamOptions = struct('RandomChunking', true, 'ShuffleSignals', true);
            daq.prepare(tc.daqCfg());
            [~, info] = daq.acquire(8192);
            tc.verifyTrue(info.integrity.ok);
            daq.shutdown();
            % corruption: data loss must be reported as FATAL integrity error
            http.StreamOptions = struct('CorruptEvery', 5);
            daq.prepare(tc.daqCfg());
            [~, info] = daq.acquire(8192);
            tc.verifyFalse(info.integrity.ok);
            daq.shutdown();
            % interruption: acquisition must stop with an error and the
            % module must be returned to a stopped state
            http.StreamOptions = struct('StopAfterSamples', 4096);
            daq.prepare(tc.daqCfg());
            tc.verifyError(@() daq.acquire(16384, [], 30), 'tim:lanxi:streamStalled');
            tc.verifyEqual(http.State, 'RecorderStreaming');
            daq.shutdown();
            tc.verifyEqual(http.State, 'Idle');
        end

        function lanxiStartFailureReleasesTheStream(tc)
            % audit 2026-10-11: a fault while a recording starts (the POST, or its
            % reply lost after the module executed it) closes the data stream,
            % stops a recording the module started and leaves the driver ready
            [daq, http] = tc.makeDaq();
            daq.prepare(tc.daqCfg());
            aborted = 0;
            daq.AbortFcn = @() countAbort();
            function countAbort(), aborted = aborted + 1; end
            http.FailPath = '/rest/rec/measurements';           % the request never reached the module
            tc.verifyError(@() daq.acquire(4096), 'tim:lanxi:network');
            tc.verifyFalse(daq.isAcquiring(), 'stream closed after the failed start');
            tc.verifyTrue(http.ActiveStream.Closed);
            tc.verifyEqual(aborted, 1, 'AbortFcn on the abnormal end');
            tc.verifySize(daq.acquire(4096), [4096 4], 'the next acquisition works');
            http.LoseReplyPath = '/rest/rec/measurements';      % executed, reply lost
            tc.verifyError(@() daq.acquire(4096), 'tim:lanxi:network');
            tc.verifyEqual(http.State, 'RecorderStreaming', 'the recording the module started was stopped');
            tc.verifyFalse(daq.isAcquiring());
            tc.verifySize(daq.acquire(4096), [4096 4], 'the next acquisition works');
            % the module left RecorderStreaming outside the driver: the refused
            % start leaves no data of the previous acquisition to collect
            http.request('PUT', '/rest/rec/finish');
            tc.verifyError(@() daq.acquire(4096), 'tim:lanxi:state');
            tc.verifyError(@() daq.collect(), 'tim:stream:missingSignal', ...
                'no samples of the previous acquisition as partial data');
            daq.shutdown();
        end

        function scpiLateReplyIsNotTakenAsTheNextAnswer(tc)
            % audit 2026-10-11: a reply that arrives after its query timed out
            % (e.g. OUTP? with the window's 1 s) is discarded, before or after
            % the next query is written; a local fake instrument (127.0.0.1 only)
            srv = []; port = 0;
            for p = 50300 + randperm(200, 20)
                try
                    srv = tcpserver("127.0.0.1", p); port = p; break
                catch
                end
            end
            tc.assumeNotEmpty(srv, 'no free local port for the fake instrument');
            tc.addTeardown(@() delete(srv));
            configureTerminator(srv, "LF");
            fake = struct('silent', "OUTP?", 'lateBeforeIdn', "");
            configureCallback(srv, "terminator", @(s, ~) answer(s));
            function answer(s)
                cmd = strtrim(readline(s));
                if cmd == fake.silent, return; end              % answered later, by the test
                if cmd == "*IDN?" && strlength(fake.lateBeforeIdn) > 0
                    writeline(s, fake.lateBeforeIdn); fake.lateBeforeIdn = "";
                end
                switch cmd
                    case "*IDN?", writeline(s, "Agilent Technologies,33220A,FAKE0001,2.02-2.02-22-2");
                    case "VOLT?", writeline(s, "+1.0000000000000E-01");
                    case "SYST:ERR?", writeline(s, "+0,""No error""");
                end
            end
            % no readline time-out warnings in the test log
            ws = warning('off', 'all'); restore = onCleanup(@() warning(ws));
            tr = tim.instr.ScpiTcpTransport('127.0.0.1', port, 2);
            tc.addTeardown(@() tr.close());
            tc.verifyError(@() tr.query('OUTP?', 0.5), 'tim:scpi:timeout');
            writeline(srv, "0");                                % the late reply arrives
            pause(0.3);
            tc.verifyEqual(tr.query('VOLT?'), '+1.0000000000000E-01', 'late reply already received: discarded');
            tc.verifyEqual(tr.query('SYST:ERR?'), '+0,"No error"');
            tc.verifyError(@() tr.query('OUTP?', 0.5), 'tim:scpi:timeout');
            fake.lateBeforeIdn = "1";                           % arrives after the next query was sent
            tc.verifyEqual(tr.query('VOLT?'), '+1.0000000000000E-01', 'resynchronised after the time-out');
            tc.verifyEqual(tr.query('SYST:ERR?'), '+0,"No error"');
            log = tr.Log(:, 3);
            tc.verifyTrue(any(startsWith(log, '(late reply discarded) 0')));
            tc.verifyTrue(any(startsWith(log, '(late reply discarded) 1')));
        end

        function scpiConnectionDroppedAndReopened(tc)
            % WO-003 (hardware check 2026-10-12: the 33220A drops an idle
            % connection): when the instrument side closes the connection, the
            % next query fails with an English error of the transport (no MATLAB
            % text) and never hangs; reopen() connects again and the queries are
            % answered; a local fake instrument (127.0.0.1 only)
            port = 0; srv = [];
            for p = 50500 + randperm(200, 20)
                try
                    srv = tcpserver("127.0.0.1", p); port = p; break
                catch
                end
            end
            tc.assumeNotEmpty(srv, 'no free local port for the fake instrument');
            servers = containers.Map('KeyType', 'double', 'ValueType', 'any');
            servers(1) = srv;
            tc.addTeardown(@() deleteServers(servers));
            configureTerminator(srv, "LF");
            configureCallback(srv, "terminator", @(s, ~) answerFake(s));
            ws = warning('off', 'all'); restore = onCleanup(@() warning(ws));
            tr = tim.instr.ScpiTcpTransport('127.0.0.1', port, 2);
            tc.addTeardown(@() tr.close());
            tc.verifyEqual(tr.query('OUTP?'), '0');
            delete(srv);                                       % the instrument drops the connection
            pause(0.3);
            t0 = tic; id = '';
            try
                tr.query('OUTP?');
            catch err
                id = err.identifier;
                tc.verifyFalse(contains(err.message, char([54620 51116])), 'English text');   % (no Korean MATLAB message)
            end
            tc.verifyLessThan(toc(t0), 4, 'bounded by the time-out');
            tc.verifyTrue(any(strcmp(id, {'tim:scpi:connectionLost', 'tim:scpi:timeout'})), ...
                sprintf('the dropped connection is reported (%s)', id));
            srv2 = tcpserver("127.0.0.1", port);               % the instrument listens again
            servers(2) = srv2; %#ok<NASGU> (a handle: the teardown deletes it)
            configureTerminator(srv2, "LF");
            configureCallback(srv2, "terminator", @(s, ~) answerFake(s));
            tr.reopen();
            tc.verifyTrue(tr.isOpen());
            tc.verifyEqual(tr.query('OUTP?'), '0', 'answered on the new connection');
            tc.verifyTrue(any(startsWith(tr.Log(:, 3), 're-opening the connection to 127.0.0.1')));
            clear restore
        end

        function scpiConnectFailureIsEnglish(tc)
            % hardware check of 1.2.1 (2026-10-12, LAN cable pulled): the window
            % showed MATLAB's own text of the failed connection (Korean, with a
            % help link); the error is now English only (the text goes to the log)
            port = 0;
            for p = 50900 + randperm(90, 20)
                try
                    srv = tcpserver("127.0.0.1", p); delete(srv); port = p; break   % free, nobody listening
                catch
                end
            end
            tc.assumeGreaterThan(port, 0, 'no free local port');
            try
                tim.instr.ScpiTcpTransport('127.0.0.1', port, 1);
                tc.verifyFail('the connection must fail');
            catch err
                tc.verifyEqual(err.identifier, 'tim:scpi:connect');
                tc.verifyTrue(all(double(err.message) < 128), ['ASCII only: ' err.message]);
                tc.verifyFalse(contains(err.message, '<'), 'no help link');
            end
        end

        function generatorReplacesAnIdleConnection(tc)
            % owner decision 2026-10-12 (WO-003): a connection idle for more
            % than ReopenAfterIdle_s is replaced before use - nothing is sent on
            % it (the 33220A may have dropped it: a reset, and MATLAB's stack
            % trace in the command window); a connection used recently is only
            % checked with OUTP?; a local fake instrument (127.0.0.1 only)
            port = 0; srv = [];
            for p = 50700 + randperm(200, 20)
                try
                    srv = tcpserver("127.0.0.1", p); port = p; break
                catch
                end
            end
            tc.assumeNotEmpty(srv, 'no free local port for the fake instrument');
            tc.addTeardown(@() delete(srv));
            configureTerminator(srv, "LF");
            configureCallback(srv, "terminator", @(s, ~) answerFake(s));
            ws = warning('off', 'all'); restore = onCleanup(@() warning(ws));
            tr = tim.instr.ScpiTcpTransport('127.0.0.1', port, 2);
            g = tim.instr.Keysight33220A(tr, 'MaxVpp', 1);
            tc.addTeardown(@() g.close());
            tc.verifyEqual(g.ReopenAfterIdle_s, 30, 'default');
            nQueries = @() nnz(strcmp(tr.Log(:, 3), 'OUTP?'));
            n = nQueries();
            r = g.checkConnection();
            tc.verifyEqual(r.state, 'ok', 'used just now: checked');
            tc.verifyEqual(nQueries(), n + 1, 'with OUTP?');
            g.ReopenAfterIdle_s = 0.2;
            pause(0.5);
            tc.verifyGreaterThan(tr.idleSeconds(), 0.2);
            n = nQueries();
            r = g.checkConnection();
            tc.verifyEqual(r.state, 'reopened', 'idle: replaced');
            tc.verifySubstring(r.detail, 'output off');
            tc.verifyEqual(nQueries(), n, 'nothing sent on the idle connection');
            L = tr.Log(:, 3);
            k = find(startsWith(L, 're-opening the connection'), 1, 'last');
            tc.verifyNotEmpty(k);
            tc.verifyEqual(L(k + 1:k + 2), {'*IDN?'; 'Agilent Technologies,33220A,FAKE0001,2.02-2.02-22-2'}, ...
                'the same instrument asked first');
            tc.verifyTrue(any(strcmp(L(k:end), 'OUTP OFF')) && any(strcmp(L(k:end), 'OUTP:LOAD INF')), 'safe state again');
            tc.verifyLessThan(tr.idleSeconds(), 0.2, 'the new connection was just used');
            tc.verifyFalse(g.isOutputOn(), 'answered on the new connection');
            clear restore
        end

        function overloadDetected(tc)
            cfg = tim.app.defaultConfig();
            cfg.geometry = cfg.simulation.Geometry;
            rig = tim.sim.SimulatedRig(cfg);
            rig.SourceGain = 2e4;                         % absurd level -> clipping
            http = tim.instr.MockLanXiHttp(rig);
            daq = tim.instr.LanXi(http, @(h, p) http.openStream(h, p), 'Host', 'mock');
            daq.Verbose = false;
            g = struct('OUTP', 1, 'FUNC', 'SIN', 'FREQ', 500, 'VOLT', 1, 'FREQ_STAR', 100, ...
                'FREQ_STOP', 1000, 'SWE_SPAC', 'LIN', 'SWE_TIME', 1, 'SWE_STAT', 0, 'TRIG_SOUR', 'IMM');
            rig.setGeneratorState(g);
            daq.prepare(tc.daqCfg());
            [~, info] = daq.acquire(16384);
            tc.verifyFalse(info.integrity.ok);
            tc.verifyTrue(any(contains(info.integrity.fatal, 'CLIPPED')));
            daq.shutdown();
        end
    end

    methods
        function [daq, http] = makeDaq(~)
            cfg = tim.app.defaultConfig();
            cfg.geometry = cfg.simulation.Geometry;
            rig = tim.sim.SimulatedRig(cfg);
            http = tim.instr.MockLanXiHttp(rig);
            daq = tim.instr.LanXi(http, @(h, p) http.openStream(h, p), 'Host', 'mock');
            daq.Verbose = false;
            daq.StateTimeout = 2;
        end
        function c = daqCfg(~)
            c = struct('sampleRate', 16384, 'range', '10 Vpeak', 'filter', '0.7 Hz', 'ccld', true(1, 4), ...
                'channels', 1:4, 'detectTeds', true, 'connector', 'BNC', 'names', {{'M1', 'M2', 'M3', 'M4'}});
        end
    end
end

function guardedThenAborted(gen)
% an output guard that goes out of scope without dismiss (as on Ctrl+C,
% where only destructors and onCleanup objects run)
guard = tim.app.outputGuard(gen); %#ok<NASGU>
error('test:abort', 'aborted inside the measurement');
end

function answerFake(s)
% fake 33220A on 127.0.0.1 (scpiConnectionDroppedAndReopened,
% generatorReplacesAnIdleConnection). Every complete line received is
% answered: MATLAB may call the terminator callback once for several lines
% that arrived together (the driver sends OUTP OFF, OUTP:LOAD INF, SYST:ERR?
% right after a reopen), and a callback that read only one line left
% SYST:ERR? unanswered - generatorReplacesAnIdleConnection then failed in the
% owner's desktop MATLAB, where events are processed later (2026-10-13)
while s.NumBytesAvailable > 0
    cmd = strtrim(readline(s));
    switch cmd
        case "*IDN?", writeline(s, "Agilent Technologies,33220A,FAKE0001,2.02-2.02-22-2");
        case "OUTP?", writeline(s, "0");
        case "SYST:ERR?", writeline(s, "+0,""No error""");
    end
end
end

function deleteServers(m)
% the fake instruments of a test (containers.Map of tcpserver objects)
k = keys(m);
for i = 1:numel(k)
    try, delete(m(k{i})); catch, end
end
end
