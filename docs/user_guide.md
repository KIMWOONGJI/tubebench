# Measurement user guide

This guide describes the program **tubebench** (four-microphone transfer-impedance tube
measurement): the window (`tubebench`), the safety behaviour, the configuration file and the
script interface. The switching calibration has its own document (`calibration_procedure.md`),
the hardware tests theirs (`validation_procedure.md`), and the formulas are in `theory.md` and in
the **Formula** tab of the window.

## 1. First steps

1. Read `installation_windows.md`, then run `run_tests` once. All tests must pass
   (`run_tests('fast')` leaves out TestEndToEnd and the two hidden-window app runs).
2. Check `config\user_config.json` (tracked in Git; it holds the lab settings, see section 9).
   Create it from `config\example_config.json` only if it does not exist. Commit it after
   changes, so that the history keeps the measured geometry.
3. Start the window:
   * double-click `start_tubebench.bat` (real instruments, `config\user_config.json`), or
     `start_tubebench.bat sim` (virtual tube for practice, `config\sim_thin_screen.json`). It
     starts MATLAB without its desktop (faster); a small MATLAB command window stays open behind
     the program, also after the program is closed: type `tubebench` there to open the program
     again, and `exit` (or close that window) to quit MATLAB;
   * or type `tubebench` / `tubebench sim` / `tubebench myconf.json` in MATLAB.

   For script-based use, run `start_here.m` section by section (section 11).

## 2. The window

The main window appears about 16 s after a double-click on `start_tubebench.bat` (about 11 s
after MATLAB has started; in a MATLAB that is already running about 6–9 s). Meanwhile a small
start window shows the logo, the program name, the version, the author's site, a progress bar
and the current step (control panel, Connection view, settings); its turning icon keeps moving
while MATLAB is busy.
It closes by itself when the main window appears; closing it earlier does not stop the start.

The main window can be used at once: the menus, the control panel, the Messages pane, every tab
and the view Setup > Connection are ready. The other views are prepared in the background, one
after the other (Tube setup, Calibration, Time signals, Spectrum, Transfer functions, Two-load,
the five Results views, Formula). The Messages pane shows "Preparing the views in the background…" and,
about 20–25 s later, "All views ready (… s after the start)".

* A view that is not prepared yet shows "Preparing the view…". Opening it prepares it at once
  (1–3 s; the 3D models wait until the window has given the view its size).
* While a view is being prepared, a click is answered after a moment (at most about 3 s).
* Nothing is prepared in the background while an action runs (connection, measurement,
  background noise, calibration, saving, loading): a step of 1–3 s would interrupt the data
  stream of the acquisition module (LAN-XI). Every action prepares the views it uses **before**
  it starts, e.g. Start measurement the Time signals view, the calibration the Calibration view.
  A view opened during an action says "This view is prepared when the running action has
  finished" and is prepared first afterwards.
* A view prepared later shows the data of then (last measurement, results, calibration,
  IMPEDANCE TUBE fields).
* Scripts that use the window (`app = tubebench(...)`) can wait for every view with
  `app.ensureBuilt('all')`.

The window title is "tubebench". It opens as a normal window as large as the screen without the taskbar (it can be moved and resized) and has four parts:

* the **menu bar** (File, Help; section 7);
* the **control panel** on the left, in workflow order: INSTRUMENTS, IMPEDANCE TUBE, EXCITATION,
  CALIBRATION, MEASUREMENT, RESULTS (section 4). It fits a 1920 × 1080 screen without scrolling
  and scrolls only in a small window;
* the **views** on the right, in two levels of tabs (section 6):

  | Tab | Sub-tabs |
  |---|---|
  | Setup | Connection, Tube setup |
  | Calibration | – |
  | Measurement | Time signals, Spectrum, Transfer functions, Two-load |
  | Results | Reflection and transmission, Transmission loss, Transfer impedance, Validity, Transfer matrix |
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
  frequency lines in colour on top (a single valid line between two that are not valid as a
  coloured dot). Nothing is shown as valid just because it is finite. Stepped sine: one marker
  per step (filled = valid, hollow grey = not valid); a step without any value is marked by a
  hollow triangle on the frequency axis;
* channel colours: ch1 blue, ch2 raspberry, ch3 bluish green, ch4 dark yellow (darkened so that
  it stays visible on white); every channel is also labelled. Physical quantities (R, τ, α_d, TL,
  Z_t) use black, orange, sky blue and grey, never a channel colour;
* every graph has a small toolbar: export, zoom in / out, pan, restore view. After a zoom the
  ticks are automatic; "restore view" brings back the fitted limits of the data shown now and the
  octave ticks.

## 3. Safety behaviour

* **Connect always switches the generator output off**, and it stays off while you configure.
* The output can be switched on only inside a measurement that you started: **Start
  measurement** or a step of the switching calibration. It is switched off as soon as the
  excitation ends and locked again after the measurement. **Background noise** and the
  signal check of Connect never drive the loudspeaker.
* **Amplitude limit** (`generator.maxVpp`): the largest **open-circuit voltage** at the generator
  terminals, whatever the load setting (since 1.3.0; with an amplifier input of R ohm the
  programmed level is at most maxVpp · R / (R + 50 Ω)). The level field cannot exceed it, the
  settings are checked against it, and the programmed value is read back from the generator
  (33220A) and checked again right before the output is switched on. The field cannot go below
  the smallest level of the generator either (33220A at load `"INF"`: 0.01 Vpk).
* **Loudspeaker power limit** (Test limit [W]): the loudspeaker power at its **nominal impedance**,
  P = V_rms² / Z (the convention of the rated power, IEC 60268-5), from the generator level, the
  amplifier gain and the amplifier input (section 4), is checked before every excitation. Above the
  limit the excitation is refused, also in simulation; from 80 % of the limit the window shows
  "Speaker near the limit" (the real impedance may be 20 % below the nominal one, so the real power
  up to 1.25 × the estimate). Noise counts with its crest factor (3.3), a sine or sweep with √2.
* **Amplifier gain**: the gain is set by hand on the amplifier; the program cannot read or change
  it. When an amplifier is chosen, its gain must be entered (section 4) before a measurement or a
  calibration can start.
* **Excitation confirmation** (hardware mode): before the loudspeaker is driven, the dialog
  "Confirm excitation" shows the signal, the generator amplitude in Vpk (Vpp in brackets; with an
  amplifier input as the load, e.g. `generator.load = "600"`, the programmed value into that
  resistance - the voltage at the amplifier input - and the open-circuit voltage, section 9), the
  amplitude limit (open circuit) and the drive estimate with the amplifier gain: the loudspeaker
  voltage in Vpk and Vrms, the power at the nominal impedance and its share of the test limit
  ("near the limit" from 80 %). **Start excitation** drives
  the loudspeaker, **Cancel** stops without driving it; the window then reports "Measurement
  cancelled: the loudspeaker was not driven." as information, not as an error. The question comes
  once per combination of amplitude and amplifier setting and again after any change (a
  calibration with ten sweeps asks once). `amplifier.confirmBeforeExcitation = false` switches it
  off.
* **Stop**: while an action runs, every field, button and menu is locked. The red **Stop** button
  is enabled only during the actions it can stop: Connect, a measurement, the background-noise
  recording and the switching calibration (its tooltip names the action). Saving, reprocessing and
  loading cannot be interrupted; Stop stays disabled while they run. Stop switches the generator
  output off at once and ends the action; a Stop pressed in the first moment of Connect, before
  the instruments are contacted, is kept and stops the connection. The tabs stay usable. In
  hardware mode the Generator lamp turns orange while the loudspeaker can be driven, and the status
  line says "Measurement – loudspeaker driven" (or "Calibration – …"). A Stop acts only on the
  running action: a question asked after that action has ended, e.g. the unsaved-measurement
  question, is shown as usual.
* **Errors and Stop** (network, stream, instrument error, Stop): the generator output is switched
  off and read back (33220A: `OUTP?`). The message pane first says "generator output commanded
  off" (only the command; a failure to send it is a warning in the command window), then the
  result of the read-back; the alert says whether the output is confirmed off, or asks
  you to switch the generator output off at the instrument (a generator that cannot report its
  state - none of today's drivers - is reported as "switched off … check it at the instrument";
  the simulated combined device as "output stopped (device idle, 0 V)"). If the read-back does
  not confirm the output off, the Generator lamp turns red and the status line reads "Generator
  output not confirmed off" until a later read-back confirms it. If a recording was running, the
  generator output is switched off **first**, before the acquisition module is stopped (since
  2026-10-11; stopping an unreachable LAN-XI module can take about 20 s, and the loudspeaker is
  no longer driven meanwhile). The recording is then stopped and the data received so far are
  saved to `data\emergency\partial_<time>.mat`; the views then show the last measurement again.
  A Stop or an instrument error **between two repetitions** (e.g. while the stream of a
  repetition is being closed) also keeps the repetitions completed so far in that file, and the
  generator is locked again (it can be switched on only by the next measurement).
* **Data integrity**: the input faults the acquisition reports (LAN-XI: DataQuality flags INVALID,
  clipped) and a software check (≥ 99 % of the input range) mark a measurement as failing. The
  results are still computed, the message pane lists the problem and a "Data integrity" warning
  appears.
* **Unsaved measurement**: before an unsaved measurement is replaced or lost (Start measurement,
  Background noise, File > Open measurement…, File > Load configuration…, closing the
  window), a dialog asks
  "… anyway? The measurement is then lost." with the action and Cancel.
