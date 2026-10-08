function file = saveEmergency(session, partial)
%SAVEEMERGENCY Preserve data acquired before an error (never overwrites).
file = '';
try
    d = fullfile(tim.app.outputDir(session.Cfg, 'data'), 'emergency');
    if ~exist(d, 'dir'), mkdir(d); end
    file = tim.app.uniqueName(fullfile(d, ['partial_' char(datetime('now'), 'yyyyMMdd_HHmmss') '.mat']));
    log = session.LogLines; %#ok<NASGU>
    md = tim.app.collectMetadata(session); %#ok<NASGU>
    save(file, 'partial', 'log', 'md', '-v7.3');
catch err
    warning('tim:emergency', 'Could not save partial data: %s', err.message);
end
end
