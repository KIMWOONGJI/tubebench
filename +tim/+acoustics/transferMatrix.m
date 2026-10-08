function tm = transferMatrix(method, varargin)
%TRANSFERMATRIX Two-port transfer matrix of the sample, [pL; uL] = T*[pR; uR].
%
%   tm = tim.acoustics.transferMatrix('twoLoad', resA, resB)
%       General method (ASTM E2611 two-load). resA, resB are outputs of
%       analyzeFourMic for the SAME sample and geometry, measured with two
%       acoustically different downstream terminations (or two source
%       positions). With P = [pL_a pL_b; uL_a uL_b] and Q = [pR_a pR_b; uR_a uR_b]:
%           T = P * inv(Q)
%       The column scaling of each load cancels, so relative pressures can be
%       used. The condition number of Q is returned: if the two loads are not
%       sufficiently different (Q nearly singular) T is not determined.
%
%   tm = tim.acoustics.transferMatrix('oneLoadSymmetric', res)
%       Single-load method, valid ONLY if the sample is reciprocal
%       (det T = 1) AND geometrically symmetric (T11 = T22). Under these two
%       assumptions (ASTM E2611, one-load method):
%           D   = pL*uR + pR*uL
%           T11 = T22 = (pR*uR + pL*uL) / D
%           T12 = (pL^2 - pR^2) / D
%           T21 = (uL^2 - uR^2) / D
%       A single excitation condition provides only 2 equations for the 4
%       unknown elements; this method is therefore NOT a general measurement
%       and must not be used for asymmetric samples.
%
%   Output tm: T11,T12,T21,T22 (Nf x 1), detT, reciprocityError = |detT - 1|,
%   symmetryError = |T11 - T22| / (|T11| + |T22|), condQ (two-load), method,
%   assumptions; plus anechoic-termination coefficients derived from T:
%       tau_a = 2 / (T11 + T12/Zc + Zc*T21 + T22)
%       R_a   = (T11 + T12/Zc - Zc*T21 - T22) / (T11 + T12/Zc + Zc*T21 + T22)
%   (tau_a: transmitted wave at the rear face / incident wave at the front
%   face, for an anechoic termination; TL = -20 log10 |tau_a| for equal
%   tube areas on both sides.)

switch method
    case 'twoLoad'
        a = varargin{1}; b = varargin{2};
        mustHaveBoundary(a); mustHaveBoundary(b);
        if numel(a.f) ~= numel(b.f) || any(abs(a.f - b.f) > 1e-9 * max(a.f))
            error('tim:tm:grid', 'Both loads must share the same frequency grid.');
        end
        Nf = numel(a.f);
        T = zeros(Nf, 4); condQ = zeros(Nf, 1);
        for i = 1:Nf
            P = [a.boundary.pL(i), b.boundary.pL(i); a.boundary.uL(i), b.boundary.uL(i)];
            Q = [a.boundary.pR(i), b.boundary.pR(i); a.boundary.uR(i), b.boundary.uR(i)];
            % Normalise velocity rows by Zc so cond(Q) is dimensionless
            Zc = a.Zc(i);
            Qn = Q .* [1; Zc];
            condQ(i) = cond(Qn);
            Ti = P / Q;
            T(i, :) = [Ti(1,1), Ti(1,2), Ti(2,1), Ti(2,2)];
        end
        tm = struct('T11', T(:,1), 'T12', T(:,2), 'T21', T(:,3), 'T22', T(:,4), 'condQ', condQ);
        tm.method = 'twoLoad';
        tm.assumptions = ['Linear, time-invariant sample; identical sample mounting for both loads; ' ...
            'the two loads must give linearly independent boundary states (check condQ).'];
        Zc = a.Zc; f = a.f;
    case 'oneLoadSymmetric'
        r = varargin{1};
        mustHaveBoundary(r);
        pL = r.boundary.pL; uL = r.boundary.uL; pR = r.boundary.pR; uR = r.boundary.uR;
        D = pL .* uR + pR .* uL;
        T11 = (pR .* uR + pL .* uL) ./ D;
        tm = struct('T11', T11, 'T12', (pL.^2 - pR.^2) ./ D, ...
            'T21', (uL.^2 - uR.^2) ./ D, 'T22', T11, 'condQ', nan(size(pL)));
        tm.method = 'oneLoadSymmetric';
        tm.assumptions = ['ASSUMED reciprocal (det T = 1) and symmetric (T11 = T22) sample. ' ...
            'Not a general transfer-matrix measurement.'];
        Zc = r.Zc; f = r.f;
    otherwise
        error('tim:tm:method', 'Unknown method "%s".', method);
end
tm.f = f;
tm.detT = tm.T11 .* tm.T22 - tm.T12 .* tm.T21;
tm.reciprocityError = abs(tm.detT - 1);
tm.symmetryError = abs(tm.T11 - tm.T22) ./ (abs(tm.T11) + abs(tm.T22));
den = tm.T11 + tm.T12 ./ Zc + Zc .* tm.T21 + tm.T22;
tm.tau_anechoic = 2 ./ den;
tm.R_anechoic = (tm.T11 + tm.T12 ./ Zc - Zc .* tm.T21 - tm.T22) ./ den;
tm.TL_dB = -20 * log10(abs(tm.tau_anechoic));
tm.Zseries = tm.T12;   % for a pure series element T = [1 Zs; 0 1]
tm.convention = '[pL; uL] = T [pR; uR], u positive towards +x (downstream), exp(+j omega t)';
end

function mustHaveBoundary(r)
if ~isfield(r, 'boundary') || ~r.boundary.available
    error('tim:tm:geometry', ...
        'Transfer matrix requires boundary-plane pressures/velocities (complete geometry).');
end
end
