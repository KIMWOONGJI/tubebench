# transfer-impedance-tube-measurement

Repository: <https://github.com/kimwoongji/transfer-impedance-tube-measurement> (private; access by
invitation of the owner)

MATLAB R2022b program "Transfer impedance tube" for broadband four-microphone impedance-tube
measurements: Keysight/Agilent **33220A** generator → amplifier → loudspeaker → M1 M2 | specimen |
M3 M4 → termination, with four **B&K 4957** microphones on an **HBK LAN-XI Light 3676** (Open API).

It computes the reflection and transmission coefficients, the transmission loss, the thin-element
transfer impedance and the two-port transfer matrix (two-load / symmetric one-load, scripts only),
with explicit validity diagnostics. Measurements run without hardware synchronisation between the
generator and the LAN-XI module.

## Quick start

Get the code by cloning `https://github.com/kimwoongji/transfer-impedance-tube-measurement.git`
(private repository: your GitHub account needs access) or by copying the project folder.
Double-click **`start_tubeapp.bat`**, which starts MATLAB and opens the window with
`config/user_config.json`. `start_tubeapp.bat sim` opens it on a virtual tube. From the MATLAB
command window:

```matlab
tubeapp                     % window, real instruments (config/user_config.json)
tubeapp sim                 % window, virtual tube for practice
results = run_tests();      % self-test in simulation (no hardware needed)
edit start_here.m           % step-by-step script entry point (no window)
run examples/demo_simulation.m   % full simulated workflow + example plots
```

The window guides through Connect → tube geometry → excitation → switching calibration → Start
measurement → Save measurement; `docs/user_guide.md` describes every control and view (also in
the window under Help > User guide).

Configuration: `config/user_config.json` holds the lab settings (instrument addresses, limits,
microphones, lab-tube geometry) and is **tracked in Git**, so a clone has them; commit it after
changing it (File > Save configuration… in the window). `config/example_config.json` is a neutral
template (simulation mode, no geometry) - never copy it over `user_config.json`. The stored
software commit does not see uncommitted local changes - commit before measuring with edited code
or configuration.

## Status (2026-10-09)

* **Software**: complete. 189 automated tests in 16 test classes (simulation and recorded hardware
  fixtures); `run_tests` writes the result to `tests/last_test_report.txt`.
* **Window**: menu bar (File, Help), control panel in workflow order (INSTRUMENTS, IMPEDANCE TUBE,
  EXCITATION, CALIBRATION, MEASUREMENT, RESULTS), two-level tabs (Setup, Calibration, Measurement,
  Results, Formula) and a message pane. Every view has a header, the graphs and a summary table;
  the saved figures are drawn by the same views, with the same titles and descriptions.
* **Analysis**: tube losses by default with the visco-thermal (Kirchhoff) model, the ISO 10534-2
  attenuation as an option; air density from the ideal-gas law; R and its validity from the
  upstream microphone pair alone. See `docs/theory.md`.
* **Hardware**: network, identification, the LAN-XI recorder state machine and binary streaming
  are verified on the real instruments. The generator output, the microphone chain, TEDS,
  calibration and the acoustic validation (Tests A–G) are **pending**; see
  `docs/hardware_status.md`.
* **Geometry**: CAD design values of the lab tube (s1 29, L1 41, d 75, L2 41, s2 29 mm; the
  specimen fills the 75 mm specimen section) are in `config/user_config.json`; verify them with
  calipers. The switching calibration is done with the empty specimen section mounted and ends
  with an automatic empty-tube check (Test E).

## Structure

```
start_here.m            entry point (sections)        run_tests.m   automated tests
tubeapp.m, start_tubeapp.bat   start the window
config/                 user_config.json (lab settings), example_config.json (template),
                        sim_thin_screen.json (virtual tube)
+tim/+instr             Keysight33220A, ScpiTcpTransport, LanXi, LanXiHttp, LanXiTcpStream,
                        LanXiStreamParser, RecordingStream, Mock* (simulation)
+tim/+acq               checkIntegrity, voltsToPascal
+tim/+dsp               sweepResponse, sineResponse, welchResponse, detectExcitation, estimateSweepLaw
+tim/+cal               switchingCorrection, buildCalibration, interpolateCalibration,
                        applyCalibration, resolveSensitivities, calibrationContext
+tim/+acoustics         airProperties, wavenumber, decomposeWaves, fieldAt, analyzeFourMic,
                        validityMasks, transferMatrix, frequencyLimits
+tim/+sim               SimulatedRig, tubeModel, lanxiEncode
+tim/+app               MeasurementSession, runCalibration, processMeasurement, driveEstimate,
                        plotResults (saved figures), plotCalibration, save* / export*,
                        loadConfig / saveConfig / defaultConfig / validateConfig, msg (prompts
                        en / ko), softwareVersion
+tim/+plots             the views, shared by the window and the saved figures: timeSignals,
                        spectrum, transferFunctions, reflection, transmissionLoss,
                        transferImpedance, validity, calibration; house style and helpers:
                        style, fitAxes, legend, masked, bandValues, octaveBands, dataTitle,
                        emptyState, thickSpecimen, viewText (titles and descriptions)
+tim/+gui               TubeApp (uifigure window), ViewPage (header + graphs + summary of a view),
                        drawTube3D (3D tube model), equationsPanel (Formula tab), Checklist,
                        palette, icon, closeApp
+tim/+val               hardware validation procedures (Tests A–E)
+tim/+cad               readStep (STEP assembly reader used for the tube dimensions)
resources/icons         status and button icons
tests/                  matlab.unittest suites + fixtures (real LAN-XI responses and stream)
examples/               demo_simulation.m, hardware_commissioning.m, bench_test_no_tube.m,
                        output/ (example plots)
docs/                   see below
data/, calibration/     measurement and calibration output (never overwritten)
```

## Documentation

| Document | Content |
|---|---|
| `docs/installation_windows.md` | dependencies (none beyond MATLAB + toolboxes), network, verification, Git |
| `docs/user_guide.md` | the window, workflow, views, menus, safety, configuration, scripts, results, stored data, troubleshooting |
| `docs/calibration_procedure.md` | sensitivity and switching calibration (12 operator steps, empty-tube check) |
| `docs/validation_procedure.md` | Tests A–G, criteria and tolerance rationale |
| `docs/theory.md` | conventions, derivations, estimators, frequency limits, validity levels |
| `docs/hardware_status.md` | verified vs pending, observations from the hardware sessions |
| `docs/assumptions_and_limitations.md` | assumptions, limitations, future work |
| `docs/ref_33220A_scpi.md`, `docs/ref_lanxi_openapi.md` | verified instrument protocol references |

## References

LAN-XI Open API user guide BE 1872; HBK `open-api-tutorials` (stream format, single-module
example) and `open-api-time-data-recorder` (MATLAB reference, MIT licence; used as a behavioural
reference, not copied); Agilent 33220A User's Guide 33220-90002; ISO 10534-2; ASTM E1050; ASTM E2611.
