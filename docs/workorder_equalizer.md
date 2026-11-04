# Work order WO-006: level equalizer for the stepped sine (proposal)

| | |
|---|---|
| Target version | 1.6.0 (after 1.5.0, the frequency-dependent step timing) |
| Status | **proposal, not started** (2026-11-04). The owner decides after the step-timing work (branch `stepped-timing`) whether and how far to build it (section 8) |
| Requested by | the owner (Woongji Kim), 2026-11-04: a pressure or particle-velocity equalizer as in spectrum analyzers; one load against two loads; swept sine |
| Rules | as in CLAUDE.md; the equalizer never plays more than the level the operator set (raising a level needs the owner's approval); hardware results only from real measurements with the owner present |

## 1. Summary of the discussion (2026-11-04)

- **Why.** The transfer-function method uses ratios between the channels, so for a **linear**
  specimen the result does not depend on the excitation spectrum; ISO 10534-2 and ASTM E2611 do not
  ask for a constant level. An equalizer pays off for:
  - **specimens that are not linear**: the necks of resonator cells, perforates. Their resistance
    depends on the particle velocity, and near a resonance the level rises steeply, so today every
    frequency of a TL curve is measured at another amplitude. A defined level at every frequency
    makes the condition clear and allows measurements of the amplitude dependence;
  - **SNR and overdrive**: the tube and loudspeaker resonances make the level vary by up to about
    ±20 dB, more with a rigid cap (load B of two loads).
- **Controlled quantity.** Not one microphone (it can sit near a node of the standing wave), but
  from the four-microphone decomposition:
  - the **incident pressure** |A| at the specimen front face [dB SPL] (the usual reference in the
    literature), or
  - the **particle velocity** |u_L| at the front face [mm/s] (closer to the cause of the
    non-linearity of necks and orifices).
- **Feedforward, not a closed loop.** A low-level pre-measurement gives the transfer from the
  generator voltage to the controlled quantity at every step frequency; the steps then play the
  voltage that gives the target. A closed loop (measure, correct, settle again at every step)
  costs a settling time per iteration and cannot work on a device that plans its output in
  advance (block acquisition, `simcombined`).
- **Two loads.** The transfer depends on the termination: reflections from the specimen and the
  termination return to the loudspeaker, so the same voltage gives another |A| with load B, and
  |u_L| changes even more. Hence a pre-measurement after **every change of termination** (A and B).
  A′ is played with the voltages of A, so that the repeat check compares only the mounting. For a
  specimen that is not linear the two-load T stays an approximation: at the same incident pressure
  the faces still see other states in A and B; the equalizer reduces the difference, it does not
  remove it.
- **Swept sine: not now.** A linear specimen needs no equalized sweep, and a sweep passes a
  resonance as a transient, so it controls the non-linear condition less clearly than a stepped
  sine. The built-in sweep of the 33220A has one amplitude; an equalized sweep needs an arbitrary
  waveform (ARB memory of about 64 k points: sweeps of 2–3 s up to 5.5 kHz, to be confirmed from
  the manual), a new optional contract capability and a new check of the sweep gate. To be
  revisited when a sweep band lacks SNR or a sample-output source (DAQ analog output, audio
  interface) is used.
- **Roles.** Swept sine = the broadband main measurement, without equalizer. Stepped sine with
  equalizer = level-controlled checks and specimens that are not linear.

## 2. Stage 1: the level at the specimen, for every measurement

- From the calibrated decomposition and the absolute sensitivity of the reference microphone
  (TEDS or certificate): the incident pressure |A| at the front face [dB SPL] and the particle
  velocity |u_L| [mm/s] per frequency line. Stepped sine: from the fitted amplitudes (already used
  for the step levels). Swept sine: the equivalent sine amplitude when the sweep passes the
  frequency (from the spectrum and the sweep rate).
- Shown in the window (Spectrum view), written to `results.csv` and saved with every measurement.
- Purpose: see on real data how much the level varies, before stage 2 is decided.

## 3. Stage 2: feedforward equalizer for the stepped sine

1. **Settings** (`excitation.stepped.equalizer`): `mode` `'off'` (default) | `'incidentPressure'`
   | `'faceVelocity'`; `target` (dB SPL or mm/s); `preLevelVpp` (the pre-measurement, at most the
   amplitude); `tolerance_dB`; `corrections` (0 = pure feedforward; 1 = one correction where the
   source can change its level while on).
2. **Sequence.** Pre-measurement → transfer G(f_k) = controlled quantity per volt at every step →
   V_k = target / |G(f_k)|, capped at the amplitude the operator set and at the drive limits
   (`tim.app.driveLimits`: generator, amplifier, loudspeaker power) → the steps are played with V_k
   → the achieved level is reported per step; a step capped below the target is marked "target not
   reached".
3. **A level per step.** An optional contract method `setAmplitude(vpp)`: sine only, the output
   state unchanged, the level checked before the command (`tim:gen:amplitude`), declared by
   `capabilities().source.levelWhileOn` (default false); `tim.instr.SignalSource` implements it as
   `tim:gen:unsupported`. A source without it either switches the output at every step
   (`configureSine` + `outputOn`, the settling covers the click) or cannot use the equalizer
   (decision 4).
4. **Two loads.** A pre-measurement after every change of termination (A, B) as a step of the
   operator bar (no extra handling of the tube); A′ with the voltages of A; `loadBLevel_dB` (B
   level) is replaced by the equalizer while it is on.
5. **Safety.** Never above the amplitude field; the pre-measurement below it; every per-step level
   checked by the driver before its command and by the drive check; the output-off duties (D24)
   unchanged.
6. **Results.** Per step: voltage played, achieved level, target, deviation; in the metadata; the
   Spectrum view shows the achieved level against the target.

## 4. The add-instrument skill and the instrument contract

- The contract grows only by an **optional** capability (`levelWhileOn` with `setAmplitude`), so the
  existing drivers and the drivers other labs write with the guide stay valid.
- To update: `docs/instrument_interface.md` (sections 3 and 5), `docs/adding_an_instrument.md` (an
  optional step), `templates/instrument/` (stub, capability false), `TestInstrumentContract` (cases
  for the drivers that declare it), `TestInstrumentTemplates`. The skill
  `.claude/skills/add-instrument` runs the guide and is not expected to change (checked, as for
  WO-004).
- `TestBusTraffic`: a new scenario (equalized stepped sine); fixtures regenerated only with the
  owner's approval.
- 33220A: a `VOLT` command while the output is on (attenuator relays, glitch, read-back) is checked
  in the manual and on the instrument before the driver declares `levelWhileOn`.

## 5. Tests (simulation)

- The virtual rig reaches the target within the tolerance at every step (linear virtual specimen),
  for both controlled quantities.
- A step capped at the operator's level is marked; no level above the amplitude field.
- Two loads: a pre-measurement per load, A′ with the voltages of A.
- A source without `levelWhileOn` (decision 4).
- Stage 1: the displayed incident pressure against the true one of the virtual rig.

## 6. Hardware check (owner present)

1. 33220A: `VOLT` while the output is on (glitch, read-back); the settling covers it.
2. Empty section with the absorber, equalized: incident level within the tolerance at every step;
   TL ≈ 0 dB.
3. Resonator cell: TL at two targets (for example 80 and 100 dB SPL) for the amplitude dependence;
   two loads with the equalizer.

## 7. Not in this work order

- Equalized swept sine (arbitrary waveform), closed-loop control, the two-source method.

## 8. Open decisions (owner)

1. Stage 1 first and stage 2 after its results, or both together.
2. Default controlled quantity: incident pressure or face velocity.
3. Pre-measurement: a swept sine (fast, all frequencies) or the steps themselves at a low level.
4. A source without `levelWhileOn`: switch the output at every step, or no equalizer.
5. A step that misses the target: reported only, or masked.
6. Version 1.6.0.

## 9. Estimate

- Stage 1: small (analysis, one view, CSV, tests).
- Stage 2: medium (session sequence, optional contract capability, window, two-load integration,
  documents, tests, fixture regeneration, hardware check).
