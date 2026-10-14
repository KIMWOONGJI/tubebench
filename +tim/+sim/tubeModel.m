function out = tubeModel(f, geom, env, sample, termination, opts)
%TUBEMODEL Analytical four-microphone tube response (synthetic ground truth).
%
%   out = tim.sim.tubeModel(f, geom, env, sample, termination)
%
%   Builds the exact 1-D field in the tube for a sample described by its
%   transfer matrix and a downstream termination described by its pressure
%   reflection coefficient. Used to verify the analysis against known
%   solutions (Test F) and to drive the simulated acquisition.
%
%   sample.type:
%     'thin'      series impedance Zt [Pa*s/m]: T = [1 Zt; 0 1]
%                 (sample.Zt: scalar or function handle @(f); or sample.R
%                 [Pa*s/m] and sample.m [kg/m^2]: Zt = R + j*omega*m)
%     'air'       empty tube section of length xRear-xFront:
%                 T = [cos kd, j Zc sin kd; j sin kd / Zc, cos kd]
%     'porous'    rigid-frame equivalent fluid (Miki 1990), flow
%                 resistivity sample.sigma [Pa*s/m^2], length xRear-xFront
%     'matrix'    sample.T = @(f) -> [Nf x 4] (T11 T12 T21 T22)
%   termination.R : complex scalar or @(f) reflection coefficient referred to
%                   the plane termination.x (0 = anechoic, 1 = rigid)
%   termination.x : axial position of the termination plane [m], >= xRear.
%                   The tube ENDS there: a microphone at x > termination.x
%                   sits behind the termination (e.g. behind a rigid plug)
%                   and receives NO sound, p = 0 (out.behindTermination).
%                   The standing wave is not continued past the plug.
%   termination.model : (optional) 'unflangedOpenEnd' replaces R by the open
%                   end of the tube at termination.x (WO-005, an estimate:
%                   |R| = exp(-(k a)^2 / 2), phase of a reflection at
%                   0.6133 a beyond the end, a = D/2). Struct fields only,
%                   so the termination stays JSON-encodable in the metadata.
%   opts.lossModel : passed to wavenumber ('kirchhoff' default; use the
%                    analysis setting cfg.analysis.lossModel)
%   opts.incident  : complex amplitude of the incident wave at xFront (1)
%
%   NOTE: the field is built with the SAME air properties and wavenumber as
%   the analysis, so a round trip (Test F) verifies the decomposition
%   algebra only, not the physical tube model.
%
%   out.p  (Nf x 4) pressures at geom.micPositions
%   out.T  (Nf x 4) true transfer matrix,  out.R, out.tau, out.Rterm (true)
%   out.pL,uL,pR,uR  true boundary values

arguments
    f (:,1) double
    geom struct
    env struct
    sample struct
    termination struct
    opts.lossModel char = 'kirchhoff'
    opts.incident double = 1
end
air = tim.acoustics.airProperties(env);
[k, Zc] = tim.acoustics.wavenumber(f, air, geom.diameter, opts.lossModel);
xF = geom.xFront; xR = geom.xRear; d = xR - xF;
if termination.x < xR
    error('tim:sim:termination', 'Termination plane x = %.4g m lies upstream of the rear face xRear = %.4g m.', ...
        termination.x, xR);
end

switch sample.type
    case 'thin'
        if isfield(sample, 'Zt') && ~isempty(sample.Zt)
            Zt = evalParam(sample.Zt, f);
        else
            % JSON-friendly form: resistance R [Pa s/m] + mass reactance j*omega*m [kg/m^2]
            Zt = sample.R + 1j * 2 * pi * f(:) * sample.m;
        end
        T = [ones(size(f)), Zt, zeros(size(f)), ones(size(f))];
    case 'air'
        kd = k * d;
        T = [cos(kd), 1j * Zc .* sin(kd), 1j * sin(kd) ./ Zc, cos(kd)];
    case 'porous'
        [kp, Zp] = mikiModel(f, air, sample.sigma);
        kd = kp * d;
        T = [cos(kd), 1j * Zp .* sin(kd), 1j * sin(kd) ./ Zp, cos(kd)];
    case 'matrix'
        T = sample.T(f);
    otherwise
        error('tim:sim:sample', 'Unknown sample type "%s".', sample.type);
