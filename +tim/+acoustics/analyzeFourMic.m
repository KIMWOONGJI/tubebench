function res = analyzeFourMic(f, H, geom, env, opts)
%ANALYZEFOURMIC Four-microphone wave decomposition and sample quantities.
%
%   res = tim.acoustics.analyzeFourMic(f, H, geom, env, opts)
%
%   INPUTS
%   f    (Nf x 1) frequency vector [Hz]
%   H    (Nf x 4) calibrated complex pressures at the tube positions
%        M1..M4 (columns ordered by POSITION, M1 nearest the loudspeaker).
%        Usually H(:,m) = p_m / p_ref (relative to a reference channel); all
%        outputs except absolute amplitudes are invariant to that scaling.
%   geom struct:
%        diameter        [m]
%        micPositions    1x4 axial coordinates of M1..M4 [m] (NaN = unknown)
%        spacingUp       |x2 - x1| [m] (used when positions unknown)
%        spacingDown     |x4 - x3| [m]
%        xFront, xRear   sample front (upstream) / rear (downstream) face [m]
%                        (NaN = unknown -> boundary quantities disabled)
%        Coordinate x increases from the loudspeaker towards the termination.
%   env  struct for tim.acoustics.airProperties (temperature_C, pressure_Pa,...)
%   opts struct (all optional):
%        lossModel        'iso10534' (default) | 'none'
%        velocityRef      'mean' (default) | 'upstream' | 'downstream'
%        condMax          max allowed condition number of decomposition (40)
%        phaseUncertainty_rad  inter-channel phase uncertainty after
%                         calibration, for the low-frequency sensitivity
%                         estimate (default 0.002 rad)
%        maxPhaseSensitivity   allowed relative error from phase uncertainty (0.05)
%        quality          struct with coherence (Nf x 4) and snr_dB (Nf x 4)
%        coherenceMin     (0.98)   snrMin_dB (20)
%        calValid         (Nf x 1 logical) calibration validity
%        fRange           [fmin fmax] analysis band
%        validatedBands   (n x 2) experimentally validated bands [Hz]
%        passivityTol     (0.05)  velocityMismatchMax (0.10)
%        anechoicRmax     max |R_termination| for which tau is reported
%                         as valid with the anechoic assumption (0.1)
%
%   OUTPUT res: see docs/theory.md. Main fields
%     .waves     A1,B1 (upstream), A2,B2 (downstream) referred to x = 0
%     .boundary  pL,uL,pR,uR at the sample faces (if geometry complete)
%     .R         pressure reflection coefficient at the front face
%     .tau       pressure transmission coefficient (rear-face transmitted /
%                front-face incident), valid only for anechoic termination
%     .Rterm     reflection coefficient of the downstream termination,
%                referred to the rear face
%     .thin      thin-element transfer impedance Zt = (pL - pR)/u and
%                velocity mismatch
%     .power     |R|^2, |tau|^2, alpha = 1 - |R|^2 - |tau|^2
%     .valid     per-frequency logical masks and warnings

arguments
    f (:,1) double
    H (:,4) double
    geom struct
    env struct
    opts struct = struct()
end
o = fillDefaults(opts);
Nf = numel(f);
if size(H, 1) ~= Nf
    error('tim:analysis:size', 'H must have one row per frequency.');
end

air = tim.acoustics.airProperties(env);
[k, Zc] = tim.acoustics.wavenumber(f, air, geom.diameter, o.lossModel);

res = struct();
res.f = f; res.air = air; res.k = k; res.Zc = Zc;
res.convention = 'exp(+j*omega*t); forward wave A*exp(-j*k*x); u positive towards +x (downstream)';
res.options = o;
res.warnings = {};

% ---------- geometry status ---------------------------------------------
xm = geom.micPositions(:).';
positionsKnown = numel(xm) == 4 && all(isfinite(xm));
facesKnown = positionsKnown && isfinite(geom.xFront) && isfinite(geom.xRear);
if positionsKnown
    sUp = abs(xm(2) - xm(1));  sDn = abs(xm(4) - xm(3));
else
    sUp = geom.spacingUp;  sDn = geom.spacingDown;
    xm = [0, sUp, 0, sDn];   % pair-local coordinates (each pair separately)
    res.warnings{end+1} = ['Microphone axial positions not supplied: only pair-local ' ...
        'quantities are computed (upstream reflection at M2 plane, downstream reflection at M3 plane). ' ...
        'Boundary-plane quantities are DISABLED.'];
end
if facesKnown
    if ~(max(xm(1:2)) <= geom.xFront && geom.xFront <= geom.xRear && geom.xRear <= min(xm(3:4)))
        error('tim:analysis:geometry', ...
            'Geometry must satisfy x1,x2 <= xFront <= xRear <= x3,x4 (got x=[%s], faces %.4g, %.4g).', ...
            num2str(xm), geom.xFront, geom.xRear);
    end
elseif positionsKnown
    res.warnings{end+1} = 'Sample face positions not supplied: boundary-plane quantities are DISABLED.';
end
res.geometry = struct('positionsKnown', positionsKnown, 'facesKnown', facesKnown, ...
    'x', xm, 'spacingUp', sUp, 'spacingDown', sDn);