* **Closing the window** (the window's X or File > Exit): a "Closing" dialog appears at once and
  lists the steps: generator output off, the connections closed ("generator output off, DAQ back
  to Idle" with the lab instruments; 2 s time-outs, so a switched-off instrument
  cannot delay it), window closed. If an action is running it is stopped first (output off at
  once) and the window closes as soon as it has stopped; if the last measurement is not saved,
  the unsaved-measurement question is asked first (Cancel keeps the window open). A second close
  request closes at once. A question dialog that is open, or still opening, when the window
  closes counts as its cancel answer. So does a question of the running action when the close
  is requested (or Stop pressed) during that action, also in a window that is not connected:
  e.g. the tube set-up and microphone-mapping questions of File > Open measurement… are
  cancelled and the window closes after one close request. Stop or a close request pressed
  while Connect is still starting is kept: the connection stops at its first step, before any
  instrument is contacted.
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
* Choose "none (direct drive)" in the Amplifier list (gain fixed at ×1); the generator load is
  then High Z (`generator.load = "INF"`, owner decision 2026-10-12): the generator sets the
  open-circuit voltage, and the loudspeaker impedance, which changes with frequency, divides it. A
  numeric load with direct drive is rejected. Raise `generator.maxVpp` deliberately (the lab file
  uses 2 Vpp = 1 Vpk open circuit, i.e. at most 0.138 Vpk, about 1.2 mW, at an 8 Ω loudspeaker; the
  third line below the EXCITATION fields then reads "set by generator.maxVpp").
* The drive estimate and the loudspeaker power limit take the source impedance from the generator
  driver (50 Ω for the 33220A). Another generator with an output of about 0 Ω (e.g. a DAQ analog
  output) drives an 8 Ω loudspeaker with about (58/8)² ≈ 50 times the power of the same voltage
  from the 33220A; the estimate and the excitation confirmation ("via the 0 Ω generator output")
  account for it. A driver name the program does not know counts as 0 Ω (the worst case).

## 4. The control panel

### INSTRUMENTS

| Control | Function |
|---|---|
| Operating mode | Simulation (virtual tube, practice) or Hardware (the instruments of the configuration; lab: 33220A and LAN-XI module). **Fixed while connected**: press Disconnect to change it. |
| Connect | Connects the generator (output off) and the acquisition module (lab: the LAN-XI), reads TEDS where the module can, sets up the channels and makes a 1 s signal check without excitation. Opens Setup > Connection, where every step is shown. |
| Disconnect | Generator output off, acquisition stopped (LAN-XI: back to Idle), connections closed. |
| Status | "Not connected" (grey); "Connecting (hardware)…", "Busy: …" or "Measurement – loudspeaker driven" (blue) while an action runs; "Ready (simulation)" (green); "Ready (hardware) – with warnings" or "Connected (hardware) – a check failed" (orange); "Generator output not confirmed off" (orange, section 3); "Connection lost - Disconnect and Connect" (orange: an instrument connection could not be re-opened, see "Connection check" below). The verdict of the connection checks stays in the status line after every later action. |
| Lamps | generator and acquisition module, labelled by their role (from their drivers: Generator and DAQ in the lab; Output and Inputs for the simulated combined device; the model is in the "In use" line and the tooltip), ch1–ch4: grey = not connected, blue = running, green = OK, orange = check, red = fault. The tooltip of the first two names the instrument and, once connected, its vendor, model, serial number and firmware. Details in Setup > Connection. |
| In use | the instruments in use, one line each: before Connect the instruments the configuration selects (e.g. "Keysight/Agilent 33220A function generator", "HBK LAN-XI module (Open API)"); after Connect what each instrument reported about itself, e.g. "Generator: 33220A s/n …" and "DAQ: 3676-B-040 s/n 110283". In simulation mode the lines end with "(simulated)": the simulated instruments report realistic identities. |

The instruments are **chosen in the configuration file**, not in the window (section 9, "Choosing
the instruments"); the window only shows them. The texts of Connect and Disconnect, the lamp
labels, the connection checklist and the limits of the EXCITATION fields follow the instruments
in use.

Connect takes the operating mode and the other fields as they are. If a field is invalid, Connect
stops with the alert "Check the settings" and does not connect: correct the field and press
**Connect** again. A failed or stopped connection leaves no half-open connection: the status reads
"Not connected", **Connect** and **Operating mode** are usable again, and Setup > Connection names
the step that failed. Remove the cause and press **Connect** again.

**Connection check.** The lab's 33220A drops an idle network connection now and then without
telling the PC (hardware check of 2026-10-12; also with a static IP address and without MATLAB):
before 1.2.1 the next Start then failed with a MATLAB message. Now the program checks the generator
connection **before every measurement and calibration step**, and in hardware mode **every minute
while the window is idle** (never during an action):

* a connection that has been idle for more than 30 s is not used again: the program closes it and
  opens a new one (the generator must report the same serial number, its output is switched off
  and its load setting sent again). Nothing is written in the message pane; it takes a fraction of
  a second. Because nothing is sent on an old connection, the dropped connection no longer causes
  an error;
* a connection used within the last 30 s is asked for the output state; if it has been dropped
  anyway, it is replaced the same way and the message pane says "Generator: connection re-opened
  (the instrument had closed it): …" (the MATLAB command window may then show a red stack trace,
  harmless, section 13); the measurement runs as usual;
* if the generator does not answer at all, nothing is switched on: the lamp turns red, the status
  reads "Connection lost - Disconnect and Connect" and the minute check stops until the next
  Connect.

A Start pressed during the (short) check is not started; press it again.

### IMPEDANCE TUBE (lengths in mm)

* **Diameter [mm]** (inner diameter D), **T [°C]** (air temperature; T in kelvin in the formulas)
  and **p [kPa]** (static pressure, `p_s` in the formulas) on one row.
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
* The line below shows the speed of sound, the geometric validity range of the tube by ASTM
  E1050 / E2611 (microphone spacing 0.01–0.40 c/s, plane waves 0.58 c/D) and the analysis band
  with its source ("c = 343.3 m/s · ASTM E1050/E2611 limits 118–4735 Hz · analysis band 120–4734 Hz
  (from the tube)"), and in red any input error ("CHECK: …"). With `analysis.bandMode` =
  `"geometry"` (the lab file, since 1.3.2) the band is that range and follows the fields at once:
  a wider microphone spacing lowers it, a narrower one raises it (up to the plane-wave limit), and
  the temperature moves it slightly. With `"fixed"` (the default) it stays as configured, the
  line says "(fixed)", and lines outside the range are computed but not valid. A calibration covers
  only the band it was made with: after the band grows, calibrate again. The tooltip explains the
  limits; `docs/theory.md` section 7.

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
| Frequency [Hz] … to … | start and stop frequency, at most the usable band of the instruments (LAN-XI: 0.45 × sample rate, i.e. 7372.8 Hz at 16384 S/s; the tooltip states the limit) |
| Sweep duration [s] | duration of one sweep, within the sweep times of the generator (33220A: 0.001–500 s); for the stepped sine the field is **Number of steps** (1–400) |
| Repetitions | number of repetitions, averaged (1–100) |
| Amplifier | "none (direct drive)", "power amplifier", or the model of your amplifier: type it into the list and press Enter; it is added to the list and saved with the configuration (File > Save configuration…) |
| Amplifier gain [×] | voltage gain of the amplifier (Vout/Vin) as a plain number: 20 dB = ×10, 26 dB = ×20, 40 dB = ×100 (the tooltip gives the conversion; do not enter the dB value: a 40 dB amplifier entered as ×40 would get 2.5 × the shown loudspeaker voltage) |
| Amp input [Ω] / Generator load | with an amplifier: its **input impedance** from the data sheet - a list with High Z, 50, 600 and 10000, or type a value (e.g. 2200) and press Enter. It is also the generator's **load setting** (`OUTP:LOAD`), sent at Connect, so the programmed level is the voltage at the amplifier input (High Z, or above the 33220A's 10 kΩ: the open-circuit voltage). Fixed while connected. In direct drive the label reads **Generator load** and the list is fixed at High Z. See "Generator output load" below |
| Loudspeaker [Ω] | nominal (rated) impedance of the loudspeaker |
| Test limit [W] | power limit of the loudspeaker for these measurements, at most its rated power (`loudspeaker.ratedPower_W`): an excitation above it (power at the nominal impedance) is refused |
| Speaker [Vpk] ▾ / Generator [Vpk] ▾ / Amp input [Vpk] ▾ | the label of the level field is a list: **Speaker [Vpk]** (the voltage at the loudspeaker; with an amplifier it needs the gain) or the generator's level - **Generator [Vpk]** in direct drive (the open-circuit voltage), **Amp input [Vpk]** with an amplifier (the voltage at its input). The field: peak voltage; for the generator from its smallest level at the load (33220A: 0.01 Vpk at High Z, 0.0092 Vpk at 600 Ω) up to the amplitude limit (`generator.maxVpp`/2 open circuit, at the load × R/(R + 50 Ω)); at the loudspeaker the same range converted (33220A at High Z, 8 Ω: 0.00138–0.138 Vpk for a 1 Vpk limit) |
| (after the field) | the level as Vrms (= Vpk/√2; noise: Vpk/3.3) and the expected duration of one measurement, e.g. "about 29 s" |

* Each signal keeps its own frequency range, duration or number of steps and repetitions:
  switching the Signal shows the values last used for that signal. The amplitude is common.
* **Swept-sine range**: let the sweep start at or below f_lo/1.3 and stop at or above 1.1 × f_hi,
  where f_lo = fMin − Δf/2 and f_hi = fMax + Δf/2 are the outer edges of the first and last
  frequency line: **91 Hz and 4952 Hz** for the analysis band 120–4500 Hz at Δf = 2 Hz (default
  sweep 80–5500 Hz). The sweep gate (theory.md section 4) needs that room outside the band to leave
  the generator's switching clicks out. Since 2026-10-11 an end without the margin is analysed
  without the gate's ramp, so the lines near the band edge stay accurate (before, they were biased
  by up to 13 % at a 109 Hz start and 58 % for 120–4500 Hz in simulation): a start above the lower
  limit keeps the gate's ramp, placed on the start-frequency tone before the sweep (since 1.3.1;
  an output-on click before the ramp stays out, one within it is included - with the lab's
  trigger latency of 0.13–0.28 s the click mostly stays out; from 2026-10-11 to 1.3.0 the window
  began at the detected start, the click always included), a stop below the upper limit keeps a
  ring-down margin after the sweep (an output-off click within it included). The message pane warns when the configuration or a processed sweep does not keep
  the margin, names the edge that was used and prints the two limits; the configuration check and
  the analysis use the same limits.
* **Amplifier gain [×]**: the field is disabled for "none (direct drive)" (gain 1). When you choose
  an amplifier, the field turns yellow and the message pane asks for the gain: **Start measurement
  and Run switching calibration… are refused until a gain has been entered** (typed into the
  field), also in simulation.
