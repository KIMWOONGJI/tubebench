function closeApp(fig, app)
%CLOSEAPP Close request of the Tubebench window - always closes the window.
%   A "Closing" dialog appears at once and shows the steps (generator
%   output off, LAN-XI module back to Idle with short time-outs, window
%   deleted). During a running measurement / calibration a stop is requested first and
%   the window closes as soon as the action has stopped; a second close
%   request closes immediately. If the app object is gone (e.g. after
%   "clear classes") or its clean-up fails, the window is deleted anyway so
%   it can never get stuck.
try
    if ~isempty(app) && isvalid(app)
        app.closeRequest();
        return
    end
catch err
    warning('tim:gui:close', 'Clean-up on closing the window failed: %s', err.message);
end
if isvalid(fig)
    delete(fig);
end
end
