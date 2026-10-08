function files = exportFigures(figs, folder, formats)
%EXPORTFIGURES Save figures as PNG (raster) and PDF/SVG (vector).
%   figs: struct of figure handles (field name = file stem)
if nargin < 3, formats = {'png', 'pdf'}; end
files = {};
names = fieldnames(figs);
for i = 1:numel(names)
    h = figs.(names{i});
    if isempty(h) || ~isgraphics(h), continue; end
    for k = 1:numel(formats)
        fmt = lower(formats{k});
        file = fullfile(folder, sprintf('fig_%s.%s', names{i}, fmt));
        switch fmt
            case 'png', exportgraphics(h, file, 'Resolution', 200);
            case 'pdf', exportgraphics(h, file, 'ContentType', 'vector');
            case 'svg', print(h, file, '-dsvg');
            case 'fig', savefig(h, file);
            otherwise, warning('tim:export:format', 'Unknown figure format %s.', fmt); continue
        end
        files{end+1} = file; %#ok<AGROW>
    end
end
end
