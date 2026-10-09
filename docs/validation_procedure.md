# Validation procedure (Tests A–G)

Every test exists in two forms:

* **Simulation** (automatic, `run_tests`): verifies the software and the procedure against the
  virtual rig, whose ground truth is known.
* **Hardware** (`examples/hardware_commissioning.m`, functions `tim.val.*`): the physical test.
  A hardware test counts as passed **only** after it has been run on the real set-up and its
  result recorded. The current status is in `hardware_status.md`.

Tolerances are stated with their rationale. Simulated noise is 2 mPa rms per microphone against an
incident wave of ≈0.4 Pa (≈ 86 dB SPL), i.e. > 40 dB SNR per 2 Hz band.

| Test | What | Simulation test | Hardware function | Pass criteria (hardware) |
|---|---|---|---|---|
| A | channel identification, units, continuity, sample rate, packet integrity, overload | `TestStreamParser`, `TestInstruments`, `TestValidationProcedures/testA` | `testA_acquisition`, `channelIdentification` | integrity OK (no corrupt / gap / overrun / INVALID / clipped); unit V; fs as configured; tap test maps every port to the configured channel by > 6 dB |
| B | stable sinusoid: relative amplitude/phase | `TestDsp/sineFitWithClockOffset`, `TestDsp/sineFitSnrUnbiased`, `TestValidationProcedures/testB` | `testB_singleFrequency` | SNR > 40 dB per 0.25 s block (narrow-band SNR of the sine fit, noise bandwidth 4 Hz; since 2026-10-09 an unbiased value, before it read 3.5 dB high); repeat scatter < 0.05 dB and < 0.2°; clock offset reported (typically < ±50 ppm) |
| C | switching calibration; consistency before/after correction | `TestCalibration`, `TestEndToEnd/fullSweepWorkflow`, `TestValidationProcedures/testC` | `runCalibration`, `testC_calibrationConsistency` | remounting repeatability < 0.05 dB / 0.2°; independent interchanged measurement agrees after correction to < 0.05 dB and < 0.3° rms |
| D | rigid termination | `TestAcoustics/rigidTermination`, `TestAcoustics/rigidPlugUpstreamOnly`, `TestValidationProcedures/testDrigid` | `testDE_reference(res,'rigid')` | after removing the propagation `exp(−2jkL)`: median magnitude deficit −0.02 … 0.05; phase error < 3° rms (upstream-pair frequency lines, no passivity screen; `nonPassiveBins` reported) |
| E | empty-tube check (empty specimen section) | `TestAcoustics/emptyTube`, `TestAcoustics/emptySection75mm`, `TestValidationProcedures/testEempty` | `testDE_reference(res,'empty')`; automatic at the end of `runCalibration` | `\|\|τ\|−1\| < 0.02`, τ phase error < 2° rms, `\|R − R_term·e^{−2jkd}\| < 0.02` (medians over the frequency lines that meet the geometry and quality criteria, no passivity screen) |
| F | synthetic waves with known amplitudes, mismatch and noise | `TestAcoustics/*` (exact to 1e-9; Monte-Carlo within the analytic bound), `TestEndToEnd` | – (simulation only) | – (verifies the algebra only; see below) |
| G | stepped sine vs log sweep | `TestDsp/steppedVsSweep`, `TestEndToEnd/steppedSineAndCrossMethod` | commissioning section H8 | max `\|R_stepped − R_sweep\|` < 0.03 over the valid frequency lines |

## Tolerance rationale

* **Exact-arithmetic tests** (decomposition, transfer matrix, calibration algebra): 1e-9 … 1e-12
  relative. The limit is round-off amplified by the condition number (≤ 40) and the lossy
  exponentials. **Test F checks the algebra only**: the virtual tube (`tim.sim.tubeModel`) builds the
  field with the same air properties, wavenumber and `Z_c` as the analysis, so any error in those
  models cancels in the round trip. The independent check of the tube physics is
  `TestAcoustics/kirchhoffMatchesExactTube`: the default loss model against the exact
  visco-thermal circular-tube solution (Bessel functions), `k` and `Z_c` within 2·10⁻⁴ and a thin
  element of `|Z_t|/(ρc) ≈ 0.05` within 0.1 %. On hardware, Tests D and E check the physics.
* **Noise propagation** (`TestAcoustics/noisyRecoveryWithinBound`): first-order bound
  `|ΔR| ≤ 2√2·cond·e·(1+|R|)` for a relative pressure noise `e`. The 95th percentile of 50
  Monte-Carlo runs must stay below it.
