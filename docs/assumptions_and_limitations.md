# Assumptions, known limitations and recommendations

## Assumptions

**Physics**

1. Linear, time-invariant tube and specimen during each measurement (the loudspeaker may be
   non-linear).
2. Plane-wave propagation between each microphone pair and the adjacent specimen face. This holds
   below the ISO 10534-2 diameter limit `0.58·c/D` (6.87 kHz for the inner diameter D = 29 mm; the
   (1,1) mode cuts on 1 % higher, at 6.94 kHz) and outside the near field of the specimen and the
   loudspeaker. ISO 10534-2 recommends microphones ≥ 1–2 diameters from the specimen surface, a
   recommendation for **your** geometry.
3. Tube wall losses (`cfg.analysis.lossModel`):
   * `'kirchhoff'` (default): visco-thermal wall losses of a wide tube, first order of the
     Zwikker–Kosten model: `k = ω/c + (1 − j)·k″`, `k″ = C_w·√f/(c·D)`,
     `C_w = 2√(πν)·(1 + (κ − 1)/√Pr)` = 2.03·10⁻² m·s^−1/2 at 20 °C, and the matching
     characteristic impedance `Z_c = ρc·[1 + (1 − j)·Ψ·k″/k0]`, `Ψ = 0.356`. `Re k` includes the
     phase-velocity reduction, which is as large as the attenuation. Against the exact
     circular-tube solution the error is about 10⁻⁴ in `k` and `Z_c` and below 0.1 % in a
     thin-element `Z_t` (`TestAcoustics/kirchhoffMatchesExactTube`). It needs `a/δ_v ≫ 1`
     (radius over viscous boundary layer; 66 at 100 Hz for D = 29 mm).
   * `'iso10534'`: the empirical ISO 10534-2 attenuation `k = ω/c − j·1.94·10⁻²·√f/(c·D)` with
     `Z_c = ρc`. It is the ISO-conformant option for absorption work. It omits the phase-velocity
     reduction, which biases a thin-element `Z_t` by about `k″·(x3 − x2)·ρc` (≈ 0.02ρc at 4.5 kHz
     in the lab tube): up to about 47 % at `|Z_t|/(ρc) = 0.05`, 12 % at 0.2 and 2 % at 1 (lab tube,
     120 Hz–4.5 kHz); the effect on `|R|` is below 0.008.
   * `'none'`: no losses (thin-element `Z_t` error about 0.03ρc at 4.5 kHz, up to about two thirds
     of `Z_t` at `|Z_t|/(ρc) = 0.05`).

   `'iso10534'` and `'none'` give a "CHECK:" warning. Configurations saved before `'kirchhoff'`
   became the default (2026-10-09) still name `'iso10534'`.
4. Air properties: `c = 343.2 m/s·√(T/293 K)` (ISO 10534-2) and the ideal-gas density of dry air
   `ρ = p_s/(287.05 J/(kg K)·T)` = 1.2041 kg/m³ at 20 °C and 101.325 kPa. (Until 2026-10-09 the ISO
   expression `1.186·(p_s/101325)·(293/T)` was used; it is 1.55 % low, so absolute `Z_t`, `T12` and
   `T21` in Pa·s/m are now 1.6 % higher than before. Normalised quantities are unchanged.)
   Humidity is neglected: at 20 °C and 50 % RH, `c` is 0.18 % higher and `ρ` 0.44 % lower than for
   dry air. Enter the measured temperature and static pressure. For thin elements of low impedance
   these errors are amplified: `|ΔZ_t|/(ρc) ≈ |δφ_interpair| + |Δk′|·(x3 − x2)`, an absolute error
   (0.18 % on `c` gives about 9–12 % in `Z_t` at 1–4 kHz for `|Z_t|/(ρc) ≈ 0.05–0.2`). Neither the
   phase-sensitivity nor the velocity-mismatch mask detects it; see `theory.md` section 3A.
5. The same medium and cross-section on both sides of the specimen (power coefficients, TL).
6. Thin-element `Z_t`: negligible thickness and approximately continuous velocity. This is checked
   (`velocityMismatch`), never enforced. The views hide `Z_t` and the TL from `Z_t` when
   `Re(k)·d > 1` in the analysis band (d = specimen thickness).
