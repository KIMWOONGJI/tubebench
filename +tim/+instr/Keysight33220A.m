classdef Keysight33220A < tim.instr.SignalSource
    %KEYSIGHT33220A Driver for the Agilent/Keysight 33220A function generator.
    %
    %   gen = tim.instr.Keysight33220A(transport, 'MaxVpp', 1.0, 'Load', 'INF')
    %   transport: tim.instr.ScpiTcpTransport (hardware) or
    %              tim.instr.MockScpiTransport (simulation).
    %   gen = tim.instr.create('source', cfg, ctx)   % registry (driver 'keysight33220a')
    %
    %   SignalSource of the instrument contract (docs/instrument_interface.md):
    %   output read-back 'instrument' (OUTP?); relay output (OUTP OFF
    %   disconnects it); bus-triggered sweep; 50 ohm source impedance.
    %
    %   SAFETY MODEL
    %   * The output is switched OFF on connect, on every configuration call,
    %     on close and on delete.
    %   * outputOn() is refused unless armOutput() has been called by the
    %     measurement session (i.e. the user explicitly started a measurement).
    %   * The amplitude is limited to MaxVpp (user setting, chosen to protect
    %     the amplifier/loudspeaker) as OPEN-CIRCUIT voltage: at a load setting
    %     of R ohm the programmed level is at most MaxVpp * R / (R + 50)
    %     (WO-004, 1.3.0). Read-back is verified.
    %   * Load: 'INF' (the programmed level is the open-circuit voltage) or a
    %     resistance 1 .. 10000 ohm written as a number ('50', '600'; manual
    %     p.189): the level is the voltage across that resistance, e.g. the
    %     input of an amplifier. A numeric load is read back (OUTP:LOAD?).
    %   * APPLy is never used (it forces OUTP ON, see manual p.175).
    %
    %   All SCPI strings follow the 33220A User's Guide (33220-90002, Ed. 4);
    %   page references are in docs/ref_33220A_scpi.md.

    properties (SetAccess = private)
        Transport
        Identity struct = struct()
        MaxVpp double
        Load char
        Mode char = 'none'           % 'none' | 'sine' | 'sweep' | 'noise'
        SweepSettings struct = struct()
        Settings struct = struct()   % driver settings (host, port, timeout) from fromConfig
    end
    properties
        ReopenAfterIdle_s double = 30   % checkConnection replaces a connection idle longer than this
    end

    methods
        function obj = Keysight33220A(transport, opts)
            arguments
                transport
                opts.MaxVpp (1,1) double {mustBePositive} = 1.0
                opts.Load (1,:) char {mustBeLoad(opts.Load)} = 'INF'
                opts.Reset (1,1) logical = true
            end
            obj.Transport = transport;
            obj.MaxVpp = opts.MaxVpp;
            obj.Load = canonicalLoad(opts.Load);
            obj.identify();
            % Output OFF before anything else (it may have been left on).
            obj.Transport.write('OUTP OFF');
            if opts.Reset
                obj.Transport.write('*RST');
                obj.Transport.write('OUTP OFF');
            end
            obj.Transport.write('*CLS');
            obj.setLoad();
            obj.Transport.write('VOLT:UNIT VPP');
            obj.checkErrors('initialisation');
        end

        function id = identify(obj)
            r = obj.Transport.query('*IDN?');
            p = strtrim(strsplit(r, ','));
            if numel(p) < 4 || ~contains(p{2}, '33220A')
                error('tim:gen:identity', 'Unexpected *IDN? response "%s" (expected a 33220A).', r);
            end
            id = struct('raw', r, 'vendor', p{1}, 'model', p{2}, 'serial', p{3}, 'firmware', p{4});
            obj.Identity = id;
        end

        %% ---- configuration -------------------------------------------------
        function configureSine(obj, f, vpp)
            %CONFIGURESINE Continuous sine (stepped-sine mode). Output stays OFF.
            obj.outputOff();
            obj.checkAmplitude(vpp);
            obj.Transport.write('SWE:STAT OFF');
            obj.Transport.write('TRIG:SOUR IMM');
            obj.Transport.write('FUNC SIN');
            obj.Transport.write(sprintf('FREQ %.6f', f));
            obj.Transport.write('VOLT:OFFS 0');
            obj.Transport.write(sprintf('VOLT %.4f', vpp));
            obj.checkErrors('configureSine');
            obj.verifyNumeric('FREQ?', f, 1e-6, 'frequency');
            obj.verifyNumeric('VOLT?', vpp, 1e-3, 'amplitude');
            obj.Mode = 'sine';
        end

        function setFrequency(obj, f)
            %SETFREQUENCY Change the sine frequency (phase continuous, output unchanged).
            if ~strcmp(obj.Mode, 'sine')
                error('tim:gen:mode', 'setFrequency requires sine mode.');
            end
            obj.Transport.write(sprintf('FREQ %.6f', f));
            obj.checkErrors('setFrequency');
        end

        function configureSweep(obj, s)
            %CONFIGURESWEEP BUS-triggered single sweep. Output stays OFF.
            %   s.fStart, s.fStop [Hz], s.duration [s], s.spacing 'LOG'|'LIN',
            %   s.amplitudeVpp [Vpp]
            obj.outputOff();
            obj.checkAmplitude(s.amplitudeVpp);
            if s.duration < 1e-3 || s.duration > 500
                error('tim:gen:sweep', 'Sweep time %.3g s outside 1 ms .. 500 s (manual p.219).', s.duration);
            end
            if s.fStart <= 0 || s.fStop <= 0
                error('tim:gen:sweep', 'Sweep frequencies must be positive.');
            end
            spacing = upper(s.spacing);
            if ~any(strcmp(spacing, {'LOG', 'LIN'}))
                error('tim:gen:sweep', 'Sweep spacing must be LOG or LIN.');
            end
            % Recommended order (manual p.215-216): function, freq, ampl, offset,
            % start/stop, spacing, time, trigger source, sweep state last.
            w = @(c) obj.Transport.write(c);
            w('SWE:STAT OFF');
            w('FUNC SIN');
            w(sprintf('FREQ %.6f', s.fStart));
            w('VOLT:OFFS 0');
            w(sprintf('VOLT %.4f', s.amplitudeVpp));
            w(sprintf('FREQ:STAR %.6f', s.fStart));
            w(sprintf('FREQ:STOP %.6f', s.fStop));
            w(['SWE:SPAC ' spacing]);
            w(sprintf('SWE:TIME %.6f', s.duration));
            w('TRIG:SOUR BUS');
            w('OUTP:TRIG:SLOP POS');
            w('OUTP:TRIG ON');      % rear Trig Out pulse at sweep start (p.233)
            w('SWE:STAT ON');
            obj.checkErrors('configureSweep');
            obj.verifyNumeric('FREQ:STAR?', s.fStart, 1e-6, 'sweep start');
            obj.verifyNumeric('FREQ:STOP?', s.fStop, 1e-6, 'sweep stop');
            obj.verifyNumeric('SWE:TIME?', s.duration, 1e-6, 'sweep time');
            obj.verifyNumeric('VOLT?', s.amplitudeVpp, 1e-3, 'amplitude');
            sp = obj.Transport.query('SWE:SPAC?');
            if ~strncmpi(sp, spacing, 3)
                error('tim:gen:verify', 'Sweep spacing read-back "%s" ~= "%s".', sp, spacing);
            end
            obj.SweepSettings = s;
            obj.Mode = 'sweep';
        end

        function configureNoise(obj, vpp)
            %CONFIGURENOISE Built-in Gaussian noise (optional broadband mode).
            obj.outputOff();
            obj.checkAmplitude(vpp);
            obj.Transport.write('SWE:STAT OFF');
            obj.Transport.write('TRIG:SOUR IMM');
            obj.Transport.write('FUNC NOIS');
            obj.Transport.write('VOLT:OFFS 0');
            obj.Transport.write(sprintf('VOLT %.4f', vpp));
            obj.checkErrors('configureNoise');
            obj.verifyNumeric('VOLT?', vpp, 1e-3, 'amplitude');
            obj.Mode = 'noise';
        end

        %% ---- output / trigger ---------------------------------------------
        function armOutput(obj, tf)
            %ARMOUTPUT Permission flag set by the measurement session only after
            %   the user explicitly starts a measurement.
            obj.OutputArmed = logical(tf);
            if ~tf, obj.outputOff(); end
        end

        function outputOn(obj)
            if ~obj.OutputArmed
                error('tim:gen:notArmed', ...
                    'Output enable refused: no measurement has been explicitly started (armOutput(true) not called).');
            end
            if strcmp(obj.Mode, 'none')
                error('tim:gen:mode', 'Output enable refused: generator not configured.');
            end
            % Re-check amplitude against the safety limit right before enabling
            % (open-circuit voltage, whatever the load setting).
            v = str2double(obj.Transport.query('VOLT?'));
            if ~(v * obj.ocFactor() <= obj.MaxVpp * (1 + 1e-6))
                error('tim:gen:amplitude', 'Programmed amplitude %.4g Vpp at load %s (open circuit %.4g Vpp) exceeds MaxVpp %.4g Vpp.', ...
                    v, obj.Load, v * obj.ocFactor(), obj.MaxVpp);
            end
            obj.Transport.write('OUTP ON');
            obj.checkErrors('outputOn');
        end

        function outputOff(obj)
            % Never throws: used in cleanup paths.
            try
                if obj.Transport.isOpen()
                    obj.Transport.write('OUTP OFF');
                end
            catch err
                warning('tim:gen:outputOff', 'Could not switch output off: %s', err.message);
            end
        end

        function tf = isOutputOn(obj, timeout)
            %ISOUTPUTON Output state read back from the instrument (OUTP?).
            %   isOutputOn(timeout) waits at most timeout s for the answer. An
            %   answer other than 0 or 1 raises tim:gen:verify (never reported
            %   as "off").
            if nargin < 2
                r = obj.Transport.query('OUTP?');
            else
                r = obj.Transport.query('OUTP?', timeout);
            end
            v = str2double(r);
            if ~(v == 0 || v == 1)
                error('tim:gen:verify', 'Unexpected answer "%s" to OUTP? (output state unknown).', r);
            end
            tf = v == 1;
        end

        function triggerSweep(obj)
            if ~strcmp(obj.Mode, 'sweep')
                error('tim:gen:mode', 'triggerSweep requires a configured sweep.');
            end
            obj.Transport.write('*TRG');
        end

        function tf = waitComplete(obj, timeout)
            %WAITCOMPLETE *OPC? blocks until the sweep is complete (manual p.220).
            r = obj.Transport.query('*OPC?', timeout);
            tf = strcmp(strtrim(r), '1');
        end

        %% ---- errors ----------------------------------------------------------
        function errs = readErrors(obj)
            errs = {};
            for i = 1:25
                r = obj.Transport.query('SYST:ERR?');
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
            errs = obj.readErrors();
            if ~isempty(errs)
                obj.outputOff();
                error('tim:gen:scpiError', '33220A reported error(s) during %s: %s', ...
                    context, strjoin(errs, ' | '));
            end
        end

        %% ---- shutdown ----------------------------------------------------------
        function close(obj)
            if isempty(obj.Transport), return; end
            obj.OutputArmed = false;
            obj.outputOff();
            try
                if obj.Transport.isOpen()
                    obj.Transport.write('SWE:STAT OFF');
                    obj.Transport.write('SYST:LOC');
                end
            catch
            end
            try, obj.Transport.close(); catch, end
        end

        function delete(obj)
            try, obj.close(); catch, end
        end

        function r = checkConnection(obj)
            %CHECKCONNECTION Contract: before every excitation, and every 60 s
            %   while the window is idle. The 33220A drops an idle socket
            %   connection now and then without telling the PC (hardware check
            %   2026-10-12: also with a static IP, also without MATLAB); the
            %   next command then gets a reset, which MATLAB's tcpclient prints
            %   as a stack trace in the command window. So a connection idle for
            %   more than ReopenAfterIdle_s (30 s) is not used again but
            %   replaced by a new one (owner decision 2026-10-12): nothing is
            %   sent on the old one. A connection used more recently is checked
            %   with OUTP? (2 s time-out) and replaced when that fails. A new
            %   connection: *IDN? must name the same serial number, the output
            %   is switched off, the error queue cleared and OUTP:LOAD /
            %   VOLT:UNIT set again; the next measurement configures the
            %   waveform as always. r.state 'ok' | 'reopened' (an idle
            %   connection replaced as a precaution, not logged by the session)
            %   | 'reconnected' (a dropped connection found and replaced);
            %   r.detail; tim:instr:connectionLost when no new connection can be
            %   opened (nothing is armed: the output stays disarmed). On the
            %   protocol mock (no idleSeconds) only the OUTP? check runs.
            r = struct('state', 'ok', 'detail', '');
            if isempty(obj.Transport) || ~ismethod(obj.Transport, 'reopen'), return; end
            idle = 0;
            if ismethod(obj.Transport, 'idleSeconds'), idle = obj.Transport.idleSeconds(); end
            first = [];
            if idle <= obj.ReopenAfterIdle_s
                try
                    obj.isOutputOn(2);
                    return
                catch first
                end
            end
            obj.OutputArmed = false;
            before = obj.Identity;
            try
                obj.Transport.reopen();
                obj.identify();
                if ~strcmp(obj.Identity.serial, before.serial)
                    other = obj.Identity.raw; obj.Identity = before;
                    try, obj.Transport.write('OUTP OFF'); catch, end
                    error('tim:gen:identity', 'another instrument answered (%s), not s/n %s', other, before.serial);
                end
                obj.Transport.write('OUTP OFF');
                obj.Transport.write('*CLS');
                obj.setLoad();
                obj.Transport.write('VOLT:UNIT VPP');
                obj.checkErrors('the reconnection');
            catch err
                error('tim:instr:connectionLost', ['The connection to the generator was lost and could not be ' ...
                    're-opened (%s). Check the LAN cable and the generator, then Disconnect and Connect.'], err.message);
            end
            obj.Mode = 'none';                        % configured again by the next measurement
            if isempty(first)
                r = struct('state', 'reopened', 'detail', sprintf(['connection idle for %.0f s replaced by a new ' ...
                    'one: %s s/n %s, output off'], idle, obj.Identity.model, obj.Identity.serial));
                return
            end
            why = 'no answer';
            if strcmp(first.identifier, 'tim:scpi:connectionLost'), why = 'the instrument had closed it'; end
            r = struct('state', 'reconnected', 'detail', sprintf(['connection re-opened (%s): %s s/n %s, ' ...
                'output off'], why, obj.Identity.model, obj.Identity.serial));
        end

        %% ---- contract: identity, metadata, time-out ----------------------
        function id = identity(obj)
            %IDENTITY vendor, model, serial, firmware, raw (*IDN? reply); no I/O.
            id = tim.instr.Instrument.emptyIdentity();
            f = fieldnames(id);
            for i = 1:numel(f)
                if isfield(obj.Identity, f{i}), id.(f{i}) = obj.Identity.(f{i}); end
            end
        end

        function md = metadata(obj)
            %METADATA Stored with every measurement: contract fields plus the
            %   fields of md.generator before 1.2.0 (identity, host, port,
            %   maxVpp, load).
            d = tim.instr.Keysight33220A.describe();
            st = obj.Settings;
            if isempty(fieldnames(st)), st = struct('host', '', 'port', NaN, 'timeout', NaN); end
            md = struct('driver', d.name, 'displayName', d.displayName, 'roles', {obj.rolesInUse()}, ...
                'identity', obj.identity(), 'sharedClock', false, 'settings', st, ...
                'host', st.host, 'port', st.port, 'maxVpp', obj.MaxVpp, 'load', obj.Load);
        end

        function setTimeout(obj, t)
            %SETTIMEOUT Shorten the SCPI time-out (closing the window).
            if ~isempty(obj.Transport) && ismethod(obj.Transport, 'setTimeout')
                obj.Transport.setTimeout(t);
            end
        end
    end

    %% ---- contract: class-level members ----------------------------------
    methods (Static)
        function d = describe()
            d = struct('name', 'keysight33220a', ...
                'displayName', 'Keysight/Agilent 33220A function generator', ...
                'labels', struct('source', 'Generator'), ...
                'defaults', struct('settings', struct('host', '169.254.2.20', 'port', 5025, 'timeout', 5)), ...
                'texts', struct('settle', '', 'noun', 'generator', 'closed', 'output off'), ...
                'simulation', 'protocol');
        end

        function c = capabilities()
            % limits: 33220A User's Guide (docs/ref_33220A_scpi.md); amplitude
            % per OUTP:LOAD: 20 / 10 Vpp maximum, 20 / 10 mVpp minimum (INF / 50);
            % any load 1 .. 10000 ohm (p.189): the INF range x R / (R + 50)
            src = struct('waveforms', {{'sine', 'sweep', 'noise'}}, 'sweepSpacing', {{'LOG', 'LIN'}}, ...
                'frequencyRange', [1e-6 20e6], 'bandFraction', NaN, 'loads', {{'INF', '50'}}, ...
                'maxVpp', [20 10], 'minVpp', [0.02 0.01], 'loadRange', [1 10000], 'sweepTime', [1e-3 500], 'noiseCrest', 3.3, ...
                'outputImpedance_ohm', 50, 'trigger', 'bus', 'readback', 'instrument', 'levelKnown', true);
            c = struct('roles', {{'source'}}, 'sharedClock', false, 'rolesTogether', false, ...
                'products', struct('name', {}, 'feature', {}), 'source', src);
        end

        function s = connectionSteps()
            s = struct('key', 'gen', 'label', 'connect (33220A, SCPI)', 'role', 'source', 'phase', 'connect');
        end

        function report = checkConfig(cfg)
            %CHECKCONFIG Driver settings (generator.keysight33220a) and the
            %   generic source limits (tim.instr.SignalSource.checkSourceConfig).
            d = tim.instr.Keysight33220A.describe();
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
            report = tim.instr.SignalSource.checkSourceConfig(cfg, tim.instr.Keysight33220A.capabilities(), d.displayName);
        end

        function obj = fromConfig(cfg, ctx)
            %FROMCONFIG Connect (SCPI over TCP, or the mock on ctx.rig), identify,
            %   output OFF (constructor). Reports the checklist step 'gen'.
            st = ctx.settings;
            sim = strcmp(ctx.mode, 'simulation');
            if sim
                detail = 'simulated generator';
            else
                detail = sprintf('%s:%d (SCPI over TCP)', st.host, st.port);
            end
            tim.instr.Instrument.reportStep(ctx, 'gen', 'run', detail);
            if sim
                tr = tim.instr.MockScpiTransport(ctx.rig);
            else
                tr = tim.instr.ScpiTcpTransport(st.host, st.port, st.timeout);
            end
            try
                obj = tim.instr.Keysight33220A(tr, 'MaxVpp', cfg.generator.maxVpp, 'Load', cfg.generator.load);
            catch err
                try, tr.close(); catch, end
                rethrow(err);
            end
            obj.Settings = st;
            obj.Roles = ctx.roles;
            tim.instr.Instrument.reportStep(ctx, 'gen', 'ok', sprintf('%s – output off', obj.Identity.raw));
        end

        function h = testHooks(obj)
            %TESTHOOKS Simulation only: handles into the SCPI mock (contract tests).
            tr = obj.Transport;
            if ~isa(tr, 'tim.instr.MockScpiTransport')
                error('tim:instr:noHooks', 'Test hooks need the generator on its mock transport (simulation).');
            end
            h = struct();
            h.traffic = @() tr.Log;
            h.breakLink = @() setProperty(tr, 'Broken', true);
            h.outputOn = @() tr.State.OUTP == 1;
            h.levelHistory = @() programmedLevels(tr.Log);
            h.forceOutputOn = @() tr.write('OUTP ON');          % front panel / another program
            h.forceLevel = @(vpp) tr.write(sprintf('VOLT %.4f', vpp));
            h.injectError = @() setProperty(tr, 'InjectError', '-222,"Data out of range"');
            h.dropConnection = @() setProperty(tr, 'Dropped', true);   % the 33220A drops it unnoticed
        end
    end

    methods (Access = private)
        function checkAmplitude(obj, vpp)
            % vpp: the programmed level at the load setting
            if ~(isscalar(vpp) && vpp > 0)
                error('tim:gen:amplitude', 'Amplitude must be a positive scalar [Vpp].');
            end
            oc = vpp * obj.ocFactor();
            if oc > obj.MaxVpp * (1 + 1e-9)
                error('tim:gen:amplitude', ['Requested %.4g Vpp at load %s (open circuit %.4g Vpp) exceeds the configured ' ...
                    'safety limit MaxVpp = %.4g Vpp (open circuit).'], vpp, obj.Load, oc, obj.MaxVpp);
            end
            [lo, hi] = tim.instr.SignalSource.levelRange(tim.instr.Keysight33220A.capabilities().source, obj.Load);
            if vpp < lo * (1 - 1e-9) || vpp > hi * (1 + 1e-9)
                error('tim:gen:amplitude', 'Requested %.4g Vpp outside the range of the instrument at load %s (%.4g .. %.4g Vpp).', ...
                    vpp, obj.Load, lo, hi);
            end
        end

        function f = ocFactor(obj)
            % open-circuit voltage per volt programmed at the load setting
            f = tim.instr.SignalSource.openCircuitFactor(tim.instr.Keysight33220A.capabilities().source, obj.Load);
        end

        function setLoad(obj)
            % OUTP:LOAD; a numeric load is read back (the generator answers in ohm)
            obj.Transport.write(['OUTP:LOAD ' obj.Load]);
            R = tim.instr.SignalSource.loadOhm(obj.Load);
            if isfinite(R), obj.verifyNumeric('OUTP:LOAD?', R, 1e-6, 'output load'); end
        end

        function verifyNumeric(obj, q, expected, relTol, what)
            v = str2double(obj.Transport.query(q));
            if ~(abs(v - expected) <= relTol * max(abs(expected), 1e-12) + 1e-9)
                obj.outputOff();
                error('tim:gen:verify', 'Read-back of %s = %.10g differs from requested %.10g.', what, v, expected);
            end
        end
    end
end

function setProperty(obj, name, value)
% assignment for the test hooks (an anonymous function cannot assign)
obj.(name) = value;
end

function v = programmedLevels(log)
% every amplitude the mock received ('> VOLT <Vpp>'), in order
tok = regexp(log, '^> VOLT ([-+0-9.eE]+)$', 'tokens', 'once');
tok = tok(~cellfun(@isempty, tok));
v = cellfun(@(t) str2double(t{1}), tok);
v = v(:).';
end

function mustBeLoad(load)
% 'INF' or a resistance 1 .. 10000 ohm written as a number (OUTP:LOAD, manual p.189)
if ~tim.instr.SignalSource.supportsLoad(tim.instr.Keysight33220A.capabilities().source, load)
    error('tim:gen:load', 'Output load ''%s'': use INF or a resistance of 1 to 10000 ohm written as a number.', load);
end
end

function t = canonicalLoad(load)
% '600.0' -> '600', 'inf' -> 'INF' (the text sent with OUTP:LOAD and stored)
R = tim.instr.SignalSource.loadOhm(load);
if isinf(R), t = 'INF'; else, t = sprintf('%.10g', R); end
end
