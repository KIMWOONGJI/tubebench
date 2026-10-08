function d = outputDir(cfg, which)
%OUTPUTDIR Folder for measurement data or calibrations.
%   d = tim.app.outputDir(cfg, 'data' | 'calibration')
%   In SIMULATION mode a relative folder gets a 'simulation' subfolder, so
%   simulated results can never be mistaken for real measurements or
%   calibrations. Absolute folders (e.g. test temp folders) are used as is.
switch which
    case 'data',        p = cfg.output.dataDir;
    case 'calibration', p = cfg.output.calibrationDir;
    otherwise, error('tim:app:outputDir', 'Unknown output kind "%s".', which);
end
isRelative = isempty(regexp(p, '^([A-Za-z]:[\\/]|[\\/])', 'once'));
d = tim.app.resolvePath(p);
if strcmp(cfg.mode, 'simulation') && isRelative
    d = fullfile(d, 'simulation');
end
end
