function saveConfig(cfg, file)
%SAVECONFIG Write a configuration as pretty-printed JSON (UTF-8, no BOM).
%   NaN values are written as null (= "not provided"). The run-time field
%   configFile (path the configuration was loaded from) is not written.
if isfield(cfg, 'configFile'), cfg = rmfield(cfg, 'configFile'); end
txt = jsonencode(cfg, 'PrettyPrint', true);
fid = fopen(file, 'w', 'n', 'UTF-8');
if fid < 0, error('tim:io:open', 'Cannot write "%s".', file); end
c = onCleanup(@() fclose(fid));
fwrite(fid, unicode2native(txt, 'UTF-8'));
end
