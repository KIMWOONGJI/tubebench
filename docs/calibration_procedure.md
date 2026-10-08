# Microphone calibration procedure

There are two independent calibration layers. Neither replaces the other.

| Layer | Purpose | Source | Used for |
|---|---|---|---|
| **A. Sensitivity** (V/Pa) | absolute pressure, dB SPL display, overload margins | TEDS, individual calibration certificate, or nominal 11.2 mV/Pa | `tim.acq.voltsToPascal`, spectra in Pa |
| **B. Complex inter-channel** `C_k(f) = c_k/c_ref` | relative magnitude **and phase** of the complete chains | sensor-switching measurement in the tube | wave decomposition (R, τ, Zt, T) |

**TEDS sensitivity is never a substitute for B.** Four-microphone decomposition depends on
phase differences of a few degrees at low frequency (k·s = 3.6° at 120 Hz). Without layer B no
result is marked valid.

## A. Sensitivity layer

1. In `config/user_config.json`, fill in for every microphone (`mics(i)`): `serial`,
   `certificateSensitivity_VperPa` and `certificateDate`, taken from the calibration certificate.
2. Priority (`acquisition.sensitivityPolicy`, default `certificate>teds>nominal`): the first
   available value is used. The source is logged and stored with every measurement
   (`meas.mics(i).sensitivitySource`).
3. TEDS is read with `POST /rest/rec/channels/input/all/transducers/detect`. If the TEDS serial
   differs from the configured serial, a warning is logged. This catches swapped cables.
4. The LAN-XI stream is always configured in **volts** (module default transducer with
   sensitivity 1). The sensitivity is applied exactly once, in software. If the stream ever
   reports a unit other than `V`, the data are rejected. This prevents the sensitivity from being
   applied twice.
5. Optional: a sound calibrator, with the coupler/adaptor that HBK specifies for the Type 4957,
   can verify the sensitivity of each chain. Check the 4957 product data for the correct
   adaptor; it is not specified here. This procedure is not automated.

## B. Complex calibration by sensor switching

### Principle

Microphone k and the reference microphone (channel `ref`) are mounted in two ports a and b. Each
microphone **stays on its own cable, CCLD supply and LAN-XI channel**; only the microphone bodies
are moved.

* Configuration I: ref at a, k at b → `HI = Y_k/Y_ref = (c_k p_b)/(c_ref p_a)`
* Configuration II: the two microphones interchanged → `HII = (c_k p_a)/(c_ref p_b)`

Then `HI·HII = (c_k/c_ref)²` and `HI/HII = (p_b/p_a)²`, so

    C_k = c_k/c_ref = ±sqrt(HI·HII),        p_b/p_a = ±sqrt(HI/HII)

**Branch selection**: the phase of `HI·HII` is unwrapped along frequency over the valid bins and
halved. The multiple of π is chosen so that the low-frequency phase of `C_k` is closest to 0. This
assumes that two chains of the same microphone type differ by less than ±90° at low frequency,
which holds for matched 4957 chains (a few degrees). A reversed polarity (180°) **cannot** be
detected by switching and must be excluded by correct wiring. A magnitude outside [0.5, 2] or a
phase above 45° flags the bins as implausible (`notes`).

Invalid bins (coherence below `calibration.coherenceMin`, or SNR below `calibration.snrMin_dB`)
are excluded from the phase unwrapping, receive interpolated phase, and stay flagged invalid.
Interpolation onto the measurement grid uses `log|C|` and the **unwrapped** phase separately, so
there are no phase jumps and no magnitude shrinkage. There is no extrapolation outside the
calibrated range.

### Physical set-up

* Ports a, b: `cfg.calibration.positions` (default [1 2], the upstream pair M1/M2). All three
  channel pairs are calibrated in the same two ports, so position-dependent mounting effects are
  identical for all channels.
* **Remove the test specimen.** Terminate the tube anechoically, or put a highly absorbing
  material (e.g. 50–100 mm of porous foam) at the end or in the empty sample holder. This keeps
  the standing-wave ratio low, so no pressure minimum falls on a calibration port. Minima give
  low-SNR, invalid bins. Mathematically the method holds with any field that is identical in
  configurations I and II, so a reflecting set-up (or a specimen in place) still works, but bins
  near the standing-wave nodes become invalid. The specimen is also removed so that it cannot be
  disturbed between the configurations. The GUI and `runCalibration` show this checklist as the
  first step.
