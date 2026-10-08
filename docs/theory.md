# Theory, conventions and methods

This document defines every convention used in the code (`+tim/+acoustics`, `+tim/+dsp`,
`+tim/+cal`) and derives the formulas that are implemented. All quantities are SI.

## 1. Conventions

| Item | Convention |
|---|---|
| Time dependence | `exp(+jωt)` |
| Axis | `x` increases from the loudspeaker towards the termination; M1 is nearest the loudspeaker |
| Forward (incident, downstream) wave | `A·exp(−jkx)` |
| Backward wave | `B·exp(+jkx)` |
| Particle velocity `u` | positive towards `+x` |
| Attenuation | `k = k′ − jk″`, `k″ ≥ 0` |
| Transfer matrix | `[p_L; u_L] = T·[p_R; u_R]`; L = front (upstream) face, R = rear (downstream) face |
| Relative channel response | `H_c = Y_c / Y_ref` (ref = `cfg.analysis.refChannel`, default 1) |
| Calibration factor | `C_k = c_k / c_ref` (complete chain k over reference chain); corrected `H_k = H_k,meas / C_k` |
| Phasor from sine fit | `x(t) = Re{a·exp(jωt)}` |

Air: `c0 = 343.2·sqrt(T/293)`, `ρ0 = 1.186·(pa/101325)·(293/T)` (ISO 10534-2), `Zc = ρ0·c0`.
Tube losses (option `lossModel = 'iso10534'`): `k″ = 1.94·10⁻²·√f /(c0·d)`; `'none'` gives the lossless model.

## 2. Two-microphone plane-wave decomposition

On each side of the sample the field between the microphones and the sample is

    p(x) = A·exp(−jkx) + B·exp(+jkx),       u(x) = (A·exp(−jkx) − B·exp(+jkx)) / Zc

(the expression for `u` follows from `jωρ u = −∂p/∂x`). With two pressures `p_a, p_b` at `x_a, x_b`:

    [p_a; p_b] = M [A; B],   M = [e^{−jkx_a}  e^{+jkx_a}; e^{−jkx_b}  e^{+jkx_b}]
    det M = 2j·sin(k(x_b − x_a))
    A = (p_a e^{jkx_b} − p_b e^{jkx_a}) / det M
    B = (p_b e^{−jkx_a} − p_a e^{−jkx_b}) / det M

`det M = 0` when `k·s = nπ` (`s = |x_b − x_a|`), i.e. at `f = n·c/(2s)` ≈ 5.92 kHz for s = 29 mm.
The 2-norm condition number of the lossless pair matrix is `max(|cot(ks/2)|, |tan(ks/2)|)`. It is
reported per frequency (`waves.cond1`, `waves.cond2`) in pair-local coordinates and is ≈31 at 120 Hz,
≈3.7 at 1 kHz and 1 at `ks = π/2` (≈ 2.96 kHz).

Only *ratios* of pressures are needed: if all `p_m` are scaled by the same complex factor (the
unknown absolute pressure of the reference channel), `A` and `B` scale with it. `R`, `τ`, `Zt` and
`T` are all ratios and are therefore independent of that factor.

### Boundary-plane extrapolation

With `A1, B1` from M1/M2 and `A2, B2` from M3/M4 (global coordinates):

    p_L = p(x_front) and u_L = u(x_front) from (A1, B1);   p_R = p(x_rear) and u_R = u(x_rear) from (A2, B2)

The extrapolation assumes plane waves in air between the microphones and the faces, with the
configured loss model. **Positions are never invented**: when they are missing
(`geometry.micPositions` or `xFront/xRear` = NaN), only the pair-local reflection coefficients are
computed: `local.R_up_atM2` (upstream, at the plane of M2) and `local.R_dn_atM3` (downstream, at
the plane of M3). Boundary quantities are then NaN and every boundary validity mask is false.

## 3. Sample quantities

### Reflection and transmission (pressure amplitude coefficients)

    R     = B1 e^{+jk x_front} / (A1 e^{−jk x_front})       reflection at the front face
    τ     = A2 e^{−jk x_rear}  / (A1 e^{−jk x_front})       forward wave at the rear face / incident at the front face
    Rterm = B2 e^{+jk x_rear}  / (A2 e^{−jk x_rear})        reflection of everything downstream, referred to the rear face

`τ` equals the intrinsic transmission coefficient of the sample **only for an anechoic
termination** (`Rterm ≈ 0`). Otherwise waves returning from the termination are re-reflected by the
sample's rear face and contaminate `A2`. The mask `valid.validTau` therefore requires
`|Rterm| ≤ cfg.analysis.anechoicRmax` (0.1 by default). Termination-independent transmission
quantities come from the transfer matrix (section 4).

