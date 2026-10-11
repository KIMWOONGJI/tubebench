classdef TestSessionHardwareMode < matlab.unittest.TestCase
    %TESTSESSIONHARDWAREMODE The hardware-only branches of the measurement session, with no I/O.
    %
    %   Owner decision 2026-10-11 (audit: the suite ran only simulation-mode
    %   sessions, so every hardware branch of tim.app.MeasurementSession was
    %   unexecuted). A session in mode 'hardware' runs on the test-only
    %   drivers tests/support/FakeHardwareSource and FakeHardwareDaq: the
    %   unchanged 33220A and LAN-XI drivers on their protocol mocks on a
    %   virtual rig. noNetworkOrDeviceIo proves that no socket or HTTP
    %   connection is opened; the other tests cover the branches that exist
    %   only in hardware mode: the settle step of the inputs, the
    %   amplifier-gain gate (tim:session:gainRequired) and the excitation
    %   confirmation in the command window (consoleConfirm). The instrument
    %   addresses are 127.0.0.1 as well, so not even a missed check could
    %   reach a lab instrument.

    properties
        cfg
        tmp
    end

    methods (TestMethodSetup)
        function setup(tc)
            f = tc.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            tc.tmp = f.Folder;
            tc.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(fileparts(mfilename('fullpath')), 'support')));
            tim.instr.drivers('add', struct('name', 'fakehwsource', 'class', 'FakeHardwareSource'));
            tim.instr.drivers('add', struct('name', 'fakehwdaq', 'class', 'FakeHardwareDaq'));
            tc.addTeardown(@() tim.instr.drivers('remove', 'fakehwsource'));
            tc.addTeardown(@() tim.instr.drivers('remove', 'fakehwdaq'));
            tc.addTeardown(@() FakeHardwareSource.rig([]));
            c = tim.app.defaultConfig();
            c.mode = 'hardware';
            c.generator.driver = 'fakehwsource'; c.daq.driver = 'fakehwdaq';
            c.generator.fakehwsource = struct('host', '127.0.0.1');   % never an instrument address
            c.daq.fakehwdaq = struct('host', '127.0.0.1');
            c.generator.keysight33220a.host = '127.0.0.1';
            c.daq.lanxi.host = '127.0.0.1';
            c.geometry = c.simulation.Geometry;
            % absolute folders: in hardware mode a relative folder is data\ itself
            % (an emergency file of a failed measurement would go there)
            c.output.dataDir = fullfile(tc.tmp, 'data'); c.output.calibrationDir = fullfile(tc.tmp, 'cal');
            c.excitation.sweep.duration = 1; c.excitation.sweep.repetitions = 1;
            c.acquisition.settleTime = 0.3;
            c.amplifier.model = 'none (direct drive)'; c.amplifier.gainFactor = 1; c.amplifier.gain_dB = 0;
            tc.cfg = c;
        end
    end

    methods
        function s = session(tc, c)
            % a session on the fakes; a command-window prompt that a test does
            % not expect fails at once instead of waiting for a keyboard
            if nargin < 2, c = tc.cfg; end
            s = tim.app.MeasurementSession(c);
            tc.addTeardown(@() delete(s));
            s.ConsoleInput = @(varargin) error('tim:test:console', 'Unexpected command-window prompt.');
        end
    end

    methods (Test)
        function noNetworkOrDeviceIo(tc)
            % (1) the fakes name no real transport and build their base driver
            % on its mocks; (2) the instruments of a hardware-mode session talk
            % to the protocol mocks: the SCPI transport, the REST client and the
            % data stream are the mock classes; (3) the commands of a whole
            % session (connect, prepare, measure, close) reached the mocks
            here = fullfile(fileparts(mfilename('fullpath')), 'support');
            for f = {'FakeHardwareSource.m', 'FakeHardwareDaq.m'}
                code = regexprep(tim.app.readTextUtf8(fullfile(here, f{1})), '%[^\n]*', '');   % without comments
                hit = regexp(code, ['ScpiTcpTransport|(?<!Mock)LanXiHttp|LanXiTcpStream|tcpclient|tcpip|tcpserver|' ...
                    'udpport|serialport|webread|webwrite|websave|urlread|matlab\.net|java\.net|http'], 'match', 'once');
                tc.verifyEmpty(hit, sprintf('%s names a real transport: %s', f{1}, hit));
                tc.verifySubstring(code, 'ctx.mode = ''simulation''', [f{1} ': the base driver is built on its mocks']);
            end
            tim.instr.mockBusLog('start');
            tc.addTeardown(@() tim.instr.mockBusLog('stop'));
            s = tc.session();
            s.ExcitationConfirm = @(msg) true;
            s.connect(); s.prepareAcquisition();
            tc.verifyEqual(s.Cfg.mode, 'hardware');
            tc.verifyEmpty(s.Rig, 'a hardware-mode session has no virtual rig of its own');
            tc.verifyClass(s.Gen.Transport, 'tim.instr.MockScpiTransport');
            tc.verifyClass(s.Daq.Http, 'tim.instr.MockLanXiHttp');
            m = s.measure('sweep');
            tc.verifyTrue(m.integrityOk);
            tc.verifyEqual(m.metadata.mode, 'hardware');
            tc.verifyClass(s.Daq.LastStream.Inner, 'tim.instr.MockLanXiStream', 'the data stream');
            s.close();
            bus = tim.instr.mockBusLog('stop');
            tc.verifyTrue(any(startsWith(bus, 'SCPI > *IDN?')), 'identification sent to the SCPI mock');
            tc.verifyTrue(any(startsWith(bus, 'SCPI > OUTP ON')), 'the excitation switched on at the SCPI mock');
            tc.verifyTrue(any(startsWith(bus, 'REST GET /rest/rec/module/info')), 'REST requests to the mock');
            tc.verifyTrue(any(startsWith(bus, 'STREAM open port')), 'the data stream of the mock');
        end

        function inputsSettleOnlyInHardwareMode(tc)
            % prepareAcquisition waits acquisition.settleTime for the inputs to
            % settle (the driver's text: CCLD + high-pass), in hardware mode only
            steps = struct('key', {}, 'state', {}, 'detail', {}, 't', {});
            t0 = tic;
            s = tc.session();
            s.ProgressCallback = @(k, st, d) record(k, st, d);
            s.connect(); s.prepareAcquisition();
            st = steps(strcmp({steps.key}, 'settle'));
            tc.assertNumElements(st, 2);
            tc.verifyEqual({st.state}, {'run', 'ok'});
            tc.verifyEqual(st(1).detail, '0.3 s (CCLD + 0.7 Hz high-pass)');
            tc.verifyGreaterThanOrEqual(st(2).t - st(1).t, 0.29, 'waited acquisition.settleTime');
            tc.verifyTrue(any(contains(s.LogLines, 'Waiting 0.3 s for the inputs to settle (CCLD + 0.7 Hz high-pass)')));
            order = {steps.key};
            tc.verifyGreaterThan(find(strcmp(order, 'settle'), 1), find(strcmp(order, 'sens'), 1, 'last'), ...
                'after the sensitivities, when the inputs are set up');
            tc.verifyTrue(s.Prepared);
            s.close();
            % nothing to wait for
            c = tc.cfg; c.acquisition.settleTime = 0;
            steps(:) = [];
            s = tc.session(c); s.ProgressCallback = @(k, st, d) record(k, st, d);
            s.connect(); s.prepareAcquisition();
            st = steps(strcmp({steps.key}, 'settle'));
            tc.verifyEqual({st.state}, {'skip'});
            tc.verifyEqual(st.detail, 'not needed');
            s.close();
            % the same drivers in simulation mode: no wait
            c = tc.cfg; c.mode = 'simulation';
            steps(:) = [];
            s = tc.session(c); s.ProgressCallback = @(k, st, d) record(k, st, d);
            s.connect(); s.prepareAcquisition();
            st = steps(strcmp({steps.key}, 'settle'));
            tc.verifyEqual({st.state}, {'skip'});
            tc.verifyEqual(st.detail, 'not needed (simulation)');
            function record(k, state, d)
                steps(end + 1) = struct('key', k, 'state', state, 'detail', d, 't', toc(t0));
            end
        end

        function amplifierWithoutGainIsNotDriven(tc)
            % loudspeaker protection: in hardware mode an amplifier without its
            % gain is refused (tim:session:gainRequired) before the operator is
            % asked and before the output is armed - nothing is played
            asked = 0;
            s = tc.session();
            s.ExcitationConfirm = @(msg) countYes();
            s.connect(); s.prepareAcquisition();
            s.setAmplifierGain('XYZ power amplifier', NaN);        % chosen, gain not entered
            tim.instr.mockBusLog('start');
            tc.addTeardown(@() tim.instr.mockBusLog('stop'));
            tc.verifyError(@() s.measure('sweep'), 'tim:session:gainRequired');
            bus = tim.instr.mockBusLog('lines');
            tc.verifyFalse(any(startsWith(bus, 'SCPI > OUTP ON')), 'the output was never switched on');
            tc.verifyEqual(asked, 0, 'refused before the operator is asked');
            tc.verifyFalse(s.Gen.OutputArmed, 'not armed');
            tc.verifyFalse(s.Gen.isOutputOn());
            tc.verifyEmpty(FakeHardwareSource.rig().TriggerLog, 'nothing was played');
            tc.verifyEmpty(s.LastPartial, 'nothing was recorded');
            % the gain entered: confirmed and measured
            s.setAmplifierGain('XYZ power amplifier', 2);
            m = s.measure('sweep');
            tc.verifyTrue(m.integrityOk);
            tc.verifyEqual(asked, 1);
            tc.verifyNumElements(FakeHardwareSource.rig().TriggerLog, 1, 'played once');
            function ok = countYes()
                asked = asked + 1; ok = true;
            end
        end

        function excitationConfirmedInTheCommandWindow(tc)
            % hardware mode without ExcitationConfirm (a script): the
            % confirmation in the command window is asked BEFORE the output is
            % armed; anything but "y" refuses (tim:session:notConfirmed) and
            % nothing is played; after a refusal it is asked again, after a "y"
            % once per amplitude and amplifier
            tim.instr.mockBusLog('start');
            tc.addTeardown(@() tim.instr.mockBusLog('stop'));
            s = tc.session();
            s.connect(); s.prepareAcquisition();
            tc.assertEmpty(s.ExcitationConfirm, 'a script sets no confirmation function');
            reply = 'n'; prompts = {}; busAtPrompt = []; armedAtPrompt = false(1, 0);
            s.ConsoleInput = @(prompt, kind) answer(prompt, kind);
            tc.verifyError(@() s.measure('sweep'), 'tim:session:notConfirmed');
            tc.verifyEqual(prompts, {tim.app.msg('en', 'typeY')}, 'asked once, in the command window');
            tc.verifyFalse(any(startsWith(tim.instr.mockBusLog('lines'), 'SCPI > OUTP ON')), ...
                'refused: the output was never switched on');
            tc.verifyFalse(s.Gen.OutputArmed);
            tc.verifyFalse(s.Gen.isOutputOn());
            tc.verifyEmpty(FakeHardwareSource.rig().TriggerLog, 'nothing was played');
            reply = ' Y ';
            m = s.measure('sweep');
            tc.verifyTrue(m.integrityOk);
            tc.verifyNumElements(prompts, 2, 'asked again after the refusal');
            bus = tim.instr.mockBusLog('lines');
            on = find(startsWith(bus, 'SCPI > OUTP ON'), 1);
            tc.assertNotEmpty(on, 'played after "y"');
            tc.verifyLessThan(busAtPrompt(2), on, 'asked before the output was switched on');
            tc.verifyEqual(armedAtPrompt, [false false], 'asked before the output was armed');
            tc.verifyTrue(any(contains(s.LogLines, 'Excitation confirmed')));
            s.measure('sweep');
            tc.verifyNumElements(prompts, 2, 'same amplitude and amplifier: not asked again');
            ex = s.Cfg.excitation; ex.sweep.amplitudeVpp = 0.1; s.setExcitation(ex);
            s.measure('sweep');
            tc.verifyNumElements(prompts, 3, 'another amplitude: asked again');
            function a = answer(prompt, kind)
                tc.verifyEqual(kind, 's', 'read as text, like input(prompt, ''s'')');
                prompts{end + 1} = prompt;
                busAtPrompt(end + 1) = numel(tim.instr.mockBusLog('lines'));
                armedAtPrompt(end + 1) = s.Gen.OutputArmed;
                a = reply;
            end
        end

        function consoleConfirmAcceptsOnlyY(tc)
            % the command-window confirmation prints the message, then continues
            % only on "y" (either case, blanks ignored); the prompt in Korean too
            [ok, printed] = consoleAnswer('Drive the loudspeaker at 0.1 Vpk?', 'en', 'y');
            tc.verifyTrue(ok);
            tc.verifySubstring(printed, 'Drive the loudspeaker at 0.1 Vpk?');
            tc.verifyTrue(consoleAnswer('m', 'en', ' Y '));
            tc.verifyTrue(consoleAnswer('m', 'ko', 'y'));
            for no = {'n', '', 'yes', 'Y Y'}
                tc.verifyFalse(consoleAnswer('m', 'en', no{1}), sprintf('"%s" refuses', no{1}));
            end
        end
    end
end

function [ok, printed] = consoleAnswer(msg, lang, reply) %#ok<INUSD> (used by the evalc expression)
% tim.app.MeasurementSession.consoleConfirm answered with reply; printed = its output
ok = false;
printed = evalc('ok = tim.app.MeasurementSession.consoleConfirm(msg, lang, @(p, k) reply);');
end