* Sealing: every port must be sealed. An unused port must hold its microphone (the other two
  microphones go to the remaining ports) or a dummy plug. Leaks change `p_b/p_a` between the
  configurations and violate the method.
* Mounting depth: insert each microphone with the same depth and orientation in every
  configuration. Mark the holders.
* Excitation: the configured log sweep (`cfg.excitation.sweep`), ≥ 2 repetitions, at a level
  ≥ 40 dB above background but ≥ 6 dB below overload. Check with Test A/B first.
* Temperature: keep it stable during the calibration (< 0.5 K). The calibration is not
  temperature compensated.

### In the GUI

Press **"Run switching cal."**. The **Calibration** tab then shows, for every step, a diagram of
the tube with the loudspeaker, ports M1–M4 and the sample position. The two calibration ports are
highlighted in yellow, and coloured circles give the DAQ channel and TEDS serial of the microphone
that must sit in each port. At every step the circles **move** from their previous ports to the
new ones (up, across, down; dashed arrows keep the paths visible), and while the dialog waits for
you the two calibration ports **pulse**. A dialog shows the step number ("Calibration step 4 of
8") and the instruction. Press "Done - measure" once the microphones are in place, or "Abort".
Closing the window also aborts (the dialog never blocks MATLAB).

Next to the diagram, the **step list** shows every operator step with its state (turning icon =
running) and, after each measurement, its quality: share of the frequency bins that meet the
coherence and SNR criteria (`calibration.coherenceMin`, `snrMin_dB`), median coherence and median
SNR. Green ≥ 90 % of the bins, orange 50–90 %, red below 50 % or failed data integrity. After the
config II measurement of a channel the list adds the number of valid bins of `C_k` and, with the
repeated config I, the re-mount repeatability. After the last step the curves `|C_k|` and `∠C_k`
are plotted in the same tab. The **Equations** tab lists the calibration equations together
with all other equations used.

While the calibration (or any measurement) runs, the GUI is **locked**: every input and button
is disabled except the STOP button, which reads **"ABORT calibration"**. Pressing it switches the
generator output off and stops the calibration; nothing is saved. Between the steps the dialog
also offers "Abort".

### Step by step (`[cal, file] = tim.app.runCalibration(s)` or the GUI button)

For every k ≠ ref (default k = 2, 3, 4) the program prompts:

1. **CONFIG I**: put the reference microphone (channel `ref`) in port a and microphone k in port
   b; place the other two microphones in the remaining ports. Press ENTER → sweep measurement.
2. **CONFIG I (repeat)** (if `calibration.repeatConfigI = true`): remove both microphones and
   re-insert them in the same ports → measurement. This quantifies the remounting repeatability
   (`results{k}.repeatability`, max dB / deg).
3. **CONFIG II**: interchange the two microphones (cables stay connected) → measurement.

When it finishes, the program asks you to return all microphones to their measurement ports. The
calibration is saved as `calibration/CAL-yyyyMMdd-HHmmss.mat` (never overwritten). The file holds
`cal` (f, C, valid, refChannel, version, results, meta) and **all raw calibration
measurements** (`raw`). Plot it with `tim.app.plotCalibration(cal)`.

### Acceptance criteria (suggested; enter your own in the lab book)

* `results{k}.nValid` covers the intended band (120 Hz – 4.5 kHz).
* Remounting repeatability below 0.05 dB / 0.2° in the band. The simulation gives about
  0.1 dB / 0.8°; that figure is noise-limited and not representative of real mounting.
* `|C_k|` within ±1 dB and `∠C_k` within a few degrees (matched 4957). Larger values point to
  wiring or channel problems.
* Test C (`tim.val.testC_calibrationConsistency`), run on an **independent** interchanged
  measurement, gives < 0.05 dB and < 0.3° rms after correction.

### When to re-calibrate

After any change of microphone, cable or channel assignment, LAN-XI settings (range, filter,
sample rate) or temperature by more than ~3 K, and at least once per measurement day. The
calibration version is stored with every measurement (`metadata.calibrationVersion`).
