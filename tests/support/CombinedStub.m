classdef CombinedStub < tim.instr.SignalSource & tim.instr.Acquisition
    %COMBINEDSTUB Minimal driver that takes both roles (tests only, no I/O).
    %
    %   Proves that the contract classes accept ONE object in both roles
    %   (tests/TestInstrumentContract/combinedRoleClassMechanics): the members
    %   both roles share are defined only in tim.instr.Instrument, so MATLAB
    %   accepts the class that inherits from tim.instr.SignalSource and
    %   tim.instr.Acquisition. Not registered and not a model for a real
    %   driver: the simulated combined driver 'simcombined' (WO-001 stage B)
    %   is the real case, with a planning pass and 0 V outputs.

    properties (SetAccess = private)
        OutputState logical = false
        Closed logical = false
    end

    methods
        function configureSine(obj, ~, ~), obj.outputOff(); end
        function setFrequency(~, ~), end
        function configureSweep(obj, ~), obj.outputOff(); end
        function configureNoise(obj, ~), obj.outputOff(); end
        function armOutput(obj, tf)
            obj.OutputArmed = logical(tf);
            if ~tf, obj.outputOff(); end
        end
        function outputOn(obj)
            if ~obj.OutputArmed, error('tim:gen:notArmed', 'Output enable refused: not armed.'); end
            obj.OutputState = true;
        end
        function outputOff(obj), obj.OutputState = false; end
        function tf = isOutputOn(obj, ~), tf = obj.OutputState; end
        function triggerSweep(~), end
        function tf = waitComplete(~, ~), tf = true; end

        function prepare(obj, c)
            obj.SampleRate = c.sampleRate;
            obj.Teds = cell(1, 4);
        end
        function [data, info] = acquire(obj, n, onBlock, ~)
            if nargin >= 3 && ~isempty(onBlock), onBlock(n); end
            [data, info] = obj.collect(n);
        end
        function [data, info] = collect(obj, n)
            data = zeros(n, 4);
            info = struct('fs', obj.SampleRate, 'dataUnit', 'V');
        end
        function [x, nTotal] = recent(~, ~), x = []; nTotal = 0; end
        function tf = isAcquiring(~), tf = false; end
        function b = rawBytes(~), b = zeros(1, 0, 'uint8'); end

        function id = identity(~)
            id = tim.instr.Instrument.emptyIdentity();
            id.model = 'stub';
        end
        function md = metadata(obj)
            md = struct('driver', 'combinedstub', 'roles', {obj.rolesInUse()}, 'identity', obj.identity());
        end
        function close(obj)
            obj.outputOff();
            obj.OutputArmed = false;
            obj.Closed = true;
        end
    end

    methods (Static)
        function d = describe()
            d = struct('name', 'combinedstub', 'displayName', 'Combined stub (tests)', ...
                'labels', struct('source', 'Output', 'acquisition', 'Inputs'), ...
                'defaults', struct('settings', struct(), 'acquisition', struct('sampleRate', 16384, ...
                    'range', '10 Vpeak', 'filter', 'DC', 'ccld', false(1, 4))), ...
                'texts', struct('settle', '', 'noun', 'combined stub', 'closed', 'stopped'), 'simulation', 'only');
        end
        function c = capabilities()
            c = struct('roles', {{'source', 'acquisition'}}, 'sharedClock', true, 'rolesTogether', true, ...
                'products', struct('name', {}, 'feature', {}));
        end
        function s = connectionSteps()
            s = struct('key', 'device', 'label', 'Stub device', 'role', 'both', 'phase', 'connect');
        end
        function report = checkConfig(~), report = {}; end
        function obj = fromConfig(~, ctx)
            obj = CombinedStub();
            obj.Roles = ctx.roles;
        end
        function h = testHooks(obj)
            h = struct('outputOn', @() obj.OutputState);
        end
    end
end
