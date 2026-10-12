function md = collectMetadata(session)
%COLLECTMETADATA Complete measurement metadata (instruments, software, config).
%
%   md = tim.app.collectMetadata(session)
%   md.generator and md.daq are the metadata() of the connected drivers
%   (docs/instrument_interface.md section 7): driver, displayName, roles,
%   identity (vendor, model, serial, firmware and raw text, as the instrument
%   reported them), sharedClock and the driver settings in use, plus each
%   driver's own fields - for the 33220A and the LAN-XI module the fields
%   stored before 1.2.0 (generator: identity, host, port, maxVpp, load; daq:
%   host, connector, model, serial, firmware, setup, teds). md.generator
%   always has maxVpp and load. A device that takes both roles appears in
%   both. Without a connected instrument: the configured driver and settings
%   with an empty identity. Readers of the newer fields (driver, identity,
%   integrity.channelFaults) check isfield: measurements saved before 1.2.0
%   lack them.
c = session.Cfg;
md = struct();
md.timestamp = char(datetime('now', 'TimeZone', 'local'), 'yyyy-MM-dd''T''HH:mm:ss.SSSZ');
md.mode = c.mode;
md.matlabVersion = version;
md.matlabRelease = version('-release');
v = ver;
md.toolboxes = strjoin(arrayfun(@(x) sprintf('%s %s', x.Name, x.Version), v, 'UniformOutput', false), '; ');
md.computer = computer;
[md.software, md.softwareInfo] = tim.app.softwareVersion();   % version, GitHub URL, Git commit
md.generator = instrumentMetadata(session.Gen, c, 'generator');
if ~isfield(md.generator, 'maxVpp'), md.generator.maxVpp = c.generator.maxVpp; end
if ~isfield(md.generator, 'load'), md.generator.load = c.generator.load; end
md.amplifier = c.amplifier;
md.amplifier.confirmedSignature = session.ConfirmedExcitation;
md.daq = instrumentMetadata(session.Daq, c, 'daq');
md.acquisition = c.acquisition;
md.mics = session.Mics;
md.geometry = c.geometry;
md.environment = c.environment;
md.excitation = c.excitation;
md.analysis = c.analysis;
md.calibrationVersion = 'none';
if ~isempty(session.Calibration), md.calibrationVersion = session.Calibration.version; end
md.config = c;
if strcmp(c.mode, 'simulation') && ~isempty(session.Rig)
    md.simulationTruth = struct('Geometry', session.Rig.Geometry, 'Sample', session.Rig.Sample, ...
        'Termination', session.Rig.Termination, 'MicPosOfChannel', session.Rig.MicPosOfChannel, ...
        'TriggerLog', session.Rig.TriggerLog);
    md.WARNING = 'SIMULATED DATA - not a physical measurement.';
end
end

function m = instrumentMetadata(obj, c, section)
% metadata() of a driver object, or what the configuration says without one
if ~isempty(obj)
    m = obj.metadata();
    return
end
name = char(string(c.(section).driver));
m = struct('driver', name, 'displayName', '', 'roles', {{}}, 'identity', tim.instr.Instrument.emptyIdentity(), ...
    'sharedClock', false, 'settings', struct());
if isfield(c.(section), name) && isstruct(c.(section).(name)), m.settings = c.(section).(name); end
if any(strcmp(name, {tim.instr.drivers().name}))
    d = tim.instr.driverInfo(name);
    m.displayName = d.displayName;
    m.roles = d.capabilities.roles;
    m.sharedClock = d.capabilities.sharedClock;
    m.settings = tim.instr.Instrument.settingsFrom(c, section, name, d.defaults.settings);
end
f = fieldnames(m.settings);
for i = 1:numel(f)
    if ~isfield(m, f{i}), m.(f{i}) = m.settings.(f{i}); end    % e.g. host, port, connector as before 1.2.0
end
end
