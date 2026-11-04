<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="resources/logo/tubebench-mark-reverse.svg">
    <img src="resources/logo/tubebench-mark.svg" alt="tubebench logo" width="112">
  </picture>
</p>

<h1 align="center">tubebench</h1>

<p align="center">
  <strong>Four-microphone impedance-tube measurements in MATLAB</strong><br>
  transmission loss · reflection · transfer impedance · transfer matrix<br>
  <sub>by <a href="https://kimwoongji.github.io">Woongji Kim</a> ·
  <a href="https://kimwoongji.github.io/projects/tubebench.html">project page</a></sub>
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue" alt="License: MIT"></a>
  <img src="https://img.shields.io/badge/MATLAB-R2022b-e16737" alt="MATLAB R2022b">
  <img src="https://img.shields.io/badge/toolbox-Signal%20Processing-lightgrey" alt="Signal Processing Toolbox">
  <img src="https://img.shields.io/badge/version-1.5.0-informational" alt="Version 1.5.0">
  <img src="https://img.shields.io/badge/tests-386-brightgreen" alt="386 automated tests">
  <img src="https://img.shields.io/badge/method-ASTM%20E2611-555555" alt="ASTM E2611">
</p>

<p align="center">
  <a href="#quick-start">Quick start</a> ·
  <a href="#features">Features</a> ·
  <a href="docs/user_guide.md">User guide</a> ·
  <a href="docs/theory.md">Theory</a> ·
  <a href="#verification">Verification</a> ·
  <a href="#project-status">Status</a> ·
  <a href="#citing">Cite</a> ·
  <a href="https://kimwoongji.github.io/projects/tubebench.html">Project page</a>
</p>

---

Commercial four-microphone impedance-tube systems are expensive and tied to their vendor's
hardware, so many labs build their own tube. Run by hand across separate instruments and scripts,
settings drift, channels get swapped and calibrations stop matching the data: instrument control
is what turns a home-built tube into a measurement system.

