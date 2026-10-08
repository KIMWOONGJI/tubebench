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
