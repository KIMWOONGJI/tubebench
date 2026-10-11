classdef MockTemplateAcquisition < handle
    %MOCKTEMPLATEACQUISITION TEMPLATE of a protocol mock: the device session of TemplateAcquisition in software.
    %
    %   THIS IS A TEMPLATE. Copy it with the driver (docs/adding_an_instrument.md,
    %   steps 3 and 5) to +tim/+instr/Mock<Name>.m with the same replacements
    %   ('TemplateAcquisition' -> '<Name>', 'templateacquisition' -> '<registry
    %   name>'). Lines marked TODO hold device facts (identity, supported
    %   settings, the flags it reports): make them say what YOUR device does.
    %   Then replace this paragraph by a line naming your device and its
    %   reference document; "TODO" must not occur in the file any more.
    %
    %   dev = tim.instr.MockTemplateAcquisition(rig)
    %   The same methods as the hardware device session the driver uses:
    %   identify(), fs = configure(c), start(), [x, st] = read(), stop(),
    %   close(), setTimeout(t). read() delivers a fixed block of samples per
    %   call at once (no real-time pacing), so a simulation runs faster than
    %   real time and every scheduled generator command falls on the same block.
    %   COUPLING TO THE VIRTUAL TUBE (simulation mode, tim.sim.SimulatedRig): a
    %   separate acquisition takes its samples from rig.generate(m): the four
    %   microphone voltages produced by whatever source drives the rig (the
    %   33220A mock, another generator mock), on the DAQ clock. While it runs
    %   it registers advance() with rig.setProducer: a generator mock asked
    %   whether its sweep is complete lets the virtual time run on through it
    %   (rig.finishSweep), as a real device keeps recording meanwhile.
    %
    %   Fault injection (the driver's testHooks): fault('broken') - the link is
    %   lost, every operation fails; fault('stallAfter', n) - from the next
    %   acquisition on, data stop after n samples (Inf: normal again);
    %   fault('channel', c) - from the next acquisition on, input c reports a
    %   fault. Log lists the device operations (identify, configure, start,
    %   stop, close), not the data reads (as for a data stream).

    properties
        Rig = []                     % tim.sim.SimulatedRig, or [] (noise only, driver unit tests)
        BlockSamples double = 1024   % samples per channel delivered per read
        IdText = struct('vendor', 'tubebench template', 'model', 'TEMPLATE-DAQ', ...   % TODO a realistic identity
            'serial', 'TMPL-0002', 'firmware', '1.0')
    end
    properties (SetAccess = private)
        Log cell = {}
        Closed logical = false
        Broken logical = false
        Running logical = false
        Fs double = NaN              % rate after configure
        Channels double = 1:4
        StallAfter double = Inf      % of the running acquisition
        FaultChannels double = []
        Delivered double = 0         % samples produced in the running acquisition (read or pending)
        Pending double = zeros(0, 4) % produced, not yet read (advance)
        Next struct = struct('stallAfter', Inf, 'channels', [])   % faults of the next acquisition
    end
    properties (Constant)
        Rates = [8192 16384 32768]   % TODO rates the device can run
    end

    methods
        function obj = MockTemplateAcquisition(rig)
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

        function start(obj)
            obj.operation('start');
            obj.Running = true;
            obj.Delivered = 0;
            obj.Pending = zeros(0, numel(obj.Channels));
            obj.StallAfter = obj.Next.stallAfter;
            obj.FaultChannels = obj.Next.channels;
            % a generator mock waiting for the end of its sweep lets the virtual
            % time run on through this device (tim.sim.SimulatedRig.finishSweep)
            if ~isempty(obj.Rig), obj.Rig.setProducer(@() obj.advance()); end
        end

        function [x, st] = read(obj)
            %READ The samples since the last read (BlockSamples, or none after a stall).
            if obj.Closed, error('tim:templateacquisition:closed', 'Mock device closed.'); end
            if obj.Broken, error('tim:templateacquisition:link', 'Mock device not reachable (read).'); end
            nCh = numel(obj.Channels);
            st = struct('fault', ismember(1:nCh, obj.FaultChannels), 'overload', false(1, nCh));
            obj.advance();
            x = obj.Pending;
            obj.Pending = zeros(0, nCh);
        end

        function advance(obj)
            %ADVANCE Produce the next block now (delivered by the next read): the
            %   virtual time runs on, as on a device that keeps recording.
            nCh = numel(obj.Channels);
            m = 0;
            if obj.Running, m = max(0, min(obj.BlockSamples, obj.StallAfter - obj.Delivered)); end
            if m == 0, return; end
            if isempty(obj.Rig)
                x = 1e-4 * randn(m, nCh);
            else
                y = obj.Rig.generate(m);                      % microphone volts of the virtual tube
                x = y(:, obj.Channels);
            end
            obj.Pending = [obj.Pending; x];
            obj.Delivered = obj.Delivered + m;
        end

        function stop(obj)
            obj.operation('stop');
            obj.Running = false;
            obj.releaseRig();
        end

        function close(obj)
            if ~obj.Closed, obj.Log{end+1} = 'close'; end
            obj.Closed = true;
            obj.Running = false;
            obj.releaseRig();
        end

        function setTimeout(~, ~)
            % the mock answers at once
        end

        function fault(obj, kind, value)
            %FAULT 'broken' | 'stallAfter', n | 'channel', c (test hooks).
            switch kind
                case 'broken', obj.Broken = true;
                case 'stallAfter', obj.Next.stallAfter = value;
                case 'channel', obj.Next.channels = value;
            end
        end
    end

    methods (Access = private)
        function releaseRig(obj)
            % this device no longer produces the rig's samples
            if ~isempty(obj.Rig), obj.Rig.setProducer([]); end
        end

        function operation(obj, op)
            % one operation on the device: refused when closed or not reachable, else logged
            if obj.Closed, error('tim:templateacquisition:closed', 'Mock device closed (%s).', op); end
            if obj.Broken, error('tim:templateacquisition:link', 'Mock device not reachable (%s).', op); end
            obj.Log{end+1} = op;
            tim.instr.mockBusLog('add', 'TemplateAcquisition', op);
        end
    end
end
