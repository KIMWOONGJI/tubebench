function name = measurementName(meas, res)
%MEASUREMENTNAME Name of a measurement folder after its time stamp.
%
%   name = tim.app.measurementName(meas, res)
%
%   tim.app.saveMeasurement writes data/<yyyyMMdd_HHmmss>_<name>/. The name
%   starts with the method, like the pair folder of two loads
%   (<yyyyMMdd_HHmmss>_twoload_<specimen>, tim.app.saveTwoLoad):
%
%     oneload_<signal>[_<specimen>]            one load
%     oneload-symmetric_<signal>[_<specimen>]  one load, the transfer matrix
%                                              of a symmetric specimen ASSUMED
%                                              (res.transferMatrix)
%     <signal>[_<specimen>]_load<role>_<tag>   one load of a two-load run
%                                              (metadata.twoLoad; the pair
%                                              folder names the method), e.g.
%                                              sweep_empty75_loadB_rigid-end
%     background                               background noise
%
%   <signal> is meas.kind (sweep, stepped, noise). <specimen> is
%   metadata.specimen, the name entered at Start. It is left out when no name
%   was entered. saveMeasurement replaces characters other than letters,
%   digits, '_' and '-'.

if nargin < 2, res = []; end
kind = char(meas.kind);
if strcmp(kind, 'background'), name = kind; return; end
md = struct();
if isfield(meas, 'metadata') && isstruct(meas.metadata), md = meas.metadata; end
name = kind;
if isfield(md, 'specimen') && ~isempty(md.specimen) && ~strcmp(md.specimen, 'unnamed specimen')
    name = [name '_' char(md.specimen)];
end
if isfield(md, 'twoLoad') && isstruct(md.twoLoad) && isfield(md.twoLoad, 'role')
    tag = '';
    if isfield(md, 'termination') && isstruct(md.termination) && isfield(md.termination, 'kind')
        d = tim.app.describeLoad(struct('kind', md.termination.kind, 'place', md.termination.place));
        tag = ['_' d.tag];
    end
    name = sprintf('%s_load%s%s', name, md.twoLoad.role, tag);
    return
end
method = 'oneload';
if isstruct(res) && isfield(res, 'transferMatrix') && isstruct(res.transferMatrix) ...
        && isfield(res.transferMatrix, 'method') && strcmp(res.transferMatrix.method, 'oneLoadSymmetric')
    method = 'oneload-symmetric';
end
name = [method '_' name];
end
