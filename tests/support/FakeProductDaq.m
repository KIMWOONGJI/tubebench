classdef FakeProductDaq < tim.instr.LanXi
    %FAKEPRODUCTDAQ Test driver: the LAN-XI driver declaring a MATLAB product that is missing.
    %
    %   Not registered; tests/TestInstrumentContract adds it for one test
    %   (tim.instr.drivers('add', ...)). Its capabilities name the product
    %   'Fake Acquisition Toolbox', which is never installed: the registry must
    %   refuse the driver in hardware mode with tim:instr:missingProduct
    %   before any I/O, and build it in simulation mode, where it runs on the
    %   LAN-XI protocol mock without the product. fromConfig never connects to
    %   hardware, also if a check were missed.

    methods (Static)
        function d = describe()
            d = tim.instr.LanXi.describe();
            d.name = 'fakeproductdaq';
            d.displayName = 'Test DAQ that needs a toolbox';
        end

        function c = capabilities()
            c = tim.instr.LanXi.capabilities();
            c.products = struct('name', 'Fake Acquisition Toolbox', 'feature', 'Fake_Acquisition_Toolbox');
        end

        function obj = fromConfig(cfg, ctx)
            if ~strcmp(ctx.mode, 'simulation')
                error('tim:test:hardware', 'Test driver: never connects to an instrument.');
            end
            obj = tim.instr.LanXi.fromConfig(cfg, ctx);
        end
    end
end