% ---------- wave decomposition -----------------------------------------
[A1, B1, cond1] = tim.acoustics.decomposeWaves(H(:,1), H(:,2), xm(1), xm(2), k);
[A2, B2, cond2] = tim.acoustics.decomposeWaves(H(:,3), H(:,4), xm(3), xm(4), k);
res.waves = struct('A1', A1, 'B1', B1, 'A2', A2, 'B2', B2, 'cond1', cond1, 'cond2', cond2);

% Pair-local reflection coefficients (always available):
%   upstream: R at the plane of M2;  downstream: R at the plane of M3.
res.local.R_up_atM2 = (B1 .* exp(1j*k*xm(2))) ./ (A1 .* exp(-1j*k*xm(2)));
res.local.R_dn_atM3 = (B2 .* exp(1j*k*xm(3))) ./ (A2 .* exp(-1j*k*xm(3)));

% ---------- boundary quantities ----------------------------------------
nanv = nan(Nf, 1) + 1j*nan(Nf, 1);
res.boundary = struct('available', facesKnown, 'pL', nanv, 'uL', nanv, 'pR', nanv, 'uR', nanv);
res.R = nanv; res.tau = nanv; res.Rterm = nanv;
res.thin = struct('Zt', nanv, 'Zt_norm', nanv, 'u', nanv, 'velocityMismatch', nan(Nf,1), 'TL_dB', nan(Nf,1), ...
    'velocityRef', o.velocityRef, 'assumption', ...
    'Lumped element of negligible thickness; normal particle velocity approximately continuous across the element.');
res.power = struct('Rpow', nan(Nf,1), 'tauPow', nan(Nf,1), 'alpha', nan(Nf,1), 'TL_tau_dB', nan(Nf,1));

if facesKnown
    [pL, uL] = tim.acoustics.fieldAt(A1, B1, geom.xFront, k, Zc);
    [pR, uR] = tim.acoustics.fieldAt(A2, B2, geom.xRear, k, Zc);
    res.boundary = struct('available', true, 'pL', pL, 'uL', uL, 'pR', pR, 'uR', uR, ...
        'xFront', geom.xFront, 'xRear', geom.xRear, 'thickness', geom.xRear - geom.xFront);

    incL = A1 .* exp(-1j*k*geom.xFront);   % incident wave at front face
    refL = B1 .* exp(+1j*k*geom.xFront);   % reflected wave at front face
    trR  = A2 .* exp(-1j*k*geom.xRear);    % transmitted (forward) wave at rear face
    retR = B2 .* exp(+1j*k*geom.xRear);    % wave returning from termination at rear face
    res.R = refL ./ incL;
    res.tau = trR ./ incL;
    res.Rterm = retR ./ trR;

    switch o.velocityRef
        case 'mean',       ut = (uL + uR) / 2;
        case 'upstream',   ut = uL;
        case 'downstream', ut = uR;
    end
    res.thin.u = ut;
    res.thin.Zt = (pL - pR) ./ ut;
    res.thin.Zt_norm = res.thin.Zt ./ Zc;
    res.thin.velocityMismatch = abs(uL - uR) ./ max(abs(uL), abs(uR));
    % Transmission loss of the thin element derived from Zt:
    %   T = [1 Zt; 0 1]  ->  tau = 2 / (2 + Zt/Zc)  ->  TL = 20 log10 |1 + Zt/(2 Zc)|
    % (equal cross-sections, anechoic termination; independent of the actual
    % termination because Zt itself is termination independent)
    res.thin.TL_dB = 20 * log10(abs(1 + res.thin.Zt ./ (2 * Zc)));

    res.power.Rpow = abs(res.R).^2;
    res.power.tauPow = abs(res.tau).^2;   % same medium and area on both sides
    res.power.alpha = 1 - res.power.Rpow - res.power.tauPow;
    % TL directly from the measured pressure transmission coefficient
    % (valid only for an anechoic termination, see validTau)
    res.power.TL_tau_dB = -20 * log10(abs(res.tau));
    res.power.note = ['alpha = 1 - |R|^2 - |tau|^2 is the dissipated fraction only for an ' ...
        'anechoic termination (Rterm ~ 0); otherwise use transfer-matrix based quantities.'];
end

% ---------- validity ----------------------------------------------------
res.valid = tim.acoustics.validityMasks(res, geom, o);
end

function o = fillDefaults(o)
d = struct('lossModel', 'iso10534', 'velocityRef', 'mean', 'condMax', 40, ...
    'phaseUncertainty_rad', 0.002, 'maxPhaseSensitivity', 0.05, 'quality', [], ...
    'coherenceMin', 0.98, 'snrMin_dB', 20, 'calValid', [], 'fRange', [], ...
    'validatedBands', zeros(0, 2), 'passivityTol', 0.05, 'velocityMismatchMax', 0.10, ...
    'anechoicRmax', 0.1, 'lowerFraction', 0.01, 'upperFraction', 0.40);
fn = fieldnames(d);
for i = 1:numel(fn)
    if ~isfield(o, fn{i}) || (isempty(o.(fn{i})) && ~isempty(d.(fn{i})))
        o.(fn{i}) = d.(fn{i});
    end
end
end
