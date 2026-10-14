# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

tubebench is a MATLAB R2022b program for broadband four-microphone transfer-impedance tube
measurements. A Keysight/Agilent 33220A generator drives the loudspeaker; four B&K 4957 microphones
record on an HBK LAN-XI 3676 through its Open API (HTTP REST + binary TCP stream). It needs only
MATLAB and the Signal Processing Toolbox. Every feature also runs without hardware in simulation
mode. The code is the package `+tim`, which kept its name when the program was renamed to
tubebench; the main window is `tim.gui.Tubebench`, started by `tubebench.m` /
`start_tubebench.bat` (the old names `tubeapp` and `tim.gui.TubeApp` were removed). README.md has
the package map and docs/ has the theory and procedures. Code, comments, UI text and docs are in English;
operator prompts exist in English and Korean (`tim.app.msg`).

## Commands

In MATLAB (`run_tests` and `tubebench` add the project root to the path themselves):

```matlab
results = run_tests();          % all tests (simulation + recorded LAN-XI fixtures); report -> tests/last_test_report.txt
results = run_tests('fast');    % without TestEndToEnd and the hidden-window app simulation
addpath(pwd); runtests('tests/TestDsp.m')                              % one test class
runtests('tests/TestGui.m', 'ProcedureName', 'openSavedMeasurement')   % one test
tubebench sim                   % window on the virtual tube (config/sim_thin_screen.json)
tubebench                       % window on the real instruments (config/user_config.json)
run examples/demo_simulation.m  % scripted workflow without the window (see also start_here.m)
```

When the MATLAB MCP server is connected, use its tools: `run_matlab_test_file`,
`evaluate_matlab_code`, and `check_matlab_code` for the Code Analyzer (there is no other lint
step). That session is the user's own visible MATLAB desktop, so leave the user's tubebench and
About windows open. Tests that count windows must count relative to the windows already open.

From PowerShell without MCP: the `matlab.exe` launcher returns at once, so wait for the process
and read the log. The log uses the Korean locale, so read it as UTF-8.

```powershell
$code = "r = run_tests('fast'); assertSuccess(r)"
$log  = "$env:TEMP\claude\tubebench_tests.log"
$p = Start-Process -FilePath "C:\Program Files\MATLAB\R2022b\bin\matlab.exe" -ArgumentList @('-sd', "`"$PWD`"", '-batch', "`"$code`"", '-logfile', "`"$log`"") -Wait -PassThru -WindowStyle Hidden
$p.ExitCode; Get-Content $log -Encoding UTF8
```

## Architecture

