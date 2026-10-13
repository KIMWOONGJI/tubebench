classdef (Abstract) SignalSource < tim.instr.Instrument
    %SIGNALSOURCE Output role of the contract: drives the loudspeaker.
    %
    %   Abstract; a driver implements the methods below (contract:
    %   docs/instrument_interface.md section 3, safety duties section 11).
    %
    %   OUTPUT OFF means no waveform, the output at 0 V or disconnected. A
    %   sample-producing output (DAQ analog output, audio interface) writes
    %   0 V on creation, ends every plan with a fade to 0 V and writes 0 V
    %   after every stop, because an analog output can keep its last value.
    %
    %   configureSine(f, vpp)    continuous sine; output OFF first; level checked first
    %   setFrequency(f)          sine only (tim:gen:mode); output state unchanged
    %   configureSweep(s)        single sweep s.fStart, s.fStop [Hz], s.duration [s],
    %                            s.spacing 'LOG'|'LIN', s.amplitudeVpp; tim:gen:sweep
    %   configureNoise(vpp)      Gaussian noise, crest factor ~3.3 (rms ~ Vpp/6.6)
    %   armOutput(tf)            permission from the session; false switches off
    %   outputOn()               only armed (tim:gen:notArmed) and configured
    %                            (tim:gen:mode); level re-checked (tim:gen:amplitude)
    %   outputOff()              never throws, idempotent, any state, re-entrant
    %   tf = isOutputOn(timeout) state of the kind capabilities().source.readback:
    %                            'instrument' (query), 'device' (device session),
    %                            'none' (last commanded state, never "confirmed")
    %   triggerSweep()           start the configured sweep (sweep only)
    %   tf = waitComplete(t)     true when the sweep has ended, never earlier
    %
    %   Every level is checked BEFORE any level command: positive, its
    %   open-circuit voltage at most generator.maxVpp, within the level range
    %   of the source at the load (levelRange).
    %   Errors: tim:gen:notArmed, :amplitude, :mode, :sweep, :unsupported,
    %   :verify, :schedule (block source).
    %
    %   LOADS (generator.load). A level is programmed for a load setting:
    %   'INF' = the open-circuit voltage. A source lists its load settings in
    %   capabilities().source.loads with their level ranges (minVpp, maxVpp);
    %   a source that also accepts any resistance R as the setting (the
    %   33220A: OUTP:LOAD <ohms>) declares source.loadRange = [Rmin Rmax] [Ω].
    %   At such a load the level is the voltage across R and its range is the
    %   open-circuit range scaled by R / (R + outputImpedance_ohm)
    %   (levelRange). generator.maxVpp limits the OPEN-CIRCUIT voltage
    %   (openCircuitFactor), whatever the load setting (WO-004, 1.3.0).

    properties (SetAccess = protected)
        OutputArmed logical = false   % set by armOutput (session only, inside measure*)
    end

    methods (Abstract)
        configureSine(obj, f, vpp)
        setFrequency(obj, f)
        configureSweep(obj, s)
        configureNoise(obj, vpp)
        armOutput(obj, tf)
        outputOn(obj)
        outputOff(obj)
        tf = isOutputOn(obj, timeout)
        triggerSweep(obj)
        tf = waitComplete(obj, timeout)
    end

    methods (Static)
        function report = checkSourceConfig(cfg, c, displayName)
            %CHECKSOURCECONFIG Generic source checks for a driver's checkConfig.
            %   report = tim.instr.SignalSource.checkSourceConfig(cfg, capabilities(), displayName)
            %   generator.load against the driver's loads (or its loadRange);
            %   generator.maxVpp (open-circuit voltage) against the largest
            %   open-circuit voltage of the source; a swept sine with the
            %   configured spacing (the switching calibration and Test E are
            %   sweeps); excitation.mode; the amplitude of the swept sine and
            %   of the selected signal at least the minimum at the load
            %   (another level is checked by configure* when it is played,
            %   tim:gen:amplitude); sweep duration and frequencies within the
            %   source limits.
            report = {};
            s = c.source; g = cfg.generator;
            ld = g.load; if isstring(ld), ld = char(ld); end
            if ~ischar(ld) || ~tim.instr.SignalSource.supportsLoad(s, ld)
                error('tim:config:load', 'Generator output load (generator.load) ''%s'' is not supported by the %s (supported: %s).', ...
                    char(string(ld)), displayName, tim.instr.SignalSource.loadsText(s));
            end
            [lo, hi] = tim.instr.SignalSource.levelRange(s, ld);
            ocMax = hi * tim.instr.SignalSource.openCircuitFactor(s, ld);
            if g.maxVpp > ocMax * (1 + 1e-9)
                error('tim:config:maxVpp', ['Generator amplitude limit (generator.maxVpp, open-circuit voltage) %.3g Vpp exceeds ' ...
                    'the largest open-circuit voltage of the %s (%.3g Vpp).'], g.maxVpp, displayName, ocMax);
            end
            ex = cfg.excitation;
            if ~any(strcmp('sweep', s.waveforms))
                error('tim:config:excitation', ['The %s cannot play a swept sine; the switching calibration and the empty-tube ' ...
                    'check (Test E) need one.'], displayName);
            end
            if ~any(strcmpi(ex.sweep.spacing, s.sweepSpacing))
                error('tim:config:excitation', 'Swept sine spacing ''%s'' (excitation.sweep.spacing) is not supported by the %s (supported: %s).', ...
                    ex.sweep.spacing, displayName, strjoin(s.sweepSpacing, ', '));
            end
            wave = struct('sweep', 'sweep', 'stepped', 'sine', 'noise', 'noise');
            if ~isfield(wave, ex.mode) || ~any(strcmp(wave.(ex.mode), s.waveforms))
                error('tim:config:excitation', 'Excitation signal ''%s'' (excitation.mode) is not supported by the %s.', ex.mode, displayName);
            end
            what = {'sweep', 'swept sine'; 'stepped', 'stepped sine'; 'noise', 'random noise'};
            for i = 1:size(what, 1)
                if ~any(strcmp(wave.(what{i, 1}), s.waveforms)), continue; end
                if ~any(strcmp(what{i, 1}, {'sweep', ex.mode})), continue; end   % not played now
                v = ex.(what{i, 1}).amplitudeVpp;
                if v < lo * (1 - 1e-9)
                    error('tim:config:amplitude', ['Generator amplitude of the %s, %.3g Vpp, is below the minimum of the %s at ' ...
                        'load %s (%.3g Vpp).'], what{i, 2}, v, displayName, ld, lo);
                end
            end
            if ex.sweep.duration < s.sweepTime(1) || ex.sweep.duration > s.sweepTime(2)
                error('tim:config:sweep', 'Swept sine: duration %g s outside the %g .. %g s of the %s.', ...
                    ex.sweep.duration, s.sweepTime(1), s.sweepTime(2), displayName);
            end
            f = [ex.sweep.fStart ex.sweep.fStop ex.stepped.fStart ex.stepped.fStop];
            if any(f < s.frequencyRange(1) | f > s.frequencyRange(2))
                error('tim:config:sweep', 'Excitation frequencies %s Hz outside the range of the %s (%g .. %g Hz).', ...
                    mat2str(f), displayName, s.frequencyRange(1), s.frequencyRange(2));
            end
        end

        function tf = supportsLoad(s, load)
            %SUPPORTSLOAD The source accepts the load setting: one of
            %   s.loads (exact text), or a resistance [Ω] written as a number
            %   ('600') within s.loadRange.
            %   tf = tim.instr.SignalSource.supportsLoad(capabilities().source, '600')
            if isstring(load), load = char(load); end
            tf = ischar(load) && any(strcmp(load, s.loads));
            if ~tf && ischar(load) && isfield(s, 'loadRange') && ~isempty(s.loadRange)
                R = tim.instr.SignalSource.loadOhm(load);
                tf = isfinite(R) && R >= s.loadRange(1) && R <= s.loadRange(2);
            end
        end

        function [lo, hi] = levelRange(s, load)
            %LEVELRANGE Programmed level range [Vpp] of the source at a load setting.
            %   [lo, hi] = tim.instr.SignalSource.levelRange(capabilities().source, load)
            %   A listed load: its minVpp / maxVpp. A numeric load R within
            %   s.loadRange: the open-circuit range scaled by R / (R + Rs).
            %   NaN for a load the source does not accept.
            lo = NaN; hi = NaN;
            if isstring(load), load = char(load); end
            k = find(strcmp(load, s.loads), 1);
            if ~isempty(k)
                lo = s.minVpp(k); hi = s.maxVpp(k);
            elseif tim.instr.SignalSource.supportsLoad(s, load)
                [ocLo, ocHi] = tim.instr.SignalSource.openCircuitRange(s);
                f = 1 / tim.instr.SignalSource.openCircuitFactor(s, load);
                lo = ocLo * f; hi = ocHi * f;
            end
        end

        function f = openCircuitFactor(s, load)
            %OPENCIRCUITFACTOR Open-circuit voltage per volt of programmed level.
            %   f = tim.instr.SignalSource.openCircuitFactor(capabilities().source, load)
            %   'INF': 1; a load of R ohm: (R + Rs) / R with the source
            %   impedance Rs = s.outputImpedance_ohm (0 when not given).
            R = tim.instr.SignalSource.loadOhm(load);
            Rs = 0;
            if isfield(s, 'outputImpedance_ohm') && isfinite(s.outputImpedance_ohm), Rs = s.outputImpedance_ohm; end
            if isinf(R) || isnan(R), f = 1; else, f = (R + Rs) / R; end
        end

        function R = loadOhm(load)
            %LOADOHM Resistance of a load setting [Ω]: 'INF' -> Inf, '600' -> 600,
            %   anything else NaN. The text is taken as it is (review
            %   analysis-6: ' 50' or 'INF ' is not a load setting); only the
            %   case of INF is ignored here ('inf' -> Inf), supportsLoad
            %   compares the listed loads exactly.
            if isstring(load), load = char(load); end
            R = NaN;
            if ~ischar(load), return; end
            if strcmpi(load, 'INF'), R = Inf; return; end
            if ~isempty(regexp(load, '^\d+(\.\d+)?$', 'once')), R = str2double(load); end
            if R <= 0, R = NaN; end
        end

        function t = loadsText(s)
            %LOADSTEXT The load settings a source accepts, for messages.
            t = strjoin(s.loads, ', ');
            if isfield(s, 'loadRange') && ~isempty(s.loadRange)
                t = sprintf('%s or a resistance of %g to %g Ω written as a number', t, s.loadRange(1), s.loadRange(2));
            end
        end
    end

    methods (Static, Access = private)
        function [lo, hi] = openCircuitRange(s)
            % level range at the open circuit: the INF entry, else a listed
            % numeric load converted back to the open circuit
            k = find(strcmp('INF', s.loads), 1);
            if ~isempty(k), lo = s.minVpp(k); hi = s.maxVpp(k); return; end
            lo = NaN; hi = NaN;
            for i = 1:numel(s.loads)
                f = tim.instr.SignalSource.openCircuitFactor(s, s.loads{i});
                if isfinite(tim.instr.SignalSource.loadOhm(s.loads{i}))
                    lo = s.minVpp(i) * f; hi = s.maxVpp(i) * f; return
                end
            end
        end
    end
end
