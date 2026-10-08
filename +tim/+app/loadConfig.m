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

cfg = tim.app.defaultConfig();
if nargin < 1 || isempty(file), return; end
u = jsondecode(tim.app.readTextUtf8(file));
[cfg, unknown] = merge(cfg, u, 'cfg');
if ~isempty(unknown)
    warning('tim:config:unknownField', 'Unknown configuration field(s): %s', strjoin(unknown, ', '));
end
cfg.configFile = file;
tim.app.validateConfig(cfg);
end

function [d, unknown] = merge(d, u, path)
unknown = {};
fu = fieldnames(u);
for i = 1:numel(fu)
    k = fu{i};
    p = [path '.' k];
    if ~isfield(d, k)
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
