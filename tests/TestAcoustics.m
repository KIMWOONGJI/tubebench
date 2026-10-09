classdef TestAcoustics < matlab.unittest.TestCase
    %TESTACOUSTICS Wave decomposition and sample quantities vs analytic solutions.
    %   Test D (rigid termination), Test E (empty tube), Test F (synthetic
    %   waves incl. mismatch + noise). Tolerances are derived from the model:
    %   exact arithmetic -> 1e-9 (round-off with cond <= 40 and lossy
    %   exponentials); noisy cases -> analytic error bound (see each test).

    properties
        env = struct('temperature_C', 20, 'pressure_Pa', 101325, 'c_override', [], 'rho_override', [])
        geom
        f = (100:5:5000).'
    end

    methods (TestMethodSetup)
        function setup(tc)
            tc.geom = struct('diameter', 0.029, 'micPositions', [-0.150 -0.121 0.071 0.100], ...
                'spacingUp', 0.029, 'spacingDown', 0.029, 'xFront', 0, 'xRear', 0.010);
        end
    end

    methods (Test)
        function airAndLimits(tc)
            air = tim.acoustics.airProperties(tc.env);
            tc.verifyEqual(air.c, 343.2 * sqrt(293.15 / 293), 'RelTol', 1e-12);
            lim = tim.acoustics.frequencyLimits(0.029, 0.029, air);
            % values quoted in the project brief (approximately, 20 degC)
            tc.verifyEqual(lim.lowerSpacing, 118.4, 'AbsTol', 0.5);
            tc.verifyEqual(lim.upperSpacing, 4735, 'AbsTol', 5);
            tc.verifyEqual(lim.singular, 5919, 'AbsTol', 5);
            tc.verifyEqual(lim.cutOn11, 6937, 'AbsTol', 10);
            tc.verifyEqual(lim.fUpper, lim.upperSpacing, 'RelTol', 1e-12);
        end

        function decompositionExact(tc)
            air = tim.acoustics.airProperties(tc.env);
            k = tim.acoustics.wavenumber(tc.f, air, 0.029, 'iso10534');
            rng(3);
            A = randn(size(tc.f)) + 1j * randn(size(tc.f));
            B = randn(size(tc.f)) + 1j * randn(size(tc.f));
            xa = -0.2; xb = -0.171;
            pa = A .* exp(-1j*k*xa) + B .* exp(1j*k*xa);
            pb = A .* exp(-1j*k*xb) + B .* exp(1j*k*xb);
            [A2, B2, cnd] = tim.acoustics.decomposeWaves(pa, pb, xa, xb, k);
            tc.verifyEqual(A2, A, 'AbsTol', 1e-10 * max(abs(A)) * max(cnd));
            tc.verifyEqual(B2, B, 'AbsTol', 1e-10 * max(abs(B)) * max(cnd));
            % lossless condition number: sqrt((1+|cos ks|)/(1-|cos ks|))
            %   = max(|cot(ks/2)|, |tan(ks/2)|)  (minimum 1 at ks = pi/2)
            k0 = real(k); h = k0 * 0.029 / 2; sel = tc.f < 5000;
            tc.verifyEqual(cnd(sel), max(abs(cot(h(sel))), abs(tan(h(sel)))), 'RelTol', 2e-2);
        end

        function thinElementRecovery(tc)
            % Test F (noise-free): thin resistive/reactive element, anechoic end
            Zt = @(f) 400 + 1j * 2 * pi * f * 0.02;    % Pa*s/m, mass-like reactance
            geom = tc.geom; geom.xRear = 0;              % zero thickness
            s = struct('type', 'thin', 'Zt', Zt);
            t = struct('R', 0, 'x', 0.6);
            m = tim.sim.tubeModel(tc.f, geom, tc.env, s, t);
            r = tim.acoustics.analyzeFourMic(tc.f, m.p ./ m.p(:,1), geom, tc.env, struct());
            tc.verifyEqual(r.thin.Zt, Zt(tc.f), 'RelTol', 1e-9);
            tc.verifyEqual(r.R, m.R, 'AbsTol', 1e-10);
            tc.verifyEqual(r.tau, m.tau, 'AbsTol', 1e-10);
            tc.verifyLessThan(max(r.thin.velocityMismatch), 1e-9);   % continuity holds exactly
            % energy: passive element -> alpha >= 0
            tc.verifyGreaterThanOrEqual(min(r.power.alpha), -1e-9);
            % TL from Zt (thin-element formula) == TL from the true tau (anechoic end)
            tc.verifyEqual(r.thin.TL_dB, -20 * log10(abs(m.tau)), 'AbsTol', 1e-9);
            tc.verifyEqual(r.power.TL_tau_dB, -20 * log10(abs(m.tau)), 'AbsTol', 1e-9);
            % JSON-friendly R + j*omega*m form gives the same field
            s2 = struct('type', 'thin', 'R', 400, 'm', 0.02);
            m2 = tim.sim.tubeModel(tc.f, geom, tc.env, s2, t);
            tc.verifyEqual(m2.p, m.p, 'RelTol', 1e-12);
        end

        function porousLayerTransferMatrix(tc)
            % Thick porous layer: one-load (symmetric) and two-load methods
            s = struct('type', 'porous', 'sigma', 1.5e4);
            g = tc.geom; g.xRear = 0.025;
            mA = tim.sim.tubeModel(tc.f, g, tc.env, s, struct('R', 0, 'x', 0.6));
            mB = tim.sim.tubeModel(tc.f, g, tc.env, s, struct('R', 0.95, 'x', 0.45));
            rA = tim.acoustics.analyzeFourMic(tc.f, mA.p, g, tc.env, struct());
            rB = tim.acoustics.analyzeFourMic(tc.f, mB.p, g, tc.env, struct());
            T2 = tim.acoustics.transferMatrix('twoLoad', rA, rB);
            T1 = tim.acoustics.transferMatrix('oneLoadSymmetric', rA);
            for e = {'T11', 'T12', 'T21', 'T22'}
                tc.verifyEqual(T2.(e{1}), mA.T(:, find(strcmp(e{1}, {'T11','T12','T21','T22'}))), 'RelTol', 1e-8);
                tc.verifyEqual(T1.(e{1}), mA.T(:, find(strcmp(e{1}, {'T11','T12','T21','T22'}))), 'RelTol', 1e-8);
            end
            tc.verifyLessThan(max(T2.reciprocityError), 1e-8);
            % transmission for anechoic end from T equals direct tau
            tc.verifyEqual(T2.tau_anechoic, mA.tau, 'AbsTol', 1e-9);
            tc.verifyEqual(T2.R_anechoic, mA.R, 'AbsTol', 1e-9);
            % thin-element model must FLAG velocity mismatch for a thick layer
            tc.verifyGreaterThan(median(rA.thin.velocityMismatch), 0.10);
        end

        function emptySection75mm(tc)
            % lab tube: EMPTY 75 mm specimen section mounted (calibration / Test E).
            % tau = exp(-j k d); the thin-element model gives a spurious reactance
            % Zt/Zc = 2j tan(kd/2) and is rejected by the velocity-mismatch mask.
            g = struct('diameter', 0.029, 'micPositions', [-0.070 -0.041 0.116 0.145], ...
                'spacingUp', 0.029, 'spacingDown', 0.029, 'xFront', 0, 'xRear', 0.075);
            air = tim.acoustics.airProperties(tc.env);
            [k, Zc] = tim.acoustics.wavenumber(tc.f, air, 0.029);     % default 'kirchhoff'
            m = tim.sim.tubeModel(tc.f, g, tc.env, struct('type', 'air'), struct('R', 0, 'x', 0.6));
            r = tim.acoustics.analyzeFourMic(tc.f, m.p, g, tc.env, struct('calValid', true(size(tc.f))));
            tc.verifyEqual(r.tau, exp(-1j * k * 0.075), 'AbsTol', 1e-10);
            % 1 kHz, 20 degC: k0 = 2 pi 1000/343.288 = 18.3030 /m, k'' = Cw sqrt(f)/(c D)
            % = 2.029e-2*31.623/(343.288*0.029) = 0.06445 /m (Kirchhoff):
            % |tau| = exp(-k'' d) = 0.99518, angle = -(k0 + k'') d = -78.93 deg
            % (ISO model, Re k = k0: 0.99539 / -78.65 deg)
            i = tc.f == 1000;
            tc.verifyEqual(abs(r.tau(i)), 0.99518, 'AbsTol', 2e-5);
            tc.verifyEqual(rad2deg(angle(r.tau(i))), -78.93, 'AbsTol', 0.01);
            band = tc.f >= 120 & tc.f <= 4500;
            tc.verifyLessThan(max(r.power.TL_tau_dB(band)), 0.09);   % 0.089 dB at 4.5 kHz
            % Zt = 2j Zc tan(kd/2); Zt_norm is normalised by the real rho c (air.Z0)
            tc.verifyEqual(r.thin.Zt_norm, 2j * tan(k * 0.075 / 2) .* Zc / air.Z0, 'RelTol', 1e-8);
            % velocity mismatch |uL - uR|/|uL| = |1 - e^{-jkd}| ~ |Re(k) d - 2 pi n|: the
            % thin model is rejected except where the air column is a whole
            % wavelength (T ~ identity, transparent): Re(k) d = 2 pi at 4.57 kHz,
            % mismatch <= 0.1 from 4.50 kHz (Kirchhoff Re k; 4.505 kHz with Re k = w/c)
            tc.verifyFalse(any(r.valid.validThinZt(band & tc.f < 4495)), 'thin-element model rejected for 75 mm');
            near = abs(real(k) * 0.075 - 2 * pi) < 0.1;
            tc.verifyTrue(all(near(r.valid.validThinZt)));
            % reflecting end: tau unchanged, R = Rterm exp(-2jkd)
            m2 = tim.sim.tubeModel(tc.f, g, tc.env, struct('type', 'air'), struct('R', 0.7, 'x', 0.4));
            r2 = tim.acoustics.analyzeFourMic(tc.f, m2.p, g, tc.env, struct());
            tc.verifyEqual(r2.tau, exp(-1j * k * 0.075), 'AbsTol', 1e-10);
            tc.verifyEqual(r2.R, r2.Rterm .* exp(-2j * k * 0.075), 'AbsTol', 1e-10);
        end

        function emptyTube(tc)
            % Test E: empty specimen section mounted -> air section between the faces
            g = tc.geom; g.xRear = 0.05;
            m = tim.sim.tubeModel(tc.f, g, tc.env, struct('type', 'air'), struct('R', 0, 'x', 0.6));
            r = tim.acoustics.analyzeFourMic(tc.f, m.p, g, tc.env, struct());
            air = tim.acoustics.airProperties(tc.env);
            k = tim.acoustics.wavenumber(tc.f, air, 0.029);      % same (default) model as the analysis
            tc.verifyEqual(r.R, zeros(size(tc.f)), 'AbsTol', 1e-10);         % anechoic end
            tc.verifyEqual(r.tau, exp(-1j * k * 0.05), 'AbsTol', 1e-10);   % pure propagation
            % reflecting end: tau unchanged, R = Rterm*exp(-2jkd) (continuity across the gap)
            m2 = tim.sim.tubeModel(tc.f, g, tc.env, struct('type', 'air'), struct('R', 0.7, 'x', 0.4));
            r2 = tim.acoustics.analyzeFourMic(tc.f, m2.p, g, tc.env, struct());
            tc.verifyEqual(r2.tau, exp(-1j * k * 0.05), 'AbsTol', 1e-10);
            tc.verifyEqual(r2.R, r2.Rterm .* exp(-2j * k * 0.05), 'AbsTol', 1e-10);
        end

        function rigidTermination(tc)
            % Test D: no sample (zero-length air), rigid end at distance L:
            % R at the reference plane = exp(-2jkL), |R| < 1 only by tube losses
            g = tc.geom; g.xRear = 0;
            L = 0.3;
            m = tim.sim.tubeModel(tc.f, g, tc.env, struct('type', 'air'), struct('R', 1, 'x', L));
            r = tim.acoustics.analyzeFourMic(tc.f, m.p, g, tc.env, struct());
            air = tim.acoustics.airProperties(tc.env);
            k = tim.acoustics.wavenumber(tc.f, air, 0.029);
            tc.verifyEqual(r.R, exp(-2j * k * L), 'AbsTol', 1e-8);
            tc.verifyLessThan(max(abs(r.R)), 1);
            % lossless model: |R| = 1 exactly
            m0 = tim.sim.tubeModel(tc.f, g, tc.env, struct('type', 'air'), struct('R', 1, 'x', L), 'lossModel', 'none');
            r0 = tim.acoustics.analyzeFourMic(tc.f, m0.p, g, tc.env, struct('lossModel', 'none'));
            tc.verifyEqual(abs(r0.R), ones(size(tc.f)), 'AbsTol', 1e-9);
        end

        function noisyRecoveryWithinBound(tc)
            % Test F with mismatch + noise: relative noise e on each pressure.
            % First-order bound: |dA|/|A| <= cond(M) * e * sqrt(2) (two inputs)
            % -> |dR| <= ~ 2*sqrt(2)*cond*e*(1+|R|). Monte-Carlo 95th percentile
            % must stay below this bound.
            s = struct('type', 'porous', 'sigma', 2e4);
            m = tim.sim.tubeModel(tc.f, tc.geom, tc.env, s, struct('R', 0, 'x', 0.6));
            e = 1e-3;
            rng(11);
            nMC = 50; err = zeros(numel(tc.f), nMC);
            for i = 1:nMC
                pn = m.p .* (1 + e * (randn(size(m.p)) + 1j * randn(size(m.p))) / sqrt(2));
                r = tim.acoustics.analyzeFourMic(tc.f, pn, tc.geom, tc.env, struct());
                err(:, i) = abs(r.R - m.R);
            end
            bound = 2 * sqrt(2) * r.waves.cond1 * e .* (1 + abs(m.R));
            tc.verifyLessThan(prctile(err, 95, 2) ./ bound, 1);
        end

        function incompleteGeometry(tc)
            g = tc.geom; g.micPositions = nan(1, 4); g.xFront = NaN; g.xRear = NaN;
            m = tim.sim.tubeModel(tc.f, tc.geom, tc.env, struct('type', 'air'), struct('R', 1, 'x', 0.3));
            r = tim.acoustics.analyzeFourMic(tc.f, m.p, g, tc.env, struct());
            tc.verifyFalse(r.boundary.available);
            tc.verifyTrue(all(isnan(r.R)));
            tc.verifyTrue(all(isfinite(r.local.R_up_atM2)));
            % pair-local result only depends on the spacing: reflection seen at
            % the M3 plane of a rigid end at x = 0.3 m is exp(-2jk(0.3 - 0.071))
            tc.verifyEqual(r.local.R_dn_atM3, exp(-2j * r.k * (0.3 - 0.071)), 'AbsTol', 1e-9);
            tc.verifyNotEmpty(r.warnings);
        end

        function geometryOrderChecked(tc)
            g = tc.geom; g.xFront = -0.13;   % front face upstream of M2 -> invalid
            m = tim.sim.tubeModel(tc.f, tc.geom, tc.env, struct('type', 'air'), struct('R', 0, 'x', 0.6));
            tc.verifyError(@() tim.acoustics.analyzeFourMic(tc.f, m.p, g, tc.env, struct()), 'tim:analysis:geometry');
        end

        function validityRequiresCalibration(tc)
            m = tim.sim.tubeModel(tc.f, tc.geom, tc.env, struct('type', 'air'), struct('R', 0, 'x', 0.6));
            r = tim.acoustics.analyzeFourMic(tc.f, m.p, tc.geom, tc.env, struct());
            tc.verifyFalse(any(r.valid.valid), 'Without complex calibration nothing may be valid.');
            r2 = tim.acoustics.analyzeFourMic(tc.f, m.p, tc.geom, tc.env, struct('calValid', true(size(tc.f))));
            ok = r2.valid.valid;
            tc.verifyTrue(any(ok));
            tc.verifyFalse(any(ok & (tc.f < r2.valid.limits.fLower | tc.f > r2.valid.limits.fUpper)));
            tc.verifyFalse(any(r2.valid.validated), 'No validated band configured -> nothing validated.');
        end

        function nonPassiveFlagged(tc)
            % upstream field with |R| = 1.3 at the front face (an "active"
            % sample, e.g. the signature of a gross calibration error)
            air = tim.acoustics.airProperties(tc.env);
            k = tim.acoustics.wavenumber(tc.f, air, 0.029);
            m = tim.sim.tubeModel(tc.f, tc.geom, tc.env, struct('type', 'air'), struct('R', 0, 'x', 0.6));
            p = m.p;
            x = tc.geom.micPositions;
            for i = 1:2
                p(:, i) = exp(-1j * k * x(i)) + 1.3 * exp(1j * k * x(i));
            end
            r = tim.acoustics.analyzeFourMic(tc.f, p, tc.geom, tc.env, struct('calValid', true(size(tc.f))));
            tc.verifyEqual(abs(r.R), 1.3 * ones(size(tc.f)), 'RelTol', 1e-9);
            tc.verifyTrue(all(r.valid.flags.nonPassive));
            tc.verifyFalse(any(r.valid.valid));
            % R uses the one-sided upstream test |R| <= 1 + passivityTol
            tc.verifyTrue(all(r.valid.upstream.flags.nonPassive));
            tc.verifyFalse(any(r.valid.validR));
        end

        function airDensityIdealGas(tc)
            % formula review acoustics-4: rho = p_s/(287.05 T) (dry air)
            air = tim.acoustics.airProperties(tc.env);
            tc.verifyEqual(air.rho, 101325 / (287.05 * 293.15), 'RelTol', 1e-12);
            tc.verifyEqual(air.rho, 1.2041, 'AbsTol', 1e-4);              % dry air, 20 degC, 101.325 kPa
            tc.verifyEqual(air.Z0, air.rho * air.c, 'RelTol', 1e-12);
            % thermodynamic consistency with c = 343.2 sqrt(T/293): rho c^2 = gamma p_s, gamma = 1.4
            tc.verifyEqual(air.rho * air.c^2 / 101325, 1.4, 'RelTol', 1e-3);
            tc.verifyEqual(air.mu, 1.813e-5, 'RelTol', 2e-3);              % Sutherland, 20 degC
            e = tc.env; e.temperature_C = 30; e.pressure_Pa = 95000;
            a2 = tim.acoustics.airProperties(e);
            tc.verifyEqual(a2.rho, air.rho * (95000 / 101325) * (293.15 / 303.15), 'RelTol', 1e-12);
            % overrides keep working
            e = tc.env; e.c_override = 340; e.rho_override = 1.2;
            a3 = tim.acoustics.airProperties(e);
            tc.verifyEqual([a3.c a3.rho a3.Z0], [340 1.2 408], 'AbsTol', 1e-12);
            tc.verifyEqual(a3.nu, a3.mu / 1.2, 'RelTol', 1e-12);
        end

        function kirchhoffMatchesExactTube(tc)
            % formula review acoustics-1/-3: the default loss model against an
            % INDEPENDENT propagation model, the exact visco-thermal circular-tube
            % solution (Zwikker-Kosten / Stinson, Bessel functions), same air.
            fq = [120 200 500 1000 2000 4000].';
            air = tim.acoustics.airProperties(tc.env);
            D = 0.029;
            [kT, ZcT] = TestAcoustics.exactTube(fq, air, D);
            [kK, ZcK] = tim.acoustics.wavenumber(fq, air, D, 'kirchhoff');
            k0 = 2 * pi * fq / air.c;
            % first-order wide-tube expansion: residual O((delta/a)^2), < 2e-4 of k0
            tc.verifyLessThan(max(abs(kK - kT) ./ k0), 2e-4);
            tc.verifyLessThan(max(abs(ZcK - ZcT) / air.Z0), 2e-4);
            % Re(k) - k0 = k'' (phase-velocity reduction equal to the attenuation)
            tc.verifyEqual(real(kK) - k0, -imag(kK), 'RelTol', 1e-12);
            % coefficient 2 sqrt(pi nu)(1 + (gamma-1)/sqrt(Pr)) = 2.03e-2 m s^-1/2
            tc.verifyEqual(-imag(kK) * air.c * D ./ sqrt(fq), 2.03e-2 * ones(size(fq)), 'RelTol', 5e-3);
            % thin element of low impedance at x = 0 in the exact tube, lab mics,
            % anechoic end: Zt within 0.1 % with 'kirchhoff'; the ISO model
            % (Re k = w/c) is off by 3-17 % for this Zt (|Zt|/rho c rising from
            % 0.05 to 0.21) - the reason for the default
            g = struct('diameter', D, 'micPositions', [-0.070 -0.041 0.116 0.145], ...
                'spacingUp', 0.029, 'spacingDown', 0.029, 'xFront', 0, 'xRear', 0);
            Zt = air.Z0 * (0.05 + 0.05j * fq / 1000);
            [p, R] = TestAcoustics.thinField(fq, kT, ZcT, Zt, g.micPositions);
            rK = tim.acoustics.analyzeFourMic(fq, p, g, tc.env, struct());
            rI = tim.acoustics.analyzeFourMic(fq, p, g, tc.env, struct('lossModel', 'iso10534'));
            tc.verifyLessThan(max(abs(rK.thin.Zt ./ Zt - 1)), 1e-3);
            tc.verifyGreaterThan(max(abs(rI.thin.Zt ./ Zt - 1)), 0.1);
            tc.verifyLessThan(max(abs(rK.R - R)), 1e-4);
            % review analysis-1: the documented bias (wavenumber.m, validateConfig)
            % for a frequency-independent |Zt|/rho c = 0.05: ~45 % with 'iso10534'
            % (absolute ~ k''(x3 - x2) rho c), still < 0.1 % with 'kirchhoff'
            Zt = air.Z0 * 0.05 * ones(size(fq));
            p = TestAcoustics.thinField(fq, kT, ZcT, Zt, g.micPositions);
            rK = tim.acoustics.analyzeFourMic(fq, p, g, tc.env, struct());
            rI = tim.acoustics.analyzeFourMic(fq, p, g, tc.env, struct('lossModel', 'iso10534'));
            eI = max(abs(rI.thin.Zt ./ Zt - 1));
            tc.verifyLessThan(max(abs(rK.thin.Zt ./ Zt - 1)), 1e-3);
            tc.verifyGreaterThan(eI, 0.35); tc.verifyLessThan(eI, 0.55);
        end

        function nearSingularityPerPair(tc)
            % formula review acoustics-2 / calval-3: the proximity test to
            % k s = n pi is applied per pair. Unequal spacings s1 = 29 mm,
            % s2 = 100 mm: c/(4 s2) = 858 Hz .. 0.1 c/s1 = 1184 Hz used to be
            % rejected only because k s1 < 0.2 pi there (cond1 <= 4.3).
            fq = (100:2:4000).';
            g = struct('diameter', 0.029, 'micPositions', [-0.150 -0.121 0.071 0.171], ...
                'spacingUp', 0.029, 'spacingDown', 0.100, 'xFront', 0, 'xRear', 0.010);
            m = tim.sim.tubeModel(fq, g, tc.env, struct('type', 'thin', 'Zt', 200), struct('R', 0, 'x', 0.6));
            r = tim.acoustics.analyzeFourMic(fq, m.p, g, tc.env, struct('calValid', true(size(fq))));
            fl = r.valid.flags;
            ks = real(r.k) * [0.029 0.100];
            band = fq >= 860 & fq <= 1182;
            tc.verifyFalse(any(fl.nearSingularity(band)));
            % flagged exactly where one pair is within 0.2 pi of k s = n pi (n >= 1)
            tc.verifyEqual(fl.nearSingularity, any(abs(sin(ks)) < sin(0.2 * pi) & ks > pi / 2, 2));
            i1 = find(ks(:, 2) >= pi, 1);                       % k s2 = pi near 1.7 kHz
            tc.verifyTrue(fl.nearSingularity(i1));
            % short downstream pair (s2 = 10 mm): 3.0-3.4 kHz no longer rejected
            g2 = g; g2.micPositions(4) = 0.081; g2.spacingDown = 0.010;
            m2 = tim.sim.tubeModel(fq, g2, tc.env, struct('type', 'thin', 'Zt', 200), struct('R', 0, 'x', 0.6));
            r2 = tim.acoustics.analyzeFourMic(fq, m2.p, g2, tc.env, struct('calValid', true(size(fq))));
            tc.verifyFalse(any(r2.valid.flags.nearSingularity(fq >= 3000 & fq <= 3400)));
            % equal spacings (lab): identical to the former common-gate rule
            f3 = (100:10:6500).';
            m3 = tim.sim.tubeModel(f3, tc.geom, tc.env, struct('type', 'thin', 'Zt', 200), struct('R', 0, 'x', 0.6));
            r3 = tim.acoustics.analyzeFourMic(f3, m3.p, tc.geom, tc.env, struct('calValid', true(size(f3))));
            ks3 = real(r3.k) * [0.029 0.029];
            old = any(abs(sin(ks3)) < sin(0.2 * pi), 2) & f3 > 0.5 * min(r3.valid.limits.singular);
            tc.verifyTrue(any(old));
            tc.verifyEqual(r3.valid.flags.nearSingularity, old);
        end

        function rigidPlugUpstreamOnly(tc)
            % formula review calval-1: rigid plug at the front face (L = 0) in the
            % lab tube. M3/M4 lie behind the plug: the virtual tube gives p = 0
            % there (no standing wave continued past the plug). R needs only
            % M1/M2: validR and Test D use the upstream masks, whatever the
            % downstream quality is.
            fq = (100:5:5000).';
            g = struct('diameter', 0.029, 'micPositions', [-0.070 -0.041 0.116 0.145], ...
                'spacingUp', 0.029, 'spacingDown', 0.029, 'xFront', 0, 'xRear', 0);
            m = tim.sim.tubeModel(fq, g, tc.env, struct('type', 'air'), struct('R', 1, 'x', 0));
            tc.verifyEqual(m.behindTermination, [false false true true]);
            tc.verifyEqual(m.p(:, 3:4), zeros(numel(fq), 2));
            tc.verifyEqual(m.R, ones(size(fq)), 'AbsTol', 1e-12);
            % M3/M4: background noise only (incoherent, SNR 3 dB)
            rng(21);
            H = m.p;
            H(:, 3:4) = 1e-3 * (randn(numel(fq), 2) + 1j * randn(numel(fq), 2));
            coh = ones(numel(fq), 4); coh(:, 3:4) = 0.2;
            snr = 60 * ones(numel(fq), 4); snr(:, 3:4) = 3;
            o = struct('calValid', true(size(fq)), 'quality', struct('coherence', coh, 'snr_dB', snr), ...
                'fRange', [120 4500]);
            a = tim.acoustics.analyzeFourMic(fq, H, g, tc.env, o);
            v = a.valid;
            tc.verifyFalse(any(v.valid), 'all-four-position mask fails behind the plug');
            band = fq >= 120 & fq <= 4500;
            tc.verifyEqual(v.validR, v.upstream.valid);
            tc.verifyGreaterThan(nnz(v.validR), 0.9 * nnz(band));
            tc.verifyFalse(any(v.validR & ~band));
            tc.verifyEqual(a.R(v.validR), ones(nnz(v.validR), 1), 'AbsTol', 1e-9);
            tc.verifyFalse(any(v.validTau | v.validThinZt));
            r = tim.val.testDE_reference(struct('analysis', a), 'rigid', struct('L', 0));
            tc.verifyTrue(r.passed);
            tc.verifyEqual(r.validBins, nnz(v.upstream.geometryOK & v.upstream.qualityOK));
            tc.verifyEqual(r.magDeficit_median, 0, 'AbsTol', 1e-9);
            tc.verifyEqual(r.nonPassiveBins, 0);
            % review analysis-4: the reference-channel warning only when the
            % reference microphone sits behind the plug face xFront + L
            rr = struct('analysis', a, 'channelOfPosition', 1:4, 'spectra', struct('refChannel', 3));
            tc.verifyNotEmpty(tim.val.testDE_reference(rr, 'rigid', struct('L', 0)).warning);
            rr.spectra.refChannel = 1;
            tc.verifyEmpty(tim.val.testDE_reference(rr, 'rigid', struct('L', 0)).warning);
            mP = tim.sim.tubeModel(fq, g, tc.env, struct('type', 'air'), struct('R', 1, 'x', 0.30));   % plug beyond M4
            tc.verifyEqual(mP.behindTermination, false(1, 4));
            aP = tim.acoustics.analyzeFourMic(fq, mP.p, g, tc.env, struct('calValid', true(size(fq)), 'fRange', [120 4500]));
            rP = tim.val.testDE_reference(struct('analysis', aP, 'channelOfPosition', 1:4, ...
                'spectra', struct('refChannel', 3)), 'rigid', struct('L', 0.30));
            tc.verifyTrue(rP.passed);
            tc.verifyEmpty(rP.warning, 'reference at M3 upstream of the plug');
            % low coherence at M1 rejects R (and Test D bins) where it occurs
            coh2 = coh; bad = fq > 1000 & fq < 1500; coh2(bad, 1) = 0.5;
            o.quality.coherence = coh2;
            a2 = tim.acoustics.analyzeFourMic(fq, H, g, tc.env, o);
            tc.verifyFalse(any(a2.valid.validR(bad)));
            tc.verifyTrue(all(a2.valid.upstream.flags.lowCoherence(bad)));
            % the termination plane cannot lie upstream of the rear face
            tc.verifyError(@() tim.sim.tubeModel(fq, g, tc.env, struct('type', 'air'), struct('R', 1, 'x', -0.01)), ...
                'tim:sim:termination');
        end

        function bandEdgeTolerance(tc)
            % UI audit B-L2: logspace(log10(120), ...) gives 119.99999999999996 Hz;
            % such a step at fMin must count as inside the analysis band
            fq = logspace(log10(120), log10(4500), 12).';
            fq(1) = 120 - 3 * eps(120);                          % = 119.99999999999996 (3 ulp below)
            fq(end) = 4500 + 2 * eps(4500);                      % and a few ulp above fMax
            m = tim.sim.tubeModel(fq, tc.geom, tc.env, struct('type', 'air'), struct('R', 0, 'x', 0.6));
            r = tim.acoustics.analyzeFourMic(fq, m.p, tc.geom, tc.env, struct('fRange', [120 4500]));
            tc.verifyTrue(all(r.valid.measured));
            r2 = tim.acoustics.analyzeFourMic(fq * (1 - 1e-6), m.p, tc.geom, tc.env, struct('fRange', [120 4500]));
            tc.verifyFalse(r2.valid.measured(1), 'a real offset (1e-6) is still outside');
        end
    end

    methods (Static)
        function [k, Zc] = exactTube(fq, air, D)
            % Exact visco-thermal plane-wave mode of a rigid circular tube,
            % exp(+j w t) (Zwikker & Kosten 1949; Stinson 1991):
            %   rho_eff = rho / (1 - F(x_v)),  C_eff = (1 + (gamma-1) F(x_t)) / (gamma p)
            %   F(x) = 2 J1(x) / (x J0(x)),  x_v = a sqrt(-j w/nu),  x_t = x_v sqrt(Pr)
            % C_eff is scaled so that the lossless limit has the analysis c.
            a = D / 2; w = 2 * pi * fq;
            xv = a * sqrt(-1j * w / air.nu); xt = xv * sqrt(air.Pr);
            F = @(x) 2 * besselj(1, x) ./ (x .* besselj(0, x));
            rhoE = air.rho ./ (1 - F(xv));
            Ce = (1 + (air.gamma - 1) * F(xt)) / (air.rho * air.c^2);
            k = w .* sqrt(rhoE .* Ce); k = real(k) - 1j * abs(imag(k));
            Zc = sqrt(rhoE ./ Ce);
        end

        function [p, R] = thinField(fq, k, Zc, Zt, x)
            % pressures at x (1x4) for a thin element Zt at x = 0, anechoic end
            z = Zt ./ Zc; tau = 2 ./ (2 + z); R = z ./ (2 + z);
            p = zeros(numel(fq), 4);
            for m = 1:2, p(:, m) = exp(-1j * k * x(m)) + R .* exp(1j * k * x(m)); end
            for m = 3:4, p(:, m) = tau .* exp(-1j * k * x(m)); end
        end
    end
end
