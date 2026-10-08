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
            % Zt/rho c = 2j tan(kd/2) and is rejected by the velocity-mismatch mask.
            g = struct('diameter', 0.029, 'micPositions', [-0.070 -0.041 0.116 0.145], ...
                'spacingUp', 0.029, 'spacingDown', 0.029, 'xFront', 0, 'xRear', 0.075);
            air = tim.acoustics.airProperties(tc.env);
            k = tim.acoustics.wavenumber(tc.f, air, 0.029, 'iso10534');
            m = tim.sim.tubeModel(tc.f, g, tc.env, struct('type', 'air'), struct('R', 0, 'x', 0.6));
            r = tim.acoustics.analyzeFourMic(tc.f, m.p, g, tc.env, struct('calValid', true(size(tc.f))));
            tc.verifyEqual(r.tau, exp(-1j * k * 0.075), 'AbsTol', 1e-10);
            i = tc.f == 1000;
            tc.verifyEqual(abs(r.tau(i)), 0.99539, 'AbsTol', 2e-4);
            tc.verifyEqual(rad2deg(angle(r.tau(i))), -78.65, 'AbsTol', 0.1);
            band = tc.f >= 120 & tc.f <= 4500;
            tc.verifyLessThan(max(r.power.TL_tau_dB(band)), 0.09);
            tc.verifyEqual(r.thin.Zt_norm, 2j * tan(k * 0.075 / 2), 'RelTol', 1e-8);
            tc.verifyFalse(any(r.valid.validThinZt(band)), 'thin-element model rejected for 75 mm');
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
            k = tim.acoustics.wavenumber(tc.f, air, 0.029, 'iso10534');
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
            k = tim.acoustics.wavenumber(tc.f, air, 0.029, 'iso10534');
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
            k = tim.acoustics.wavenumber(tc.f, air, 0.029, 'iso10534');
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
        end
    end
end
