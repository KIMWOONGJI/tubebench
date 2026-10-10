classdef (Abstract) Instrument < handle
    %INSTRUMENT Members common to both instrument roles (contract base class).
    %
    %   Abstract base of tim.instr.SignalSource (output role) and
    %   tim.instr.Acquisition (input role). A driver derives from one role
    %   class, or from both when one device takes both roles (output and
    %   inputs on one sample clock). Every member that both roles share is
    %   defined only here, so MATLAB accepts a class that inherits from both.
    %   The contract (units, duties, timing, error identifiers) is
    %   docs/instrument_interface.md; this help is its summary.
    %
    %   CLASS-LEVEL (static, no I/O - used before anything is connected)
    %     d = describe()             name (registry name = generator.driver /
    %                                daq.driver), displayName, labels.<role>
    %                                (lamp label), defaults.settings (driver
    %                                sub-struct), defaults.acquisition,
    %                                texts.settle / noun / closed (window
    %                                texts), simulation ('protocol'|'only')
    %     c = capabilities()         roles, sharedClock, rolesTogether, products
    %                                (struct array name/feature), source.*,
    %                                acquisition.* (section 5)
    %     s = connectionSteps()      struct array key, label, role
    %                                ('source'|'acquisition'|'both'), phase
    %                                ('connect'|'prepare')
    %     report = checkConfig(cfg)  the driver's part of the configuration;
    %                                errors tim:config:*, returns warnings
    %     obj = fromConfig(cfg, ctx) factory, used only by tim.instr.create:
    %                                connect, identify, safe state; reports its
    %                                'connect' steps through ctx.progress
    %     h = testHooks(obj)         simulation only: handles into the protocol
    %                                mock for tests/TestInstrumentContract
    %     checkInstalled()           optional: support packages / runtimes
    %                                (hardware mode, tim:instr:missingProduct)
    %   ctx: mode, rig, progress, roles, settings (driver settings merged onto
    %   describe().defaults.settings by the registry).
    %
    %   INSTANCE
    %     id = identity()   vendor, model, serial, firmware, raw (as reported
    %                       when created; no I/O)
    %     md = metadata()   JSON-encodable: driver, displayName, roles,
    %                       identity, sharedClock, settings + driver state
    %     setTimeout(t)     shorten the I/O time-out (closing the window)
    %     close()           safe state and release; never throws; idempotent:
    %                       a second close() sends nothing; afterwards other
    %                       methods raise '...:closed' and send nothing
    %     ProgressFcn       @(key, state, detail), connection checklist
    %   outputOff, close and setTimeout may be called at any time, also
    %   re-entrantly from a callback inside one of the object's own methods.
    %   There is deliberately no delete() here: MATLAB would run it after the
    %   subclass destructor and close twice (each driver has its own).

    properties
        ProgressFcn = []        % @(key, state, detail), see connectionSteps
    end
    properties (SetAccess = protected)
        Roles cell = {}         % roles this object takes (set by fromConfig; {} = its capabilities)
    end

    methods (Abstract, Static)
        d = describe()
        c = capabilities()
        s = connectionSteps()
        report = checkConfig(cfg)
        obj = fromConfig(cfg, ctx)
        h = testHooks(obj)
    end

    methods (Abstract)
        id = identity(obj)
        md = metadata(obj)
        close(obj)
    end

    methods
        function setTimeout(~, ~)
            %SETTIMEOUT Shorten the I/O time-out [s]. Default: nothing to shorten.
        end

        function r = rolesInUse(obj)
            %ROLESINUSE Roles this object takes (its capabilities when not set by fromConfig).
            r = obj.Roles;
            if isempty(r)
                c = feval([class(obj) '.capabilities']);
                r = c.roles;
            end
        end
    end

    methods (Static)
        function st = settingsFrom(cfg, section, name, defaults)
            %SETTINGSFROM Driver settings: cfg.(section).(name) merged onto defaults.
            %   st = tim.instr.Instrument.settingsFrom(cfg, 'generator', 'keysight33220a', d.defaults.settings)
            %   Fields missing in the configuration (or JSON null = empty
            %   numeric) keep the default; other fields are kept as given.
            st = defaults;
            if ~isfield(cfg, section) || ~isstruct(cfg.(section)) || ~isfield(cfg.(section), name), return; end
            u = cfg.(section).(name);
            if ~isstruct(u) || ~isscalar(u), return; end
            f = fieldnames(u);
            for i = 1:numel(f)
                v = u.(f{i});
                if isnumeric(v) && isempty(v) && isfield(st, f{i}), continue; end
                st.(f{i}) = v;
            end
        end

        function reportStep(ctx, key, state, detail)
            %REPORTSTEP Report a 'connect' step through ctx.progress (if any).
            %   Errors of the callback (operator Stop: tim:session:stopped)
            %   propagate: fromConfig then releases what it opened.
            if isstruct(ctx) && isfield(ctx, 'progress') && ~isempty(ctx.progress)
                ctx.progress(key, state, detail);
            end
        end

        function id = emptyIdentity()
            %EMPTYIDENTITY Identity with every field unknown ('').
            id = struct('vendor', '', 'model', '', 'serial', '', 'firmware', '', 'raw', '');
        end
    end
end