Power quantities, assuming the same medium and cross-section on both sides:
`|R|²` (reflected power fraction), `|τ|²` (transmitted power fraction) and
`α = 1 − |R|² − |τ|²` (dissipated fraction, meaningful only for an anechoic termination).
Passivity checks: `|R| ≤ 1 + tol`, and `|R|² + |τ|² ≤ 1 + tol` when `|Rterm|` is small. Bins that
violate them are flagged `nonPassive` and are never valid.

### A. Thin-element transfer impedance

For a lumped element of negligible thickness, across which the normal particle velocity is
(approximately) continuous:

    Zt = (p_L − p_R) / u,      u = (u_L + u_R)/2   (cfg.analysis.velocityRef = 'mean'; or 'upstream' / 'downstream')
    velocity mismatch δu = |u_L − u_R| / max(|u_L|, |u_R|)

Continuity is **not** enforced. `δu` is reported per frequency, and `valid.validThinZt` requires
`δu ≤ velocityMismatchMax` (default 0.10). For a thick or compressible sample `δu` is large. The
simulated 10 mm porous layer gives `δu > 0.1` in more than 90 % of the band. In that case use the
transfer matrix instead.

For a pure series element `T = [1 Zt; 0 1]`, `T12 = Zt` (`tm.Zseries`).

**Transmission loss from Zt** (`res.thin.TL_dB`). Inserting `T = [1 Zt; 0 1]` into the
anechoic-termination transmission coefficient (section 4) gives `τ = 2/(2 + Zt/Zc)`, hence

    TL = −20·log10|τ| = 20·log10|1 + Zt/(2·Zc)|

This assumes equal cross-sections on both sides. Because `Zt` itself does not depend on the
termination, this TL is the anechoic-equivalent TL even when the real termination reflects. It
carries the validity of `Zt` (`valid.validThinZt`). For comparison, `res.power.TL_tau_dB =
−20·log10|τ|` uses the measured τ directly and is valid only for an anechoic termination
(`valid.validTau`). In simulation, a 3 % termination reflection already makes the τ-based curve
ripple, while the Zt-based curve stays smooth.

### B. Two-port transfer matrix

`[p_L; u_L] = T [p_R; u_R]` has four unknown complex elements per frequency. One excitation state
gives one vector equation, i.e. two scalar equations. A complete `T` therefore needs **two
independent acoustic states** (ASTM E2611): two terminations (two-load method) or two source
positions.

* **Two-load** (`transferMatrix('twoLoad', resA, resB)`):
  `T = P·Q⁻¹`, `P = [p_L,a p_L,b; u_L,a u_L,b]`, `Q = [p_R,a p_R,b; u_R,a u_R,b]`.
  The column scaling of each load cancels, so relative pressures can be used. `cond(Q)` (with the
  velocity rows multiplied by `Zc`) is reported. If the loads are too similar, `T` is undetermined.
* **One-load, symmetric** (`transferMatrix('oneLoadSymmetric', res)`): valid **only** if the
  sample is reciprocal (`det T = 1`) **and** symmetric (`T11 = T22`). Then
  `D = p_L u_R + p_R u_L`, `T11 = T22 = (p_R u_R + p_L u_L)/D`, `T12 = (p_L² − p_R²)/D`,
  `T21 = (u_L² − u_R²)/D`. This is an assumption-based reconstruction, not a general measurement.

From `T` (anechoic-termination equivalents, independent of the actual termination):

    τ_a = 2 / (T11 + T12/Zc + Zc·T21 + T22)
    R_a = (T11 + T12/Zc − Zc·T21 − T22) / (T11 + T12/Zc + Zc·T21 + T22)
    TL  = −20·log10|τ_a|

Diagnostics: `reciprocityError = |det T − 1|`, `symmetryError`.

## 4. Swept-sine estimator without generator synchronisation

The 33220A and the LAN-XI have independent clocks. The sweep is BUS-triggered by software, so its
start is uncertain by the network/stream latency and the generator trigger latency. The manual
gives no explicit sweep law and states that the sweep is made of discrete frequency steps. The
estimator therefore **never uses the excitation signal**.

For a linear time-invariant tube, every DAQ channel c records

    Y_c(f) = P(x_c, f) · c_c(f) · S(f)

where `S(f)` is the (unknown) spectrum of the loudspeaker drive over the analysis window. All four
channels are sampled by the same LAN-XI clock, so

    Y_c / Y_ref = [P(x_c)/P(x_ref)] · [c_c / c_ref]

which is independent of `S(f)`. That removes the dependence on:

* the sweep waveform (stepped, non-ideal, linear or logarithmic),
* the start time, trigger latency and generator clock offset/drift,
* loudspeaker/amplifier harmonic distortion. A harmonic of the drive is acoustic excitation at its
  own frequency and propagates through the same linear tube. The tube and sample must be linear;
  the source need not be.
* the start-frequency tone the 33220A emits before and after a triggered sweep.

Estimator (`tim.dsp.sweepResponse`), per repetition r:

1. Detect the excited interval on the reference channel (band-limited short-time RMS, 12 dB above
   the pre-roll background).