* **End-to-end**: `δH ≈ 0.3 %` → `|ΔR| ≲ 0.03` for cond ≈ 3 (f > 1 kHz), and up to ≈ 0.3 at
  120 Hz (cond ≈ 31). Tests therefore require max `|ΔR| < 0.03` above 1 kHz and a median below
  0.01 over all valid frequency lines.
* **Hardware criteria** (table above) are starting values derived from typical
  impedance-tube practice. Set the final values for your laboratory once the repeatability of the
  real set-up is known. They are not claims about the achieved accuracy.

## Reference cases for Tests D and E

Both tests compare with the wavenumber of the analysis (`res.analysis.k`, i.e.
`cfg.analysis.lossModel`, default `'kirchhoff'`).

* **D, rigid plug**: a massive, well-sealed plug with a flat face, normal to the axis, at a
  measured distance L downstream of `xFront`. Theory: `R = exp(−2jkL)·R_wall` with `|R_wall|` ≈ 1.
  The residual deficit is caused by tube attenuation (partly modelled) and by the plug's own losses
  and leaks.
  * **`R` needs only the upstream pair M1/M2**, and Test D selects its frequency lines with the
    upstream-only masks (`res.analysis.valid.upstream`: in band, pair-1 geometry, coherence and SNR
    at M1 and M2, calibration). The plug may therefore sit in the specimen section, face at
    `xFront` (L = 0), with M3/M4 behind it recording only background noise. Condition: the
    **reference channel must be at M1 or M2** (otherwise the upstream coherence is lost and
    `r.warning` says so).
  * The passivity screen is **not** applied: an over-unity `|R|` must count in the median deficit,
    not be dropped. The number of lines with `|R| > 1 + passivityTol` is reported as
    `nonPassiveBins`.
  * Alternatively the plug can be the termination downstream of M4 with the empty specimen section
    mounted (`L = x_plug − xFront`); pressure nodes at M3/M4 then do not matter either.
  * In the virtual tube a microphone behind the termination plane receives no sound (p = 0,
    `out.behindTermination`); the standing wave is not continued past the plug.
* **E, empty-tube check**: mount the empty specimen section (lab tube: the original 75 mm part,
  without specimen), so the tube is continuous. With the configured faces the "specimen" is an air
  column of thickness d = xRear − xFront = 75 mm. Theory, independent of the termination:
  `τ = exp(−jkd)` (free propagation of the forward wave, lossy wavenumber) and
  `R = R_term·exp(−2jkd)` (field continuity across the section). `R = 0` only for an anechoic
  termination. Expected values for d = 75 mm, D = 29 mm, 20 °C:

  | | 120 Hz | 1 kHz | 4.5 kHz |
  |---|---|---|---|
  | \|τ\| (`'kirchhoff'`, default) | 0.9983 | 0.9952 | 0.9898 |
  | τ phase (`'kirchhoff'`) | −9.53° | −78.93° | −354.52° |
  | TL_τ (`'kirchhoff'`) | 0.015 dB | 0.042 dB | 0.089 dB |
  | τ phase (`'iso10534'`, `Re k = ω/c`) | −9.44° | −78.65° | −353.93° |

  The thin-element Z_t is NOT a criterion here: for 75 mm the thin model gives
  `Z_t/Z_c = 2j·tan(kd/2)` (pole at 2.29 kHz) and the velocity-mismatch mask rejects it except near
  `Re(k)·d = 2π` (4.57 kHz). Because A2 = A1 and B2 = B1 in a continuous tube, both relations
  depend only on the microphone coordinates (s1, s2, x3 − x2 = L1 + d + L2) and the calibration –
  about 1° per mm at 1 kHz – not on how L1 / d / L2 are split. Large deviations indicate wrong
  positions or spacing, a specimen section taken out, an uncorrected channel phase, or leaks.
  **`runCalibration` performs this test automatically** after the switching steps
  (`cal.meta.emptyCheck`). The frequency lines are those that meet the geometry and quality
  criteria, without the passivity screen. (An earlier draft of this procedure wrongly stated
  `R = 0`; the simulation test `testEempty` exposed the error.) Note that Test E cannot tell the
  loss models apart: analysed with `'iso10534'`, a real (visco-thermal) tube deviates from the
  expectation by at most 1.4° in the τ phase up to 4 kHz, inside the 2° criterion. The difference
  matters for thin elements of low impedance (`theory.md` section 3A).

## Recording "experimentally validated" bands

After D and E (and G) pass in a frequency band, enter that band in
`config/user_config.json → analysis.validatedBands`, e.g. `[[150, 4000]]`. Only then are results
labelled `validated` in exports and plots. The bands describe the validated performance of **this**
set-up (tube, microphones, mounting, calibration) and must be re-established after changes.
