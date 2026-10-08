function closeApp(fig, app)
%CLOSEAPP Close request of the TubeApp window - always closes the window.
%   Disconnects the instruments through the app if it still exists; if the
%   app object is gone (e.g. after "clear classes") or its clean-up fails,
%   the window is closed anyway so it can never get stuck.
try
    if ~isempty(app) && isvalid(app)
        app.disconnect();
    end
catch err
    warning('tim:gui:close', 'Clean-up on close failed: %s', err.message);
end
if isvalid(fig)
    delete(fig);
end
end