7. One-load transfer matrix: reciprocal and symmetric specimen (stated assumption). The two-load
   method needs only linearity, plus two sufficiently different loads.
8. `R`, `τ` and the dissipation coefficient `α_d = 1 − |R|² − |τ|²` are the **as-mounted** values:
   specimen plus the actual downstream termination. They equal the specimen's anechoic-backed
   values only for an anechoic termination (`|R_term|` ≈ 0); `R` of a specimen that transmits nothing
   is intrinsic. `τ`, `α_d` and `TL_τ` are therefore valid only for `|R_term|` ≤ 0.1
   (`anechoicRmax`). `R` is computed from the upstream pair M1/M2 alone and has no termination
   condition. Termination-independent values: `τ_a` and `R_a` from the transfer matrix (scripts).

**Instrumentation**

9. The four LAN-XI channels share one sample clock, so their relative timing is exact. This is a
   property of a single LAN-XI module. The generator and the LAN-XI module do **not** share a
   clock, and the method does not need them to.
10. The complete microphone chains are stable between calibration and measurement (same cables,
    channels, range, filter, sample rate, temperature within a few K).
11. Switching calibration: microphones are interchanged without changing cables or channels, the
    sound field is identical in configurations I and II (no leaks, same insertion depth), and the
    chains differ in phase by < 90° at low frequency (branch rule; polarity reversal cannot be
    detected).
12. The LAN-XI stream is configured in volts (default transducer, sensitivity 1). The sensitivity
    is applied once in software. Verified on the real module (stream unit "V").

## Known limitations

* **Geometry not yet verified**: the CAD design values of the lab tube are entered
  (`config/user_config.json`: s1 29, L1 41, d 75, L2 41, s2 29 mm) but not yet checked on the real
  tube (calipers); Tests D/E are pending.
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
* `|R_term|` > 0.1 makes `τ`, `α_d` and `TL_τ` invalid. `R` stays valid, but it is the as-mounted
  value, which with a reflecting termination differs from the anechoic-backed `R` of a transmitting
  specimen (up to about 30 % at `|R_term|` = 0.1 for a thin screen `Z_t = 0.5ρc`). For reflecting
  terminations use the two-load transfer matrix (`τ_a`, `R_a`).
* Thin elements of low impedance (`|Z_t|/(ρc)` below about 0.2) are sensitive to the inter-pair
  phase residual of the calibration and to errors in `c` (temperature, humidity); no validity mask
  covers this (assumption 4).
* The calibration is not temperature compensated. Recalibrate after temperature changes > 3 K.
* Uncertainty: the software reports diagnostics (condition number, coherence, SNR, phase
  sensitivity, calibration repeatability, block scatter for stepped sine) but **no complete
  uncertainty budget** (GUM). The tolerances in `validation_procedure.md` are not uncertainty
  statements.
* GUI: a programmatic `uifigure` application. No `.mlapp` file is provided, because App Designer
  binary files cannot be produced reliably from source. The GUI is optional and less flexible
  than the scripts (for example, the two-load transfer matrix is scripted only).
* Simulation: the virtual rig models the loudspeaker as an ideal incident-wave source, with no
  source reflection or tube resonances on the upstream side. That is sufficient for estimator and
  decomposition tests, but not a model of the real tube. The virtual tube (`tim.sim.tubeModel`)
  uses the same air properties, wavenumber and `Z_c` as the analysis, so the round trip (Test F)
  checks the algebra only, not the tube physics; the independent physics check of the loss model is
  `TestAcoustics/kirchhoffMatchesExactTube` (exact Bessel-function tube). Microphones behind the
  termination plane (for example behind a rigid plug) receive no sound in the virtual tube (p = 0).

## Recommendations for future development

1. Measure the geometry (micrometer/caliper; acoustic centre of the 4957 relative to its holder)
   and correct the CAD values where needed; then run Tests D/E and populate `validatedBands`.
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
