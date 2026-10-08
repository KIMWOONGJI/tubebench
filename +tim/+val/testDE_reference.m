function r = testDE_reference(res, kind, opts)
%TESTDE_REFERENCE Compare a processed measurement with a reference case.
%
%   r = tim.val.testDE_reference(res, 'rigid', struct('L', 0.0))   % Test D
%   r = tim.val.testDE_reference(res, 'empty', struct())          % Test E
%
%   'rigid' (Test D): rigid termination plug whose surface is at distance
%       opts.L [m] downstream of the reference plane xFront (L = 0 if the
%       plug face is placed exactly at xFront). Expected
%           R = exp(-2jkL) * R_wall,  |R_wall| ~ 1 (minus small losses)
%       The comparison uses the configured tube-loss model; the residual
%       |R| deficit at the plug is reported (should be < ~0.02-0.05 for a
%       well sealed plug; ISO 10534-2 notes |R| slightly below 1).
%   'empty' (Test E): the EMPTY specimen section is mounted (no specimen;
%       lab: 75 mm), so the tube is continuous and the "sample" is the air
%       column d = xRear - xFront. Independently of the termination:
%           tau = exp(-jkd)                 (forward wave propagates freely)
%           R   = Rterm * exp(-2jkd)        (continuity of the field across
%                                            the section; R = 0 only if the
%                                            termination is anechoic)
%       The second relation checks the consistency of the upstream and the
%       downstream decomposition (positions, spacing, channel phase). With
%       A2 = A1, B2 = B1 both checks depend only on the microphone
%       coordinates (s1, s2, x3 - x2 = L1 + d + L2) and the calibration,
%       not on how L1 / d / L2 are split. For d = 75 mm: |tau| 0.998 /
%       0.995 / 0.990 and phase -9.4 / -78.7 / -353.9 deg at 120 Hz / 1 kHz
%       / 4.5 kHz, TL ~ 0.01-0.09 dB. tim.app.runCalibration performs this
%       check automatically (cal.meta.emptyCheck).
%       Reported: |tau| error, tau phase error, R-consistency error, TL.
%   Pass criteria are applied only in the VALID band of res.

a = res.analysis; v = a.valid.valid & a.boundary.available;
k = a.k;
switch kind
    case 'rigid'
        L = opts.L;
        Rexp = exp(-2j * k * L);
        dR = a.R ./ Rexp;
        r = struct('name', 'Test D - rigid termination', 'validBins', nnz(v), ...
            'absR_median', median(abs(a.R(v))), 'absR_min', min(abs(a.R(v))), ...
            'phaseError_deg_rms', rms(rad2deg(angle(dR(v)))), ...
            'magDeficit_median', median(1 - abs(dR(v))));
        r.passed = nnz(v) > 0 && r.magDeficit_median < 0.05 && r.magDeficit_median > -0.02 && r.phaseError_deg_rms < 3;
        r.criteria = '|R| deficit after removing propagation: -0.02 .. 0.05 (median); phase error < 3 deg rms';
    case 'empty'
        d = a.boundary.thickness;
        texp = exp(-1j * k * d);
        dt = a.tau ./ texp;
        Rexp = a.Rterm .* exp(-2j * k * d);
        TLexp = -20 * log10(abs(texp));
        r = struct('name', 'Test E - empty specimen section', 'validBins', nnz(v), 'gap_m', d, ...
            'tauMagError_median', median(abs(abs(dt(v)) - 1)), ...
            'tauPhaseError_deg_rms', rms(rad2deg(angle(dt(v)))), ...
            'RconsistencyError_median', median(abs(a.R(v) - Rexp(v))), ...
            'absR_median', median(abs(a.R(v))), 'absRterm_median', median(abs(a.Rterm(v))), ...
            'TLtau_dB_median', median(a.power.TL_tau_dB(v)), 'TLexpected_dB_median', median(TLexp(v)));
        r.passed = nnz(v) > 0 && r.tauMagError_median < 0.02 && r.tauPhaseError_deg_rms < 2 && ...
            r.RconsistencyError_median < 0.02;
        r.criteria = ['||tau|-1| < 0.02, tau phase error < 2 deg rms, |R - Rterm e^{-2jkd}| < 0.02 ' ...
            '(medians over valid bins)'];
    otherwise
        error('tim:val:kind', 'kind must be rigid or empty.');
end
end
