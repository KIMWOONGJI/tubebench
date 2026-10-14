function t = dataTitle(src, opts)
%DATATITLE One-line identification of the data shown in a plot.
%   t = tim.plots.dataTitle(res)         'Swept sine  ·  2026-10-09 11:15:37  ·  CAL-20261009-105835'
%   t = tim.plots.dataTitle(meas)        'Background noise  ·  2026-10-09 11:20:01'
%   t = tim.plots.dataTitle(cal)         'Calibration CAL-20261009-105835'
%   t = tim.plots.dataTitle(tl)          'Two loads: Absorber at tube end / Rigid cap at tube end  ·  ...'
%                                        (tim.app.processTwoLoad)
%   opts.simulation (logical) appends '  ·  SIMULATION'.
%   Used as the axes title of every view (the header of a GUI view says
%   WHAT is shown; this line says WHICH data), so a stale plot is visible.
if nargin < 2, opts = struct(); end
sep = [' ' char(183) ' '];
parts = {};
if isstruct(src) && isfield(src, 'C') && isfield(src, 'version')          % calibration
    parts{end + 1} = ['Calibration ' src.version];
elseif isstruct(src) && isfield(src, 'method') && isfield(src, 'T')      % transfer matrix (tim.app.processTwoLoad)
    if strcmp(src.method, 'oneLoadSymmetric')
        parts{end + 1} = 'One load, symmetric specimen ASSUMED';
    else
        lab = {src.loads(ismember({src.loads.role}, {'A', 'B'})).label};
        parts{end + 1} = ['Two loads: ' strjoin(lab, ' / ')];
    end
    if isfield(src, 'timestamp') && ~isempty(src.timestamp), parts{end + 1} = char(src.timestamp); end
    if isfield(src, 'calibrationVersion')
        if strcmp(src.calibrationVersion, 'none')
            parts{end + 1} = 'NO calibration';
        else
            parts{end + 1} = src.calibrationVersion;
        end
    end
elseif isstruct(src)
    kind = ''; if isfield(src, 'kind'), kind = src.kind; end
    switch kind
        case 'sweep', parts{end + 1} = 'Swept sine';
        case 'stepped', parts{end + 1} = 'Stepped sine';
        case 'noise', parts{end + 1} = 'Random noise';
        case 'background', parts{end + 1} = 'Background noise';
        otherwise, if ~isempty(kind), parts{end + 1} = kind; end
    end
    if isfield(src, 'timestamp') && ~isempty(src.timestamp)
        ts = src.timestamp;
        if isdatetime(ts), ts = char(ts, 'yyyy-MM-dd HH:mm:ss'); end
        parts{end + 1} = char(ts);
    end
    if isfield(src, 'calibration') && isstruct(src.calibration) && isfield(src.calibration, 'version')
        if strcmp(src.calibration.version, 'none')
            parts{end + 1} = 'NO calibration';
        else
            parts{end + 1} = src.calibration.version;
        end
    end
end
if isfield(opts, 'simulation') && opts.simulation, parts{end + 1} = 'SIMULATION'; end
t = strjoin(parts, sep);
end
