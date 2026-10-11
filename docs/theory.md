# Theory, conventions and methods

This document defines every convention used in the code (`+tim/+acoustics`, `+tim/+dsp`,
`+tim/+cal`, `tim.app.processMeasurement`) and derives the formulas that are implemented. All
quantities are SI. The GUI tab **Formula** (`tim.gui.equationsPanel`) shows the same equations in
short form, with the default thresholds read from `tim.app.defaultConfig` at run time.

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

    c   = 343.2 m/s · √(T / 293 K)                         ISO 10534-2
    ρ   = p_s / (287.05 J/(kg K) · T)                      ideal gas, dry air (R/M, M = 28.9647 g/mol)
    μ   = 1.716·10⁻⁵ Pa s · (T/273.15 K)^{3/2} · 383.55 K / (T + 110.4 K)     Sutherland
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

**`'kirchhoff'` (default).** Visco-thermal wall losses of a wide tube (Kirchhoff 1868; first order
of the Zwikker–Kosten circular-tube model, Tijdeman 1975, Stinson 1991). With the viscous boundary
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
attenuation. It keeps `Re k = ω/c`, i.e. it omits the phase-velocity reduction of equal magnitude.
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

*First lab data (empty 75 mm section, 20261009_192503_sweep, CAL-20261009-191631, T entered
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

On each side of the specimen the field between the microphones and the specimen is

    p(x) = A·exp(−jkx) + B·exp(+jkx),       u(x) = (A·exp(−jkx) − B·exp(+jkx)) / Z_c

The velocity follows from the linearised Euler equation of the cross-section average,
`jωρ_eff·u = −∂p/∂x`: `u = k/(ωρ_eff)·(A e^{−jkx} − B e^{+jkx})`, and `k/(ωρ_eff) = 1/Z_c` with
`Z_c = √(ρ_eff·K_eff)`. This is exact for the visco-thermal plane mode with the `'kirchhoff'` pair
`(k, Z_c)` and for the lossless model. `'iso10534'` keeps `Z_c = ρc` (ASTM E2611 practice); for a
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

For a pure series element `T = [1 Z_t; 0 1]`, `T12 = Z_t` (`tm.Zseries`).

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

### B. Two-port transfer matrix (scripts only)

`[p_L; u_L] = T [p_R; u_R]` has four unknown complex elements per frequency. One excitation state
gives one vector equation, i.e. two scalar equations. A complete `T` therefore needs **two
independent acoustic states** (ASTM E2611): two terminations (two-load method) or two source
positions. The GUI does not compute `T`; use `tim.acoustics.transferMatrix` from a script.

* **Two-load** (`transferMatrix('twoLoad', resA, resB)`):
  `T = P·Q⁻¹`, `P = [p_L⁽¹⁾ p_L⁽²⁾; u_L⁽¹⁾ u_L⁽²⁾]`, `Q = [p_R⁽¹⁾ p_R⁽²⁾; u_R⁽¹⁾ u_R⁽²⁾]` for loads (1)
  and (2). The column scaling of each load cancels, so relative pressures can be used. `cond(Q)`
  (with the velocity row multiplied by `Z_c`) is reported. If the loads are too similar, `T` is
  undetermined.
* **One-load, symmetric** (`transferMatrix('oneLoadSymmetric', res)`): valid **only** if the
  specimen is reciprocal (`det T = 1`) **and** symmetric (`T11 = T22`). Then, with
  `q = p_L u_R + p_R u_L`: `T11 = T22 = (p_R u_R + p_L u_L)/q`, `T12 = (p_L² − p_R²)/q`,
  `T21 = (u_L² − u_R²)/q`. This is an assumption-based reconstruction, not a general measurement.

From `T` (anechoic-termination equivalents, independent of the actual termination):

    τ_a = 2 / (T11 + T12/Z_c + Z_c·T21 + T22)
    R_a = (T11 + T12/Z_c − Z_c·T21 − T22) / (T11 + T12/Z_c + Z_c·T21 + T22)
    TL  = −20·log10|τ_a|

`τ_a` is the transmitted wave at the rear face over the incident wave at the front face for an
anechoic termination; it differs from the ASTM E2611 `t` only by the phase `e^{−jkd}`.
Diagnostics: `reciprocityError = |det T − 1|`, `symmetryError = |T11 − T22| / (|T11| + |T22|)`.

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

Estimator (`tim.dsp.sweepResponse`), per repetition:

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
   view (grey: not analysed). If the sweep is not found, step 2' is used and a warning says so.
   The sweep must reach beyond the band: it should start at or below `f_lo/1.3` and stop at or
   above `1.1 f_hi` (default 80–5500 Hz for 120–4500 Hz). Closer to the band the gate has no room
   for its ramps at that end: they would fall on the band edges (the lower one at most half as
   long as designed, the start-frequency tone cut close to the band; no ring-down margin above
   `f_hi`), and the lines there would be biased while their coherence stays high, so they would
   remain valid. **An end without that margin therefore gets another edge** (owner decision
   2026-10-11), with exactly the thresholds of the warning (`f_start > f_lo/1.3`,
   `f_stop < 1.1 f_hi`, with `f_lo`, `f_hi` the outer edges of the first and last line):

   * **start**: as without the gate (step 2'), from the detected start of the excitation minus
     10 ms with a 10 ms raised cosine - the output-on transient and the start-frequency tone are
     inside the window, the tone is not cut;
   * **end**: the window is extended past the end of the sweep `t0 + T` by the gate's ring-down
     margin, the sweep law continued beyond `f_stop`: 1 up to `t(1.1 f_hi)`, a raised cosine down
     to `t(1.5 f_hi)` (at least 10 ms, at most to the end of the record). An output-off transient
     later than that stays out.

   `res.diagnostics.excitation(r).gateEnds` records the edge used at each end of every repetition
   (`'gate'`, `'detected start'`, `'ring-down margin'`), and `tim.dsp.sweepResponse` adds a warning
   ("Sweep … too close to the analysis band for the sweep gate: …", in `res.diagnostics.warnings`
   and the calibration log) that names the edge and the margin; `tim.app.validateConfig` reports
   the configured range. The lab range (80–5500 Hz or wider for 120–4500 Hz) keeps the gate at both
   ends: the five lab folders and both lab calibrations give bit-identical results with this rule.

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
   contain it). The extension is therefore used at the end. At the start only step 2'
   applies (there is no ring-down before the sweep); 109–5500 Hz: 12 % → 0.63 % (|R_term| = 0.9).
   A start without margin always contains the output-on click, so the advice stays: let the sweep
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
   frequency line `[f − Δf/2, f + Δf/2)` (`Δf = cfg.analysis.df`, default 2 Hz) and over all
   repetitions.
4. Compute

        H_k^m = Σ Y_k Y_ref* / Σ |Y_ref|²                       (H1)
        γ_k²  = |Σ Y_k Y_ref*|² / (Σ |Y_ref|² · Σ |Y_k|²)

   Because the sums run over neighbouring bins and repetitions, `γ²` is a meaningful consistency
   indicator. It is trivially 1 only for a single bin and a single repetition, which is reported
   as a warning.
5. SNR: the signal energy of the frequency line is compared with the expected energy of the
   background noise measured in the pre-roll (one-sided Welch PSD `G_n,k`, same taper and length):

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
by `FREQ` while the output stays on (phase continuous), and every step is analysed only after
`settleTime`, over `recordTime` (`N_rec` samples).

1. **Frequency.** The generator and LAN-XI clocks differ by up to ~10⁻⁴, so the frequency seen by
   the LAN-XI module is estimated on the reference channel (mean removed, Hann window `w`):

        f̂ = argmax |Σ_m w_m x_ref(t_m) e^{−j2πf t_m}|   over |f − f_nom| ≤ max(5·10⁻⁴ f_nom, 2 f_s/N_rec)

   and used for all channels.
2. **Block fits.** The record is split into `n_b` blocks (`nBlocks`, default 4) of
   `N = ⌊N_rec/n_b⌋` samples. In block `i` a linear least-squares fit on `[cos, −sin, 1]` at `f̂`
   (3-parameter sine fit, IEEE 1057) gives the phasor of every channel:

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
   defaults (0.5 s, 4 blocks, 16384 Hz) `N = 2048` and `f_s/N = 8 Hz`; Test B (1 s, 4 blocks) has
   `f_s/N = 4 Hz`. `snrBroadband_dB = mean_i(|Y|²/2) / residual variance` (all frequencies) is
   also returned.
   The noise level of the stepped-sine Spectrum view is `G_n,k·f_s/N` (`toneLevels.noise_dB =
   spl_dB − snr_dB`).
5. **Repetitions.** `H` is the mean over the repetitions, `γ²` and SNR the minimum, and the
   standard error `√(mean σ_H²)/√n_rep`.

*Change 2026-10-09 (formula review dsp-1/dsp-2/formulatab-10).* The SNR used to divide the
one-sided PSD by 2 and to take the plain median of an unaveraged periodogram (−1.59 dB). Together
the SNR was 4.6 dB too high with the default settings. The corrected estimator has a Monte-Carlo
bias of +0.08 dB (white noise, N_rec = 8192) and +0.01 dB (N_rec = 16384); a stray tone −14 dB
50 Hz away makes it 0.2–0.3 dB conservative. The displayed noise level rose by the same 4.6 dB.

## 6. Noise excitation (scripts only)

The 33220A `FUNC NOIS` is used with Welch H1 estimation (`tim.dsp.welchResponse`, Hann window,
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
| Spacing lower limit (ASTM E1050: s ≥ 1 % of λ) | `0.01·c/s` | 118 Hz |
| Spacing upper limit (ASTM E1050/E2611: `ks ≤ 0.8π`) | `0.40·c/s` | 4.73 kHz |
| ISO 10534-2 spacing rule (`f·s < 0.45c`) | `0.45·c/s` | 5.33 kHz (not applied) |
| Singularity (`ks = π`) | `c/(2s)` | 5.92 kHz |
| ISO 10534-2 diameter rule (`f·D < 0.58c`) | `0.58·c/D` | 6.87 kHz |
| Cut-on of the (1,1) mode | `1.8412·c/(πD) = 0.586·c/D` | 6.94 kHz |

The geometric validity range is

    max(0.01·c/s1, 0.01·c/s2) ≤ f ≤ min(0.40·c/s1, 0.40·c/s2),     f < min(0.58·c/D, f_(1,1)) = 0.58·c/D

`0.58·c/D` is always 1 % below the (1,1) cut-on (`0.58/0.586 = 0.990`), so the ISO diameter rule is
the binding diameter limit. For the lab tube the spacing limit `0.40·c/s` governs; the diameter
rule would bind only for `s < 0.40/0.58·D = 20 mm`. The defaults `lowerFraction = 0.01` and
`upperFraction = 0.40` are configurable. ISO 10534-2 also suggests `s > 5 %` of the wavelength for
better accuracy, which would give 592 Hz here. These are rules of thumb, **not** uncertainty
statements.

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
3. `qualityOK`: coherence and SNR at all four ports, **and a valid complex calibration**. Without
   calibration nothing is ever valid.

`valid = measured & geometryOK & qualityOK & ~nonPassive`. An unknown coherence or SNR (NaN, e.g.
the swept-sine SNR when no repetition had ≥ 0.1 s of noise-only pre-roll, section 4 step 5) fails
its criterion, as in the switching calibration (`tim.cal.switchingCorrection`); before 2026-10-11
it passed silently. `tim.app.validateConfig` reports a sweep pre-roll below 0.15 s. Criteria and
defaults (`cfg.analysis`):

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
| `calInvalid` | no valid calibration at this line for all four channels | – |
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
| Sound pressure level | `L_p = 20·log10(p_rms / 20 µPa)` dB SPL; tone of a step: `p_rms = \|Y\|/(√2·sensitivity)` |
| PSD | `10·log10(G_pp / (20 µPa)²)` dB re (20 µPa)²/Hz, one-sided Welch estimate |
| Without sensitivities | dB re 1 V and dB re 1 V²/Hz |
| `\|H_k\|`, `\|C_k\|` | `20·log10\|·\|` dB; phases in degrees |
| TL, TL_τ | dB (`20·log10` of amplitude ratios) |
| Octave-band summaries | every octave band (`f_c = 1000·2^n` Hz) that overlaps the analysis band; mean over the valid frequency lines in `[f_c/√2, f_c·√2)`; TL as the energy mean `−10·log10(mean \|τ\|²)`; "*" marks a band only partly inside the analysis band (mean over that part only) |

## References

* ISO 10534-2:1998, Acoustics – Determination of sound absorption coefficient and impedance in
  impedance tubes – Part 2: Transfer-function method.
* ASTM E1050, Standard test method for impedance and absorption of acoustical materials using a
  tube, two microphones and a digital frequency analysis system.
* ASTM E2611, Standard test method for normal incidence determination of porous material acoustical
  properties based on the transfer matrix method.
* IEEE 1057, Standard for digitizing waveform recorders (3-parameter sine fit).
* G. Kirchhoff (1868), Ann. Phys. 134; H. Tijdeman (1975), J. Sound Vib. 39, 1–33;
  M. R. Stinson (1991), J. Acoust. Soc. Am. 89, 550–558; C. Zwikker and C. W. Kosten (1949), Sound
  absorbing materials.
