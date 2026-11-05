# Theory, conventions and methods

This document defines every convention used in the code (`+tim/+acoustics`, `+tim/+dsp`,
`+tim/+cal`, `tim.app.processMeasurement`) and derives the formulas that are implemented. All
quantities are SI. The GUI tab **Formula** (`tim.gui.equationsPanel`) shows the same equations in
short form, with the default thresholds read from `tim.app.defaultConfig` at run time.

Sources are cited as [n]. The list at the end (References) is, word for word, section 13 of the
Formula tab (`TestFormulaPanel` compares them). A definition, threshold or procedure without a
source is this program's own choice, and its reason is given here.

## 1. Conventions, symbols, air and tube losses

| Item | Convention |
|---|---|
| Time dependence | `exp(+jωt)` |
| Axis | `x` increases from the loudspeaker towards the termination; M1 is nearest the loudspeaker |
| Forward (incident, downstream) wave | `A·exp(−jkx)` |
| Backward wave | `B·exp(+jkx)` |
| Particle velocity `u` | positive towards `+x` |
| Attenuation | `k = k′ − jk″`, `k″ ≥ 0` |
| Positions (GUI) | specimen front face `x_L = 0`, rear face `x_R = d`; `x_M1 = −L1 − s1`, `x_M2 = −L1`, `x_M3 = d + L2`, `x_M4 = d + L2 + s2` |
| Transfer matrix | `[p_L; u_L] = T·[p_R; u_R]`; L = front (upstream) face, R = rear (downstream) face |
| Measured ratio | `H_k^m = Y_k / Y_ref` (ref = `cfg.analysis.refChannel`, default 1) |
| Calibration factor | `C_k = g_k / g_ref` (complex gain of chain k over that of the reference chain) |
| Transfer function | `H_k = p(x_k)/p(x_ref) = H_k^m / C_k` (calibrated) |
| Phasor from a sine fit | `x(t) = Re{Y·exp(jωt)}` |

Symbols (one meaning each, as in the GUI): `D` inner diameter of the tube, `d` specimen thickness,
`s1`, `s2` microphone spacings M1–M2 and M3–M4, `L1`, `L2` distances M2 → front face and rear face
→ M3, `T` temperature [K], `p_s` static pressure, `c` speed of sound, `ρ` density, `κ` ratio of
specific heats, `k` wavenumber, `Z_c` characteristic impedance of the tube (`ρc` without losses),
`g_k` chain gain, `H_k` transfer function, `C_k` calibration factor, `γ²` coherence, `R`, `τ`,
`R_term`, `α_d` dissipation coefficient, `Z_t` transfer impedance, `δ_u` velocity mismatch, `TL`
and `TL_τ`, and `τ_a`, `R_a` for the anechoic-termination coefficients derived from `T`.

### Air properties (`tim.acoustics.airProperties`)

    c   = 343.2 m/s · √(T / 293 K)                         ISO 10534-2 [1]
    ρ   = p_s / (287.05 J/(kg K) · T)                      ideal gas, dry air (R/M, M = 28.9647 g/mol)
    μ   = 1.716·10⁻⁵ Pa s · (T/273.15 K)^{3/2} · 383.55 K / (T + 110.4 K)     Sutherland [15]
    ν   = μ/ρ,   κ = 1.4,   Pr = 0.709

`T` is in kelvin (temperature in °C + 273.15). At 20 °C and 101.325 kPa: `c = 343.29 m/s`,
`ρ = 1.2041 kg/m³`, `ρc = 413.36 Pa·s/m`, `μ = 1.813·10⁻⁵ Pa·s`, `ν = 1.506·10⁻⁵ m²/s`. The pair
`(c, ρ)` is thermodynamically consistent: `ρc²/p_s = 1.4005`.

*Change 2026-10-09 (formula review acoustics-4).* The density used to be the ISO 10534-2
expression `1.186·(p_s/101325)·(293/T)`, which is 1.55 % below the density of air at 20 °C
(`ρc²/p_s = 1.379`). With the ideal-gas density every absolute impedance in Pa·s/m (`Z_t`, `T12`,
`T21`) is 1.6 % higher than before. Quantities normalised by `ρc` or `Z_c` (`R`, `τ`, `TL`, `α_d`,
`Z_t/(ρc)`) do not depend on `ρ`. `c_override` and `rho_override` still replace the computed values.

Humidity is neglected. At 20 °C and 50 % RH, `c` is 0.18 % higher and `ρ` 0.44 % lower than for
dry air. Enter the measured temperature and static pressure. For thin elements of low impedance
the error in `c` is amplified, see section 3A.

### Tube losses (`tim.acoustics.wavenumber`, `cfg.analysis.lossModel`)

**`'kirchhoff'` (default).** Visco-thermal wall losses of a wide tube (Kirchhoff [11]; first order
of the Zwikker–Kosten circular-tube model [12], Tijdeman [13], Stinson [14]). With the viscous boundary
layer `δ_v = √(2ν/ω)` and the radius `a = D/2`, the effective density and bulk modulus are

    ρ_eff/ρ = 1 + (1 − j)·δ_v/a,      K/K_eff = 1 + (κ − 1)(1 − j)·δ_v/(a·√Pr)

and `k = k0·√(ρ_eff/ρ · K/K_eff)` (`k0 = ω/c`) gives, to first order,

    k   = ω/c + (1 − j)·k″
    k″  = C_w·√f / (c·D),      C_w = 2√(πν)·(1 + (κ − 1)/√Pr) = 2.029·10⁻² m·s^−1/2  (20 °C)
    Z_c = √(ρ_eff·K_eff) = ρc·[1 + (1 − j)·Ψ·k″/k0],     Ψ = (1 − (κ−1)/√Pr) / (1 + (κ−1)/√Pr) = 0.356

(`f` in Hz, `c` in m/s, `D` in m.) The phase velocity is reduced by the same amount as the wave is
attenuated: `Re k = ω/c + k″`. For `D = 29 mm`: `k″/k0` = 1.0 % at 120 Hz, 0.35 % at 1 kHz and
0.17 % at 4.5 kHz (`k″ = 0.0645 /m` at 1 kHz); `|Z_c/(ρc) − 1|` = 0.51 % at 120 Hz and 0.08 % at
4.5 kHz. The expansion needs `a/δ_v ≫ 1` (66 at 100 Hz for `D = 29 mm`). Negative frequencies are
Hermitian-consistent (`k(−f) = −k(f)*`, `Z_c(−f) = Z_c(f)*`).

Against the exact circular-tube solution (Zwikker–Kosten / Stinson, Bessel functions, same air;
`TestAcoustics/kirchhoffMatchesExactTube`), `k` and `Z_c` agree to about 1·10⁻⁴ relative between
120 Hz and 4 kHz (test bound 2·10⁻⁴), and a thin element with `Z_t = ρc(0.05 + 0.05j·f/kHz)` in the
lab geometry is recovered within 0.1 % (0.06 % found).

**`'iso10534'`.** `k = ω/c − j·1.94·10⁻²·√f/(c·D)`, `Z_c = ρc`: the empirical ISO 10534-2 wall
attenuation [1]. It keeps `Re k = ω/c`, i.e. it omits the phase-velocity reduction of equal magnitude.
That is harmless for `|R|` (error < 0.008) and is the ISO-conformant choice for absorption work. It
biases the thin-element `Z_t`, which is a small difference of two pressures extrapolated over
`x3 − x2`: the absolute error is about `k″·(x3 − x2)·ρc`, i.e. about `0.02ρc` at 4.5 kHz for
`x3 − x2 = 157 mm`. Against the exact tube field (lab tube, 120 Hz–4.5 kHz, frequency-independent
`Z_t`) the relative error reaches about 47 % at `|Z_t|/(ρc) = 0.05`, 12 % at 0.2 and 2 % at 1
(review analysis-1; the earlier figure of 3–17 % was for a `Z_t` rising from 0.05ρc to 0.21ρc).

**`'none'`.** Lossless: `k = ω/c`, `Z_c = ρc`. The thin-element `Z_t` error is about `0.03ρc` at
4.5 kHz in the lab tube, i.e. up to about two thirds of `Z_t` at `|Z_t|/(ρc) = 0.05`.

`tim.app.validateConfig` reports a "CHECK:" warning for `'iso10534'` and `'none'`. A configuration
saved before `'kirchhoff'` became the default (2026-10-09), and the `config.json` of an older
measurement folder, still name `'iso10534'`; `tim.app.loadConfig` keeps the saved value.

The same model must be used for the analysis, the reference expectations of Tests D/E
(`testDE_reference` takes `res.analysis.k`) and the virtual tube (`tim.sim.tubeModel`,
`SimulatedRig`); all of them take it from `cfg.analysis.lossModel`.

**Decision (2026-10-09): `'kirchhoff'` stays the default; `'iso10534'` stays selectable.**
Reasons: (1) it is the physically complete wide-tube model (attenuation, the equal phase-velocity
reduction and `Z_c`; it matches the exact tube solution to 1·10⁻⁴), whereas the ISO formula is an
empirical attenuation-only approximation; (2) the attenuation of both is the same within 5 %, so
`|R|`, `|τ|` and TL hardly differ; (3) the omitted dispersion biases a thin-element `Z_t` by up to
about 47 % at `|Z_t|/(ρc) = 0.05` - the quantity this tube is built for. `'iso10534'` is kept for
comparisons and ISO-conformant absorption reports.

*First lab data (empty 75 mm section, 20261009_192503_oneload_sweep, CAL-20261009-191631, T entered
20 °C, CAD geometry; termination-independent one-load transfer matrix):*

| Model | `|τ/τ_exp| − 1` | phase error rms | median | > 2.5 kHz |
|---|---|---|---|---|
| `kirchhoff` | −0.18 % | 1.28° | +0.89° | +1.30° |
| `iso10534` | −0.26 % | 0.91° | −0.15° | +0.05° |
| `none` | −1.99 % | 0.91° | −0.15° | +0.05° |