**Session layer.** `tim.app.MeasurementSession` owns the instruments (`s.Gen` signal source,
`s.Daq` acquisition; one object when a device takes both roles) and runs every acquisition. The
configuration names a driver per role (`generator.driver`, `daq.driver`: `keysight33220a`,
`lanxi`, `simcombined` for both, or the guide's simulation-only example `demo`); `connect` builds
them through the registry `tim.instr.create` (list in `+tim/+instr/drivers.m`). Drivers implement
the contract `tim.instr.SignalSource` / `tim.instr.Acquisition` (`docs/instrument_interface.md`),
so the session and the window name no instrument (a test greps for it). A new instrument gets a
driver by `docs/adding_an_instrument.md` (templates in `templates/instrument/`, checked by
`TestInstrumentTemplates`; skill `.claude/skills/add-instrument`), never by a change to the session
or the window. `cfg.mode` chooses what each driver talks to:

- `'hardware'`: its transport - `ScpiTcpTransport` (33220A); `LanXiHttp`, `LanXiTcpStream` →
  `LanXiStreamParser` (LAN-XI).
- `'simulation'`: its protocol mock (`MockScpiTransport`, `MockLanXiHttp`/`MockLanXiStream`) on
  one `tim.sim.SimulatedRig`, which reads the generator state from the SCPI mock and synthesises
  the four channels from an analytic tube model (`tim.sim.tubeModel`) plus a per-channel chain,
  noise and a clock offset. `tim.sim.SimulatedCombined` (`simcombined`) implements the contract
  directly on the rig (`respond(x)`): shared clock, planned block acquisition.

Everything above the drivers is the same in both modes. That is why the test suite exercises
the whole workflow, including the GUI, without hardware. The tests also replay real recorded
LAN-XI responses from `tests/fixtures`, and `TestBusTraffic` compares every SCPI / REST message of
a simulated session with recorded fixtures (regenerated only for an owner-approved change).

**No shared clock.** The generator and the LAN-XI are not synchronised. Every action is scheduled
on the number of samples received so far: output on, trigger, frequency step, output off (a
device that takes both roles runs the same schedule first as a planning pass on its own clock).
Only afterwards is it verified that the excitation lies inside the recording:

- `tim.dsp.detectExcitation`;
- for sweeps, the matched-filter "sweep gate" in `tim.dsp.sweepResponse`, which also excludes
  the generator's output-switching clicks. It needs the sweep to reach beyond the band
  (`tim.dsp.sweepGateLimits`, also used by `validateConfig`); an end without that margin gets
  another window edge (from the detected start, or a ring-down margin past the sweep end).

The analysis uses only the relative responses between channels.

**Processing pipeline.** `meas = session.measure()` → `res = tim.app.processMeasurement(meas, cfg, cal)`:

1. The relative responses Y_c/Y_ref are computed per excitation kind (`sweepResponse`,
   `sineResponse` for stepped sines, `welchResponse` for noise).
2. The complex switching calibration is applied (`tim.cal.*`; C_k = g_k/g_ref, from
   `tim.app.runCalibration`).
3. The columns are reordered from **DAQ channel to tube position** using `cfg.mics(c).position`
   (Reprocess of an opened measurement: the recorded mapping by default, `tim.app.useRecordedMapping`).
4. `tim.acoustics.analyzeFourMic` runs the wave decomposition and computes R, τ, TL, the transfer
   impedance and the validity masks. `tim.acoustics.transferMatrix` gives the two-port matrix;
   the two-load method (WO-005, Method "Two loads") measures load A, load B and load A again with
   operator prompts (`tim.app.runTwoLoad`: every load saved at once, then a pair folder) and
   combines them (`tim.app.processTwoLoad`: T, condQ with unit columns, anechoic and hard-backed
   values, the repeat check through T). The termination of every measurement is recorded
   (`MeasurementSession.setTermination`); in simulation the virtual rig gets it.

`meas` holds raw volts and is never modified. The axial coordinate x increases from the
loudspeaker towards the termination. The positions are ordered M1..M4, with M1 nearest the
loudspeaker. Unknown geometry is `NaN`, and the quantities that depend on it are disabled rather
than guessed. The default tube-loss model is `'kirchhoff'` (visco-thermal boundary layer);
`'iso10534'` and `'none'` are options. See `docs/theory.md`, including the recorded decision.

**One drawing code for the window and the saved figures.** Every graph is a `tim.plots.*` view
function. `tim.gui.ViewPage` shows it in the window (header + axes + summary table), and
`tim.app.plotResults` draws the same view into the saved figures. Titles and descriptions come
only from `tim.plots.viewText`. A change to a view therefore changes both outputs, and both are
tested (TestPlots*, TestGui).

**GUI.** `tim.gui.Tubebench` (one large class) is a thin layer over `MeasurementSession`; every
action is also available from scripts (`start_here.m`).

- It is built programmatically with uifigure components, not as an .mlapp file.
- Progressive start-up: `tim.gui.StartWindow` shows progress, and the main window appears after
  the control panel and Setup > Connection are built. A timer named `tubebench-build` then
  prepares the other views one by one.
- Background steps never run while `Busy` is set, while a session operation or stream is active,
  or while the window closes, because that would stall the LAN-XI stream.
- Code that touches a view must call `app.ensureBuilt(part)` first.
- No instrument selector (owner decision): the window shows the instruments in use from the
  drivers (`tim.instr.driverInfo`, `identity()`): lamp labels and tooltips, "In use", the
  Instruments table and checklist of Setup > Connection, texts (`describe().texts`) and the
  limits of the EXCITATION fields (`capabilities()`).
- A hidden window (`'Visible','off'`, as used by the tests) builds everything synchronously, and
  its prompts (`ask`, `askBar`) return the default answer. A Stop or close request during an
  action (also in a window without a session) makes them return the cancel answer.
- Connection check (1.2.1): the 33220A drops an idle socket silently (also with a static IP). The
  session calls the drivers' `checkConnection()` before every excitation: the 33220A driver
  replaces a connection idle for more than 30 s without sending on it, checks a newer one with
  `OUTP?`, and raises `tim:instr:connectionLost` before anything is armed when no new connection
  opens; a visible hardware window repeats it every 60 s while idle (`LinkTimer`,
  `checkConnectionNow`, never during an action).

**Calibration** (`tim.app.runCalibration`) is a sequence of operator steps. The microphones swap
ports through a `prompt` callback: in the GUI this is the operator bar, in a script the command
window, and in simulation the virtual rig moves them. The sequence ends with an empty-tube check
(Test E). See `docs/calibration_procedure.md`.

**Configuration.** `tim.app.loadConfig` merges a JSON file onto `tim.app.defaultConfig`:

- JSON `null` or a missing field keeps the default.
- Unknown fields raise a warning.
- Files of the old layout (`formatVersion` 1: `generator.host`, a `lanxi` section) and old
  scripts are read through `tim.app.migrateConfig`.
- `tim.app.validateConfig` checks the result; the selected drivers check their part
  (`checkConfig`).
- A new setting must be added to `defaultConfig` and, where relevant, to `validateConfig`; a
  driver's own setting goes into its `describe().defaults.settings` (sub-struct
  `generator.<driver>` / `daq.<driver>`).

