classdef FakeHardwareDaq < tim.instr.LanXi
    %FAKEHARDWAREDAQ Test driver: the LAN-XI driver that ALWAYS runs on its REST and stream mocks, also in hardware mode.
    %
    %   Not registered; tests/TestSessionHardwareMode adds it together with
    %   FakeHardwareSource (see there). fromConfig never builds a real
    %   transport, whatever ctx.mode says: it builds the unchanged LAN-XI
    %   driver on its protocol mocks (REST and data stream) on the virtual rig
    %   that FakeHardwareSource.fromConfig created for the same connection.
    %   Its texts are the LAN-XI driver's, so a hardware-mode session waits
    %   for the inputs to settle ("CCLD + <filter> high-pass"). This file names
    %   no real transport (checked by the tests).

    methods (Static)
        function d = describe()
            d = tim.instr.LanXi.describe();
            d.name = 'fakehwdaq';
            d.displayName = 'Test acquisition on its mocks (hardware mode, no I/O)';
        end

        function obj = fromConfig(cfg, ctx)
            r = FakeHardwareSource.rig();
            if isempty(r)
                error('tim:test:rig', 'Test driver: use it with the generator driver "fakehwsource" (its virtual rig).');
            end
            ctx.mode = 'simulation';                % the base driver: the protocol mocks on the rig
            ctx.rig = r;
            obj = tim.instr.LanXi.fromConfig(cfg, ctx);
        end
    end
end
