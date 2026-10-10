function cfg = migrateConfig(cfg, origin)
%MIGRATECONFIG Bring a configuration to the instrument layout of formatVersion 2.
%
%   cfg = tim.app.migrateConfig(cfg)          % a configuration built in code
%   u   = tim.app.migrateConfig(u, 'file')    % contents of a JSON file, before
%                                             % tim.app.loadConfig merges it
%
%   formatVersion 2 selects the instruments by driver name and keeps each
%   driver's settings in a sub-struct named after it:
%     generator.driver, generator.maxVpp, generator.load, generator.<driver>
%     daq.driver, daq.<driver>       (a combined driver: daq.<driver>)
%   Older files and scripts (formatVersion 1) used generator.host / port /
%   timeout and a top-level lanxi section. Rules (docs/instrument_interface.md
%   section 9.3):
%     1. a top-level 'lanxi' section moves to daq.lanxi (daq.driver 'lanxi'
%        when there is no daq section); 'lanxi' is removed
%     2. generator.host / port / timeout move to generator.keysight33220a;
%        when another generator driver is selected they are not used by it
%        and the warning tim:config:legacyField says where its setting belongs
%     3. a missing driver name: the role's default ('keysight33220a', 'lanxi')
%     4. both layouts: the new key wins and tim:config:legacyField names the
%        ignored old key. In code (origin not 'file') a new key that still
%        holds the driver default does not count as set: an old script that
%        sets cfg.generator.host on tim.app.defaultConfig keeps working.
%     5. formatVersion 2
%   A full configuration (origin not 'file') is also completed:
%     6. empty acquisition.sampleRate / range / filter / ccld: the default of
%        the acquisition driver (describe().defaults.acquisition)
%     7. the settings sub-struct of each selected registered driver: the
%        configured values merged onto the driver's defaults
%   An unknown driver name is kept as it is (tim.app.validateConfig warns).
%   Idempotent: a formatVersion 2 configuration comes back unchanged except
%   for steps 6 and 7.

if nargin < 2, origin = 'code'; end
inFile = strcmp(origin, 'file');
if ~isstruct(cfg) || ~isscalar(cfg), return; end
legacyGen = {'host', 'port', 'timeout'};

% ---- 1. lanxi section -> daq.lanxi
if isfield(cfg, 'lanxi')
    old = cfg.lanxi;
    cfg = rmfield(cfg, 'lanxi');
    if ~isfield(cfg, 'daq') || ~isstruct(cfg.daq) || ~isscalar(cfg.daq)
        cfg.daq = struct('driver', 'lanxi');
    end
    if isstruct(old) && isscalar(old)
        cfg.daq = moveLegacy(cfg.daq, 'lanxi', old, fieldnames(old), 'lanxi', inFile);
    end
end
% ---- 2. generator.host / port / timeout -> generator.keysight33220a
if isfield(cfg, 'generator') && isstruct(cfg.generator) && isscalar(cfg.generator)
    g = cfg.generator;
    keys = legacyGen(isfield(g, legacyGen));
    if ~isempty(keys)
        drv = 'keysight33220a';
        if isfield(g, 'driver') && ~isempty(g.driver), drv = char(g.driver); end
        old = struct();
        for k = keys, old.(k{1}) = g.(k{1}); end
        g = rmfield(g, keys);
        g = moveLegacy(g, 'keysight33220a', old, keys, 'generator', inFile);
        if ~strcmp(drv, 'keysight33220a')
            given = keys(cellfun(@(k) ~isempty(old.(k)), keys));
            if ~isempty(given)
                warning('tim:config:legacyField', ['generator.%s (old layout) belong to the 33220A driver and are not ' ...
                    'used by the generator driver "%s": set them in generator.%s if that driver needs them.'], ...
                    strjoin(given, ', generator.'), drv, drv);
            end
        end
        cfg.generator = g;
    end
end
% ---- 3. missing driver names, 5. formatVersion
if isfield(cfg, 'generator') && isstruct(cfg.generator) && isscalar(cfg.generator) ...
        && (~isfield(cfg.generator, 'driver') || isempty(cfg.generator.driver))
    cfg.generator.driver = 'keysight33220a';
end
if ~inFile && isfield(cfg, 'generator') && ~isfield(cfg, 'daq')
    cfg.daq = struct('driver', 'lanxi');              % a full configuration without any DAQ section
end
if isfield(cfg, 'daq') && isstruct(cfg.daq) && isscalar(cfg.daq) && (~isfield(cfg.daq, 'driver') || isempty(cfg.daq.driver))
    cfg.daq.driver = 'lanxi';
end
if inFile || isfield(cfg, 'formatVersion'), cfg.formatVersion = 2; end
if inFile, return; end

% ---- 6. empty acquisition values -> defaults of the acquisition driver
if isfield(cfg, 'acquisition') && isfield(cfg, 'daq')
    d = info(cfg.daq.driver);
    if isempty(d) || ~isfield(d.defaults, 'acquisition'), d = info('lanxi'); end
    def = d.defaults.acquisition;
    for f = {'sampleRate', 'range', 'filter', 'ccld'}
        if ~isfield(cfg.acquisition, f{1}) || isempty(cfg.acquisition.(f{1}))
            cfg.acquisition.(f{1}) = def.(f{1});
        end
    end
end
% ---- 7. settings sub-struct of each selected driver
if isfield(cfg, 'daq') && isfield(cfg, 'generator')
    combined = strcmp(char(cfg.generator.driver), char(cfg.daq.driver));
    if ~combined
        cfg = withSettings(cfg, 'generator');
    end
    cfg = withSettings(cfg, 'daq');
end
end

function s = moveLegacy(s, name, old, keys, section, inFile)
% move the old keys into s.(name) field by field (rules 1, 2 and 4)
if isfield(s, name) && isstruct(s.(name)) && isscalar(s.(name))
    target = s.(name);
else
    target = struct();
end
def = struct();
d = info(name);
if ~isempty(d), def = d.defaults.settings; end
ignored = {};
for k = reshape(keys, 1, [])
    v = old.(k{1});
    if isempty(v) && isnumeric(v), continue; end      % JSON null: no setting
    if ~isfield(target, k{1}) || (isempty(target.(k{1})) && isnumeric(target.(k{1})))
        target.(k{1}) = v;
    elseif ~isequal(target.(k{1}), v)
        isDefault = isfield(def, k{1}) && isequal(target.(k{1}), def.(k{1}));
        if ~inFile && isDefault
            target.(k{1}) = v;                         % old script on the default configuration
        else
            ignored{end+1} = k{1}; %#ok<AGROW>
        end
    end
end
if ~isempty(ignored)
    warning('tim:config:legacyField', ['Old configuration key(s) %s.%s ignored: %s.%s.%s is set as well and is used ' ...
        '(remove the old key).'], section, strjoin(ignored, sprintf(', %s.', section)), sectionOf(section), name, ignored{1});
end
s.(name) = target;
end

function t = sectionOf(section)
% role section of an old key
if strcmp(section, 'lanxi'), t = 'daq'; else, t = section; end
end

function cfg = withSettings(cfg, section)
% the selected driver's settings: configured values merged onto its defaults
name = char(cfg.(section).driver);
d = info(name);
if isempty(d), return; end
cfg.(section).(name) = tim.instr.Instrument.settingsFrom(cfg, section, name, d.defaults.settings);
end

function d = info(name)
% driverInfo of a registered driver, [] for an unknown name
d = [];
list = tim.instr.drivers();
name = char(string(name));
k = find(strcmp(name, {list.name}), 1);
if ~isempty(k), d = tim.instr.driverInfo(name); end
end
