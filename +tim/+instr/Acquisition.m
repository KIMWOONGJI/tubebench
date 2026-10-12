classdef (Abstract) Acquisition < tim.instr.Instrument
    %ACQUISITION Input role of the contract: records the four microphones.
    %
    %   Abstract; a driver implements the methods below (contract:
    %   docs/instrument_interface.md sections 4 and 8, duties section 11).
    %
    %   prepare(c)                    c.sampleRate, channels, names, range, filter,
    %                                 ccld, detectTeds; runs at EXACTLY c.sampleRate
    %                                 or fails with tim:<driver>:rate
    %   [data, info] = acquire(n, onBlock, timeout)
    %                                 n x C samples in info.dataUnit ('V' volts at
    %                                 the input, or 'FS' for an unknown input scale);
    %                                 onBlock(nNow) with ONE input, at least every
    %                                 0.25 s while recording; stops on every exit
    %                                 path incl. an interrupt (onCleanup); calls
    %                                 AbortFcn first on every abnormal exit
    %   [data, info] = collect(n)     data received so far (partial after an error)
    %   [x, nTotal] = recent(n)       last <= n samples, no I/O (live view)
    %   tf = isAcquiring()            a recording is running
    %   tf = isPlanning()             planning pass of a combined block device
    %                                 (section 8.3); false for every other driver
    %   b = rawBytes()                undecoded bytes of the last acquisition, or empty
    %   info: fs, dataUnit, integrity (ok, fatal, warnings, peakFractionOfRange,
    %   channelFaults = device flags in the driver's words) + driver fields.
    %
    %   Timing (section 8): when source and acquisition are different
    %   objects, onBlock is called AS DATA ARRIVE; a driver that cannot do
    %   that declares capabilities().acquisition.needsOwnSource = true and can
    %   only take both roles. close() during acquire (also from inside
    %   onBlock) stops at once; acquire then ends with tim:instr:closed and
    %   every later acquire raises it.

    properties (SetAccess = protected)
        SampleRate double = NaN       % S/s, set by prepare
        Teds cell = {}                % 1 x C: [] or struct typeNumber, serialNumber,
                                      % sensitivity [V/unit], unit, requiresCcld; {} = none read
    end
    properties
        AbortFcn = []                 % @() called first on every abnormal end of acquire
                                      % (session: generator output off), before any stop I/O
    end

    methods (Abstract)
        prepare(obj, c)
        [data, info] = acquire(obj, n, onBlock, timeout)
        [data, info] = collect(obj, n)
        [x, nTotal] = recent(obj, n)
        tf = isAcquiring(obj)
        b = rawBytes(obj)
    end

    methods
        function tf = isPlanning(~)
            %ISPLANNING True only during the planning pass of a combined block device.
            tf = false;
        end

        function set.AbortFcn(obj, f)
            if ~(isempty(f) || isa(f, 'function_handle'))
                error('tim:instr:abortFcn', 'AbortFcn must be a function handle @() or empty.');
            end
            obj.AbortFcn = f;
        end
    end

    methods (Access = protected)
        function callAbortFcn(obj)
            %CALLABORTFCN Run AbortFcn once; never throws (a failure is a warning).
            f = obj.AbortFcn;
            if isempty(f), return; end
            try
                f();
            catch err
                warning('tim:instr:abortFcn', 'AbortFcn failed: %s', err.message);
            end
        end
    end

    methods (Static)
        function report = checkAcquisitionConfig(cfg, c, d)
            %CHECKACQUISITIONCONFIG Generic acquisition checks for a driver's checkConfig.
            %   report = tim.instr.Acquisition.checkAcquisitionConfig(cfg, capabilities(), describe())
            %   Sample rate in the driver's list or range; analysis band and
            %   stop frequencies below bandFraction x sample rate; range and
            %   filter among the driver's values; CCLD only on a device with a
            %   switchable supply. Empty values mean the driver default
            %   (describe().defaults.acquisition).
            report = {};
            q = c.acquisition; a = cfg.acquisition; def = d.defaults.acquisition;
            fs = valueOr(a.sampleRate, def.sampleRate);
            if isempty(q.sampleRates)
                ok = fs >= q.sampleRateRange(1) && fs <= q.sampleRateRange(2);
                supported = sprintf('%g .. %g S/s', q.sampleRateRange);
            else
                ok = ismember(fs, q.sampleRates);
                supported = strjoin(arrayfun(@(x) sprintf('%g', x), q.sampleRates, 'UniformOutput', false), ', ');
            end
            if ~ok
                error('tim:config:fs', 'Sample rate %g S/s (acquisition.sampleRate) is not supported by the %s (supported: %s).', ...
                    fs, d.displayName, supported);
            end
            fNy = q.bandFraction * fs;                % usable band of the anti-alias filter
            if cfg.analysis.fMax > fNy
                error('tim:config:fmax', ['Upper limit of the analysis band (analysis.fMax) %g Hz is above %.2g × sample rate ' ...
                    '= %.0f Hz (sample rate %g S/s, %s).'], cfg.analysis.fMax, q.bandFraction, fNy, fs, d.displayName);
            end
            if cfg.excitation.sweep.fStop > fNy
                error('tim:config:sweep', ['Swept sine: stop frequency %g Hz is above %.2g × sample rate = %.0f Hz ' ...
                    '(sample rate %g S/s, %s).'], cfg.excitation.sweep.fStop, q.bandFraction, fNy, fs, d.displayName);
            end
            if cfg.excitation.stepped.fStop > fNy
                error('tim:config:stepped', ['Stepped sine: stop frequency %g Hz is above %.2g × sample rate = %.0f Hz ' ...
                    '(sample rate %g S/s, %s).'], cfg.excitation.stepped.fStop, q.bandFraction, fNy, fs, d.displayName);
            end
            inRange = valueOr(a.range, def.range);
            if ~any(strcmp(inRange, q.ranges))
                error('tim:config:range', 'Input range ''%s'' (acquisition.range) is not supported by the %s (supported: %s).', ...
                    char(string(inRange)), d.displayName, strjoin(q.ranges, ', '));
            end
            flt = valueOr(a.filter, def.filter);
            if ~any(strcmp(flt, q.filters))
                error('tim:config:filter', 'High-pass filter ''%s'' (acquisition.filter) is not supported by the %s (supported: %s).', ...
                    char(string(flt)), d.displayName, strjoin(q.filters, ', '));
            end
            if any(valueOr(a.ccld, def.ccld)) && ~q.ccld
                error('tim:config:ccld', ['The %s has no switchable CCLD/IEPE supply. External IEPE supply: set ' ...
                    'acquisition.ccld false.'], d.displayName);
            end
            if strcmp(q.dataUnit, 'FS')
                report{end+1} = sprintf(['The %s delivers full-scale units: levels are relative (dB re FS) unless its ' ...
                    'volts per full scale are configured.'], d.displayName);
            end
        end
    end
end

function v = valueOr(v, default)
% empty (JSON null or '') -> the driver default
if isempty(v), v = default; end
end