The attenuation is clearly needed (`'none'`: −2 % in `|τ|`). The phase difference of the two models
over 75 mm is only 0.28° at 1 kHz and 0.55° at 4 kHz - the same as 1 K of temperature or 0.1-0.2 mm
of `d`. The temperature was not measured (20 °C entered) and the geometry is the CAD design (not yet
checked with calipers), so this measurement cannot decide between the models: the Kirchhoff
residual corresponds to the room being about 2-3 K warmer than 20 °C, or to `d` 0.3 mm shorter.
To test it: enter the measured air temperature, check s1, L1, d, L2, s2 with calipers and repeat
the empty-tube check; or measure a thin reference element with a known `Z_t`.

## 2. Two-microphone plane-wave decomposition

The two-microphone decomposition is that of Seybert and Ross [6] and Chung and Blaser [7]; the
four-microphone arrangement, with one pair on each side of the specimen, that of ASTM E2611 [3]
and Song and Bolton [8]. On each side of the specimen the field between the microphones and the
specimen is

    p(x) = A·exp(−jkx) + B·exp(+jkx),       u(x) = (A·exp(−jkx) − B·exp(+jkx)) / Z_c

The velocity follows from the linearised Euler equation of the cross-section average,
`jωρ_eff·u = −∂p/∂x`: `u = k/(ωρ_eff)·(A e^{−jkx} − B e^{+jkx})`, and `k/(ωρ_eff) = 1/Z_c` with
`Z_c = √(ρ_eff·K_eff)`. This is exact for the visco-thermal plane mode with the `'kirchhoff'` pair
`(k, Z_c)` and for the lossless model. `'iso10534'` keeps `Z_c = ρc` (ASTM E2611 [3] practice); for a
visco-thermal tube the true `Z_c` then differs by about `0.36·(1 − j)·k″/k0` (< 0.6 % above
100 Hz for `D = 29 mm`). `R`, `τ`, `R_term`, `δ_u`, `Z_t/Z_c`, the TL from `Z_t`, `τ_a`, `R_a` and
the TL from `T` do not depend on `Z_c`; only the dimensional `u`, `Z_t` [Pa·s/m], `T12`, `T21` and
`Z_t/(ρc)` do. (Note: `ρω/k` would be the wrong choice; it moves `Z_c` the other way.)

With two pressures `p_a, p_b` at `x_a, x_b`:

    [p_a; p_b] = M [A; B],   M = [e^{−jkx_a}  e^{+jkx_a}; e^{−jkx_b}  e^{+jkx_b}]
    det M = 2j·sin(k(x_b − x_a))
    A = (p_a e^{jkx_b} − p_b e^{jkx_a}) / det M
    B = (p_b e^{−jkx_a} − p_a e^{−jkx_b}) / det M

The upstream pair M1/M2 gives `A1, B1`, the downstream pair M3/M4 gives `A2, B2`; the pressures are
the calibrated transfer functions `H_k`. `det M = 0` when `k·s = nπ` (`s = |x_b − x_a|`), i.e. at
`f = n·c/(2s)` ≈ 5.92 kHz for s = 29 mm. The 2-norm condition number of the lossless pair matrix is
`max(|cot(ks/2)|, |tan(ks/2)|)`. The code computes it numerically with the lossy `k` in pair-local
coordinates (`waves.cond1`, `waves.cond2`); it is ≈ 31 at 120 Hz, ≈ 3.7 at 1 kHz and 1 at
`ks = π/2` (≈ 2.96 kHz).

Only *ratios* of pressures are needed: if all `p_m` are scaled by the same complex factor (the
unknown absolute pressure of the reference channel), `A` and `B` scale with it. `R`, `τ`, `Z_t` and
`T` are all ratios and are therefore independent of that factor.

### Boundary-plane extrapolation

With `A1, B1` from M1/M2 and `A2, B2` from M3/M4 (global coordinates):

    p_L = A1 e^{−jkx_L} + B1 e^{jkx_L},   u_L = (A1 e^{−jkx_L} − B1 e^{jkx_L}) / Z_c
    p_R = A2 e^{−jkx_R} + B2 e^{jkx_R},   u_R = (A2 e^{−jkx_R} − B2 e^{jkx_R}) / Z_c

The extrapolation assumes plane waves in air between the microphones and the faces, with the
configured loss model. The geometry must satisfy `x1, x2 ≤ x_L ≤ x_R ≤ x3, x4`. **Positions are
never invented**: when they are missing (`geometry.micPositions` or `xFront/xRear` = NaN), only the
pair-local reflection coefficients are computed: `local.R_up_atM2` (upstream, at the plane of M2)
and `local.R_dn_atM3` (downstream, at the plane of M3). Boundary quantities are then NaN and every
boundary validity mask is false.

## 3. Specimen quantities

### Reflection and transmission (pressure amplitude coefficients)

    R      = B1 e^{+jk x_L} / (A1 e^{−jk x_L})       reflection at the front face
    τ      = A2 e^{−jk x_R} / (A1 e^{−jk x_L})       forward wave at the rear face / incident wave at the front face
    R_term = B2 e^{+jk x_R} / (A2 e^{−jk x_R})       reflection of everything downstream, referred to the rear face

**These are the as-mounted values** of the specimen together with the actual downstream
termination. For a transmitting specimen `R = S11 + S12·S21·R_t/(1 − S22·R_t)` depends on the
termination just as `τ` does (`S` = scattering matrix of the specimen, `R_t = R_term`). `R` and `τ`
equal the specimen's anechoic-backed values only when `R_term ≈ 0`; for a specimen that transmits
nothing `R` is intrinsic. Example: a thin screen `Z_t = 0.5ρc` has `|R| = 0.20` with an anechoic
termination; `|R_term| = 0.1` moves `|R|` to 0.14–0.26 (formula review calval-4).
Termination-independent values are `τ_a` and `R_a` from the transfer matrix (section 3B).

`R` is computed from the upstream pair M1/M2 alone, and its mask `valid.validR` uses only that
pair (section 8). `τ` is contaminated by waves that return from the termination and are
re-reflected by the specimen's rear face; `valid.validTau` therefore requires
`|R_term| ≤ cfg.analysis.anechoicRmax` (0.1 by default).

Power quantities, assuming the same medium and cross-section on both sides: `|R|²` (reflected
power fraction), `|τ|²` (transmitted power fraction) and the **dissipation coefficient**
`α_d = 1 − |R|² − |τ|²`. `α_d` is not the ISO 10534-2 absorption coefficient `α = 1 − |R|²`. For
any termination the net power balance is `1 − |R|² − |τ|²(1 − |R_term|²)`; inside the `validTau`
mask (`|R_term| ≤ 0.1`) it differs from `α_d` by at most `0.01·|τ|²`. `α_d` uses the `validTau`
mask.

Passivity checks: `|R| ≤ 1 + tol`, and `|R|² + |τ|² ≤ 1 + tol` when `|R_term| ≤ anechoicRmax`
(`tol = passivityTol = 0.05`). Frequency lines that violate them are flagged `nonPassive` and are
never valid.

### A. Thin-element transfer impedance

For a lumped element of negligible thickness, across which the normal particle velocity is
(approximately) continuous:

    Z_t = (p_L − p_R) / u,      u = (u_L + u_R)/2   (cfg.analysis.velocityRef = 'mean'; or 'upstream': u_L, 'downstream': u_R)
    velocity mismatch δ_u = |u_L − u_R| / max(|u_L|, |u_R|)
    normalised: Z_t/(ρc) = res.thin.Zt_norm, with the real ρc of the air (air.Z0)

Continuity is **not** enforced. `δ_u` is reported per frequency, and `valid.validThinZt` requires
`δ_u ≤ velocityMismatchMax` (default 0.10). For a thick or compressible specimen `δ_u` is large: the
simulated 10 mm porous layer gives `δ_u > 0.1` in more than 90 % of the band, and an empty 75 mm
section gives `Z_t/Z_c = 2j·tan(kd/2)`. The Transfer impedance and Transmission loss views hide
`Z_t` and the TL from `Z_t` when `Re(k)·d > 1` anywhere in the analysis band (`tim.plots.thickSpecimen`,
`d` = specimen thickness). For such specimens use the transfer matrix.

For a pure series element `T = [1 Z_t; 0 1]` (Munjal [10]), `T12 = Z_t` (`tm.Zseries`).

**Transmission loss from Z_t** (`res.thin.TL_dB`). Inserting `T = [1 Z_t; 0 1]` into the
anechoic-termination transmission coefficient of section 3B gives `τ_a = 2/(2 + Z_t/Z_c)`, hence

    TL = −20·log10|τ_a| = 20·log10|1 + Z_t/(2·Z_c)|

with `Z_c` of the loss model. This assumes equal cross-sections on both sides. Because `Z_t` itself
does not depend on the termination, this TL is the anechoic-equivalent TL even when the real
termination reflects. It carries the validity of `Z_t` (`valid.validThinZt`). For comparison,
`res.power.TL_tau_dB = TL_τ = −20·log10|τ|` uses the measured `τ` directly and is valid only for an
anechoic termination (`valid.validTau`). In simulation, a 3 % termination reflection already makes
the τ-based curve ripple, while the Z_t-based curve stays smooth.

**Sensitivity of a thin element of low impedance** (formula review acoustics-5). `p_L − p_R` is
a small difference of two pressures extrapolated from pairs `x3 − x2` apart (157 mm in the lab
tube). An inter-pair phase error `δφ` (calibration residual) and an error `Δk′` of the real part
of the wavenumber (temperature, humidity, loss model) give an **absolute** error

    |ΔZ_t|/(ρc) ≈ |δφ_interpair| + |Δk′|·(x3 − x2)

