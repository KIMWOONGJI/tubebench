# Measurement user guide

## 1. First steps

1. Read `installation_windows.md`, then run `run_tests` once. All tests must pass.
2. `copy config\example_config.json config\user_config.json` and edit:
   * `"mode"`: `"simulation"` to practise, `"hardware"` for real measurements.
   * `"generator.maxVpp"`: **safety limit** of the generator amplitude (Vpp) for your
     amplifier/loudspeaker. Every excitation amplitude is checked against it, both in software
     and by instrument read-back before the output is switched on.
   * `"generator.load"`: `"INF"` if the amplifier input is high-impedance. This only rescales the
     programmed value: the 33220A source impedance is always 50 Ω.
   * `"amplifier"`: `model` (GUI drop-down; `"none (direct drive)"` = loudspeaker connected
     directly to the 33220A; the list comes from `knownModels`, and models typed in the GUI are
     added for the session) and `gainFactor`, the voltage gain as a **multiplier** (×10 = 10 =
     20 dB; `gain_dB` is derived). The amplifier gain is set **by hand**; the software cannot
     change it. It records the value with every measurement and, in hardware mode, asks you to
     confirm before the loudspeaker is driven. The confirmation shows the generator amplitude in
     **Vpk**, the amplifier gain and the expected amplifier output in Vpk; for direct drive it
     shows the voltage and current at an 8 Ω loudspeaker. It asks once per combination, and again
     after `s.setAmplifierGain('model', 10)` or an amplitude change. Set
     `confirmBeforeExcitation: false` to disable it.
   * **Amplitudes**: the GUI and all messages use **Vpk** (generator open-circuit peak
     voltage). The configuration file stores `amplitudeVpp` and `generator.maxVpp` (= 2 × Vpk),
     the unit the 33220A is programmed in.
   * `"ui.language"`: `"en"` (default) or `"ko"`, the language of operator prompts
     (calibration steps, excitation confirmation, channel identification). Logs stay in English.
   * `"lanxi.connector"`: `"BNC"` or `"LEMO"`, whichever the microphones are plugged into.
   * `"mics"`: per DAQ channel, the tube **position** (1 = M1 nearest the loudspeaker … 4 = M4),
     serial number and certificate sensitivity.
   * `"geometry"`: diameter, and **measured** axial positions `micPositions` (M1..M4) and sample
     faces `xFront`, `xRear` in metres, in one coordinate system increasing towards the
     termination. Until they are entered, only pair-local results are produced. The software
     never guesses these values.
   * `"environment"`: temperature and static pressure at the time of measurement.
   * `"excitation"`: see section 3.
3. Start the GUI by double-clicking `start_tubeapp.bat`, or type `tubeapp` in MATLAB
   (`tubeapp sim` for the virtual tube). Alternatively, run `start_here.m` section by section
   for script-based use.

## 2. Safety behaviour

* Connecting **always switches the generator output OFF**, and it stays off while you configure.
* The output is armed only inside a measurement that you started explicitly (`s.measure(...)`,
  the START button, or a calibration step). It is switched off as soon as the excitation ends and
  disarmed after the measurement.
* On any error (network, stream, overload, user STOP): output OFF, LAN-XI recording stopped. The
  data received so far are saved to `data/emergency/partial_*.mat` and the error is reported.
* Overload: the LAN-XI DataQuality flags and a software peak check (≥ 99 % of range) mark the
  measurement as failing integrity. Results are still computed, but the measurement is reported
  as failed.
* Start with a low generator amplitude **and a low amplifier gain**, and increase gradually (see
  commissioning section H3).

### Driving the loudspeaker directly from the 33220A (no power amplifier)

This is possible for bench tests and low-level measurements. The 33220A manual (specifications)
states: output impedance 50 Ω, "Short-circuit protected, overload automatically disables main
output", and at most 20 Vpp into an open circuit. With a loudspeaker of impedance Zs the 50 Ω
source forms a voltage divider:

| Programmed (`generator.load = "INF"`, open-circuit Vpp) | at 8 Ω | at 4 Ω |
|---|---|---|
| 1 Vpp | 0.14 Vpp, 0.3 mW | 0.07 Vpp, 0.2 mW |
| 10 Vpp | 1.38 Vpp, 30 mW | 0.74 Vpp, 17 mW |
| 20 Vpp (maximum) | 2.76 Vpp, **0.12 W** | 1.48 Vpp, 69 mW |

