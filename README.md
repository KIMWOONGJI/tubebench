# transfer-impedance-tube-measurement

Repository: <https://github.com/kimwoongji/transfer-impedance-tube-measurement> (private; access by
invitation of the owner)

MATLAB R2022b application for broadband four-microphone impedance-tube measurements:
Keysight/Agilent **33220A** generator → amplifier → loudspeaker → M1 M2 | sample | M3 M4 →
termination, with four **B&K 4957** microphones on an **HBK LAN-XI Light 3676** (Open API).

It computes the reflection and transmission coefficients, the thin-element transfer impedance,
and the two-port transfer matrix (two-load / symmetric one-load), with explicit validity
diagnostics. Measurements can run without hardware synchronisation between the generator and the
DAQ.

## Quick start

Get the code by cloning `https://github.com/kimwoongji/transfer-impedance-tube-measurement.git`
(private repository: your GitHub account needs access) or by copying the project folder.
Double-click **`start_tubeapp.bat`**, which starts MATLAB and opens the GUI with
`config/user_config.json`. `start_tubeapp.bat sim` opens the GUI on a virtual tube. From the
MATLAB command window:

```matlab
tubeapp                     % GUI, real instruments (config/user_config.json)
tubeapp sim                 % GUI, virtual tube for practice
results = run_tests();      % simulation self-test (no hardware needed)
edit start_here.m           % step-by-step script entry point (no GUI)
run examples/demo_simulation.m   % full simulated workflow + example plots
```

Configuration: `config/user_config.json` holds the lab settings (instrument addresses, limits,
microphones, lab-tube geometry) and is **tracked in Git**, so a clone has them; commit it when
you change it ("Save config…"). `config/example_config.json` is a neutral template (simulation
mode, no geometry) - never copy it over `user_config.json`. The stored software commit does not
see uncommitted local changes - commit before measuring with edited code or configuration.

## Status (2026-10-09)

* **Software**: complete. 100 automated tests (simulation and recorded hardware fixtures); see
  `tests/last_test_report.txt`.
* **Hardware**: network, identification, the LAN-XI recorder state machine and binary streaming
  are verified on the real instruments. The generator output, the microphone chain, TEDS,
  calibration and the acoustic validation (Tests A–G) are **pending**; see
  `docs/hardware_status.md`.
* **Geometry**: CAD design values of the lab tube (s1 29, L1 41, d 75, L2 41, s2 29 mm; the
  specimen fills the 75 mm middle section) are in `config/user_config.json`; verify them with
  calipers. The switching calibration is done with the EMPTY 75 mm section mounted and ends with an
  automatic empty-tube check (Test E).

## Structure

```
start_here.m            entry point (sections)        run_tests.m   automated tests
config/                 user_config.json (lab settings), example_config.json (template)
+tim/+instr             Keysight33220A, ScpiTcpTransport, LanXi, LanXiHttp, LanXiTcpStream,
                        LanXiStreamParser, RecordingStream, Mock* (simulation)
+tim/+acq               checkIntegrity, voltsToPascal
+tim/+dsp               sweepResponse, sineResponse, welchResponse, detectExcitation, estimateSweepLaw
+tim/+cal               switchingCorrection, buildCalibration, interpolateCalibration,
                        applyCalibration, resolveSensitivities, calibrationContext
+tim/+acoustics         airProperties, wavenumber, decomposeWaves, fieldAt, analyzeFourMic,
                        validityMasks, transferMatrix, frequencyLimits
+tim/+sim               SimulatedRig, tubeModel, lanxiEncode
+tim/+app               MeasurementSession, runCalibration, processMeasurement, plot*, save*, config
+tim/+val               hardware validation procedures (Tests A–E)
+tim/+gui               TubeApp (uifigure GUI), drawTube3D (3D tube model), Checklist, icon
+tim/+cad               readStep (STEP assembly reader used for the tube dimensions)
tests/                  matlab.unittest suites + fixtures (real LAN-XI responses and stream)
examples/               demo_simulation.m, hardware_commissioning.m, output/ (example plots)
docs/                   see below
data/, calibration/     measurement and calibration output (never overwritten)
```

## Documentation

| Document | Content |
|---|---|
| `docs/installation_windows.md` | dependencies (none beyond MATLAB + toolboxes), network, verification, Git |
| `docs/user_guide.md` | configuration, safety, measurement, results, troubleshooting |
| `docs/calibration_procedure.md` | sensitivity layer and sensor-switching complex calibration |
| `docs/validation_procedure.md` | Tests A–G, criteria and tolerance rationale |
| `docs/theory.md` | conventions, derivations, estimators, frequency limits, validity levels |
| `docs/hardware_status.md` | verified vs pending, observations from the hardware sessions |
| `docs/assumptions_and_limitations.md` | assumptions, limitations, future work |
| `docs/ref_33220A_scpi.md`, `docs/ref_lanxi_openapi.md` | verified instrument protocol references |

## References

LAN-XI Open API user guide BE 1872; HBK `open-api-tutorials` (stream format, single-module
example) and `open-api-time-data-recorder` (MATLAB reference, MIT licence; used as a behavioural
reference, not copied); Agilent 33220A User's Guide 33220-90002; ISO 10534-2; ASTM E1050; ASTM E2611.