* **Level at the loudspeaker**: with the label set to **Speaker [Vpk]** the field is the voltage at
  the loudspeaker. The program sets the generator to the matching level. In direct drive through
  the generator's source impedance (33220A: 50 Ω) and the nominal loudspeaker impedance:
  generator = loudspeaker × (Z + 50 Ω) / Z, e.g. 10 mVpk at 8 Ω needs 72.5 mVpk programmed at High
  Z. With an amplifier (since 1.3.0) through its gain: amplifier input = loudspeaker / gain, e.g.
  0.707 Vpk at the loudspeaker with ×10 is 70.7 mVpk at the amplifier input (with Amp input
  600 Ω also the programmed level). Switching the label keeps the same level; a new Loudspeaker
  [Ω], gain or amplifier input keeps the loudspeaker voltage. The configuration stores the
  generator amplitude (as always) and `ui.amplitudeAt`; every measurement stores the drive
  estimate as well (`metadata.drive`: the programmed and open-circuit levels, the estimated
  loudspeaker voltage in Vpk and Vrms, current, power, its share of the test limit and the
  state). The real loudspeaker impedance varies with frequency and the gain is the one you
  entered, so the loudspeaker voltage is an estimate.
* **Choosing an amplifier** keeps the programmed level; until its gain is entered the field shows
  it at the amplifier input (Amp input [Vpk]) and Speaker [Vpk] cannot be chosen. When the gain is
  entered the field switches to Speaker [Vpk], the default with a known gain.
* **The drive check below the fields** (WO-004, a white box of three lines) shows the drive for
  the current settings:
  1. the signal path: the generator in Vpp, as its display shows it, and what that number is
     ("open circuit" in direct drive, "into 600 Ω" at an amplifier input), the gain and the
     loudspeaker voltage, e.g. "Generator 0.2 Vpp into 600 Ω → ×10 → speaker 1 Vpk";
  2. two **meters side by side**, each a bar of its share of the limit with a tick at 80 %, the
     share in % and a state box (hover for the numbers):
     - **Speaker**: the power at the nominal impedance against the test limit - **OK** (green,
       below 80 %), **Near** (orange, 80-100 %: the measurement may run), **Above** (red: Start is
       refused), or **Gain?** while an amplifier's gain is missing; the tooltip gives the voltage,
       the power, its share and the rated power;
     - **Generator**: its open-circuit voltage against the smallest of its limits
       (`generator.maxVpp`, or its own largest level at the load) - **OK** or **Above**;
  3. the **largest level and the criterion that sets it**: the loudspeaker test limit,
     `generator.maxVpp` (open circuit) or the generator's own largest level at the load, e.g.
     "Max 4 Vpk at the speaker, set by the loudspeaker test limit (1 W at 8 Ω)" or, in direct drive
     with the lab file, "Max 0.138 Vpk at the speaker, set by generator.maxVpp (2 Vpp open
     circuit)"; red "Test limit … above the rated …" when the test limit exceeds the rated
     power. The tooltip lists every criterion.
* The expected **Duration** is repetitions × (pre-roll + sweep duration + post-roll + 0.2 s) for
  the swept sine and repetitions × (1 s + steps × (settling + recording time)) for the stepped
  sine. The connection, the confirmation and the processing come on top.

### CALIBRATION

* **Calibration** shows the active calibration:
  * "No calibration – results not valid" (red): without a calibration no result is ever valid;
  * `CAL-yyyyMMdd-HHmmss`, followed by "✓ Test E" when its empty-tube check passed, or
    "✗ Test E failed" (orange); no mark when the check was not performed. The tooltip gives the
    result text of the check;
  * "– check" (orange) is appended when the calibration does not fit the set-up in the fields:
    temperature more than 3 K different, port distances changed, other operating mode, Test E
    failed, or another acquisition module or other input settings (driver, model, serial number,
    sample rate, range, filter, CCLD) than when it was made - the calibration factors include the
    DAQ inputs. A calibration made before version 1.2.0 does not record them and is not checked
    for them. Also another microphone on a channel (the TEDS serial number read at Connect, else
    the configured `mics(i).serial`; the factors include the microphones), and a calibration
    computed from sweeps that failed the data integrity check (clipping, overload, device
    flags). The tooltip lists the reasons;
  * "… (used at Connect)" (grey): a calibration file chosen while not connected; it is loaded at
    the next Connect. "… not found" (red): the configured file does not exist.
* **Load calibration…** loads a `CAL-*.mat` file from the calibration folder. The file name is
  also stored by File > Save configuration…, so the next session starts with it.
* **Run switching calibration…** runs the switching calibration with the empty specimen section
  (needs a connection; `calibration_procedure.md`). The new calibration becomes the configured
  calibration file in the same way, also when it was kept after a Cancel or Stop at the "return
  the microphones" step: it is loaded at the next Connect and stored by File > Save configuration….

### MEASUREMENT

* **Specimen**: name of the specimen. The name in the field when **Start measurement** is pressed
  counts: it is stored in the metadata (`metadata.specimen`) and becomes part of the data folder
  name when the measurement is saved (section 12). A later change of the field does not rename a
  measurement that has already been started. A background-noise record carries no specimen name.
* **Method** (1.4.0, WO-005):
  * **One load** (default): one measurement with the termination chosen in Setup > Tube setup.
    τ, α_d and the TL from τ need an anechoic termination.
  * **One load, symmetric**: the same measurement, plus the transfer matrix from this one load
    (ASTM E2611 one-load method). It is valid **only** for a front-to-back symmetric, reciprocal
    specimen; the views say "symmetric specimen ASSUMED".
  * **Two loads**: the specimen is measured with load A, load B and (Repeat load A, the default)
    load A again, as chosen in Setup > Tube setup (section 6). The transfer matrix of the specimen
    follows (ASTM E2611 two-load method); it does not need an anechoic termination. Choosing
    "Two loads" opens Setup > Tube setup.
  The method is not remembered between sessions; it starts as the configuration says
  (`measurement.method`, default one load).
* **Background noise**: 2 s without excitation (background noise of every channel); then the
  Spectrum view opens. (It shares the row with Method: the control panel keeps its height.)
* **Start measurement** (green; "Start two-load measurement" with two loads): measures with the
  selected signal. In hardware mode it asks before the loudspeaker is driven (section 3). The Time
  signals view shows the four channels live. Every measurement records its termination
  (`metadata.termination`).
* **Stop** (red): stops the running connection, measurement (also a two-load sequence: the loads
  measured so far stay saved), background-noise recording or switching calibration; the generator
  output is switched off at once. Disabled otherwise.

### RESULTS

* **Last result**: "No measurement"; "Swept sine 11:15:37 – not saved" (red) after a measurement;
  "Saved: `<folder>`" (green, the tooltip gives the full path) after Save measurement;
  "Opened: `<folder>`" (green) after File > Open measurement…. After a two-load measurement every
  load is already saved and the line names the pair folder ("Saved: `…_twoload_<specimen>`"); after
  Reprocess or File > Combine… it reads "Two-load result – not saved".