(anechoic termination; larger near pressure nodes with a reflecting termination). Example: `c`
0.18 % too low (50 % RH neglected) gives 9–12 % error in `Z_t` between 1 and 4 kHz for
`Z_t = ρc(0.05 + 0.05j·f/kHz)`, and a residual phase of 0.002 rad on M3/M4 gives
`|ΔZ_t| ≈ 0.002ρc` at all frequencies. Neither `phaseSensitive` nor `velocityMismatch` flags this.
When `|Z_t|/(ρc)` is below about 0.2, log temperature and humidity and keep the inter-pair phase
residual of Test C small.

### B. Two-port transfer matrix

`[p_L; u_L] = T [p_R; u_R]` has four unknown complex elements per frequency. One excitation state
gives one vector equation, i.e. two scalar equations. A complete `T` therefore needs **two
independent acoustic states** (ASTM E2611 [3]; Song and Bolton [8]): two terminations (two-load
method) or two source positions. The window measures it with Method "Two loads" (1.4.0, WO-005:
`tim.app.runTwoLoad`, `tim.app.processTwoLoad`); scripts use `tim.acoustics.transferMatrix`.

* **Two-load** (`transferMatrix('twoLoad', resA, resB)`):
  `T = P·Q⁻¹`, `P = [p_L⁽¹⁾ p_L⁽²⁾; u_L⁽¹⁾ u_L⁽²⁾]`, `Q = [p_R⁽¹⁾ p_R⁽²⁾; u_R⁽¹⁾ u_R⁽²⁾]` for loads (1)
  and (2). The column scaling of each load cancels, so relative pressures can be used. If the
  loads are too similar, `T` is undetermined. **condQ** (this program): the condition number of `Q`
  with the velocity row multiplied by `Z_c` and then **every column scaled to unit length**, since
  the scale of a load (generator level, reference microphone, a resonance in front of the reference
  microphone) is arbitrary and must not change it. With θ the angle between the two boundary states
  `[p_R; Z_c u_R]`, `condQ = cot(θ/2)`: 1 for orthogonal states, ∞ for equal loads; errors of the
  measured states grow up to condQ times in `T`. Up to 1.3.2 only the velocity row was scaled. A
  line is valid when every load used is valid (both microphone pairs, `valid.valid`) and
  `condQ ≤ analysis.condQMax` = 10 (this program). For a rigid cap (`R = 1`) and an open end
  (`R ≈ −1`) at the same plane the states are nearly orthogonal (condQ 1.0–2.4 in the lab band);
  for the lab absorber against a rigid cap at the tube end the lab data give condQ ≤ 11
  (`docs/workorder_two_load.md`, section 2).
* **Repeat of load A** (this program): with A → B → A′, `T(A,B)` and `T(A′,B)` are compared,
  `d = ‖T̃(A,B) − T̃(A′,B)‖ / ‖T̃(A,B)‖` per line with `T̃ = [T11, T12/Z_c; Z_c·T21, T22]`
  (Frobenius norm); the median over the lines valid in all loads must not exceed
  `analysis.repeatTol` = 0.05. `T` does not depend on the termination, so a termination mounted
  again a little differently (a re-packed absorber) does not count; a moved specimen or microphone
  does. The value is a draft from simulation (no change: median 0.004–0.014); it is set from the
  first hardware measurement of an empty section (WO-005 section 9).
* **One-load, symmetric** (`transferMatrix('oneLoadSymmetric', res)`; [3], [8], [9]): valid
  **only** if the specimen is reciprocal (`det T = 1`) **and** symmetric (`T11 = T22`). Then, with
  `q = p_L u_R + p_R u_L`: `T11 = T22 = (p_R u_R + p_L u_L)/q`, `T12 = (p_L² − p_R²)/q`,
  `T21 = (u_L² − u_R²)/q`. This is an assumption-based reconstruction, not a general measurement.

From `T` (anechoic-termination equivalents, independent of the actual termination; equal
cross-sections, [3], [10]):

    τ_a = 2 / (T11 + T12/Z_c + Z_c·T21 + T22)
    R_a = (T11 + T12/Z_c − Z_c·T21 − T22) / (T11 + T12/Z_c + Z_c·T21 + T22)
    TL  = −20·log10|τ_a|

`τ_a` is the transmitted wave at the rear face over the incident wave at the front face for an
anechoic termination; it differs from the ASTM E2611 `t` only by the phase `e^{−jkd}`. The window
also gives `α_a = 1 − |R_a|²` and the dissipation `1 − |R_a|² − |τ_a|²`.

The specimen **backed by a rigid wall** at its rear face (`u_R = 0`; [3], [9]):

    Z_h = T11 / T21,   R_h = (T11 − Z_c·T21) / (T11 + Z_c·T21),   α_h = 1 − |R_h|²

**Thin element by `T`** (this program): a thin series element has `T = [1, Z_t; 0, 1]`, so `T12`
is its `Z_t` where `|Z_c·T21|` and `|T22 − 1|` are small. The Transfer impedance view colours `T12`
where both are at most `analysis.velocityMismatchMax` = 0.10. Unlike the velocity mismatch `δ_u`
of one load (section 3A), this does not depend on the termination: `u_L − u_R = T21·p_R +
(T22 − 1)·u_R`, and near a pressure maximum at the rear face (a rigid termination) a small `T21`
gives a large `δ_u`.

Diagnostics: `reciprocityError = |det T − 1|` (flagged above `analysis.reciprocityTol` = 0.1,
a quality indicator, not a mask; a passive linear specimen without flow is reciprocal [8]),
`symmetryError = |T11 − T22| / (|T11| + |T22|)` (zero for a symmetric specimen: it tells whether
the one-load method would apply).

### C. Sound level at the specimen (1.6.0, WO-006)

The ratios above do not depend on the excitation level for a linear specimen. The level matters
for specimens that are not linear (the resistance of necks and perforates depends on the particle
velocity) and for the SNR. Every swept or stepped measurement therefore reports, per frequency
line, the incident pressure at the front face and the particle velocity there (`res.levels`,
`tim.app.processMeasurement`; owner decisions 2026-11-04, `docs/workorder_equalizer.md` stage 1).
The equalizer of the stepped sine (stage 2) uses the same values.

The decomposition uses pressures relative to the reference microphone, `H = p/p_ref` (section 2),
so `A1`, `B1` and `u_L` are relative to `p_ref`. With `p̂_ref` the absolute pressure amplitude
(peak) at the reference microphone (DAQ channel `analysis.refChannel`):

    |p_inc|   = |A1 e^{−jk x_L}| · p̂_ref / √2       incident wave at the front face [Pa rms]
    L_inc     = 20·log10(|p_inc| / 20 µPa)            [dB SPL]
    |u_L|_rms = |u_L| · p̂_ref / √2                   particle velocity at the front face [m/s; shown in mm/s]

with `u_L` of section 2 (`Z_c` of the loss model) and `p̂_ref = Ŷ_ref / S_ref`, `S_ref` the
sensitivity of the reference microphone from the sensitivity layer (certificate, TEDS or nominal,
`acquisition.sensitivityPolicy`); the complex calibration is relative (`C_ref = 1`) and does not
enter `p̂_ref`.

* **Stepped sine**: `Ŷ_ref` is the fitted tone amplitude of the step (section 5, the mean of
  `|Y_ref,i|` over the blocks and the repetitions), the tone level of the reference channel in the
  Spectrum view.
* **Swept sine**: the **sine-equivalent amplitude** of the sweep as it passes the line
  (`tim.dsp.sweepEquivalentAmplitude`):

        Ŷ_ref(f) = (2/f_s)·√(ḟ(f)·P_ref(f)),   P_ref = Σ|Y_ref|² / n
        ḟ = f·ln(f_stop/f_start)/T  (logarithmic),   ḟ = (f_stop − f_start)/T  (linear)

  `Σ|Y_ref|²` and `n` (= `nAvg`) are those of the H1 sums of section 4, step 3 (the FFT bins of the
  line with their edge weights, and the repetitions; `Y` the unnormalised DFT of the windowed
  segment; `res.spectra.refPower` = `P_ref`). `T` is the sweep duration on the DAQ clock from the
  matched filter of the sweep gate (mean over the gated repetitions; the programmed duration when
  no repetition was gated). Derivation (Parseval): a sine of amplitude `A` that sweeps at the rate
  `ḟ` stays `Δf/ḟ` in a line of width `Δf`, so the line holds the energy `A²·Δf/(2ḟ)`; the
  one-sided DFT energy of the line is `2·Σ|Y|²/(N·f_s)` with `n = Δf·N/f_s` bins (`N` the FFT
  length), hence `A² = 4ḟ·Σ|Y|²/(n·f_s²)`. Stationary phase gives the same, `|X(f)|² = A²/(4ḟ)`
  and `|Y| = f_s·|X|` ([18]). The FFT length (zero padding) and the number of repetitions cancel.
  The window is 1 inside the band (the sweep gate, section 4 step 2; the 10 ms tapers of step 2'
  lie at the ends of the excitation), so no window correction enters. For a linear tube the
  channel spectrum is the drive spectrum times the response of the channel, so `Ŷ_ref(f)` is the
  steady-state amplitude a stepped sine of the same generator level would give at `f`. Only the
  drive spectrum itself is smooth just on the scale of `√ḟ` (15 Hz at 150 Hz and 80 Hz at 4.5 kHz
  for a 3 s logarithmic sweep 80–5500 Hz): near the ends of the sweep and the ramps of the gate
  (the lowest lines of the band, within a few `√ḟ` of `f_lo/1.1`) the value ripples by up to a few
  0.1 dB. NaN outside `[f_start, f_stop]`. While a sweep passes a sharp resonance the level in the
  tube has no time to build up: the instantaneous level is lower than this steady-state value,
  which is one reason why a level-controlled measurement uses the stepped sine (WO-006).

