# Assumptions, known limitations and recommendations

## Assumptions

**Physics**

1. Linear, time-invariant tube and sample during each measurement (the loudspeaker may be
   non-linear).
2. Plane-wave propagation between each microphone pair and the adjacent sample face. This holds
   below the (1,1) cut-on (6.94 kHz for d = 29 mm) and outside the near field of the sample and the
   loudspeaker. ISO 10534-2 recommends microphones ≥ 1–2 diameters from the sample surface, a
   recommendation for **your** geometry.
3. Tube wall losses follow the empirical ISO 10534-2 attenuation constant (`lossModel =
   'iso10534'`), with `Zc = ρc` (the dispersion of Zc is neglected), or no losses at all (`'none'`).
4. Air properties from the ISO 10534-2 formulas. Humidity is neglected (≈ 0.1–0.3 % on c). Enter
   the measured temperature and pressure.
5. The same medium and cross-section on both sides of the sample (power coefficients, TL).
6. Thin-element `Zt`: negligible thickness and approximately continuous velocity. This is checked
   (`velocityMismatch`), never enforced.
7. One-load transfer matrix: reciprocal and symmetric sample (stated assumption). The two-load
   method needs only linearity, plus two sufficiently different loads.
8. `τ` from the wave amplitudes is the intrinsic transmission coefficient only for an anechoic
   termination (`|Rterm|` ≤ 0.1).

**Instrumentation**

9. The four LAN-XI channels share one sample clock, so their relative timing is exact. This is a
   property of a single LAN-XI module. Generator and DAQ do **not** share a clock, and the method
   does not need them to.
10. The complete microphone chains are stable between calibration and measurement (same cables,
    channels, range, filter, sample rate, temperature within a few K).
11. Sensor switching: microphones are interchanged without changing cables or channels, the sound
    field is identical in configurations I and II (no leaks, same insertion depth), and the
    chains differ in phase by < 90° at low frequency (branch rule; polarity reversal cannot be
    detected).
12. The LAN-XI stream is configured in volts (default transducer, sensitivity 1). The sensitivity
    is applied once in software. Verified on the real module (stream unit "V").

## Known limitations

* **Geometry not yet provided**: microphone positions and sample faces are unknown, so boundary
  quantities are disabled until they are entered.
* **Hardware-dependent functions are partly unverified**. See `hardware_status.md`: generator
  output, sweep triggering, the microphone signal chain, TEDS and calibration on hardware are
  **pending**. No physical accuracy is claimed.
* **First hardware acquisition flagged INVALID on all channels** (microphones apparently not
  connected / connector selection). This must be resolved before any acoustic test.
* Periodic **multisine** excitation (33220A arbitrary waveform) is not implemented. Noise
  excitation is implemented with Welch H1.
* The trigger timing is software-based. The 33220A Trig Out and Sync outputs are not recorded,
  because the LAN-XI 3676 has only four inputs, all used by the microphones. The excitation
  interval is therefore detected acoustically.
* The stream timestamp semantics ("time of first sample") are not documented by HBK. Timestamps
  are only used as a continuity diagnostic.
* Raw stream bytes are stored for the **last** repetition of each measurement. All repetitions are
  stored as decoded volts. The decoder is deterministic and HW-verified bit-identical.
* `|Rterm|` > 0.1 makes `τ` and `α` invalid. For reflecting terminations use the two-load transfer
  matrix.
* The calibration is not temperature compensated. Re-calibrate after temperature changes > 3 K.
* Uncertainty: the software reports diagnostics (condition number, coherence, SNR, phase
  sensitivity, calibration repeatability, block scatter for stepped sine) but **no complete
  uncertainty budget** (GUM). The tolerances in `validation_procedure.md` are not uncertainty
  statements.
* GUI: a programmatic `uifigure` application. No `.mlapp` file is provided, because App Designer
  binary files cannot be produced reliably from source. The GUI is optional and less flexible
  than the scripts (for example, the two-load transfer matrix is scripted only).
* Simulation: the virtual rig models the loudspeaker as an ideal incident-wave source, with no
  source reflection or tube resonances on the upstream side. That is sufficient for estimator and
  decomposition tests, but not a model of the real tube.

## Recommendations for future development

1. Measure the geometry (micrometer/caliper; acoustic centre of the 4957 relative to its holder)
   and enter it; then run Tests D/E and populate `validatedBands`.
2. Add an uncertainty budget (Monte-Carlo propagation of position, temperature, calibration and
   noise uncertainties through `analyzeFourMic`; the noise part already exists in the tests).
3. Two-source (source switching) transfer-matrix method, as an alternative to the two-load method.
4. Optional hardware synchronisation: a second LAN-XI input channel, or a module with more inputs,
   to record the generator Sync/Trig Out (useful for impulse-response windowing, not needed for
   the current method).
5. Periodic multisine via the 33220A arbitrary waveform (`DATA VOLATILE`, `FUNC:USER`), giving
   leakage-free periodic averaging.
6. Automatic level control: increase the amplitude in steps until a target SNR or headroom is
   reached.
7. Temperature/humidity sensor logging per measurement.
8. Mean-flow corrections if the tube is ever used with flow.
9. **Standalone application (deferred until development is largely complete, decided
   2026-10-08).** The lab license includes MATLAB Compiler (`license('test','Compiler') = 1`),
   but the toolbox is not installed. Steps: install MATLAB Compiler (Add-On Explorer); add a
   build script (`compiler.build.standaloneApplication` for `tim.gui.TubeApp`). Make paths
   deployment-aware: when `isdeployed`, config/data/calibration must live next to the exe or in
   the user's Documents folder, not under the project root. Include `tests/fixtures` (needed by
   the simulation mode) and the example config. Target PCs need the free MATLAB Runtime
   **R2022b**. Command-window prompts (`input`) are script-only; the GUI uses dialogs.
