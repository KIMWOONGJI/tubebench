# Changelog

All notable changes to tubebench. Every measurement stores the version and the git commit that
made it (`tim.app.softwareVersion`); the commit given for each version is the commit on `main`
that released it. Releases on GitHub start with v1.4.2; earlier versions have no tag. Hardware
verification is tracked separately in [docs/hardware_status.md](docs/hardware_status.md): the
automated tests verify the software's behaviour, not physical accuracy.

## 1.5.1 - 2026-11-04 (`29504e1`)

### Added
- EXCITATION: a **Settle [cycles] / Measure [cycles]** row for the stepped sine (greyed for the
  swept sine). The tooltips give the resulting times at the first and the last step, the Duration
  estimate follows, and fewer than 4 measured cycles per block are marked. The section bars (22 px)
  and the spacers (3 px) are thinner, so the control panel stays within 930 px.
- Lines outside the frequency range of the calibration (a stepped-sine step outside the analysis
  band) get a value: they are corrected with the factor of the nearest calibrated line, flagged
  `outsideCalibration` and never valid. The stepped-sine views draw them as hollow diamonds with a
  legend entry; Validity has the row and `results.csv` the column. Before, they had no value.

### Changed
- The stepped-sine timing is given in cycles everywhere (tooltips, Formula tab, documents).
## 1.5.0 - 2026-11-04 (`5744c89`)

### Changed
- Stepped sine: every step settles max(`settleTime`, `settleCycles`/f) after its frequency change
  and records max(`recordTime`, `recordCycles`/f) (`tim.app.steppedPlan`), so low frequencies get
  more periods and high ones no more than the minimum time. Defaults and the shipped configuration
  files: 0.2 s / 50 periods and 0.2 s / 100 periods (1.25 s at 120 Hz, 0.4 s from 500 Hz up; 40
  steps take 22 s instead of 33 s). Configurations without the cycles keep fixed times; saved
  stepped measurements reprocess as before. The constants are a starting point until the decay of
  the tube is measured (docs/theory.md section 5).
- The window's Duration estimate, the Number-of-steps tooltip and the Formula tab (1b) follow the
  per-step timing.

### Added
- Work order WO-006 (proposal): a level equalizer for the stepped sine (docs/workorder_equalizer.md).

## 1.4.2 - 2026-11-03 (`7955545`)

### Changed
- Setup > Tube setup: with two loads the 3D model draws load A at first, then the load whose kind
  or place was changed last in Termination. The separate Show selector is removed.

## 1.4.1 - 2026-10-30 (`a70b53b`)

### Changed
- The Amplifier list cannot be typed in, like Signal; further models come from
  `amplifier.knownModels` of the configuration.
- The Amplifier list is fixed while connected: its input impedance is the generator's load
  setting, which is sent at Connect. The amplifier gain stays editable.

### Removed
- The window no longer remembers the two-load terminations between sessions; it starts with the
  loads of the configuration.

## 1.4.0 - 2026-10-14 (`beb10b1`)

### Added
- Two-load transfer matrix (ASTM E2611) in the window: Method "Two loads" guides the operator
  through load A, load B and load A again; every load is saved at once, then a pair folder with
  the transfer matrix, the condition number of the loads, the anechoic and the hard-backed
  results and the check that nothing moved between the loads.
- Method "One load, symmetric": the transfer matrix from one load, for a front-to-back symmetric,
  reciprocal specimen (an assumption, stated in every view).
- Terminations chosen in Setup > Tube setup (absorber, rigid cap or open end, at the tube end or
  the joint); every measurement records its termination.
- Time signals shown while a load is measured; a question before a two-load run without a
  calibration.

### Changed
- Folder names start with the method: `<timestamp>_oneload_…`, `…_oneload-symmetric_…`,
  `…_twoload…`.

## 1.3.2 - 2026-10-13 (`046dc67`)

### Added
- `analysis.bandMode` `'geometry'`: the analysis band from the ASTM E1050 / E2611 limits of the
  tube (spacings, diameter, temperature). The window names the standard and the source of the
  band.
- MIT licence, also shown in Help > About.

## 1.3.1 - 2026-10-13 (`3a3e4fd`)

### Changed
- Sweep gate: when a sweep has no margin at its start, the window ramp lies before the start.
- Reprocess: the microphone-mapping question names the mapping of the saved results.

## 1.3.0 - 2026-10-13 (`96a3c3f`)

### Added
- Excitation drive chain: the amplifier's input impedance is set as the generator load and read
  back; the loudspeaker drive is checked against its power limit at the nominal impedance (two
  meters: OK, near the limit, refused); the amplifier gain is entered as a factor.
- Role names in the window (Generator, DAQ); the products appear in "In use", the tooltips and the
  Instruments table.

### Fixed
- The signal-source template checks the open-circuit level.

## 1.2.1 - 2026-10-12 (`917d8f9`)

### Added
- Connection check before every excitation and every 60 s while idle. The 33220A drops an idle
  connection silently: a connection idle for more than 30 s is replaced, a newer one is checked
  with `OUTP?`, and the measurement stops with `tim:instr:connectionLost` before anything is
  armed when no connection opens.
- EXCITATION controls: amplifier gain, generator load, loudspeaker row, level entered at the
  generator or at the loudspeaker.
- Calibration view: rounded microphone-swap paths.

## 1.2.0 - 2026-10-12 (`e9039b7`)

### Added
- Instrument interface: the contracts `tim.instr.SignalSource` and `tim.instr.Acquisition`, a
  driver registry (`generator.driver`, `daq.driver`) and contract tests over every driver;
  configuration `formatVersion` 2 (files of the old layout are migrated).
- Guide, templates and a Claude Code skill for adding an instrument; a simulated combined device
  (`simcombined`) and a simulation-only `demo` driver.
- Bus-traffic regression tests against recorded fixtures.
- Formula tab and theory: the sources of every section and a numbered reference list.

### Changed
- Safety: the output switches off before the acquisition stops on every error path, and an
  interrupt (Ctrl+C) switches the output off.
- Swept-sine lines are symmetric about their frequency (saved sweep results change slightly when
  reprocessed).
- Sweep gate: an end without the margin gets another window edge.
- Reprocess uses the recorded microphone mapping by default.

### Fixed
- 43 findings of a whole-code audit: sessions and drivers keep the data and stay safe at a failed
  start, between repetitions, on Stop and on close; configuration round trip; reprocessing reports;
  opened results drawn as saved.

## 1.1.0 - 2026-10-09 (`e8fb4fb`)

### Added
- The window (`tim.gui.Tubebench`): control panel, Setup, Calibration, Measurement, Results and
  Formula views, 3D tube model, connection checklist, File > Open measurement and Reprocess; a start
  window with progress and a progressive start-up.
- Switching calibration with the empty specimen section and the automatic empty-tube check
  (Test E); an operator bar and animated microphone moves in the Calibration view.
- Sweep gate: the generator's output-switching transients are excluded from the analysis.
- Stepped sine: step levels and markers at the step frequencies.

### Changed
- The program is named tubebench (formerly transfer-impedance-tube-measurement); the package stays
  `+tim`, and the window class is `tim.gui.Tubebench`.
- Default tube-loss model `'kirchhoff'` (visco-thermal boundary layer); `'iso10534'` stays
  available.

## 1.0.0 - 2026-10-08 (`dc41afd`)

- Initial version: four-microphone transfer-impedance tube measurement with the Keysight/Agilent
  33220A and the HBK LAN-XI 3676, the analysis, the virtual tube and the tests.

