function model = readStep(file)
%READSTEP Minimal STEP (ISO 10303-21, AP203/AP214) reader for assemblies.
%
%   model = tim.cad.readStep('cad/transfer-impedance-tube.step')
%
%   Extracts what is needed to dimension the impedance tube - not a general
%   CAD kernel:
%     model.products(i)  : name, id of PRODUCT_DEFINITION, local geometry
%                          (cylinders: point, axis, radius; planes: point,
%                          normal; vertex points), local bounding box
%     model.instances(j) : product index, world transform T (4x4, mm),
%                          path of occurrence names, world bounding box
%   The assembly transform of each NEXT_ASSEMBLY_USAGE_OCCURRENCE is taken
%   from CONTEXT_DEPENDENT_SHAPE_REPRESENTATION ->
%   REPRESENTATION_RELATIONSHIP_WITH_TRANSFORMATION -> ITEM_DEFINED_TRANSFORMATION
%   as T = A(item_1) * inv(A(item_2)) (child -> parent), with A the 4x4
%   matrix of an AXIS2_PLACEMENT_3D (convention verified on the lab tube
%   export, see below). Units are those of the file (checked: mm).

txt = fileread(file);
i0 = strfind(txt, 'DATA;'); i1 = strfind(txt, 'ENDSEC;');
i1 = i1(i1 > i0(1));
data = txt(i0(1) + 5:i1(1) - 1);
% one entity per "#id = ... ;" (strings in STEP do not contain ';' here)
tok = regexp(data, '#(\d+)\s*=\s*(.*?);\s*(?=#\d+\s*=|$)', 'tokens');
n = numel(tok);
ids = zeros(n, 1); types = cell(n, 1); args = cell(n, 1);
for k = 1:n
    ids(k) = str2double(tok{k}{1});
    body = strtrim(tok{k}{2});
    m = regexp(body, '^([A-Z0-9_]+)\s*\((.*)\)$', 'tokens', 'once');
    if isempty(m)
        types{k} = 'COMPLEX'; args{k} = body;
    else
        types{k} = m{1}; args{k} = m{2};
    end
end
E = struct('ids', ids, 'types', {types}, 'args', {args});
idx = containers.Map('KeyType', 'double', 'ValueType', 'double');
for k = 1:n, idx(ids(k)) = k; end
E.idx = idx;
model.file = file;
model.unit = 'mm';
if isempty(regexp(txt, 'SI_UNIT\s*\(\s*\.MILLI\.\s*,\s*\.METRE\.', 'once'))
    warning('tim:cad:unit', 'Length unit is not millimetre - check the file.');
    model.unit = 'unknown';
end

