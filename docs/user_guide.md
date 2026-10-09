# Measurement user guide

This guide describes the program "Transfer impedance tube": the window (`tubeapp`), the safety
behaviour, the configuration file and the script interface. The switching calibration has its
own document (`calibration_procedure.md`), the hardware tests theirs (`validation_procedure.md`),
and the formulas are in `theory.md` and in the **Formula** tab of the window.

## 1. First steps

1. Read `installation_windows.md`, then run `run_tests` once. All tests must pass.
2. Check `config\user_config.json` (tracked in Git; it holds the lab settings, see section 9).
   Create it from `config\example_config.json` only if it does not exist. Commit it after
   changes, so that the history keeps the measured geometry.
3. Start the window:
   * double-click `start_tubeapp.bat` (real instruments, `config\user_config.json`), or
     `start_tubeapp.bat sim` (virtual tube for practice, `config\sim_thin_screen.json`);
   * or type `tubeapp` / `tubeapp sim` / `tubeapp myconf.json` in MATLAB.

   For script-based use, run `start_here.m` section by section (section 11).

## 2. The window

The window title is "Transfer impedance tube". It opens maximised and has four parts:

* the **menu bar** (File, Help; section 7);
* the **control panel** on the left, in workflow order: INSTRUMENTS, IMPEDANCE TUBE, EXCITATION,
  CALIBRATION, MEASUREMENT, RESULTS (section 4). It fits a 1920 × 1080 screen without scrolling
  and scrolls only in a small window;
* the **views** on the right, in two levels of tabs (section 6):

  | Tab | Sub-tabs |
  |---|---|
  | Setup | Connection, Tube setup |
  | Calibration | – |
  | Measurement | Time signals, Spectrum, Transfer functions |
  | Results | Reflection and transmission, Transmission loss, Transfer impedance, Validity |
  | Formula | – |

* the **Messages** pane below the views: every action, result and warning with its time. Warnings
  about the settings appear once as "CHECK: …". The last 1000 lines are kept.

### Every view has the same layout

* A **header**: the title, a one-line description of what is shown and, when needed, a note line
  (orange = warning, red = failure, green = OK, grey = information). The Tube setup view has its
  buttons on the right of the header.
