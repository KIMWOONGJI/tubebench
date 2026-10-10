# Microphone calibration procedure

There are two independent calibration layers. Neither replaces the other.

| Layer | Purpose | Source | Used for |
|---|---|---|---|
| **A. Sensitivity** [mV/Pa] | absolute pressure, dB SPL, overload margins | individual calibration certificate, TEDS, or nominal 11.2 mV/Pa | `tim.acq.voltsToPascal`, time signals and spectra in Pa |
| **B. Switching calibration**, calibration factor `C_k = g_k/g_ref` | relative magnitude **and phase** of the complete measurement chains | microphone-switching measurement in the tube (ISO 10534-2 / ASTM E1050 type) | transfer functions, wave decomposition (R, τ, Z_t, TL, T) |

**A sensitivity (also from TEDS) is never a substitute for B.** The four-microphone method
depends on phase differences of a few degrees at low frequency (k·s = 3.6° at 120 Hz for
s = 29 mm). Without a calibration of layer B no result is marked valid; the window shows
"No calibration – results not valid" in the CALIBRATION section.

## A. Sensitivity

1. In `config/user_config.json`, enter for every microphone (`mics(i)`) the `serial`,
   `certificateSensitivity_VperPa` and `certificateDate` from its calibration certificate.
2. Order of the sources (`acquisition.sensitivityPolicy`, default `certificate>teds>nominal`): the
   first available value is used. The source is shown for every channel in Setup > Connection
   (cards and the Source column: certificate, TEDS, nominal), logged, and stored with every
   measurement (`meas.mics(i).sensitivitySource`). A nominal value is marked orange ("check:
   nominal sensitivity").
3. TEDS is read at Connect (`POST /rest/rec/channels/input/all/transducers/detect`). If the TEDS
   serial number differs from the configured one, the channel card shows "check: TEDS serial
   differs from the configuration" and a warning is logged. This catches mixed-up cables.
4. The LAN-XI stream is always configured in **volts** (module default transducer with sensitivity
   1). The sensitivity is applied exactly once, in software. If the stream ever reports a unit other
   than V, the data are rejected, so the sensitivity can never be applied twice.
5. Optional: a sound calibrator, with the coupler or adaptor that HBK specifies for the Type 4957,
   can verify the sensitivity of each chain. Check the 4957 product data for the correct adaptor;
   it is not specified here. This check is not automated.

## B. Switching calibration

### Principle

Let `g_k` be the complex gain of the complete measurement chain k (microphone, preamplifier,
cable, CCLD supply, LAN-XI input) and `g_ref` that of the reference channel
(`analysis.refChannel`, default ch1). The two microphones are placed in the calibration ports a
and b. Each microphone **stays on its own cable, CCLD supply and LAN-XI input**; only the
microphones are moved.

* Configuration I: reference microphone in port a, microphone k in port b:
  `H^I = Y_k/Y_ref = (g_k·p_b)/(g_ref·p_a)`
* Configuration II: the two microphones interchanged:
  `H^II = (g_k·p_a)/(g_ref·p_b)`

Then `H^I·H^II = (g_k/g_ref)²` and `H^I/H^II = (p_b/p_a)²`, so

    C_k = g_k/g_ref = ±√(H^I·H^II),        p_b/p_a = ±√(H^I/H^II)

The calibrated transfer function of a measurement is `H_k = (Y_k/Y_ref)/C_k`.

**Branch selection**: the phase of `H^I·H^II` is unwrapped along frequency over the valid
frequency lines and halved. The multiple of π is chosen so that the low-frequency phase of `C_k`
is closest to 0. This assumes that two chains of the same microphone type differ by less than
±90° at low frequency, which holds for matched 4957 chains (a few degrees). A reversed polarity
(180°) **cannot** be detected by switching and must be excluded by correct wiring. A magnitude
outside 0.5–2 or a phase above 45° marks the frequency lines as implausible (a note in the log
and in `results{k}.notes`); they are not valid.

Frequency lines with a coherence below `calibration.coherenceMin` (0.98) or an SNR below
`calibration.snrMin_dB` (20 dB) in configuration I or II are not valid. They are excluded from the
phase unwrapping, receive interpolated phase and stay marked not valid. Interpolation onto the
frequency lines of a measurement uses `log|C_k|` and the **unwrapped** phase separately, so there
are no phase jumps and no magnitude shrinkage. There is no extrapolation outside the calibrated
range: there the transfer functions are undefined.

### Physical set-up

* Calibration ports a, b: `calibration.positions`, default M1 (a) and M2 (b), the upstream pair.
  All three channels are calibrated in the same two ports, so position-dependent mounting effects
  are identical for all channels. The other two microphones go to the remaining ports.
* **Mount the empty specimen section** (lab tube: the original 75 mm specimen section SIT-PT-003,
  without a specimen) in place of the specimen section with the specimen. **Do not remove the
  section and join the tubes**: M3 and M4 would move by 75 mm and the configured geometry would be
  wrong. With the empty specimen section the tube is continuous, and the geometry (s1 29, L1 41,
  d 75, L2 41, s2 29 mm; M2 → M3 = L1 + d + L2 = 157 mm) is the same for the calibration, the
  empty-tube check and the measurement.
* Mount the **absorbing termination** (or highly absorbing material at the end of the tube, e.g.
  50–100 mm of porous foam). This keeps the standing-wave ratio low, so that no pressure minimum
  falls on a calibration port; minima give low-SNR frequency lines that are not valid. The method
  itself holds for any sound field that is the same in configurations I and II, so a reflecting
  set-up still works, but more frequency lines near the pressure minima become not valid. With the
  specimen out of the tube it cannot be disturbed between the configurations.
* Sealing: every port must be sealed, either by a microphone or by a dummy plug. Leaks change
  `p_b/p_a` between the configurations and violate the method.
* Mounting depth: insert each microphone with the same depth and orientation in every
  configuration. Mark the holders.
* Excitation: the **swept-sine settings** of the EXCITATION section (frequency range, sweep
  duration, repetitions ≥ 2) and the Amplitude, whichever Signal is selected; a level at least
  40 dB above the background noise but at least 6 dB below overload. Check with Tests A/B first.
* Temperature: keep it stable during the calibration (< 0.5 K). The calibration is not temperature
  compensated.

### Steps (numbering as shown in the window)

With the defaults (reference ch1, ports M1 (a) and M2 (b), `calibration.repeatConfigI = true`,
`calibration.verifyEmptySection = true`) there are **12 operator steps**. Each step is shown as
"Calibration step n of 12" in the operator bar above the 3D model (in the language of `ui.language`);
the step list of the Calibration view has one row per step.

| Step | What the operator does | Microphones (channel → port) | Button |
|---|---|---|---|
| 1 | Prepare: mount the empty specimen section and the absorbing termination, seal every port, move only the microphones (never the cables or LAN-XI inputs), keep the temperature constant | ch1 → M1, ch2 → M2, ch3 → M3, ch4 → M4 | Continue |
| 2 | ch2, configuration I | ch1 → M1 (a), ch2 → M2 (b), ch3 → M3, ch4 → M4 | Measure |
| 3 | ch2, configuration I repeated: remove both microphones and reinsert them in the same ports | as step 2 | Measure |
| 4 | ch2, configuration II: interchange the two microphones | ch2 → M1 (a), ch1 → M2 (b), ch3 → M3, ch4 → M4 | Measure |
| 5 | ch3, configuration I | ch1 → M1 (a), ch3 → M2 (b), ch2 → M3, ch4 → M4 | Measure |
| 6 | ch3, configuration I repeated | as step 5 | Measure |
| 7 | ch3, configuration II | ch3 → M1 (a), ch1 → M2 (b), ch2 → M3, ch4 → M4 | Measure |
| 8 | ch4, configuration I | ch1 → M1 (a), ch4 → M2 (b), ch2 → M3, ch3 → M4 | Measure |
| 9 | ch4, configuration I repeated | as step 8 | Measure |
| 10 | ch4, configuration II | ch4 → M1 (a), ch1 → M2 (b), ch2 → M3, ch3 → M4 | Measure |
| 11 | Return all microphones to their measurement ports; the empty specimen section stays mounted. One sweep follows: the **empty-tube check (Test E)** | ch1 → M1, ch2 → M2, ch3 → M3, ch4 → M4 | Measure |
| 12 | Replace the empty specimen section by the specimen section with the specimen (same orientation, flanges sealed); check that L1, d and L2 describe the mounted specimen | – | Continue |

* Every measuring step is one swept-sine measurement with all its repetitions.
* Without the repeated configuration I (`repeatConfigI = false`) there are **9 steps**; the
  remounting repeatability is then not measured.
* Without the empty-tube check (`verifyEmptySection = false`), or when it cannot run (L1, d or L2
  not entered, or a channel without any valid frequency line), step 11 only returns the
  microphones. Its bar says "The empty-tube check (Test E) is skipped: …" with the reason; the
  button reads Continue and nothing is measured.
* Another reference channel or other calibration ports change the table accordingly: the
  reference microphone always starts in port a, and the two microphones that are not calibrated go
  to the remaining ports in ascending order.

### In the window

1. Connect (the calibration needs a complete connection) and check the EXCITATION settings of the
   swept sine and the Amplifier gain.
2. Press **Run switching calibration…** in the CALIBRATION section. The **Calibration** view opens.
3. For every step the view shows:
   * the instruction ("Calibration step 4 of 12: Configuration II for ch2: interchange the two
     microphones – …");
   * the **3D model** of the Tube setup view in its calibration state: the empty specimen section
     (dashed outline, "(no specimen)"), the absorbing termination, the calibration ports M1 (a)
     and M2 (b) with a **yellow glow**, every microphone in the colour of its LAN-XI channel and
     labelled with the channel (with "(ref)") and its serial number. The microphones that change
     port are **lifted out of their holders, moved and lowered** into the new ports; dashed arrows
     keep the moves visible. While the bar waits, the calibration ports **pulse**. The model can
     be rotated and zoomed with its toolbar;
   * the **operator bar** above the model with the instruction: while the program waits it turns
     yellow and shows the buttons **Measure** (a sweep follows) or **Continue** (steps 1 and 12,
     and step 11 without the empty-tube check) and **Cancel calibration** on its right. There is no
     separate dialog: the window is not dimmed and nothing covers the model. Stop and closing the
     window still work while it waits. The confirmation before the loudspeaker is first driven
     also appears in the bar.
4. The **step list** ("Operator steps and quality of every measurement", right column, the detail
   under each step) shows every step with its
   state (turning icon = running) and, after each measurement, its quality, e.g.
   "97 % OK · γ² 0.9995 · 52 dB": the share of the frequency lines with coherence ≥
   `calibration.coherenceMin` and SNR ≥ `calibration.snrMin_dB` (the lower SNR of the reference
   channel and channel k), the median coherence γ² and the median SNR. Green ≥ 90 % of the lines,
   orange 50–90 %, red below 50 % or failed data integrity. After configuration II of a channel the
   row adds the number of valid frequency lines of `C_k` and, with the repeated configuration I,
   the remounting repeatability ("· C2 2191/2191 valid · remount 0.02 dB / 0.1°"); it turns orange
   when fewer than 90 % of the lines are valid. Row 11 shows the result of the empty-tube check;
   row 12 asks to mount the specimen section again.
5. Below the model, side by side: |C_k| [dB] and the phase of `C_k` [°] for ch2, ch3 and ch4 relative to ch1
   (grey = not valid). The summary table "Calibration factors Ck = gk/gref" gives per channel the
   share of valid frequency lines, the range of magnitude and phase over the valid lines, and the
   remounting repeatability. The header note gives the result of Test E (green = passed, red =
   failed, orange = not performed).
6. At the end the CALIBRATION line shows the new version, e.g. "CAL-20261009-105835 ✓ Test E"
   ("✗ Test E failed" in orange after a failed check), and the file becomes the configured
   calibration file: it is loaded at the next Connect and stored by File > Save configuration….

In **simulation** mode the bar does not wait (to practise the steps with the bar:
`app.PromptInSimulation = true`): the program moves the virtual microphones, and the
virtual tube holds the empty specimen section during the calibration and gets its specimen back
afterwards (also after an error or Stop).

The **Formula** tab (section 2) lists the calibration equations together with all other
equations.

### Empty-tube check (Test E)

After step 11 one sweep is measured with the microphones in their measurement ports and the empty
specimen section mounted, and evaluated with the new calibration: for the empty section
`τ = e^(−jkd)` (wavenumber of the tube-loss model, d = xRear − xFront = 75 mm) and
`R = R_term·e^(−2jkd)`. It passes when, as medians over the frequency lines that meet the geometry
and quality criteria (no passivity screen), `|τ/τ_exp|` deviates from 1 by less than 0.02, the
phase error of τ is below 2° rms and `|R − R_term·e^(−2jkd)|` is below 0.02.

* It checks the port coordinates (s1, s2 and M2 → M3 = L1 + d + L2) and the calibration to about
  1° per mm at 1 kHz. It cannot check how the 157 mm are split into L1, d and L2.
* If the specimen section had been removed and the tubes joined, the phase error of τ would be
  about 79° at 1 kHz and the check fails.
* The result is stored in `cal.meta.emptyCheck`, logged ("Test E, empty specimen section
  (d = 75 mm): passed (|τ| error …, τ phase error …° rms, R consistency …, … frequency lines
  evaluated)"), shown in row 11, in the header note of the Calibration view and in the
  CALIBRATION line. A failed check only warns: `C_k` stays valid, but check s1, L1 + d + L2, s2,
  leaks, and that the empty specimen section is mounted.
* The check sweep is saved with the raw calibration measurements.

### Cancelling and stopping

While the calibration runs, the window is locked: every field, button and menu is disabled
except the red **Stop** button, which switches the generator output off at once and ends the
calibration. At each step **Cancel calibration** in the bar ends it as well. Closing the window stops the
calibration first and then closes. The calibration file is written as soon as the switching
measurements are complete, **before** the question of step 11, and becomes the active calibration
at once. What is kept depends on when the calibration ends:

* **Steps 1–10** (preparation and switching measurements): nothing is saved; the calibration that
  was active before stays active. The running step is marked red.
* **Step 11, at its question**: the calibration file was already written before this question and is
  the active calibration. Cancel calibration (or Stop) keeps it and records
  `cal.meta.emptyCheck.text = 'not performed: cancelled by the operator – calibration saved without the empty-tube check'`
  (any other error at this step: "not performed: error – calibration saved without the
  empty-tube check: …"). Row 11 shows this text, the log says "Calibration … was saved before the
  stop and is active.", and the file becomes the configured calibration file (used at the next
  Connect, stored by File > Save configuration…). The question of step 12 is not shown: mount the
  specimen section yourself.
* **Step 11, during the check sweep**: the calibration stays active and records
  `cal.meta.emptyCheck.text = 'stopped by the operator – calibration saved without the empty-tube check'`
  (an instrument error during the check is recorded the same way, with the error message). After
  a Stop the question of step 12 is skipped and a warning reminds you to mount the specimen section.
* **Step 12**: the calibration and its check are saved and active. Cancel calibration only logs
  "Warning: last calibration step not confirmed … – mount the specimen section before measuring."

### Script use

`[cal, file] = tim.app.runCalibration(s)` runs the same steps on a connected session `s`. In
hardware mode every step is printed in the command window and waits for Enter ("Press Enter when
done (Ctrl+C to cancel)…"); in simulation mode the virtual microphones are moved. The prompts
follow `ui.language` (`"en"` or `"ko"`) and are written to the log in that language. The file is
written before the "return the microphones" prompt and adopted by the session
(`s.Calibration`, `s.CalibrationFile`), so a cancel, Stop or error from there on keeps it.
`opts.prompt` and `opts.report` replace the prompt and
receive the quality of every measurement (this is how the window uses it). Plot a calibration
with `tim.app.plotCalibration(cal)`.

### The calibration file

The calibration is saved as `calibration\CAL-yyyyMMdd-HHmmss.mat` (simulation:
`calibration\simulation\`), never overwritten. The file holds `cal` (`f`, `C`, `valid`,
`refChannel`, `version`, `results`, `meta`) and **all raw calibration measurements** (`raw`,
including the empty-tube sweep). `cal.convention` documents `C_k = g_k/g_ref` and
`H_k = measured H_k ./ C_k`. `cal.meta` records the microphones, the ports, the excitation, the
operating mode, the software version and commit, the empty-tube check (`emptyCheck`) and the
set-up (`tube`: specimen section "empty", its length, the geometry and the environment).

The calibration also records the acquisition chain (`acquisition`: driver, module model, serial
number and firmware, sample rate, range, filter, CCLD), because the calibration factors are ratios
of chain gains that include the DAQ inputs.

`tim.app.processMeasurement` compares this set-up with every measurement
(`res.calibration.context`): port distances, temperature (more than 3 K → recalibrate), simulation
vs hardware, the Test E result and the acquisition chain recorded with the measurement (another
module or other input settings → recalibrate; a calibration made before version 1.2.0 has no
record of it and is not checked for it). Differences are logged as warnings ("CALIBRATION: …")
and shown as "– check" in the CALIBRATION line of the window; nothing is invalidated.

### Acceptance criteria (suggested; enter your own in the lab book)

* `results{k}.nValid` covers the intended band (120 Hz – 4.5 kHz).
* Remounting repeatability below 0.05 dB / 0.2° in the band. The simulation gives about
  0.1 dB / 0.8°; that figure is noise-limited and not representative of real mounting.
* |C_k| within ±1 dB and ∠C_k within a few degrees (matched 4957). Larger values point to wiring
  or channel problems.
* Test E passed.
* Test C (`tim.val.testC_calibrationConsistency`), run on an **independent** interchanged
  measurement, gives < 0.05 dB and < 0.3° rms after correction.

### When to recalibrate

After any change of microphone, cable or channel assignment, LAN-XI settings (range, filter,
sample rate) or temperature by more than about 3 K, and at least once per measurement day. The
calibration version is stored with every measurement (`metadata.calibrationVersion`).