Conditions (otherwise NaN, `res.levels.note` says why): a **calibrated** result (owner decision
2026-11-04: without the calibration the chain mismatch of M2 enters `A1` amplified by
`1/(2 sin(ks))`; the 2 % of the virtual rig give 16 %, 1.3 dB, at 120 Hz), the front face known
(`x_L`), data in volts and a valid `S_ref`; `res.levels.refAmplitude_Pa` (the reference
microphone alone) is kept when only the calibration or the face is missing. A line is valid with
`valid.validR` (section 8): `A1` and `u_L` need only the upstream pair, as `R`. Accuracy: the absolute value rests on `S_ref` (a nominal
sensitivity can be 1–2 dB off; use the certificate or TEDS). A relative calibration residual `δ`
of M2 against M1 changes `|A1|` by about `δ/(2 sin(ks))`: 0.5 % gives 2.4 % (0.2 dB) at 200 Hz and
0.5 % at 1 kHz for `s` = 29 mm; `|u_L|` is affected similarly. Random noise gets no level in 1.6.0
(no sine amplitude; a level per line would depend on the line width).

*Verification (simulation, `TestSpecimenLevels`; limits of the test, not measured values):* ideal
synthetic sweeps of known amplitude (median error below 0.05 dB from 150 Hz up for a log sweep,
also behind a linear filter and over repetitions), the face values of an analytic field (exact),
the virtual rig against its own incident wave (steps within 0.3 dB, face velocity within 5 %; the
sweep within 0.2 dB median) and the sweep against the steps at the same generator level (0.5 dB).
Not yet compared on the bench with an independent level (`hardware_status.md`).

**Level equalizer of the stepped sine** (stage 2; owner decisions 2026-11-04,
`tim.app.equalizerPlan`). The controlled quantity `q` is either the incident pressure
`|p_inc|` (dB SPL above, used as Pa rms) or the face velocity `|u_L|_rms` [mm/s]. A
pre-measurement plays the same steps at `V_pre = V_max·10^(preLevel_dB/20)` (default −20 dB;
`V_max` = the amplitude field, at least the smallest level of the source) and gives `q_pre,k` per
step. With the transfer from the generator voltage to the field at the specimen taken as linear,
the voltage that gives the target `t` is

    V_k = min(V_max, V_pre · t / q_pre,k)

on a 0.1 mVpp grid (at most 0.04 dB at 20 mVpp). A step with `V_pre·t/q_pre,k > V_max` is played at
`V_max` and cannot reach `t`; a step below the smallest level of the source is played there
(above `t`); a step without a level from the pre-measurement at `V_pre`. The achieved value is
taken from the equalized measurement itself (`res.levels`, recomputed on Reprocess), not from the
plan: `ΔL_k = L_k − L_t` (incident pressure, dB) or `ΔL_k = 20·log10(|u_L,k| / t)` (face velocity),
and the step reaches the target when `|ΔL_k| ≤ tolerance_dB` (default 1 dB; `ΔL_k`, not the drift
`Δ_k` of the settled check in section 5 step 7). This is **reported, never
masked**: the ratios of sections 2-3 do not depend on the level for a linear specimen, so a missed
target is no reason to reject a line. For a specimen that is not linear the transfer between
`V_pre` and `V_k` is not proportional; the reported `ΔL_k` then shows how far the feedforward missed
(no correction pass in 1.6.0). The transfer from the generator to the field at the specimen
depends on the termination (the waves reflected by the specimen and the termination return to
the loudspeaker), so a plan belongs to the termination it was measured with: with two loads a
pre-measurement follows every change of termination (loads A and B), and load A again is played
with the voltages of load A, so that the repeat check of section 3B compares only the mounting
(owner decisions 2026-11-04). For a specimen that is not linear the two-load T stays an
approximation: at the same incident pressure the faces still see other states with A and B; the
equalizer reduces the difference, it does not remove it. *Verification (simulation,
`TestEqualizer`):* both quantities within 0.3 dB of the target at every step of the virtual tube
(linear), capped steps reported. The playing of the steps is described in section 5, step 6.

## 4. Swept-sine estimator without generator synchronisation

The 33220A and the LAN-XI have independent clocks. The sweep is BUS-triggered by software, so its
start is uncertain by the network/stream latency and the generator trigger latency. The manual
gives no explicit sweep law and states that the sweep is made of discrete frequency steps. The
estimator therefore **never uses the excitation signal**.

For a linear time-invariant tube, every LAN-XI channel k records

    Y_k(f) = g_k(f) · p(x_k, f) · S(f)

where `g_k` is the complex gain of the measurement chain (microphone, cable, CCLD supply, LAN-XI
input) and `S(f)` the (unknown) spectrum of the loudspeaker drive over the analysis window. All four
channels are sampled by the same LAN-XI clock, so

    H_k^m = Y_k / Y_ref = [p(x_k)/p(x_ref)] · [g_k / g_ref] = C_k · H_k

which is independent of `S(f)`. That removes the dependence on:

* the sweep waveform (stepped, non-ideal, linear or logarithmic),
* the start time, trigger latency and generator clock offset/drift,
* loudspeaker/amplifier harmonic distortion. A harmonic of the drive is acoustic excitation at its
  own frequency and propagates through the same linear tube. The tube and specimen must be linear;
  the source need not be.
* the start-frequency tone the 33220A emits before and after a triggered sweep (it is outside the
  sweep gate of step 2 anyway).

Estimator (`tim.dsp.sweepResponse`), per repetition. The H1 estimator and the coherence are those
of Bendat and Piersol [16] (sweep measurements in general: Müller and Massarani [18]); the sweep
gate, the frequency lines and the SNR are this program's:

1. Detect the excited interval on the reference channel (band-limited short-time RMS in 10 ms
   frames, 12 dB above the pre-roll background).