The configuration files:

- `config/user_config.json` holds the lab settings and is tracked in git.
- `config/example_config.json` is a neutral template; never copy it over `user_config.json`.
- `config/sim_thin_screen.json` is the virtual tube.

**Provenance.** `tim.app.softwareVersion` returns the version and the git commit, and both are
stored with every measurement. When releasing, bump the version number and date in
`softwareVersion.m`. Uncommitted changes are not visible in the stored commit.

## Rules specific to this project

- **Safety and hardware.**
  - The generator output may be armed only inside `MeasurementSession.measure*()`. Every error
    path must switch the output off, stop the acquisition and keep the partial data. The output
    goes off first: the session sets the acquisition's `AbortFcn` to the source's `outputOff` at
    connect (D24), so a driver calls it before its own stop sequence.
  - Ask the user before raising excitation levels.
  - Do not change instrument IP addresses, firmware, drivers, firewall or licences without
    approval.
- **Data.**
  - Raw data are never overwritten. `tim.app.saveMeasurement` always writes a new
    `data/<yyyyMMdd_HHmmss>_<name>/` folder, and reprocessing a measurement saves a new folder.
  - `data/`, `calibration/**/*.mat` and `cad/` are git-ignored and must stay out of commits.
- **Verification status.**
  - Tests verify software behaviour in simulation, not physical accuracy.
  - `docs/hardware_status.md` separates software-verified from hardware-verified items. Never mark
    a hardware test (Tests A–G, `tim.val.*`) as passed without a real measurement.
- **Shared MATLAB session.**
  - Never call `exportapp`, `uiconfirm`, `uialert` or `waitfor` on invisible figures; they block
    MATLAB.
  - `exportapp` also mis-renders scrollable grids, so check layouts with real screen captures,
    never by clicking or typing on the user's screen.
- **R2022b uifigure limits.** `OuterPosition` cannot be set (Position excludes about 53 px of
  title and menu bar), and the window `Icon` needs a PNG, while `uiimage` can show an SVG.
- **Docs.**
  - Behaviour changes go into `docs/user_guide.md` (also opened by Help > User guide).
  - Analysis changes go into `docs/theory.md`.
  - A formula's source is cited as [n]. The reference list of `docs/theory.md` and section 13 of
    the Formula tab (`tim.gui.equationsPanel`) are the same text (`TestFormulaPanel` compares
    them), and every Formula section ends with its "Sources:" line, which also names the
    program's own choices.
  - The README states the test count.
  - Planned work for the next version is in `docs/workorder_*.md`.
- **Errors.** Error and warning identifiers use the `tim:<area>:<what>` form.