* The **graphs**. The title above the graphs says *which* data are shown: the signal, the time
  stamp, the calibration version (or "NO calibration") and "SIMULATION" for simulated data, so a
  stale plot is recognised at once. Before there are data, every graph already shows its labels,
  units and default limits with a centred message ("No measurement yet – connect and press Start
  measurement").
* A **summary table** on the right with a title and a short note below it (octave-band values,
  levels, signal quality, criteria; Connection and Formula have none).

### Reading the graphs (house style)

The same style is used in the window and in the saved figures:

* outward ticks, no frame on the top and right, a light grid;
* the axis limits lie half a tick interval beyond the outermost ticks, so no tick sits on the end
  of an axis;
* frequency axes are logarithmic with **octave ticks** (31.5, 63, 125, 250, 500, 1k, 2k, 4k …) and
  cover the analysis band (stepped sine: every step);
* **grey = not valid**. A curve is drawn thin and grey over its whole range, and its valid
  frequency lines in colour on top. Nothing is shown as valid just because it is finite. Stepped
  sine: one marker per step (filled = valid, hollow grey = not valid); a step without any value
  is marked by a hollow triangle on the frequency axis;
* channel colours (Okabe–Ito, colour-blind safe): ch1 blue, ch2 vermilion, ch3 bluish green,
  ch4 reddish purple. Physical quantities (R, τ, α_d, TL, Z_t) use black, orange, sky blue and
  grey, never a channel colour;
* every graph has a small toolbar: export, zoom in / out, pan, restore view. After a zoom the
  ticks are automatic; "restore view" brings back the fitted limits and the octave ticks.

## 3. Safety behaviour

* **Connect always switches the generator output off**, and it stays off while you configure.
* The output can be switched on only inside a measurement that you started: **Start
  measurement** or a step of the switching calibration. It is switched off as soon as the
  excitation ends and locked again after the measurement. **Measure background noise** and the
  signal check of Connect never drive the loudspeaker.
* **Amplitude limit** (`generator.maxVpp`): the Amplitude field cannot exceed it, the settings are
  checked against it, and the programmed value is read back from the 33220A and checked again
  right before the output is switched on.
* **Loudspeaker power limit**: the estimated loudspeaker power (generator amplitude × amplifier
  gain, section 4) is checked before every excitation. Above the limit the excitation is refused,
  also in simulation.
* **Amplifier gain**: the gain is set by hand on the amplifier; the program cannot read or change
  it. When an amplifier is chosen, its gain must be entered (section 4) before a measurement or a
  calibration can start.
* **Excitation confirmation** (hardware mode): before the loudspeaker is driven, the dialog
  "Confirm excitation" shows the signal, the generator amplitude in Vpk (Vpp in brackets), the
  amplitude limit and the drive estimate with the amplifier gain. **Start excitation** drives the
  loudspeaker, **Cancel** stops without driving it. The question comes once per combination of
  amplitude and amplifier setting and again after any change (a calibration with ten sweeps asks
  once). `amplifier.confirmBeforeExcitation = false` switches it off.
* **Stop**: while an action runs, every field, button and menu is locked except the red Stop
  button, which names the action ("Stop measurement", "Stop calibration", "Stop connection").
  It switches the generator output off at once and ends the action. The tabs stay usable. In
  hardware mode the Generator lamp turns orange while the loudspeaker can be driven, and the status
  line says "… – loudspeaker driven, Stop switches it off".
* **Errors and Stop** (network, stream, instrument error, Stop): the generator output is switched
  off and read back (`OUTP?`); the alert says whether the output is confirmed off, or asks you to
  switch the 33220A output off at the instrument. If a recording was running, it is stopped and
  the data received so far are saved to `data\emergency\partial_<time>.mat`.
* **Data integrity**: the LAN-XI DataQuality flags (INVALID, clipped) and a software check
  (≥ 99 % of the input range) mark a measurement as failing. The results are still computed, the
  message pane lists the problem and a "Data integrity" warning appears.
* **Unsaved measurement**: before an unsaved measurement is replaced or lost (Start measurement,
  Measure background noise, File > Load configuration…, closing the window), a dialog asks
  "… anyway? The measurement is then lost." with the action and Cancel.
* **Closing the window** (the window's X or File > Exit): a "Closing" dialog appears at once and
  lists the steps: generator output off, LAN-XI module back to Idle (2 s time-outs, so a
  switched-off instrument cannot delay it), window closed. If an action is running it is stopped
  first (output off at once) and the window closes as soon as it has stopped, without the
  unsaved-measurement question; a second close request closes at once.
* Start with a low generator amplitude **and a low amplifier gain**, and increase gradually
  (commissioning section H3 in `examples/hardware_commissioning.m`).

### Driving the loudspeaker directly from the 33220A (no power amplifier)

This is possible for bench tests and low-level measurements. The 33220A manual (specifications)
states: output impedance 50 Ω, "Short-circuit protected, overload automatically disables main
output", and at most 20 Vpp into an open circuit. With a loudspeaker of impedance Z the 50 Ω
source forms a voltage divider, `V_spk = V_oc·Z/(Z + 50 Ω)`:

| Generator, open circuit (`generator.load = "INF"`) | at 8 Ω | at 4 Ω |
|---|---|---|
| 0.5 Vpk (1 Vpp) | 0.069 Vpk, 0.3 mW | 0.037 Vpk, 0.2 mW |
| 5 Vpk (10 Vpp) | 0.69 Vpk, 30 mW | 0.37 Vpk, 17 mW |
| 10 Vpk (20 Vpp, maximum) | 1.38 Vpk, **0.12 W** | 0.74 Vpk, 69 mW |

* About 0.1 W at most. That is harmless for practically any loudspeaker and enough for the
  impedance tube, where the plane wave stays confined. In free air it gives roughly 80–90 dB SPL at
  0.3 m for a typical loudspeaker (estimate; it depends on the loudspeaker's sensitivity).
* With 50 Ω source impedance the drive is current-like and the loudspeaker is poorly damped. This
  does **not** matter for the measurement, which uses only ratios of microphone signals.
* Choose "none (direct drive)" in the Amplifier list (gain fixed at ×1) and keep
  `generator.load = "INF"`; "50" with direct drive is rejected. Raise `generator.maxVpp`
  deliberately (the lab file uses 2 Vpp = 1 Vpk).

## 4. The control panel

### INSTRUMENTS

| Control | Function |
|---|---|
| Operating mode | Simulation (virtual tube, practice) or Hardware (33220A and LAN-XI module). **Fixed while connected**: press Disconnect to change it. |
| Connect | Connects the generator (output off) and the LAN-XI module, reads TEDS, sets up the channels and makes a 1 s signal check without excitation. Opens Setup > Connection, where every step is shown. |
| Disconnect | Generator output off, LAN-XI module back to Idle, connections closed. |
| Status | "Not connected", "Ready (simulation)", "Ready (hardware) - with warnings", "Connected (hardware) - a check FAILED", "Not ready – connection incomplete", "Busy: … – only Stop is available". |
| Lamps | Generator, LAN-XI, ch1–ch4: grey = not connected, blue = running, green = OK, orange = check, red = fault. Details in Setup > Connection. |

Connect takes the operating mode and the other fields as they are; if a field is invalid, the
connection uses the last valid settings and a "CHECK: …" line says so. After a failed connection
the status reads "Not ready – connection incomplete" and Connect stays disabled: press
**Disconnect**, remove the cause and press **Connect** again.

### IMPEDANCE TUBE (lengths in mm)

* **Diameter [mm]** (inner diameter D), **T [°C]** (air temperature) and **p [kPa]** (static
  pressure) on one row.
* The five **distances** in the order of the tube, measured between port **centres** and specimen
  **faces**:

  | Field | From → to |
  |---|---|
  | s1 M1–M2 | centre of port M1 → centre of port M2 |
  | L1 M2–front | centre of port M2 → specimen **front** face (towards the loudspeaker) |
  | d thickness | specimen front face → rear face (thickness; 0 for a thin screen) |
  | L2 rear–M3 | specimen **rear** face → centre of port M3 |
  | s2 M3–M4 | centre of port M3 → centre of port M4 |

  L1, d and L2 may be left empty ("?") while they are not measured. Acquisition, spectra and
  transfer functions still work, but the specimen results (R, τ, Z_t, TL) are disabled.
* The line below shows the speed of sound, the geometric validity range of the spacings and the
  analysis band ("c = 343.3 m/s · geometry 118–4735 Hz · analysis band 120–4500 Hz"), and in red
  any input error ("CHECK: …").

Internally x = 0 is the specimen front face (`xFront = 0`, `xRear = d`, `x_M2 = −L1`,
`x_M1 = −L1 − s1`, `x_M3 = d + L2`, `x_M4 = d + L2 + s2`). These coordinates are stored in the
configuration on a 1 nm grid (without it binary floating point would show s1 = 29.000000000000004
mm and write 0.11599999999999999 instead of 0.116). Store the values with **File > Save
configuration…**.

The lab tube (CAD assembly `cad/transfer-impedance-tube.step`) has s1 = 29, L1 = 41, d = 75 (the
specimen fills the 75 mm specimen section), L2 = 41 and s2 = 29 mm, inner diameter 29 mm. These
design values are in `config/user_config.json` (M1..M4 at −70, −41, 116, 145 mm, `xFront` 0,
`xRear` 75 mm) and must be checked on the real tube.

### EXCITATION

| Field | Meaning |
|---|---|
| Signal | **Swept sine** (broadband, default) or **Stepped sine** (discrete frequencies, for cross-checks). Random noise is available from scripts only. |
| Frequency [Hz] … to … | start and stop frequency, at most 0.45 × sample rate |
| Sweep duration [s] | duration of one sweep; for the stepped sine the field is **Number of steps** (1–400) |
| Repetitions | number of repetitions, averaged (1–100) |
| Amplitude [Vpk] | generator amplitude, peak voltage, up to the amplitude limit (`generator.maxVpp`/2) |
| Duration | expected duration of one measurement with these settings, e.g. "about 29 s" |
| Amplifier | "none (direct drive)", "power amplifier", or type a model (typed models are added to the list) |
| Amplifier gain | voltage gain of the amplifier as a factor, shown as ×10 (= 20 dB) |
| Loudspeaker [Ω] | nominal loudspeaker impedance |
| Power limit [W] | loudspeaker power limit: an excitation above this estimated power is refused |

* Each signal keeps its own frequency range, duration or number of steps and repetitions:
  switching the Signal shows the values last used for that signal. The amplitude is common.
* **Amplifier gain**: the field is disabled for "none (direct drive)" (gain ×1). When you choose an
  amplifier, the field turns yellow and the message pane asks for the gain: **Start measurement
  and Run switching calibration… are refused until a gain has been entered** (typed into the
  field), also in simulation.
* The line below the fields shows the **estimated loudspeaker drive** for the current settings:
  voltage (Vpk), current (peak) and power, the loudspeaker power limit and the generator amplitude
  limit, e.g. "Estimated loudspeaker drive: 0.0138 Vpk, 1.72 mA peak, 11.9 µW (limit 1 W).
  Generator limit 1 Vpk." It turns red above a limit, while the gain is not entered, or when the
  power limit is set above the rated power of the loudspeaker (`loudspeaker.ratedPower_W`).
* The expected **Duration** is repetitions × (pre-roll + sweep duration + post-roll + 0.2 s) for
  the swept sine and repetitions × (1 s + steps × (settling + recording time)) for the stepped
  sine. The connection, the confirmation and the processing come on top.

### CALIBRATION

* **Calibration** shows the active calibration:
  * "No calibration – results not valid" (red): without a calibration no result is ever valid;
  * `CAL-yyyyMMdd-HHmmss`, followed by "✓ empty-tube check" when its Test E passed, or
    "✗ empty-tube check FAILED" (orange);
  * "– check" (orange) is appended when the calibration does not fit the set-up in the fields:
    temperature more than 3 K different, port distances changed, other operating mode, or Test E
    failed. The tooltip lists the reasons;
  * "… (used at Connect)" (grey): a calibration file chosen while not connected; it is loaded at
    the next Connect. "… not found" (red): the configured file does not exist.
* **Load calibration…** loads a `CAL-*.mat` file from the calibration folder. The file name is
  also stored by File > Save configuration…, so the next session starts with it.
* **Run switching calibration…** runs the switching calibration with the empty specimen section
  (needs a connection; `calibration_procedure.md`).

### MEASUREMENT

* **Specimen**: name of the specimen. It becomes part of the data folder name when the measurement
  is saved (section 12); the name in the field at the moment of Save measurement counts.
* **Start measurement** (green): measures with the selected signal. In hardware mode it asks before
  the loudspeaker is driven (section 3). The Time signals view shows the four channels live.
* **Stop** (red): stops the running action; the generator output is switched off at once.
* **Measure background noise**: 2 s without excitation (background noise of every channel); then
  the Spectrum view opens.

### RESULTS

* **Last result**: "No measurement"; "Swept sine 11:15:37 – not saved" (red) after a measurement;
  "Saved: `<folder>`" (green, the tooltip gives the full path) after Save measurement.
* **Save measurement**: raw data, results, configuration, metadata, CSV files and figures into a
  new folder under `data\` (section 12).
* **Reprocess**: computes the results of the last measurement again with the current IMPEDANCE TUBE
  fields (geometry, temperature, pressure) and the active calibration, e.g. after correcting a
  distance or loading another calibration. Save measurement again to keep the new results (a new
  folder; the first one is not changed).

### Which buttons are available

| Control | Enabled when |
|---|---|
| Operating mode, Connect | not connected |
| Disconnect | connected (also after a failed connection) |
| Start measurement, Measure background noise, Run switching calibration… | the connection is complete (status "Ready") |
| Stop | only while an action runs |
| Save measurement | a measurement or a background-noise record exists |
| Reprocess | a measurement exists (not for background noise) |
| Amplifier gain | an amplifier other than "none (direct drive)" is chosen |
| everything else, menus | no action running |

## 5. Workflow step by step

1. **Start** the window (section 1). The message pane says "Ready (… mode). Not connected …".
2. Check the **Operating mode**. It cannot be changed while connected.
3. Press **Connect**. Setup > Connection opens and lists every step with its result and duration
   (section 6). Read the line above the list: "Connected - all checks passed.", "Connected with
   warnings …" (orange items) or "Connected, but a check FAILED …" (red items). Check the
   sensitivity source of every channel and the background level of the signal check.
4. Check the **IMPEDANCE TUBE** fields against the tube (D, T, p, s1, L1, d, L2, s2) and look at
   Setup > Tube setup. Enter the measured temperature and static pressure. Store the values with
   File > Save configuration… and commit `config/user_config.json`.
5. Set the **EXCITATION**: Signal, frequency range (wider than the analysis band, e.g. 80–5500 Hz),
   sweep duration or number of steps, repetitions, a low Amplitude, the Amplifier and its gain, the
   loudspeaker data. Read the estimated loudspeaker drive and the expected duration.
6. Optional: **Measure background noise** and check the Spectrum view.
7. **Calibration**: Load calibration… (an existing `CAL-*.mat` that fits the set-up), or Run
   switching calibration… (`calibration_procedure.md`; 12 operator steps, about 5 min of sweeps
   with the default settings). The Calibration line must show the version and "✓ empty-tube
   check".
8. Mount the **specimen section with the specimen**, check L1, d and L2 for this specimen, and
   enter its name in **Specimen**.
9. Press **Start measurement**. In hardware mode confirm the excitation dialog (**Start
   excitation**). The Time signals view shows the last 0.5 s of every channel live ("LIVE · 3.2 s
   recorded …") with the level of every channel in the header. Stop ends the measurement at once.
10. Check the result: Measurement > Transfer functions (coherence and SNR against their limits),
    the Results views and Results > Validity (why frequency lines are not valid). The message pane
    gives the summary line of the validity masks.
11. Press **Save measurement**. Last result turns green: "Saved: `<folder>`".
12. If a distance, the temperature or the calibration was wrong: correct it, press **Reprocess**
    and **Save measurement** again.
13. Next specimen: change the specimen and its name, Start measurement. An unsaved measurement is
    not replaced without a question.
14. At the end: **Disconnect** or close the window (File > Exit).

In simulation mode there is no excitation dialog, and during the switching calibration the
virtual microphones are moved by the program; everything else is the same.

## 6. The views

### Setup > Connection

* The **Connection checklist**, one row per step with a status icon (turning icon = running), the
  result and the duration: function generator 33220A (SCPI, output off); LAN-XI module (REST);
  recorder state Idle (returned to Idle if needed); open recorder; TEDS transducer detection;
  channel setup → streaming; microphone sensitivities (order certificate → TEDS → nominal);
  settling of the CCLD supply and the high-pass filter (hardware only); **signal check** (1 s
  without excitation). A failing step is marked red with the error message, and the line above
  the list names it.
* One **card per channel**: "ch1 → port M1", status, TEDS type and serial number, sensitivity and
  its source, the level of the signal check in dB SPL. Orange "check: …" for no TEDS, a nominal
  sensitivity or a TEDS serial number that differs from the configuration; red "FAULT" for a
  failed signal check (LAN-XI flag INVALID: cable or CCLD fault; clipped; no signal; overload).
* A **table**: Channel, Port, Microphone, Sensitivity [mV/Pa], Source, TEDS s/n, Level [dB SPL],
  Signal check.

A slow step such as the LAN-XI channel setup (more than 10 s) keeps its turning icon, because the
window animates it while MATLAB waits for the instrument.

### Setup > Tube setup

A **3D model** of the tube built from the IMPEDANCE TUBE fields: loudspeaker housing, tube, the
specimen section with the specimen (a generic block; d < 1 mm is drawn as a thin plate in the
joint), the microphones in their holders and the termination. Each microphone carries the colour
of the LAN-XI channel in that port. The dimension lines s1, L1, d, L2, s2 (black) and the overall
lengths (grey) follow every change of a field at once; the viewpoint is kept.

* Header buttons: **Default** (side view, slightly from above), **Side** (like a 2D drawing),
  **Perspective**, **Top**; rotate, zoom and pan with the toolbar of the drawing.
* **Section view** removes the half towards the viewer (cut faces hatched), so that the bore, the
  specimen and the microphone tips are visible; microphones, holders and bolts are drawn whole, as
  in a technical drawing. **Dimensions** shows or hides the dimension lines.
* Summary **Geometry**: inner diameter, s1, s2, L1, d, L2, x(M1)…x(M4), speed of sound,
  geometric validity range, cut-on frequency of the (1,1) mode, analysis band.
* Without L1, d and L2 the header note says that the model is schematic and the specimen results
  are disabled.

The part sizes come from the `tubeDrawing` section of the configuration (CAD values: flanges and
specimen section Ø65 mm, tube body Ø45 mm, flanges 9 mm with 6 × M4, bore end 95 mm before M1,
termination 291 mm after M4, loudspeaker housing Ø135 mm, microphone holders Ø22 mm, B&K 4957
Ø7 × 34.1 mm with the tip 0.25 mm behind the bore wall). `tubeDrawing.absorberLength` [m] is the
length of the absorbing material in the termination behind M4, drawn from the end cap towards the
specimen; `null` = not known (the label then reads "(absorber side)", the calibration model shows a
schematic absorber). Enter it in `config/user_config.json` (no field in the window). These values
are used only for the drawings. `tim.cad.readStep` reads a STEP assembly (part names, cylinders,
planes, placements) if the tube is changed.

### Calibration

The view of the switching calibration (details in `calibration_procedure.md`): an instruction
line ("Calibration step 4 of 12: …"), the 3D model in its calibration state (empty specimen
section, absorbing termination, calibration ports M1 (a) and M2 (b) glowing yellow, microphones
labelled with their channel and serial number), the **operator steps and the quality of every
measurement**, and the calibration factors |C_k| [dB] and ∠C_k [°] of ch2, ch3, ch4 relative to
ch1 (grey = not valid). The header note gives the result of the empty-tube check (Test E). The
summary table "Calibration factors Ck = gk/gref" gives per channel the share of valid frequency
lines, the range of magnitude and phase over the valid lines and the remounting repeatability.
Before any calibration the view says "No calibration loaded – use Load calibration… or Run
switching calibration…".

### Measurement > Time signals

Sound pressure (voltage / sensitivity) of the four channels, one graph per channel on a common time
axis, labelled "ch1 (M1) [Pa]" etc. During an acquisition: the last 0.5 s, about five updates per
second, the header note gives the live level of every channel. After the measurement: the whole
record of repetition 1, long records as a min / max envelope so that every peak stays visible. A
display high-pass at 20 Hz removes the slow CCLD settling drift; the raw data are not changed and
are stored in volts. Without a valid sensitivity for every channel the graphs show mV.
Summary **Channels**: Channel, Port, Peak [Pa], Level [dB SPL] (rms of the displayed record,
including pre- and post-roll), Sensitivity [mV/Pa], Source (TEDS, Certificate, Nominal).

The LAN-XI deliberately streams **volts** (module default transducer, sensitivity 1 V/V). The
sensitivity (certificate > TEDS > nominal) is applied once, in software, so it can never be applied
twice.

### Measurement > Spectrum

* Swept sine, random noise and background noise: **power spectral density** of the sound pressure
  of repetition 1 in dB re (20 µPa)²/Hz (Welch, Hann window, 50 % overlap), one curve per channel,
  the analysis band between two dashed lines. Summary **Levels**: the level in the analysis band
  and the overall level (20 Hz to half the sample rate), from the integrated PSD of the whole
  record.
* Stepped sine: the PSD of a stepped record is a line spectrum (one line per step) and is no level
  display. After processing the view shows the **level of every step** (sine fit of the settled
  part, markers, dB SPL) and, dotted, the residual noise in the bandwidth of the fit. Summary
  **Step levels**: minimum and maximum step level and the median SNR per channel. Before
  processing the raw PSD is drawn grey with this explanation.

### Measurement > Transfer functions

Three graphs on one frequency axis: |H| [dB], phase [°] and coherence, where `H = p(port)/p(ref)`
is the **calibrated** transfer function of each port M1…M4 relative to the reference channel
(ch1 by default). Every curve has the colour of the channel in that port; legend "M1 (ch1)". The
phase is unwrapped (stepped sine: wrapped to ±180° and drawn as markers). The coherence graph
shows every channel except the reference, with a dashed line at the limit ("Limit 0.98"). Summary
**Signal quality**: per port the median coherence, the minimum SNR and the share of frequency lines
in the analysis band that meet both limits (`analysis.coherenceMin`, `analysis.snrMin_dB`). The
header note says "NOT calibrated" without a calibration and counts the frequency lines without a
value (outside the calibrated range).

### Results > Reflection and transmission

Top graph: |R| at the specimen front face (mask `validR`), |τ| from the front face to the rear face
and the dissipation coefficient α_d = 1 − |R|² − |τ|² (both mask `validTau`), |R_term| of the
termination (dotted; grey where the downstream pair is not reliable) and the limit up to which the
termination counts as anechoic (dashed, `analysis.anechoicRmax` = 0.1). Bottom graph: the phase of
R. Summary **Octave bands**: mean |R|, |τ| and α_d over the valid frequency lines of each octave
band 125–4000 Hz (centre/√2 to centre·√2); "–" = no valid line. |τ| and α_d need an anechoic
termination.

### Results > Transmission loss

Normal-incidence transmission loss **TL from τ** = −20 log10 |τ| (solid; needs an anechoic
termination, mask `validTau`). For a thin specimen also the **TL from Z_t** =
20 log10 |1 + Z_t/(2ρc)| (dashed, independent of the termination, mask `validThinZt`). For a thick
specimen (k·d > 1 in the analysis band) the TL from Z_t is not drawn and the note says why.
Summary **Octave bands**: energy mean over the valid lines, TL = −10 log10(mean |τ|²).

### Results > Transfer impedance

Re{Z_t}/(ρc) (top) and Im{Z_t}/(ρc) (bottom) of the thin-element model,
Z_t = (p_front − p_rear)/u with u the mean of the front- and rear-face velocities (mask
`validThinZt`: velocity match across the specimen). Only meaningful for a thin specimen (k·d ≪ 1):
when k·d exceeds 1 in the analysis band the graphs stay empty with the message "Thin-element model
not applicable: d = 75 mm (k·d up to 6.2)" and a pointer to Transmission loss and Reflection and
transmission. This is the case for the 75 mm lab specimen section. Summary **Octave bands**: mean
Re and Im over the valid lines; the note gives ρc. Without L1, d and L2 the view says that the
specimen face positions are unknown.

### Results > Validity

One row per criterion, the frequency lines that pass in dark blue, the others light grey:
"Measured (in band)" (inside the analysis band, with data), "Geometry OK", "Quality OK (coherence,
SNR, cal.)", "Passive", **"Valid"**, "Valid R", "Valid τ / TL", "Valid thin Z_t", "Validated
(experiment)". Below a separator one row per rejection reason ("Rejected: low coherence",
"Rejected: termination not anechoic", …), red where it rejects.
Stepped sine: one square per step. Summary **Validity criteria**: number and share of passing
lines and which results each criterion affects; the note is the summary line of the masks.
"Valid R" uses only the upstream pair M1/M2 (section 10) and may therefore pass where "Valid" does
not.

### Formula

Every equation used by the program, with the default thresholds read from the code: 0 conventions
and symbols; 1 transfer functions (swept sine, stepped sine, random noise); 2 switching
calibration; 3 plane-wave decomposition; 4 pressure and particle velocity at the specimen faces;
5 reflection, transmission and dissipation; 6 transfer impedance; 7 transmission loss; 8 transfer
matrix (scripts only); 9 air properties and tube losses; 10 geometric validity range; 11 validity
criteria; 12 units and level references. The derivations are in `theory.md`.

## 7. Menus

* **File**: Load configuration…, Save configuration…, Exit.
  * *Load configuration…* asks about an unsaved measurement; when connected it asks "Disconnect and
    load" (the operating mode, the microphones and the calibration settings belong to the
    connection). The last measurement is cleared.
  * *Save configuration…* writes the fields of the control panel (excitation, amplifier,
    loudspeaker, geometry, temperature and pressure, calibration file) into a JSON file; the
    default is the file that was loaded. Commit `config/user_config.json` afterwards.
  * *Exit* closes like the window's X (section 3).
* **Help**: User guide, Calibration procedure, Validation procedure, Installation (Windows) – the
  documents of `docs/`, opened in the MATLAB Editor; Source code on GitHub (web browser);
  **About**.
* **Help > About** shows the program, the software version and release date, the Git commit and
  branch, the MATLAB release and the repository link
  (<https://github.com/kimwoongji/transfer-impedance-tube-measurement>, private). The text can be
  selected and copied.

The version, the repository and the commit are stored with every measurement (`metadata.json`,
field `softwareInfo`, and `README.txt`) and calibration (`cal.meta.softwareInfo`). The commit is
read from the `.git` folder; **local changes that are not committed are not detected**, so commit
before measuring if the code was edited. Without a `.git` folder (copied project) the commit is
"unknown".

## 8. Excitation signals

| Signal | Use | Main settings (`excitation.*`) |
|---|---|---|
| `sweep` (swept sine, default) | broadband, fast, robust | `fStart` 80, `fStop` 5500 Hz (wider than the analysis band), `duration` 5 s, `spacing` `LOG`/`LIN`, `amplitudeVpp`, `repetitions` 4 (≥ 2 gives a meaningful coherence), `preRoll` 1 s (silence for the noise estimate), `postRoll` 1 s (ring-down) |
| `stepped` (stepped sine) | highest SNR at chosen frequencies, cross-check | `fStart` 120, `fStop` 4500 Hz, `nPoints` 40, `spacing` `log`/`lin`, `settleTime` 0.3 s, `recordTime` 0.5 s, `nBlocks` 4, `repetitions` 1 |
| `noise` (random noise, scripts only) | 33220A built-in noise, Welch H1 | `amplitudeVpp`, `duration` 20 s, `nfft` 8192 |

* The 33220A and the LAN-XI module are **not synchronised**. The sweep is triggered by software
  (`*TRG`) once the pre-roll has been received and switched off after `*OPC?` reports completion.
  The analysis uses only ratios between microphones, so timing uncertainty, the generator clock
  and the exact sweep law do not matter (`theory.md` section 4). The sweep must lie inside the
  recording; this is checked and reported (`res.diagnostics.excitation`, `sweepLaw`).
* Stepped sine: the first and the last step are exactly `fStart` and `fStop` (a step at 120 Hz is
  inside the default analysis band). Each step is evaluated by a sine fit of the settled part, in
  `nBlocks` blocks. The SNR of a step is the tone power over the noise power in the bandwidth of
  the fit (`theory.md` section 5); it enters the validity masks like the SNR of the sweep.
  All results are drawn with markers at the step frequencies (also in the saved figures and in
  `spectra.csv`: `level<c>_dB_SPL`, `noise<c>_dB_SPL`).
* The switching calibration always uses the swept-sine settings (frequency range, duration,
  repetitions) and the Amplitude, whichever Signal is selected.

## 9. Configuration (`config/user_config.json`)

`tim.app.loadConfig` merges the file onto the defaults of `tim.app.defaultConfig`; a key that is
missing in the file keeps its default. Lengths in metres, amplitudes in Vpp (the window shows Vpk
= Vpp/2), NaN / `null` = not provided (the program never guesses a value).

| Key | Default | Meaning |
|---|---|---|
| `mode` | `"simulation"` | `"simulation"` or `"hardware"` (lab file: hardware) |
| `ui.language` | `"en"` | `"en"` or `"ko"`: operator prompts and dialog buttons of the calibration steps, the excitation confirmation and the channel identification. Logs and window labels stay in English. |
| `generator.host`, `port` | 169.254.2.20, 5025 | 33220A (SCPI over TCP) |
| `generator.maxVpp` | 0.5 (lab file 2) | **amplitude limit** of the programmed amplitude in Vpp, at most 20 Vpp |
| `generator.load` | `"INF"` | 33220A output load setting, see below |
| `amplifier.model` | `""` | `"none (direct drive)"` (must start with "none"), `"power amplifier"` or a model name |
| `amplifier.gainFactor` | NaN | voltage gain as a factor (×10 = 10 = 20 dB); 1 for direct drive; `gain_dB` is derived |
| `amplifier.gainSetting` | `""` | free text, e.g. the knob position (scripts) |
| `amplifier.inputImpedance_ohm` | NaN | amplifier input impedance; NaN = from `generator.load` |
| `amplifier.knownModels` | none (direct drive), power amplifier | items of the Amplifier list |
| `amplifier.confirmBeforeExcitation` | true | excitation confirmation in hardware mode |
| `loudspeaker.impedance_ohm` | 8 | nominal impedance (field Loudspeaker [Ω]) |
| `loudspeaker.maxPower_W` | 1.0 | loudspeaker power limit (field Power limit [W]) |
| `loudspeaker.ratedPower_W` | 25 | rated power: a power limit above it is flagged |
| `lanxi.host`, `connector` | 169.254.64.156, `"BNC"` | LAN-XI module; `"BNC"` or `"LEMO"`, whichever the microphones use |
| `acquisition.sampleRate` | 16384 | 4096, 8192, 16384, 32768 or 65536 Hz |
| `acquisition.range`, `filter` | `"10 Vpeak"`, `"0.7 Hz"` | input range and high-pass filter |
| `acquisition.settleTime` | 3 | seconds of CCLD / high-pass settling after the channel setup (hardware) |
| `acquisition.sensitivityPolicy` | `"certificate>teds>nominal"` | order of the sensitivity sources |
| `mics(i)` | ch1–ch4 in M1–M4 | `channel` (LAN-XI input), `position` (port 1–4 = M1–M4, M1 nearest the loudspeaker), `model`, `serial`, `nominalSensitivity_VperPa` (11.2 mV/Pa), `certificateSensitivity_VperPa`, `certificateDate` |
| `geometry` | D 29 mm, positions NaN | `diameter` (D), `micPositions` (x of M1–M4), `spacingUp`/`spacingDown` (s1, s2), `xFront`, `xRear`; written by the IMPEDANCE TUBE fields |
| `tubeDrawing` | lab CAD | part sizes for the drawings only |
| `environment` | 20 °C, 101325 Pa | `temperature_C`, `pressure_Pa`; `c_override`, `rho_override` replace the computed values; `relativeHumidity` is recorded only |
| `excitation` | section 8 | `mode` and the settings of `sweep`, `stepped`, `noise` |
| `analysis.refChannel` | 1 | reference channel of the transfer functions |
| `analysis.fMin`, `fMax`, `df` | 120, 4500, 2 Hz | analysis band and frequency-line spacing (`fMax` ≤ 0.45 × sample rate) |
| `analysis.lossModel` | `"kirchhoff"` | tube-loss model: `"kirchhoff"` (visco-thermal wall losses, attenuation and phase-velocity reduction, matching characteristic impedance), `"iso10534"` (ISO 10534-2 attenuation only, for ISO-conformant work) or `"none"`. The same model is used by the analysis, Tests D/E and the virtual tube (`theory.md` section 1). |
| `analysis.velocityRef` | `"mean"` | velocity in Z_t: `"mean"`, `"upstream"` or `"downstream"` |
| `analysis.coherenceMin`, `snrMin_dB` | 0.98, 20 dB | quality limits of the validity masks |
| `analysis.condMax`, `phaseUncertainty_rad`, `maxPhaseSensitivity` | 40, 0.002, 0.05 | geometry limits of the decomposition |
| `analysis.lowerFraction`, `upperFraction` | 0.01, 0.40 | spacing limits 0.01·c/s < f < 0.40·c/s |
| `analysis.passivityTol`, `velocityMismatchMax`, `anechoicRmax` | 0.05, 0.10, 0.1 | passivity, thin-element and anechoic-termination limits |
| `analysis.validatedBands` | empty | experimentally validated bands (`validation_procedure.md`) |
| `calibration.file` | `""` | calibration loaded at Connect |
| `calibration.positions` | [1 2] | calibration ports a and b |
| `calibration.repeatConfigI`, `verifyEmptySection` | true, true | repeated configuration I; empty-tube check (Test E) |
| `calibration.coherenceMin`, `snrMin_dB` | 0.98, 20 dB | quality limits of the calibration |
| `output.dataDir`, `calibrationDir` | `data`, `calibration` | output folders |
| `output.saveRawStream`, `exportCsv`, `exportFigures`, `figureFormats` | true, true, true, png + pdf | what Save measurement writes |
| `simulation` | – | the virtual tube (geometry, specimen, termination, noise, generator clock error) |

**Amplitudes**: the window and all messages use **Vpk** (generator peak voltage). The
configuration stores `amplitudeVpp` and `generator.maxVpp` (= 2 × Vpk), the unit the 33220A is
programmed in.

**Generator output load (`generator.load`)**. The 33220A source impedance is always 50 Ω; the
OUTP:LOAD setting only changes what the programmed amplitude means:

| `generator.load` | Programmed amplitude is | Open-circuit voltage | Use |
|---|---|---|---|
| `"INF"` (default) | the open-circuit voltage | = programmed | direct drive; amplifier with a high-impedance input |
| `"50"` | the voltage across a 50 Ω load | 2 × programmed | only an amplifier with a 50 Ω input (rejected with direct drive) |

The amplitude field and the amplitude limit always refer to the programmed value. The drive
estimate uses `V_in = V_oc·Z_in/(Z_in + 50 Ω)` at the amplifier input, with
`Z_in = amplifier.inputImpedance_ohm`; when that is NaN, `"INF"` means a high-impedance input
(`V_in = V_oc`) and `"50"` a 50 Ω input (`V_in` = programmed value). The loudspeaker voltage is
`V_in` × gain (amplifier output impedance ≈ 0) and the power `P = V_spk,pk²/(2Z)`.

## 10. Results and how to read them

`res.analysis` (`tim.acoustics.analyzeFourMic`):

| Field | Meaning | Valid only if |
|---|---|---|
| `R` | complex pressure reflection coefficient at the front face, from the upstream pair M1/M2; the as-mounted value (specimen with the actual termination) | `valid.validR` |
| `tau` | forward wave at the rear face / incident wave at the front face | `valid.validTau` (needs `\|Rterm\| ≤ anechoicRmax`) |
| `Rterm` | reflection of the downstream termination, at the rear face | diagnostic |
| `thin.Zt`, `thin.Zt_norm` | thin-element transfer impedance `(pL − pR)/u` [Pa·s/m] and `Zt/(ρc)` (meaningful only for k·d ≪ 1) | `valid.validThinZt` (velocity mismatch ≤ 10 %) |
| `thin.velocityMismatch` | `\|uL − uR\|/max(\|uL\|, \|uR\|)` | – |
| `thin.TL_dB` | TL from Z_t: `20·log10\|1 + Zt/(2Zc)\|` (anechoic-equivalent, termination independent) | `valid.validThinZt` |
| `power.TL_tau_dB` | `−20·log10\|τ\|` from the measured τ | `valid.validTau` |
| `power.Rpow`, `tauPow`, `alpha` | power fractions \|R\|², \|τ\|²; `alpha` = dissipation coefficient α_d = 1 − \|R\|² − \|τ\|² | `validR` (`Rpow`), `validTau` (`tauPow`, `alpha`) |
| `boundary.pL, uL, pR, uR` | extrapolated face values (relative units) | geometry complete |
| `waves.A1, B1, A2, B2`, `cond1`, `cond2` | wave amplitudes, condition numbers | – |
| `local.R_up_atM2`, `R_dn_atM3` | pair-local reflection (no geometry needed) | – |
| `air`, `k` | air properties (c, ρ from the ideal-gas law, ρc) and the complex wavenumber of the loss model | – |
| `valid.*` | masks, the reason for every rejection (`valid.flags`), `valid.upstream` (masks of the upstream pair), `valid.summary` | – |

* `validR` uses **only the upstream pair** M1/M2: its geometry (spacing s1), the coherence and SNR
  at M1 and M2, the calibration and |R| ≤ 1 + `passivityTol`. A rigid plug in front of M3/M4 or a
  high-TL specimen with a weak downstream signal does not reject R.
* `validTau` and `validThinZt` use both pairs (`valid`) plus their own condition.
* The near-singularity criterion (k·s close to π) is tested separately for each pair.
* For a thick specimen (the 75 mm lab specimen section: k·d up to about 6 at 4.5 kHz) the
  thin-element Z_t has no meaning. Use R, τ and the TL from τ (anechoic termination), or the
  transfer matrix (two loads, scripts only).

Transfer matrix (scripts only; needs two measurements of the same specimen with **different
terminations**):

```matlab
resA = tim.app.processMeasurement(measA, cfg, cal);   % e.g. anechoic termination
resB = tim.app.processMeasurement(measB, cfg, cal);   % e.g. rigid / open termination
tm = tim.acoustics.transferMatrix('twoLoad', resA.analysis, resB.analysis);
% tm.T11..T22, tm.condQ (check!), tm.TL_dB, tm.tau_anechoic, tm.reciprocityError
```

`transferMatrix('oneLoadSymmetric', res)` is available **only** for specimens that are known to be
reciprocal and symmetric.

**Levels of trust**: *in the analysis band* → *geometry criteria met* → *quality criteria met*
(coherence, SNR, calibration) → *valid* (also passive) → *validated* (inside the experimentally
validated bands, `analysis.validatedBands`, which stay empty until Tests D/E have passed on this
set-up). Graphs draw values that are not valid in grey. The CSV files contain every mask and flag.

## 11. Script use

```matlab
cfg = tim.app.loadConfig('config/user_config.json');
s = tim.app.MeasurementSession(cfg);
s.connect();  s.prepareAcquisition();          % generator output off, TEDS read
chk = s.signalCheck(1);                         % 1 s without excitation, per channel
bg = s.measureBackground(2);                    % background noise
s.setAmplifierGain('none (direct drive)', 1);   % or e.g. ('XYZ amplifier', 10) for ×10
s.loadCalibration('calibration/CAL-20261009-101500.mat');   % or: cal = tim.app.runCalibration(s);
meas = s.measure('sweep');                      % explicit start ('sweep' | 'stepped' | 'noise')
res  = tim.app.processMeasurement(meas, s.Cfg, s.Calibration);
figs = tim.app.plotResults(res, meas);          % the same views as the window
folder = tim.app.saveMeasurement(meas, res, s.Cfg, 'foam_25mm', figs);
s.close();
```

* In hardware mode the excitation confirmation appears in the command window ("Type y to
  continue …"); `s.ExcitationConfirm = @(msg) …` replaces it.
* `s.setExcitation(ex)`, `s.setLoudspeaker(Z, Pmax)` and `s.setGeometryEnvironment(geom, env)`
  change settings between measurements (validated). A change of amplifier or amplitude asks for a
  new confirmation.
* The switching calibration from a script prints every step in the command window and waits for
  Enter (`calibration_procedure.md`).

Processing can be repeated offline at any time, e.g. with corrected geometry or another
calibration:

```matlab
S = load('data/<folder>/raw.mat');  cfg2 = tim.app.loadConfig('config/user_config.json');
C = load('calibration/CAL-20261009-101500.mat', 'cal');
res2 = tim.app.processMeasurement(S.meas, cfg2, C.cal);
```

## 12. Stored data

**Save measurement** writes a new folder `data\<yyyyMMdd_HHmmss>_<signal>_<specimen>\`, e.g.
`20261009_111537_sweep_foam_25mm` (`<signal>` = sweep, stepped or background; characters other
than letters, digits, `_` and `-` in the specimen name become `_`; without a name the folder ends
with the signal). Folders are never overwritten; a suffix `_2`, `_3`, … is added if needed.

| File | Content |
|---|---|
| `raw.mat` | `meas`: raw volts of every repetition, settings, generator events, microphones and sensitivities, metadata (instrument identities, firmware, TEDS, LAN-XI setup, amplifier, configuration) and the undecoded stream bytes of the last repetition |
| `result.mat` | `res` (spectra, calibration info, analysis, validity); not for background noise |
| `config.json`, `metadata.json` | configuration snapshot; metadata including `softwareInfo` |
| `results.csv` | one row per frequency line: R, τ, R_term, Z_t, TL, power fractions, condition numbers, every mask and flag |
| `spectra.csv` | transfer functions per channel, coherence, SNR; stepped sine also the step levels |
| `fig_*.png`, `fig_*.pdf` | the figures (PNG 200 dpi, vector PDF; `output.figureFormats`) |
| `README.txt` | time, mode, software version, repository and commit |

The **saved figures** are drawn by the same views as the window (`tim.app.plotResults`): header
(title, description, note), the graphs, the summary table on the right, the software version in
the footer and a red "SIMULATED DATA" mark for simulated data. File names: `fig_waveforms` (Time
signals), `fig_spectrum`, `fig_transfer` (Transfer functions), `fig_reflection`,
`fig_transmissionLoss`, `fig_impedance` (Transfer impedance), `fig_validity`. A background-noise
record is saved without results, CSV files and figures. The calibration view is drawn by
`tim.app.plotCalibration(cal)`; it is not saved with a measurement.

Simulated measurements are labelled "SIMULATED DATA" in `README.txt` and in the metadata, and are
stored separately in `data\simulation\` and `calibration\simulation\`, so they cannot be confused
with real measurements and calibrations.

**Practising without hardware**: `tubeapp sim` (or
`app = tim.gui.TubeApp('config/sim_thin_screen.json')`) opens the window on a virtual tube with a
thin resistive screen (Z_t = 400 + jω·0.05 Pa·s/m). Press Connect, Run switching calibration…,
then Start measurement. The Transfer impedance and Transmission loss views show the results.

## 13. Troubleshooting

| Symptom | Likely cause / action |
|---|---|
| Start measurement is greyed out | not connected, or the connection is incomplete: Disconnect, remove the cause, Connect |
| Alert "Check the settings" | a field is not valid (e.g. the stop frequency is not above the start frequency, L1, d or L2 is not a number): correct it and start again |
| "enter the voltage gain set on the amplifier …" or "Amplifier gain not entered" | an amplifier is chosen: type its gain into Amplifier gain |
| Excitation refused: estimated loudspeaker power exceeds the limit | lower the Amplitude or the amplifier gain, or raise Power limit [W] deliberately |
| Signal check: LAN-XI flag INVALID on all channels, no TEDS | microphones not connected, or wrong connector (`lanxi.connector` BNC ↔ LEMO), cable fault |
| Card "check: nominal sensitivity" | no certificate value and no TEDS: enter `certificateSensitivity_VperPa` |
| Card "check: TEDS serial differs from the configuration" | microphone on the wrong channel, or `mics(i).serial` outdated |
| `tim:lanxi:state` | the module is in an unexpected state: Disconnect returns it to Idle (`s.Daq.shutdown()` in scripts) |
| HTTP 403 | request not allowed in the current recorder state (another client? BK Connect open?) |
| `tim:lanxi:streamStalled` | network interruption or module stopped; partial data saved in `data\emergency` |
| `tim:gen:amplitude` | requested amplitude above `generator.maxVpp`, or changed at the front panel |
| `tim:gen:scpiError` | the 33220A reported an error (message included); output switched off |
| "Excitation not detected" | amplifier off or muted, loudspeaker disconnected, level too low |
| Calibration "– check" (orange) | hover over it: temperature changed by more than 3 K, port distances changed, other mode or Test E failed: recalibrate |
| Few valid frequency lines | Results > Validity: "no valid calibration" (load or run a calibration), low coherence / low SNR (amplitude, repetitions), termination not anechoic (τ, TL), velocity mismatch (thick specimen: thin-element Z_t not applicable) |
| Transfer impedance view empty, "Thin-element model not applicable" | the specimen is thick (k·d > 1): use Reflection and transmission and Transmission loss |
