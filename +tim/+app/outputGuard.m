classdef outputGuard < handle
    %OUTPUTGUARD Switches the generator output off when a measurement ends abnormally.
    %
    %   guard = tim.app.outputGuard(gen);   % right after gen.armOutput(true)
    %   ... acquisition ...
    %   guard.dismiss();                    % normal end, or the error path
    %                                       % switched the output off itself
    %
    %   MATLAB does not catch an interrupt (Ctrl+C in the command window of a
    %   script, or in the console of start_tubebench.bat) with try/catch: only
    %   onCleanup objects and the destructors of handle objects run. When the
    %   guard is destroyed before it was dismissed (interrupt, or any other
    %   exit that skipped the dismiss), it calls gen.outputOff() and
    %   gen.armOutput(false). A dismissed guard does nothing, so neither the
    %   normal path nor the error paths send an extra output-off command
    %   (docs/instrument_interface.md section 11.2). Never throws.

    properties (SetAccess = private)
        Source = []                % tim.instr.SignalSource
        Dismissed logical = false
    end

    methods
        function obj = outputGuard(source)
            obj.Source = source;
        end

        function dismiss(obj)
            %DISMISS The caller has handled the output: nothing to do on destruction.
            obj.Dismissed = true;
        end

        function delete(obj)
            if obj.Dismissed || isempty(obj.Source), return; end
            src = obj.Source;
            try
                if isvalid(src)
                    src.outputOff();
                    src.armOutput(false);
                end
            catch err
                warning('tim:session:outputGuard', 'Output guard: %s', err.message);
            end
        end
    end
end
