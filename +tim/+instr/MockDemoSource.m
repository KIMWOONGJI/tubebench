classdef MockDemoSource < handle
    %MOCKDEMOSOURCE The demo signal generator DEMO-SG1 in software (protocol mock).
    %
    %   The protocol mock of tim.instr.DemoSource, the worked example of
    %   docs/adding_an_instrument.md (section 13), made from
    %   templates/instrument/MockTemplateSource.m. The DEMO-SG1 does not exist:
    %   this mock and docs/ref_demo_source.md (its "manual") define it, and the
    %   driver runs only on this mock (simulation mode).
    %
    %   tr = tim.instr.MockDemoSource(rig)
    %   The same methods as a hardware transport (tim.instr.ScpiTcpTransport):
    %   write(cmd), r = query(cmd, timeout), isOpen(), close(), setTimeout(t).
    %   It understands the DEMO-SG1 commands (SCPI with channel-numbered
    %   headers SOUR1:, OUTP1:, TRIG1:; docs/ref_demo_source.md section 3):
    %     * error queue (FIFO, 16 entries): an unknown header -113, a value
    %       out of range -222 (the value is clamped), a function other than
    %       SIN -224, a trigger that is not armed -211; *CLS clears the queue
    %     * replies: numbers as %+.13E, the output state as ON / OFF
    %   COUPLING TO THE VIRTUAL TUBE (simulation mode, tim.sim.SimulatedRig):
    %   a separate generator maps its state onto the rig's function-generator
    %   model (rig.setGeneratorState: output, function, frequency, Vpp, sweep)
    %   and starts a triggered sweep with rig.generatorTrigger(); the rig then
    %   synthesises the excitation on the generator's own clock while a DAQ
    %   driver records (docs/instrument_interface.md section 10).
    %
    %   Fault injection (the driver's testHooks): fault('broken') - the link is
    %   lost, every command fails; fault('error') - the instrument reports an
    %   error at its next command; frontPanel('output', tf) and
    %   frontPanel('level', vpp) - someone changes the instrument behind the
    %   driver's back (not bus traffic). Log lists every command ('> cmd'),
    %   every reply ('< reply') and the close; LevelLog every level received
    %   [Vpp]. The same lines go to tim.instr.mockBusLog while it records.

    properties
        Rig = []                     % tim.sim.SimulatedRig (simulation), or [] (driver unit tests)
        IdnString = 'tubebench demo,DEMO-SG1,DEMO-0001,1.0'   % identification reply (ref 2.1)
    end
    properties (SetAccess = private)
        State struct                 % the instrument's settings (see resetState)
        ErrorQueue cell = {}
        Log cell = {}
        LevelLog double = zeros(1, 0)
        Closed logical = false
        Broken logical = false       % lost link: every command fails
        PendingError char = ''       % error the instrument reports at its next command
    end

    methods
        function obj = MockDemoSource(rig)
            if nargin >= 1, obj.Rig = rig; end
            obj.resetState();
        end

        function write(obj, cmd)
            obj.assertOpen();
            obj.assertLink(cmd);
            obj.addLog(['> ' cmd]);
            parts = strsplit(cmd, ';');
            for i = 1:numel(parts)
                obj.execute(strtrim(parts{i}));
            end
            if ~isempty(obj.PendingError)
                obj.ErrorQueue{end+1} = obj.PendingError; obj.PendingError = '';
            end
        end

        function resp = query(obj, cmd, ~)
            obj.assertOpen();
            obj.assertLink(cmd);
            obj.addLog(['> ' cmd]);
            resp = obj.answer(upper(strtrim(cmd)));
            obj.addLog(['< ' resp]);
        end

        function tf = isOpen(obj), tf = ~obj.Closed; end

        function close(obj)
            if ~obj.Closed, obj.addLog('close'); end
            obj.Closed = true;
        end

        function setTimeout(~, ~)
            % the mock answers at once
        end

        %% ---- fault injection and the front panel (test hooks) ---------------
        function fault(obj, kind)
            %FAULT 'broken': lost link; 'error': an error at the next command.
            switch kind
                case 'broken', obj.Broken = true;
                case 'error', obj.PendingError = '-222,"Data out of range"';    % (ref 2.2)
            end
        end

        function frontPanel(obj, what, value)
            %FRONTPANEL A change at the instrument behind the driver's back.
            switch what
                case 'output', obj.State.output = logical(value);
                case 'level', obj.State.vpp = value;
            end
            obj.pushRig();
        end
    end

    methods (Access = private)
        function resetState(obj)
            % power-on state (ref 2.4): output off, 1 kHz sine at 0.1 Vpp, sweep off
            obj.State = struct('output', false, 'func', 'SIN', 'freq', 1e3, 'vpp', 0.1, 'offset', 0, ...
                'start', 100, 'stop', 1e3, 'spacing', 'LIN', 'time', 1, 'sweep', false, 'trigger', 'IMM');
            obj.pushRig();
        end

        function assertOpen(obj)
            if obj.Closed, error('tim:scpi:closed', 'Mock transport closed.'); end
        end

        function assertLink(obj, cmd)
            if obj.Broken, error('tim:scpi:timeout', 'No response to "%s" (mock: link lost).', cmd); end
        end

        function addLog(obj, line)
            obj.Log{end+1} = line;
            tim.instr.mockBusLog('add', 'DemoSource', line);
        end

        function execute(obj, cmd)
            % one DEMO-SG1 command (docs/ref_demo_source.md section 3)
            if isempty(cmd), return; end
            tok = regexp(cmd, '^(\*?[A-Za-z0-9:]+)\s*(.*)$', 'tokens', 'once');
            if isempty(tok), obj.pushErr(-113, 'Undefined header'); return; end
            hdr = upper(tok{1}); arg = strtrim(tok{2});
            num = str2double(arg);
            on = any(strcmpi(arg, {'ON', '1'}));
            switch hdr
                case '*CLS',            obj.ErrorQueue = {};
                case 'OUTP1:STAT',      obj.State.output = on;
                case 'SOUR1:FUNC'
                    if strcmpi(arg, 'SIN')
                        obj.State.func = 'SIN';
                    else
                        obj.pushErr(-224, 'Illegal parameter value');     % sine only (ref 3.2)
                    end
                case 'SOUR1:FREQ',      obj.State.freq = obj.inRange(num, 0.1, 1e5);
                case 'SOUR1:VOLT'
                    obj.LevelLog(end+1) = num;                            % every level received
                    obj.State.vpp = obj.inRange(num, 0.002, 10);
                case 'SOUR1:VOLT:OFFS', obj.State.offset = obj.inRange(num, -5, 5);
                case 'SOUR1:SWE:STAR',  obj.State.start = obj.inRange(num, 0.1, 1e5);
                case 'SOUR1:SWE:STOP',  obj.State.stop = obj.inRange(num, 0.1, 1e5);
                case 'SOUR1:SWE:SPAC'
                    if any(strcmpi(arg, {'LOG', 'LIN'}))
                        obj.State.spacing = upper(arg);
                    else
                        obj.pushErr(-224, 'Illegal parameter value');
                    end
                case 'SOUR1:SWE:TIME',  obj.State.time = obj.inRange(num, 0.01, 300);
                case 'SOUR1:SWE:STAT',  obj.State.sweep = on;
                case 'TRIG1:SOUR',      obj.State.trigger = upper(arg);
                case '*TRG'
                    if strcmp(obj.State.trigger, 'BUS') && obj.State.sweep
                        if ~isempty(obj.Rig), obj.Rig.generatorTrigger(); end    % the sweep starts (ref 3.4)
                    else
                        obj.pushErr(-211, 'Trigger ignored');
                    end
                case 'SYST:LOC'
                    % front panel back to local: no state relevant for the simulation
                otherwise
                    obj.pushErr(-113, 'Undefined header');
            end
            obj.pushRig();
        end

        function r = answer(obj, cmd)
            % reply to a DEMO-SG1 query (docs/ref_demo_source.md section 3)
            s = obj.State;
            switch cmd
                case '*IDN?',           r = obj.IdnString;
                case '*OPC?',           r = '1';            % the mock has no clock: never busy
                case 'SYST:ERR?'
                    if isempty(obj.ErrorQueue)
                        r = '0,"No error"';
                    else
                        r = obj.ErrorQueue{1}; obj.ErrorQueue(1) = [];
                    end
                case 'OUTP1:STAT?'
                    if s.output, r = 'ON'; else, r = 'OFF'; end
                case 'SOUR1:FREQ?',     r = sprintf('%+.13E', s.freq);
                case 'SOUR1:VOLT?',     r = sprintf('%+.13E', s.vpp);
                case 'SOUR1:SWE:STAR?', r = sprintf('%+.13E', s.start);
                case 'SOUR1:SWE:STOP?', r = sprintf('%+.13E', s.stop);
                case 'SOUR1:SWE:TIME?', r = sprintf('%+.13E', s.time);
                case 'SOUR1:SWE:SPAC?', r = s.spacing;
                otherwise
                    obj.pushErr(-113, 'Undefined header'); r = '';
            end
        end

        function v = inRange(obj, v, lo, hi)
            % a value outside the instrument's range: error -222, value clamped
            if isnan(v)
                obj.pushErr(-224, 'Illegal parameter value'); v = lo; return
            end
            if v < lo || v > hi
                obj.pushErr(-222, 'Data out of range');
                v = min(max(v, lo), hi);
            end
        end

        function pushErr(obj, code, msg)
            % error queue of 16 entries; the last one says overflow (ref 2.2)
            if numel(obj.ErrorQueue) >= 16
                obj.ErrorQueue{end} = '-350,"Queue overflow"';
            else
                obj.ErrorQueue{end+1} = sprintf('%d,"%s"', code, msg);
            end
        end

        function pushRig(obj)
            % the generator state as the rig's function-generator model (sine only)
            if isempty(obj.Rig), return; end
            s = obj.State;
            obj.Rig.setGeneratorState(struct('OUTP', double(s.output), 'FUNC', 'SIN', 'FREQ', s.freq, ...
                'VOLT', s.vpp, 'FREQ_STAR', s.start, 'FREQ_STOP', s.stop, 'SWE_SPAC', s.spacing, ...
                'SWE_TIME', s.time, 'SWE_STAT', double(s.sweep), 'TRIG_SOUR', s.trigger));
        end
    end
end