* **Save measurement**: raw data, results, configuration, metadata, CSV files and figures into a
  new folder under `data\` (section 12). A background-noise record, or a measurement that could
  not be processed, is saved with its raw data and the figures of its time signals and spectrum.
  A "Saving the measurement" dialog (same style as the "Closing" dialog) shows the steps and a
  progress bar; a save takes about 10–15 s, most of it the PNG figures. With a transfer matrix of
  two loads it writes a **new pair folder** (section 12); the load folders are not touched.
* **Reprocess**: computes the results of the last measurement again with the current IMPEDANCE TUBE
  fields (geometry, temperature, pressure) and the active calibration, e.g. after correcting a
  distance or loading another calibration; with a transfer matrix of two loads every load, then the
  transfer matrix. Save measurement again to keep the new results (a new
  folder; the first one is not changed). This also works for a measurement opened with File > Open
  measurement…. Channel-to-port assignment (which DAQ channel is in which port M1–M4): a new
  measurement is processed with the configuration's, the one of the connection. For a measurement
  opened with File > Open measurement… whose recorded assignment (`meas.mics`, or its folder's
  `config.json`) differs from the configuration's, the window asks when it opens it (section 7);
  the recorded one is the default and Reprocess then uses it ("Microphone mapping as recorded with
  the measurement: …" in the message pane). The configuration's assignment stays available there,
  to correct an assignment that was recorded wrongly; the message pane then says that it differs
  ("Microphone mapping of the configuration … differs …"). Since 2026-10-11 every swept-sine
  frequency line is centred on its frequency (`docs/theory.md` section 4, step 3), so a sweep
  saved before gives slightly different results when reprocessed (on the lab data of 2026-10-09/10
  |ΔR| up to 0.006, |ΔZt| up to 0.0024 ρc, a few lines change validity); a calibration made
  before that date was computed with the former lines and still applies (the difference it
  leaves is of the same order, at most 0.004 in the calibrated pressures).
* The `config.json` that Save measurement writes is the configuration the saved results were
  computed with (after File > Open measurement… without Reprocess: the opened folder's
  `config.json`), so it always describes `result.mat`; folder and figure formats follow the
  window.

### Which buttons are available

| Control | Enabled when |
|---|---|
| Operating mode, Connect | not connected (also after a failed or stopped connection) |
| Disconnect | connected |
| Start measurement, Background noise, Run switching calibration… | the connection is complete (status "Ready …" or "Connected … – a check failed") |
| Stop | only while Connect, a measurement, the background-noise recording or the switching calibration runs |
| Save measurement | a measurement or a background-noise record exists |
| Reprocess | a measurement exists (not for background noise) |
| Amplifier gain [×] | an amplifier other than "none (direct drive)" is chosen |
| Amp input [Ω] | an amplifier is chosen and the window is not connected (direct drive: Generator load, fixed at High Z) |
| Speaker / Generator / Amp input [Vpk] (the list) | direct drive, or an amplifier whose gain is entered |
| everything else, menus | no action running |

## 5. Workflow step by step

1. **Start** the window (section 1). The message pane says "Ready (… mode). Not connected …".
2. Check the **Operating mode**. It cannot be changed while connected.
3. Press **Connect**. Setup > Connection opens and lists every step with its result and duration
   (section 6). Read the line above the list: "Connected - all checks passed.", "Connected with
   warnings – see the orange items below." or "Connected, but a check failed – see the red items
   below." The status line keeps this verdict. A Connect refused before any instrument is
   contacted (a setting outside the driver's limits, an unknown driver, a missing calibration
   file) reads "Connection refused: …" in red, with every step still pending. Check the
   sensitivity source of every channel and the background level of the signal check.
4. Check the **IMPEDANCE TUBE** fields against the tube (D, T, p, s1, L1, d, L2, s2) and look at
   Setup > Tube setup. Enter the measured temperature and static pressure. Store the values with
   File > Save configuration… and commit `config/user_config.json`.
5. Set the **EXCITATION**: Signal, frequency range (wider than the analysis band, e.g. 80–5500 Hz),
   sweep duration or number of steps, repetitions, a low Amplitude, the Amplifier and its gain, the
   loudspeaker data. Read the estimated loudspeaker drive and the expected duration.
6. Optional: **Background noise** and check the Spectrum view.
7. **Calibration**: Load calibration… (an existing `CAL-*.mat` that fits the set-up), or Run
   switching calibration… (`calibration_procedure.md`; 12 operator steps, about 5 min of sweeps
   with the default settings). The Calibration line must show the version and "✓ Test E".
8. Mount the **specimen section with the specimen**, check L1, d and L2 for this specimen, and
   enter its name in **Specimen** (before Start measurement: the name at Start counts).
9. Press **Start measurement**. In hardware mode confirm the excitation dialog (**Start
   excitation**). The Time signals view shows the last 0.5 s of every channel live ("LIVE · 3.2 s
   recorded …") with the level of every channel in the header. Stop ends the measurement at once;
   the views then show the last measurement again.
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

### Two loads (transfer matrix, ASTM E2611)

Use it when the termination is not anechoic (the lab termination reflects: |R_term| 0.85 at
125 Hz, 0.25 at 4 kHz) or for a thick specimen. Steps 1–8 as above, then:

1. **Method**: Two loads. Setup > Tube setup opens: choose **Load A** and **Load B** in the
   Termination box (default: Absorber at tube end, Rigid cap at tube end), keep **Repeat load A at
   the end** on, and leave **B level** at "same as A" unless load B overdrives the specimen (it may
   only be lowered). **Show** draws load A or load B in the model.
2. **Start two-load measurement**. Measurement > Two-load opens. For every load the operator bar
   names the termination and how it is mounted ("Load B: Rigid cap at tube end – the extension
   tube empty (absorber removed), the end cap on and sealed (face 291 mm behind M4)"), the model
   shows it glowing, and in hardware mode the program waits for **Measure** (or **Abort**). Change
   **only the termination**: the specimen section and the microphones stay untouched. In simulation
   the virtual tube changes the termination by itself.
3. Every load is processed and **saved at once** in a folder of its own
   (`…_sweep_<specimen>_loadA_absorber-end`, `…_loadB_rigid-end`, `…_loadA2_absorber-end`); a Stop
   or an error keeps the loads measured so far. After the last load the figures of the loads are
   written and the transfer matrix is saved in a **pair folder** (`…_twoload_<specimen>`; about a
   minute with the figures).
4. Check Measurement > Two-load (condQ of the two loads, the repeat of load A, the loads table) and
   the Results views, which now show the transfer matrix first (section 6).

The window remembers load A, load B and the repeat of the last two-load Start for each
configuration file (MATLAB preferences of the Windows user, so the lab file and the virtual tube do
not overwrite each other); without a record the configuration's loads apply. The method itself is
not remembered.

## 6. The views

### Setup > Connection

* The **Instruments** table: one row per instrument (one row "Output + Inputs (both roles)" for a
  device that is generator and acquisition at once): role and lamp label, the instrument (the
  driver's display name), the driver name of the configuration, and - after Connect - the vendor,
  model, serial number and firmware the instrument reported ("–" before); the last column shows
  the settings of the configuration (amplitude limit and load; sample rate, input range,
  high-pass filter, CCLD). Its tooltip lists the values each driver allows (loads and levels,
  sweep times, sample rates, ranges, filters, CCLD, TEDS). Sample rate and range have no control
  in the window: set them in the configuration (section 9).
* The **Connection checklist**, one row per step with a status icon (turning icon = running), the
  result and the duration. The steps come from the drivers in use, each after the lamp label of
  its role; with the lab instruments: "Generator: connect (33220A, SCPI)" (output off); "DAQ:
  connect (LAN-XI, REST)"; "DAQ: recorder state Idle" (returned to Idle if needed); "DAQ: open
  recorder"; "DAQ: TEDS detection"; "DAQ: channel setup → streaming"; then always microphone
  sensitivities (order certificate → TEDS → nominal); settling of the inputs (lab: the CCLD
  supply and the high-pass filter; hardware only); **signal check** (1 s without excitation). The
  simulated combined device has the steps "Output + Inputs: connect (simulated device)" and
  "Inputs: channel setup". A failing step is marked red with the error message,
  and the line above the list names it. Before Connect the list shows the steps of the
  instruments the configuration selects; after Disconnect it shows the last connection.
* One **card per channel**: "ch1 → port M1", status, TEDS type and serial number, sensitivity and
  its source, the level of the signal check in dB SPL. Orange "check: …" for no TEDS (on a module
  that reads TEDS), a nominal sensitivity or a TEDS serial number that differs from the
  configuration; red "FAULT" for a failed signal check (an input fault the module reports, e.g.
  LAN-XI flag INVALID: cable or CCLD fault; clipped; no signal; overload).
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
* **Termination** box (1.4.0, above the Geometry table): the termination of the tube, a **kind**
  (Absorber, Rigid cap, Open end) **at** a **place** (Tube end: the end cap, 291 mm behind M4;
  Joint: the joint of the downstream tube with the extension tube removed, 41 mm behind M4; the
  absorber only at the tube end, so its place is fixed). One load: one row "Termination"; Two
  loads: **Load A**, **Load B**, **Repeat load A at the end** and **B level**. Any two different
  terminations can be paired; ASTM E2611 and Brüel & Kjær use an open and an approximately
  anechoic termination. A grey line below says what is mounted and where; two equal loads are
  named in red (Start refuses them). The 3D model draws the chosen termination: the absorber, the
  empty extension tube with the end cap, without it (open end), or the extension removed with a
  cap on the joint flange or open, with the label and the dimension "M4 – termination" of that
  termination. With two loads **Show** (header) switches between load A and load B.
  Estimated conditioning in the lab tube (absorber measured on 2026-10-12/13, ideal rigid cap or
  open end): rigid cap at the tube end condQ ≤ 11 in the whole band; a rigid cap at the joint or an
  open end loses part of 250–1000 Hz to condQ > 10 (`workorder_two_load.md` section 2).

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

The view of the switching calibration (details in `calibration_procedure.md`): the **operator
bar** at the top ("**Calibration step 4 of 12:** …"; while the program waits for you it turns
yellow and shows the buttons on its right, e.g. **Measure** and **Cancel calibration** - there is
no separate dialog, the window is not dimmed and nothing covers the model), the 3D model in its
calibration state below it (empty specimen section, absorbing termination, calibration ports
M1 (a) and M2 (b) glowing yellow, microphones labelled with their channel and serial number; at
every step the microphones that change port move along paths with rounded corners, which stay
as dashed arrows), and
the calibration factors |C_k| [dB] and ∠C_k [°] of ch2, ch3, ch4 relative to ch1 side by side at
the bottom (grey = not valid). The right column holds the summary table "Calibration factors
Ck = gk/gref" (per channel the share of valid frequency lines, the range of magnitude and phase over
the valid lines and the remounting repeatability) and the **operator steps and the quality of
every measurement** (detail under each step). The header note gives the result of the empty-tube
check (Test E). The confirmation before the loudspeaker is first driven also appears in the bar
during a calibration.
Before any calibration the view says "No calibration loaded – use Load calibration… or Run
switching calibration…".

### Measurement > Time signals

Sound pressure (voltage / sensitivity) of the four channels, one graph per channel on a common time
axis, labelled "ch1 (M1) [Pa]" etc. During an acquisition: the last 0.5 s, about five updates per
second, the header note gives the live level of every channel. After the measurement: the whole
record of repetition 1, long records as a min / max envelope so that every peak stays visible. A
display high-pass at 20 Hz removes the slow CCLD settling drift; the raw data are not changed and
are stored in volts. Without a valid sensitivity for every channel the graphs show mV.
For a swept sine the parts of the record that are **not analysed** are shaded grey: normally
before the sweep (the "click" when the generator output is switched on and the start-frequency
tone) and after it (the jump back to the start frequency and the click when the output is
switched off).
The sweep is located in every repetition by a matched filter; only the sweep enters the transfer
functions and the calibration (`docs/theory.md`, section 4). A sweep that starts too close to the
band (above f_lo/1.3) keeps its ramp on the start-frequency tone before the sweep, one that stops
too close (below 1.1 × f_hi) a ring-down margin after its end, so the shading starts or ends there
(see "Swept-sine range" above). The header note then says so per end: the analysed part begins
on the start-frequency tone before the sweep (an output-on transient after that time is
included; results of 1.2.0–1.3.0 analysed from the detected start, and their note says so), or
the analysed part continues past the sweep end and includes an output-off transient within the
margin. If the sweep cannot be found, the message pane says so and the whole excited interval is
used.
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

### Measurement > Two-load

The view of the two-load measurement (1.4.0), built like the Calibration view: the **operator
bar** at the top ("**Two-load step 2 of 3:** Load B: …"; yellow with **Measure** and **Abort**
while the program waits in hardware mode), the 3D model with the termination to mount glowing,
and at the bottom side by side **cond(Q)** (the condition number of the two loads' states at the
rear face of the specimen, black where both loads are valid, the limit `analysis.condQMax` = 10
dashed: lines above it are not valid) and the **repeat of load A**, |T(A,B) − T(A′,B)| / |T| per
line with the tolerance `analysis.repeatTol` = 0.05 (the median decides). T does not depend on
the termination, so a re-packed absorber does not count as a change; a moved specimen or
microphone does. The right column holds the **Loads** table (load, termination, share of the band
valid in that load, peak level in the tube, temperature) and the **operator steps and the
quality of every load** (valid share, peak level, saved folder; the last row: the transfer
matrix, the figures and the pair folder). **Show load** (header) picks the load whose measurement
(Time signals, Spectrum, Transfer functions) and own results (|R_term|, the validity rows of that
load) the other views show; the transfer matrix stays. The header note warns when the loads could
not be combined (another calibration, geometry, mapping or signal), when the repeat of load A
differs, when load B is 10 dB or more above load A (`measurement.levelStepWarn_dB`: a rigid cap
raises the level at the tube resonances, check that the specimen is linear), and when the loads
are more than 1 K or 30 min apart.

### Results > Reflection and transmission

With a transfer matrix (two loads, or one load of a symmetric specimen) the top graph shows the
specimen with an **anechoic termination**, from T: |R_a|, |τ_a|, α_d = 1 − |R_a|² − |τ_a|², and
dashed α_h = 1 − |R_h|², the absorption of the specimen **backed by a rigid wall** at its rear
face; |R_term| of the load shown stays as the diagnostic of its termination. The bottom graph
shows the phase of R_a, the table |R_a|, |τ_a|, α_d, α_h. Without one:

Top graph: |R| at the specimen front face (mask `validR`), |τ| from the front face to the rear face
and the dissipation coefficient α_d = 1 − |R|² − |τ|² (both mask `validTau`), |R_term| of the
termination (dotted; grey where the downstream pair is not reliable) and the limit up to which the
termination counts as anechoic (dashed, `analysis.anechoicRmax` = 0.1). Bottom graph: the phase of
R. Summary **Octave bands**: mean |R|, |τ| and α_d over the valid frequency lines of each octave
band (centre/√2 to centre·√2); "–" = no valid line. |τ| and α_d need an anechoic termination.

The octave-band tables of the three Results views list every octave band that overlaps the
analysis band (default 120–4500 Hz: 125 … 4000 Hz). A band that lies only partly inside the
analysis band is marked "*" ("125*", "4000*" with the default band): its value is the mean over
the part inside the analysis band only, and the note under the table says so ("* = only partly
inside the analysis band (120–4500 Hz).").

### Results > Transmission loss

Normal-incidence transmission loss **TL from τ** = −20 log10 |τ| (solid; needs an anechoic
termination, mask `validTau`). For a thin specimen also the **TL from Z_t** =
20 log10 |1 + Z_t/(2Z_c)| (dashed, independent of the termination, mask `validThinZt`), with Z_c
the characteristic impedance of the tube-loss model (Z_c ≈ ρc, within 0.5 %; `theory.md`
section 3A). For a thick specimen (k·d > 1 in the analysis band) the TL from Z_t is not drawn and
the note says why. Without L1, d and L2 the graph stays empty with the message "Specimen face
positions unknown (L1, d, L2): the transmission loss is not available." Summary **Octave bands**:
energy mean over the valid lines, TL = −10 log10(mean |τ|²).
With a transfer matrix the first, black curve is the **TL from T** (the specimen with an anechoic
termination, independent of the actual one; legend "TL from T (two loads)" or "… (one load,
symmetric specimen assumed)"), masked with the validity of T; the TL from τ of the load shown
follows dashed, and the table gets a first column "TL from T [dB]".

### Results > Transfer impedance

Re{Z_t}/(ρc) (top) and Im{Z_t}/(ρc) (bottom) of the thin-element model,
Z_t = (p_front − p_rear)/u with u the mean of the front- and rear-face velocities (mask
`validThinZt`: velocity match across the specimen). Only meaningful for a thin specimen (k·d ≪ 1):
when k·d exceeds 1 in the analysis band the graphs stay empty with the message "Thin-element model
not applicable: d = 75 mm (k·d up to 6.2)" and a pointer to Transmission loss and Reflection and
transmission. This is the case for the 75 mm lab specimen section. Summary **Octave bands**: mean
Re and Im over the valid lines; the note gives ρc. Without L1, d and L2 the view says that the
specimen face positions are unknown.
With a transfer matrix the graphs show its series element T12 / (ρc), coloured where T is valid
and the specimen is a thin element **by T itself** (|Z_c·T21| and |T22 − 1| at most
`analysis.velocityMismatchMax` = 0.10; independent of the termination, unlike δ_u), grey
elsewhere; for a thick specimen the note says "Not a thin element … see Transfer matrix".

### Results > Validity

One row per criterion, the frequency lines that pass in dark blue, the others light grey:
"Measured (in band)" (inside the analysis band, with data), "Geometry OK", "Quality OK (coherence,
SNR, cal.)", "Passive", **"Valid"**, "Valid R", "Valid τ / TL", "Valid thin Z_t", "Validated
(experiment)". Below a separator one row per rejection reason ("Rejected: low coherence",
"Rejected: termination not anechoic", …), red where it rejects.
Stepped sine: one square per step. Summary **Validity criteria**: number and share of passing
lines and which results each criterion affects; the note is the summary line of the masks
("… N valid (R: M, upstream pair), …"). "Valid R" uses only the upstream pair M1/M2 (section 10)
and may therefore pass where "Valid" does not. The column "Affects" says so: "Measured", "Geometry
OK", "Quality OK" and their rejection reasons (band, spacing, singularity, condition, phase
sensitivity, coherence, SNR) affect "|τ|, α_d, TL, Z_t (R: M1/M2)", i.e. they reject R only where
they fail at M1/M2 (row "Valid R"); "Passive" rejects R only for |R| > 1 + `passivityTol`; the
mode cut-on and a missing calibration affect all results. When no line is valid
for τ, TL and Z_t but R is valid, the header note says so ("… R valid on N lines (upstream pair
M1/M2)."); without L1, d and L2 it says that R, τ, TL and Z_t are not available.
With a transfer matrix a third group of rows follows below a second separator: "Both loads
valid", "Loads differ (cond(Q) ≤ 10)", **"Valid T"**, "Reciprocal (|det T − 1| ≤ 0.1)" and "Load A
repeat (≤ 0.05)" (the last two report only).

### Results > Transfer matrix

The transfer matrix of the specimen, [p_front; u_front] = T [p_rear; u_rear] (1.4.0), with the
elements in tube units: |T11|, |T12|/Z_c, |Z_c·T21|, |T22| (top, logarithmic) and their phases
(bottom). The diagonal elements share a colour (T11 solid, T22 dashed: on top of each other for a
symmetric specimen), the off-diagonal ones another (T12/Z_c solid, Z_c·T21 dashed: zero for a thin
series element). Grey: not valid. The header note gives the median reciprocity error |det T − 1|
and symmetry error over the valid lines; for one load it says that T11 = T22 and det T = 1 are
assumed. Summary **Octave bands**: the mean magnitudes of the four elements.

### Formula

Every equation used by the program, with the default thresholds read from the code: 0 conventions
and symbols; 1 transfer functions (swept sine, stepped sine, random noise); 2 switching
calibration; 3 plane-wave decomposition; 4 pressure and particle velocity at the specimen faces;
5 reflection, transmission and dissipation; 6 transfer impedance; 7 transmission loss; 8 transfer
matrix (two loads, one load of a symmetric specimen); 9 air properties and tube losses; 10 geometric validity range; 11 validity
criteria; 12 units and level references; 13 references (standards and literature). Every section
ends with a grey "Sources:" line: the standards and papers it follows, cited as [n] of section 13,
and what is this program's own choice (for example the sweep gate, the SNR estimators and every
validity threshold). The derivations are in `theory.md`, whose reference list is the same.

## 7. Menus

* **File**: Open measurement…, Combine two saved measurements (two loads)…, Load configuration…,
  Save configuration…, Exit.
  * *Open measurement…* on a **two-load pair folder** (select `result.mat` or `twoload.json` in a
    `…_twoload_…` folder) opens its loads (from the load folders named in `twoload.json`; a
    `raw.mat` that changed since, by its SHA-256, is reported) with their saved results and the
    saved transfer matrix; Last result reads "Opened: `<pair folder>`", **Show load** picks a load,
    Reprocess reprocesses every load and Save measurement writes a new pair folder.
  * *Combine two saved measurements (two loads)…* asks for `raw.mat` of load A, then of load B
    (two measurements of the same specimen with different terminations, also older ones): both are
    reprocessed with the IMPEDANCE TUBE fields and the active calibration, then the transfer matrix.
    The termination of each is taken from its metadata (folders saved before 1.4.0: "not
    recorded"). Last result reads "Two-load result – not saved"; Save measurement writes a pair
    folder. From a script: `app.combineMeasurements(folderA, folderB)`.
  * *Open measurement…* shows a measurement saved by Save measurement again: select `raw.mat` (or
    `result.mat`) in its folder under `data\`. Every view shows the saved data and results (the
    results are not recomputed), drawn with the analysis band and the coherence and |R_term|
    limits they were computed with (as in the saved figures), not with those of the loaded
    configuration; Last result reads "Opened: `<folder>`" and the message pane gives
    the measurement time, the specimen and the calibration of the saved results. If the tube
    set-up of the saved results (its `config.json`) differs from the IMPEDANCE TUBE fields, a
    dialog asks "Use the saved set-up" (puts it into the fields) or "Keep the current fields".
    If the microphones were on other ports when the measurement was recorded (`meas.mics` in
    `raw.mat`, or the folder's `config.json`) than the configuration says now (e.g. re-cabled
    since, or another configuration loaded), a second dialog shows both assignments and asks
    "Use the recorded mapping" (the default, also when the dialog is closed with Esc or X; kept
    by the owner on 2026-10-13) or "Keep the configuration's mapping" (only to correct an
    assignment that was recorded wrongly). Since 1.3.1 the dialog and the message pane also name
    the assignment the **saved results** were computed with (the folder's `config.json`): for a
    folder saved after such a correction that is the corrected one, so reopening it shows that
    the default answer would undo the correction. When no dialog is needed (recorded =
    configured) but the saved results used another assignment, the message pane says so. The
    choice applies to Reprocess of this measurement only; the message pane records it.
    **Reprocess** then computes the results again with the fields, the active calibration and that
    assignment; **Save measurement** writes a new folder whose `config.json` holds the assignment
    of its results. The opened files are only read, never changed. It asks about an unsaved
    measurement first and works connected or not. From a script:
    `app.openMeasurement(folder, useSavedTube, useRecordedMapping)` (each `'ask'` - the
    default, a hidden window takes the default answer -, `true` or `false`).
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
* **Help > About** shows the logo, the program, the software version and release date, the Git
  commit and branch, the MATLAB release, the licence (MIT License, Copyright (c) 2026 Woongji Kim,
  file `LICENSE`) and the author's site (<https://kimwoongji.github.io>).
  The text can be selected and copied. The repository is opened with Help > Source code on GitHub.

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

### Choosing the instruments

The instruments are chosen **only in the configuration file** (`formatVersion` 2); the window has
no selector and shows which instruments are in use (INSTRUMENTS "In use" and the lamps, section 4;
the Instruments table of Setup > Connection, section 6). Each role names a **driver**, and each
driver keeps its own settings in a sub-struct named after it:

```json
"generator": { "driver": "keysight33220a", "maxVpp": 2, "load": "INF",
               "keysight33220a": { "host": "169.254.2.20", "port": 5025, "timeout": 5 } },
