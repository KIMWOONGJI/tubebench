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
    %   Every level is checked BEFORE any level command: positive, at most
    %   generator.maxVpp, at least capabilities().source.minVpp for the load.
    %   Errors: tim:gen:notArmed, :amplitude, :mode, :sweep, :unsupported,
    %   :verify, :schedule (block source).

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
            %   generator.load and generator.maxVpp against the driver's loads
            %   and per-load maximum; a swept sine with the configured spacing
            %   (the switching calibration and Test E are sweeps);
            %   excitation.mode; amplitudes at least the per-load minimum;
            %   sweep duration and frequencies within the source limits.
            report = {};
            s = c.source; g = cfg.generator;
            ld = g.load; if isstring(ld), ld = char(ld); end
            k = find(strcmp(ld, s.loads), 1);
            if ~ischar(ld) || isempty(k)
                error('tim:config:load', 'Generator output load (generator.load) ''%s'' is not supported by the %s (supported: %s).', ...
                    char(string(ld)), displayName, strjoin(s.loads, ', '));
            end
            if g.maxVpp > s.maxVpp(k)
                error('tim:config:maxVpp', ['Generator amplitude limit (generator.maxVpp) %.3g Vpp exceeds the maximum of the %s ' ...
                    'at load %s (%.3g Vpp).'], g.maxVpp, displayName, ld, s.maxVpp(k));
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
                v = ex.(what{i, 1}).amplitudeVpp;
                if v < s.minVpp(k)
                    error('tim:config:amplitude', ['Generator amplitude of the %s, %.3g Vpp, is below the minimum of the %s at ' ...
                        'load %s (%.3g Vpp).'], what{i, 2}, v, displayName, ld, s.minVpp(k));
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
    end
end