2. Cut from the detected start minus 10 ms to the detected end plus a ring-down margin, with 10 ms
   raised-cosine tapers. The acoustic ring-down is included, and truncation leakage is confined to
   segments where the signal has decayed.
3. FFT, then accumulate `G_cr = Y_c Y_ref*`, `G_rr = |Y_ref|²` and `G_cc = |Y_c|²` over all FFT
   bins inside each output band (width `df`, default 2 Hz) and over all repetitions.
4. Compute `H_c = ΣG_cr / ΣG_rr` (H1) and `γ²_c = |ΣG_cr|² / (ΣG_rr ΣG_cc)`. Because the
   averages run over neighbouring bins and repetitions, `γ²` is a meaningful consistency
   indicator. It is trivially 1 only for a single bin and a single repetition, which is reported
   as a warning.
5. SNR: the signal energy in the band is compared with the expected energy of the background
   noise measured in the pre-roll (Welch PSD, same window and length:
   `E|N|² = G_noise/2 · fs · Σw²`). Repetitions without ≥ 0.1 s of clean pre-roll are excluded
   from the SNR and reported.

Clock drift between DAQ and generator does not enter. Drift of the DAQ clock itself is common to
all channels.

**Verification (simulation)**: the virtual rig uses a stepped log sweep with a +35 ppm clock
offset, random trigger latency of 5–30 ms, loudspeaker high-pass and per-channel complex mismatch.
Relative responses agree with the realised responses to a median error of 0.26 % at 2 mPa noise
(`TestDsp`). A noise-free linear sweep agrees to within 0.2 % at the 99th percentile, which
demonstrates the excitation independence.

## 5. Stepped sine

`tim.dsp.sineResponse`: after the settling time, the DAQ-observed frequency is estimated on the
reference channel by maximising the Hann-windowed DTFT, because the generator and DAQ clocks
differ by up to ~10⁻⁴. The complex amplitudes of all channels are then obtained by a linear
3-parameter least-squares sine fit (IEEE 1057) in `nBlocks` blocks. The block scatter gives the
standard error. The frequency is switched by `FREQ` while the output stays on (phase continuous),
and every step is analysed only after `settleTime`.

## 6. Noise excitation (optional mode C)

The 33220A `FUNC NOIS` is used with Welch H1 estimation (`tim.dsp.welchResponse`; note that
MATLAB's `cpsd(a,b) = ⟨A·conj(B)⟩`, so `H = cpsd(x_c, x_ref) / pwelch(x_ref)`). The periodic
multisine (arbitrary waveform) mode is **not** implemented; see `assumptions_and_limitations.md`.

## 7. Frequency limits

`tim.acoustics.frequencyLimits(d, s, air)` gives, for d = s = 29 mm at 20 °C (c = 343.3 m/s):

| Limit | Formula | Value |
|---|---|---|
| Spacing lower limit (ASTM E1050: s ≥ 1 % of λ) | `0.01·c/s` | 118 Hz |
| Spacing upper limit (ASTM E1050/E2611: `ks ≤ 0.8π`) | `0.40·c/s` | 4.73 kHz |
| ISO 10534-2 spacing rule (`f·s < 0.45c`) | `0.45·c/s` | 5.33 kHz |
| Singularity (`ks = π`) | `c/(2s)` | 5.92 kHz |
| First higher-order mode (1,1) cut-on | `1.8412·c/(πd)` | 6.94 kHz |
| ISO 10534-2 diameter rule | `0.58·c/d` | 6.87 kHz |

The defaults `lowerFraction = 0.01` and `upperFraction = 0.40` are configurable. ISO 10534-2 also
suggests `s > 5 %` of the wavelength for better accuracy, which would give 592 Hz here. These are
rules of thumb, **not** uncertainty statements.

Low-frequency phase sensitivity: a residual inter-channel phase error `δφ` gives a relative error
of order `δφ/(ks)` in the decomposed waves. With `phaseUncertainty_rad = 0.002` this is 3 % at
120 Hz; bins above `maxPhaseSensitivity` (5 %) are flagged.

## 8. Validity levels

`res.analysis.valid` keeps three levels strictly separate:

1. `measured`: inside the analysis band, finite data;
2. `geometryOK`: spacing limits, mode cut-on, singularity proximity, condition number ≤ `condMax`,
   low-frequency phase sensitivity;
3. `qualityOK`: coherence ≥ `coherenceMin`, SNR ≥ `snrMin_dB` on all channels, **and a valid
   complex calibration**. Without calibration nothing is ever valid.

`valid = measured & geometryOK & qualityOK & ~nonPassive`, plus the quantity-specific masks
`validR`, `validTau` and `validThinZt`. `validated` is the subset that lies inside the
**experimentally validated** bands (`cfg.analysis.validatedBands`), which are empty until the
hardware validation (Tests D/E) has been carried out and the user enters the bands.
