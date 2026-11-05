classdef TemplateSource < tim.instr.SignalSource
    %TEMPLATESOURCE TEMPLATE of a signal-source driver (request / response instrument).
    %
    %   THIS IS A TEMPLATE. Copy it, do not use it in place
    %   (docs/adding_an_instrument.md, steps 3 and 4):
    %     copy to +tim/+instr/<Name>.m, then replace, case-sensitive,
    %     'TemplateSource' -> '<Name>', 'TEMPLATESOURCE' -> '<NAME>' and
    %     'templatesource' -> '<registry name>' (in this file and in the
    %     copies of MockTemplateSource.m and TestTemplateSource.m).
    %   As it stands it is a complete driver of an imaginary SCPI function
    %   generator that runs on its protocol mock (MockTemplateSource) and passes
    %   tests/TestInstrumentContract (tests/TestInstrumentTemplates runs it).
    %   Every line marked TODO holds an INSTRUMENT FACT: replace it with what
    %   YOUR instrument's programming manual says and enter the manual section /
    %   page in docs/ref_<instrument>.md. Never guess a command. When you are
    %   done, replace this paragraph and the TODO line below by a description of
    %   your driver: "TODO" must not occur in the file any more.
    %
    %   src = tim.instr.create('source', cfg, ctx)   % registry (driver 'templatesource')
    %   src = tim.instr.TemplateSource(transport, maxVpp, load)
    %   transport: tim.instr.ScpiTcpTransport (hardware) or
    %              tim.instr.MockTemplateSource (simulation)
    %
    %   SignalSource of the instrument contract (docs/instrument_interface.md
    %   sections 3 and 11): output read-back 'instrument' (output state query),
    %   bus-triggered single sweep, level checked before every level command.
    %   TODO one line: the instrument (vendor, model), its interface and the
    %   manual (title, publication number, edition); docs/ref_<instrument>.md.
    %
    %   SAFETY MODEL (contract section 11.1 - keep every point)
    %   * Output OFF first: on connect, in every configure*, on close, in
    %     delete and after every instrument error or read-back mismatch.
    %   * outputOn only when armed (armOutput, set by the session inside a
    %     measurement) and configured; the programmed level is read back and
    %     checked again right before the output is switched on.
    %   * Every level is checked BEFORE any level command (checkLevel):
    %     positive, its open-circuit voltage at most generator.maxVpp (an
    %     open-circuit limit, contract 3.4), within the instrument's range for
    %     the configured load. No level is programmed at connect.
    %   * Never a command that switches the output on by itself (33220A: APPLy).
    %   * After close() nothing is sent any more (tim:instr:closed).

    properties (SetAccess = private)
        Transport                    % ScpiTcpTransport (hardware) or MockTemplateSource (simulation)
        Identity struct = struct()   % vendor, model, serial, firmware, raw (identification reply)
        MaxVpp double                % generator.maxVpp, fixed at creation [Vpp]
        Load char                    % generator.load, one of capabilities().source.loads
        Mode char = 'none'           % configured waveform: 'none' | 'sine' | 'sweep' | 'noise'
        Sweep struct = struct()      % configured sweep (fStart, fStop, duration, spacing, amplitudeVpp)
        Settings struct = struct()   % driver settings (generator.templatesource) from fromConfig
    end
    properties (Access = private)
        Closed logical = false       % close() done: nothing is sent any more
    end

    methods
        function obj = TemplateSource(transport, maxVpp, load)
            %TEMPLATESOURCE Driver on an open transport: identify, output OFF, defaults.
            obj.Transport = transport;
            obj.MaxVpp = maxVpp;
            obj.Load = char(load);
            c = tim.instr.TemplateSource.capabilities().source;
            if ~tim.instr.SignalSource.supportsLoad(c, obj.Load)
                error('tim:templatesource:load', 'Output load "%s" not supported (supported: %s).', ...
                    obj.Load, tim.instr.SignalSource.loadsText(c));
            end
            obj.identify();                                   % the right instrument? (read-only)
            obj.Transport.write('OUTP OFF');                  % TODO output off - FIRST: it may have been left on
            obj.Transport.write('*CLS');                      % TODO clear the error queue
            obj.Transport.write(['OUTP:LOAD ' obj.Load]);     % TODO load setting (delete if the instrument has none)
            obj.Transport.write('VOLT:UNIT VPP');             % TODO amplitude unit Vpp
            obj.checkErrors('initialisation');
        end

        function id = identify(obj)
            %IDENTIFY Ask the instrument who it is; refuse another model.
            r = obj.Transport.query('*IDN?');                 % TODO identification query
            p = strtrim(strsplit(r, ','));                    % TODO reply format: vendor,model,serial,firmware
            if numel(p) < 4 || ~contains(p{2}, 'TEMPLATE-GEN')   % TODO model text (match the model, not the vendor)
                error('tim:templatesource:identity', 'Unexpected identification "%s" (expected a TEMPLATE-GEN).', r);
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
            obj.Transport.write('SWE:STAT OFF');              % TODO sweep off
            obj.Transport.write('TRIG:SOUR IMM');             % TODO continuous (not triggered)
            obj.Transport.write('FUNC SIN');                  % TODO function: sine
            obj.Transport.write(sprintf('FREQ %.6f', f));     % TODO frequency [Hz]
            obj.Transport.write('VOLT:OFFS 0');               % TODO offset 0 V
            obj.Transport.write(sprintf('VOLT %.4f', vpp));   % TODO amplitude [Vpp]
            obj.checkErrors('configureSine');
            obj.verifyNumeric('FREQ?', f, 1e-6, 'frequency');     % TODO frequency query
            obj.verifyNumeric('VOLT?', vpp, 1e-3, 'amplitude');   % TODO amplitude query
            obj.Mode = 'sine';
        end

        function setFrequency(obj, f)
            %SETFREQUENCY New sine frequency, phase continuous, output state unchanged.
            obj.assertOpen('setFrequency');
            if ~strcmp(obj.Mode, 'sine')
                error('tim:gen:mode', 'setFrequency requires sine mode.');
            end
            obj.checkFrequency(f, 'tim:gen:unsupported');
            obj.Transport.write(sprintf('FREQ %.6f', f));     % TODO frequency [Hz]
            obj.checkErrors('setFrequency');
        end

        function configureSweep(obj, s)
            %CONFIGURESWEEP Single bus-triggered sweep. Output stays OFF.
            %   s.fStart, s.fStop [Hz], s.duration [s], s.spacing 'LOG'|'LIN',
            %   s.amplitudeVpp [Vpp]; started by triggerSweep.
            obj.assertOpen('configureSweep');
            obj.switchOff();
            obj.checkLevel(s.amplitudeVpp);
            c = tim.instr.TemplateSource.capabilities().source;
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
            % TODO the commands and their ORDER as the manual recommends for a
            % triggered single sweep (enable the sweep last); the sweep must
            % follow contract section 3.3: offset 0, no hold / return time,
            % output at fStart before the trigger.
            w = @(cmd) obj.Transport.write(cmd);
            w('SWE:STAT OFF');                                % TODO
            w('FUNC SIN');                                    % TODO
            w(sprintf('FREQ %.6f', s.fStart));                % TODO
            w('VOLT:OFFS 0');                                 % TODO
            w(sprintf('VOLT %.4f', s.amplitudeVpp));          % TODO
            w(sprintf('FREQ:STAR %.6f', s.fStart));           % TODO sweep start [Hz]
            w(sprintf('FREQ:STOP %.6f', s.fStop));            % TODO sweep stop [Hz]
            w(['SWE:SPAC ' spacing]);                         % TODO spacing LOG | LIN
            w(sprintf('SWE:TIME %.6f', s.duration));          % TODO sweep time [s]
            w('TRIG:SOUR BUS');                               % TODO one sweep per bus trigger
            w('SWE:STAT ON');                                 % TODO sweep on (last)
            obj.checkErrors('configureSweep');
            obj.verifyNumeric('FREQ:STAR?', s.fStart, 1e-6, 'sweep start');     % TODO read-back queries
            obj.verifyNumeric('FREQ:STOP?', s.fStop, 1e-6, 'sweep stop');       % TODO
            obj.verifyNumeric('SWE:TIME?', s.duration, 1e-6, 'sweep time');     % TODO
            obj.verifyNumeric('VOLT?', s.amplitudeVpp, 1e-3, 'amplitude');      % TODO
            sp = obj.Transport.query('SWE:SPAC?');                              % TODO
            if ~strncmpi(sp, spacing, 3)
                obj.switchOff();
                error('tim:gen:verify', 'Sweep spacing read-back "%s" differs from "%s".', sp, spacing);
            end
            obj.Sweep = struct('fStart', s.fStart, 'fStop', s.fStop, 'duration', s.duration, 'spacing', spacing, ...
                'amplitudeVpp', s.amplitudeVpp);
            obj.Mode = 'sweep';
        end

        function configureNoise(obj, vpp)
            %CONFIGURENOISE Gaussian noise, crest factor about 3.3 (rms ~ Vpp / 6.6). Output stays OFF.
            %   Refused (tim:gen:unsupported) when 'noise' is not in capabilities().source.waveforms.
            obj.assertOpen('configureNoise');
            c = tim.instr.TemplateSource.capabilities().source;
            if ~any(strcmp('noise', c.waveforms))
                error('tim:gen:unsupported', 'The %s cannot play noise.', tim.instr.TemplateSource.describe().displayName);
            end
            obj.switchOff();
            obj.checkLevel(vpp);
            obj.Transport.write('SWE:STAT OFF');              % TODO sweep off
            obj.Transport.write('TRIG:SOUR IMM');             % TODO continuous
            obj.Transport.write('FUNC NOIS');                 % TODO function: noise (crest factor: capabilities)
            obj.Transport.write('VOLT:OFFS 0');               % TODO offset 0 V
            obj.Transport.write(sprintf('VOLT %.4f', vpp));   % TODO amplitude [Vpp]
            obj.checkErrors('configureNoise');
            obj.verifyNumeric('VOLT?', vpp, 1e-3, 'amplitude');   % TODO
            obj.Mode = 'noise';
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
            v = str2double(obj.Transport.query('VOLT?'));     % TODO amplitude query: what is programmed now
            if ~(v > 0 && v <= obj.MaxVpp * (1 + 1e-6))
                obj.switchOff();
                error('tim:gen:amplitude', 'Programmed amplitude %.4g Vpp exceeds MaxVpp %.4g Vpp (or is not valid).', ...
                    v, obj.MaxVpp);
            end
            obj.Transport.write('OUTP ON');                   % TODO output on
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
                r = obj.Transport.query('OUTP?');             % TODO output state query
            else
                r = obj.Transport.query('OUTP?', timeout);    % TODO
            end
            v = str2double(r);                                % TODO reply format (here 0 / 1)
            if ~(v == 0 || v == 1)
                error('tim:gen:verify', 'Unexpected answer "%s" to the output state query (output state unknown).', r);
            end
            tf = v == 1;
        end

        function triggerSweep(obj)
            %TRIGGERSWEEP Start the configured sweep now (bus trigger).
            obj.assertOpen('triggerSweep');
            if ~strcmp(obj.Mode, 'sweep')
                error('tim:gen:mode', 'triggerSweep requires a configured sweep.');
            end
            obj.Transport.write('*TRG');                      % TODO bus (software) trigger
        end

        function tf = waitComplete(obj, timeout)
            %WAITCOMPLETE True when the sweep has ended - never earlier; waits up to timeout s.
            % TODO the completion query must wait for the END of the sweep (manual).
            % If the manual does not say that it does, make this time-based: note
            % tic in triggerSweep and return true only after Sweep.duration has
            % passed (pause in short steps, at most timeout s).
            obj.assertOpen('waitComplete');
            r = obj.Transport.query('*OPC?', timeout);        % TODO completion query
            tf = strcmp(strtrim(r), '1');
        end

        %% ---- errors ------------------------------------------------------------
        function errs = readErrors(obj)
            %READERRORS Empty the instrument's error queue (cellstr of the entries).
            errs = {};
            for i = 1:25                                      % TODO queue length (manual)
                r = obj.Transport.query('SYST:ERR?');         % TODO error query
                code = sscanf(r, '%d', 1);                    % TODO reply format: <code>,"<text>"; 0 = no error
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
                error('tim:templatesource:instrumentError', '%s reported error(s) during %s: %s', ...
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
                    obj.Transport.write('SWE:STAT OFF');      % TODO leave it idle (or delete)
                    obj.Transport.write('SYST:LOC');          % TODO front panel back to local (or delete)
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
            d = tim.instr.TemplateSource.describe();
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
            d = struct('name', 'templatesource', ...                       % registry name = generator.driver
                'displayName', 'Template signal generator (SCPI)', ...      % TODO vendor, model and kind, as shown in the window
                'labels', struct('source', 'Generator'), ...                % lamp label: the role, not the product
                'defaults', struct('settings', struct( ...                  % generator.templatesource
                    'host', '192.0.2.10', ...                               % TODO the instrument's address (192.0.2.x: documentation address, no device)
                    'port', 5025, ...                                       % TODO SCPI socket port (manual)
                    'timeout', 5)), ...                                     % I/O time-out [s]
                'texts', struct('settle', '', 'noun', 'generator', 'closed', 'output off'), ...
                'simulation', 'protocol');                                  % real driver, protocol mock in simulation
        end

        function c = capabilities()
            % TODO every limit from the manual (section / page in docs/ref_<instrument>.md)
            src = struct('waveforms', {{'sine', 'sweep', 'noise'}}, ...    % TODO what it plays ('sweep' is required)
                'sweepSpacing', {{'LOG', 'LIN'}}, ...                       % TODO
                'frequencyRange', [1e-3 1e6], ...                           % TODO [Hz] sine and sweep
                'bandFraction', NaN, ...                                    % own clock (NaN)
                'loads', {{'INF', '50'}}, ...                               % TODO load settings ('INF' = open-circuit volts; any resistance: also 'loadRange', [Rmin Rmax], contract 3.4)
                'maxVpp', [20 10], ...                                      % TODO largest level per load [Vpp]
                'minVpp', [0.02 0.01], ...                                  % TODO smallest level per load [Vpp]
                'sweepTime', [1e-3 500], ...                                % TODO [s]
                'noiseCrest', 3.3, ...                                      % TODO crest factor of the noise
                'outputImpedance_ohm', 50, ...                              % TODO source impedance [ohm]
                'trigger', 'bus', ...                                       % 'bus' | 'software'
                'readback', 'instrument', ...                               % output state query
                'levelKnown', true, ...                                     % absolute volts
                'levelWhileOn', false);                                     % TODO true only if the manual documents a level change while the output is on; then implement setAmplitude (contract 3.2)
            c = struct('roles', {{'source'}}, 'sharedClock', false, 'rolesTogether', false, ...
                'products', struct('name', {}, 'feature', {}), ...          % TODO MATLAB products beyond the base (e.g. VISA: Instrument Control Toolbox)
                'source', src);
        end

        function s = connectionSteps()
            s = struct('key', 'templatesource', ...                        % unique: the registry name
                'label', 'connect (Template generator, SCPI)', ...          % TODO checklist text 'connect (<model>, <interface>)', shown after the lamp label
                'role', 'source', 'phase', 'connect');
        end

        function report = checkConfig(cfg)
            %CHECKCONFIG Driver settings (generator.templatesource) and the generic
            %   source limits (tim.instr.SignalSource.checkSourceConfig).
            d = tim.instr.TemplateSource.describe();
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
            report = tim.instr.SignalSource.checkSourceConfig(cfg, tim.instr.TemplateSource.capabilities(), d.displayName);
        end

        function obj = fromConfig(cfg, ctx)
            %FROMCONFIG Connect (hardware: the transport; simulation: the mock on
            %   ctx.rig), identify, output OFF. Reports the checklist step.
            st = ctx.settings;
            sim = strcmp(ctx.mode, 'simulation');
            if sim
                detail = 'simulated generator';
            else
                detail = sprintf('%s:%d (SCPI over TCP)', st.host, st.port);   % TODO interface text
            end
            tim.instr.Instrument.reportStep(ctx, 'templatesource', 'run', detail);
            if sim
                tr = tim.instr.MockTemplateSource(ctx.rig);
            else
                tr = tim.instr.ScpiTcpTransport(st.host, st.port, st.timeout);  % TODO the transport of the interface
            end
            try
                obj = tim.instr.TemplateSource(tr, cfg.generator.maxVpp, cfg.generator.load);
            catch err
                try, tr.close(); catch, end
                rethrow(err);
            end
            obj.Settings = st;
            obj.Roles = ctx.roles;
            tim.instr.Instrument.reportStep(ctx, 'templatesource', 'ok', sprintf('%s – output off', obj.Identity.raw));
        end

        function h = testHooks(obj)
            %TESTHOOKS Simulation only: handles into the protocol mock (contract tests).
            tr = obj.Transport;
            if ~isa(tr, 'tim.instr.MockTemplateSource')
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
                    obj.Transport.write('OUTP OFF');          % TODO output off
                end
            catch err
                warning('tim:gen:outputOff', 'Could not switch the output off: %s', err.message);
            end
        end

        function checkLevel(obj, vpp)
            % level limit BEFORE any level command (contract section 3.4): vpp is
            % the programmed level at the load setting, generator.maxVpp an
            % open-circuit voltage (at a load of R ohm: vpp x (R + Rs) / R)
            c = tim.instr.TemplateSource.capabilities().source;
            if ~(isscalar(vpp) && isnumeric(vpp) && isfinite(vpp) && vpp > 0)
                error('tim:gen:amplitude', 'Amplitude must be a positive scalar [Vpp].');
            end
            oc = vpp * tim.instr.SignalSource.openCircuitFactor(c, obj.Load);
            if oc > obj.MaxVpp * (1 + 1e-9)
                error('tim:gen:amplitude', ['Requested %.4g Vpp at load %s (open circuit %.4g Vpp) exceeds the ' ...
                    'configured safety limit MaxVpp = %.4g Vpp (open circuit).'], vpp, obj.Load, oc, obj.MaxVpp);
            end
            [lo, hi] = tim.instr.SignalSource.levelRange(c, obj.Load);
            if vpp < lo * (1 - 1e-9) || vpp > hi * (1 + 1e-9)
                error('tim:gen:amplitude', 'Requested %.4g Vpp outside the output range %.3g .. %.3g Vpp (load %s).', ...
                    vpp, lo, hi, obj.Load);
            end
        end

        function checkFrequency(~, f, id)
            % frequencies within capabilities().source.frequencyRange
            c = tim.instr.TemplateSource.capabilities().source;
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