2. **Sweep gate** (generator output on/off transients excluded, 2026-10-09). The 33220A output
   relay clicks when the output is switched on (the start-frequency tone then plays until the
   trigger) and off (after the sweep; at the end of the sweep the generator also jumps back to the
   start frequency). These transients are not part of the sweep. If they do not follow the
   loudspeaker → tube path exactly (electrical crosstalk, tube vibration) they bias `H`; in any
   case they add energy outside the sweep. The actual start `t0` and duration `T` of the sweep in
   every repetition are found by a matched filter with the head and the tail of the nominal sweep
   (`tim.dsp.estimateSweepLaw`; accepted if the correlation peak is ≥ 8 × its median, `T` within
   2 % of the programmed duration and the sweep inside the detected interval). With `t(f)` the
   time of frequency `f` on the sweep and `[f_lo, f_hi]` the analysis band, the window is
   0 before `t(max(f_start, f_lo/1.5))`, a raised cosine up to `t(max(f_start, f_lo/1.1))`, 1 up
   to `t(min(f_stop, 1.1 f_hi))` and a raised cosine down to `t(min(f_stop, 1.5 f_hi))`. The
   window edges lie in the part of the sweep outside the band (long, smooth ramps, so truncation
   leakage stays out of the band), and every frequency of the band keeps at least the time from
   `f_hi` to `1.1 f_hi` of ring-down (in the tube about 1 ms per 0.3 m of path, decaying with
   |R|). Ramps shorter than 10 ms are widened to 10 ms inside the sweep. The pre-roll noise
   estimate uses the same window energy. The window of repetition 1 is shown in the Time signals
   view (grey: not analysed; its note names an end without the margin, below). If the sweep is
   not found, step 2' is used and a warning says so.
   The sweep must reach beyond the band: it should start at or below `f_lo/1.3` and stop at or
   above `1.1 f_hi` (default 80–5500 Hz for 120–4500 Hz). Closer to the band the gate has no room
   for its ramps at that end: they would fall on the band edges (the lower one at most half as
   long as designed, the start-frequency tone cut close to the band; no ring-down margin above
   `f_hi`), and the lines there would be biased while their coherence stays high, so they would
   remain valid. **An end without that margin therefore gets another edge** (owner decision
   2026-10-11), with exactly the thresholds of the warning (`f_start > f_lo/1.3`,
   `f_stop < 1.1 f_hi`, with `f_lo`, `f_hi` the outer edges of the first and last line):

   * **start** (owner decision 2026-10-13, 1.3.1): the gate's ramp on the sweep law continued
     before the sweep start, 0 before `t(f_lo/1.5)` and a raised cosine up to `t(f_lo/1.1)` (at
     least 10 ms, not before the record start), with `t(f)` not clamped to `f_start`. Before `t0`
     the generator plays its start-frequency tone, so the ramp lies on that tone, which is not cut
     inside the band; an output-on transient earlier than `t(f_lo/1.5)` stays out, a later one is
     weighted by the ramp. From 2026-10-11 to 2026-10-13 this end was step 2' (from the detected
     start minus 10 ms, the output-on transient always inside); such results keep the name
     `'detected start'`;
   * **end**: the window is extended past the end of the sweep `t0 + T` by the gate's ring-down
     margin, the sweep law continued beyond `f_stop`: 1 up to `t(1.1 f_hi)`, a raised cosine down
     to `t(1.5 f_hi)` (at least 10 ms, at most to the end of the record). An output-off transient
     later than that stays out.

   `res.diagnostics.excitation(r).gateEnds` records the edge used at each end of every repetition
   (`'gate'`, `'ramp before start'`, `'ring-down margin'`), and `tim.dsp.sweepResponse` adds a warning
   ("Sweep … too close to the analysis band for the sweep gate: …", in `res.diagnostics.warnings`
   and the calibration log) that names the edge and the margin; `tim.app.validateConfig` reports
   the configured range with the same limits (`tim.dsp.sweepGateLimits`, one definition for both:
   `f_lo/1.3` = 91.5 Hz and `1.1 f_hi` = 4951.1 Hz for 120–4500 Hz at Δf = 2 Hz, printed as 91 and
   4952 Hz; until the review of 2026-10-11 the check used the line centres, 92 and 4950 Hz, so a
   sweep set to those values passed it and was analysed without the gate at that end). The lab
   range (80–5500 Hz or wider for 120–4500 Hz) keeps the gate at both ends: the five lab folders
   and both lab calibrations give bit-identical results with this rule.

   *Choice of the edges (simulation, 2026-10-11; 3 s log sweep, band 120–4500 Hz, session-like
   records with the output switched off 0.05 or 0.19 s after the sweep, max |H/H_true − 1|).*
   Without the gate's ramps both candidates for the end - step 2' (to the detected end plus the
   ring-down time) and the extension past `t0 + T` - remove the bias equally (|R_term| = 0.9:
   120–4500 Hz 58 % with the gate → 0.9–2.2 %; 80–4600 Hz 7.9 % → 0.63 %; 80–4500 Hz 63 % →
   0.62 %; |R_term| = 0.03: 16–18 % → 0.02–0.24 %; trigger latency 5–30 ms as in the rig or
   0.13–0.28 s as measured on the lab). With an output-off click that does not follow the tube
   (independent per channel, three times the signal RMS, as in `TestDsp`) step 2' always contains
   it, while the ring-down margin past `t0 + T` leaves a click 0.19 s after the sweep at the edge of
   the window (80–4600 Hz, |R_term| = 0.9: 92 % vs 13 %; with the click 0.05 s after the sweep both
   contain it). The extension is therefore used at the end. At the start step 2' was used first
   (there is no ring-down before the sweep); 109–5500 Hz: 12 % → 0.63 % (|R_term| = 0.9), but it
   always contains the output-on click.

   *The start, again (simulation, 2026-10-13; band 120–4500 Hz, output-on and output-off clicks
   as above, start tone = trigger latency, max |H/H_true − 1|, step 2' / ramp before the start).*
   With clicks the ramp before the start is better wherever the start tone is longer than the
   part of the ramp before `t0`: 5 s sweep (the lab's), latency 0.13 s, |R_term| = 0.9: 109 Hz
   16.5 % → 9.0 %, 100 Hz 17.4 % → 2.3 %, 92 Hz 18.0 % → 0.62 %; latency 0.28 s: 109 Hz
   17.3 % → 1.2 %, 100 Hz 17.8 % → 0.62 %; 3 s sweep, latency 0.13 s: 109 Hz 64 % → 13 %, 100 Hz
   60 % → 1.1 %, 92 Hz 57 % → 0.63 %; with the rig's 5–30 ms latency the click stays inside
   (109 Hz 16 % → 16 %, 92 Hz 18 % → 2.3 %). Without clicks both give the same within 0.4 % (one
   case 0.75 %: 3 s, 120 Hz, 0.28 s, 1.7 % → 2.5 %). An end without margin at the stop as well
   (120–4500 Hz) is dominated by the output-off click past the sweep (52–71 % with every start).
   A start never earlier than 50 ms after the detected output-on was also simulated: it keeps
   the click out in every case (0.6 %), but without a click it biases the edge lines when the
   start tone is short (109 Hz, 5–30 ms: 0.62 % → 5.4 %; 120 Hz, 3 s: 1.2 % → 15 %), so it was
   not taken. A start without margin may still contain the output-on click, so the advice
   stays: let the sweep
   reach `f_lo/1.3` and `1.1 f_hi`.

   *Measured with the gate before 2026-10-11 (audit; noise-free rig, 3 s log sweep, band
   120–4500 Hz, max |H/H_true − 1| over the band, |R_term| = 0.03 / 0.9):* 80–5500 Hz 0.10 % / 1.9 %
   (as without the gate); start 100 Hz 0.28 % / 2.3 %, 105 Hz 0.77 % / 6.9 %, 109 Hz (still 10 %
   below the band) 0.84 % / 13 %, 120 Hz 1.9 % / 19 %; stop 4950 Hz 0.10 % / 1.0 %, 4800 Hz 0.19 % /
   0.9 %, 4600 Hz 2.5 % / 7.7 %, 4500 Hz 18 % / 63 %. The earlier advice ("at least 10 % below the
   band") was not enough at the lower edge.

   *Measured on the lab tube (empty 75 mm section, 2026-10-09):* the trigger latency varied by
   0.15 s between repetitions (sweep start 1.128–1.277 s after the record start) and the output-off
   click came 0–0.19 s after the end of the sweep. Gating changed `H` by 0.06 % (median) and at
   most 1.4 % (above 4 kHz), added 24 valid frequency lines and raised the median SNR by 0.9 dB;
   the empty-tube check was unchanged (|τ/τ_exp| − 1 = −0.2 %, 1.25° rms).
2'. Without the gate (no sweep settings, `excludeSwitching = false`, or sweep not found): cut from
   the detected start minus 10 ms to the detected end plus a ring-down margin
   (`min(postRoll, 0.5 s)`), with 10 ms raised-cosine tapers `w`. The acoustic ring-down is
   included, and truncation leakage is confined to segments where the signal has decayed; the
   on/off transients are inside this window.
3. FFT, then accumulate `Y_k Y_ref*`, `|Y_ref|²` and `|Y_k|²` over all FFT bins inside each
   frequency line `[f − Δf/2, f + Δf/2]` (`Δf = cfg.analysis.df`, default 2 Hz) and over all
   repetitions. The line is **symmetric about its frequency `f`**: a bin inside counts once, a
   bin exactly on an edge `f ± Δf/2` counts with weight 1/2 in each of the two lines that share
   it (at the ends of the grid in the one line). With the lab's power-of-two FFT every edge is a
   bin (`f_s/N_FFT` = 0.125 Hz for a 5 s sweep, 0.25 Hz for 3 s), so a line holds `Δf·N_FFT/f_s`
   bins in all (`nAvg` sums the weights) and its centroid is `f`.

   *Change 2026-10-11 (audit finding, approved by the owner).* The line used to be half-open,
   `[f − Δf/2, f + Δf/2)`: the bins `f − Δf/2 … f + Δf/2 − δ` (`δ = f_s/N_FFT`), centred at
   `f − δ/2`, so `H`, `γ²` and the SNR were estimates at `f − δ/2` labelled `f`. The phase of
   `H_k` was off by about `−(dφ_k/df)·δ/2` - a systematic inter-pair phase error, the quantity
   section 3A identifies as critical for a low `Z_t` (in simulation 1.2·10⁻⁴ to 5.7·10⁻⁴ rad
   median for a 3 s sweep, 0.2-0.6 % of a low `Z_t`; for a pure delay `τ` exactly `π τ δ`).
   Every saved sweep result and calibration (`C_k` uses the same estimator) carries the shift.
   The five lab folders were reprocessed into new folders on 2026-10-12 with version 1.2.1 and
   the calibration `CAL-20261010-212544` (owner decision; raw data are never overwritten). The
   folders and changes are listed in `docs/hardware_status.md`, "After the merge". That
   calibration was itself computed with the old line band.

   *Effect on the lab data* (the five folders of 2026-10-09/10 and both calibrations, reprocessed
   read-only in memory on 2026-10-11; 5 s sweeps, 16 bins per line and repetition). Relative
   responses `Y_k/Y_ref`: median phase change 3.5–6.2·10⁻⁴ rad per folder; up to 5·10⁻² rad and
   4 % only at lines of low coherence where `H` is steep. `C_k` recomputed from the saved switching
   sweeps:
   at most 4·10⁻³ in magnitude and 3.9·10⁻³ rad (median 2.3–2.4·10⁻⁴ rad) on its valid lines, 2–3
   lines change validity. New code with the recomputed calibration against the old code, on the
   valid lines: calibrated pressures at most 6.3·10⁻³ in magnitude and 6.6·10⁻³ rad, |ΔR| at most
   6.0·10⁻³, |ΔZ_t|/ρc at most 2.4·10⁻³ (1.4 % of `Z_t`; 0.1 % in three folders, the fifth has no
   valid `Z_t` line); no folder has a valid `τ` line (termination not anechoic); 0–2 lines per
   folder change a validity mask. The existing calibration files (`C_k` from the old band) applied
   to the new `H`: |ΔR| at most 4.6·10⁻³ and |ΔZ_t|/ρc at most 2.6·10⁻³ against the results of the
   old code; against a calibration recomputed with the new band (CAL-20261010-212544) the old
   `C_k` leaves at most 4·10⁻³ and 3.9·10⁻³ rad in the calibrated pressures, |ΔR| 3.2·10⁻³ and
   |ΔZ_t|/ρc 1.4·10⁻⁴.
4. Compute

        H_k^m = Σ Y_k Y_ref* / Σ |Y_ref|²                       (H1 [16])
        γ_k²  = |Σ Y_k Y_ref*|² / (Σ |Y_ref|² · Σ |Y_k|²)

   Because the sums run over neighbouring bins and repetitions, `γ²` is a meaningful consistency
   indicator. It is trivially 1 only for a single bin and a single repetition, which is reported
   as a warning.
5. SNR: the signal energy of the frequency line is compared with the expected energy of the
   background noise measured in the pre-roll (one-sided Welch PSD [17] `G_n,k`, same taper and length):

        E|N_k|² = G_n,k/2 · f_s · Σ_m w_m²          (per FFT bin)
        SNR_k  = 10·log10( max(Σ|Y_k|² − ΣE|N_k|², 10⁻⁴·ΣE|N_k|²) / ΣE|N_k|² )

   The floor gives −40 dB for noise-dominated lines. Repetitions without ≥ 0.1 s of clean
   pre-roll are left out of the SNR, and this is reported.

Clock drift between the LAN-XI module and the generator does not enter. Drift of the LAN-XI clock
itself is common to all channels.

**Verification (simulation)**: the virtual rig uses a stepped log sweep with a +35 ppm clock
offset, random trigger latency of 5–30 ms, loudspeaker high-pass and per-channel complex mismatch.
Transfer functions agree with the realised responses to a median error of 0.26 % at 2 mPa noise
(`TestDsp`). A noise-free linear sweep agrees to within 0.2 % at the 99th percentile, which
demonstrates the excitation independence.

## 5. Stepped sine

`tim.dsp.sineResponse`, called per step by `tim.app.processMeasurement`. The frequency is switched
by `FREQ` while the output stays on (phase continuous), and every step is analysed only after its
settling time, over its recording time (`N_rec` samples).

0. **Timing of a step** (`tim.app.steppedPlan`, owner decision 2026-11-04). Both times follow the
   frequency of the step:

        T_settle(f) = max(settleTime, settleCycles / f),   T_rec(f) = max(recordTime, recordCycles / f)

   Defaults 0.3 s / 50 cycles and 0.2 s / 100 cycles: below 167 Hz the settling, below 500 Hz the
   recording holds the given number of cycles (120 Hz: 0.42 s + 0.83 s), above that the minimum
   time applies (40 log steps from 120 to 4500 Hz: about 25 s per repetition, 33 s with the
   fixed 0.3 s + 0.5 s before 1.5.0). The recording is chosen so that every one of the 4 blocks
   holds at least 25 cycles and the noise bandwidth of the whole record stays at or below 5 Hz.
   The settling has to cover two things after the frequency command: the delay until the new
   frequency reaches the recording, and the decay of the tube. Both were measured in the lab tube
   (2026-11-05; empty 75 mm section, lab absorber and rigid cap, 1.45 Vpp, the 40 default steps
   with a settling of 1000 cycles, the record of every step analysed again with starts from 0 to
   900 cycles after the command):

   - The new frequency reached the recording 35–140 ms after the command (median about 50 ms):
     the command is scheduled on the samples received, which lag the sound by the latency of the
     stream and of the generator. This delay does not depend on the tube.
   - After the change the tube decayed within some tens of cycles, with the rigid cap as well.
     That is shorter than the visco-thermal estimate of the tube resonances (Q about 80 at 300 Hz
     and 150 at 1 kHz, 1 % after about 1.5 Q cycles) allows; the loudspeaker and the ports add
     damping.
   - The settling the settled check (step 7, limit 0.01) needed was shorter than the default at
     every step; the smallest margin was at 2348 Hz with the absorber (400 of 470 cycles, delay
     140 ms). Every re-analysed record whose H was more than 1 % from the settled value was flagged
     (161 of 1360); the limit corresponds to an error of H of about 0.3 %.
   - With the 0.2 s / 50 cycles of 1.5.x no step was flagged, and H agreed with the long settling
     within 0.5 %, except at the two steps of the lowest SNR (45 dB, a microphone near a pressure
     node of the rigid cap: 2.2 % and 1.4 %), where the re-analysis gives about 0.1 % from the
     settling: the rest is the repeatability of the two runs.

   Above about 300 Hz the minimum time therefore covers mainly the delay, and its margin over the
   longest delay plus the decay was about 40 ms; it was raised from 0.2 s to 0.3 s (owner decision
   2026-11-05; about 3 s more per repetition). A specimen with a sharp resonance of its own
   (membrane, plate, resonator) can ring longer than the empty tube at that resonance. A remaining
   transient shows as scatter between the blocks: lower coherence, a larger σ_H, and a drift of the
   channel ratios from the first to the last block, which the settled check (step 7) flags; the
   remedy is a longer settling. Configurations without `settleCycles` / `recordCycles` (or with 0)
   keep fixed times.

1. **Frequency.** The generator and LAN-XI clocks differ by up to ~10⁻⁴, so the frequency seen by
   the LAN-XI module is estimated on the reference channel (mean removed, Hann window `w`):

        f̂ = argmax |Σ_m w_m x_ref(t_m) e^{−j2πf t_m}|   over |f − f_nom| ≤ max(5·10⁻⁴ f_nom, 2 f_s/N_rec)

   and used for all channels.
2. **Block fits.** The record is split into `n_b` blocks (`nBlocks`, default 4) of
   `N = ⌊N_rec/n_b⌋` samples. In block `i` a linear least-squares fit on `[cos, −sin, 1]` at `f̂`
   (3-parameter sine fit, IEEE 1057 [4]) gives the phasor of every channel:

        x_k(t) ≈ Re{Y_k,i e^{j2πf̂t}} + o_k,i

3. **Transfer function, coherence, standard error.**

        H_k^m = Σ_i Y_k,i Y_ref,i* / Σ_i |Y_ref,i|²
        γ_k²  = |Σ_i Y_k,i Y_ref,i*|² / (Σ_i |Y_ref,i|² · Σ_i |Y_k,i|²)
        σ_H   = std_i(Y_k,i / Y_ref,i) / √n_b

4. **SNR (narrow band, per block).**

        SNR_k = 10·log10( mean_i(|Y_k,i|²/2) / (G_n,k · f_s/N) )

   `G_n,k` is the one-sided Welch PSD of the residual of a fit over the whole record, averaged over
   the lines 10–100 Hz away from `f̂` on both sides after removing lines above 10 × their median
   (previous step, harmonics, mains); with fewer than three such lines, ±200 Hz is used. `f_s/N` is the equivalent noise bandwidth of the N-sample fit:
   white noise of variance σ² has `G = 2σ²/f_s`, the LS phasor error is `E|ΔY|² = 4σ²/N`, so the
   noise power of the fitted sinusoid is `E|ΔY|²/2 = G·f_s/N`. The SNR is therefore that of **one
   block**; the mean of the `n_b` blocks has `10·log10(n_b)` dB more (6.0 dB for 4 blocks). With the
   defaults (4 blocks, 16384 Hz) `N = 3413` and `f_s/N = 4.8 Hz` at 120 Hz (0.83 s), `N = 819` and
   `f_s/N = 20 Hz` from 500 Hz up (0.2 s); Test B (1 s, 4 blocks) has `f_s/N = 4 Hz`. `snrBroadband_dB = mean_i(|Y|²/2) / residual variance` (all frequencies) is
   also returned.
   The noise level of the stepped-sine Spectrum view is `G_n,k·f_s/N` (`toneLevels.noise_dB =
   spl_dB − snr_dB`).
5. **Repetitions.** `H` is the mean over the repetitions, `γ²` and SNR the minimum, and the
   standard error `√(mean σ_H²)/√n_rep`.
6. **Level per step (level equalizer, 1.6.0; owner decisions 2026-11-04).** With
   `excitation.stepped.equalizer.mode` on, `MeasurementSession.measureStepped` first plays the
   same steps and repetitions at `V_pre = V_max·10^(preLevel_dB/20)` (the pre-measurement,
   processed with the session's calibration), then every step at its own generator level `V_k`
   of section 3C, never above the amplitude `V_max`. The level command (the optional contract
   method `setAmplitude`, `VOLT` on the 33220A; `docs/instrument_interface.md` section 3.2) is
   sent with the frequency command of the step while the output stays on: a lower level before
   the new frequency, a higher one after it, so that no frequency is played above its own level or
   that of the step before. The settling of the step (step 0) covers the level change as it covers
   the frequency change; a glitch of the level change on the 33220A is still to be checked on the
   instrument (`hardware_status.md`). The analysis of a step does not change: the transfer
   functions are ratios of the channels of the same step, so `V_k` enters only the level at the
   specimen (`res.levels.generatorVpp`) and the report of the equalizer (`res.equalizer`). The
   expected duration doubles (the pre-measurement has the same steps and repetitions).
7. **Settled check (1.6.0, owner decision 2026-11-04).** A transient that has not decayed when the
   record of a step begins (the tube or a resonant specimen after the frequency change, a settling
   time that is too short) makes the ratio of the channels change from block to block. Averaged
   into `H_k^m` it biases the result, while the coherence and the SNR can stay high: a weak first
   block counts little in the coherence, and a slowly changing tone hardly reaches the noise band
   10–100 Hz away from `f̂` (step 4). Per step, repetition and channel `k ≠ ref`, with the block
   ratios of step 3 (`tim.dsp.sineResponse`: `drift`, `driftSigma`):

        H_k,i = Y_k,i / Y_ref,i,     Δ_k = |H_k,n_b − H_k,1| / |H_k^m|

   The ratio removes what all channels share: a level change of the generator, the frequency
   estimate (a phase rotation from block to block, equal in every channel) and the clocks. Noise
   alone: by step 4 one block has `E|ΔY|²/2 = G_n·f_s/N = (|Y|²/2)/SNR`, i.e. `E|ΔY/Y|² = 1/SNR`
   with the per-block SNR, so the relative change between two independent blocks has the variance

        σ_Δ,k² = 2·(10^(−SNR⁰_k/10) + 10^(−SNR⁰_ref/10))

   `SNR⁰` is the per-block SNR of step 4 with `G_n` taken from the **pre-roll** of the repetition
   (the 0.5 s before the output goes on, noise only; the same band 10–100 Hz from `f̂` and the same
   trimming; Welch segments of about 0.25 s), not from the residual of the step. The residual of the
   fit over the whole record holds the transient under test: an abrupt one (the sound of the step
   arriving during the record, a settling of 0 s) spreads into the band and would raise its own
   `σ_Δ,k` in proportion to its size, so that whether it is flagged would depend on its shape, not
   on its size (review 2026-11-05). The pre-roll is free of it. A record with less than 0.1 s of
   pre-roll (synthetic data) uses the residual. Noise from the loudspeaker side (its rattle, the
   generator) reaches every microphone through the same transfer function as the tone and does not
   change the ratio; what changes it - electrical and room noise - is in the pre-roll.
   For complex Gaussian noise `Δ_k²/σ_Δ,k²` is exponentially distributed, `P(Δ_k > z·σ_Δ,k) =
   e^(−z²)`. The indicator is the excess over four standard deviations,

        e_k = max(0, Δ_k − 4·σ_Δ,k)

   which noise alone exceeds with the probability `e^(−16) ≈ 10⁻⁷` per channel and step; `e_k > 0`
   is a systematic change. With several repetitions the largest `e_k` counts. The flag
   `notSettled` (section 8) rejects a line when `e_k > analysis.settleDriftMax` at any port (for
   `R`: at M1 or M2); it is a quality flag (`qualityOK`). With one block (`nBlocks` 1) or a skipped
   repetition the step is not judged (`NaN`). The limit 0.01 (1 % of `|H_k|`, about 0.09 dB or
   0.57°): a transient that decays within the record biases the averaged `H_k^m` by at most about
   half the change (a drift linear over the record), 0.5 %, the size of the tolerance of the
   switching calibration on the virtual rig in the tests (5·10⁻³) and of the phase uncertainty
   0.002 rad of the masks (section 8). The limit is a default of this program.
   `analysis.settleDriftMax` = Inf switches the check off (in a script). Stored per step and DAQ
   channel in `res.spectra.settleDrift` (`e_k`) and `blockDrift` (`Δ_k`), the largest `e_k` over
   the ports in `res.analysis.valid.settleDrift`, and in `results.csv` (`settleDrift`,
   `flag_notSettled`) and `spectra.csv` (`settleDrift<c>`). The check uses the recorded data only,
   so a stepped measurement of an older version gets it when it is reprocessed.
   Limits: a transient much slower than the record changes little between the first and the last
   block and passes (it shows only as a dependence of `H_k` on the settling time); a stray line
   within about `1/T_block` of the tone (mains hum and its harmonics, `workorder_mains_hum.md`)
   beats against it and is flagged too when it reaches about half the limit relative to the tone
   (one exactly on the step frequency does not beat and is not seen); drifts between repetitions
   are not judged; noise that is much louder during the steps than in the pre-roll (a noise burst in
   the room) changes the ratios like a transient and can be flagged as well.
   Verification (simulation only, `tests/TestSettledCheck.m`): the virtual rig delays the sound by
   0.1 s from the generator to the front face, with its absorbing termination the other decays are
   shorter than 10 ms, and its first-order chain high-passes (2.6–4.2 Hz, time constants 38–61 ms, a transient of about
   f_hp/f) leave a drift far below 10⁻³ after the default settling; the default
   timing flags no step, and a settling of 0 s with four 80 ms blocks (the first block ends before
   the new tone reaches the microphones) is flagged at (nearly) every step, its excess equal to the
   drift within the noise of the pre-roll; an abrupt change of 1.2 % within a synthetic record is
   flagged against the pre-roll noise while the residual of the same record gives a sigma many
   times larger. On the bench the limit
   has still to be checked against the decay measurement of step 0 (`hardware_status.md`).

*Change 2026-10-09 (formula review dsp-1/dsp-2/formulatab-10).* The SNR used to divide the
one-sided PSD by 2 and to take the plain median of an unaveraged periodogram (−1.59 dB). Together
the SNR was 4.6 dB too high with the default settings. The corrected estimator has a Monte-Carlo
bias of +0.08 dB (white noise, N_rec = 8192) and +0.01 dB (N_rec = 16384); a stray tone −14 dB
50 Hz away makes it 0.2–0.3 dB conservative. The displayed noise level rose by the same 4.6 dB.

## 6. Noise excitation (scripts only)

The 33220A `FUNC NOIS` is used with Welch spectra [17] and the H1 estimator [16] (also for the SNR
from the coherence; `tim.dsp.welchResponse`, Hann window,
50 % overlap; note that MATLAB's `cpsd(a,b) = ⟨A·conj(B)⟩`, so `H = cpsd(x_c, x_ref) /
pwelch(x_ref)`):

    H_k^m = G_k,ref / G_ref,ref,    γ_k² = |G_k,ref|² / (G_ref,ref · G_k,k),    SNR_k = 10·log10(γ_k²/(1 − γ_k²))

interpolated (real and imaginary parts) onto the analysis grid. The GUI offers swept and stepped
sine only. The periodic multisine (arbitrary waveform) mode is **not** implemented; see
`assumptions_and_limitations.md`.

## 7. Frequency limits

`tim.acoustics.frequencyLimits(D, s, air)` gives, for D = s = 29 mm at 20 °C (c = 343.3 m/s):

| Limit | Formula | Value |
|---|---|---|
| Spacing lower limit (ASTM E1050 [2]: s ≥ 1 % of λ) | `0.01·c/s` | 118 Hz |
| Spacing upper limit (ASTM E1050 [2] / E2611 [3]: `ks ≤ 0.8π`) | `0.40·c/s` | 4.73 kHz |
| ISO 10534-2 [1] spacing rule (`f·s < 0.45c`) | `0.45·c/s` | 5.33 kHz (not applied) |
| Singularity (`ks = π`) | `c/(2s)` | 5.92 kHz |
| ISO 10534-2 [1] diameter rule (`f·D < 0.58c`) | `0.58·c/D` | 6.87 kHz |
| Cut-on of the (1,1) mode [10] | `1.8412·c/(πD) = 0.586·c/D` | 6.94 kHz |

The geometric validity range is

    max(0.01·c/s1, 0.01·c/s2) ≤ f ≤ min(0.40·c/s1, 0.40·c/s2),     f < min(0.58·c/D, f_(1,1)) = 0.58·c/D

`0.58·c/D` is always 1 % below the (1,1) cut-on (`0.58/0.586 = 0.990`), so the ISO diameter rule is
the binding diameter limit. For the lab tube the spacing limit `0.40·c/s` governs; the diameter
rule would bind only for `s < 0.40/0.58·D = 20 mm`. The defaults `lowerFraction = 0.01` and
`upperFraction = 0.40` are configurable. ISO 10534-2 also suggests `s > 5 %` of the wavelength for
better accuracy, which would give 592 Hz here. These are rules of thumb, **not** uncertainty
statements.

**The analysis band and these limits** (owner decision 2026-10-13, 1.3.2). The four-microphone
transmission measurement follows ASTM E2611 [3], whose frequency limits are those of ASTM E1050
[2] above (ISO 10534-2 [1] is the two-microphone reflection method; its `0.45·c/s` is not used).
The analysis band `analysis.fMin`–`fMax` is set in one of two ways (`analysis.bandMode`,
`tim.app.analysisBand`):

* `'geometry'` (the lab file): the band **is** the geometric validity range of the tube in the
  configuration or the IMPEDANCE TUBE fields, rounded inward to the line spacing `df` - for the lab
  tube at 20 °C 120–4734 Hz. It follows the microphone spacings, the diameter and the temperature
  (the speed of sound: 4695 Hz at 15 °C, 4779 Hz at 25 °C), at once in the window. A calibration
  covers the band it was made with and is not extended (`tim.cal.interpolateCalibration`): lines of
  a later, wider band (warmer air, another geometry - which needs a new calibration anyway) are not
  valid there. Since 1.5.1 such a line (or a stepped-sine step outside the band) is corrected with
  the factor of the nearest calibrated line, held constant, so that it still shows a value; it is
  flagged `outsideCalibration` and is never valid (owner decision 2026-11-04). Before 1.5.1 it had
  no value.
* `'fixed'` (the default, as before): the band is the configured one. Lines outside the limits are
  computed but rejected by the masks of section 8 (`belowSpacingLimit`, `aboveSpacingLimit`,
  `aboveModeCutOn`); `tim.app.validateConfig` reports a band that extends beyond the limits of the
  configured tube.

The window states the limits and the source of the band below the IMPEDANCE TUBE fields ("ASTM
E1050/E2611 limits 118–4735 Hz · analysis band 120–4734 Hz (from the tube)") and in the geometry
table of Setup > Tube setup.

The limits use `c`. With `'kirchhoff'` the phase speed is `c/(1 + k″/k0)`, 1 % lower at 120 Hz and
0.15 % lower near `c/(2s)`, which moves `ks = π` down by 0.15 % (9 Hz for s = 29 mm). The
near-singularity, condition and phase-sensitivity masks use `Re k` and follow it exactly.

Low-frequency phase sensitivity: a residual inter-channel phase error `δφ` within a pair gives a
relative error of order `δφ/(k′s)` in the decomposed waves. With `phaseUncertainty_rad = 0.002` this
is 3 % at 120 Hz; frequency lines above `maxPhaseSensitivity` (5 %) are flagged (below 75 Hz for
s = 29 mm). For thin elements of low impedance the inter-pair phase matters more, see section 3A.

## 8. Validity levels

`res.analysis.valid` (`tim.acoustics.validityMasks`) keeps the levels strictly separate:

1. `measured`: inside the analysis band `[fMin, fMax]` (edges tolerant by 10⁻⁹ relative, so a
   stepped-sine step that `logspace` rounded a few ulp outside counts as inside) with finite wave
   amplitudes of both pairs;
2. `geometryOK`: geometric validity range, singularity proximity, condition number, low-frequency
   phase sensitivity, each for both pairs;
3. `qualityOK`: coherence and SNR at all four ports, for a stepped sine the settled check (1.6.0,
   section 5 step 7), **and a valid complex calibration**. Without calibration nothing is ever
   valid.

`valid = measured & geometryOK & qualityOK & ~nonPassive`. An unknown coherence or SNR (NaN, e.g.
the swept-sine SNR when no repetition had ≥ 0.1 s of noise-only pre-roll, section 4 step 5) fails
its criterion, as in the switching calibration (`tim.cal.switchingCorrection`); before 2026-10-11
it passed silently. A step the settled check cannot judge (one block) is not flagged: that check
only adds to the coherence and the SNR, which still apply. `tim.app.validateConfig` reports a sweep pre-roll below 0.15 s. Criteria and
defaults (`cfg.analysis`; every threshold is a configurable default of this program, not a value of a
standard, and the geometric limits are those of section 7):

| Flag (rejects when true) | Criterion | Default |
|---|---|---|
| `outsideBand` | `f` outside `[fMin, fMax]` or wave amplitudes not finite | 120–4500 Hz |
| `belowSpacingLimit` | `f < max_s(lowerFraction·c/s)` | 0.01 |
| `aboveSpacingLimit` | `f > min_s(upperFraction·c/s)` | 0.40 |
| `aboveModeCutOn` | `f ≥ min(0.58·c/D, 1.8412·c/(πD))` | – |
| `nearSingularity` | `\|sin(k′s)\| < sin(0.2π)` and `k′s > π/2`, **per pair** (`k′ = Re k`) | – |
| `illConditioned` | `cond1 > condMax` or `cond2 > condMax` | 40 |
| `phaseSensitive` | `phaseUncertainty_rad/(k′·min(s)) > maxPhaseSensitivity` | 0.002 rad, 0.05 |
| `lowCoherence` | `γ_k² < coherenceMin` at any port | 0.98 |
| `lowSNR` | `SNR_k < snrMin_dB` at any port (SNR of the estimator, sections 4–6) | 20 dB |
| `notSettled` | stepped sine only (1.6.0): `Δ_k − 4·σ_Δ,k > settleDriftMax` at any port, the drift of the channel ratio from the first to the last block beyond four noise standard deviations (section 5 step 7); a step with one block is not judged; sweep and noise results have no such flag | 0.01 |
| `calInvalid` | no valid calibration at this line for all four channels | – |
| `outsideCalibration` | outside the frequency range of the calibration: corrected with the nearest calibrated line, a value for information only (also `calInvalid`; stepped sine: hollow diamonds) | – |
| `nonPassive` | `\|R\| > 1 + passivityTol`, or `\|R\|² + \|τ\|² > 1 + passivityTol` with `\|R_term\| ≤ anechoicRmax` | 0.05 |
| `terminationNotAnechoic` | `\|R_term\| > anechoicRmax` (τ, α_d, TL_τ only) | 0.1 |
| `velocityMismatch` | `δ_u > velocityMismatchMax` (Z_t and TL from Z_t only) | 0.10 |

The near-singularity test is applied per pair on the side `k′s > π/2` only; the small-`ks` side
is covered by the spacing limit, the condition number and the phase sensitivity. (A common gate
`f > c/(4·s_max)` used to reject well-conditioned low-`ks` lines of the shorter pair when
`s_short/s_long < 0.4`; formula review acoustics-2 / calval-3. For equal spacings both rules are
identical.) For s = 29 mm the condition-number limit acts only below 94 Hz and the phase
sensitivity below 75 Hz, i.e. outside the default band.

Quantity-specific masks:

* `validR = valid.upstream.valid`. `R` needs **only the upstream pair**:
  `valid.upstream` (fields `measured`, `geometryOK`, `qualityOK`, `valid`, `flags`, `note`)
  requires the upstream wave amplitudes in the band; the spacing limits, mode limit,
  near-singularity, condition number and phase sensitivity of pair 1; coherence and SNR at M1 and
  M2; a valid calibration of the channels in M1 and M2; `|R| ≤ 1 + passivityTol`; and complete
  geometry. Data of M3/M4 (a rigid plug in front of them, a high-TL specimen with low downstream
  SNR, or a failed calibration of the M3/M4 channels) do not reject `R`. `R` is the as-mounted
  reflection coefficient (section 3); `validR` has no termination condition.
* `validTau = valid & complete geometry & |R_term| ≤ anechoicRmax` (also for `α_d` and `TL_τ`).
* `validThinZt = valid & complete geometry & δ_u ≤ velocityMismatchMax` (also for the TL from
  `Z_t`).
* `validated` is the subset of `valid` inside the **experimentally validated** bands
  (`cfg.analysis.validatedBands`), which are empty until the hardware validation (Tests D/E) has
  been carried out and the user enters the bands.

The summary line (`valid.summary`: the note under the "Validity criteria" table of the Validity
view and a line in the message pane) gives the number of frequency lines at each level, then
"N valid (R: M, upstream pair)", then the number of lines rejected by each flag inside the band
("Rejected in the band by: …"). In that table the criteria of both pairs are marked "(R: M1/M2)":
they reject `R` only through their upstream part (`valid.upstream`).

## 9. Units and level references

| Quantity | Unit / reference |
|---|---|
| `p`, `u`, `Z_t`, `ρc` | Pa, m/s, Pa·s/m; `Z_t/(ρc)`, `R`, `τ`, `α_d`, `γ²`, `C_k`, `H_k` dimensionless |
| `k`, `f`, positions | rad/m, Hz, m (mm in the GUI) |
| Sound pressure level | `L_p = 20·log10(p_rms / 20 µPa)` dB SPL (reference value: ISO 1683 [5]); tone of a step: `p_rms = \|Y\|/(√2·sensitivity)` |
| Level at the specimen (section 3C) | incident wave at the front face `L_inc = 20·log10(\|p_inc\|_rms / 20 µPa)` dB SPL; particle velocity at the front face `\|u_L\|` in mm/s rms |
| PSD | `10·log10(G_pp / (20 µPa)²)` dB re (20 µPa)²/Hz, one-sided Welch estimate |
| Without sensitivities | dB re 1 V and dB re 1 V²/Hz |
| `\|H_k\|`, `\|C_k\|` | `20·log10\|·\|` dB; phases in degrees |
| TL, TL_τ | dB (`20·log10` of amplitude ratios) |
| Octave-band summaries | every octave band (`f_c = 1000·2^n` Hz) that overlaps the analysis band; mean over the valid frequency lines in `[f_c/√2, f_c·√2)`; TL as the energy mean `−10·log10(mean \|τ\|²)`; "*" marks a band only partly inside the analysis band (mean over that part only) |

## References

Cited as [n] above and in the Formula tab (section 13, the same text). The constants taken from
ISO 10534-2 (`c`, the attenuation `1.94·10⁻²`, `f·D < 0.58c`, `f·s < 0.45c`, `s > 5 %` of the
wavelength) are those of the 1998 edition; the 2023 edition and the 2024 editions of the ASTM
standards were not checked against them (checked 2026-10-12: ISO 10534-2:1998 is withdrawn,
E1050-24 and E2611-24 are the active ASTM editions).

Standards

* [1] ISO 10534-2:1998, Acoustics – Determination of sound absorption coefficient and impedance in
  impedance tubes – Part 2: Transfer-function method. Withdrawn; revised as ISO 10534-2:2023,
  Acoustics – Determination of acoustic properties in impedance tubes – Part 2: Two-microphone
  technique for normal sound absorption coefficient and normal surface impedance.
* [2] ASTM E1050, Standard test method for impedance and absorption of acoustical materials using
  a tube, two microphones and a digital frequency analysis system (current edition E1050-24).
* [3] ASTM E2611, Standard test method for normal incidence determination of porous material
  acoustical properties based on the transfer matrix method (current edition E2611-24).
* [4] IEEE Std 1057-2017, IEEE standard for digitizing waveform recorders (3-parameter sine fit).
* [5] ISO 1683:2015, Acoustics – Preferred reference values for acoustical and vibratory levels.

Literature

* [6] A. F. Seybert and D. F. Ross (1977), Experimental determination of acoustic properties using
  a two-microphone random-excitation technique, J. Acoust. Soc. Am. 61, 1362–1370.
* [7] J. Y. Chung and D. A. Blaser (1980), Transfer function method of measuring in-duct acoustic
  properties. I. Theory; II. Experiment, J. Acoust. Soc. Am. 68, 907–913 and 914–921.
* [8] B. H. Song and J. S. Bolton (2000), A transfer-matrix approach for estimating the
  characteristic impedance and wave numbers of limp and rigid porous materials, J. Acoust. Soc.
  Am. 107, 1131–1152.
* [9] J. S. Bolton, T. Yoo and O. Olivieri (2007), Measurement of normal incidence transmission
  loss and other acoustical properties of materials placed in a standing wave tube, Brüel & Kjær
  Technical Review No. 1.
* [10] M. L. Munjal (2014), Acoustics of ducts and mufflers, 2nd ed., Wiley.
* [11] G. Kirchhoff (1868), Ueber den Einfluss der Wärmeleitung in einem Gase auf die
  Schallbewegung, Ann. Phys. Chem. 134, 177–193.
* [12] C. Zwikker and C. W. Kosten (1949), Sound absorbing materials, Elsevier.
* [13] H. Tijdeman (1975), On the propagation of sound waves in cylindrical tubes, J. Sound Vib.
  39, 1–33.
* [14] M. R. Stinson (1991), The propagation of plane sound waves in narrow and wide circular
  tubes, and generalization to uniform tubes of arbitrary cross-sectional shape, J. Acoust. Soc.
  Am. 89, 550–558.
* [15] W. Sutherland (1893), The viscosity of gases and molecular force, Phil. Mag. (5) 36,
  507–531.
* [16] J. S. Bendat and A. G. Piersol (2010), Random data: analysis and measurement procedures,
  4th ed., Wiley.
* [17] P. D. Welch (1967), The use of fast Fourier transform for the estimation of power spectra:
  a method based on time averaging over short, modified periodograms, IEEE Trans. Audio
  Electroacoust. 15, 70–73.
* [18] S. Müller and P. Massarani (2001), Transfer-function measurement with sweeps, J. Audio Eng.
  Soc. 49, 443–471.
