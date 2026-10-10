function cfg = loadConfig(file)
%LOADCONFIG Load a JSON configuration and merge it onto the defaults.
%
%   cfg = tim.app.loadConfig('config/user_config.json')
%   cfg = tim.app.loadConfig()          % defaults only
%
%   JSON has no NaN: a null (or missing field) keeps the default value,
%   so unknown geometry stays NaN ("not provided"). Numeric arrays are
%   returned with the default's orientation. Unknown fields are kept and
%   reported as a warning (typo protection).
%
%   Instruments: a file of formatVersion 1 (generator.host / port / timeout,
%   a top-level lanxi section, no driver names) is brought to the layout of
%   formatVersion 2 first (tim.app.migrateConfig), so it loads with the same
%   settings; the file itself is not changed. A settings sub-struct named
%   after a registered driver (generator.<driver>, daq.<driver>) is merged
%   onto that driver's defaults and kept also when another driver is
%   selected; the sub-struct of an unknown driver is kept as it is (warning
%   tim:config:driver from tim.app.validateConfig). A sub-struct in a section
%   its driver never reads (generator.<d> of a driver that takes both roles,
%   which reads daq.<d>) gives the warning tim:config:misplacedSettings.
%   Values outside the limits of the selected drivers give warnings
%   (tim.app.validateConfig): the file loads, Connect refuses it.
%   acquisition.sampleRate, range, filter and ccld that the file leaves out
%   (or sets to null / '') take the default of the selected DAQ driver.

cfg = tim.app.defaultConfig();
if nargin < 1 || isempty(file), return; end
u = jsondecode(tim.app.readTextUtf8(file));
if isfield(u, 'configFile'), u = rmfield(u, 'configFile'); end   % run-time field (older files)
u = tim.app.migrateConfig(u, 'file');
u = acquisitionDefaults(u);
[cfg, unknown] = merge(cfg, u, 'cfg');
if ~isempty(unknown)
    warning('tim:config:unknownField', 'Unknown configuration field(s): %s', strjoin(unknown, ', '));
end
cfg = tim.app.migrateConfig(cfg);
cfg.configFile = file;
for m = tim.instr.Instrument.misplacedSettings(cfg)       % e.g. generator.<d> of a combined driver
    warning('tim:config:misplacedSettings', '%s', m{1});
end
tim.app.validateConfig(cfg);
end

function u = acquisitionDefaults(u)
% acquisition values the file leaves out: the default of its DAQ driver (the
% generic default of tim.app.defaultConfig belongs to the default driver)
name = 'lanxi';
if isfield(u, 'daq') && isstruct(u.daq) && isfield(u.daq, 'driver'), name = char(string(u.daq.driver)); end
if ~any(strcmp(name, {tim.instr.drivers().name})), return; end
d = tim.instr.driverInfo(name);
if ~isfield(d.defaults, 'acquisition'), return; end
if ~isfield(u, 'acquisition') || ~isstruct(u.acquisition), u.acquisition = struct(); end
for f = {'sampleRate', 'range', 'filter', 'ccld'}
    if ~isfield(u.acquisition, f{1}) || isempty(u.acquisition.(f{1}))
        u.acquisition.(f{1}) = d.defaults.acquisition.(f{1});
    end
end
end

function [d, unknown] = merge(d, u, path)
unknown = {};
fu = fieldnames(u);
for i = 1:numel(fu)
    k = fu{i};
    p = [path '.' k];
    if ~isfield(d, k)
        if any(strcmp(path, {'cfg.generator', 'cfg.daq'}))
            [d, un, done] = driverSettings(d, u, k, p);
            unknown = [unknown, un]; %#ok<AGROW>
            if done, continue; end
        end
        unknown{end+1} = p; %#ok<AGROW>
        d.(k) = u.(k);
        continue
    end
    dv = d.(k); uv = u.(k);
    if any(strcmp(p, {'cfg.simulation.Sample', 'cfg.simulation.Termination'}))
        d.(k) = uv;      % model definitions are replaced as a whole (fields depend on type)
    elseif isstruct(dv) && isscalar(dv) && isstruct(uv) && isscalar(uv)
        [d.(k), un] = merge(dv, uv, p);
        unknown = [unknown, un]; %#ok<AGROW>
    elseif isstruct(dv) && isstruct(uv)
        % struct array (e.g. mics): take user entries, fill missing fields
        out = repmat(dv(1), numel(uv), 1);
        for j = 1:numel(uv)
            [out(j), un] = merge(dv(min(j, end)), uv(j), sprintf('%s(%d)', p, j));
            unknown = [unknown, un]; %#ok<AGROW>
        end
        d.(k) = out.';
    elseif isempty(uv) && isnumeric(uv)
        % null -> keep default
    elseif isnumeric(dv) || islogical(dv)
        if isnumeric(uv) || islogical(uv)
            if isrow(dv) && iscolumn(uv), uv = uv.'; end
            if islogical(dv), uv = logical(uv); end
            d.(k) = uv;
        else
            error('tim:config:type', 'Configuration field %s must be numeric.', p);
        end
    elseif iscell(dv) && (ischar(uv) || isstring(uv) || iscell(uv))
        uv = cellstr(uv);
        if isrow(dv), uv = reshape(uv, 1, []); end
        d.(k) = uv;
    else
        d.(k) = uv;
    end
end
end

function [d, unknown, done] = driverSettings(d, u, k, p)
% generator.<k> / daq.<k> that the defaults do not have: the settings of
% another registered driver (merged onto its defaults: typos are reported),
% or of the unknown driver this section names (kept as it is)
unknown = {}; done = false;
uv = u.(k);
if ~isstruct(uv) || ~isscalar(uv), return; end
if any(strcmp(k, {tim.instr.drivers().name}))
    def = tim.instr.driverInfo(k).defaults.settings;
    [d.(k), unknown] = merge(def, uv, p);
    done = true;
elseif isfield(u, 'driver') && strcmp(char(string(u.driver)), k)
    d.(k) = uv;
    done = true;
end
end
