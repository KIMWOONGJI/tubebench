classdef MockTemplateCombined < handle
    %MOCKTEMPLATECOMBINED TEMPLATE of a protocol mock: the device session of TemplateCombined in software.
    %
    %   THIS IS A TEMPLATE. Copy it with the driver (docs/adding_an_instrument.md,
    %   steps 3 and 5) to +tim/+instr/Mock<Name>.m with the same replacements
    %   ('TemplateCombined' -> '<Name>', 'templatecombined' -> '<registry
    %   name>'). Lines marked TODO hold device facts (identity, supported
    %   rates, the flags it reports): make them say what YOUR device does.
    %   Then replace this paragraph by a line naming your device and its
    %   reference document; "TODO" must not occur in the file any more.
    %
    %   dev = tim.instr.MockTemplateCombined(rig)
    %   The same methods as the hardware device session the driver uses:
    %   identify(), fs = configure(c), writeZero(), start(),
    %   [y, st] = playRecord(x), stop(), close(), setTimeout(t).
    %   COUPLING TO THE VIRTUAL TUBE (simulation mode, tim.sim.SimulatedRig): a
    %   device that plays and records on one clock gives the rig its output
    %   samples and gets the microphone voltages of the same samples back,
    %   y = rig.respond(x); writeZero() is rig.respond(zeros(0, 1)) (the rig's
    %   OutputLog records "output at 0 V"). The contract tests read the rig's
    %   OutputLog to check what was really played. Like an analog output, the
    %   output keeps its last value after stop() and close(): only writeZero()
    %   sets 0 V (Playing, the test hook outputOn, shows it).
    %
    %   Fault injection (the driver's testHooks): fault('broken') - the link is
    %   lost, every operation fails; fault('error') - the device reports an
    %   error at its next operation; fault('stallAfter', n) - from the next
    %   acquisition on, no data after n samples (the device times out);
    %   fault('channel', c) - from the next acquisition on, input c reports a
    %   fault; fault('forceOn') - the output plays behind the driver's back.
    %   A failing operation raises BEFORE it is logged, so the AbortFcn check of
    %   the contract test sees no device operation after the failure. Log lists
    %   the device operations, one line per block played.

    properties
        Rig = []                     % tim.sim.SimulatedRig, or [] (noise only, driver unit tests)
        IdText = struct('vendor', 'tubebench template', 'model', 'TEMPLATE-DEV', ...   % TODO a realistic identity
            'serial', 'TMPL-0003', 'firmware', '1.0')
    end
    properties (SetAccess = private)
        Log cell = {}
        Closed logical = false
        Broken logical = false
        PendingError char = ''       % error the device reports at its next operation
        Running logical = false      % playing and recording
        Playing logical = false      % the output produces a signal (last block not all zero)
        Fs double = NaN
        Channels double = 1:4
        Recorded double = 0          % samples played and recorded since start
        StallAfter double = Inf
        FaultChannels double = []
        Next struct = struct('stallAfter', Inf, 'channels', [])   % faults of the next acquisition
    end
    properties (Constant)
        Rates = [8192 16384 32768]   % TODO rates the device can run
    end

    methods
        function obj = MockTemplateCombined(rig)
            if nargin >= 1, obj.Rig = rig; end
        end

        function id = identify(obj)
            obj.operation('identify');
            id = obj.IdText;
            id.raw = sprintf('%s %s  s/n %s  firmware %s', id.vendor, id.model, id.serial, id.firmware);
        end

        function fs = configure(obj, c)
            %CONFIGURE Channel setup; returns the rate the device runs at (the
            %   nearest supported one, as a device that coerces a requested rate).
            obj.operation(sprintf('configure %g S/s, %s, %s', c.sampleRate, c.range, c.filter));
            [~, k] = min(abs(obj.Rates - c.sampleRate));
            fs = obj.Rates(k);
            obj.Fs = fs;
            obj.Channels = c.channels;
        end

        function writeZero(obj)
            obj.operation('output 0 V');
            obj.Playing = false;
            if ~isempty(obj.Rig), obj.Rig.respond(zeros(0, 1)); end
        end

        function start(obj)
            obj.operation('start');
            obj.Running = true;
            obj.Recorded = 0;
            obj.StallAfter = obj.Next.stallAfter;
            obj.FaultChannels = obj.Next.channels;
        end

        function [y, st] = playRecord(obj, x)
            %PLAYRECORD Play x (m x 1 volts) and record the same m samples (m x C volts).
            x = x(:);
            m = numel(x);
            if obj.Recorded + m > obj.StallAfter
                error('tim:templatecombined:stalled', 'No data from the device after %d samples (time-out).', obj.Recorded);
            end
            obj.operation(sprintf('block %d-%d', obj.Recorded + 1, obj.Recorded + m));
            nCh = numel(obj.Channels);
            if isempty(obj.Rig)
                y = 1e-4 * randn(m, nCh);
            else
                v = obj.Rig.respond(x);                       % microphone volts of the same samples
                y = v(:, obj.Channels);
            end
            obj.Recorded = obj.Recorded + m;
            obj.Playing = any(x ~= 0);
            st = struct('fault', ismember(1:nCh, obj.FaultChannels), 'overload', false(1, nCh));
        end

        function stop(obj)
            % the output keeps its last value (as an NI analog output does):
            % only writeZero() sets it to 0 V
            obj.operation('stop');
            obj.Running = false;
        end

        function close(obj)
            % released: the output keeps its last value as well
            if ~obj.Closed, obj.Log{end+1} = 'close'; end
            obj.Closed = true;
            obj.Running = false;
        end

        function setTimeout(~, ~)
            % the mock answers at once
        end

        function fault(obj, kind, value)
            %FAULT 'broken' | 'error' | 'stallAfter', n | 'channel', c | 'forceOn' (test hooks).
            switch kind
                case 'broken', obj.Broken = true;
                case 'error', obj.PendingError = 'E-101 output buffer underrun';   % TODO an error of this device
                case 'stallAfter', obj.Next.stallAfter = value;
                case 'channel', obj.Next.channels = value;
                case 'forceOn', obj.Playing = true;
            end
        end
    end

    methods (Access = private)
        function operation(obj, op)
            % one operation on the device: refused when closed, not reachable or
            % failing (before it is logged), else logged
            if obj.Closed, error('tim:templatecombined:closed', 'Mock device closed (%s).', op); end
            if obj.Broken, error('tim:templatecombined:link', 'Mock device not reachable (%s).', op); end
            if ~isempty(obj.PendingError)
                e = obj.PendingError; obj.PendingError = '';
                error('tim:templatecombined:device', 'Device error during "%s": %s', op, e);
            end
            obj.Log{end+1} = op;
            tim.instr.mockBusLog('add', 'TemplateCombined', op);
        end
    end
end
