classdef DemoSource < tim.instr.SignalSource
    %DEMOSOURCE Driver of the demo signal generator DEMO-SG1 - SIMULATION ONLY.
    %
    %   The worked example of docs/adding_an_instrument.md (section 13): made
    %   from templates/instrument/TemplateSource.m by following that guide. The
    %   DEMO-SG1 does not exist; docs/ref_demo_source.md defines its commands
    %   and plays the part of its programming manual. The driver runs only on
    %   its protocol mock tim.instr.MockDemoSource, which drives the virtual
    %   tube (tim.sim.SimulatedRig); the registry refuses it in hardware mode
    %   (describe().simulation = 'only').
    %
    %   src = tim.instr.create('source', cfg, ctx)   % registry (driver 'demo')
    %   src = tim.instr.DemoSource(transport, maxVpp, load)
    %   transport: tim.instr.MockDemoSource (simulation)
    %
    %   SignalSource of the instrument contract (docs/instrument_interface.md
    %   sections 3 and 11): output read-back 'instrument' (OUTP1:STAT?),
    %   bus-triggered single sweep, level checked before every level command;
    %   sine and swept sine, no noise. SCPI dialect with channel-numbered
    %   headers (SOUR1:, OUTP1:, TRIG1:); docs/ref_demo_source.md.
    %
    %   SAFETY MODEL (contract section 11.1 - keep every point)
    %   * Output OFF first: on connect, in every configure*, on close, in
    %     delete and after every instrument error or read-back mismatch.
    %   * outputOn only when armed (armOutput, set by the session inside a
    %     measurement) and configured; the programmed level is read back and
    %     checked again right before the output is switched on.
    %   * Every level is checked BEFORE any level command (checkLevel):
    %     positive, at most generator.maxVpp, within the instrument's range for
    %     the configured load. No level is programmed at connect.
    %   * Never a command that switches the output on by itself (33220A: APPLy).
    %   * After close() nothing is sent any more (tim:instr:closed).

    properties (SetAccess = private)
        Transport                    % MockDemoSource (simulation only)
        Identity struct = struct()   % vendor, model, serial, firmware, raw (identification reply)
        MaxVpp double                % generator.maxVpp, fixed at creation [Vpp]
        Load char                    % generator.load, one of capabilities().source.loads
        Mode char = 'none'           % configured waveform: 'none' | 'sine' | 'sweep'
        Sweep struct = struct()      % configured sweep (fStart, fStop, duration, spacing, amplitudeVpp)
        Settings struct = struct()   % driver settings (generator.demo) from fromConfig
    end
    properties (Access = private)
        Closed logical = false       % close() done: nothing is sent any more
    end

    methods
        function obj = DemoSource(transport, maxVpp, load)
            %DEMOSOURCE Driver on an open transport: identify, output OFF, defaults.
            obj.Transport = transport;
            obj.MaxVpp = maxVpp;
            obj.Load = char(load);
            c = tim.instr.DemoSource.capabilities().source;
            if ~any(strcmp(obj.Load, c.loads))
                error('tim:demo:load', 'Output load "%s" not supported (supported: %s).', ...
                    obj.Load, strjoin(c.loads, ', '));
            end
            obj.identify();                                   % the right instrument? (read-only)
            obj.Transport.write('OUTP1:STAT OFF');            % output off - FIRST: it may have been left on (ref 3.1)
            obj.Transport.write('*CLS');                      % clear the error queue (ref 2.2)
            % no load setting (the level is the open-circuit voltage) and no
            % amplitude unit command (always Vpp) on the DEMO-SG1 (ref 3.2)
            obj.checkErrors('initialisation');
        end

        function id = identify(obj)
            %IDENTIFY Ask the instrument who it is; refuse another model.
            r = obj.Transport.query('*IDN?');                 % identification (ref 2.1)
            p = strtrim(strsplit(r, ','));                    % vendor,model,serial,firmware
            if numel(p) < 4 || ~strcmp(p{2}, 'DEMO-SG1')
                error('tim:demo:identity', 'Unexpected identification "%s" (expected a DEMO-SG1).', r);
            end
            id = struct('vendor', p{1}, 'model', p{2}, 'serial', p{3}, 'firmware', p{4}, 'raw', r);
            obj.Identity = id;
        end

        %% ---- configuration (output stays OFF) ------------------------------
        function configureSine(obj, f, vpp)
            %CONFIGURESINE Continuous sine f [Hz], vpp [Vpp]. Output stays OFF.
            obj.assertOpen('configureSine');
            obj.switchOff();
            obj.checkLevel(vpp);                              % before any level command
            obj.checkFrequency(f, 'tim:gen:unsupported');
            obj.Transport.write('SOUR1:SWE:STAT OFF');                 % sweep off (ref 3.3)
            obj.Transport.write('TRIG1:SOUR IMM');                     % continuous (ref 3.4)
            obj.Transport.write('SOUR1:FUNC SIN');                     % sine (ref 3.2)
            obj.Transport.write(sprintf('SOUR1:FREQ %.6f', f));        % frequency [Hz] (ref 3.2)
            obj.Transport.write('SOUR1:VOLT:OFFS 0');                  % offset 0 V (ref 3.2)
            obj.Transport.write(sprintf('SOUR1:VOLT %.4f', vpp));      % amplitude [Vpp] (ref 3.2)
            obj.checkErrors('configureSine');
            obj.verifyNumeric('SOUR1:FREQ?', f, 1e-6, 'frequency');
            obj.verifyNumeric('SOUR1:VOLT?', vpp, 1e-3, 'amplitude');
            obj.Mode = 'sine';
        end

        function setFrequency(obj, f)
            %SETFREQUENCY New sine frequency, phase continuous, output state unchanged.
            obj.assertOpen('setFrequency');
            if ~strcmp(obj.Mode, 'sine')
                error('tim:gen:mode', 'setFrequency requires sine mode.');
            end
            obj.checkFrequency(f, 'tim:gen:unsupported');
            obj.Transport.write(sprintf('SOUR1:FREQ %.6f', f));        % phase continuous (ref 3.2)
            obj.checkErrors('setFrequency');
        end

        function configureSweep(obj, s)
            %CONFIGURESWEEP Single bus-triggered sweep. Output stays OFF.
            %   s.fStart, s.fStop [Hz], s.duration [s], s.spacing 'LOG'|'LIN',
            %   s.amplitudeVpp [Vpp]; started by triggerSweep.
            obj.assertOpen('configureSweep');
            obj.switchOff();
            obj.checkLevel(s.amplitudeVpp);
            c = tim.instr.DemoSource.capabilities().source;
            if ~(s.duration >= c.sweepTime(1) && s.duration <= c.sweepTime(2))
                error('tim:gen:sweep', 'Sweep time %.3g s outside %g .. %g s.', s.duration, c.sweepTime(1), c.sweepTime(2));
            end
            if ~(s.fStart > 0 && s.fStop > 0)
                error('tim:gen:sweep', 'Sweep frequencies must be positive.');
            end
            obj.checkFrequency([s.fStart s.fStop], 'tim:gen:sweep');
            spacing = upper(char(s.spacing));
            if ~any(strcmp(spacing, c.sweepSpacing))
                error('tim:gen:sweep', 'Sweep spacing "%s" not supported (supported: %s).', spacing, strjoin(c.sweepSpacing, ', '));
            end
            % the order of ref 3.3: sweep off, the sine at fStart, the sweep
            % settings, trigger source BUS, the sweep on last; the output plays
            % fStart before *TRG and again after the sweep (contract 3.3)
            w = @(cmd) obj.Transport.write(cmd);
            w('SOUR1:SWE:STAT OFF');
            w('SOUR1:FUNC SIN');
            w(sprintf('SOUR1:FREQ %.6f', s.fStart));
            w('SOUR1:VOLT:OFFS 0');
            w(sprintf('SOUR1:VOLT %.4f', s.amplitudeVpp));
            w(sprintf('SOUR1:SWE:STAR %.6f', s.fStart));
            w(sprintf('SOUR1:SWE:STOP %.6f', s.fStop));
            w(['SOUR1:SWE:SPAC ' spacing]);
            w(sprintf('SOUR1:SWE:TIME %.6f', s.duration));
            w('TRIG1:SOUR BUS');                                       % one sweep per *TRG (ref 3.4)
            w('SOUR1:SWE:STAT ON');
            obj.checkErrors('configureSweep');
            obj.verifyNumeric('SOUR1:SWE:STAR?', s.fStart, 1e-6, 'sweep start');
            obj.verifyNumeric('SOUR1:SWE:STOP?', s.fStop, 1e-6, 'sweep stop');
            obj.verifyNumeric('SOUR1:SWE:TIME?', s.duration, 1e-6, 'sweep time');
            obj.verifyNumeric('SOUR1:VOLT?', s.amplitudeVpp, 1e-3, 'amplitude');
            sp = obj.Transport.query('SOUR1:SWE:SPAC?');
            if ~strncmpi(sp, spacing, 3)
                obj.switchOff();
                error('tim:gen:verify', 'Sweep spacing read-back "%s" differs from "%s".', sp, spacing);
            end
            obj.Sweep = struct('fStart', s.fStart, 'fStop', s.fStop, 'duration', s.duration, 'spacing', spacing, ...
                'amplitudeVpp', s.amplitudeVpp);
            obj.Mode = 'sweep';
        end

        function configureNoise(obj, ~)
            %CONFIGURENOISE Refused (tim:gen:unsupported): the DEMO-SG1 has no noise
            %   function (ref 3.2). Nothing is sent.
            obj.assertOpen('configureNoise');
            error('tim:gen:unsupported', 'The %s cannot play noise.', tim.instr.DemoSource.describe().displayName);
        end

        %% ---- output / trigger ------------------------------------------------
        function armOutput(obj, tf)
            %ARMOUTPUT Permission set by the session only inside a measurement; false switches off.
            obj.OutputArmed = logical(tf);
            if ~tf, obj.outputOff(); end
        end

        function outputOn(obj)
            %OUTPUTON Output on: only armed and configured, the programmed level re-checked first.
            obj.assertOpen('outputOn');
            if ~obj.OutputArmed
                error('tim:gen:notArmed', ...
                    'Output enable refused: no measurement has been explicitly started (armOutput(true) not called).');
            end
            if strcmp(obj.Mode, 'none')
                error('tim:gen:mode', 'Output enable refused: generator not configured.');
            end
            v = str2double(obj.Transport.query('SOUR1:VOLT?'));       % what is programmed now (ref 3.2)
            if ~(v > 0 && v <= obj.MaxVpp * (1 + 1e-6))
                obj.switchOff();
                error('tim:gen:amplitude', 'Programmed amplitude %.4g Vpp exceeds MaxVpp %.4g Vpp (or is not valid).', ...
                    v, obj.MaxVpp);
            end
            obj.Transport.write('OUTP1:STAT ON');                      % output on (ref 3.1)
            obj.checkErrors('outputOn');
        end

        function outputOff(obj)
            %OUTPUTOFF Output off. Never throws (a failure is a warning); idempotent;
            %   any state; re-entrant; does nothing after close().
            if obj.Closed, return; end
            obj.switchOff();
        end

        function tf = isOutputOn(obj, timeout)
            %ISOUTPUTON Output state read back from the instrument ('instrument'
            %   read-back), never a cached flag. timeout [s] optional. An answer
            %   other than on / off raises tim:gen:verify (never reported as off).
            obj.assertOpen('isOutputOn');
            if nargin < 2
                r = obj.Transport.query('OUTP1:STAT?');               % output state (ref 3.1)
            else
                r = obj.Transport.query('OUTP1:STAT?', timeout);
            end
            r = upper(strtrim(r));                                     % reply ON or OFF (ref 3.1)
            if ~any(strcmp(r, {'ON', 'OFF'}))
                error('tim:gen:verify', 'Unexpected answer "%s" to the output state query (output state unknown).', r);
            end
            tf = strcmp(r, 'ON');
        end

        function triggerSweep(obj)
            %TRIGGERSWEEP Start the configured sweep now (bus trigger).
            obj.assertOpen('triggerSweep');
            if ~strcmp(obj.Mode, 'sweep')
                error('tim:gen:mode', 'triggerSweep requires a configured sweep.');
            end
            obj.Transport.write('*TRG');                               % bus trigger (ref 3.4)
        end

        function tf = waitComplete(obj, timeout)
            %WAITCOMPLETE True when the sweep has ended - never earlier; waits up to timeout s.
            %   *OPC? answers 1 only after a triggered sweep has ended (ref 3.4).
            obj.assertOpen('waitComplete');
            r = obj.Transport.query('*OPC?', timeout);
            tf = strcmp(strtrim(r), '1');
        end

        %% ---- errors ------------------------------------------------------------
        function errs = readErrors(obj)
            %READERRORS Empty the instrument's error queue (cellstr of the entries).
            errs = {};
            for i = 1:16                                               % queue of 16 entries (ref 2.2)
                r = obj.Transport.query('SYST:ERR?');                  % <code>,"<text>"; 0 = no error (ref 2.2)
                code = sscanf(r, '%d', 1);
                if isempty(code)
                    errs{end+1} = sprintf('Unparsable error response: %s', r); %#ok<AGROW>
                    break
                end
                if code == 0, break; end
                errs{end+1} = r; %#ok<AGROW>
            end
        end

        function checkErrors(obj, context)
            %CHECKERRORS Raise (output off first) when the instrument reports an error.
            errs = obj.readErrors();
            if ~isempty(errs)
                obj.switchOff();
                error('tim:demo:instrumentError', '%s reported error(s) during %s: %s', ...
                    obj.Identity.model, context, strjoin(errs, ' | '));
            end
        end

        %% ---- shutdown ----------------------------------------------------------
        function close(obj)
            %CLOSE Disarm, output off, front panel back to local, transport released.
            %   Never throws; a second close() sends nothing; afterwards every
            %   method that needs the instrument raises tim:instr:closed.
            if obj.Closed, return; end
            obj.Closed = true;                                % a re-entrant close() returns at once
            obj.OutputArmed = false;
            if isempty(obj.Transport), return; end
            obj.switchOff();
            try
                if obj.Transport.isOpen()
                    obj.Transport.write('SOUR1:SWE:STAT OFF');         % idle (ref 3.3)
                    obj.Transport.write('SYST:LOC');                   % front panel back to local (ref 2.3)
                end
            catch
            end
            try, obj.Transport.close(); catch, end
        end

        function delete(obj)
            % output off and released (as close)
            try, obj.close(); catch, end
        end

        %% ---- contract: identity, metadata, time-out ----------------------------
        function id = identity(obj)
            %IDENTITY vendor, model, serial, firmware, raw (identification reply); no I/O.
            id = tim.instr.Instrument.emptyIdentity();
            f = fieldnames(id);
            for i = 1:numel(f)
                if isfield(obj.Identity, f{i}), id.(f{i}) = obj.Identity.(f{i}); end
            end
        end

        function md = metadata(obj)
            %METADATA Stored with every measurement (JSON-encodable): the contract
            %   fields, the driver settings and the role settings in use.
            d = tim.instr.DemoSource.describe();
            md = struct('driver', d.name, 'displayName', d.displayName, 'roles', {obj.rolesInUse()}, ...
                'identity', obj.identity(), 'sharedClock', false, 'settings', obj.Settings, ...
                'maxVpp', obj.MaxVpp, 'load', obj.Load);
        end

        function setTimeout(obj, t)
            %SETTIMEOUT Shorten the I/O time-out [s] (closing the window).
            if ~isempty(obj.Transport) && ismethod(obj.Transport, 'setTimeout')
                obj.Transport.setTimeout(t);
            end
        end
    end

    %% ---- contract: class-level members (no I/O) -------------------------------
    methods (Static)
        function d = describe()
            d = struct('name', 'demo', ...                                 % registry name = generator.driver
                'displayName', 'Demo signal generator DEMO-SG1 (simulation only)', ...
                'labels', struct('source', 'Generator'), ...                % short lamp label
                'defaults', struct('settings', struct( ...                  % generator.demo
                    'host', '192.0.2.10', ...                               % documentation address: the demo has no instrument
                    'port', 5025, ...                                       % SCPI socket (ref 1)
                    'timeout', 5)), ...                                     % I/O time-out [s]
                'texts', struct('settle', '', 'noun', 'generator', 'closed', 'output off'), ...
                'simulation', 'only');                                      % no instrument: simulation mode only
        end

        function c = capabilities()
            % limits of the DEMO-SG1 (docs/ref_demo_source.md section 4)
            src = struct('waveforms', {{'sine', 'sweep'}}, ...             % no noise function (ref 3.2)
                'sweepSpacing', {{'LOG', 'LIN'}}, ...                       % ref 3.3
                'frequencyRange', [0.1 1e5], ...                            % [Hz] sine and sweep (ref 3.2)
                'bandFraction', NaN, ...                                    % own clock (NaN)
                'loads', {{'INF'}}, ...                                     % the level is the open-circuit voltage (ref 3.2)
                'maxVpp', 10, ...                                           % largest level [Vpp] (ref 3.2)
                'minVpp', 0.002, ...                                        % smallest level [Vpp] (ref 3.2)
                'sweepTime', [0.01 300], ...                                % [s] (ref 3.3)
                'noiseCrest', 3.3, ...                                      % no noise output; the contract value
                'outputImpedance_ohm', 50, ...                              % source impedance [ohm] (ref 3.1)
                'trigger', 'bus', ...                                       % *TRG (ref 3.4)
                'readback', 'instrument', ...                               % OUTP1:STAT? (ref 3.1)
                'levelKnown', true);                                        % absolute volts
            c = struct('roles', {{'source'}}, 'sharedClock', false, 'rolesTogether', false, ...
                'products', struct('name', {}, 'feature', {}), ...          % nothing beyond the base (tcpclient)
                'source', src);
        end

        function s = connectionSteps()
            s = struct('key', 'demo', ...                                  % unique: the registry name
                'label', 'Demo generator DEMO-SG1 (SCPI, simulated)', ...
                'role', 'source', 'phase', 'connect');
        end

        function report = checkConfig(cfg)
            %CHECKCONFIG Driver settings (generator.demo) and the generic
            %   source limits (tim.instr.SignalSource.checkSourceConfig).
            d = tim.instr.DemoSource.describe();
            st = tim.instr.Instrument.settingsFrom(cfg, 'generator', d.name, d.defaults.settings);
            if ~(ischar(st.host) || isstring(st.host)) || isempty(strtrim(char(st.host)))
                error('tim:config:host', 'Generator address (generator.%s.host) is empty.', d.name);
            end
            if ~(isscalar(st.port) && st.port >= 1 && st.port <= 65535 && st.port == round(st.port))
                error('tim:config:port', 'Generator port (generator.%s.port) must be an integer 1 .. 65535.', d.name);
            end
            if ~(isscalar(st.timeout) && st.timeout > 0)
                error('tim:config:timeout', 'Generator time-out (generator.%s.timeout) must be greater than 0 s.', d.name);
            end
            report = tim.instr.SignalSource.checkSourceConfig(cfg, tim.instr.DemoSource.capabilities(), d.displayName);
        end

        function obj = fromConfig(cfg, ctx)
            %FROMCONFIG Connect to the mock on ctx.rig (simulation only), identify,
            %   output OFF. Reports the checklist step 'demo'.
            st = ctx.settings;
            if ~strcmp(ctx.mode, 'simulation')
                % the registry refuses a simulation-only driver before; a real
                % driver builds its transport here (TemplateSource: ScpiTcpTransport)
                error('tim:instr:simulationOnly', 'The %s exists only in simulation mode.', ...
                    tim.instr.DemoSource.describe().displayName);
            end
            tim.instr.Instrument.reportStep(ctx, 'demo', 'run', 'simulated generator');
            tr = tim.instr.MockDemoSource(ctx.rig);
            try
                obj = tim.instr.DemoSource(tr, cfg.generator.maxVpp, cfg.generator.load);
            catch err
                try, tr.close(); catch, end
                rethrow(err);
            end
            obj.Settings = st;
            obj.Roles = ctx.roles;
            tim.instr.Instrument.reportStep(ctx, 'demo', 'ok', sprintf('%s – output off', obj.Identity.raw));
        end

        function h = testHooks(obj)
            %TESTHOOKS Simulation only: handles into the protocol mock (contract tests).
            tr = obj.Transport;
            if ~isa(tr, 'tim.instr.MockDemoSource')
                error('tim:instr:noHooks', 'Test hooks need the driver on its mock transport (simulation).');
            end
            h = struct();
            h.traffic = @() tr.Log;
            h.breakLink = @() tr.fault('broken');
            h.outputOn = @() tr.State.output;
            h.levelHistory = @() tr.LevelLog;
            h.forceOutputOn = @() tr.frontPanel('output', true);
            h.forceLevel = @(vpp) tr.frontPanel('level', vpp);
            h.injectError = @() tr.fault('error');
        end
    end

    methods (Access = private)
        function switchOff(obj)
            % output off on the instrument; never throws (a failure is a warning)
            try
                if obj.Transport.isOpen()
                    obj.Transport.write('OUTP1:STAT OFF');             % output off (ref 3.1)
                end
            catch err
                warning('tim:gen:outputOff', 'Could not switch the output off: %s', err.message);
            end
        end

        function checkLevel(obj, vpp)
            % level limit BEFORE any level command (contract section 3.4)
            c = tim.instr.DemoSource.capabilities().source;
            k = find(strcmp(obj.Load, c.loads), 1);
            if ~(isscalar(vpp) && isnumeric(vpp) && isfinite(vpp) && vpp > 0)
                error('tim:gen:amplitude', 'Amplitude must be a positive scalar [Vpp].');
            end
            if vpp > obj.MaxVpp * (1 + 1e-9)
                error('tim:gen:amplitude', 'Requested %.4g Vpp exceeds the configured safety limit MaxVpp = %.4g Vpp.', ...
                    vpp, obj.MaxVpp);
            end
            if vpp < c.minVpp(k) || vpp > c.maxVpp(k)
                error('tim:gen:amplitude', 'Requested %.4g Vpp outside the output range %.3g .. %.3g Vpp (load %s).', ...
                    vpp, c.minVpp(k), c.maxVpp(k), obj.Load);
            end
        end

        function checkFrequency(~, f, id)
            % frequencies within capabilities().source.frequencyRange
            c = tim.instr.DemoSource.capabilities().source;
            if any(~(f >= c.frequencyRange(1) & f <= c.frequencyRange(2)))
                error(id, 'Frequency %s Hz outside %g .. %g Hz.', mat2str(f), c.frequencyRange(1), c.frequencyRange(2));
            end
        end

        function verifyNumeric(obj, q, expected, relTol, what)
            % read back a numeric setting; a difference: output off, tim:gen:verify
            v = str2double(obj.Transport.query(q));
            if ~(abs(v - expected) <= relTol * max(abs(expected), 1e-12) + 1e-9)
                obj.switchOff();
                error('tim:gen:verify', 'Read-back of %s = %.10g differs from requested %.10g.', what, v, expected);
            end
        end

        function assertOpen(obj, action)
            % after close() nothing is sent any more
            if obj.Closed
                error('tim:instr:closed', 'Generator driver closed: %s refused (connect again).', action);
            end
        end
    end
end