% ---- products and their shape representations
pdIds = ids(strcmp(types, 'PRODUCT_DEFINITION'));
model.products = struct('name', {}, 'pd', {}, 'rep', {}, 'cyl', {}, 'planes', {}, 'pts', {}, 'bbox', {});
for p = pdIds(:).'
    a = splitArgs(getArgs(E, p));
    form = ref(a{3});                                   % PRODUCT_DEFINITION_FORMATION
    fa = splitArgs(getArgs(E, form));
    prod = ref(fa{3});
    pa = splitArgs(getArgs(E, prod));
    name = strrep(strtrim(pa{1}), '''', '');
    pds = findRefTo(E, 'PRODUCT_DEFINITION_SHAPE', p, 3);
    rep = [];
    for s = pds(:).'
        sdr = findRefTo(E, 'SHAPE_DEFINITION_REPRESENTATION', s, 1);
        if ~isempty(sdr), sa = splitArgs(getArgs(E, sdr(1))); rep = ref(sa{2}); end
    end
    model.products(end+1) = struct('name', name, 'pd', p, 'rep', rep, 'cyl', [], 'planes', [], 'pts', [], 'bbox', []);
end

% ---- geometry of every product (reachable from its representation and
%      from representations related to it by SHAPE_REPRESENTATION_RELATIONSHIP)
for i = 1:numel(model.products)
    r = model.products(i).rep;
    if isempty(r), continue; end
    reps = r;
    srr = find(contains(args, sprintf('#%d', r)) & (strcmp(types, 'SHAPE_REPRESENTATION_RELATIONSHIP') | strcmp(types, 'COMPLEX')));
    for k = srr(:).'
        if strcmp(types{k}, 'COMPLEX') && contains(args{k}, 'TRANSFORMATION'), continue; end
        rr = regexp(args{k}, '#(\d+)', 'tokens');
        rr = cellfun(@(c) str2double(c{1}), rr);
        reps = union(reps, rr);
    end
    [cyl, pl, pts] = collectGeometry(E, reps);
    model.products(i).cyl = cyl; model.products(i).planes = pl; model.products(i).pts = pts;
    if ~isempty(pts), model.products(i).bbox = [min(pts, [], 1); max(pts, [], 1)]; end
end

% ---- assembly tree: occurrences with transforms
nauo = ids(strcmp(types, 'NEXT_ASSEMBLY_USAGE_OCCURRENCE'));
occ = struct('id', {}, 'name', {}, 'parentPd', {}, 'childPd', {}, 'T', {}, 'A1', {}, 'A2', {}, 'rel', {});
for o = nauo(:).'
    a = splitArgs(getArgs(E, o));
    T = eye(4); A1 = eye(4); A2 = eye(4);
    pds = findRefTo(E, 'PRODUCT_DEFINITION_SHAPE', o, 3);
    if ~isempty(pds)
        cdsr = findRefTo(E, 'CONTEXT_DEPENDENT_SHAPE_REPRESENTATION', pds(1), 2);
        if ~isempty(cdsr)
            ca = splitArgs(getArgs(E, cdsr(1))); rel = ref(ca{1});
            relArgs = getArgs(E, rel);
            idt = regexp(relArgs, 'REPRESENTATION_RELATIONSHIP_WITH_TRANSFORMATION\s*\(\s*#(\d+)', 'tokens', 'once');
            if ~isempty(idt)
                ia = splitArgs(getArgs(E, str2double(idt{1})));
                A1 = axisMatrix(E, ref(ia{3})); A2 = axisMatrix(E, ref(ia{4}));
                % child -> parent transform. Verified on the SolidWorks 2024 AP214
                % export of the lab tube: with T = A1*inv(A2) all bores (r = 14.5 mm)
                % are coaxial to 0.000 mm and the four 4957 microphones sit on
                % their ports (29.00 mm spacing); A2*inv(A1) scatters the parts.
                T = A1 / A2;
            end
        end
    end
    occ(end+1) = struct('id', o, 'name', strrep(strtrim(a{1}), '''', ''), 'parentPd', ref(a{4}), ...
        'childPd', ref(a{5}), 'T', T, 'A1', A1, 'A2', A2, 'rel', relArgsOrEmpty(E, o)); %#ok<AGROW>
end
model.occurrences = occ;

% ---- world placement of every leaf instance (recursive from the root)
childPds = [occ.childPd];
roots = setdiff([model.products.pd], childPds);
model.instances = struct('product', {}, 'name', {}, 'T', {}, 'path', {}, 'bbox', {});
for rt = roots(:).'
    model = place(model, rt, eye(4), {});
end
end

