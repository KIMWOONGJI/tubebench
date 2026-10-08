function md = collectMetadata(session)
%COLLECTMETADATA Complete measurement metadata (instruments, software, config).
c = session.Cfg;
md = struct();
md.timestamp = char(datetime('now', 'TimeZone', 'local'), 'yyyy-MM-dd''T''HH:mm:ss.SSSZ');
md.mode = c.mode;
md.matlabVersion = version;
md.matlabRelease = version('-release');
v = ver;
md.toolboxes = strjoin(arrayfun(@(x) sprintf('%s %s', x.Name, x.Version), v, 'UniformOutput', false), '; ');
md.computer = computer;
md.software = tim.app.softwareVersion();
md.generator = struct('identity', [], 'host', c.generator.host, 'port', c.generator.port, ...
    'maxVpp', c.generator.maxVpp, 'load', c.generator.load);
if ~isempty(session.Gen), md.generator.identity = session.Gen.Identity; end
md.amplifier = c.amplifier;
md.amplifier.confirmedSignature = session.ConfirmedExcitation;
md.daq = struct('host', c.lanxi.host, 'connector', c.lanxi.connector, 'model', '', 'serial', NaN, ...
    'firmware', '', 'setup', [], 'teds', {{}});
if ~isempty(session.Daq) && ~isempty(fieldnames(session.Daq.Info))
    md.daq.model = session.Daq.Info.model;
    md.daq.serial = session.Daq.Info.serial;
    md.daq.firmware = session.Daq.Info.firmware;
    md.daq.setup = session.Daq.Setup;
    md.daq.teds = session.Daq.Teds;
end
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