"daq":       { "driver": "lanxi",
               "lanxi": { "host": "169.254.64.156", "timeout": 10, "connector": "BNC" } }
```

1. **Find the driver.** `tim.instr.drivers()` lists the registered drivers; today
   `keysight33220a` (Keysight/Agilent 33220A function generator), `lanxi` (HBK LAN-XI module,
   Open API), `simcombined` (a simulated device with one output and four inputs on one sample
   clock, for both roles, simulation mode only) and `demo` (the demo signal generator DEMO-SG1,
   an imaginary instrument: the worked example of `docs/adding_an_instrument.md`, simulation mode
   only). `d = tim.instr.driverInfo('lanxi')` shows its display name, its roles
   (`d.capabilities.roles`), its default settings (`d.defaults.settings`) and what it allows
   (`d.capabilities`: sample rates, input ranges, filters, loads, levels, sweep times). The
   Instruments table of Setup > Connection shows the same values in its tooltip.
2. **Name it** in `generator.driver` and / or `daq.driver`. A driver that takes both roles (one
   device with output and inputs) is named in both sections and reads its settings from
   `daq.<driver>` only; settings of it in `generator.<driver>` are not used (warning
   `tim:config:misplacedSettings` when the file is loaded and at Connect).
3. **Its own settings** (address, time-out, connector, …) go into `generator.<driver>` or
   `daq.<driver>`; keys left out take the driver's defaults. A file may keep the settings of
   several drivers and switch with `driver`.
4. **The generic settings** (`generator.maxVpp`, `generator.load`, the excitation levels and sweep
   durations, the `acquisition` section) mean the same for every driver, but their allowed values
   come from the selected driver, which checks them and names any value it does not support.
   Loading a file (File > Load configuration…, File > Open measurement…, start-up,
   `tim.app.loadConfig`) only **warns** about such a value - a file written by tubebench 1.1.0 or
   on another set-up still loads; the EXCITATION fields start within the driver's limits (e.g. at
   the generator's smallest level). **Connect** refuses it with the message (window: "Check the
   settings"). The smallest level of the generator is checked for the swept sine (calibration,
   Test E) and the selected signal; another level is refused when it is played.
   `acquisition.sampleRate`, `range`, `filter` and `ccld` left out, `null` or `""` take the
   driver's default.
5. **Connect.** Before connecting the window shows the display names of the selected drivers,
   after Connect the vendor, model, serial number and firmware each instrument reported, and the
   checklist, the lamp labels, the Connect / Disconnect texts and the limits of the EXCITATION
   fields follow the drivers. Every measurement stores the drivers, their settings and these
   identities (`metadata.json`: `generator`, `daq`); a calibration records the acquisition module
   and its input settings, and the CALIBRATION line warns when the measurement uses another one.

An instrument without a driver needs one first: `docs/adding_an_instrument.md` is the
step-by-step procedure (with the templates of `templates/instrument/`; in Claude Code the skill
`add-instrument` runs it), `docs/instrument_interface.md` the contract a driver implements. A file
of the older layout (`formatVersion` 1: `generator.host` / `port` / `timeout` and a `lanxi`
section, as `config/user_config.json` still is) loads with the same settings; File > Save
configuration… writes the new layout. A driver name this installation does not know (a measurement folder from
another set-up) loads with a warning and is shown as `unknown driver "<name>"`, so the data can
still be opened and reprocessed; Connect then reports the error.

### All keys

| Key | Default | Meaning |
|---|---|---|
| `mode` | `"simulation"` | `"simulation"` or `"hardware"` (lab file: hardware) |
| `ui.language` | `"en"` | `"en"` or `"ko"`: operator prompts, dialog titles and buttons of the calibration steps (including the step header and the diagram hint), the excitation confirmation (also its drive line in the log line "Excitation confirmed") and the channel identification, and the command-window prompts of scripts. The calibration prompts are also written to the log in the selected language, and the errors "estimated loudspeaker power exceeds the limit" and "Amplifier gain not entered" are raised in it. All other log lines and errors, the window labels and the documents stay in English. |
| `ui.amplitudeAt` | `"generator"` | what the level field of the window gives: `"generator"` (the programmed level: open circuit in direct drive, the amplifier input with an amplifier) or `"loudspeaker"` (the voltage at the loudspeaker; with an amplifier it needs the gain; section 4, EXCITATION). The excitation amplitudes are always the generator's. |
| `generator.driver` | `"keysight33220a"` | generator driver |
| `generator.keysight33220a.host`, `port`, `timeout` | 169.254.2.20, 5025, 5 s | 33220A (SCPI over TCP); old layout: `generator.host`, `port`, `timeout` |
| `generator.maxVpp` | 0.5 (lab file 2) | **amplitude limit**: the largest **open-circuit** voltage at the generator terminals in Vpp, whatever the load setting (since 1.3.0; before, the programmed value), at most the driver's largest open-circuit voltage (33220A: 20 Vpp) |
| `generator.load` | `"INF"` | output load setting: exactly `"INF"`, or a resistance in ohm written as text within the driver's range (33220A: `"1"`–`"10000"`, e.g. `"50"`, `"600"`); with an amplifier the window sets it to the amplifier input, direct drive needs `"INF"` (see below) |
| `generator.allowUnconfirmedOff` | false | only for a generator that cannot report whether its output is off (none of today's drivers): true accepts it in hardware mode |
| `amplifier.model` | `""` | `"none (direct drive)"` (must start with "none"), `"power amplifier"` or a model name |
| `amplifier.gainFactor` | NaN | voltage gain as a factor (×10 = 10 = 20 dB); 1 for direct drive; `gain_dB` is derived |
| `amplifier.gainSetting` | `""` | free text, e.g. the knob position (scripts) |
| `amplifier.inputImpedance_ohm` | NaN | amplifier input impedance [Ω] from the data sheet (field Amp input [Ω]); NaN = from `generator.load` (`"INF"`: high-Z, a number: that resistance) |
| `amplifier.knownModels` | none (direct drive), power amplifier | items of the Amplifier list |
| `amplifier.confirmBeforeExcitation` | true | excitation confirmation in hardware mode |
| `loudspeaker.impedance_ohm` | 8 | nominal impedance (field Loudspeaker [Ω]) |
| `loudspeaker.maxPower_W` | 1.0 | loudspeaker test limit (field Test limit [W]): power at the nominal impedance; "near the limit" from 80 % |
| `loudspeaker.ratedPower_W` | 25 | rated power: a test limit above it is flagged |
| `daq.driver` | `"lanxi"` | acquisition (DAQ) driver |
| `daq.lanxi.host`, `timeout`, `connector` | 169.254.64.156, 10 s, `"BNC"` | LAN-XI module; `"BNC"` or `"LEMO"`, whichever the microphones use (`""`, possible in files of 1.1.0: the module keeps its own setting); old layout: `lanxi.host`, `timeout`, `connector` |
| `acquisition.sampleRate` | 16384 (driver default) | a rate of the DAQ driver; LAN-XI 3676: 4096, 8192, 16384, 32768 or 65536 S/s |
| `acquisition.range`, `filter` | `"10 Vpeak"`, `"0.7 Hz"` (driver defaults) | input range and high-pass filter, values of the DAQ driver |
| `acquisition.settleTime` | 3 | seconds of CCLD / high-pass settling after the channel setup (hardware) |
| `acquisition.sensitivityPolicy` | `"certificate>teds>nominal"` | order of the sensitivity sources |
| `mics(i)` | ch1–ch4 in M1–M4 | `channel` (DAQ input), `position` (port 1–4 = M1–M4, M1 nearest the loudspeaker), `model`, `serial`, `nominalSensitivity_VperPa` (11.2 mV/Pa), `certificateSensitivity_VperPa`, `certificateDate` |
| `geometry` | D 29 mm, positions NaN | `diameter` (D), `micPositions` (x of M1–M4), `spacingUp`/`spacingDown` (s1, s2), `xFront`, `xRear`; written by the IMPEDANCE TUBE fields |
| `tubeDrawing` | lab CAD | part sizes for the drawings only |
| `environment` | 20 °C, 101325 Pa | `temperature_C`, `pressure_Pa`; `c_override`, `rho_override` replace the computed values; `relativeHumidity` is recorded only |
| `excitation` | section 8 | `mode` and the settings of `sweep`, `stepped`, `noise` |
| `analysis.refChannel` | 1 | reference channel of the transfer functions |
| `analysis.fMin`, `fMax`, `df` | 120, 4500, 2 Hz | analysis band and frequency-line spacing (`fMax` ≤ the usable band of the DAQ driver, LAN-XI: 0.45 × sample rate) |
| `analysis.bandMode` | `"fixed"` | `"fixed"`: `fMin`, `fMax` as set; `"geometry"` (lab file): `fMin`, `fMax` = the ASTM E1050 / E2611 limits of the tube (spacings s1, s2: `lowerFraction`–`upperFraction` × c/s; diameter: 0.58 c/D; c from the temperature), rounded inward to `df` and recomputed whenever those values change; L1, d and L2 do not enter. Section 7 of `docs/theory.md` |
| `analysis.lossModel` | `"kirchhoff"` | tube-loss model: `"kirchhoff"` (visco-thermal wall losses, attenuation and phase-velocity reduction, matching characteristic impedance), `"iso10534"` (ISO 10534-2 attenuation only, for ISO-conformant work) or `"none"`. The same model is used by the analysis, Tests D/E and the virtual tube (`theory.md` section 1). `"iso10534"` and `"none"` bias a thin-element Z_t (up to about 47 % and about two thirds of Z_t at \|Z_t\|/(ρc) = 0.05 in the lab tube) and give a "CHECK: …" warning. A configuration saved before `"kirchhoff"` became the default (2026-10-09), and the `config.json` of an older measurement folder, still name `"iso10534"`. |
| `analysis.velocityRef` | `"mean"` | velocity in Z_t: `"mean"`, `"upstream"` or `"downstream"` |
| `analysis.coherenceMin`, `snrMin_dB` | 0.98, 20 dB | quality limits of the validity masks |
| `analysis.condMax`, `phaseUncertainty_rad`, `maxPhaseSensitivity` | 40, 0.002, 0.05 | geometry limits of the decomposition |
| `analysis.lowerFraction`, `upperFraction` | 0.01, 0.40 | spacing limits 0.01·c/s < f < 0.40·c/s |
| `analysis.passivityTol`, `velocityMismatchMax`, `anechoicRmax` | 0.05, 0.10, 0.1 | passivity, thin-element and anechoic-termination limits |
| `analysis.condQMax`, `reciprocityTol`, `repeatTol` | 10, 0.1, 0.05 | transfer matrix (1.4.0): largest condition number of the two loads (columns of unit length); \|det T − 1\| flagged above it (report only); the median difference of T(A,B) and T(A′,B) relative to \|T\| (the repeat of load A) |
| `measurement.method` | `"oneLoad"` | `"oneLoad"`, `"oneLoadSymmetric"` (T from one load, symmetric specimen assumed) or `"twoLoad"` (field Method) |
| `measurement.loadA`, `loadB` | absorber at `tubeEnd`; rigid at `tubeEnd` | termination of load A (also of a one-load measurement) and load B: `kind` `"absorber"`, `"rigid"` or `"open"` and `place` `"tubeEnd"` or `"joint"` (the absorber only at the tube end); Setup > Tube setup |
| `measurement.repeatLoadA` | true | load A again at the end (A → B → A′) |
| `measurement.loadBLevel_dB` | 0 | level of load B relative to load A, −40 … 0 dB (only lower) |
| `measurement.levelStepWarn_dB`, `maxTemperatureDiff_C`, `maxMinutesBetween` | 10, 1, 30 | warnings: load B so much louder than load A (peak level), the loads more than 1 K or 30 min apart |
| `analysis.validatedBands` | empty | experimentally validated bands (`validation_procedure.md`) |
| `calibration.file` | `""` | calibration loaded at Connect |
| `calibration.positions` | [1 2] | calibration ports a and b |
| `calibration.repeatConfigI`, `verifyEmptySection` | true, true | repeated configuration I; empty-tube check (Test E) |
| `calibration.coherenceMin`, `snrMin_dB` | 0.98, 20 dB | quality limits of the calibration |
| `output.dataDir`, `calibrationDir` | `data`, `calibration` | output folders |
| `output.saveRawStream`, `exportCsv`, `exportFigures`, `figureFormats` | true, true, true, png | what Save measurement writes (add "pdf" for vector figures; about 3 s more per save) |
| `simulation` | – | the virtual tube (geometry, specimen, termination, noise, generator clock error) |

**Amplitudes**: the level field and the messages use **Vpk** (owner decision 2026-10-12); the
field also shows the Vrms, and the first line below the fields gives the generator in **Vpp**, as
its display shows it (the program sets `VOLT:UNIT VPP`). The configuration stores
`amplitudeVpp` and `generator.maxVpp` (= 2 × Vpk), the unit the 33220A is programmed in.

**Generator output load (`generator.load`)**. The 33220A source impedance is always 50 Ω; the
OUTP:LOAD setting only changes what the programmed amplitude means (manual p.189: `INF` or any
1 Ω - 10 kΩ):

| `generator.load` | Programmed amplitude is | Open-circuit voltage | Use |
|---|---|---|---|
| `"INF"` (default) | the open-circuit voltage | = programmed | direct drive (always); an amplifier with a high-impedance input (above 10 kΩ) |
| a resistance R, e.g. `"600"` | the voltage across R | programmed × (R + 50 Ω) / R (`"50"`: 2 ×) | an amplifier with that input impedance (rejected with direct drive) |

The window's **Amp input [Ω]** field (with an amplifier, while not connected) sets both
`amplifier.inputImpedance_ohm` and `generator.load` to the amplifier's input impedance (owner
decision 2026-10-12, WO-004), so the programmed level - and the generator's display - is the
voltage at the amplifier input; the setting is sent to the generator at Connect and read back
(`OUTP:LOAD?`). Above 10 kΩ the generator is set to `INF` (the difference is below 0.5 %). With
direct drive the load is High Z: the loudspeaker gets the open-circuit voltage divided by 50 Ω and
its impedance, V_spk = V_oc · Z / (Z + 50 Ω), about 14 % at 8 Ω, and at most about 2.8 Vpp
(0.12 W) with the 33220A's 20 Vpp - a higher level needs an amplifier.

The amplitude limit `generator.maxVpp` is an open-circuit voltage at every load. The excitation
confirmation shows the programmed value ("programmed into 600 Ω = at the amplifier input") and
the open-circuit voltage. The drive estimate uses `V_in = V_oc·Z_in/(Z_in + 50 Ω)` at the
amplifier input, with `Z_in = amplifier.inputImpedance_ohm`; when that is NaN, `"INF"` means a
high-impedance input (`V_in = V_oc`) and a resistance R an R-ohm input (`V_in` = programmed
value). The loudspeaker voltage is `V_in` × gain (amplifier output impedance ≈ 0) and the power
`P = V_spk,rms²/Z` at the nominal impedance (`V_spk,rms = V_spk,pk/√2`; noise: `/3.3`). A
configuration written by a script with a resistance as the load, an amplifier and no
`amplifier.inputImpedance_ohm` gives the warning "CHECK: Generator output load '…' with an
amplifier of unknown input impedance …": with a high-impedance amplifier input the loudspeaker
would get up to ((R + 50)/R)² × the estimated power (4 × at 50 Ω); a load that differs from the
amplifier input impedance is reported too.

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
  at M1 and M2, the calibration of the channels in M1 and M2 and |R| ≤ 1 + `passivityTol`. A rigid
  plug in front of M3/M4, a high-TL specimen with a weak downstream signal or a failed
  calibration of the M3/M4 channels does not reject R.
* `validTau` and `validThinZt` use both pairs (`valid`) plus their own condition.
* The near-singularity criterion (k·s close to π) is tested separately for each pair.
* For a thick specimen (the 75 mm lab specimen section: k·d up to about 6 at 4.5 kHz) the
  thin-element Z_t has no meaning. Use R, τ and the TL from τ (anechoic termination), or the
  transfer matrix (Method Two loads).

**Transfer matrix** (Method Two loads, or One load, symmetric; `tim.app.processTwoLoad`, result
`tm`, in the pair folder's `result.mat` as `tl`):

| Field | Meaning |
|---|---|
| `T.T11`, `T12`, `T21`, `T22`, `T.detT` | the transfer matrix, [p_L; u_L] = T [p_R; u_R] |
| `condQ` | condition number of the two loads' boundary states (columns of unit length; 1 = independent) |
| `anechoic.tau`, `TL_dB`, `R`, `alpha`, `dissipation`, `Zs` | the specimen with an anechoic termination: τ_a, TL, R_a, α = 1 − \|R_a\|², 1 − \|R_a\|² − \|τ_a\|², surface impedance |
| `hard.R`, `alpha`, `Zs` | the specimen backed by a rigid wall at its rear face (u_R = 0) |
| `thin.Zt`, `T21Zc`, `T22dev` | series impedance T12; \|Z_c·T21\| and \|T22 − 1\| (a thin element: both 0) |
| `reciprocityError`, `symmetryError` | \|det T − 1\|, \|T11 − T22\| / (\|T11\| + \|T22\|) |
| `valid.valid` (`base`, `loadsDiffer`, `notReciprocal`, `summary`) | every load used valid (both pairs) and condQ ≤ `condQMax`; reciprocity is a flag only |
| `checks.errors`, `checks.warnings` | the loads cannot be combined (another calibration, geometry, mapping, signal; equal terminations); temperature and time apart |
| `repeat` (`diff`, `median`, `p90`, `ok`, `text`) | T(A,B) against T(A′,B) |
| `level` (`peak_dB`, `stepB_dB`, `warn`) | peak level in the tube per load, load B over load A |
| `loads` | per load: role, termination, folder, time, temperature, peak level, valid share |

The one-load method (`method` `"oneLoadSymmetric"`) is valid **only** for specimens that are known
to be reciprocal and symmetric; its `reciprocityError` and `symmetryError` are zero by assumption.

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

* `s.Gen` is the generator and `s.Daq` the acquisition module (one object for a device that takes
  both roles); `s.Gen.identity()` / `s.Daq.identity()` return what the instrument reported
  (`vendor`, `model`, `serial`, `firmware`, `raw`) and `metadata()` what is stored with every
  measurement. `connect` logs both in the command window.
* In hardware mode the excitation confirmation appears in the command window ("Type y to
  continue …"); `s.ExcitationConfirm = @(msg) …` replaces it.
* `s.setExcitation(ex)`, `s.setLoudspeaker(Z, Pmax)` and `s.setGeometryEnvironment(geom, env)`
  change settings between measurements (validated). A change of amplifier or amplitude asks for a
  new confirmation.
* The switching calibration from a script prints every step in the command window and waits for
  Enter (`calibration_procedure.md`).
* `s.setTermination(struct('kind', 'rigid', 'place', 'tubeEnd'))` records the termination mounted
  now with every following measurement (`metadata.termination`; in simulation the virtual tube
  gets it). The calibration sets the absorber.
* Two loads from a script (each load saved at once, then the pair folder; the prompts in the
  command window, Enter to go on):

  ```matlab
  out = tim.app.runTwoLoad(s, struct('specimen', 'cell1'));   % loads of s.Cfg.measurement
  out.tl.anechoic.TL_dB, out.tl.valid.valid, out.folder       % (opts.cfg: another configuration)
  p = tim.app.loadTwoLoad(out.folder);                        % reopen; loadTwoLoad({fA, fB}) pairs folders
  tm = tim.app.processTwoLoad(p.loads, cfg);                  % after reprocessing p.loads(i).res
  ```

Processing can be repeated offline at any time, e.g. with corrected geometry or another
calibration:

```matlab
S = load('data/<folder>/raw.mat');  cfg2 = tim.app.loadConfig('config/user_config.json');
cfg2 = tim.app.useRecordedMapping(cfg2, S.meas.mics);   % the ports the microphones were recorded in
C = load('calibration/CAL-20261009-101500.mat', 'cal');
res2 = tim.app.processMeasurement(S.meas, cfg2, C.cal);
```

`tim.app.useRecordedMapping` sets the port of every DAQ channel in `cfg2.mics` to the one the
measurement was recorded with (the configuration loaded now may have been re-cabled since); its
second output says whether the two differed. Leave that line out only to correct an assignment
that was recorded wrongly: `processMeasurement` then uses the configuration's assignment and adds
the warning "Microphone mapping of the configuration … differs …" to `res2.diagnostics.warnings`.

## 12. Stored data

**Save measurement** writes a new folder `data\<yyyyMMdd_HHmmss>_<signal>_<specimen>\`, e.g.
`20261009_111602_sweep_foam_25mm` (`<yyyyMMdd_HHmmss>` = the time of saving; the measurement time
is in `metadata.json` and `README.txt`; `<signal>` = sweep, stepped or background; `<specimen>` =
the name entered at Start measurement, characters other than letters, digits, `_` and `-` become
`_`; without a name, and always for background noise, the folder ends with the signal). Folders are
never overwritten; a suffix `_2`, `_3`, … is added if needed.

| File | Content |
|---|---|
| `raw.mat` | `meas`: raw volts of every repetition, settings, generator events, microphones and sensitivities, metadata (the drivers with their display names and settings, the instrument identities with firmware, TEDS, the LAN-XI setup, amplifier, configuration) and the undecoded stream bytes of the last repetition |
| `result.mat` | `res` (spectra, calibration info, analysis, validity); not for background noise or a measurement without results |
| `config.json`, `metadata.json` | configuration snapshot; metadata including `softwareInfo` |
| `results.csv` | one row per frequency line: R, τ, R_term, Z_t, TL, power fractions, condition numbers, every mask and flag |
| `spectra.csv` | transfer functions per channel, coherence, SNR; stepped sine also the step levels |
| `fig_*.png` | the figures (PNG 200 dpi; a vector PDF only if `output.figureFormats` contains "pdf") |
| `README.txt` | time, mode, software version, repository and commit |

The **saved figures** are drawn by the same views as the window (`tim.app.plotResults`): header
(title, description, note), the graphs, the summary table on the right, the software version in
the footer and a red "SIMULATED DATA" mark for simulated data. File names: `fig_waveforms` (Time
signals), `fig_spectrum`, `fig_transfer` (Transfer functions), `fig_reflection`,
`fig_transmissionLoss`, `fig_impedance` (Transfer impedance), `fig_validity`. The titles and
descriptions of the views come from one source (`tim.plots.viewText`) for the window and the saved
figures. A background-noise record, or a measurement that could not be processed, is saved
without results and CSV files, with the figures it has in the window: `fig_waveforms` and
`fig_spectrum`. The calibration view is drawn by `tim.app.plotCalibration(cal)`; it is not saved
with a measurement.

**Two loads** (1.4.0): every load is an ordinary measurement folder as above
(`…_<signal>_<specimen>_loadA_absorber-end`, `…_loadB_rigid-end`, `…_loadA2_absorber-end`, their
`metadata.json` with `termination` and `twoLoad` (group, role)), and the transfer matrix is in a
pair folder `data\<yyyyMMdd_HHmmss>_twoload_<specimen>\`:

| File | Content |
|---|---|
| `twoload.json` | method, specimen, the loads (role, termination, the name of the load folder in the same data folder, the SHA-256 of its `raw.mat`), the limits, the summary, the repeat of load A, the levels, errors and warnings, software and commit |
| `result.mat` | `tl` (the transfer-matrix result, section 10) and `info` (= `twoload.json`) |
| `results.csv` | per frequency line: T (re, im), condQ, TL, \|τ\|, R_a, α (anechoic), the dissipation, R_h, α (rigid backing), Z_t = T12, \|Z_c·T21\|, \|T22 − 1\|, the reciprocity and symmetry errors, the repeat difference and the masks |
| `fig_*.png` | the figures of load A with the transfer matrix: also `fig_twoLoad` and `fig_transferMatrix` |
| `README.txt` | method, software, the note that the raw data are in the load folders |

A one-load symmetric result is saved with its measurement (`result.mat`: `res.transferMatrix`).

A saved folder is shown again in the window with **File > Open measurement…** (section 7), or
from a script with `app.openMeasurement(folder)`; without the window: `load(fullfile(folder,
'raw.mat'))`, `cfg = tim.app.useRecordedMapping(cfg, meas.mics)` and
`tim.app.processMeasurement(meas, cfg, cal)` (section 11).

Simulated measurements are labelled "SIMULATED DATA" in `README.txt` and in the metadata, and are
stored separately in `data\simulation\` and `calibration\simulation\`, so they cannot be confused
with real measurements and calibrations.

**Practising without hardware**: `tubebench sim` (or
`app = tim.gui.Tubebench('config/sim_thin_screen.json')`) opens the window on a virtual tube with a
thin resistive screen (Z_t = 400 + jω·0.05 Pa·s/m). Press Connect, Run switching calibration…,
then Start measurement. The Transfer impedance and Transmission loss views show the results.

## 13. Troubleshooting

| Symptom | Likely cause / action |
|---|---|
| Start measurement is greyed out | not connected; a failed or stopped connection leaves the instruments disconnected: remove the cause (Setup > Connection names the failed step) and press Connect |
| Alert "Check the settings" | a field is not valid (e.g. the stop frequency is not above the start frequency, L1, d or L2 is not a number): correct it and press Connect, Start measurement or Run switching calibration… again |
| Status "Generator output not confirmed off", Generator lamp red | the read-back after a Stop or an error did not confirm that the generator output (33220A) is off: switch the output off at the instrument |
| "In use" or the Instruments table shows `unknown driver "…"` | the configuration names a driver this installation does not have (e.g. a configuration from another set-up): the data can be opened and reprocessed, Connect is refused; choose a registered driver (section 9, "Choosing the instruments") |
| "In use" shows other instruments than expected | the configuration selects them: check `generator.driver` and `daq.driver` and the operating mode (Simulation shows the simulated instruments, marked "(simulated)") |
| Alert "Measurement cancelled" | Cancel in "Confirm excitation": the loudspeaker was not driven; nothing to repair |
| "enter the voltage gain set on the amplifier …", "Amplifier gain not entered" or "Speaker: enter the amplifier gain" | an amplifier is chosen: type its gain into Amplifier gain [×] (as a factor: 20 dB = ×10) |
| "Max … set by generator.maxVpp" with a low level, e.g. 0.138 Vpk at the speaker in direct drive | the amplitude limit `generator.maxVpp` (an open-circuit voltage; lab file 2 Vpp) is reached, not the loudspeaker limit: in direct drive only 8/58 of it reaches an 8 Ω loudspeaker. Raise `generator.maxVpp` deliberately, or use an amplifier |
| Amplifier input "…": enter the input impedance … | Amp input [Ω] takes a number in ohm (e.g. 600, 10k) or High Z |
| "Generator: connection re-opened (the instrument had closed it) …" | nothing to do: the generator had dropped its idle network connection and the program opened it again, with the output off (section 4, Connection check). The MATLAB command window may show a red stack trace "현재 연결은 원격 호스트에 의해 강제로 끊겼습니다" (an existing connection was forcibly closed by the remote host) at the same moment: MATLAB prints it, it is harmless |
| "Connection lost - Disconnect and Connect", "The connection to the generator was lost and could not be re-opened …" | the generator does not answer: check its LAN cable and power, check the output at the generator, then Disconnect and Connect |
| Excitation refused: estimated loudspeaker power exceeds the limit, "Speaker above the limit" | lower the level or the amplifier gain, or raise Test limit [W] deliberately (at most the rated power) |
| Signal check: LAN-XI flag INVALID on all channels, no TEDS | microphones not connected, or wrong connector (`daq.lanxi.connector` BNC ↔ LEMO; in a file of the older layout, as the lab file: `lanxi.connector`), cable fault |
| Card "check: nominal sensitivity" | no certificate value and no TEDS: enter `certificateSensitivity_VperPa` |
| Card "check: TEDS serial differs from the configuration" | microphone on the wrong channel, or `mics(i).serial` outdated |
| `tim:lanxi:state` | the module is in an unexpected state: Disconnect returns it to Idle (`s.Daq.shutdown()` in scripts) |
| HTTP 403 | request not allowed in the current recorder state (another client? BK Connect open?) |
| `tim:lanxi:streamStalled` | network interruption or module stopped; partial data saved in `data\emergency` |
| `tim:gen:amplitude` | requested amplitude above `generator.maxVpp` (open circuit) or outside the generator's range at the load, or changed at the front panel |
| `tim:gen:load` | the generator load is not `INF` or a resistance of 1-10000 Ω written as a number |
| `tim:gen:scpiError` | the 33220A reported an error (message included); output switched off |
| "Excitation not detected" | amplifier off or muted, loudspeaker disconnected, level too low |
| Calibration "✗ Test E failed" or "– check" (orange) | hover over it: Test E failed, temperature changed by more than 3 K, port distances changed, other mode, another acquisition module or input settings, another microphone on a channel, or calibration sweeps with data integrity problems: check the set-up and recalibrate |
| Calibration message "C3 (ch3/ch1): no valid frequency line" | no usable signal on that input (microphone unplugged, cable or CCLD fault): the calibration of the other channels is saved, that channel stays uncalibrated and the empty-tube check is skipped; repair the input and calibrate again |
| Few valid frequency lines | Results > Validity: "no valid calibration" (load or run a calibration), low coherence / low SNR (amplitude, repetitions), termination not anechoic (τ, TL), velocity mismatch (thick specimen: thin-element Z_t not applicable) |
| Transfer impedance view empty, "Thin-element model not applicable" | the specimen is thick (k·d > 1): use Reflection and transmission and Transmission loss |
| A view shows "Preparing the view…" | the views are prepared in the background during the first half minute after the start (section 2); after a running action it is prepared first. "This view could not be prepared" names the cause in Messages: close and start the program again |
| A MATLAB command window stays open after the program was closed | `start_tubebench.bat` starts MATLAB without its desktop: type `tubebench` there to open the program again, or `exit` to quit MATLAB |
