function r = testDE_reference(res, kind, opts)
%TESTDE_REFERENCE Compare a processed measurement with a reference case.
%
%   r = tim.val.testDE_reference(res, 'rigid', struct('L', 0.0))   % Test D
%   r = tim.val.testDE_reference(res, 'empty', struct())          % Test E
%
%   All expectations use the wavenumber of the analysis (res.analysis.k,
%   cfg.analysis.lossModel), i.e. the same tube model as the results.
%
%   'rigid' (Test D): rigid termination plug whose surface is at distance
%       opts.L [m] downstream of the reference plane xFront (L = 0 if the
%       plug face is placed exactly at xFront). Expected
%           R = exp(-2jkL) * R_wall,  |R_wall| ~ 1 (minus small losses)
%       The comparison uses the configured tube-loss model; the residual
%       |R| deficit at the plug is reported (should be < ~0.02-0.05 for a
%       well sealed plug; ISO 10534-2 notes |R| slightly below 1).
%       R needs only the UPSTREAM pair: frequency lines are selected with
%       the upstream-only masks (res.analysis.valid.upstream: geometry of
%       the pair M1-M2, coherence/SNR of ports M1-M2, calibration). M3/M4
%       may sit behind the plug and record only background noise. The
%       passivity screen is NOT applied (an over-unity |R| must count, not
%       be dropped); such lines are reported as nonPassiveBins. The
%       reference channel must be at M1 or M2 when M3/M4 are behind the plug
%       (r.warning when the reference microphone lies downstream of the plug
%       face xFront + L; no warning with the plug downstream of M4).
%       (Results computed before the upstream masks existed fall back to
%       res.analysis.valid.valid.)
%   'empty' (Test E, empty-tube check): the empty specimen section is
%       mounted (no specimen; lab: 75 mm), so the tube is continuous and the
%       "specimen" is the air column d = xRear - xFront. Independently of
%       the termination:
%           tau = exp(-jkd)                 (forward wave propagates freely)
%           R   = Rterm * exp(-2jkd)        (continuity of the field across
%                                            the section; R = 0 only if the
%                                            termination is anechoic)
%       The second relation checks the consistency of the upstream and the
%       downstream decomposition (positions, spacing, channel phase). With
%       A2 = A1, B2 = B1 both checks depend only on the microphone
%       coordinates (s1, s2, x3 - x2 = L1 + d + L2) and the calibration,
%       not on how L1 / d / L2 are split. For d = 75 mm, D = 29 mm, 20 °C
%       (lossModel 'kirchhoff', k = w/c + (1-j)k''): |tau| 0.9983 / 0.9952 /
%       0.9898 and phase -9.53 / -78.93 / -354.52 deg at 120 Hz / 1 kHz /
%       4.5 kHz, TL 0.015 / 0.042 / 0.089 dB ('iso10534', Re k = w/c:
%       phase -9.44 / -78.65 / -353.93 deg). tim.app.runCalibration performs this
%       check automatically (cal.meta.emptyCheck).
%       Reported: |tau| error, tau phase error, R-consistency error, TL.
%       Evaluated on the frequency lines that meet the geometry and the
%       quality criteria of all four microphones (res.analysis.valid.geometryOK
%       & qualityOK, which includes the analysis band and the calibration),
%       WITHOUT the passivity screen (|tau| > 1 errors must count, not be
%       dropped).
%   The pass criteria are therefore NOT evaluated on the 'valid' mask of
%   res (res.analysis.valid.valid also applies the passivity screen):
%   Test D uses the upstream-pair masks, Test E the four-microphone
%   geometry and quality masks, both without the passivity screen and both
%   only where the specimen faces are known (res.analysis.boundary.available).
%   r.validBins is the number of frequency lines evaluated.