**tubebench** drives a signal generator and a multichannel acquisition module, records four
microphones around a specimen in an impedance tube and computes the specimen's acoustic
properties after ASTM E2611, with a validity verdict for every frequency line. It includes a
complete virtual tube, so every feature, the window included, also runs without hardware. The
background, the verification and the principle are summarised on the
[project page](https://kimwoongji.github.io/projects/tubebench.html).

<p align="center">
  <img src="docs/images/tube_setup.png" alt="The tubebench window: Setup > Tube setup with the 3D model of the lab tube" width="100%">
  <br><sub>Setup › Tube setup: the 3D model follows the geometry entered in the window, and the analysis band
  follows the ASTM E1050 / E2611 limits of the tube (simulation mode).</sub>
</p>

## Features

- **One window for the whole workflow.** Connect → tube geometry → excitation → switching
  calibration → measurement → save. Every step has its own view (header, graphs, summary table),
  and the Formula tab shows every equation with its source.
- **Four-microphone analysis.** Wave decomposition; reflection and transmission coefficients,
  transmission loss, thin-element transfer impedance and the two-port transfer matrix. Visco-thermal
  tube losses (Kirchhoff) by default, ISO 10534-2 attenuation as an option.
- **Two-load transfer matrix (ASTM E2611).** The window guides the operator through load A, load B
  and load A again. The loads are chosen in the window (absorber, rigid cap or open end, at the tube
  end or the joint), and no anechoic termination is needed. It gives the transmission loss, the
  absorption with an anechoic and with a rigid backing, and the matrix itself, with the condition
  number of the loads and a check that nothing moved between them. For a front-to-back symmetric
  specimen, one load is enough.
- **Validity per frequency line.** Lines that the tube geometry, the calibration, the signal
  quality or the termination do not support are masked, and the program says why. The analysis
  band can follow the ASTM E1050 / E2611 limits of the tube geometry.
- **Three excitations.** Swept sine (log or linear), stepped sine and random noise.
- **No shared clock needed.** Generator and acquisition are not synchronised; every action is
  scheduled on the samples received, and a matched-filter sweep gate keeps the generator's
  switching clicks out of the analysis.
- **Guided switching calibration.** Twelve operator steps that swap the microphones, ending with
  an automatic empty-tube check.
- **Traceable data.** Raw volts are never modified or overwritten; every measurement stores its
  configuration, calibration, software version and git commit. Results export to CSV, figures to
  PNG, PDF, SVG or FIG.
- **Runs without hardware.** Protocol-level mocks of the instruments on an analytic tube model.
  The automated tests exercise the whole workflow, including the window, and replay recorded
  responses of a real LAN-XI module.
- **Pluggable instruments.** Drivers implement a small contract; templates and a Claude Code skill
  add a new instrument without changes to the session or the window.
- **Operator prompts in English and Korean.**

https://github.com/user-attachments/assets/815febda-de94-4d78-855e-cb60f887468e

<p align="center"><sub>Switching calibration on the virtual tube (pauses for the measurements shortened): the
microphones swap between the calibration ports M1 (a) and M2 (b), each one staying on its own cable and
input channel; the empty-tube check (Test E) closes the sequence.</sub></p>

## Quick start

**Requirements:** MATLAB R2022b with the Signal Processing Toolbox (nothing else; tested on
Windows). Instrument communication uses base MATLAB (TCP, HTTP).

```bash
git clone https://github.com/kimwoongji/tubebench.git
```

Try it without hardware, in MATLAB from the `tubebench` folder:

```matlab
tubebench sim                    % the window on a virtual tube
```

| Command | What it does |
|---|---|
| `tubebench` | the window on the real instruments (`config/user_config.json`) |
| `results = run_tests();` | self-test in simulation, report in `tests/last_test_report.txt` |
| `edit start_here.m` | the workflow as a script, step by step, without the window |
| `run examples/demo_simulation.m` | full simulated workflow with example plots |

On Windows, **`start_tubebench.bat`** starts MATLAB without its desktop and opens the window
(`start_tubebench.bat sim` for the virtual tube). The [user guide](docs/user_guide.md), also in the
window under Help > User guide, describes every control and view.

**Configuration.** [`config/user_config.json`](config/user_config.json) holds the settings of the
author's lab (instrument addresses, limits, microphones, tube geometry); it is tracked in git as a
working example. [`config/example_config.json`](config/example_config.json) is a neutral template.
The window saves the configuration under File > Save configuration…. Commit code and configuration
before measuring: the commit stored with a measurement does not see uncommitted changes.

## How it works

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/images/measurement_chain-dark.svg">
    <img src="docs/images/measurement_chain.svg" alt="Measurement chain: tubebench drives the signal generator over SCPI, the amplifier drives the loudspeaker of the tube, four microphones M1-M4 around the specimen feed the LAN-XI module, which streams to tubebench" width="100%">
  </picture>
</p>

`meas = session.measure()` records raw volts; `res = tim.app.processMeasurement(meas, cfg, cal)`
then

1. computes the relative responses between the channels for the excitation used (sweep
   deconvolution, stepped-sine estimates or Welch averaging);
2. applies the complex switching calibration;
3. maps the acquisition channels to the tube positions M1..M4;
4. decomposes the waves and computes R, τ, TL, the transfer impedance and the validity masks.

With two loads, every load is processed this way and saved as a measurement of its own.
`tl = tim.app.processTwoLoad(loads, cfg)` then computes the transfer matrix T of the specimen from
the loads, and `tim.app.runTwoLoad` runs the whole sequence from a script.

**Choosing the method** (Method in the window's MEASUREMENT section):

| Method | Termination | Result | Saved as |
|---|---|---|---|
| One load | anechoic in the band (\|R_term\| ≤ 0.1); elsewhere τ and TL are masked | R, τ, TL, Z_t | `<time>_oneload_<signal>_<specimen>` |
| One load, symmetric | any | T, assuming a front-to-back symmetric, reciprocal specimen | `<time>_oneload-symmetric_<signal>_<specimen>` |
| Two loads (ASTM E2611) | two different terminations, A and B (A again at the end) | T: TL, absorption with an anechoic or a rigid backing, Z_t | one folder per load and a pair folder `<time>_twoload_<specimen>` |

A short absorber is anechoic only at high frequencies: in the author's tube its reflection
falls below 0.1 only above about 3 kHz. Two loads remove that limit. An empty specimen section
cannot show the difference: air has no reflection of its own, so its TL is near 0 dB with any
termination. A reflecting specimen does (see [Verification](#verification)).

The derivations, estimators, frequency limits and validity levels are in
[docs/theory.md](docs/theory.md).

## Verification

To check the whole chain against an independent reference, a 3D-printed resonator cell was
measured on the same mount with one load and with two loads (absorber at the tube end, then a rigid
cap at the joint, then the absorber again; 2026-11-02) and compared with a 3D finite-element model
with thermoviscous losses.

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/images/verification_tl-dark.svg">
    <img src="docs/images/verification_tl.svg" alt="Transmission loss of a 3D-printed resonator cell from 118 Hz to 4.7 kHz: two-load measurement, one-load measurement and 3D finite-element simulation, with a close-up of the first resonance between 250 and 550 Hz" width="100%">
  </picture>
  <br><sub>Transmission loss of the cell: (a) over the tube's band, (b) around the first resonance
  (shaded in a).</sub>
</p>

- **Two loads follow the simulation:** 377 Hz and 12.9 dB at the first resonance against 377 Hz
  and 13.4 dB; the other resonances lie within 3 % of the simulated frequencies, up to 2.4 dB lower
  above 2 kHz.
- **One load is biased by the termination:** with the absorbing end alone (|R_term| ≈ 0.5 near
  400 Hz) the transmission coefficient peaks at 371 Hz and 11.0 dB, and tubebench masks τ and TL on
  every line, because the end is not anechoic. The two-load transfer matrix removes that
  dependence.
- **Nothing moved:** the repeat of the first load reproduced the transfer matrix to 3 % (median);
  1929 of 2301 frequency lines are valid in both loads.

Details and the open checks are in [docs/hardware_status.md](docs/hardware_status.md).

## Supported instruments

The configuration names a driver for each role (`generator.driver`, `daq.driver`). The window
has no instrument selector; it shows the instruments in use with the model, serial number and
firmware they report.

| Driver | Role | Instrument | Mode |
|---|---|---|---|
| `keysight33220a` | signal source | Keysight/Agilent 33220A (SCPI over TCP) | hardware and simulation |
| `lanxi` | acquisition | HBK LAN-XI Light 3676 (Open API) | hardware and simulation |
| `simcombined` | both | simulated device: one output and four inputs on one clock | simulation |
| `demo` | signal source | the worked example of the driver guide | simulation |

**Adding an instrument:** write a driver that follows the contract in
[docs/instrument_interface.md](docs/instrument_interface.md). The step-by-step procedure is
[docs/adding_an_instrument.md](docs/adding_an_instrument.md), with starting files in
[`templates/instrument/`](templates/instrument); in [Claude Code](https://claude.com/claude-code)
the skill `/add-instrument` runs the procedure.

## Project status

Version **1.5.0** (2026-11-04); the changes of every version are in [CHANGELOG.md](CHANGELOG.md).
The automated tests verify the software's behaviour, not physical accuracy;
[docs/hardware_status.md](docs/hardware_status.md) lists what has been verified on the real
instruments.

| Area | Status |
|---|---|
| Software | ✅ complete; 386 automated tests in 25 classes (simulation and recorded hardware fixtures) |
| Instrument communication: 33220A SCPI, LAN-XI REST, recorder cycle, binary stream, TEDS | ✅ verified on the instruments |
| Swept-sine measurements in the tube, sine excitation on the bench, microphone chain, switching calibration with its empty-tube check, measurement workflow in the window | ✅ done on the instruments (2026-10-08 to 2026-10-12) |
| Instrument interface (1.2.0), connection check (1.2.1), generator load at the amplifier input (1.3.0) | ✅ owner's hardware checks passed (2026-10-12 / 2026-10-13) |
| Two-load transfer matrix in the window (1.4.0) | ✅ verified on the instruments against a 3D finite-element model (resonator cell, 2026-11-02; [Verification](#verification)); the empty-section checks of the work order were not repeated |
| Noise excitation on the instrument, channel-to-port identification, formal validation (Tests A–G) | ⏳ pending |
| Tube geometry of the lab configuration | ⏳ CAD design values; caliper check pending |

Until 2026-10-10 the program was called `transfer-impedance-tube-measurement`; measurements saved
before then carry that name.

## Documentation

| Document | Content |
|---|---|
| [User guide](docs/user_guide.md) | the window, workflow, views, menus, safety, configuration, scripts, results, stored data, troubleshooting |
| [Installation (Windows)](docs/installation_windows.md) | dependencies, network, verification, git |
| [Calibration procedure](docs/calibration_procedure.md) | sensitivity and switching calibration, empty-tube check |
| [Validation procedure](docs/validation_procedure.md) | Tests A–G, criteria and tolerance rationale |
| [Theory](docs/theory.md) | conventions, derivations, estimators, frequency limits, validity levels, references |
| [Hardware status](docs/hardware_status.md) | verified vs pending, observations from the hardware sessions |
| [Assumptions and limitations](docs/assumptions_and_limitations.md) | assumptions, limitations, future work |
| [Instrument interface](docs/instrument_interface.md) | the driver contract, as built |
| [Adding an instrument](docs/adding_an_instrument.md) | a new driver step by step; worked example [demo source](docs/ref_demo_source.md) |
| [33220A SCPI](docs/ref_33220A_scpi.md), [LAN-XI Open API](docs/ref_lanxi_openapi.md) | verified instrument protocol references |

<details>
<summary><strong>Repository layout</strong></summary>

The code is the MATLAB package `+tim` (tim = transfer-impedance measurement; it kept its name when
the program was renamed). The main window is the class `tim.gui.Tubebench`.

```
start_here.m            entry point (sections)        run_tests.m   automated tests
tubebench.m, start_tubebench.bat   start the window          LICENSE   MIT
CHANGELOG.md            changes per version           CITATION.cff  how to cite
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
+tim/+app               MeasurementSession, runCalibration, processMeasurement, useRecordedMapping,
                        analysisBand, driveEstimate, plotResults (saved figures), plotCalibration,
                        save* / export*, measurementName (folder names), loadConfig / saveConfig /
                        defaultConfig / validateConfig / migrateConfig, outputGuard, msg (prompts
                        en / ko), softwareVersion; two loads: describeLoad, terminationModel,
                        runTwoLoad, processTwoLoad, saveTwoLoad, loadTwoLoad, peakLevel
+tim/+plots             the views, shared by the window and the saved figures: timeSignals,
                        spectrum, transferFunctions, reflection, transmissionLoss,
                        transferImpedance, validity, calibration, twoLoad, transferMatrix;
                        house style and helpers:
                        style, fitAxes, legend, masked, bandValues, octaveBands, dataTitle,
                        emptyState, thickSpecimen, viewText (titles and descriptions)
+tim/+gui               Tubebench (uifigure window; names no instrument: lamps, checklist,
                        texts, identity display and field limits come from the drivers),
                        ViewPage (header + graphs + summary of a view),
                        drawTube3D (3D tube model), calSwapPath (rounded microphone-swap
                        paths of the Calibration view), equationsPanel (Formula tab), Checklist,
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
                        device; identity display); TestSessionHardwareMode (the hardware-only
                        session branches on test-only drivers, no I/O); support/ (test-only drivers)
templates/instrument    starting files for a new driver (source, acquisition, combined device,
                        their protocol mocks and tests, reference document, configuration
                        snippets); not on the path (docs/adding_an_instrument.md)
.claude/skills          add-instrument: the Claude Code skill that runs the driver guide
examples/               demo_simulation.m, hardware_commissioning.m, bench_test_no_tube.m,
                        output/ (example plots)
docs/                   documentation (see above); workorder_*.md: planned work; images/: the
                        figures of this README
data/, calibration/     measurement and calibration output (never overwritten; not in git)
```

</details>

## Citing

If tubebench helps your work, please cite it (GitHub's "Cite this repository" reads
[CITATION.cff](CITATION.cff)):

```bibtex
@software{kim_tubebench,
  author  = {Kim, Woongji},
  title   = {tubebench: four-microphone impedance-tube measurements in MATLAB},
  year    = {2026},
  version = {1.5.0},
  url     = {https://github.com/kimwoongji/tubebench},
  license = {MIT}
}
```

## Author

tubebench is developed by **Woongji Kim**. The
[project page](https://kimwoongji.github.io/projects/tubebench.html) tells why it was built and how
it was verified; an earlier two-microphone tube is on the
[hardware page](https://kimwoongji.github.io/projects/hardware.html). Other projects, publications
and the CV are at **[kimwoongji.github.io](https://kimwoongji.github.io)**.

## References

ASTM E2611; ASTM E1050; ISO 10534-2; LAN-XI Open API user guide BE 1872; HBK
`open-api-tutorials` (stream format, single-module example) and `open-api-time-data-recorder`
(MATLAB reference, MIT licence; used as a behavioural reference, not copied); Agilent 33220A User's
Guide 33220-90002. The sources of every formula are listed in [docs/theory.md](docs/theory.md)
(References) and in the Formula tab of the window.

## License

[MIT](LICENSE) © 2026 Woongji Kim.

The software is provided "as is", without warranty of any kind. It drives a loudspeaker through
real instruments: keep the level limits of the configuration and check every new set-up in
simulation first ([user guide](docs/user_guide.md), section 3).

## Author

**Woongji Kim** · <https://kimwoongji.github.io>