* About 0.1 W at most. That is harmless for practically any loudspeaker and enough for the
  impedance tube, where the plane wave stays confined. In free air it gives roughly 80–90 dB SPL at
  0.3 m for a typical driver (estimate; depends on the driver's sensitivity).
* With 50 Ω source impedance the drive is current-like and the loudspeaker is poorly damped. This
  does **not** matter for the measurement, which uses only microphone ratios.
* Keep `generator.load = "INF"`: the programmed value is then the open-circuit voltage. The real
  voltage at the loudspeaker is `V·Zs/(Zs+50)`, and Zs varies with frequency.
* Record the configuration as `"amplifier": {"model": "none (direct drive)", "gainSetting": "-",
  "gain_dB": null}` and raise `generator.maxVpp` deliberately, e.g. to 10–20 Vpp.

### GUI overview (`tubeapp`)

Left panel, top to bottom (compact: related fields share a row; it fits a 1920 × 1080 screen
without scrolling and scrolls only in a very small window):

* **INSTRUMENTS**: mode (simulation / hardware), Load / **Save config…**, Connect + TEDS, and a
  row of **status lamps** (Generator, LAN-XI, ch1–ch4: grey = not connected, blue = running,
  green = OK, orange = check, red = fault). "Connect + TEDS" opens the **Connection** tab, where
  every step is listed while it runs, with a turning icon for the running step (it keeps turning
  during the slow LAN-XI channel setup, > 10 s), its result and its duration: generator (SCPI,
  output OFF), LAN-XI module, recorder Idle, open recorder, TEDS detection, channel setup →
  streaming, microphone sensitivities, settling, and a **1 s signal check without excitation**
  (level in dB SPL, INVALID / clipped / dead flags per channel). Below the list one card per
  channel shows its port, TEDS type and serial, sensitivity and source, and the background level.
  A failing step is marked red together with the error message.
* **EXCITATION**: mode (**sweep** = broadband default; **stepped** = discrete sines for
  cross-checks), frequency range, sweep time (**Steps** in stepped mode), **amplitude in Vpk**,
  repetitions, **amplifier** (drop-down: "none (direct drive)", "power amplifier", or type your
  model), **gain as a multiplier** (×10 = 20 dB), and the **loudspeaker impedance and power
  limit**. The line below shows the estimated loudspeaker voltage, current and power for the
  current settings, in red if a limit is exceeded. Excitation is refused above the power limit,
  and with an amplifier whose gain is not entered. START, STOP and **Background** (2 s without
  excitation) share one row.
* **IMPEDANCE TUBE**: inner diameter, temperature and pressure on one row, then the five
  **distances in mm** on one row in the order of the tube ("?" = not measured), measured between
  port **centres** and specimen **faces**:

  | Field | From → to |
  |---|---|
  | `s1` | centre of port M1 → centre of port M2 |
  | `L1` | centre of port M2 → specimen **front** face (towards the loudspeaker) |
  | `d` | specimen front face → rear face (thickness; 0 for a thin screen) |
  | `L2` | specimen **rear** face → centre of port M3 |
  | `s2` | centre of port M3 → centre of port M4 |

  Leave L1, d or L2 empty while they are not measured. Acquisition and the relative spectra still
  work, but specimen results (R, τ, Zt, TL) are disabled. Internally x = 0 is the specimen front
  face (`xFront = 0`, `xRear = d`, `x_M2 = −L1`, `x_M1 = −L1 − s1`, `x_M3 = d + L2`,
  `x_M4 = d + L2 + s2`), and these coordinates are what is stored in the configuration file
  (on a 1 nm grid: without this, binary floating point would show s1 = 29.000000000000004 mm
  while editing and write 0.11599999999999999 instead of 0.116 to the file).
  Temperature and pressure are entered here too. The line below the fields shows the speed of
  sound, the geometric frequency range and any input error (red). The **Tube setup** tab shows a
  **3D model** of the tube built from these values, with the dimension lines s1, L1, d, L2, s2
  (black) and the overall lengths (grey). It is redrawn as soon as a field changes and keeps
  your viewpoint. Buttons: **Default** (side view, slightly from above), **Side** (like a 2D
  drawing), **Perspective**, **Top**; rotate / zoom / pan freely with the toolbar of the drawing.
  **Section view** removes the half towards the viewer (cut faces hatched) so that the bore, the
  specimen and the microphone tips are visible; microphones, holders and bolts are drawn whole,
  as in a technical drawing. Each microphone carries the colour of the LAN-XI channel mounted in
  that port. Save the values with "Save config…".

  The lab tube (CAD assembly `cad/transfer-impedance-tube.step`) gives s1 = 29, L1 = 41,
  d = 75 (the specimen fills the 75 mm middle section), L2 = 41 and s2 = 29 mm; these design
  values are in `config/user_config.json` and should be checked on the real tube. The parts used
  only for the drawing are in the `tubeDrawing` section of the configuration (CAD values: flanges
  and specimen section Ø65 mm, tube body Ø45 mm, flanges 9 mm with 6 × M4, bore end 95 mm before
  M1, termination 291 mm after M4, loudspeaker housing Ø135 mm at the large end, microphone
  holders Ø22 mm, B&K 4957 Ø7 × 34.1 mm with the tip 0.25 mm behind the bore wall, absorber at
  the small end with `absorberLength` = null until it is known). They do not enter any
  calculation. The loudspeaker inside the housing is schematic. `tim.cad.readStep` reads such a
  STEP assembly (part names, cylinders, planes, placements) if the tube is changed.
* **CALIBRATION**, **RESULTS**.

During a measurement or calibration the panel is locked and only **ABORT** is active. The
**Waveforms** tab shows the four channels **live** (last 0.5 s, SPL per channel, about 5 updates
per second). After the measurement it shows the whole record, one graph per channel. The
waveforms are shown as **sound pressure in Pa** (voltage / sensitivity, the sensitivity and its
source are in the title of each graph). The LAN-XI deliberately streams **volts** (module
default transducer, sensitivity 1 V/V) and the raw data are stored in volts; the sensitivity
(certificate > TEDS > nominal) is applied once in software, so it can never be applied twice.
Without any sensitivity the graphs fall back to mV. All plots
use one colour-blind-safe palette (ch1 blue, ch2 vermillion, ch3 green, ch4 purple; grey = not
valid).

The noise excitation is available from scripts only (`s.measure('noise')`): the swept sine
covers its purpose. In **stepped** mode the fields f start / stop, **Steps** (instead of the
sweep time) and Repetitions set the stepped sine. Its record holds one tone per step, so the
PSD of the record would be a line spectrum (one spike per step): the **Spectrum** tab therefore
shows the **level of every step** (sine fit of the settled part, dB SPL, dotted = noise in the
fit bandwidth), and all results are drawn with **markers at the step frequencies** (also in the
saved figures and `spectra.csv`: `level<c>_dB_SPL`, `noise<c>_dB_SPL`).

**Closing the window**: a "Closing" dialog appears at once and shows the steps (generator output
OFF, LAN-XI back to Idle with 2 s time-outs, so a switched-off instrument cannot delay it). If a
measurement or calibration is running, it is stopped first (output OFF at once) and the window
closes as soon as the action has stopped; a second close request closes immediately.

The window title is "Transfer impedance tube"; the bottom line shows the software version (with
the Git commit) and a link to the repository
(<https://github.com/kimwoongji/transfer-impedance-tube-measurement>, private). The version, the
repository and the commit are also stored with every measurement (`metadata.json`, field
`softwareInfo`, and `README.txt`) and calibration.

## 3. Excitation modes

| Mode | Use | Main settings (`excitation.*`) |
|---|---|---|
| `sweep` (default) | broadband, fast, robust | `fStart`, `fStop` (choose wider than the analysis band, e.g. 80–5500 Hz), `duration` (2–10 s), `amplitudeVpp`, `repetitions` (≥ 2 gives a meaningful coherence), `preRoll` (≥ 0.5 s of silence for the noise estimate), `postRoll` (ring-down) |
| `stepped` | highest SNR at selected frequencies, cross-check | `fStart`, `fStop`, `nPoints`, `spacing` (`log`/`lin`), `settleTime`, `recordTime`, `nBlocks`, `repetitions` |
| `noise` | optional (33220A built-in noise), Welch H1 | `amplitudeVpp`, `duration`, `nfft` |

The 33220A and the LAN-XI are **not synchronised**. The sweep is triggered by software (`*TRG`)
once the pre-roll has been received, and switched off after `*OPC?` reports completion. The
analysis uses only ratios between microphones, so timing uncertainty, the generator clock and the
exact sweep law do not matter (`theory.md` section 4). The sweep must, however, lie inside the
recording; this is checked and reported (`res.diagnostics.excitation`, `sweepLaw`).

## 4. Typical session (script)

```matlab
cfg = tim.app.loadConfig('config/user_config.json');
s = tim.app.MeasurementSession(cfg);
s.connect();  s.prepareAcquisition();          % output OFF, TEDS read
bg = s.measureBackground(2);                    % electrical check
s.loadCalibration('calibration/CAL-20261009-101500.mat');   % or: cal = tim.app.runCalibration(s);
meas = s.measure('sweep');                      % explicit start
res  = tim.app.processMeasurement(meas, cfg, s.Calibration);
figs = tim.app.plotResults(res, meas);
folder = tim.app.saveMeasurement(meas, res, cfg, 'foam_25mm', figs);
s.close();
```

Processing can be repeated offline at any time, for example with corrected geometry or another
calibration:

```matlab
S = load('data/<folder>/raw.mat');  cfg2 = tim.app.loadConfig('config/user_config.json');
res2 = tim.app.processMeasurement(S.meas, cfg2, cal);
```

## 5. Results and how to read them

`res.analysis`:

| Field | Meaning | Valid only if |
|---|---|---|
| `R` | complex pressure reflection coefficient at the front face | `valid.validR` |
| `tau` | forward wave at the rear face / incident wave at the front face | `valid.validTau` (needs `|Rterm| ≤ 0.1`) |
| `Rterm` | reflection of the downstream termination, at the rear face | diagnostic |
| `thin.Zt`, `thin.Zt_norm` | thin-element transfer impedance `(pL−pR)/u` [Pa·s/m], normalised by ρc (only meaningful for a thin element, k·d ≪ 1; for the 75 mm lab specimen section the GUI and the saved figures show a note instead of the curves) | `valid.validThinZt` (velocity mismatch ≤ 10 %) |
| `thin.velocityMismatch` | `|uL−uR|/max` | – |
| `thin.TL_dB` | transmission loss from Zt: `20·log10|1+Zt/(2ρc)|` (anechoic-equivalent, termination independent) | `valid.validThinZt` |
| `power.TL_tau_dB` | `−20·log10|τ|` from the measured τ | `valid.validTau` |
| `power.Rpow`, `tauPow`, `alpha` | power fractions; α = dissipated fraction (anechoic end) | `validTau` |
| `boundary.pL,uL,pR,uR` | extrapolated face values (relative units) | geometry complete |
| `waves.A1,B1,A2,B2`, `cond1,cond2` | wave amplitudes, condition numbers | – |
| `local.R_up_atM2`, `R_dn_atM3` | pair-local reflection (no geometry needed) | – |
| `valid.*` | masks and the reason for every rejection (`valid.flags`), `valid.summary` | – |

Transfer matrix (needs two measurements of the same sample with **different terminations**):

```matlab
resA = tim.app.processMeasurement(measA, cfg, cal);   % e.g. anechoic termination
resB = tim.app.processMeasurement(measB, cfg, cal);   % e.g. rigid / open termination
tm = tim.acoustics.transferMatrix('twoLoad', resA.analysis, resB.analysis);
% tm.T11..T22, tm.condQ (check!), tm.TL_dB, tm.tau_anechoic, tm.reciprocityError
```

`transferMatrix('oneLoadSymmetric', res)` is available **only** for samples that are known to be
reciprocal and symmetric.

**Three levels of trust**: *measured* → *valid* (geometry, quality and calibration criteria
passed) → *validated* (inside the experimentally validated bands, `analysis.validatedBands`,
which are empty until Tests D/E have passed on this set-up). Plots draw non-valid values in grey.
CSV files contain all flags.

## 6. Stored data

`data/<yyyyMMdd_HHmmss>_<name>/`: `raw.mat` (raw volts of every repetition, settings, generator
events, metadata including instrument identities, firmware, TEDS, LAN-XI setup, the undecoded
stream bytes of the last repetition, and the configuration), `result.mat`, `config.json`,
`metadata.json`, `results.csv`, `spectra.csv`, and figures (PNG + PDF). Folders are never
overwritten; a suffix `_2`, `_3`, … is added if needed. Simulated measurements are labelled
`SIMULATED DATA` in `README.txt` and in the metadata. In simulation mode they are also stored
separately, in `data/simulation/` and `calibration/simulation/`, so they cannot be confused with
real measurements and calibrations.

**Trying the analysis without hardware**: `app = tim.gui.TubeApp('config/sim_thin_screen.json')`
opens the GUI on a virtual tube with a thin resistive screen (Zt = 400 + jω·0.05 Pa·s/m). Press
"Connect + TEDS", then "Run switching cal.", then "START". The "Transfer impedance" and
"Transmission loss" tabs show the results.

## 7. Troubleshooting

| Symptom | Likely cause / action |
|---|---|
| Integrity: `INVALID` on all channels, no TEDS | microphones not connected, or wrong connector (`lanxi.connector` BNC↔LEMO), cable fault |
| `tim:lanxi:state` | the module is in an unexpected state: `s.Daq.shutdown()` returns it to Idle |
| HTTP 403 | request not allowed in the current recorder state (another client? BK Connect open?) |
| `tim:lanxi:streamStalled` | network interruption or module stopped; partial data saved in `data/emergency` |
| `tim:gen:amplitude` | requested amplitude above `generator.maxVpp`, or changed at the front panel |
| `tim:gen:scpiError` | 33220A reported an error (message included); output switched off |
| "Excitation not detected" | amplifier off/muted, speaker disconnected, level too low |
| Few valid bins | check `valid.flags`: `calInvalid` (no or unsuitable calibration), `lowCoherence`/`lowSNR` (level, repetitions), `velocityMismatch` (thick sample: use the transfer matrix) |
