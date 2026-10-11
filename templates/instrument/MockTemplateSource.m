classdef MockTemplateSource < handle
    %MOCKTEMPLATESOURCE TEMPLATE of a protocol mock: the instrument of TemplateSource in software.
    %
    %   THIS IS A TEMPLATE. Copy it with the driver (docs/adding_an_instrument.md,
    %   steps 3 and 5) to +tim/+instr/Mock<Name>.m with the same replacements
    %   ('TemplateSource' -> '<Name>', 'templatesource' -> '<registry name>').
    %   Lines marked TODO hold instrument facts (commands, replies, limits,
    %   error codes): make them say what YOUR instrument's manual says - the
    %   same commands as the driver, with the documented side effects, so that
    %   the simulation tests what the real instrument would do. Then replace
    %   this paragraph by a line naming your instrument and its reference
    %   document; "TODO" must not occur in the file any more.
    %
    %   tr = tim.instr.MockTemplateSource(rig)
    %   The same methods as the hardware transport (tim.instr.ScpiTcpTransport):
    %   write(cmd), r = query(cmd, timeout), isOpen(), close(), setTimeout(t).
    %   It understands exactly the commands the driver sends:
    %     * error queue (FIFO): an unknown header -113, a value out of range
    %       -222 (the value is clamped), a sweep of noise -221, a trigger that
    %       is not armed -211; *CLS clears the queue
    %     * replies in the instrument's format (identification, numbers)
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
        IdnString = 'tubebench template,TEMPLATE-GEN,TMPL-0001,1.0'   % TODO a realistic identification reply
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
        function obj = MockTemplateSource(rig)
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
                case 'error', obj.PendingError = '-222,"Data out of range"';    % TODO an error of this instrument
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
            % power-on state (TODO from the manual: output off, its default settings)
            obj.State = struct('output', false, 'func', 'SIN', 'freq', 1e3, 'vpp', 0.1, 'offset', 0, ...
                'load', 'INF', 'unit', 'VPP', 'start', 100, 'stop', 1e3, 'spacing', 'LIN', 'time', 1, ...
                'sweep', false, 'trigger', 'IMM');
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
            tim.instr.mockBusLog('add', 'TemplateSource', line);
        end

        function execute(obj, cmd)
            % one command (TODO: the instrument's command set and side effects)
            if isempty(cmd), return; end
            tok = regexp(cmd, '^(\*?[A-Za-z0-9:]+)\s*(.*)$', 'tokens', 'once');   % headers may carry a channel number
            if isempty(tok), obj.pushErr(-113, 'Undefined header'); return; end
            hdr = upper(tok{1}); arg = strtrim(tok{2});
            num = str2double(arg);
            on = any(strcmpi(arg, {'ON', '1'}));
            [vmin, vmax] = obj.levelRange();
            switch hdr
                case '*CLS',      obj.ErrorQueue = {};
                case 'OUTP',      obj.State.output = on;
                case 'OUTP:LOAD', obj.State.load = upper(arg);
                case 'VOLT:UNIT', obj.State.unit = upper(arg);
                case 'FUNC',      obj.State.func = upper(arg);
                case 'FREQ',      obj.State.freq = obj.inRange(num, 1e-3, 1e6);       % TODO limits
                case 'VOLT'
                    obj.LevelLog(end+1) = num;                                    % every level received
                    obj.State.vpp = obj.inRange(num, vmin, vmax);
                case 'VOLT:OFFS', obj.State.offset = obj.inRange(num, -10, 10);
                case 'FREQ:STAR', obj.State.start = obj.inRange(num, 1e-3, 1e6);
                case 'FREQ:STOP', obj.State.stop = obj.inRange(num, 1e-3, 1e6);
                case 'SWE:SPAC',  obj.State.spacing = upper(arg);
                case 'SWE:TIME',  obj.State.time = obj.inRange(num, 1e-3, 500);
                case 'SWE:STAT'
                    if on && strncmp(obj.State.func, 'NOI', 3)
                        obj.pushErr(-221, 'Settings conflict');                   % noise cannot be swept
                    else
                        obj.State.sweep = on;
                    end
                case 'TRIG:SOUR', obj.State.trigger = upper(arg);
                case '*TRG'
                    if strcmp(obj.State.trigger, 'BUS') && obj.State.sweep
                        if ~isempty(obj.Rig), obj.Rig.generatorTrigger(); end    % the sweep starts
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
            % reply to a query (TODO: the instrument's reply formats)
            s = obj.State;
            switch cmd
                case '*IDN?',      r = obj.IdnString;
                case '*OPC?'                              % after the end of a triggered sweep
                    if ~isempty(obj.Rig), obj.Rig.finishSweep(); end
                    r = '1';
                case 'SYST:ERR?'
                    if isempty(obj.ErrorQueue)
                        r = '+0,"No error"';
                    else
                        r = obj.ErrorQueue{1}; obj.ErrorQueue(1) = [];
                    end
                case 'OUTP?',      r = sprintf('%d', s.output);
                case 'FREQ?',      r = sprintf('%+.13E', s.freq);
                case 'VOLT?',      r = sprintf('%+.13E', s.vpp);
                case 'FREQ:STAR?', r = sprintf('%+.13E', s.start);
                case 'FREQ:STOP?', r = sprintf('%+.13E', s.stop);
                case 'SWE:TIME?',  r = sprintf('%+.13E', s.time);
                case 'SWE:SPAC?',  r = s.spacing;
                otherwise
                    obj.pushErr(-113, 'Undefined header'); r = '';
            end
        end

        function [vmin, vmax] = levelRange(obj)
            % level range of the load setting (TODO from the manual)
            if strcmp(obj.State.load, '50'), vmin = 0.01; vmax = 10; else, vmin = 0.02; vmax = 20; end
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
            if numel(obj.ErrorQueue) >= 20
                obj.ErrorQueue{end} = '-350,"Queue overflow"';
            else
                obj.ErrorQueue{end+1} = sprintf('%+d,"%s"', code, msg);
            end
        end

        function pushRig(obj)
            % the generator state as the rig's function-generator model
            if isempty(obj.Rig), return; end
            s = obj.State;
            func = 'SIN'; if strncmp(s.func, 'NOI', 3), func = 'NOI'; end
            obj.Rig.setGeneratorState(struct('OUTP', double(s.output), 'FUNC', func, 'FREQ', s.freq, ...
                'VOLT', s.vpp, 'FREQ_STAR', s.start, 'FREQ_STOP', s.stop, 'SWE_SPAC', s.spacing, ...
                'SWE_TIME', s.time, 'SWE_STAT', double(s.sweep), 'TRIG_SOUR', s.trigger));
        end
    end
end
