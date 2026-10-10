# tubebench

Four-microphone transfer-impedance tube measurement (MATLAB)

Repository: <https://github.com/kimwoongji/tubebench> (private; access by invitation of the owner;
not created yet - the code has not been pushed). Until 2026-10-10 the program was called
`transfer-impedance-tube-measurement`; measurements saved before then carry that name.

MATLAB R2022b program "tubebench" for broadband four-microphone impedance-tube
measurements: Keysight/Agilent **33220A** generator → amplifier → loudspeaker → M1 M2 | specimen |
M3 M4 → termination, with four **B&K 4957** microphones on an **HBK LAN-XI Light 3676** (Open API).

It computes the reflection and transmission coefficients, the transmission loss, the thin-element
transfer impedance and the two-port transfer matrix (two-load / symmetric one-load, scripts only),
with explicit validity diagnostics. Measurements run without hardware synchronisation between the
generator and the LAN-XI module.

Supported instruments: the generator and the acquisition module are **drivers chosen in the
configuration** (`generator.driver`, `daq.driver`): today the 33220A (`keysight33220a`) and the
LAN-XI 3676 (`lanxi`), plus a simulated combined device with one output and four inputs on one
clock (`simcombined`) and the demo signal generator of the driver guide (`demo`), both
simulation only. Another instrument needs a driver that follows the contract in
`docs/instrument_interface.md`; `docs/adding_an_instrument.md` is the step-by-step procedure (with
templates in `templates/instrument/`; in Claude Code the skill `add-instrument`). The window has no
instrument selector; it shows the instruments in use and the model, serial number and firmware
they report.

## Quick start

Get the code by cloning `https://github.com/kimwoongji/tubebench.git` (folder `tubebench`;
private repository: your GitHub account needs access) or by copying the project folder.
Double-click **`start_tubebench.bat`**, which starts MATLAB (without its desktop) and opens the
window with `config/user_config.json`; `start_tubebench.bat sim` opens it on a virtual tube. A
small MATLAB command window stays open behind the program. In it, or in the MATLAB command window:

```matlab
tubebench                   % window, real instruments (config/user_config.json)
tubebench sim               % window, virtual tube for practice
results = run_tests();      % self-test in simulation (no hardware needed)
edit start_here.m           % step-by-step script entry point (no window)
run examples/demo_simulation.m   % full simulated workflow + example plots
```

The window guides through Connect → tube geometry → excitation → switching calibration → Start
measurement → Save measurement; `docs/user_guide.md` describes every control and view (also in
the window under Help > User guide).

Configuration: `config/user_config.json` holds the lab settings (instrument addresses, limits,
microphones, lab-tube geometry) and is **tracked in Git**, so a clone has them; commit it after
changing it (File > Save configuration… in the window). The instruments are chosen there by driver
name (`generator.driver`, `daq.driver`; user guide section 9); a file of the older layout loads
unchanged. `config/example_config.json` is a neutral
template (simulation mode, no geometry) - never copy it over `user_config.json`. The stored
software commit does not see uncommitted local changes - commit before measuring with edited code
or configuration.

## Status (2026-10-11)

* **Software**: complete. 299 automated tests in 21 test classes (simulation and recorded hardware
  fixtures); `run_tests` writes the result to `tests/last_test_report.txt`.
* **Window**: menu bar (File, Help), control panel in workflow order (INSTRUMENTS, IMPEDANCE TUBE,
  EXCITATION, CALIBRATION, MEASUREMENT, RESULTS), two-level tabs (Setup, Calibration, Measurement,
  Results, Formula) and a message pane. Every view has a header, the graphs and a summary table;
  the saved figures are drawn by the same views, with the same titles and descriptions. The
  window appears after the control panel and Setup > Connection are built (about 16 s after the
  double-click); the other views are prepared in the background, never during an action.
* **Analysis**: tube losses by default with the visco-thermal (Kirchhoff) model, the ISO 10534-2
  attenuation as an option; air density from the ideal-gas law; R and its validity from the
  upstream microphone pair alone. See `docs/theory.md`.
* **Hardware**: network, identification, the LAN-XI recorder state machine and binary streaming
  are verified on the real instruments. The generator output, the microphone chain, TEDS,
  calibration and the acoustic validation (Tests A–G) are **pending**; see
  `docs/hardware_status.md`, which also lists the pending hardware check of the 1.2.0 instrument
  interface (WO-001, branch `wo-001`: software-verified in simulation only).
* **Geometry**: CAD design values of the lab tube (s1 29, L1 41, d 75, L2 41, s2 29 mm; the
  specimen fills the 75 mm specimen section) are in `config/user_config.json`; verify them with
  calipers. The switching calibration is done with the empty specimen section mounted and ends
  with an automatic empty-tube check (Test E).

## Structure

The code is the MATLAB package `+tim` (tim = transfer-impedance measurement, the internal package
of tubebench, which kept its name when the program was renamed). The main window is the class
`tim.gui.Tubebench`.

