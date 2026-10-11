classdef FakeRateCombined < tim.sim.SimulatedCombined
    %FAKERATECOMBINED Test driver: the simulated combined device reporting its data at another rate.
    %
    %   Not registered; tests/TestEndToEnd adds it for one test
    %   (tim.instr.drivers('add', ...)). acquire returns the device's data with
    %   info.fs at half the configured sample rate and leaves the integrity
    %   result as the device reported it (ok): the session must make the
    %   mismatch a fatal integrity problem itself (MeasurementSession.checkRate),
    %   whatever the driver checks. Simulation only, like the device it extends.

    methods
        function obj = FakeRateCombined(varargin)
            obj@tim.sim.SimulatedCombined(varargin{:});
        end

        function [data, info] = acquire(obj, varargin)
            [data, info] = acquire@tim.sim.SimulatedCombined(obj, varargin{:});
            info.fs = info.fs / 2;               % data delivered at another rate than configured
        end
    end

    methods (Static)
        function d = describe()
            d = tim.sim.SimulatedCombined.describe();
            d.name = 'fakeratecombined';
            d.displayName = 'Test device delivering another sample rate';
        end

        function obj = fromConfig(cfg, ctx)
            if ~strcmp(ctx.mode, 'simulation')
                error('tim:test:hardware', 'Test driver: simulation only.');
            end
            rig = ctx.rig;
            if isempty(rig), rig = tim.sim.SimulatedRig(cfg); end
            obj = FakeRateCombined(rig, ctx.settings, cfg.generator.maxVpp, cfg.generator.load, ...
                cfg.acquisition.sampleRate);
            obj.Roles = ctx.roles;
        end
    end
end