end

% Downstream: p = C e^{-jk(x-xR)} + D e^{jk(x-xR)}, with D/C fixed by termination
if isfield(termination, 'model') && ~isempty(termination.model)
    switch termination.model
        case 'unflangedOpenEnd'
            % open pipe end without flange (low-frequency estimate, Levine and
            % Schwinger): |R| falls as the end radiates, end correction 0.6133 a
            a = geom.diameter / 2;
            Rt = -exp(-(real(k) * a).^2 / 2) .* exp(-2j * k * 0.6133 * a);
        otherwise
            error('tim:sim:termination', 'Unknown termination model "%s".', termination.model);
    end
else
    Rt = evalParam(termination.R, f);
end
Lt = termination.x - xR;                      % distance rear face -> termination
DoverC = Rt .* exp(-2j * k * Lt);             % reflection referred to the rear face
% Choose C = 1 first, then scale everything so incident amplitude at xF = opts.incident
pR = 1 + DoverC;  uR = (1 - DoverC) ./ Zc;
pL = T(:,1) .* pR + T(:,2) .* uR;
uL = T(:,3) .* pR + T(:,4) .* uR;
incL = (pL + Zc .* uL) / 2;                   % forward wave at xF
refL = (pL - Zc .* uL) / 2;                   % backward wave at xF
s = opts.incident ./ incL;
pR = pR .* s; uR = uR .* s; pL = pL .* s; uL = uL .* s; C = s; D = DoverC .* s;
incL = incL .* s; refL = refL .* s;

% Field at microphones
xm = geom.micPositions(:).';
p = zeros(numel(f), 4);
behind = false(1, 4);
for m = 1:4
    if xm(m) > termination.x
        behind(m) = true;              % behind the termination (rigid plug): no sound, p = 0
    elseif xm(m) <= xF
        p(:, m) = incL .* exp(-1j * k * (xm(m) - xF)) + refL .* exp(1j * k * (xm(m) - xF));
    elseif xm(m) >= xR
        p(:, m) = C .* exp(-1j * k * (xm(m) - xR)) + D .* exp(1j * k * (xm(m) - xR));
    else
        error('tim:sim:geometry', 'Microphone %d lies inside the sample.', m);
    end
end
out = struct('f', f, 'p', p, 'T', T, 'pL', pL, 'uL', uL, 'pR', pR, 'uR', uR, ...
    'R', refL ./ incL, 'tau', C ./ incL, 'Rterm', D ./ C, 'k', k, 'Zc', Zc, 'air', air, ...
    'behindTermination', behind);
if strcmp(sample.type, 'thin')
    out.Zt = Zt;
end
end

function v = evalParam(p, f)
if isa(p, 'function_handle')
    v = p(f);
else
    v = p * ones(size(f));
end
v = v(:);
end

function [kp, Zp] = mikiModel(f, air, sigma)
% Miki (1990) modification of the Delany-Bazley model, exp(+j*omega*t):
%   X  = f/sigma
%   Zp = rho*c*(1 + 0.0699 X^-0.632 - j 0.1071 X^-0.632)
%   kp = (omega/c)*(1 + 0.1093 X^-0.618 - j 0.1597 X^-0.618)
% Miki's form is positive-real (causal); the original Delany-Bazley model
% is not, which produced a wrapped acausal FIR tail in the simulated rig.
X = f / sigma;
Zp = air.Z0 * (1 + 0.0699 * X.^-0.632 - 1j * 0.1071 * X.^-0.632);
kp = (2*pi*f / air.c) .* (1 + 0.1093 * X.^-0.618 - 1j * 0.1597 * X.^-0.618);
end
