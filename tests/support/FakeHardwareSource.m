classdef FakeHardwareSource < tim.instr.Keysight33220A
    %FAKEHARDWARESOURCE Test driver: the 33220A driver that ALWAYS runs on its SCPI mock, also in hardware mode.
    %
    %   Not registered; tests/TestSessionHardwareMode adds it together with
    %   FakeHardwareDaq (tim.instr.drivers('add', ...)) so that a
    %   MeasurementSession in mode 'hardware' runs its hardware-only branches
    %   (the excitation confirmation in the command window, the amplifier-gain
    %   gate tim:session:gainRequired, the settle step of the inputs) with NO
    %   network or device I/O. fromConfig never builds a real transport,
    %   whatever ctx.mode says: it creates a virtual rig (tim.sim.SimulatedRig)
    %   and builds the unchanged 33220A driver on the SCPI protocol mock on
    %   that rig. FakeHardwareDaq builds the acquisition on the same rig
    %   (FakeHardwareSource.rig), so the recordings contain the excitation.
    %   This file names no real transport (checked by the tests).

    methods (Static)
        function d = describe()
            d = tim.instr.Keysight33220A.describe();
            d.name = 'fakehwsource';
            d.displayName = 'Test generator on its mock (hardware mode, no I/O)';
        end

        function obj = fromConfig(cfg, ctx)
            r = tim.sim.SimulatedRig(cfg);
            FakeHardwareSource.rig(r);              % for FakeHardwareDaq (created next by the registry)
            ctx.mode = 'simulation';                % the base driver: the protocol mock on the rig
            ctx.rig = r;
            obj = tim.instr.Keysight33220A.fromConfig(cfg, ctx);
        end

        function r = rig(newRig)
            %RIG The virtual rig of the last FakeHardwareSource.fromConfig
            %   (FakeHardwareSource.rig([]) forgets it).
            persistent current
            if nargin >= 1, current = newRig; end
            r = current;
        end
    end
end
