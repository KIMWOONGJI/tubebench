function obj = create(role, cfg, ctx, other)
%CREATE Build the instrument driver that the configuration selects for a role.
%
%   src = tim.instr.create('source', cfg, ctx)
%   acq = tim.instr.create('acquisition', cfg, ctx, src)
%
%   role   'source' (driver cfg.generator.driver) | 'acquisition' (cfg.daq.driver)
%   ctx    mode ('simulation' | 'hardware'; default cfg.mode), rig
%          (tim.sim.SimulatedRig, simulation), progress (@(key, state, detail),
%          the connection checklist; it may throw to stop the connection)
%   other  the object already created for the other role, or []. When both
%          roles name the same driver and it takes both roles, other itself is
%          returned (one combined object, one connection).
%
%   Checks BEFORE any I/O (docs/instrument_interface.md section 9.1), for the
%   whole selection of both roles, so that the first instrument is not
%   opened when the second cannot be used:
%     1. both drivers registered                           tim:instr:unknownDriver
%     2. the driver has the role                            tim:instr:role
%     3. the pairing: one object takes both roles exactly when both roles name
%        the same driver; a rolesTogether driver must take both roles; an
%        acquisition driver with needsOwnSource must also be the source
%                                                           tim:instr:role
%     4. no simulation-only driver in hardware mode         tim:instr:simulationOnly
%     5. hardware mode: products installed and licensed, checkInstalled()
%                                                           tim:instr:missingProduct
%     6. hardware mode: a source without output read-back only with
%        generator.allowUnconfirmedOff = true               tim:instr:readback
%     7. the drivers' checkConfig(cfg)                      tim:config:*
%   (4-7 for the driver of each role, a combined driver once.)
%   Then the driver's fromConfig(cfg, ctx) connects, identifies and puts the
%   instrument in its safe state; ctx.roles and ctx.settings (the driver
%   sub-struct merged onto describe().defaults.settings) are filled in, and
%   ctx.progress becomes the object's ProgressFcn.
%
%   Until the configuration has formatVersion 2 (WO-001 stage B) the legacy
%   keys are read: generator.host / port / timeout for the 33220A, the
%   top-level lanxi section, and a missing driver name = the role's default.

if nargin < 3 || isempty(ctx), ctx = struct(); end
if nargin < 4, other = []; end
if ~isfield(ctx, 'mode') || isempty(ctx.mode), ctx.mode = cfg.mode; end
if ~isfield(ctx, 'rig'), ctx.rig = []; end
if ~isfield(ctx, 'progress'), ctx.progress = []; end
roles = {'source', 'acquisition'};
sections = {'generator', 'daq'};
r = find(strcmp(role, roles), 1);
if isempty(r)
    error('tim:instr:role', 'Unknown instrument role "%s" (source or acquisition).', char(string(role)));
end
cfg = withDriverLayout(cfg);
names = {char(cfg.generator.driver), char(cfg.daq.driver)};
info = {tim.instr.driverInfo(names{1}), tim.instr.driverInfo(names{2})};      % 1
same = strcmp(names{1}, names{2});
for k = 1:2                                                                     % 2, 3
    c = info{k}.capabilities;
    if ~any(strcmp(roles{k}, c.roles))
        error('tim:instr:role', 'The %s (driver "%s", %s.driver) cannot be the %s.', ...
            info{k}.displayName, names{k}, sections{k}, roleText(roles{k}));
    end
    if same && ~all(ismember(roles, c.roles))
        error('tim:instr:role', ['generator.driver and daq.driver both name "%s", but the %s takes only one role; ' ...
            'name a %s driver for the other role.'], names{k}, info{k}.displayName, roleText(setdiff(roles, c.roles)));
    end
    if c.rolesTogether && ~same
        error('tim:instr:role', ['The %s (driver "%s") works only as generator and acquisition together: set ' ...
            'generator.driver and daq.driver both to "%s" (now "%s" and "%s").'], ...
            info{k}.displayName, names{k}, names{k}, names{1}, names{2});
    end
end
qa = info{2}.capabilities.acquisition;
if isfield(qa, 'needsOwnSource') && qa.needsOwnSource && ~same
    error('tim:instr:role', ['The %s (driver "%s") delivers its data only in whole blocks, so it cannot record the ' ...
        'excitation of the %s (driver "%s"): set generator.driver to "%s" as well.'], ...
        info{2}.displayName, names{2}, info{1}.displayName, names{1}, names{2});
end
hardware = strcmp(ctx.mode, 'hardware');
for k = 1:2 - same                                                              % 4 - 7, each driver once
    d = info{k}; cls = d.class; caps = d.capabilities;
    if hardware && strcmp(d.simulation, 'only')                                % 4
        error('tim:instr:simulationOnly', 'The %s (driver "%s") exists only in simulation mode.', d.displayName, d.name);
    end
    if hardware                                                                 % 5
        tim.instr.checkProducts(caps.products, d.displayName);
        if any(strcmp('checkInstalled', methods(cls)))
            feval([cls '.checkInstalled']);
        end
    end
    if hardware && k == 1 && strcmp(caps.source.readback, 'none')              % 6
        allow = isfield(cfg.generator, 'allowUnconfirmedOff') && isequal(cfg.generator.allowUnconfirmedOff, true);
        if ~allow
            error('tim:instr:readback', ['The %s cannot report whether its output is off. Use it only if you accept ' ...
                'that: set generator.allowUnconfirmedOff to true.'], d.displayName);
        end
    end
    feval([cls '.checkConfig'], cfg);                                          % 7
end

d = info{r}; cls = d.class; caps = d.capabilities;
both = same && all(ismember(roles, caps.roles));
if both && ~isempty(other) && isa(other, cls)
    obj = other;                       % the combined object already exists
    return
end
section = sections{r};
if both
    ctx.roles = roles;
    section = 'daq';                   % a combined driver reads daq.<name>
else
    ctx.roles = {role};
end
ctx.settings = tim.instr.Instrument.settingsFrom(cfg, section, d.name, d.defaults.settings);
obj = feval([cls '.fromConfig'], cfg, ctx);
if ~isempty(ctx.progress), obj.ProgressFcn = ctx.progress; end
end

function cfg = withDriverLayout(cfg)
% formatVersion 1 seen through the driver layout of formatVersion 2 (stage A
% only; stage B: tim.app.migrateConfig). Legacy keys go only to the legacy
% driver (docs/instrument_interface.md section 9.3).
if ~isfield(cfg.generator, 'driver') || isempty(cfg.generator.driver), cfg.generator.driver = 'keysight33220a'; end
if ~isfield(cfg, 'daq') || ~isstruct(cfg.daq), cfg.daq = struct(); end
if ~isfield(cfg.daq, 'driver') || isempty(cfg.daq.driver), cfg.daq.driver = 'lanxi'; end
if strcmp(cfg.generator.driver, 'keysight33220a') && ~isfield(cfg.generator, 'keysight33220a')
    st = struct();
    for k = {'host', 'port', 'timeout'}
        if isfield(cfg.generator, k{1}), st.(k{1}) = cfg.generator.(k{1}); end
    end
    cfg.generator.keysight33220a = st;
end
if strcmp(cfg.daq.driver, 'lanxi') && ~isfield(cfg.daq, 'lanxi') && isfield(cfg, 'lanxi')
    cfg.daq.lanxi = cfg.lanxi;
end
end

function t = roleText(role)
% operator name of a role
if iscell(role), role = role{1}; end
if strcmp(role, 'source'), t = 'signal source (generator)'; else, t = 'acquisition (DAQ)'; end
end
