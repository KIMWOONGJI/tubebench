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
| B | stable sinusoid: relative amplitude/phase | `TestDsp/sineFitWithClockOffset`, `TestValidationProcedures/testB` | `testB_singleFrequency` | SNR > 40 dB; repeat scatter < 0.05 dB and < 0.2°; clock offset reported (typically < ±50 ppm) |
| C | switching calibration; consistency before/after correction | `TestCalibration`, `TestEndToEnd/fullSweepWorkflow`, `TestValidationProcedures/testC` | `runCalibration`, `testC_calibrationConsistency` | remounting repeatability < 0.05 dB / 0.2°; independent interchanged measurement agrees after correction to < 0.05 dB and < 0.3° rms |
| D | rigid termination | `TestAcoustics/rigidTermination`, `TestValidationProcedures/testDrigid` | `testDE_reference(res,'rigid')` | after removing the propagation `exp(−2jkL)`: median magnitude deficit −0.02 … 0.05; phase error < 3° rms |
| E | empty through-tube | `TestAcoustics/emptyTube`, `TestValidationProcedures/testEempty` | `testDE_reference(res,'empty')` | `||τ|−1| < 0.02`, τ phase error < 2° rms, `|R − R_term·e^{−2jkd}| < 0.02` (medians, valid bins) |
| F | synthetic waves with known amplitudes, mismatch and noise | `TestAcoustics/*` (exact to 1e-9; Monte-Carlo within the analytic bound), `TestEndToEnd` | – (simulation only) | – |
| G | stepped sine vs log sweep | `TestDsp/steppedVsSweep`, `TestEndToEnd/steppedSineAndCrossMethod` | commissioning section H8 | max `|R_stepped − R_sweep|` < 0.03 over valid bins |

## Tolerance rationale

* **Exact-arithmetic tests** (decomposition, transfer matrix, calibration algebra): 1e-9 … 1e-12
  relative. The limit is round-off amplified by the condition number (≤ 40) and the lossy
  exponentials.
* **Noise propagation** (`TestAcoustics/noisyRecoveryWithinBound`): first-order bound
  `|ΔR| ≤ 2√2·cond·e·(1+|R|)` for a relative pressure noise `e`. The 95th percentile of 50
  Monte-Carlo runs must stay below it.
* **End-to-end**: `δH ≈ 0.3 %` → `|ΔR| ≲ 0.03` for cond ≈ 3 (f > 1 kHz), and up to ≈ 0.3 at
  120 Hz (cond ≈ 31). Tests therefore require max `|ΔR| < 0.03` above 1 kHz and a median below
  0.01 over all valid bins.
* **Hardware criteria** (table above) are starting values derived from typical
  impedance-tube practice. Set the final values for your laboratory once the repeatability of the
  real set-up is known. They are not claims about the achieved accuracy.

## Reference cases for Tests D and E

* **D, rigid plug**: a massive, well-sealed plug with a flat face, normal to the axis, at a
  measured distance L from `xFront`. Theory: `R = exp(−2jkL)·R_wall` with `|R_wall|` ≈ 1. The
  residual deficit is caused by tube attenuation (partly modelled) and by the plug's own losses
  and leaks.
* **E, empty tube**: remove the sample, keep the sample holder. With the configured faces the
  "sample" is an air gap of length d = xRear − xFront. Theory, independent of the termination:
  `τ = exp(−jkd)` (free propagation of the forward wave) and `R = R_term·exp(−2jkd)` (field
  continuity across the gap). `R = 0` only for an anechoic termination, and `Zt → 0` only as
  `d → 0`. The second relation tests the consistency of the upstream and downstream
  decompositions. Large deviations indicate wrong positions or spacing, an uncorrected channel
  phase, or leaks. (An earlier draft of this procedure wrongly stated `R = 0`; the simulation test
  `testEempty` exposed the error.)

## Recording "experimentally validated" bands

After D and E (and G) pass in a frequency band, enter that band in
`config/user_config.json → analysis.validatedBands`, e.g. `[[150, 4000]]`. Only then are results
labelled `validated` in exports and plots. The bands describe the validated performance of **this**
set-up (tube, microphones, mounting, calibration) and must be re-established after changes.
