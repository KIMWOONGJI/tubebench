classdef MockScpiTransport < handle
    %MOCKSCPITRANSPORT Software model of a 33220A SCPI socket (simulation mode).
    %
    %   Implements the subset of commands used by tim.instr.Keysight33220A,
    %   with the documented side effects (see docs/ref_33220A_scpi.md):
    %     * *TRG is ignored with error -211 unless TRIG:SOUR BUS and SWE:STAT ON
    %     * SYST:ERR? FIFO queue, *CLS clears it, *RST does not
    %     * unknown headers produce -113
    %   If a tim.sim.SimulatedRig is attached, output/trigger events are
    %   forwarded so the simulated acquisition "hears" the excitation.
    %
    %   Fault injection: set FailNextQuery = true to emulate a timeout,
    %   InjectError = '-222,"Data out of range"' to push an error,
    %   Broken = true to emulate a lost link (every command fails, nothing
    %   reaches the instrument, reopen() fails too), or Dropped = true to
    %   emulate the 33220A dropping an idle connection unnoticed (hardware
    %   check 2026-10-12): the next write or query fails with
    %   tim:scpi:connectionLost and reaches nothing, isOpen() is false
    %   afterwards, and reopen() opens a new connection (the instrument keeps
    %   its settings, as the real one does).
    %
    %   Log lists every command ('> cmd'), every response ('< resp') and the
    %   close; the same lines go to tim.instr.mockBusLog (bus 'SCPI') while
    %   it records (tests/TestBusTraffic).

    properties
        Rig = []                 % optional tim.sim.SimulatedRig
        IdnString = 'Agilent Technologies,33220A,MOCK0001,2.02-2.02-22-2'
        FailNextQuery logical = false
        InjectError char = ''
        Broken logical = false   % lost link: every write / query fails with tim:scpi:timeout
        Dropped logical = false  % the instrument dropped the connection: the next write / query fails
    end
    properties (SetAccess = private)
        State struct
        ErrorQueue cell = {}
        Log cell = {}
        Closed logical = false
        Lost logical = false     % a write / query found the connection dropped (until reopen)
    end

    methods
        function obj = MockScpiTransport(rig)
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
            if ~isempty(obj.InjectError)
                obj.ErrorQueue{end+1} = obj.InjectError; obj.InjectError = '';
            end
        end

        function resp = query(obj, cmd, ~)
            obj.assertOpen();
            obj.assertLink(cmd);
            obj.addLog(['> ' cmd]);
            if obj.FailNextQuery
                obj.FailNextQuery = false;
                error('tim:scpi:timeout', 'No response to "%s" (mock timeout).', cmd);
            end
            resp = obj.answer(upper(strtrim(cmd)));
            obj.addLog(['< ' resp]);
        end

        function tf = isOpen(obj), tf = ~obj.Closed && ~obj.Lost; end
        function close(obj)
            if ~obj.Closed, obj.addLog('close'); end
            obj.Closed = true;
        end
        function reopen(obj)
            %REOPEN A new connection to the same instrument (state kept).
            if obj.Broken
                error('tim:scpi:connect', 'Cannot open TCP socket (mock: link lost).');
            end
            obj.addLog('reconnect');
            obj.Closed = false; obj.Lost = false; obj.Dropped = false;
        end
    end

    methods (Access = private)
        function resetState(obj)
            obj.State = struct('FUNC', 'SIN', 'FREQ', 1e3, 'VOLT', 0.1, 'VOLT_UNIT', 'VPP', ...
                'VOLT_OFFS', 0, 'OUTP', 0, 'OUTP_LOAD', 50, 'FREQ_STAR', 100, 'FREQ_STOP', 1e3, ...
                'SWE_SPAC', 'LIN', 'SWE_TIME', 1, 'SWE_STAT', 0, 'TRIG_SOUR', 'IMM', 'OUTP_TRIG', 0);
            obj.pushRig();
        end

        function assertOpen(obj)
            if obj.Closed, error('tim:scpi:closed', 'Mock transport closed.'); end
            if obj.Lost, error('tim:scpi:connectionLost', 'The connection was closed by the instrument (mock).'); end
        end

        function assertLink(obj, cmd)
            if obj.Broken, error('tim:scpi:timeout', 'No response to "%s" (mock: link lost).', cmd); end
            if obj.Dropped
                % the command reaches nobody; the instrument answers with a reset
                obj.Lost = true;
                obj.addLog(sprintf('! connection lost while sending "%s"', cmd));
                error('tim:scpi:connectionLost', ['The connection was closed while sending "%s": the instrument ' ...
                    'dropped it (mock).'], cmd);
            end
        end

        function addLog(obj, line)
            obj.Log{end+1} = line;
            tim.instr.mockBusLog('add', 'SCPI', line);
        end

        function execute(obj, cmd)
            if isempty(cmd), return; end
            tok = regexp(cmd, '^(\*?[A-Za-z:]+)\s*(.*)$', 'tokens', 'once');
            if isempty(tok), obj.pushErr(-113, 'Undefined header'); return; end
            hdr = upper(tok{1}); arg = strtrim(tok{2});
            num = str2double(regexprep(arg, '[A-Za-z\s]+$', ''));
            switch hdr
                case '*RST',  obj.resetState();
                case '*CLS',  obj.ErrorQueue = {};
                case 'FUNC',  obj.State.FUNC = upper(arg(1:min(3,end)));
                case 'FREQ',  obj.setNum('FREQ', num, 1e-6, 20e6);
                case 'VOLT'
                    % 20 Vpp open circuit; at a load setting R the voltage across R
                    R = obj.State.OUTP_LOAD; vmax = 20; if R < 1e30, vmax = 20 * R / (R + 50); end
                    obj.setNum('VOLT', num, vmax/1000, vmax);
                case 'VOLT:UNIT', obj.State.VOLT_UNIT = upper(arg);
                case 'VOLT:OFFS', obj.setNum('VOLT_OFFS', num, -10, 10);
                case 'OUTP'
                    obj.State.OUTP = double(any(strcmpi(arg, {'ON', '1'})));
                    obj.pushRig();
                case 'OUTP:LOAD'          % INF or 1 .. 10000 ohm (manual p.189)
                    if strncmpi(arg, 'INF', 3), obj.State.OUTP_LOAD = 9.9e37; else, obj.setNum('OUTP_LOAD', num, 1, 1e4); end
                case 'OUTP:TRIG', obj.State.OUTP_TRIG = double(any(strcmpi(arg, {'ON', '1'})));
                case 'OUTP:TRIG:SLOP' % accepted
                case 'FREQ:STAR', obj.setNum('FREQ_STAR', num, 1e-6, 20e6);
                case 'FREQ:STOP', obj.setNum('FREQ_STOP', num, 1e-6, 20e6);
                case 'SWE:SPAC', obj.State.SWE_SPAC = upper(arg(1:3));
                case 'SWE:TIME', obj.setNum('SWE_TIME', num, 1e-3, 500);
                case 'SWE:STAT'
                    on = any(strcmpi(arg, {'ON', '1'}));
                    if on && strcmp(obj.State.FUNC, 'NOI')
                        obj.pushErr(-221, 'Settings conflict; not able to sweep this function');
                    else
                        obj.State.SWE_STAT = double(on);
                    end
                case 'TRIG:SOUR', obj.State.TRIG_SOUR = upper(arg(1:3));
                case '*TRG'
                    if strcmp(obj.State.TRIG_SOUR, 'BUS') && obj.State.SWE_STAT
                        if ~isempty(obj.Rig), obj.Rig.generatorTrigger(); end
                    else
                        obj.pushErr(-211, 'Trigger ignored');
                    end
                case {'SYST:LOC', 'SYST:REM', 'DISP:TEXT', 'DISP:TEXT:CLE', '*WAI'}
                    % accepted, no state relevant for simulation
                otherwise
                    obj.pushErr(-113, 'Undefined header');
            end
            if any(strcmp(hdr, {'FUNC', 'FREQ', 'VOLT', 'VOLT:OFFS', 'FREQ:STAR', 'FREQ:STOP', ...
                    'SWE:SPAC', 'SWE:TIME', 'SWE:STAT', 'TRIG:SOUR'}))
                obj.pushRig();
            end
        end

        function setNum(obj, key, v, lo, hi)
            if isnan(v)
                obj.pushErr(-224, 'Illegal parameter value'); return;
            end
            if v < lo || v > hi
                obj.pushErr(-222, 'Data out of range');
                v = min(max(v, lo), hi);
            end
            obj.State.(key) = v;
        end

        function pushErr(obj, code, msg)
            if numel(obj.ErrorQueue) >= 20
                obj.ErrorQueue{end} = '-350,"Queue overflow"';
            else
                obj.ErrorQueue{end+1} = sprintf('%+d,"%s"', code, msg);
            end
        end

        function r = answer(obj, cmd)
            s = obj.State;
            switch cmd
                case '*IDN?', r = obj.IdnString;
                case '*OPC?'
                    % pending operations complete first: a triggered sweep runs
                    % to its end (the virtual time passes, the stream records it)
                    if ~isempty(obj.Rig), obj.Rig.finishSweep(); end
                    r = '1';
                case 'SYST:ERR?'
                    if isempty(obj.ErrorQueue)
                        r = '+0,"No error"';
                    else
                        r = obj.ErrorQueue{1}; obj.ErrorQueue(1) = [];
                    end
                case 'OUTP?', r = sprintf('%d', s.OUTP);
                case 'FUNC?', r = s.FUNC;
                case 'FREQ?', r = sprintf('%+.13E', s.FREQ);
                case 'VOLT?', r = sprintf('%+.13E', s.VOLT);
                case 'VOLT:UNIT?', r = s.VOLT_UNIT;
                case 'VOLT:OFFS?', r = sprintf('%+.13E', s.VOLT_OFFS);
                case 'OUTP:LOAD?', r = sprintf('%+.13E', s.OUTP_LOAD);
                case 'FREQ:STAR?', r = sprintf('%+.13E', s.FREQ_STAR);
                case 'FREQ:STOP?', r = sprintf('%+.13E', s.FREQ_STOP);
                case 'SWE:SPAC?', r = s.SWE_SPAC;
                case 'SWE:TIME?', r = sprintf('%+.13E', s.SWE_TIME);
                case 'SWE:STAT?', r = sprintf('%d', s.SWE_STAT);
                case 'TRIG:SOUR?', r = s.TRIG_SOUR;
                otherwise
                    obj.pushErr(-113, 'Undefined header'); r = '';
            end
        end

        function pushRig(obj)
            if ~isempty(obj.Rig), obj.Rig.setGeneratorState(obj.State); end
        end
    end
end