a = res.analysis;
k = a.k;
switch kind
    case 'rigid'
        L = opts.L;
        if isfield(a.valid, 'upstream')
            up = a.valid.upstream;
            v = up.geometryOK & up.qualityOK & a.boundary.available;
            nonPassive = up.flags.nonPassive;
        else                                   % result computed before the upstream masks existed
            v = a.valid.valid & a.boundary.available;
            nonPassive = a.valid.flags.nonPassive;
        end
        Rexp = exp(-2j * k * L);
        dR = a.R ./ Rexp;
        r = struct('name', 'Test D – rigid termination', 'validBins', nnz(v), ...
            'absR_median', median(abs(a.R(v))), 'absR_min', min(abs(a.R(v))), ...
            'phaseError_deg_rms', rms(rad2deg(angle(dR(v)))), ...
            'magDeficit_median', median(1 - abs(dR(v))), ...
            'nonPassiveBins', nnz(nonPassive & v), 'warning', '');
        % warn only when the reference microphone really sits behind the plug
        % face (xFront + L): with the plug as the termination downstream of M4
        % a reference at M3/M4 is fine (review analysis-4)
        refPos = referencePosition(res);
        if ~isempty(refPos) && refPos > 2 && behindPlug(a, refPos, L)
            r.warning = sprintf(['Reference channel at M%d: with M3/M4 behind the plug the upstream ' ...
                'coherence is lost – use a reference channel at M1 or M2 for Test D.'], refPos);
        end
        r.passed = nnz(v) > 0 && r.magDeficit_median < 0.05 && r.magDeficit_median > -0.02 && r.phaseError_deg_rms < 3;
        r.criteria = ['|R| deficit after removing the propagation: -0.02 to 0.05 (median); phase error < 3° rms ' ...
            '(frequency lines of the upstream pair M1-M2, no passivity screen)'];
    case 'empty'
        % frequency lines: geometry and quality criteria met - WITHOUT the passivity
        % screen, which would silently drop over-unity |tau| errors (one-sided check)
        v = a.valid.geometryOK & a.valid.qualityOK & a.boundary.available;
        d = a.boundary.thickness;
        texp = exp(-1j * k * d);
        dt = a.tau ./ texp;
        Rexp = a.Rterm .* exp(-2j * k * d);
        TLexp = -20 * log10(abs(texp));
        r = struct('name', 'Test E – empty specimen section', 'validBins', nnz(v), 'gap_m', d, ...
            'tauMagError_median', median(abs(abs(dt(v)) - 1)), ...
            'tauPhaseError_deg_rms', rms(rad2deg(angle(dt(v)))), ...
            'RconsistencyError_median', median(abs(a.R(v) - Rexp(v))), ...
            'absR_median', median(abs(a.R(v))), 'absRterm_median', median(abs(a.Rterm(v))), ...
            'TLtau_dB_median', median(a.power.TL_tau_dB(v)), 'TLexpected_dB_median', median(TLexp(v)), ...
            'nonPassiveBins', nnz(a.valid.flags.nonPassive & v));
        r.passed = nnz(v) > 0 && r.tauMagError_median < 0.02 && r.tauPhaseError_deg_rms < 2 && ...
            r.RconsistencyError_median < 0.02;
        r.criteria = ['||τ/τ_exp| - 1| < 0.02, τ phase error < 2° rms, |R - Rterm e^(-2jkd)| < 0.02 ' ...
            '(medians over the frequency lines that meet the geometry and quality criteria, no passivity screen)'];
    otherwise
        error('tim:val:kind', 'kind must be rigid or empty.');
end
end

function b = behindPlug(a, pos, L)
% microphone at tube position pos downstream of the plug face xFront + L;
% true (warn) when the coordinates are unknown
b = true;
if isfield(a, 'geometry') && isfield(a.geometry, 'positionsKnown') && a.geometry.positionsKnown && ...
        isfield(a.boundary, 'xFront') && isfinite(a.boundary.xFront)
    b = a.geometry.x(pos) > a.boundary.xFront + L;
end
end

function p = referencePosition(res)
% tube position (1..4) of the reference channel, [] if unknown
p = [];
if isfield(res, 'channelOfPosition') && isfield(res, 'spectra') && isfield(res.spectra, 'refChannel')
    p = find(res.channelOfPosition == res.spectra.refChannel, 1);
end
end
