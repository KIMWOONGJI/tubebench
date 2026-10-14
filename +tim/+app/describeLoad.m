function d = describeLoad(load, cfg)
%DESCRIBELOAD Names, place and distance of a termination load (WO-005).
%
%   d = tim.app.describeLoad(load, cfg)
%   c = tim.app.describeLoad()             % the catalogue: c.kinds, c.places
%
%   A load is the termination of the tube during one measurement:
%     load.kind   'absorber'  the absorber in the extension tube, end cap on
%                 'rigid'     a rigid, sealed cap
%                 'open'      the tube left open
%     load.place  'tubeEnd'   end of the extension tube (end cap), the
%                             distance tubeDrawing.downstreamLength behind M4
%                 'joint'     joint of the downstream tube and the extension
%                             tube (extension removed), downstreamTubeEnd
%                             behind M4
%   The absorber exists only at the tube end. Any pair of different loads can
%   be used for the two-load method (ASTM E2611 [3]); the standard's example
%   and Brüel & Kjær's practice is an open and an approximately anechoic
%   termination.
%
%   d.kind, d.place        the values
%   d.label                'Rigid cap at tube end' (window texts, English)
%   d.kindLabel, d.placeLabel
%   d.distance_m           termination face behind M4 [m] (NaN: not known)
%   d.tag                  short tag for folder names, e.g. 'rigid-end'
%   The operator texts (English / Korean) come from tim.app.msg ('tlMount_*').

kinds = struct('value', {'absorber', 'rigid', 'open'}, 'label', {'Absorber', 'Rigid cap', 'Open end'}, ...
    'tag', {'absorber', 'rigid', 'open'});
places = struct('value', {'tubeEnd', 'joint'}, 'label', {'Tube end', 'Joint'}, 'tag', {'end', 'joint'});
if nargin == 0
    d = struct('kinds', kinds, 'places', places);
    return
end
if nargin < 2, cfg = struct(); end
checkLoad(load, kinds, places);
k = kinds(strcmp({kinds.value}, char(load.kind)));
p = places(strcmp({places.value}, char(load.place)));
d = struct('kind', k.value, 'place', p.value, 'label', sprintf('%s at %s', k.label, lower(p.label)), ...
    'kindLabel', k.label, 'placeLabel', p.label, 'distance_m', NaN, 'tag', [k.tag '-' p.tag]);
if isfield(cfg, 'tubeDrawing')
    td = cfg.tubeDrawing;
    if strcmp(d.place, 'tubeEnd') && isfield(td, 'downstreamLength')
        d.distance_m = td.downstreamLength;
    elseif strcmp(d.place, 'joint') && isfield(td, 'downstreamTubeEnd')
        d.distance_m = td.downstreamTubeEnd;
    end
end
end

function checkLoad(load, kinds, places)
% a load must name a known kind and place; the absorber only at the tube end
ok = isstruct(load) && isscalar(load) && all(isfield(load, {'kind', 'place'}));
if ok
    kd = load.kind; pl = load.place;
    ok = (ischar(kd) || (isstring(kd) && isscalar(kd))) && (ischar(pl) || (isstring(pl) && isscalar(pl))) && ...
        any(strcmp(char(kd), {kinds.value})) && any(strcmp(char(pl), {places.value}));
end
if ~ok
    error('tim:config:termination', ['A termination load needs kind ''absorber'', ''rigid'' or ''open'' and place ' ...
        '''tubeEnd'' or ''joint'' (measurement.loadA, measurement.loadB).']);
end
if strcmp(char(load.kind), 'absorber') && ~strcmp(char(load.place), 'tubeEnd')
    error('tim:config:termination', ['The absorber exists only at the tube end (measurement.loadA / loadB: ' ...
        'kind ''absorber'', place ''tubeEnd'').']);
end
end