% =====================================================================
function model = place(model, pd, T, path)
occ = model.occurrences;
kids = find([occ.parentPd] == pd);
ip = find([model.products.pd] == pd, 1);
if ~isempty(model.products(ip).cyl) || ~isempty(model.products(ip).pts)
    bb = [];
    P = model.products(ip).pts;
    if ~isempty(P)
        W = (T * [P, ones(size(P, 1), 1)].').';
        bb = [min(W(:, 1:3), [], 1); max(W(:, 1:3), [], 1)];
    end
    model.instances(end+1) = struct('product', ip, 'name', model.products(ip).name, 'T', T, ...
        'path', {path}, 'bbox', bb);
end
for k = kids(:).'
    model = place(model, occ(k).childPd, T * occ(k).T, [path, {occ(k).name}]);
end
end

function [cyl, pl, pts] = collectGeometry(E, startIds)
% breadth-first traversal of references; collects surfaces and points
seen = containers.Map('KeyType', 'double', 'ValueType', 'logical');
queue = startIds(:).';
cyl = struct('p', {}, 'axis', {}, 'r', {}); pl = struct('p', {}, 'n', {}); pts = zeros(0, 3);
while ~isempty(queue)
    id = queue(1); queue(1) = [];
    if isKey(seen, id) || ~isKey(E.idx, id), continue; end
    seen(id) = true;
    k = E.idx(id); t = E.types{k}; a = E.args{k};
    switch t
        case 'CYLINDRICAL_SURFACE'
            s = splitArgs(a);
            [o, z] = axisPZ(E, ref(s{2}));
            cyl(end+1) = struct('p', o, 'axis', z, 'r', str2double(s{3})); %#ok<AGROW>
            continue
        case 'PLANE'
            s = splitArgs(a);
            [o, z] = axisPZ(E, ref(s{2}));
            pl(end+1) = struct('p', o, 'n', z); %#ok<AGROW>
            continue
        case 'VERTEX_POINT'
            s = splitArgs(a);
            pts(end+1, :) = point(E, ref(s{2})); %#ok<AGROW>
            continue
        case {'CARTESIAN_POINT', 'DIRECTION', 'AXIS2_PLACEMENT_3D', 'STYLED_ITEM', ...
              'PRESENTATION_STYLE_ASSIGNMENT', 'COLOUR_RGB'}
            continue
    end
    r = regexp(a, '#(\d+)', 'tokens');
    for j = 1:numel(r)
        queue(end+1) = str2double(r{j}{1}); %#ok<AGROW>
    end
end
end

function s = relArgsOrEmpty(E, o)
% raw text of the representation relationship of an occurrence (debugging)
s = '';
pds = findRefTo(E, 'PRODUCT_DEFINITION_SHAPE', o, 3);
if isempty(pds), return; end
cdsr = findRefTo(E, 'CONTEXT_DEPENDENT_SHAPE_REPRESENTATION', pds(1), 2);
if isempty(cdsr), return; end
ca = splitArgs(getArgs(E, cdsr(1)));
s = getArgs(E, ref(ca{1}));
end

function A = axisMatrix(E, id)
s = splitArgs(getArgs(E, id));
o = point(E, ref(s{2}));
z = [0 0 1]; x = [1 0 0];
if numel(s) >= 3 && ~strcmp(strtrim(s{3}), '$'), z = dirv(E, ref(s{3})); end
if numel(s) >= 4 && ~strcmp(strtrim(s{4}), '$'), x = dirv(E, ref(s{4})); end
z = z / norm(z); x = x - dot(x, z) * z; x = x / norm(x); y = cross(z, x);
A = [x(:) y(:) z(:) o(:); 0 0 0 1];
end

function [o, z] = axisPZ(E, id)
A = axisMatrix(E, id); o = A(1:3, 4).'; z = A(1:3, 3).';
end

function v = point(E, id)
s = getArgs(E, id);
v = sscanf(regexprep(s, '^.*?\(\s*([^)]*)\).*$', '$1'), '%f,').';
end

function v = dirv(E, id)
v = point(E, id);
end

function a = getArgs(E, id)
a = E.args{E.idx(id)};
end

function r = ref(s)
t = regexp(s, '#(\d+)', 'tokens', 'once');
if isempty(t), r = []; else, r = str2double(t{1}); end
end

function out = findRefTo(E, type, target, argPos)
% entities of TYPE whose argument number argPos references #target
cand = find(strcmp(E.types, type));
out = [];
pat = sprintf('#%d', target);
for k = cand(:).'
    if ~contains(E.args{k}, pat), continue; end
    s = splitArgs(E.args{k});
    if numel(s) >= argPos && isequal(ref(s{argPos}), target)
        out(end+1) = E.ids(k); %#ok<AGROW>
    end
end
end

function parts = splitArgs(s)
% split top-level comma-separated arguments (respecting parentheses / quotes)
parts = {}; depth = 0; inq = false; start = 1;
for i = 1:numel(s)
    ch = s(i);
    if ch == '''', inq = ~inq; end
    if inq, continue; end
    if ch == '(', depth = depth + 1; elseif ch == ')', depth = depth - 1; end
    if ch == ',' && depth == 0
        parts{end+1} = s(start:i-1); start = i + 1; %#ok<AGROW>
    end
end
parts{end+1} = s(start:end);
end
