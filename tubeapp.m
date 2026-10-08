function app = tubeapp(what)
%TUBEAPP Start the transfer impedance tube GUI (simplest entry point).
%
%   tubeapp              % real instruments: config/user_config.json
%                        %   (falls back to config/example_config.json)
%   tubeapp sim          % virtual tube for practice: config/sim_thin_screen.json
%   tubeapp myconf.json  % any configuration file (absolute, or in config/)
%   app = tubeapp(...)   % also return the app object
%
%   Can be called from any current folder once the project folder is on
%   the MATLAB path; it adds the project to the path itself. Windows users
%   can also double-click start_tubeapp.bat in the project folder.

root = fileparts(mfilename('fullpath'));
addpath(root);
cfgDir = fullfile(root, 'config');
if nargin < 1 || isempty(what)
    file = fullfile(cfgDir, 'user_config.json');
    if ~isfile(file)
        file = fullfile(cfgDir, 'example_config.json');
        fprintf('config/user_config.json not found - using config/example_config.json\n');
    end
elseif any(strcmpi(what, {'sim', 'simulation', 'virtual'}))
    file = fullfile(cfgDir, 'sim_thin_screen.json');
else
    file = what;
    if ~isfile(file), file = fullfile(cfgDir, what); end
    if ~isfile(file)
        error('tubeapp:config', 'Configuration file "%s" not found.', what);
    end
end
fprintf('Starting transfer impedance tube GUI with %s\n', file);
a = tim.gui.TubeApp(file);
if nargout > 0, app = a; end
end