```
start_here.m            entry point (sections)        run_tests.m   automated tests
tubebench.m, start_tubebench.bat   start the window
config/                 user_config.json (lab settings), example_config.json (template),
                        sim_thin_screen.json (virtual tube)
+tim/+instr             instrument contract: Instrument, SignalSource, Acquisition; registry:
                        drivers (one line per driver), driverInfo, create, checkProducts;
                        drivers Keysight33220A ('keysight33220a', with ScpiTcpTransport) and
                        LanXi ('lanxi', with LanXiHttp, LanXiTcpStream, LanXiStreamParser,
                        RecordingStream); their protocol mocks Mock* (simulation), mockBusLog;
                        DemoSource ('demo', with MockDemoSource: the worked example of the
                        driver guide, simulation only)
+tim/+acq               checkIntegrity, basicIntegrity, voltsToPascal
+tim/+dsp               sweepResponse, sineResponse, welchResponse, detectExcitation, estimateSweepLaw
+tim/+cal               switchingCorrection, buildCalibration, interpolateCalibration,
                        applyCalibration, resolveSensitivities, calibrationContext, acquisitionChain
+tim/+acoustics         airProperties, wavenumber, decomposeWaves, fieldAt, analyzeFourMic,
                        validityMasks, transferMatrix, frequencyLimits
+tim/+sim               SimulatedRig, tubeModel, lanxiEncode; SimulatedCombined (driver
                        'simcombined': one output + four inputs on one clock, simulation only)
+tim/+app               MeasurementSession, runCalibration, processMeasurement, driveEstimate,
                        plotResults (saved figures), plotCalibration, save* / export*,
                        loadConfig / saveConfig / defaultConfig / validateConfig / migrateConfig,
                        outputGuard, msg (prompts en / ko), softwareVersion
+tim/+plots             the views, shared by the window and the saved figures: timeSignals,
                        spectrum, transferFunctions, reflection, transmissionLoss,
                        transferImpedance, validity, calibration; house style and helpers:
                        style, fitAxes, legend, masked, bandValues, octaveBands, dataTitle,
                        emptyState, thickSpecimen, viewText (titles and descriptions)
+tim/+gui               Tubebench (uifigure window; names no instrument: lamps, checklist,
                        texts, identity display and field limits come from the drivers),
                        ViewPage (header + graphs + summary of a view),
                        drawTube3D (3D tube model), equationsPanel (Formula tab), Checklist,
                        StartWindow (start window with progress), palette, icon, logo, closeApp
+tim/+val               hardware validation procedures (Tests A–E)
+tim/+cad               readStep (STEP assembly reader used for the tube dimensions)
resources/icons         status and button icons
resources/logo          the tubebench mark: SVG (light, reverse) and PNG 16/32/48/256 px (window icon)
tests/                  matlab.unittest suites + fixtures (real LAN-XI responses and stream,
                        bus traffic of simulated sessions, normal and fault paths:
                        TestBusTraffic); TestInstrumentContract (every registered driver);
                        TestInstrumentTemplates (the driver templates); TestConfiguration (layout
                        and migration); TestGui (hidden window, also with the simulated combined
                        device; identity display); support/ (test-only drivers)
templates/instrument    starting files for a new driver (source, acquisition, combined device,
                        their protocol mocks and tests, reference document, configuration
                        snippets); not on the path (docs/adding_an_instrument.md)
.claude/skills          add-instrument: the Claude Code skill that runs the driver guide
examples/               demo_simulation.m, hardware_commissioning.m, bench_test_no_tube.m,
                        output/ (example plots)
docs/                   see below
data/, calibration/     measurement and calibration output (never overwritten)
```

## Documentation

| Document | Content |
|---|---|
| `docs/installation_windows.md` | dependencies (none beyond MATLAB + toolboxes; what each instrument driver needs), network, verification, Git |
| `docs/user_guide.md` | the window, workflow, views, menus, safety, configuration, scripts, results, stored data, troubleshooting |
| `docs/calibration_procedure.md` | sensitivity and switching calibration (12 operator steps, empty-tube check) |
| `docs/validation_procedure.md` | Tests A–G, criteria and tolerance rationale |
| `docs/theory.md` | conventions, derivations, estimators, frequency limits, validity levels |
| `docs/hardware_status.md` | verified vs pending, observations from the hardware sessions |
| `docs/assumptions_and_limitations.md` | assumptions, limitations, future work |
| `docs/ref_33220A_scpi.md`, `docs/ref_lanxi_openapi.md` | verified instrument protocol references |
| `docs/instrument_interface.md` | contract for instrument drivers, as built (WO-001 for 1.2.0, stages A–C: contract classes, drivers, registry, contract tests, configuration by driver name, session through the registry, simulated combined device, the window from the drivers; Part 2: guide, templates, skill, demo); software-verified, hardware check pending |
| `docs/adding_an_instrument.md` | how to add a driver for another instrument, step by step (facts, suitability, templates, mock, tests, hardware verification with the owner, safety rules); worked example: the demo source, `docs/ref_demo_source.md` |

## References

LAN-XI Open API user guide BE 1872; HBK `open-api-tutorials` (stream format, single-module
example) and `open-api-time-data-recorder` (MATLAB reference, MIT licence; used as a behavioural
reference, not copied); Agilent 33220A User's Guide 33220-90002; ISO 10534-2; ASTM E1050; ASTM E2611.
