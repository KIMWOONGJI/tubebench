classdef FakeNoReadbackSource < tim.instr.Keysight33220A
    %FAKENOREADBACKSOURCE Test driver: the 33220A driver declaring that it cannot report its output state.
    %
    %   Not registered; tests/TestInstrumentContract adds it for one test
    %   (tim.instr.drivers('add', ...)). Its capabilities declare
    %   source.readback 'none': the registry must refuse it in hardware mode
    %   with tim:instr:readback before any I/O, unless the owner sets
    %   generator.allowUnconfirmedOff = true (docs/instrument_interface.md
    %   section 9.1, check 6). fromConfig never connects to hardware, also if
    %   a check were missed (tim:test:hardware); in simulation it runs on the
    %   33220A protocol mock.

    methods (Static)
        function d = describe()
            d = tim.instr.Keysight33220A.describe();
            d.name = 'fakenoreadback';
            d.displayName = 'Test generator without output read-back';
        end

        function c = capabilities()
            c = tim.instr.Keysight33220A.capabilities();
            c.source.readback = 'none';
        end

        function obj = fromConfig(cfg, ctx)
            if ~strcmp(ctx.mode, 'simulation')
                error('tim:test:hardware', 'Test driver: never connects to an instrument.');
            end
            obj = tim.instr.Keysight33220A.fromConfig(cfg, ctx);
        end
    end
end
