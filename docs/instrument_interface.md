# Instrument interface (contract)

| | |
|---|---|
| Work order | WO-001 Part 1 (`docs/workorder_instrument_interface.md`; its §0 decides over older text) |
| Status | **Implemented (as built), 2026-10-11** on `wo-001`: designed in stage 1, revised after the design review (stage 2: 24 issues, resolutions in section 13.2), implemented in stages A, B and C (section 14): contract classes, both drivers, registry, `tests/TestInstrumentContract.m`; configuration `formatVersion` 2, the session through the registry, metadata and the calibration's DAQ chain, `simcombined`; the window from the drivers with the identity display (section 7.1). Part 2 (stage 6, section 14): the guide `docs/adding_an_instrument.md`, the templates `templates/instrument/` (tested by `tests/TestInstrumentTemplates.m`), the skill `.claude/skills/add-instrument/`, and the demo source `demo` made by following the guide. Fix stage after the review of the implementation (2026-10-11): loading only warns about driver limits, 0 V after the stop on every end of a combined device, block size from the driver in the contract cases, closing during connect / prepare, NI guidance (section 13.3). **Hardware-verified on 2026-10-12**: the owner's hardware check (WO §0.3, ten steps in `docs/hardware_status.md`) passed; merged into `main` as 1.2.0. Owner decisions of 2026-10-11 (section 13.4): D7, D8, D24, D43, D45 and two changes of the bus order approved; the session sets `AbortFcn` (D24) and the fault fixture is regenerated from the code. |
| Applies to | `tim.app.MeasurementSession`, `tim.gui.Tubebench`, `+tim/+app`, `+tim/+cal`, `+tim/+val`, the drivers in `+tim/+instr` and `+tim/+sim` |

This document is the contract between the measurement program and an instrument driver. A
driver that follows it can be selected in the configuration without any change to the session,
the window, the configuration code or the tests. It is written for a person who adds a driver
(with or without Claude Code); `docs/adding_an_instrument.md` (WO-001 Part 2) gives the
step-by-step procedure, `templates/instrument/` the starting files.

Units throughout: frequencies in Hz, times in s, sample counts per channel, sample rates in S/s,
generator amplitudes in **Vpp as programmed** (see `generator.load`; a source programmed in
full-scale units converts with its measured `vppAtFullScale`, section 3.4), input data in **volts
at the input** (no sensitivity applied; full-scale units only for an input whose scale is
unknown, section 4.2).

## 1. Roles and objects

The measurement needs two roles:

* **SignalSource** - drives the loudspeaker (today: Keysight/Agilent 33220A);
* **Acquisition** - records the four microphones simultaneously (today: HBK LAN-XI 3676).

**One object may take both roles** (WO-001 §0 change B): a DAQ card with an analog output or an
audio interface is one device, with output and inputs on one sample clock. The session then holds
the same object as `s.Gen` and `s.Daq`.

```
tim.instr.Instrument            (abstract handle)   members common to both roles
├── tim.instr.SignalSource      (abstract)          output role
│     ├── tim.instr.Keysight33220A                  driver 'keysight33220a'
│     └── tim.instr.DemoSource                      driver 'demo' (worked example of the guide,
│                                                   simulation only)
├── tim.instr.Acquisition       (abstract)          input role
│     └── tim.instr.LanXi                           driver 'lanxi'
└── tim.sim.SimulatedCombined   < tim.instr.SignalSource & tim.instr.Acquisition
                                                    driver 'simcombined' (both roles, shared clock,
                                                    block acquisition, simulation only)
```

Every member that both roles share is defined **only in `tim.instr.Instrument`**. MATLAB then
accepts a class that inherits from both role classes (the common base resolves the "diamond";
checked on R2022b with prototypes: abstract static methods, `isa` for both roles, protected
properties of the base set by the subclass, a static `fromConfig` next to an instance `create`).

Life cycle, as the session uses it:

```
src = tim.instr.create('source', cfg, ctx)            % connect, identify, output OFF
acq = tim.instr.create('acquisition', cfg, ctx, src)  % connect, identify, idle (src itself if combined)
acq.AbortFcn = @() src.outputOff()                    % abnormal end of acquire: output off first (8.1, D24)
acq.prepare(c)                                        % channels, range, CCLD, TEDS -> ready
src.configureSweep(s) ... src.armOutput(true)
[data, info] = acq.acquire(n, @onBlock)               % onBlock switches the output on / off
src.armOutput(false)
src.close(); acq.close()                              % output off, idle, released (idempotent)
```

There are two kinds of timing (section 8). **Data-driven**: the acquisition calls `onBlock` as data
arrive and the source acts at once - every pair of separate devices, e.g. 33220A + LAN-XI.
**Planned**: only when **one object takes both roles** on a shared clock, the schedule is first
planned on the device timeline and then played and recorded. Whether a plan is used is a property
of the source / acquisition pair, not of the acquisition driver alone (D16).

## 2. Members common to both roles (`tim.instr.Instrument`)

### 2.1 Class-level (static) members - available before connecting

The window builds its checklist and lamps, `validateConfig` checks the settings and the drive
estimate needs the source impedance **before** anything is connected; therefore these members
are static and must not do any I/O.

| Member | Returns / does |
|---|---|
| `d = describe()` | `name` (registry name, lower case, = `generator.driver` / `daq.driver`); `displayName` (e.g. `'Keysight/Agilent 33220A function generator'`, shown in the window and stored in the metadata); `labels` (struct, one short lamp label per role: the role as the operator calls it, never the product, which the "In use" line shows - `source: 'Generator'`, `acquisition: 'DAQ'`; a device in both roles may name its parts, `'Output'` / `'Inputs'`; owner, 2026-10-13); `defaults.settings` (default driver settings = the sub-struct `generator.<name>` / `daq.<name>`); `defaults.acquisition` (acquisition drivers: the values `acquisition.sampleRate`, `range`, `filter` and `ccld` take when the configuration leaves them empty, section 9.2); `texts.settle` (what the settling step after `prepare` waits for, `sprintf` format with the filter, e.g. `'CCLD + %s high-pass'`; `''` = no settling needed); `texts.noun` (the instrument in a sentence of the window, lower case unless a name or abbreviation, the role rather than the product: `'generator'`, `'DAQ'`, `'simulated device'`); `texts.closed` (the state `close()` leaves it in, read after the noun: `'output off'`, `'back to Idle'`, `'stopped, output at 0 V'`) - section 7.1; `simulation` (`'protocol'`: real driver that runs on its protocol mock in simulation mode; `'only'`: a driver without a real instrument - the contract-level `simcombined`, the guide's demo source on its own mock -, simulation mode only) |
| `c = capabilities()` | section 5 (roles, shared clock, pairing, products, source and acquisition limits) |
| `s = connectionSteps()` | struct array `key`, `label` (a short lower-case phrase without the role: the window shows it after the lamp label of its role, "DAQ: open recorder"; the connect step names the model and interface, `'connect (33220A, SCPI)'`), `role` (`'source'`, `'acquisition'` or `'both'`), `phase` (`'connect'`: reported by `fromConfig`; `'prepare'`: reported by `prepare`) - section 6 |
| `report = checkConfig(cfg)` | validates the driver's part of the configuration (its sub-struct and the role settings it constrains, section 9.2); errors `tim:config:*`, returns warnings (cellstr) |
| `obj = fromConfig(cfg, ctx)` | factory used only by `tim.instr.create`: builds the transport (hardware) or the protocol mock (simulation, on `ctx.rig`), connects, identifies, puts the instrument in its safe state (section 3.1); reports its `'connect'` steps through `ctx.progress`. Named `fromConfig` because MATLAB rejects a static `create` next to the LAN-XI driver's instance method `create` (= `PUT /rest/rec/create`), D20. |
| `h = testHooks(obj)` | simulation only: function handles into the driver's protocol mock with which the contract tests observe the safety duties (section 11.3); `tim:instr:noHooks` for an object that does not run on its mock |
| `checkInstalled()` (optional) | hardware mode only, called by the registry before any I/O: support packages and vendor runtimes that the product check cannot see (the NI-DAQmx support package and runtime, the ASIO driver `audioPlayerRecorder` needs on Windows); raises `tim:instr:missingProduct` naming what is missing and the driver |

`ctx` fields: `mode` (`'simulation'`/`'hardware'`), `rig` (`tim.sim.SimulatedRig` in simulation,
`[]` otherwise), `progress` (`@(key, state, detail)`), `roles` (the roles this object takes),
`settings` (the driver settings: the configured sub-struct merged onto `describe().defaults.settings`
by the registry, section 9).

### 2.2 Instance members

| Member | Returns / does |
|---|---|
| `id = identity()` | what the instrument reported about itself when it was created (no I/O): `vendor`, `model`, `serial`, `firmware` (char, `''` when unknown), `raw` (its own text, e.g. the `*IDN?` reply). Shown in the window, stored in the metadata. |
| `md = metadata()` | JSON-encodable struct stored with every measurement (section 7): at least `driver`, `displayName`, `roles`, `identity`, `sharedClock`, the driver settings in use; plus driver-specific state |
| `setTimeout(t)` | shortens the I/O time-out to `t` s (used when the window closes: `close(true)` must never wait long for a switched-off instrument). Default: no-op. |
| `r = checkConnection()` | (1.2.1, WO-003) the connection still works: called by the session before every excitation (`measure*`, so also before every calibration sweep) and by the window every 60 s while it is idle in hardware mode. `r.state` `'ok'`, `'reopened'` (an idle connection replaced as a precaution; not logged) or `'reconnected'` (a dropped connection found and replaced; the session logs "<Noun>: <detail>."), `r.detail`; raises `tim:instr:connectionLost` when the connection is lost and cannot be re-opened - nothing may then be armed. **Default: `'ok'` without I/O** (no bus traffic). A driver whose instrument can drop an idle connection unnoticed overrides it: a new connection to the same instrument (the same serial number), back in the safe state (output off, the load setting again), never armed - instead of a connection that has been idle too long, and after a short query failed. The 33220A does so (hardware check 2026-10-12: it drops an idle socket silently, also with a static IP; a connection idle for more than `ReopenAfterIdle_s` = 30 s is replaced without anything being sent on it, a newer one is checked with `OUTP?`, 2 s time-out; on the protocol mock only the check runs). |
| `close()` | safe state and release: source - disarm, output off (section 3.1, read-back not required), local, release; acquisition - stop, return to idle, release. **Never throws, idempotent: a second `close()` sends nothing.** Afterwards nothing is sent any more: a method that needs the instrument raises an error (`tim:instr:closed`, or the transport's own, e.g. `tim:scpi:closed`; a refusal such as `tim:gen:notArmed` may come first); `outputOff`, `close` and `setTimeout` return quietly; members without I/O (`identity`, `metadata`, `collect`, `recent`, `rawBytes`, `isAcquiring`, `isPlanning`) keep working, so partial data stay available. |
| `delete()` | **not** defined in the base class (MATLAB runs a base-class destructor after the subclass's, which would close twice and repeat I/O, D20). A driver's own `delete` leaves the device safe with as little I/O as possible: a source switches its output off (33220A: `close`), an acquisition stops a running acquisition (LAN-XI: stops the stream and keeps the recorder state, no further requests). |
| `ProgressFcn` | `@(key, state, detail)` for the connection checklist (section 6) |

**Re-entrancy.** `outputOff`, `close` and `setTimeout` may be called at any time, also
re-entrantly on the same object from a callback that runs inside one of its own methods:
`onBlock`, or a window callback (Stop, closing the window) that MATLAB runs during a `pause` or
`drawnow` inside a driver method (e.g. the LAN-XI state polling). A driver holds no lock while it
calls a callback. `close()` during `acquire`: section 4.

## 3. SignalSource (`tim.instr.SignalSource`)

Property (read-only): `OutputArmed` (logical, set by `armOutput`). Optional, driver-specific and
not used by the session or the window (D21): the 33220A keeps `MaxVpp`, `Load`, `Mode`,
`SweepSettings` and `Identity`.

### 3.1 Output off

"Output off" means: **no waveform, the output at 0 V or disconnected**. A relay output (33220A
`OUTP OFF`) meets it at once. A sample-producing output (DAQ analog output, audio interface)
does not: after `stop` or `release` an NI analog output channel can keep its last value (the
NI-DAQmx default for most devices; DSA devices follow their idle-output setting), i.e. a DC level
on the voice coil. Such a driver therefore

* writes 0 V to each output channel first in `fromConfig`;
* ends every plan with a fade to exactly 0 V (5 ms raised cosine) followed by zeros;
* in `outputOff`, `close`, `delete` and on every error or Stop path writes 0 V to each output
  channel after stopping and before releasing - also when the device failed while it played (a
  stall or time-out fails the rest of the fade as well): the fade, the stop and the 0 V write are
  separate steps, each one tried even when the one before failed (`TemplateCombined.endOutput`).
  The device session's 0 V write must therefore work after a stop.

### 3.2 Methods

| Method | Contract |
|---|---|
| `configureSine(f, vpp)` | continuous sine `f` [Hz], `vpp` [Vpp] (section 3.3). Output OFF first; level checked (section 3.4) **before** any level is sent; settings read back where the instrument allows. |
| `setFrequency(f)` | new sine frequency, phase-continuous where possible, output state unchanged. Only in sine mode (`tim:gen:mode`). |
| `configureSweep(s)` | single sweep (section 3.3): `s.fStart`, `s.fStop` [Hz], `s.duration` [s] within `capabilities.source.sweepTime`, `s.spacing` `'LOG'|'LIN'`, `s.amplitudeVpp` [Vpp], started later by `triggerSweep`. Output OFF; level checked first; read back. Invalid settings: `tim:gen:sweep`. |
| `configureNoise(vpp)` | broadband noise (section 3.3). Output OFF; level checked first. |
| `armOutput(tf)` | permission set by the session only after the operator started a measurement; `false` also switches the output off. |
| `outputOn()` | refused unless armed (`tim:gen:notArmed`) and configured (`tim:gen:mode`); re-checks the programmed level against the limit right before enabling (`tim:gen:amplitude`). |
| `outputOff()` | output off (section 3.1). **Never throws** (a failure is a warning), idempotent, allowed in every state, re-entrant (section 2.2), also during a planning pass or its execution (section 8.3). |
| `tf = isOutputOn(timeout)` | the output state, of the kind `capabilities.source.readback` declares: **`'instrument'`** - an instrument query (33220A `OUTP?`), never a cached flag; throws if there is no answer; **`'device'`** - the state of the device session that produces the signal (task not running and 0 V written, or audio stream stopped); allowed only for a shared-clock combined device; **`'none'`** - the instrument cannot report its state: returns the last commanded state, which a caller must never present as confirmed. `timeout` [s] optional. |
| `triggerSweep()` | starts the configured sweep now (bus trigger, software start or the shared clock, `capabilities.source.trigger`). Only in sweep mode (`tim:gen:mode`). |
| `tf = waitComplete(timeout)` | `true` when the sweep has finished; **never `true` before the sweep has ended** (it may be time-based from the trigger, e.g. for a generator whose `*OPC?` is not documented to wait for the end of a sweep); waits up to `timeout` s. |
| `setAmplitude(vpp)` | **optional** (1.6.0, WO-006; declared by `capabilities.source.levelWhileOn`, section 5): a new level `vpp` [Vpp] of the configured sine, the output state unchanged (on stays on, off stays off) - the level equalizer of the stepped sine changes the level at every step. Sine only (`tim:gen:mode`); the level is checked **before** the command (section 3.4, `tim:gen:amplitude`) and read back where the instrument allows (`tim:gen:verify`, output off); never a command that switches the output. `tim.instr.SignalSource` implements it as `tim:gen:unsupported` without any I/O, so a driver that does not declare the capability inherits the refusal. A planned source schedules it in the planning pass like `setFrequency` and raises `tim:gen:schedule` during the execution (section 8.3). |

A waveform the source cannot produce raises `tim:gen:unsupported`; so does `setAmplitude` of a source
without `levelWhileOn`. The session asks for it only with the equalizer on and refuses the
equalizer before anything is armed when the source does not declare it (`tim:session:equalizer`,
owner decision 2026-11-04, section 13.5).

The window words the state after a Stop, an error or closing by the read-back kind (it calls
`isOutputOn(1)`):
`'instrument'` - "output off (confirmed by the instrument)"; `'device'` - "output stopped (device
idle, 0 V)"; `'none'` - "output switched off - this generator cannot report its state; check it at
the instrument" (an information, not a red fault after every Stop). The registry refuses `'none'`
in hardware mode unless the owner sets `generator.allowUnconfirmedOff = true` (section 9.1).

### 3.3 Waveform definitions (what the analysis relies on)

* **Sine**: continuous, offset 0, amplitude `vpp` peak to peak.
* **Swept sine**, single shot from f1 = `s.fStart` to f2 = `s.fStop` in T = `s.duration`, offset 0:
  `'LOG'`: f(t) = f1·(f2/f1)^(t/T); `'LIN'`: f(t) = f1 + (f2 − f1)·t/T, for 0 ≤ t < T; phase
  continuous; hold and return times 0; the real duration within 0.5 % of T (the sweep gate of
  `tim.dsp.sweepResponse` needs the matched duration within 2 %; `tim.dsp.estimateSweepLaw`
  checks the exponential law). A stepped approximation with steps of at most 1 ms is accepted
  (the 33220A synthesises its sweep in steps; the virtual rig emulates 1 ms steps). After the
  sweep the output may stay at f1 or f2 until `outputOff` (the session switches it off right
  after `waitComplete`).
* **Noise**: Gaussian, flat to at least 5.5 kHz, amplitude in Vpp with a crest factor of about 3.3
  (rms ≈ Vpp / 6.6, the 33220A meaning, on which the loudspeaker power check depends); a source
  with another crest factor declares it in `capabilities.source.noiseCrest`.
* **Event samples**: `meas.events` holds the sample count at which the session issued each action.
  With a shared clock (planned, section 8.3) they are exact **on the device timeline** (the
  device I/O latency, e.g. an audio round trip of 5-30 ms, is not included); with separate
  devices they include the network and trigger latency (section 8.2).

### 3.4 Level limit

* Every method that sets a level (`configure*`, and `setAmplitude` where declared) checks it
  **first** and sends no level command when the check fails (`tim:gen:amplitude`): a positive
  scalar, its **open-circuit voltage** at most
  `generator.maxVpp` (fixed at creation; since 1.3.0, WO-004: the limit is an open-circuit
  voltage at every load), within the level range of the source at the configured load
  (`tim.instr.SignalSource.levelRange`).
* Loads: `generator.load` is `'INF'` (the programmed level is the open-circuit voltage) or one of
  `source.loads`; a source that accepts any resistance R as its load setting declares
  `source.loadRange` = [Rmin Rmax] Ω (the 33220A: [1 10000], `OUTP:LOAD <ohms>`, manual p.189).
  At a load of R ohm the programmed level is the voltage across R, its open-circuit voltage
  level × (R + R_s) / R (`openCircuitFactor`, R_s = `outputImpedance_ohm`) and its range the
  open-circuit range × R / (R + R_s). The window sets the load to the amplifier's input impedance
  (owner decision 2026-10-12); direct drive needs `'INF'`. Static helpers of
  `tim.instr.SignalSource`: `supportsLoad`, `levelRange`, `openCircuitFactor`, `loadOhm`,
  `loadsText`.
* `capabilities.source.levelKnown = true`: the driver programs an absolute voltage (SCPI
  generators, NI analog outputs).
* `levelKnown = false`: the output is programmed in full-scale units (audio interface); the volts
  at the output depend on the device and its output knob (a professional line output reaches
  +18 to +24 dBu, well over 10 Vpp at 0 dBFS), so a static `maxVpp` cannot protect anything.
  The driver setting `generator.<driver>.vppAtFullScale` (`daq.<driver>.vppAtFullScale` for a
  combined driver, which reads only `daq.<driver>`; Vpp at full scale, measured once with
  a voltmeter at a fixed knob position; **no default**) is required in hardware mode
  (`checkConfig`). The driver converts Vpp to full-scale units with it and refuses any level with
  more than full scale or more than `generator.maxVpp` (`tim:gen:amplitude`); the operator
  confirmation states the calibration and the knob position. `docs/adding_an_instrument.md` and
  the suitability step of the skill (Part 2) carry this rule.

### 3.5 Block (shared-clock) source outside `acquire`

For a source whose output is played from a plan (section 8.3):

* `configure*`, `setFrequency` and `setAmplitude` (where declared) outside `acquire` set the
  initial state of the next plan;
* `outputOn` and `triggerSweep` outside `acquire` raise `tim:gen:schedule`;
* `isOutputOn` is `false` outside `acquire` - unless 0 V could not be written after a stop (the
  state is then unknown and reported as on);
* `configure*` before `prepare` use the `acquisition.sampleRate` captured by `fromConfig`, or raise
  `tim:gen:mode` when there is none; its frequency limits may be given as a fraction of the sample
  rate (`capabilities.source.bandFraction`).

## 4. Acquisition (`tim.instr.Acquisition`)

Properties: `SampleRate` (read-only; S/s, after `prepare`), `Teds` (read-only; 1 x C cell: `[]`
or a struct `typeNumber` (char), `serialNumber`, `sensitivity` [V per unit], `unit`,
`requiresCcld`; `{}` when the device reads no TEDS - `tim.cal.resolveSensitivities` then falls
back to the certificate / nominal values), `AbortFcn` (settable, default `[]`: `@()` without
inputs or outputs, section 8.1 rule 4).

| Method | Contract |
|---|---|
| `prepare(c)` | `c.sampleRate` [S/s], `c.channels` (input numbers, 1:4), `c.names` (cellstr, `'M1'`...), `c.range` (a value of `capabilities.acquisition.ranges`), `c.filter` (a value of `...filters`), `c.ccld` (logical 1 x C), `c.detectTeds`. Driver-specific settings (e.g. the LAN-XI connector) come from `ctx.settings` captured by `fromConfig`. The device then runs at **exactly** `c.sampleRate` (relative 1e-9), or `prepare` fails with `tim:<driver>:rate` naming the achievable rate (NI DSA devices coerce a requested rate; a mislabelled rate would shift the frequency axis and the schedule). Leaves the device ready to acquire; reports its `'prepare'` steps. |
| `[data, info] = acquire(n, onBlock, timeout)` | records `n` samples per channel; `data` n x C double in `info.dataUnit` (section 4.2), column c = channel c; `onBlock(nNow)` with **one** input, section 8; `timeout` [s] wall-clock limit (default `n/fs*1.5 + 10`). Stops the acquisition on **every exit path - normal end, error, Stop and an interrupt (Ctrl+C: `onCleanup`, not only `try`/`catch`)** - and leaves the device ready for the next call. Calls `AbortFcn` first on every abnormal exit (section 8.1). |
| `[data, info] = collect(n)` | the data the last `acquire` received so far (partial data after an error or Stop), same format; at most `n` rows. |
| `[x, nTotal] = recent(n)` | the last ≤ n samples (rows x C, `dataUnit`) of the running or last acquisition and the number received so far; `[]` when none. Cheap, no I/O (live view). |
| `tf = isAcquiring()` | an acquisition (data stream) is running - the window then defers background work. |
| `tf = isPlanning()` | `true` only while a combined block device runs its planning pass (section 8.3), otherwise `false`. Cheap, no I/O. Callbacks with a wall-clock meaning (e.g. the countdown of `tim.val.channelIdentification`) do nothing while it is `true`. |
| `b = rawBytes()` | undecoded bytes of the last acquisition (uint8 row) for raw-data preservation, or empty when the driver keeps none. |

**`close()` during `acquire`** (also re-entrantly from `onBlock` or a window callback) stops output
and acquisition at once and marks the object closed. The running `acquire` then ends with
`tim:instr:closed` at its next step and **never re-opens a released resource** (MATLAB System
objects such as `audioPlayerRecorder` set themselves up again on the next call after
`release()`); every later `acquire` raises `tim:instr:closed`. The LAN-XI driver's own
`shutdown()` (return to Idle, keep the connection) stays a driver method and is not part of the
contract (D21).

### 4.1 `info` returned by `acquire` / `collect`

* `fs` - sample rate reported by the data (S/s); `dataUnit` - `'V'` or `'FS'` (section 4.2);
* `integrity` - `ok` (no fatal problem), `fatal`, `warnings` (cellstr), `peakFractionOfRange`
  (1 x C: peak / the device full scale, i.e. its nominal input range, LAN-XI `'10 Vpeak'` → 10 V),
  `channelFaults` (1 x C cell of cellstr: device-reported channel faults **in the driver's
  words**, e.g. `'LAN-XI flag INVALID (cable or CCLD fault)'`, so the session needs no device
  vocabulary); `info.fs` different from the rate set by `prepare` is a fatal problem for every
  driver;
* any driver-specific fields (LAN-XI: `unit` (per-signal cell from the stream), `scaleFactor`,
  `stats`, `qualityEvents`, `signalIds`, `integrity.peak_V`), stored as they are in
  `meas.channelInfo`.

### 4.2 Volts or full-scale units

Data are volts at the input (`dataUnit 'V'`). A device without a known input scale (an audio
interface delivers full-scale units behind an unknown front-panel gain) delivers `'FS'` unless
the driver setting `daq.<driver>.voltsAtFullScale` (1 x C, measured) is configured; it then
converts to volts. The session stores `meas.unit = info.dataUnit` (stage B); levels in Pa /
dB SPL and the sensitivity layer are used only for `'V'`, otherwise the window shows labelled
dB re FS. No range string is parsed outside the drivers (`peakFractionOfRange`). Calibration and
analysis use channel ratios only and are unchanged. The generic field is named `dataUnit`
because the LAN-XI `info.unit` already is a per-signal cell stored in saved measurements (D22).

## 5. Capabilities

`capabilities()` (static) returns:

| Field | Meaning | 33220A | LAN-XI 3676 | simcombined | demo |
|---|---|---|---|---|---|
| `roles` | `{'source'}`, `{'acquisition'}` or both | source | acquisition | both | source |
| `sharedClock` | output and inputs of this object run on one sample clock | false | false | true | false |
| `rolesTogether` | a combined driver that works only when it takes both roles (section 9.1) | false | false | true | false |
| `products` | struct array `name` (as listed by `ver`) and `feature` (license key, e.g. `Data_Acq_Toolbox`) of the MATLAB products needed beyond MATLAB + Signal Processing Toolbox; checked in hardware mode only | none | none | none | none |
| `source.waveforms` | subset of `{'sine','sweep','noise'}`; `'sweep'` is required (section 9.2) | all | - | all | sine, sweep |
| `source.sweepSpacing` | subset of `{'LOG','LIN'}` | both | - | both | both |
| `source.frequencyRange` | [fMin fMax] Hz (`Inf`: limited by the sample rate only) | [1e-6 20e6] | - | [1 Inf] | [0.1 1e5] |
| `source.bandFraction` | highest frequency as a fraction of the sample rate (shared clock), `NaN` for an own clock | NaN | - | 0.45 | NaN |
| `source.loads` | listed `generator.load` values: `'INF'` = programmed value is the open-circuit voltage, `'50'` = the voltage into 50 Ω | INF, 50 | - | INF | INF |
| `source.loadRange` | optional (1.3.0): [Rmin Rmax] Ω of any resistance accepted as the load (written as a number, e.g. `'600'`); the level range there scales from the INF entry by R / (R + `outputImpedance_ohm`) | [1 10000] | - | - | - |
| `source.maxVpp` | largest programmable level per entry of `loads`; `generator.maxVpp` (an open-circuit voltage) must not exceed the largest open-circuit voltage | 20, 10 | - | 10 | 10 |
| `source.minVpp` | smallest programmable level per entry of `loads` | 0.02, 0.01 | - | 0.001 | 0.002 |
| `source.sweepTime` | [min max] sweep duration [s] | [0.001 500] | - | [0.1 300] | [0.01 300] |
| `source.noiseCrest` | crest factor of the noise (Vpp / 2 / rms) | 3.3 | - | 3.3 | 3.3 (no noise) |
| `source.outputImpedance_ohm` | source impedance (loudspeaker drive estimate, operator texts) | 50 | - | 0 | 50 |
| `source.trigger` | how `triggerSweep` starts the sweep: `'bus'`, `'software'`, `'clock'` (sample-exact on the shared clock) | bus | - | clock | bus |
| `source.readback` | kind of `isOutputOn` (section 3.2): `'instrument'`, `'device'`, `'none'` | instrument | - | device | instrument |
| `source.levelKnown` | the driver programs absolute volts (section 3.4) | true | - | true | true |
| `source.levelWhileOn` | optional (1.6.0, WO-006): the driver implements `setAmplitude`, a level change of the sine while the output is on (section 3.2); the stepped-sine equalizer needs it. A driver without the field counts as `false` (`tim.instr.SignalSource.levelWhileOn(source)`) | true | - | true (scheduled like `setFrequency`) | false |
| `acquisition.channels` | analog inputs (≥ 4) | - | 4 | 4 | - |
| `acquisition.simultaneous` | all inputs sampled at the same instant on one clock (must be true) | - | true | true | - |
| `acquisition.sampleRates` | supported rates [S/s], or `[]` with a `sampleRateRange` | - | 4096 ... 65536 | 4096 ... 65536 | - |
| `acquisition.sampleRateRange` | [min max] of a continuous range (`checkConfig` and `prepare` refuse rates the device cannot run exactly) | - | [] | [] | - |
| `acquisition.bandFraction` | usable band / sample rate (anti-alias filter); limits `analysis.fMax` and the stop frequencies | - | 0.45 | 0.45 | - |
| `acquisition.ranges` | values of `acquisition.range` | - | `'1 Vpeak'`, `'10 Vpeak'` | `'10 Vpeak'` | - |
| `acquisition.filters` | values of `acquisition.filter` (high-pass / coupling) | - | `'DC'`, `'0.7 Hz'`, ... (module list) | `'0.7 Hz'` | - |
| `acquisition.ccld` | switchable CCLD/IEPE supply per input | - | true | true (modelled) | - |
| `acquisition.teds` | reads TEDS | - | true | false | - |
| `acquisition.dataUnit` | `'V'`, or `'FS'` when the input scale is unknown (section 4.2) | - | V | V | - |
| `acquisition.mode` | `'streaming'` (data arrive while recording) or `'block'` (recorded in blocks) | - | streaming | block | - |
| `acquisition.needsOwnSource` | the driver cannot call `onBlock` as data arrive: usable only when it is also the source (planned, section 8.3) | - | false | true | - |

The static values describe what the driver supports; a driver may still refuse a value the
connected device reports as unsupported (LAN-XI: `tim:lanxi:rate` from `module/info`). The
simcombined values are those of `tim.sim.SimulatedCombined` (as implemented in stage B); its settings
(`daq.simcombined`) are `blockSamples` (2048), `serial` and `seed` (noise output), its lamp labels
"Output" and "Inputs". The demo values are those of the imaginary DEMO-SG1
(`docs/ref_demo_source.md`; driver `tim.instr.DemoSource`, the worked example of
`docs/adding_an_instrument.md`, simulation only); its settings (`generator.demo`) are `host`
(the documentation address 192.0.2.10, never used), `port` and `timeout`.

## 6. Connection steps (checklist of Setup > Connection)

The window shows, in this order: the source's steps, the acquisition's steps (once for a combined
device), then the session's own steps `sens` (microphone sensitivities), `settle` (settling after
the channel setup, hardware only; its text from `describe().texts.settle`) and `signal` (1 s
signal check without excitation). A driver step is shown after the lamp label of its role
(`describe().labels`; both labels joined by " + " for a `'both'` step): "Generator: connect
(33220A, SCPI)", "DAQ: open recorder" (1.3.0, owner 2026-10-13: the roles, not the product names).

| Driver | Steps (`key`: label, role, phase) |
|---|---|
| keysight33220a | `gen`: connect (33220A, SCPI), source, connect |
| lanxi | `lanxi`: connect (LAN-XI, REST), acquisition, connect; `idle`: recorder state Idle, acquisition, connect; `open`: open recorder, acquisition, prepare; `teds`: TEDS detection, acquisition, prepare; `setup`: channel setup → streaming, acquisition, prepare |
| simcombined | `device`: connect (simulated device), both, connect; `setup`: channel setup, acquisition, prepare |
| demo | `demo`: connect (DEMO-SG1, SCPI, simulated), source, connect |

Rules:

* `state` is `run`, `ok`, `warn`, `fail` or `skip`; `detail` is free text (shown next to the step).
* Keys are unique among drivers that can be combined (`rolesTogether` drivers only with
  themselves) and never `sens`, `settle` or `signal` (checked by the contract test). The keys of
  the two existing drivers stay as they are.
* Report `run` **before** opening anything for that step. `ProgressFcn` may throw at `run`
  (operator Stop, `tim:session:stopped`): in `fromConfig` the driver then releases what it opened
  and lets the error propagate. In `prepare` a driver may swallow callback errors (LAN-XI does);
  the session honours the Stop at its next own step.
* The lamp of a role follows that role's steps (INSTRUMENTS section); a `'both'` step drives both
  lamps; a failing session step (`sens`, `settle`, `signal`) turns the acquisition lamp red. A
  lamp's label is `describe().labels.<role>` and its tooltip the display name and identity
  (section 7.1). The channel cards (TEDS) are refreshed after every `'prepare'` step that ends
  (before 1.2.0 only after the key `teds`).
* While not connected the checklist lists the steps of the configured drivers; it is rebuilt
  when a configuration with other drivers is loaded, and at Connect when they differ from the
  last list.

## 7. Identity and metadata

* `identity()` feeds the window (INSTRUMENTS lamps and "In use", Setup > Connection: display
  name, vendor, model, serial number, firmware - owner decision §0.2; no selection controls,
  section 7.1) and the log line after connecting (`Signal source: <display name> – <raw>`,
  `Acquisition: ...`; one line `Signal source and acquisition: ...` for a combined device).
* `collectMetadata` stores `md.generator = s.Gen.metadata()` and `md.daq = s.Daq.metadata()`. Both
  are **supersets of the fields before 1.2.0**, so saved data and scripts keep working:
  `md.generator.identity`, `host`, `port`, `maxVpp`, `load` (33220A); `md.daq.host`, `connector`,
  `model`, `serial`, `firmware`, `setup`, `teds` (LAN-XI). A combined device appears in both with
  `roles` naming both. Readers of the new fields (`md.*.identity`, `md.*.driver`,
  `integrity.channelFaults`) guard with `isfield`: measurements saved before 1.2.0 lack them.
* The switching calibration records the acquisition chain: `cal.meta.acquisition` = driver,
  display name, identity (model, serial, firmware), sample rate, range, filter, CCLD
  (`tim.cal.acquisitionChain`, from `session.acquisitionChain()`; flat text fields `model`,
  `serial`, `firmware`).
* `tim.cal.calibrationContext(cal, cfg, meas)` warns when a measurement uses another driver or
  module (model / serial) or other input settings (range, filter, CCLD, sample rate): `C_k` is a
  ratio of chain gains that include the DAQ input. The third input is optional (`TestCalibration`
  calls it with two): a measurement, of which `meas.metadata.daq` gives the module and
  `meas.metadata.acquisition` and `meas.fs` give the input settings (not the window's current
  `cfg`, which for an opened folder holds today's settings), or a chain struct (the window's
  calibration label passes the connected module, `session.acquisitionChain()`). Without it the
  configured driver and input settings are compared (module unknown). Unknown means no warning,
  item by item, in both directions: a calibration without `meta.acquisition` (made before 1.2.0;
  the existing test `calibrationContextChecks` expects none) gives no DAQ warning at all, and
  measurement metadata without a `driver` field (every folder saved before 1.2.0 has
  `md.daq.model`, a numeric `serial`, `firmware`, `host`, `connector`, but no `driver` or
  `identity`) is not compared by driver - its model and serial number are. Identities are compared
  as text (`num2str` for numeric serials). Tested with a measurement and a calibration saved by the
  e8fb4fb code in a temporary worktree (`tests/fixtures/saved_e8fb4fb`), never with files from
  `data/`.

### 7.1 What the window takes from the drivers (stage C, as built)

`tim.gui.Tubebench` names no instrument (`grep -i "lanxi\|lan-xi\|33220"` finds nothing in it or
in `MeasurementSession.m`; `TestGui/noInstrumentNamesInWindowOrSession`). It has **no instrument
selector** (owner decision §0.2): the configuration selects the drivers, the window shows them.
Everything it says about the instruments comes from `tim.instr.driverInfo` (class-level, before
connecting) and from the connected objects:

| Window element | Driver member |
|---|---|
| INSTRUMENTS lamps 1 and 2: label | `describe().labels.source` / `.acquisition` (the lamp column widens for a longer label) |
| Lamp tooltips | `'<label>: <displayName>'`, after Connect `' – <vendor> <model>, s/n <serial>, firmware <firmware>'` from `identity()` |
| INSTRUMENTS "In use" (one line per instrument; the row holds three lines, so a `displayName` of more than about 50 characters may wrap once) | before Connect (and after Disconnect) the `displayName` of each configured driver; after Connect `'<label>: <model> s/n <serial>'` from `identity()`, followed by "(simulated)" in simulation mode (the protocol mocks report realistic identities, the LAN-XI mock the lab module's) |
| Setup > Connection, Instruments table | one row per role, one row "Output + Inputs (both roles)" for a combined device: role (lamp label and role), `displayName`, driver name, vendor, model, serial number, firmware (`identity()`, "–" before Connect) and the configured settings (`generator.maxVpp`, `load`; sample rate, range, filter, CCLD) |
| Instruments table tooltip | the values the drivers allow (`capabilities()`: loads with `minVpp`–`maxVpp`, `sweepTime`, `waveforms`; `sampleRates` or `sampleRateRange`, `ranges`, `filters`, `ccld`, `teds`). The window has no sample-rate or range control: these are set in the configuration and checked by `checkConfig` (section 9.2) |
| Connection checklist, lamp of each step, card refresh | `connectionSteps()` (`key`, `label` after the lamp label of its `role`, `phase`), then the session's steps; the settling label from `texts.settle` (section 6) |
| Operating-mode, Connect and Disconnect tooltips, the log line of Disconnect, the closing dialog | `texts.noun` and `texts.closed`, e.g. "Connect the generator and the DAQ (generator output off), read TEDS and check every channel" ("read TEDS" only when `capabilities.acquisition.teds`), "Generator output off, DAQ back to Idle, connections closed." (before 1.3.0 "LAN-XI module") |
| Output state after Stop, an error or closing | `isOutputOn(1)` worded by `capabilities.source.readback` (section 3.2) |
| Live view, background work | `recent()`; the background build waits while `isAcquiring()` |
| Frequency fields (EXCITATION) | at most `acquisition.bandFraction` × `acquisition.sampleRate`, `source.frequencyRange(2)` and, for a shared clock, `source.bandFraction` × sample rate; at least `max(1 Hz, source.frequencyRange(1))` |
| Amplitude field | from the smallest level at `generator.load` (`levelRange`; 33220A at `INF`: 0.01 Vpk; before 1.2.0 the field allowed 0.005 Vpk, which the 33220A refuses: such a file loads with a warning and the field starts at the minimum) up to `generator.maxVpp` / 2 as open-circuit voltage and the largest level at the load (`tim.app.driveLimits`) |
| Amplifier input (EXCITATION) | the list offers High Z and typical inputs; a typed resistance up to `source.loadRange(2)` becomes `generator.load`, above it `'INF'` (1.3.0) |
| Sweep duration field | `source.sweepTime` |
| Drive estimate | `source.outputImpedance_ohm` (`tim.app.driveEstimate`, D12) |

A driver that is not registered (an opened measurement folder of another set-up) is shown as
`unknown driver "<name>"` with the lamp labels "Generator" / "DAQ" and the limits of before;
Connect then reports `tim:config:driver`. Tests: `TestGui/instrumentsShownFromTheDrivers` (the
lab drivers on their mocks: display names, identity, texts of before, limits, Disconnect) and
`TestGui/combinedDeviceShownFromItsDriver` (`simcombined`: one row, labels, the checklist before
connecting, texts, limits, identity); the layout was checked on screen captures of a visible
window in simulation mode with both driver selections.

## 8. Timing, callbacks and the shared clock

**The session schedules the excitation on the received-sample count** (unchanged): in
`onBlock(n)` it switches the output on and triggers the sweep when `n` reaches the pre-roll, steps
the stepped-sine frequency at fixed targets, waits for the sweep (`waitComplete`) and switches the
output off **as the normal end of every excitation**. Every `onBlock` first runs `BlockCallback`
(window: `drawnow`, so the Stop button is processed) and throws `tim:session:stopped` after a Stop.
The window's Stop and close callbacks also call `s.Gen.outputOff()` directly.

### 8.1 Rules for every acquisition driver

1. `n` is the number of samples per channel reached so far, non-decreasing **within each pass**
   (section 8.3); the last call of a pass has `n ≥` the requested count.
2. While the device records, `onBlock` is called **at least every 0.25 s** (Stop stays responsive).
3. An error thrown by `onBlock` stops the acquisition (and the output of a combined device),
   keeps the data received so far for `collect`, and propagates **unchanged** (same identifier).
4. **Abort first**: on every abnormal exit of `acquire` - its own error (stalled stream,
   time-out, transport fault), an error thrown by `onBlock`, an interrupt (via `onCleanup`) - the
   driver calls `AbortFcn` **before any stop or drain I/O**, once, ignoring any error it raises.
   The session sets `AbortFcn = @() s.Gen.outputOff()` when it connects (D24, approved by the
   owner 2026-10-11), so the loudspeaker is not driven while the driver stops its device (with
   an unreachable LAN-XI module: one HTTP time-out for the stop request and one for the first
   status poll, about 20 s with the default settings). A combined device gets the same hook:
   its re-entrant `outputOff` stops its output at once (section 8.3) before its own stop
   sequence (stopped, then 0 V). After `acquire` has returned with the error, the session's
   error path disarms the source (`armOutput(false)`, which switches the output off once more,
   also when the error came before the driver could call the hook); the session's `close()`
   clears the hook.
5. `onBlock` may call SignalSource methods of the same or another object, and `close` of its own
   object (re-entrancy, section 2.2); the driver holds no lock while calling it.
6. `onBlock` takes **one** input (the session's nested functions take one; a second argument
   would raise "too many input arguments").
7. No timer or other asynchronous callback of a driver calls session or window code.

### 8.2 Data-driven acquisition (every pair of separate devices)

Whenever source and acquisition are different objects, the acquisition driver calls `onBlock`
**as data arrive**: LAN-XI from the stream; an NI device with a background start and a polling
read; an audio interface per `audioDeviceReader` frame. The source acts when called, with a
network / trigger latency. The analysis only needs the excitation to lie inside the record
(`tim.dsp.detectExcitation`, sweep gate) and uses channel ratios only. A driver that cannot call
`onBlock` while the device records declares `capabilities.acquisition.needsOwnSource = true`: it
can then be used only as a combined driver for both roles, and the registry refuses any other
pairing before any I/O (section 9.1). Otherwise a planning pass with a separate source would run
the whole schedule before the first sample (output on, trigger, `waitComplete` and output off),
so the excitation would never be recorded.

### 8.3 Planned acquisition (one object takes both roles on a shared clock)

Only when `ctx.roles` contains both roles (`s.Gen == s.Daq`) may the driver plan:

1. **Planning pass** - before anything is played, the driver calls `onBlock(n)` for
   `n = B, 2B, ...` up to the requested count without waiting (B: the driver's block, its setting
   `blockSamples`, e.g. 2048; the contract tests read it from `metadata().settings` and place
   their actions in multiples of it);
   `isPlanning()` is `true`. Every source call made meanwhile is **scheduled** on the device
   timeline at the current `n` (sample-exact): `outputOn`, `triggerSweep`, `setFrequency`, a
   level (`configure*`, and `setAmplitude` where declared: the new level from that sample, phase
   continuous), and `outputOff` ("off at n", the normal end of the excitation). `waitComplete` returns
   `true` when the timeline says the sweep has ended. **Only an error thrown out of `onBlock`**
   (e.g. a Stop: `tim:session:stopped`) discards the plan: nothing is played, the output stays at
   0 V, the error propagates (rule 3).
2. **Execution** - the driver plays the plan while recording and calls `onBlock(nDone)` with the
   real progress, again from the first block (rule 1 holds within each pass); `isPlanning()` is
   `false`. All scheduled actions already happened, so the session's `onBlock` only processes
   Stop and the live view. A level, frequency, trigger or `outputOn` call during execution raises
   `tim:gen:schedule`. **`outputOff` during execution stops the output at once** (fade of at most
   5 ms to 0 V, then zeros); `acquire` then keeps recording to the end (preferred) or ends with
   `tim:instr:outputStopped` - it never returns a short record without an error.

A Stop from the window during the planning pass calls `outputOff` (scheduled) and then
`tim:session:stopped` is thrown from `onBlock`, which discards the plan; during execution the
same `outputOff` stops the output at once. The session code is the same for both kinds of
device: `measureSweep` / `measureStepped` / `measureNoise` are unchanged.

A device whose output is **queued ahead** of the recording (an NI device in continuous mode: the
output samples are written some blocks before they play) cannot fade samples that are already
queued. Its `outputOff` during execution stops the device at once and then writes 0 V (the output
stops at its last value - a click, no fade - and no DC remains), and `acquire` ends with
`tim:instr:outputStopped`; its recorded blocks lag the played ones by the queue length, a fixed
latency that must stay well inside the pre- and post-roll. The contract tests run on the protocol
mock, which has no queue; on the hardware the Stop is checked at the output terminal
(`docs/adding_an_instrument.md` sections 4.1 and 10). (Added after the review of 2026-10-11; there
is no such device in the lab.)

## 9. Registry and configuration

### 9.1 Registry API (`+tim/+instr`)

| Function | Contract |
|---|---|
| `list = tim.instr.drivers()` | the registry: struct array `name`, `class` - one line per driver, in one file |
| `d = tim.instr.driverInfo(name)` | `describe()` plus `class` and `capabilities()`; unknown name: `tim:instr:unknownDriver` |
| `obj = tim.instr.create(role, cfg, ctx, other)` | creates the driver named by `cfg.generator.driver` (`role = 'source'`) or `cfg.daq.driver` (`'acquisition'`); returns `other` itself when both roles name the same driver and `other` takes both roles (one object, one connection). Checks first, **before any I/O**, in this order (below). Then calls `fromConfig(cfg, ctx)` with `ctx.roles` and `ctx.settings` filled in. |

Checks of `tim.instr.create`:

1. The driver is registered (`tim:instr:unknownDriver`).
2. It has the role (`tim:instr:role`).
3. The pairing (`tim:instr:role`, naming both drivers): one object takes both roles exactly when
   both role sections name the same driver; a `rolesTogether` driver must be named for both
   roles; an acquisition driver with `needsOwnSource` must also be the source. One object per
   driver name: two separate devices of the same driver (e.g. an NI card for the output and
   another for the inputs) are one combined driver that drives both.
4. A simulation-only driver is not used in hardware mode (`tim:instr:simulationOnly`).
5. Hardware mode only: every product of `capabilities().products` is installed (`ver` name) and
   licensed (`license('test', feature)`), and the driver's optional `checkInstalled()` passes
   (`tim:instr:missingProduct`, naming the product and the driver). In simulation mode a driver
   runs on its protocol mock, which must not call product functions, so the contract tests run
   on machines without the driver's toolbox (other labs, WO-002).
6. Hardware mode only: a source with `readback 'none'` needs `generator.allowUnconfirmedOff = true`
   (`tim:instr:readback`).
7. The driver's `checkConfig(cfg)` (`tim:config:*`).

The session builds `ctx` (`mode`, `rig`, `progress`) and keeps the rig as `s.Rig` (simulation
hooks: `setMicPositionsForSimulation`, `setSimulationSample`, ground truth in tests). Optional
toolboxes are therefore needed only by the driver that uses them; the base requirement stays
MATLAB + Signal Processing Toolbox. A driver file must not call product functions outside
`fromConfig` and its instance methods (class loading must work without the product).

The registry reads every configuration through `tim.app.migrateConfig` (section 9.3), so a
configuration with the legacy keys (`generator.host` / `port` / `timeout`, the top-level `lanxi`
section, no `driver`) still connects (stage A read the legacy keys itself, D38). Checks 4-7 run
for the drivers of both roles before the first instrument is opened.
`tim.instr.drivers('add', entry)` / `('remove', name)` register a driver for the running MATLAB
session only (tests; trying a driver before its line is added).

### 9.2 Configuration layout (`formatVersion` 2)

```json
"generator": {
  "driver": "keysight33220a",
  "maxVpp": 2,
  "load": "INF",
  "keysight33220a": { "host": "169.254.2.20", "port": 5025, "timeout": 5 }
},
"daq": {
  "driver": "lanxi",
  "lanxi": { "host": "169.254.64.156", "timeout": 10, "connector": "BNC" }
},
"acquisition": { "sampleRate": 16384, "range": "10 Vpeak", "filter": "0.7 Hz",
                 "ccld": [true, true, true, true], "detectTeds": true, "settleTime": 3,
                 "maxPeakFraction": 0.8, "sensitivityPolicy": "certificate>teds>nominal" }
```

* Role settings stay generic: `generator.maxVpp`, `generator.load`, the whole `acquisition`
  section. Their **allowed values** come from the selected driver (`loads`, `maxVpp`, `minVpp`,
  `sweepTime`, `sampleRates`, `bandFraction`, `ranges`, `filters`, `ccld`, `teds`) through
  `checkConfig`.
* `acquisition.sampleRate`, `range`, `filter` and `ccld` may be `null` or `''`: the driver's
  default (`describe().defaults.acquisition`). For `lanxi` these are today's values (16384 S/s,
  `'10 Vpeak'`, `'0.7 Hz'`, CCLD on), so `user_config.json` keeps its meaning and a file that
  only sets another `daq.driver` does not fail on LAN-XI values.
* `checkConfig` policy: `ccld = true` on a device without a switchable supply is an error
  (`'external IEPE supply: set acquisition.ccld false'`); `detectTeds` on a device without TEDS
  gives the step `'skip'`, no error; the swept sine with the configured spacing must be supported
  (`'sweep'` in `source.waveforms`, `excitation.sweep.spacing` in `sweepSpacing`) because the
  switching calibration and Test E are sweeps (`tim.app.runCalibration`), and `excitation.mode`
  must be in `source.waveforms` (`tim:config:excitation`); `generator.load` one of `loads` or
  within `loadRange`; `generator.maxVpp` (open circuit) at most the source's largest open-circuit
  voltage, and the levels of the swept sine and of the selected signal at least the minimum at the
  load (`levelRange`; a level
  that is not played now is refused by `configure*` when it is, `tim:gen:amplitude`); sweep
  durations within `sweepTime`; a sample rate the device runs exactly; in hardware mode
  `vppAtFullScale` for `levelKnown = false`.
* Driver-specific settings live in a sub-struct named after the driver. It is merged onto
  `describe().defaults.settings`, not onto `tim.app.defaultConfig`. A sub-struct named after
  another registered driver is kept without a warning (a file can hold the settings of several
  drivers and switch with `driver`); unknown names still give `tim:config:unknownField`.
* A combined driver reads its device settings from `daq.<name>`; `generator.driver` names the same
  driver. A sub-struct in a section its driver never reads (`generator.<name>` of a driver that
  takes both roles, `generator.<name>` of a driver without the source role, `daq.<name>` of one
  without the acquisition role) gives the warning `tim:config:misplacedSettings` in `loadConfig`
  and at Connect (`tim.instr.create`; `tim.instr.Instrument.misplacedSettings`).
* **Loading only warns** (D29; extended after the review of 2026-10-11). An **unknown driver name**
  (a measurement folder from another lab or from a driver removed later): `loadConfig` and
  `validateConfig` give the **warning** `tim:config:driver`, keep its sub-struct as it is and skip
  the driver-dependent limits. A driver named for a role it does not have, and a value outside the
  limits of the selected driver (e.g. a level below its minimum, `generator.maxVpp` above its
  maximum at the load, a sweep time it cannot play - all accepted by 1.1.0), give the warning with
  the driver's identifier (`tim:config:amplitude`, ...), also returned in the report (the window
  logs it as a check). So File > Open measurement ("use the saved set-up"), Load configuration, the
  start-up of the window and scripts that only reprocess still work. The **error** is raised where
  an instrument is needed: by `tim.instr.create` at Connect and by
  `validateConfig(cfg, 'instruments')`, which `MeasurementSession` calls in its constructor and
  setters, and the window while it is connected (it shows such errors as "Check the settings").
* `tim.app.driveEstimate` takes the source impedance from `capabilities().source.outputImpedance_ohm`
  of `generator.driver` (before 1.2.0 a fixed 50 Ω: a DAQ output of about 0 Ω driving an 8 Ω
  loudspeaker directly would have been estimated (58/8)² ≈ 50 times too low - a safety defect for
  any new source; an unknown driver counts as 0 Ω, the worst case).
  The operator text `ampDirect` ("via the 50 Ω generator output", `tim.app.msg`) is composed from
  the same value.

### 9.3 Migration of older files (`tim.app.migrateConfig`)

One function, used by `loadConfig` (before the merge), by the `MeasurementSession` constructor
and by `validateConfig` for configurations built in code (old scripts set `cfg.lanxi.*` or
`cfg.generator.host` on `defaultConfig`):

1. A top-level `lanxi` section and no `daq` section → `daq.driver = "lanxi"`, `daq.lanxi = lanxi`;
   `lanxi` is removed (no unknown-field warning).
2. `generator.host` / `port` / `timeout` outside a driver sub-struct always move into
   `generator.keysight33220a`, the driver they belong to (a saved file then holds them there).
   When another generator driver is selected, that driver does not use them, and the warning
   `tim:config:legacyField` names the keys and where that driver's own setting goes
   (`generator.<driver>.*`): a user who only changed the driver name must not silently get the new
   driver's default address without being told.
3. A missing `driver` key → the default driver of the role (`keysight33220a`, `lanxi`).
4. Both layouts in one file → the new keys win; `tim:config:legacyField` names the ignored old keys.
   A configuration built in code starts from `defaultConfig`, which already holds the new keys with
   the driver defaults: there a new key that still holds its driver default yields to the old key
   the script set (otherwise the new key wins, with the warning).
5. The result has `formatVersion` 2; `saveConfig` writes the new layout.

`config/user_config.json` (formatVersion 1) is **not rewritten**: it loads with the same effective
settings, which a test compares field by field with the same file in the new layout. The
`config.json` of saved measurement folders loads the same way (File > Open measurement).
`example_config.json` and `sim_thin_screen.json` are converted to the new layout (templates show
the current format). Software 1.1.0 cannot read a formatVersion 2 file (not required).

## 10. Simulation

| Driver selection in a simulation configuration | What runs | Purpose |
|---|---|---|
| `keysight33220a` + `lanxi` (default) | the **real drivers** over their protocol mocks (`MockScpiTransport`, `MockLanXiHttp` / `MockLanXiStream`) on one `tim.sim.SimulatedRig` | end-to-end coverage of every SCPI command, REST request and the stream parser; the bus-traffic tests; the GUI and end-to-end tests |
| `simcombined` for both roles | `tim.sim.SimulatedCombined`: the contract implemented directly on the rig; shared clock (`GenClockPpm = 0`, no trigger latency), planned block acquisition (section 8.3), no TEDS, no recorder states | proves that the contract is not shaped like 33220A + LAN-XI (§0 change B); runs calibration and measurement through the session and the hidden window; model for a real combined driver |
| `demo` + `lanxi` | the demo source `tim.instr.DemoSource` over its own protocol mock `MockDemoSource` (an imaginary SCPI generator) on the rig, the LAN-XI driver on its mocks | the worked example of `docs/adding_an_instrument.md`: a driver made from the templates, in the contract tests, `tests/TestDemoSource.m` and the window |

The rig couples a source to the microphones in one of two ways:

* `setGeneratorState(s)` - **for the mock of a separate function generator** (own clock): the
  33220A mock, the demo's `MockDemoSource`, the template `MockTemplateSource`. The rig synthesises
  the waveform from the generator state (`FUNC` `'SIN'` / `'NOI'`, `FREQ`, `VOLT` in Vpp,
  `FREQ_STAR`, `FREQ_STOP`, `SWE_SPAC`, `SWE_TIME`, `SWE_STAT`, `OUTP`, `TRIG_SOUR`), with a
  stepped sweep, the bus-trigger latency (`generatorTrigger()`) and `GenClockPpm`; a separate DAQ
  mock reads the microphones with `generate(n)`. (Until stage 6: "only for the 33220A mock"; D44.)
* `y = respond(x)` - **for a source that produces samples**: `x` n x 1 excitation volts in, n x 4
  microphone volts out, through the same FIR, noise and clock path. A protocol mock of an NI DAQ or
  an audio interface holds a sample buffer (the planned output), not a generator state, so it calls
  `respond`; `simcombined` and the template `MockTemplateCombined` do too. `generate(n)` becomes
  `respond(sourceSignal(n))` internally, so the 33220A path, its random-number order and its bus
  traffic stay unchanged.

The rig keeps an `OutputLog` filled by both paths, one row per output block
`[firstSample nSamples peak_V last_V]` (sample index on the rig's timeline; `respond(zeros(0, 1))`
adds a row `[n 0 0 0]`: the output was set to 0 V), so the contract tests can check generically
what was really played (section 11.3); `markTrigger(n)` records a sweep start of a shared-clock
source in `TriggerLog`. A generator mock that is asked whether its sweep is complete (33220A
`*OPC?`, the demo source and the template) first calls `finishSweep()`: the running data stream
(`MockLanXiStream`, registered with `setProducer`) produces samples until the triggered sweep
has ended, as on the bench, where `*OPC?` blocks until the end of the sweep while the stream keeps
filling. Before 2026-10-11 the mocks answered at once and the last 5-30 ms of every simulated
sweep were cut (contract case `waitCompleteNotBeforeTheEndOfTheSweep`). A level change while the
output is on (`setAmplitude`, 1.6.0) reaches the rig like every other change of the generator
state: the 33220A mock passes the new `VOLT` to `setGeneratorState` and the next block the rig
generates plays it, phase continuous; `simcombined` applies a scheduled level from its sample
(contract cases `levelChangeWhileTheOutputPlays`, `levelChangeHeardInTheRecord`). A new real driver brings its own protocol mock (`docs/adding_an_instrument.md`
step 5, from the templates) and runs in simulation mode like the two lab drivers.

## 11. Safety duties (checked by `tests/TestInstrumentContract.m`)

### 11.1 Drivers

SignalSource:

1. **Output off on creation**: `fromConfig` switches the output off (section 3.1) before any other
   setting.
2. **Output off on `close`, in `delete` and after any error** a driver method raises after it may
   have changed the instrument (e.g. a read-back mismatch or an instrument error).
3. **Level limit before every level command** (section 3.4): every method that sets a level checks
   it first (`tim:gen:amplitude`) and sends no level command when it fails - `setAmplitude`
   (optional, 1.6.0) as well; `outputOn` re-checks the programmed level (read back where
   possible). A source without `levelWhileOn` refuses `setAmplitude` with `tim:gen:unsupported`
   and sends nothing (the base class).
4. `outputOn` only when armed and configured; `configure*` leave the output off; `armOutput(false)`
   switches it off.
5. **Read-back** of the declared kind (section 3.2); the window reports "confirmed off" only from
   an `'instrument'` read-back.
6. `outputOff` and `close` never throw and may be called any number of times, in any state, and
   re-entrantly; a second `close` sends nothing.

Acquisition:

7. `acquire` stops on **every exit path - normal end, error, Stop, interrupt** (`onCleanup`, not
   only `try`/`catch`) and the next `acquire` works (unless the object was closed).
8. `AbortFcn` first on every abnormal exit, before any stop or drain I/O (section 8.1 rule 4).
9. `close` is idempotent, never throws, is bounded in time (`setTimeout`) and sends nothing the
   second time; `close` during `acquire` ends it with `tim:instr:closed` and no released resource
   is opened again.
10. Data are raw volts at the input, or full-scale units for an unknown input scale (section
    4.2); the driver never applies a sensitivity (the LAN-XI channel setup keeps the module's
    1 V/V transducer and rejects a stream unit other than V).
11. Integrity problems are reported in `info.integrity`, never hidden; partial data stay available
    through `collect`.

Combined device: 12. when the acquisition stops for any reason - also when the device itself
fails while the output plays - the output stops too: the device is stopped, then 0 V is written
(section 3.1).

### 11.2 Session (defence in depth)

The output is armed only inside `measure*`. **Every exit path, including an interrupt, switches
the output off**: MATLAB does not catch Ctrl+C (from the command window of `start_here.m` or
`examples/hardware_commissioning.m`, or the console of `start_tubebench.bat`) with `try`/`catch`;
only `onCleanup` objects run. `guardedAcquire` therefore creates an output guard
(`tim.app.outputGuard`) right after `armOutput(true)`; on destruction it calls `Gen.outputOff()`
and `armOutput(false)` unless it was dismissed just before the normal return or after the error
path switched the output off itself, so neither the normal path nor the error paths send an
extra `OUTP OFF`. Every error path switches the output off, stops the acquisition and keeps the
partial data (`s.LastPartial`, emergency file). On the abnormal end of an acquisition the output
goes off first, before the driver's stop sequence: the driver calls the `AbortFcn` the session
set at connect (section 8.1 rule 4, D24); the session's error path then disarms the source
(`armOutput(false)`), so the number of output-off commands is unchanged since the owner's
approval of 2026-10-11 - one of them moved before the stop request. This includes the time **between two
repetitions** of `measureSweep` / `measureStepped` (audit 2026-10-11): an error there - a Stop
seen by the next repetition's check, an instrument error of the frequency reset - disarms the
source (`armOutput(false)`, which also switches it off) and keeps the completed repetitions in
`s.LastPartial` and the emergency file; an `onCleanup` disarms the source on an interrupt
between two repetitions. Before the first repetition nothing is sent (the source was never
armed), so the fault-path bus traffic is unchanged.

The level equalizer of the stepped sine (1.6.0, WO-006; owner decisions 2026-11-04, section 13.5)
keeps these duties: the pre-measurement and the equalized measurement are both measurements of
`measure*` (`measureStepped`, `measureEqualizerPlan`) with the same error paths (a pre-measurement
that was recorded and then refused, or stopped while it was processed, is kept in `s.LastPartial`
and an emergency file too); the equalizer is
refused before anything is configured or armed when the source does not declare `levelWhileOn`,
or without a calibration or the geometry (`tim:session:equalizer`); no step is ever played above
the amplitude field (`excitation.stepped.amplitudeVpp`, the maximum), checked by the session
before `configureSine` and by the driver before every level command; the operator confirmation and
the loudspeaker power check use that maximum, asked once for the pre-measurement and the
measurement. A level change rides with the frequency change of its step: a lower level before the
new frequency, a higher one after it. With the equalizer off the stepped sine sends the same
commands in the same order as before 1.6.0 (the bus-traffic fixtures are unchanged).

### 11.3 Contract tests and test hooks

`tests/TestInstrumentContract.m` runs every registered driver in simulation mode on its mock
(through `tim.instr.create`) and observes the duties through the driver's static
`testHooks(obj)`, so no duty is tested for the 33220A only. The hooks (struct of function
handles):

| Role | Hook | Does |
|---|---|---|
| both | `traffic()` | the messages the (simulated) instrument received so far (cellstr) - for "sends nothing" and ordering checks |
| both | `breakLink()` | every further request fails (link lost, instrument switched off) |
| source | `outputOn()` | the true output state at the instrument, not through the driver |
| source | `levelHistory()` | every level the instrument was programmed to since creation [Vpp] |
| source | `forceOutputOn()` | switches the output on behind the driver's back |
| source | `forceLevel(vpp)` (optional) | programs a level at the instrument behind the driver's back (the `outputOn` re-check); absent for an output without a programmed level |
| source | `injectError()` | the instrument reports an error at its next command |
| acquisition | `stallAfter(n)` | from the next acquisition on, data stop after `n` samples (`Inf`: normal again) |
| acquisition | `injectChannelFault(c)` | from the next acquisition on, the device reports a fault on input `c` |
| acquisition | `isRecording()` | the device is recording |

Contract cases: identity, metadata (JSON-encodable) and capabilities complete and consistent; step
keys unique; output off after creation, after `close` and after a driver error; a level above the
limit reaches the instrument neither through `configure*` nor `outputOn`; `outputOn` only armed and
configured; sweep configuration round trip and invalid sweeps refused; after `forceOutputOn`,
an `'instrument'` read-back returns `true`; after `breakLink`, `outputOff` and `close` return
quickly without throwing; a second `close` sends nothing; `acquire` shape, rate, unit and
integrity fields; a channel fault appears in `integrity`; Stop during `acquire` (error unchanged,
device stopped, partial data, next `acquire` works); `AbortFcn` first on an `onBlock` error and on
a driver error; `close` from inside `onBlock`; `close` from `ProgressFcn` at each step of `prepare`
(nothing sent afterwards, `tim:instr:closed`); every acquisition driver, run with a separate
source on the same rig, records the excitation inside the record; the registry refuses an unknown
driver, a wrong role or pairing and an invalid driver configuration before any I/O, and reads
the legacy configuration keys; the product check names the product and the driver. With `simcombined` and the rig's
`OutputLog` (stage B): Stop during planning plays nothing, Stop during execution ends the output
within one block, an `onBlock` error after `outputOn` leaves the output off, the last output
value is 0 after a normal plan, a Stop in either pass, an `onBlock` error and `close` during
`acquire`, a device that stalls while the output plays leaves it at 0 V (stopped, then 0 V; the
template mock keeps its last value after a stop like an analog output), and `estimateSweepLaw`
of the played sweep is within tolerance. The block cases place their actions in multiples of the
driver's block (`settings.blockSamples`), and `TestInstrumentTemplates` also runs them for a copy
of `TemplateCombined` with a block of 4096 samples (review of 2026-10-11). The optional
`setAmplitude` (1.6.0): `levelWhileOn`, when present, is a logical scalar; a source without it
refuses `setAmplitude` with `tim:gen:unsupported` and programs nothing; a source that declares it
refuses it before `configureSine` and outside sine mode (`tim:gen:mode`) and for a level above the
limit, of 0 or below the minimum (`tim:gen:amplitude`, nothing reaches the instrument), and sets
the new level with the output state unchanged (`levelChangeOnlyWhereDeclared`); it changes the
level of a playing sine and keeps the output on - a block device at its planned sample and never
during the execution, `tim:gen:schedule` (`levelChangeWhileTheOutputPlays`); and every separate
acquisition, run on one rig with the first separate source that declares it, records the level
change (`levelChangeHeardInTheRecord`). These cases return early where they do not apply (no
assumption, so that `TestInstrumentTemplates` sees no incomplete case).

The configuration of the contract cases (`config(role, name)`) selects the driver for its role and
keeps the default driver of the other; since stage 6 an acquisition driver gets **its own input
defaults** (`describe().defaults.acquisition`, as a configuration file that only names the driver),
not the LAN-XI values of `tim.app.defaultConfig`, and a source without the load `'INF'` gets its
first load (D46; for the lab drivers and `simcombined` the values are the same as before).
`tests/TestInstrumentTemplates.m` copies the driver templates of `templates/instrument/` into a
temporary package folder, registers them for that test only and runs every parameterised case of
`TestInstrumentContract` with the templates as its parameters (`ExternalParameters`), plus their
own driver tests (D42).

## 12. Error identifiers

| Identifier | Raised by | Meaning |
|---|---|---|
| `tim:instr:unknownDriver` | registry | driver name not registered |
| `tim:instr:role` | registry | the driver does not have the role it is configured for, or the pairing is not allowed (section 9.1) |
| `tim:instr:missingProduct` | registry, `checkInstalled` | a required MATLAB product, support package or runtime is not installed or not licensed (hardware mode) |
| `tim:instr:simulationOnly` | registry | a simulation-only driver in hardware mode |
| `tim:instr:readback` | registry | a source without output read-back in hardware mode without `generator.allowUnconfirmedOff` |
| `tim:instr:closed` | driver | call after `close()`, or `acquire` ended by `close()` |
| `tim:instr:outputStopped` | block driver | `outputOff` during execution ended the acquisition early (section 8.3) |
| `tim:instr:connectionLost` | `checkConnection` | the connection is lost and could not be re-opened (1.2.1, section 2.2); nothing armed |
| `tim:scpi:connectionLost` | SCPI transport | the instrument (or the link) closed the connection; English text, marks the transport lost until `reopen()` |
| `tim:instr:noHooks` | `testHooks` | the object does not run on its protocol mock |
| `tim:config:driver` | `validateConfig`, `checkConfig`, registry | missing / unknown driver (a warning when only loading, section 9.2) |
| `tim:config:*` | `validateConfig`, `checkConfig` | a setting the driver does not support (a warning when only loading, section 9.2) |
| `tim:config:legacyField` (warning) | `migrateConfig` | old keys ignored or not moved (section 9.3) |
| `tim:config:misplacedSettings` (warning) | `loadConfig`, registry | driver settings in a section the driver never reads, e.g. `generator.<d>` of a combined driver (section 9.2) |
| `tim:gen:notArmed` | source | `outputOn` without `armOutput(true)` |
| `tim:gen:amplitude` | source | level above the limit (open circuit), not positive, outside the instrument's range at the load, or above full scale |
| `tim:gen:load` | source | a load setting the driver does not accept (33220A: not `INF` or 1-10000 Ω written as a number; 1.3.0) |
| `tim:gen:mode` | source | call not valid in the configured mode (unconfigured `outputOn`, `setFrequency` outside sine, `triggerSweep` outside sweep, a block source configured before any sample rate is known) |
| `tim:gen:sweep` | source | invalid sweep settings |
| `tim:gen:unsupported` | source | waveform or feature not in the capabilities (also `setAmplitude` of a source without `levelWhileOn`) |
| `tim:gen:verify` | source | read-back differs from the request |
| `tim:gen:schedule` | block source | level / frequency / trigger / `outputOn` during execution; `outputOn` / `triggerSweep` outside `acquire` |
| `tim:session:stopped` | session (`onBlock`, steps) | operator Stop; passes through drivers unchanged |
| `tim:session:equalizer` | session (1.6.0) | the stepped-sine equalizer refused: the source does not declare `levelWhileOn`, no calibration or geometry, no level from the pre-measurement, a step level above the amplitude field, or a plan that does not fit the session (`setEqualizerPlan`); nothing armed or nothing more played |
| `tim:equalizer:*` | `tim.app.equalizerPlan` | the plan of the equalizer cannot be made (`mode`, `levels`) |
| `tim:<driver>:*`, `tim:scpi:*` | driver | protocol and transport faults (e.g. `tim:lanxi:http`, `tim:scpi:timeout`, `tim:gen:scpiError`, `tim:<driver>:rate`); callers treat them as instrument faults |

## 13. Design decisions

### 13.1 Decisions

| # | Decision | Alternatives considered | Reason |
|---|---|---|---|
| D1 | Abstract handle classes with a common base `tim.instr.Instrument` | duck typing as today; structs of function handles; a separate interface for combined devices | MATLAB enforces abstract methods; `isa` documents the role; the common base lets one class take both roles without member conflicts (MATLAB multiple-inheritance rules) |
| D2 | The existing drivers **become subclasses** (`Keysight33220A < SignalSource`, `LanXi < Acquisition`) | thin adapter classes around them | every SCPI / REST command stays in the same method, so the bus traffic is identical by construction; the driver tests keep constructing them directly; `s.Gen.Identity`, `s.Daq.Teds`, `s.Daq.Http` stay reachable for scripts and tests |
| D3 | Class-level (static) `describe`, `capabilities`, `connectionSteps`, `checkConfig`, `fromConfig`, `testHooks` | instance methods only | the checklist, lamps, `validateConfig` and the drive estimate are needed before connecting |
| D4 | The session keeps its sample-count schedule; a combined block device runs it in a planning pass on the shared clock | a declarative excitation plan built by the session; device-specific `measure*` variants | no change to the measurement code and its Stop / output-off paths (the highest risk of the refactor, WO §6.2); identical bus traffic; one schedule for both kinds of device |
| D5 | Registry = one list file + a static factory per class | scanning `+tim/+instr` with `meta.package`; class names in the configuration | explicit and fast; a typo in the configuration gives a clear error instead of running arbitrary code |
| D6 | Role sections + `driver` + a sub-struct named after the driver; generic role settings stay outside; old files migrated on load | flat keys per driver; moving every acquisition key into the driver sub-struct | smallest change for the user: only the connection settings move; the acquisition settings mean the same for every DAQ, only their allowed values (and their defaults, D32) differ |
| D7 | `user_config.json` stays in the old layout | rewrite it in the new layout | it is the owner's lab file; loading it unchanged proves the migration every day. **Approved by the owner 2026-10-11**: it stays in the old layout until after the hardware check (WO §0.3, `docs/hardware_status.md`) and is then rewritten in the new layout - after that check, not before |
| D8 | Simulation: real drivers over protocol mocks + one contract-level combined driver | contract-level `SimulatedSource` / `SimulatedAcquisition` for the app tests (WO task 7 text) | the protocol-mock path is the only one that exercises the real drivers end to end (and the bus-traffic tests need it); the combined driver covers both contracts at contract level and the case change B asks for; a separate simulated pair would add code without new coverage. **Approved by the owner 2026-10-11** (WO §0 did not decide task 7). |
| D9 | Products checked by the registry before any I/O, in hardware mode only | let MATLAB fail with "Undefined function"; check in every mode | clear `tim:instr:missingProduct`; the base requirements stay MATLAB + Signal Processing Toolbox; a driver runs on its mock without its toolbox, so the contract tests pass on any machine (D30) |
| D10 | Session properties keep their names `Gen` and `Daq` (role names; one object for both roles when combined) | rename to `Source` / `Acquisition` | scripts, examples and many test lines use them; the names already describe roles |
| D11 | Device flags are worded by the driver (`integrity.channelFaults`) | flag codes interpreted by the session | the session holds no LAN-XI vocabulary and today's texts stay |
| D12 | Source impedance from the driver in the drive estimate and the operator texts | keep 50 Ω | the loudspeaker protection would under-estimate the power of a low-impedance source about 50 times |
| D13 | The calibration records the acquisition chain; unknown (old) calibrations and old measurement metadata give no warning | warn for every old calibration | `C_k` depends on the DAQ inputs; old lab calibrations and folders stay usable without noise |
| D14 | One interleaved bus log (SCPI, REST, stream) as the regression fixture | one log per instrument | also catches order changes between the instruments, e.g. `OUTP ON` before the recording has started |
| D15 | Output guard with `onCleanup` in the session; drivers stop with `onCleanup` | `try`/`catch` only (today) | MATLAB runs only `onCleanup` objects on Ctrl+C; without the guard the 33220A keeps driving the loudspeaker until the next connect |
| D16 | Plan only when one object takes both roles; every other acquisition driver is data-driven; `needsOwnSource` / `rolesTogether` checked by the registry | block mode as a property of the acquisition driver (stage-1 design) | with a separate source a planning pass runs the whole schedule before the first sample (a 33220A would be switched on and off before recording, `waitComplete(5)` would wait for the whole sweep), so the excitation would never be recorded |
| D17 | During planning `outputOff` is scheduled like every other call; only an error out of `onBlock` discards the plan; `isPlanning()` for wall-clock callbacks; `onBlock` keeps one input | "an `outputOff` during planning means nothing is played" (stage 1); a second `onBlock` argument | the session switches the output off from `onBlock` as the normal end of every excitation, so the stage-1 rule would never play anything; the session's nested `onBlock` functions take one input |
| D18 | "Output off" = no waveform, 0 V or disconnected; sample outputs write 0 V and fade plans to 0 | "stops the output" | an NI analog output can keep its last value after `stop`/`release`: a DC current through the voice coil with direct drive |
| D19 | Read-back kinds `'instrument'`, `'device'`, `'none'`; `'none'` only with `generator.allowUnconfirmedOff` in hardware mode | "must read back from the instrument" for every source | DAQ and audio outputs have no output state to query; a driver forced to throw would paint the lamp red after every Stop |
| D20 | Factory named `fromConfig`; base properties `SetAccess = protected`; no `delete` in the base class; `close` marks the object closed and a second `close` sends nothing | a static `create`; `SetAccess = private`; `delete` → `close` in the base | checked on R2022b: a static `create` next to `LanXi.create` gives `MATLAB:class:DuplicateMethod`; private base properties cannot be set by the drivers (`MATLAB:class:SetProhibited`); a base destructor runs after the subclass's and would repeat REST I/O at destruction (a time-out on an unreachable module) |
| D21 | Minimal contract: LAN-XI `shutdown`, the 33220A `Mode`, `MaxVpp`, `Load` are driver members, not contract; `minVpp`, `sweepTime`, step role `'both'` added | keep them in the contract | the session and the window do not need them after stage B (the session reads `cfg`; tests use only `OutputArmed`); the GUI amplitude lower limit (0.005 Vpk) is below the 33220A minimum (0.02 Vpp at INF) and was refused only at measure time |
| D22 | Generic field `info.dataUnit` (`'V'` or `'FS'`), not `info.unit` | the review's `info.unit` | the LAN-XI `info.unit` is a per-signal cell from the stream, already stored in saved measurements and read by `tim.val.testA_acquisition`; giving one field two types would break readers |
| D23 | `levelKnown` + measured `vppAtFullScale` (no default) for full-scale outputs | a static `maxVpp` for every source | the volts of an audio output depend on the device and its knob; without a measured conversion the amplitude limit and the power check protect nothing |
| D24 | Abort hook as the property `AbortFcn` | a fourth `acquire` argument `onAbort` | set once at connect, so direct callers of `acquire` (`tim.val.channelIdentification`) are covered too. The driver side is implemented in stage A (no traffic change while `AbortFcn` is empty); the session was to set it only after the owner approved, because it moves `OUTP OFF` before the REST stop on the abnormal end of an acquisition (fault fixture update). **Approved by the owner 2026-10-11**: the session sets it at connect for every driver pair (section 8.1 rule 4), the fault fixture is regenerated from the code |
| D25 | Re-entrant `outputOff` / `close` / `setTimeout`; `close` during `acquire` → `tim:instr:closed` | specify `onBlock` re-entry only | window callbacks run during every `pause` / `drawnow` inside a driver; a released System object would otherwise set itself up again and keep playing |
| D26 | Exact sample rate or `tim:<driver>:rate`; the rate list or range is a capability; `checkConfig` refuses rates the device cannot run exactly | a static `isRateExact(fs)` member as the review proposed | `checkConfig` is already the static place that validates the driver's settings; one member less |
| D27 | Rig `respond(x)` + `OutputLog`; `setGeneratorState` only for the 33220A mock | every source maps its state onto the 33220A fields | a sample-buffer mock cannot express its output as a 33220A state; generic safety assertions need what was really played |
| D28 | Static `testHooks(obj)` per driver (simulation only) | driver-specific contract tests | without generic hooks the duties of §11 could only be tested for the 33220A |
| D29 | Unknown driver: warning on load, error at Connect; since the review of 2026-10-11 also a driver in a role it does not have and a value outside the selected driver's limits | error in `validateConfig` (stage 1); errors for limit violations also on load (as built until the review) | saved folders of other labs and scripts that only reprocess must keep loading, and so must files that 1.1.0 accepted and wrote (WO §4 acceptance) |
| D30 | Products as `name` + `feature`, hardware mode only; optional `checkInstalled()` for support packages and runtimes | `ver` names in every mode | `license` needs feature names; support packages and vendor runtimes are no MATLAB products; mocks need no toolbox |
| D31 | Second bus fixture for the fault paths, recorded before stage A on the pre-refactor code | normal-path fixture only | the fault paths (error, Stop, cancel, power refusal, fast close) are the highest refactor risk and can be recorded on the old code only once |
| D32 | Empty generic acquisition values mean the driver default; `ccld` / TEDS policy in `checkConfig` | LAN-XI values as generic defaults | a file that only names another DAQ must not fail on `'10 Vpeak'` / `'0.7 Hz'` |
| D33 | A swept sine with the configured spacing is a Must for a source | any one waveform | the switching calibration and Test E always sweep, and the calibration method must not change |
| D34 | One `migrateConfig`; legacy keys move only to the legacy driver | migration inside `loadConfig` only | configs built in code would be ignored silently; a changed driver name must not inherit the 33220A address silently |
| D35 | Waveform definitions in the contract (section 3.3) | "single sweep" without a law | the sweep gate, the sweep-law check and the power check rely on them; another generator may add hold / return times or end `*OPC?` early |
| D36 | Block source outside `acquire` specified (section 3.5) | planning and execution only | the session and the contract tests call the source outside `acquire` |
| D37 | `tim.app.outputGuard` in stage B | stage A | stage A does not change the session (stage plan); the guard is the first change of stage B |
| D38 | Stage A: the registry reads the legacy keys itself | `migrateConfig` in stage A | the configuration code changes in stage B; the registry must already work with every configuration of today |
| D39 | Window texts from two short driver texts, `texts.noun` and `texts.closed` (stage C) | compose the sentences from the display names (stage plan); from the lamp labels | the display names are long and name the protocol ("HBK LAN-XI module (Open API)"), the lamp labels are capitalised or plural ("Inputs"); with a noun and a closed state the operating-mode, Connect and Disconnect tooltips read exactly as before for the two lab drivers (the closing dialog and the Disconnect log line nearly so: "Closing the connections: generator output off, LAN-XI module back to Idle …") and correctly for a combined device |
| D40 | Identity display: an "In use" row in INSTRUMENTS (one line per instrument) and an Instruments table in Setup > Connection, plus the lamp tooltips; "(simulated)" in simulation mode | tooltips only; an identity panel in place of the checklist | visible at a glance without hovering, the table has room for vendor, firmware and the settings; the LAN-XI mock reports the lab module's real serial number, which must not look like a connected instrument. The control panel still fits the 1920 × 1080 lab screen (about 920 px of content since the "In use" row holds three lines - review of 2026-10-11: a display name that wraps hid the second instrument -, limit 930) |
| D41 | GUI limits of the EXCITATION fields from `capabilities()`; no sample-rate or range control in the window | keep 0.45 × sample rate and 0.005 Vpk; add selectors for sample rate and range | one rule for the window and `checkConfig`, so the window no longer accepts a level the source refuses only at measure time (33220A: 0.02 Vpp at `INF`); the input settings stay in the configuration (the window shows them and the allowed values, section 7.1) |
| D42 | Templates are complete drivers of imaginary instruments that pass the contract tests on their own mocks (`tests/TestInstrumentTemplates`); every instrument fact is a line marked `TODO` | skeletons with empty methods; templates that are not run | a person starts from code that is known to meet the contract, and only replaces facts; a template that is never run breaks unnoticed; the `TODO` markers and the guide's "no `TODO` left" check make every placeholder visible (stage 6) |
| D43 | The demo source `demo` stays registered, simulation only (`describe().simulation = 'only'`) | remove it after the dry run; keep it in `tests/support` | the guide's worked example stays checked by the contract tests and visible in the registry; `'only'` keeps it out of hardware mode (registry check 4). **Approved by the owner 2026-10-11** |
| D44 | The mock of a separate function generator couples to the rig through `setGeneratorState` (the rig's function-generator model); `respond(x)` for sample-producing sources (revises D27's "only for the 33220A mock") | a new rig coupling for every separate source | `generate(n)` already models a separate generator on its own clock (stepped sweep, trigger latency, clock offset) with generic quantities (function, frequency, Vpp, sweep, output); no change to the rig, the 33220A path or its bus traffic |
| D45 | A driver's defaults only in `describe().defaults` (settings and inputs), not in `tim.app.defaultConfig` | WO §5.3 "defaults in `defaultConfig`" | as built since stage B (D6, D32): `defaultConfig` holds the default drivers' sub-structs; `loadConfig` / `migrateConfig` merge any registered driver's sub-struct onto its own defaults. **Approved by the owner 2026-10-11** |
| D46 | The contract tests give an acquisition driver its own input defaults | keep the LAN-XI input values of `defaultConfig` | found while running the acquisition template: a DAQ without `'10 Vpeak'` / `'0.7 Hz'` failed `checkConfig` before any duty was tested - the test, not the contract, was shaped like the LAN-XI |
| D47 | Acquisition and combined templates talk to the device through a small device-session object (`identify`, `configure`, `start`, `read` / `playRecord`, `stop`, `writeZero`, `close`) - a thin hardware class around the vendor interface, or the mock | the vendor interface (`daq`, `audioPlayerRecorder`) called directly in the driver | the driver reads the same on the hardware and on the mock; the mock emulates a few methods instead of a toolbox object; the toolbox is needed only by the hardware class (D9) |

### 13.2 Design review of 2026-10-11 (stage 2)

All 24 issues are accepted; where the resolution differs from the proposed fix the reason is in
the decision named.

| # | Issue | Resolution | Where | Stage |
|---|---|---|---|---|
| 1 | Ctrl+C leaves the output on | session output guard; rules "every exit path including an interrupt" | 4, 11.1 (7), 11.2, D15, D37 | B (guard), A (drivers) |
| 2 | Planning pass contradicts the session schedule | `outputOff` scheduled; only an `onBlock` error discards; rule 1 per pass; `isPlanning()`; one `onBlock` input | 8.1, 8.3, D17 | B |
| 3 | Block acquisition belongs to the pair | plan only for one object in both roles; `needsOwnSource`, `rolesTogether`; registry refuses pairings | 1, 5, 8.2, 9.1, D16 | A (registry), B (test) |
| 4 | Output off undefined for analog outputs | off = 0 V or disconnected; 0 V writes, fade | 3.1, 11.1 (1, 12), D18 | B (simcombined), Part 2 |
| 5 | Read-back excludes DAQ / audio outputs | kinds `instrument` / `device` / `none`; window wording; `allowUnconfirmedOff`; WO §3 reworded | 3.2, 5, 9.1, D19 | A (registry), B (window) |
| 6 | Amplitude limit meaningless for full-scale outputs | `levelKnown`, `vppAtFullScale` | 3.4, 5, 9.2, D23 | A (capability), Part 2 |
| 7 | Output off only after the driver's stop sequence | `AbortFcn` called first; set by the session at connect (approved by the owner 2026-10-11) | 4, 8.1 (4), 11.1 (8), D24 | A (driver); session 2026-10-11 (approval) |
| 8 | MATLAB class mechanics | `fromConfig`; protected base properties; no base `delete`; second `close` sends nothing | 2, D20 | A |
| 9 | Re-entrant calls | re-entrancy rules; `close` during `acquire` → `tim:instr:closed` | 2.2, 4, 8.1 (5), D25 | A |
| 10 | Block source outside `acquire` | specified | 3.5, 8.3, D36 | B |
| 11 | Volts not possible for audio inputs | `dataUnit` `'V'` / `'FS'`, `voltsAtFullScale` | 4.1, 4.2, D22 (field name changed) | A (LAN-XI field), B (session) |
| 12 | Sample-rate coercion | exact rate or `tim:<driver>:rate`; `sampleRateRange`; fs mismatch fatal for every driver | 4, 4.1, 5, D26 (no `isRateExact` member) | A (contract test), B (generic check) |
| 13 | LAN-XI defaults as generic defaults | empty = driver default; `ccld` / TEDS policy; settle text from the driver | 2.1, 6, 9.2, D32 | B |
| 14 | Simulation coupling shaped like the 33220A | `respond(x)`, `OutputLog` | 10, D27 | B |
| 15 | Contract tests cannot observe the duties | `testHooks` | 11.3, D28 | A |
| 16 | Bus baseline covers the normal path only | fault-path fixture recorded before stage A | Appendix B, D31 | done (dba0bd8) |
| 17 | Calibration context vs old measurement metadata | unknown = no warning both ways; text comparison; settings from `meas` | 7, D13 | B |
| 18 | Unknown driver blocks analysis-only use | warning on load, error at Connect | 9.2, D29 | B |
| 19 | Product check | hardware mode only; `name` + `feature`; `checkInstalled()` | 2.1, 5, 9.1, D9, D30 | A |
| 20 | Waveforms not defined precisely | waveform definitions; "exact on the device timeline" | 3.2, 3.3, D35 | A (contract), B (sweep-law test) |
| 21 | Calibration requires a sweep | Must in WO §3 and `checkConfig` | 5, 9.2, D33 | B |
| 22 | Migration edge cases | one `migrateConfig`; legacy keys only to the legacy driver | 9.3, D34 | B |
| 23 | Inventory gaps; D8 undecided | `ampDirect` and the `driveEstimate` help added to Appendix A; D8 recorded as owner decision | A.3, D8, D12 | B |
| 24 | Minimality | `shutdown`, `Mode`, `MaxVpp`, `Load` out; `minVpp`, `sweepTime`, step role `'both'`, card refresh after `'prepare'` steps | 3, 4, 5, 6, D21 | A (contract), B (cards), C (GUI limits) |

### 13.3 Review of the implementation (2026-10-11, fix stage)

Three independent reviews (safety / bus, compatibility / contract, usability / documentation) of
the code as built; every finding was reproduced or checked in the code first.

| # | Finding (severity) | Resolution | Where |
|---|---|---|---|
| 1 | Stop or an error during the LAN-XI connect step after `module/info`: the object was dropped and the module not returned to Idle (low) | `LanXi.fromConfig` returns the module to Idle (status request, Idle if needed, 2 s time-out) before the error propagates. The status request now comes before the generator's close lines (the e8fb4fb code sent it from the window's `close(true)`, after them): an intended change of order, checked against an explicit list; both fixtures unchanged | `LanXi.m`; `TestBusTraffic/stopDuringConnectReturnsTheModuleToIdle` |
| 2 | `close()` from `ProgressFcn` during `prepare` (window closed during the TEDS step): the LAN-XI driver sent the TEDS requests to the closed module (low) | closed check after every step report and in the TEDS poll; a TEDS failure no longer hides `tim:instr:closed`; the same check in `simcombined` and the templates | 2.2, 11.1 duty 9; contract case `closeFromProgressDuringPrepare` (every step) |
| 3 | Files that 1.1.0 accepted and wrote no longer loaded (a level below the generator minimum - the 1.1.0 window wrote 0.01 Vpp -, `maxVpp` up to 20 Vpp at load `'50'`, a sweep over 500 s, connector `''`): the window did not start, Open measurement dropped "use the saved set-up" (medium) | loading only warns about driver limits (D29 extended); errors in the session (constructor and setters), the registry and the connected window; the generator minimum is checked for the swept sine and the selected signal only (another level is refused when played); LAN-XI connector `''` accepted (no `ConnectorSelect`, as 1.1.0). Not taken: `''` as "driver default" in `settingsFrom` - it would send `ConnectorSelect BNC` where 1.1.0 sent nothing, and turn an empty address into the default address | 9.2; `validateConfig`, `SignalSource.checkSourceConfig`, `LanXi.checkConfig`; `TestConfiguration/filesOfVersion110StillLoad`, `TestGui/fileOfVersion110WithLevelsBelowTheMinimum` |
| 4 | Section 9.3 rule 2 contradicted `migrateConfig` (low) | text corrected (the keys always move to `generator.keysight33220a`) | 9.3 |
| 5 | Section 1 showed the session setting `AbortFcn` (low) | marked as planned (D24); the session sets it since the owner's approval of 2026-10-11 (section 13.4) | 1 |
| 6 | `TemplateCombined`: a device error while the output played skipped the 0 V write (fade and 0 V in one `try`); 0 V was never written after the stop (high) | `endOutput`: the rest of the fade, the stop, then 0 V - separate steps, each tried; 0 V after the stop on every end, the normal one included; `isOutputOn` true when 0 V could not be written; the template mock keeps its last value after `stop` and `close`; `simcombined` in the same order; guide step 10: 0 V DC at the output terminal | 3.1, 3.5, 11.1 duty 12; contract case `deviceStallWhilePlayingLeavesOutputAtZero` |
| 7 | The block cases of the contract tests assumed B = 2048: a combined driver with another block failed 4 cases (medium) | actions in multiples of the driver's block (`settings.blockSamples`, `planUnit`); `TestInstrumentTemplates` runs them for a copy of the template with 4096 | 8.3, 11.3 |
| 8 | No usable guidance for the device session of an NI device (queued output, Stop latency, underrun, 0 V after stop) (medium) | guide section 4.1, the queued-output note in 8.3, a class-load check of the session in step 9, a table for function-call interfaces in `ref_template.md`. Guidance only: there is no NI device in the lab | 8.3; guide 4.1, 9, 10 |
| 9 | Settings of a combined driver in `generator.<driver>` were silently ignored; the templates' default address `Dev1` (medium) | warning `tim:config:misplacedSettings` (`loadConfig`, registry); `vppAtFullScale` worded for a combined driver; `config_snippet_combined.json`; the templates' address has no default and is required in hardware mode | 3.4, 9.2; guide 6 |
| 10 | The "In use" row (two lines) hid the second instrument when a display name wrapped (low) | row of three lines; guide: `displayName` at most about 50 characters | 7.1, D40 |
| 11 | Documents inconsistent in four places (low) | WO §5 item 3 (defaults in `describe()`, D45), the reference to 3.4, the `maxVpp` wording of guide step 10, the README status date | - |
| 12 | NI suitability: the IEPE current and the support-package check left open (low) | the Must item names the microphone data sheet; a commented `checkInstalled` skeleton in the acquisition and combined templates | guide 2, 4 |

### 13.4 Owner decisions of 2026-10-11

The owner approved every pending recommendation on 2026-10-11. The owner's hardware check (WO
§0.3, `docs/hardware_status.md`) passed on 2026-10-12, and `wo-001` was merged into `main` as 1.2.0.

| Item | Decision - approved by the owner 2026-10-11 | Status |
|---|---|---|
| D7 | `config/user_config.json` stays in the old layout (`formatVersion` 1) until after the hardware check; then it is rewritten in the new layout | old layout kept until the hardware check; **rewritten in the new layout on 2026-10-12**, after the merge of 1.2.1 (same configuration, no warning) |
| D8 | simulation through the real drivers over their protocol mocks plus the contract-level combined driver `simcombined`; no contract-level `SimulatedSource` / `SimulatedAcquisition` | as built |
| D24 | the session sets `AbortFcn = @() Gen.outputOff()` at connect for every driver pair (a combined device: its own re-entrant `outputOff`, section 8.3) | done: `MeasurementSession.connect` (`setAbortHook`), cleared by `close`; after `acquire` returned with an error the session disarms the source; fault fixture regenerated from the code (Appendix B); tests `TestBusTraffic/outputOffBeforeTheStopOnAnAbnormalEnd`, `TestEndToEnd/combinedDeviceStopsItsOutputFirstOnADeviceError` |
| D43 | the demo source `demo` stays registered, simulation only | as built |
| D45 | a driver's defaults only in its `describe().defaults`, not in `tim.app.defaultConfig` | as built |
| Fault-fixture scenario "window closed twice inside a sweep" | the measurement ends with `tim:instr:closed`, without the status request the code before WO-001 sent after its error (the hand edit of stage B, section 14) | recorded from the code in the regenerated fault fixture; no hand edit left |
| Bus order after a Stop during the LAN-XI connect step | the driver returns the module to Idle (status request) before the generator's close lines (section 13.3 #1) | as built; checked by `TestBusTraffic/stopDuringConnectReturnsTheModuleToIdle` |

### 13.5 Owner decisions of 2026-11-04 (WO-006, 1.6.0)

The level equalizer of the stepped sine (`docs/workorder_equalizer.md`) grows the contract by one
**optional** capability, so every existing driver and every driver written with the guide stays
valid.

| Item | Decision - owner 2026-11-04 | As built |
|---|---|---|
| Method | `setAmplitude(vpp)` on `tim.instr.SignalSource`: sine only, output state unchanged, the level checked before the command (`tim:gen:amplitude`); the base class raises `tim:gen:unsupported` | section 3.2; the base class sends nothing |
| Capability | `capabilities().source.levelWhileOn`, default `false`; a driver without the field counts as `false` | `tim.instr.SignalSource.levelWhileOn(source)`; section 5 |
| A source without it | the equalizer is refused with a clear error before anything is armed (no switching of the output at every step) | `tim:session:equalizer` naming the display name |
| 33220A | implements it: `VOLT` while the output is on, read back like its other level commands; the mock and the virtual rig follow a level change during an acquisition | `VOLT` with six significant digits, `SYST:ERR?`, `VOLT?` (`docs/ref_33220A_scpi.md`); the relay glitch is the hardware check WO-006 section 6 item 1 |
| `simcombined` | implemented where its planned output allows a level per step | `levelWhileOn` true: a `level` event of the plan, scheduled like `setFrequency`, `tim:gen:schedule` during the execution |
| Demo, templates | declare `false` (they inherit the refusal) | the templates mark it `TODO`, so a new driver decides it from its manual |
| Bus traffic | the recorded fixtures stay unchanged: the default path (equalizer off) never uses it | the off path of `measureStepped` sends the calls of 1.5 in their order (`TestEqualizer/offPathUnchanged`); no fixture added or regenerated |

## 14. Implementation plan

Each stage ends with the full test suite and both bus-traffic fixtures passing unchanged (the
fixtures are never regenerated during WO-001 except for an owner-approved change of order, D24 - the fault fixture was regenerated on 2026-10-11, section 13.4).

**Stage A - contract, existing drivers, registry, contract tests (WO tasks 1, 2, 8 and the
registry).** Done on `wo-001` (stage 3 of the work order): both bus fixtures unchanged; the
LAN-XI connect steps exist twice (`LanXi.fromConfig` and still `MeasurementSession.connect`)
until stage B switches the session to the registry.

1. `tim.instr.Instrument`, `SignalSource`, `Acquisition` (abstract; help text = sections 2-4).
2. `Keysight33220A < SignalSource`: static members (`fromConfig` builds the transport or its mock
   and reports the step `gen`); `identity`, `metadata`, `setTimeout` (transport),
   `isOutputOn(timeout)` (same `OUTP?` query); `OutputArmed` from the base. No other method body
   changes.
3. `LanXi < Acquisition`: static members; `fromConfig` takes over the connect steps `lanxi` / `idle`
   (same requests in the same order); `identity` from `module/info`; `metadata`; `recent` (parser
   tail), `isAcquiring`, `isPlanning` (`false`), `rawBytes`, `setTimeout` (HTTP); `close` =
   `shutdown` + closed (second `close` sends nothing); `acquire` calls `AbortFcn` first on an
   abnormal exit and ends with `tim:instr:closed` after `close`; `info.dataUnit`,
   `integrity.channelFaults` from the DataQuality events; `prepare` still accepts `c.connector`;
   `SampleRate`, `Teds`, `ProgressFcn` from the base. Nothing changes on the bus while `AbortFcn`
   is empty and `close` is not called.
4. `tim.instr.drivers`, `driverInfo`, `create` with the checks of section 9.1 (legacy keys, D38).
5. Mocks: `Broken` link in `MockScpiTransport` and `MockLanXiHttp`, an INVALID channel flag in
   `MockLanXiStream`; `testHooks` of both drivers.
6. `tests/TestInstrumentContract.m` (section 11.3, without the `simcombined` / `OutputLog` cases;
   one object in both roles checked with the unregistered stub `tests/support/CombinedStub.m`);
   `TestBusTraffic/registryConnectSendsTheSame`: a registry connect sends the connect section of
   the bus fixture and reports the same checklist steps as `MeasurementSession.connect`.
   The session, the window and the configuration are not touched in stage A.

**Stage B - configuration, session, metadata, calibration, contract-level simulation (WO tasks
3, 4, 6, 7).** Done on `wo-001` (stage 4 of the work order), with these differences from the plan:

* Step 1: the output guard is in place; `AbortFcn = @() Gen.outputOff()` was **not** set by the
  session in stage B - it awaited the owner's approval (D24), and the fault fixture kept the old
  order after a stalled stream. Approved by the owner on 2026-10-11: the session sets it at
  connect and the fault fixture was regenerated from the code (section 13.4).
* Step 3: closing the session uses the contract `close()` of each instrument, so closing the
  window inside a sweep ends the measurement with `tim:instr:closed` as planned in Appendix B. The
  fault fixture was edited by hand in that one scenario (the outcome line, and the status request
  the old code sent after the error to the module that was already Idle); every SCPI command and
  the REST return-to-Idle sequence are unchanged. The normal-path fixture is unchanged. The owner
  approved this scenario on 2026-10-11; the fault fixture was then regenerated from the code
  (D24), with no hand edit left, and this scenario came out exactly as edited.
* `tim.instr.create` checks 4-7 for both roles before the first instrument is opened.
* The window parts the combined device needs (checklist and lamps from `connectionSteps`, step
  `role`, channel cards without TEDS, `isAcquiring`, `recent`, `isOutputOn(1)` worded by the
  read-back kind) moved from stage C to here; its texts, lamp labels and tooltips stay for stage C.
* `examples/hardware_commissioning.m` still reads `s.Gen.Identity` and `s.Daq.Info` (members of the
  two lab drivers; it runs only on them): moved to stage C with its texts.
* Configurations built in code: a new key that still holds the driver default yields to an old
  key set by the script (section 9.3, rule 4), so old scripts keep working on `defaultConfig`.
* `tim.cal.calibrationContext`: for measurement metadata without a `driver` (before 1.2.0) the
  driver is not compared, the module model and serial number are (as text), as are the input
  settings; a calibration without `meta.acquisition` gives no DAQ warning at all.
* `generator.allowUnconfirmedOff` is in `defaultConfig` (false) and checked by `validateConfig`.

Verified at the end of stage B (simulation only): full suite 267 / 267; the normal-path bus
fixture unchanged; `config/user_config.json`, `example_config.json`, `sim_thin_screen.json` and
`e8fb4fb:config/user_config.json` load to the same effective settings as with the e8fb4fb code
(compared in a temporary worktree; the new layout only adds the driver keys and
`allowUnconfirmedOff`); the six saved measurement folders under `data/` open and reprocess in a
hidden window without an error and stay unchanged, and the lab calibration files give no DAQ
warning against them.

1. Session safety first: `tim.app.outputGuard` in `guardedAcquire` with a unit test (destroying
   the guard before it is dismissed switches the mock output off and disarms it); after the
   owner's approval `AbortFcn = @() Gen.outputOff()` and the fault fixture updated (done
   2026-10-11, section 13.4).
2. `defaultConfig` formatVersion 2; `tim.app.migrateConfig` (9.3); `validateConfig` generic +
   `checkConfig`, unknown-driver warning, `validateConfig(cfg, 'instruments')`; empty acquisition
   values = driver defaults; `driveEstimate` and `ampDirect` from `outputImpedance_ohm`;
   `example_config.json`, `sim_thin_screen.json` converted; tests: old `user_config.json` = new
   layout, saved `config.json` loads, unknown driver loads with a warning.
3. `MeasurementSession`: `ctx` + registry; no instrument names (`grep -i "lanxi\|lan-xi\|33220"`
   empty); `Http` property removed (the stream fault injection in `TestEndToEnd` uses
   `s.Daq.Http`); `signalCheck` from `integrity` (`channelFaults`, `peakFractionOfRange`);
   `meas.unit = info.dataUnit`; generic fs integrity check; `close(true)` via `setTimeout` and
   `close`; log lines from display name and identity.
4. `collectMetadata` from `metadata()`; `cal.meta.acquisition`; `calibrationContext(cal, cfg,
   meas)` (section 7), tested with a measurement saved by the e8fb4fb code.
5. Rig `respond(x)` and `OutputLog`; `tim.sim.SimulatedCombined` (`simcombined`): registered, in the
   contract tests (planning cases, 0 V cases, sweep law), calibration + measurement through the
   session and the hidden window with no driver-specific code there; pairing refusals.
6. `tim.val.testA_acquisition` without LAN-XI parser fields; `channelIdentification` countdown
   idle while `isPlanning()`; examples use `identity()` / `metadata()` instead of `s.Daq.Info`.

**Stage C - window from the drivers, documentation (WO tasks 5, 9).** Done on `wo-001` (stage 5
of the work order), with these differences from the plan:

* Items 1 and 3 were done in stage B except the texts, lamp labels, tooltips and the GUI limits,
  which stage C added (section 7.1).
* The texts are composed from two new `describe()` fields, `texts.noun` and `texts.closed`
  (D39), not from the display names; the contract test checks them for every registered driver.
* The identity display is an "In use" row in INSTRUMENTS and an Instruments table in
  Setup > Connection besides the lamp tooltips (D40); the table also shows the configured
  settings and, in its tooltip, the values the drivers allow - the window has no sample-rate or
  range control (D41).
* Also changed: the Formula view and the calibration prompt `calPrepare` (en / ko) say "DAQ
  input(s)"; `examples/hardware_commissioning.m` stores `metadata()` of both instruments in its
  H0 report (it runs with any driver; not run here, it needs the instruments); comments in
  `start_here.m`, `bench_test_no_tube.m`, `switchingCorrection`, `resolveSensitivities`.
* Not changed: `examples/bench_test_no_tube.m` keeps its notes on the 33220A's 50 Ω output (it is
  the lab's bench test); `docs/theory.md` and `docs/calibration_procedure.md` keep describing the
  lab's chain (LAN-XI input), except the prompt text quoted in the procedure.

Verified at the end of stage C (simulation only): full suite 270 / 270 in batch MATLAB (19 test
classes; the three new `TestGui` tests and the `texts` check of the contract test included); the
grep acceptance for `Tubebench.m` and `MeasurementSession.m` as a test; both bus-traffic fixtures
unchanged in stage C; the layout on screen captures of a visible window (separate MATLAB process,
simulation configuration, both driver selections) before and after Connect: the control panel
fits without scrolling, the Instruments table shows two rows (one for `simcombined`) without
cut-off text on the 1920 × 1080 screen.

The plan of stage C:

1. Checklist keys and labels from `connectionSteps` (+ the session's steps); lamp labels,
   tooltips and the lamps of each step from the driver (`'both'` drives both); channel cards
   refreshed after every `'prepare'` step; texts composed from the display names, so they read as
   today for the two existing drivers.
2. Identity display: INSTRUMENTS lamps and Setup > Connection show the display name, model, serial
   and firmware of each role; no selection controls (owner decision §0.2).
3. Live view via `s.Daq.recent`, background-work check via `isAcquiring`, output state via
   `s.Gen.isOutputOn(1)` worded by the read-back kind (section 3.2); GUI amplitude and sweep-time
   limits from `minVpp` / `sweepTime`; `grep` acceptance for `Tubebench.m`.
4. Docs: this document (status: implemented), user guide (choosing instruments in the
   configuration, identity display), installation guide (products per driver), README structure
   and test count, operator texts in `tim.app.msg` ("LAN-XI inputs" → the DAQ inputs).

**Part 2 - guide, templates, skill, dry run (WO §5, §0 change A).** Done on `wo-001` (stage 6 of
the work order):

* `docs/adding_an_instrument.md`: the step-by-step guide for a person without Claude Code - facts,
  suitability (the requirements table of WO §3, copied), templates, driver, protocol mock,
  settings, reference document, registry, offline tests, the hardware ladder (a)-(d) with the
  owner, documents, the safety rules, the worked example and a checklist. It carries the
  full-scale (`vppAtFullScale`) and 0 V rules of sections 3.1 and 3.4.
* `templates/instrument/`: driver templates for a source (request / response), an acquisition
  (streaming) and a combined block device, one protocol mock and one driver test for each, a
  reference document and a configuration snippet; outside the package folders and not on the
  path. They run as they are and pass the contract tests on their mocks
  (`tests/TestInstrumentTemplates`, D42, D47).
* `.claude/skills/add-instrument/SKILL.md`: runs the guide and repeats the rules of WO §5; it holds
  nothing the guide lacks.
* Dry run: the demo source (`demo`: `tim.instr.DemoSource`, `MockDemoSource`,
  `tests/TestDemoSource.m`, `docs/ref_demo_source.md`) was made by following the guide literally;
  it passes the contract tests (also the version before stage 6) without a change to the session or
  the window (`git diff --stat`: the new files and one line in `drivers.m`), and runs a
  calibration and a measurement in the hidden window. The guide and the templates were corrected
  where the dry run found them unclear or wrong (guide section 13).
* Found on the way: the contract tests gave every acquisition driver the LAN-XI input values
  (D46); the rig's generator coupling is documented for any separate generator mock (D44).

Verified at the end of Part 2 (simulation only): full suite 291 / 291 in batch MATLAB (21 test
classes: `TestDemoSource` and `TestInstrumentTemplates` new, 11 contract cases for `demo`); both
bus-traffic fixtures unchanged; the templates and the demo files give only the Code Analyzer's
"extra comma" messages of the one-line `try` (the project's style). The owner's hardware check
(§0.3) follows.

**Fix stage - review of the implementation (2026-10-11).** Twelve findings of three reviews,
resolved as listed in section 13.3. Each was first reproduced in simulation (or checked in the
code); the new tests fail on the code before the fixes (checked in a temporary worktree of
f892d19 with the new tests: `closeFromProgressDuringPrepare` for `lanxi`, `simcombined` and the
templates, `deviceStallWhilePlayingLeavesOutputAtZero` for the combined template, the misplaced
settings of the combined snippet). The bus traffic of the normal path and of the recorded fault
paths is unchanged; the one intended change of order (a Stop during the LAN-XI connect step) is
checked by its own test (order approved by the owner 2026-10-11, section 13.4).

Verified at the end of the fix stage (simulation only): full suite 299 / 299 in batch
MATLAB (21 test classes); `TestBusTraffic` 5 / 5 with both fixtures unchanged; no new Code Analyzer
message in the changed files; `config/*.json` and the `config.json` of the five saved measurement
folders under `data/` load without a warning (read only). The owner's hardware check (§0.3) is the
next step (`docs/hardware_status.md`).

**Owner decisions of 2026-10-11 (section 13.4).** D24 implemented (the session sets `AbortFcn`
at connect and clears it at close; the error path disarms the source after `acquire` returned);
the fault fixture regenerated with `TestBusTraffic.writeFixture('faults', note)` and compared
line by line with the previous file: the only traffic change is one `OUTP OFF` moving before
`REST PUT /rest/rec/measurements/stop` in the stalled-stream and the Stop scenarios; the
hand-edited closing scenario comes out of the code unchanged. The new tests fail on the session
code before the change (old file first on the path in a scratch folder). Verified (simulation
only, 326 tests in 21 classes): `run_tests('fast')` 289 / 290 - `TestGui/closeDuringMeasurementStopsFirst`
exceeded its 20 s wall-clock limit by 0.14 s on the loaded laptop and passed 3 / 3 when repeated
alone (it passed in the fast run before, on the same code but a comment) -, `TestEndToEnd` and
both app simulations 36 / 36; `TestBusTraffic` 6 / 6 with `bus_traffic_sim.txt` unchanged byte for
byte. The instruments were not connected; the hardware check follows.

**Review of the owner-decision stages (2026-10-11).** Four findings, none in the contract, the
drivers or the bus traffic (both fixtures unchanged); the decisions of section 13.4 stand. The one
on this interface: `TestGui/closeDuringMeasurementStopsFirst` now requests the close from the
session's block callback inside repetition 1, so the window's close runs the D24 path of a
running acquisition (the stop of the acquisition, its error path, then the closing steps); before,
its timer fired while the window was still preparing the measurement. The hardware check in
`docs/hardware_status.md` (ten steps) includes the D24 order at a Stop and at a close during a
measurement. Verified (simulation only): `run_tests()` 337 / 337 (22 classes) in one batch MATLAB.

## Appendix A - Inventory of the instrument-specific code before WO-001 (commit 8ff47f3)

Line numbers as of 8ff47f3. "→" names the stage that changed it; every item is done (stage C
completed the window texts, `msg` and the examples; the 33220A / LAN-XI texts left in `examples/`
and in the driver-specific help of `+tim/+app` and `+tim/+acq` describe those drivers).

### A.1 `tim.app.MeasurementSession`

| Lines | Use | → |
|---|---|---|
| 6, 10-11, 15, 513, 686 | help / comments name LAN-XI, `MockScpiTransport`, `MockLanXiHttp` | B |
| 27-30 | properties `Gen`, `Daq`, `Rig`, `Http` (`Http` = LAN-XI REST client or its mock) | B: `Http` removed |
| 50-52 | `ProgressCallback` doc lists the keys `gen, lanxi, idle, open, teds, setup` | B |
| 77-78 | step `gen`: `'simulated generator'`, `'%s:%d (SCPI over TCP)'` from `generator.host/port` | A/B: driver `fromConfig` |
| 81-89 | creates `SimulatedRig`, `MockScpiTransport`, `MockLanXiHttp`, `RecordingStream`, `ScpiTcpTransport(generator.host, port, timeout)`, `LanXiHttp(lanxi.host, lanxi.timeout)`, `LanXiTcpStream` | B: registry |
| 91-93 | `Keysight33220A(tr, 'MaxVpp', generator.maxVpp, 'Load', generator.load)`; `Gen.Identity.raw` in log and step | B |
| 94-107 | steps `lanxi` (`'simulated LAN-XI module'`, `'%s (REST, Open API)'`), `idle`; `LanXi(Http, factory, 'Host', lanxi.host)`; `moduleInfo` (`model`, `serial`, `firmware`, `moduleState`); return to Idle via `Daq.shutdown` | A/B: LanXi `fromConfig` |
| 120-126 | channel setup struct incl. `connector` = `cfg.lanxi.connector`; `Daq.ProgressFcn`; `Daq.prepare` | B |
| 130 | `resolveSensitivities(..., Daq.Teds, ...)` | contract property |
| 143-150 | settle step text `'CCLD + %s high-pass'`, only in hardware mode | B (`texts.settle`) |
| 171-188 | signal check: `info.qualityEvents`, `signalIds`, texts `'LAN-XI flag INVALID (cable or CCLD fault)'`, `'clipped (LAN-XI flag)'`, range parsed with `sscanf(acquisition.range)`; SPL | B: `integrity`, `dataUnit` |
| 205 | comment: steps reported by `LanXi.prepare` cannot throw | B |
| 240, 567, 573 | `Daq.acquire`, `Daq.collect` | contract |
| 248-348 | `Gen.configureSweep/Sine/Noise`, `outputOn`, `triggerSweep`, `waitComplete(5)`, `setFrequency`, `outputOff`, `armOutput` | contract (unchanged) |
| 463-481 | `Rig.MicPosOfChannel`, `Rig.Sample` (simulation hooks) | stays (rig from `ctx`) |
| 520-533 | fast close: `Http` and `Gen.Transport` (`isa(t, 'tim.instr.Keysight33220A')`) `setTimeout(2)`; `Gen.close`; `Daq.shutdown` | B: `setTimeout`, `close` |
| 564-589 | `guardedAcquire`: output off only in `catch` (no interrupt guard) | B: `outputGuard`, `AbortFcn` |
| 578-579, 606-607 | raw stream: `Daq.LastStream` is a `tim.instr.RecordingStream` → `bytes()` | B: `rawBytes` |
| 597-598 | `meas.fs` from the configuration, `meas.unit = 'V'` | B: `dataUnit` |
| 624-645 | excitation confirmation: `generator.maxVpp`, `generator.load` | generic (stays) |
| 628, 641, 667 | `Gen.outputOff` in error / Stop paths | contract |

### A.2 `tim.gui.Tubebench`

| Lines | Use | → |
|---|---|---|
| 22, 465, 1059, 1898 | comments "LAN-XI data stream / setup" | C |
| 212, 1515, 2099, 2881 | `Session.Gen.outputOff()` (close request, error, Stop, closing) | contract (re-entrant, section 2.2) |
| 561-568 | mode label and Connect / Disconnect tooltips: "generator and LAN-XI module", "read TEDS", "LAN-XI module back to Idle" | C |
| 572-579 | lamps `{'Generator', 'LAN-XI', 'ch1'...'ch4'}`, tooltips `'function generator 33220A'`, `'LAN-XI module'` | C: `labels`, `displayName` |
| 637, 1126-1127 | frequency fields limited to `0.45 * sampleRate`; amplitude lower limit 0.005 Vpk | C: `bandFraction`, `minVpp` |
| 732-733 | Connection view description "generator, LAN-XI, TEDS" | C |
| 763 | channel table column "TEDS s/n" | stays (TEDS is a standard) |
| 1063 | `s.Daq.Stream` non-empty = stream running | C: `isAcquiring` |
| 1078-1085 | `connKeys` / `connLabels`: the nine keys and labels, "Function generator 33220A (SCPI)", "LAN-XI module (REST)", "LAN-XI recorder state Idle" | C: `connectionSteps` |
| 1568-1583 | output read-back `s.Gen.Transport.query('OUTP?', 1)`; "could not be confirmed off" | C: `isOutputOn(1)`, read-back kind |
| 1604-1621 | lamp 1 tooltips `'Generator (Keysight 33220A) – details in Setup > Connection'`; red lamp when not confirmed | C |
| 1696-1702 | live view: `Daq.Parser.samplesAvailable/tail`, `Daq.SampleRate` | C: `recent` |
| 1890 | log "generator output OFF, LAN-XI Idle" | C |
| 1959-1977 | `onProgress`: key `gen` → lamp 1; `lanxi, idle, open, setup` → lamp 2; `teds` → refresh cards | C: step `role`, refresh after `'prepare'` steps |
| 1995-2011 | channel cards from `Session.Daq.Teds` | contract property |
| 2297, 2315 | calibration prompt: `setMicPositionsForSimulation` in simulation | stays |
| 2386 | tooltip "own cable and LAN-XI input" | C |
| 2886 | closing dialog "Returning the LAN-XI to Idle" | C |
| 2902-2908 | `loadText`: meaning of `generator.load` | stays (generic setting) |

### A.3 `+tim/+app`, `+tim/+cal`, `+tim/+acq`, `+tim/+val`

| File (lines) | Use | → |
|---|---|---|
| `collectMetadata` (13-25) | `generator.host/port/maxVpp/load`, `Gen.Identity`; `lanxi.host/connector`, `Daq.Info.model/serial/firmware`, `Daq.Setup`, `Daq.Teds` | B: `metadata()` |
| `collectMetadata` (36-41) | `Rig` ground truth in simulation | stays |
| `runCalibration` (12, 68-71) | comment "LAN-XI input"; simulation specimen via `session.Rig` | B (records `meta.acquisition`) |
| `validateConfig` (21-29) | `generator.load` exactly `'INF'`/`'50'` (33220A `OUTP:LOAD`) | B: `capabilities.source.loads` |
| `validateConfig` (72-75) | sample rate limited to the 3676 rates with "LAN-XI module 3676" text; `0.45 * fs` | B: `checkConfig`, `bandFraction` |
| `defaultConfig` (16-20, 23, 38-39, 41-49, 52) | 33220A comments; `generator.host/port/timeout`; `lanxi.host/timeout/connector`; acquisition values of the 3676 (`'10 Vpeak'`, `'0.7 Hz'`); "channel = LAN-XI input" | B |
| `loadConfig` | merge onto defaults; no migration yet | B: `migrateConfig` (9.3) |
| `saveMeasurement` | metadata from `collectMetadata`; `config.json` | unchanged |
| `driveEstimate` (2-22, 51-55) | help text "The 33220A has a 50-ohm source impedance"; fixed 50 Ω in the formulas | B: `outputImpedance_ohm` |
| `msg` (39-41) | `ampDirect` (en / ko): "Direct drive (no amplifier) via the 50 Ω generator output" - false for a 0 Ω DAQ output | B: composed from `outputImpedance_ohm` |
| `msg` (78, 83) | calibration prompt "never the cables or LAN-XI inputs" (en / ko) | C |
| `calibrationContext` | compares geometry, temperature, mode, Test E - not the instruments | B |
| `resolveSensitivities` (9) | TEDS cell from `LanXi.detectTransducers` | contract `Teds` |
| `switchingCorrection` (8) | comment "LAN-XI input" | C (comment) |
| `checkIntegrity` | integrity of decoded LAN-XI data (`info.qualityEvents`, `stats`, `unit`) | A: LanXi uses it; B: generic part (fs, non-finite, dead channels) for every driver |
| `val.channelIdentification` (20-21, 34-44) | `session.Daq.acquire`, `Daq.SampleRate` (no output); countdown from `n` (wall-clock meaning) | contract; B: idle while `isPlanning()` |
| `val.testA_acquisition` (13-21) | `info.fs`, `info.unit`, `info.scaleFactor`, `info.stats` (LAN-XI parser fields) | B |
| `val.testB_singleFrequency`, `sweepTimingTest`, `testC`, `testDE` | session API only | unchanged |

### A.4 Examples and tests

| File (lines) | Use | → |
|---|---|---|
| `examples/hardware_commissioning.m` (8, 22, 31) | `s.Gen.Identity`, `s.Daq.Info`, `s.Daq.Teds`; text "lanxi.connector" | B/C |
| `examples/bench_test_no_tube.m` (33-36, 41-43, 55-56) | `s.Daq.Teds`; LAN-XI / 33220A texts | C (texts) |
| `examples/demo_simulation.m` (45) | `s.Rig.trueResponse` | stays |
| `start_here.m` (2, 36, 59) | comments name the instruments | C |
| `tests/TestInstruments.m` | constructs `Keysight33220A`, `LanXi` on the mocks directly; `tim:lanxi:*`, `tim:gen:*` IDs | unchanged (D2) |
| `tests/TestEndToEnd.m` (44, 51, 55, 132, 209-210, 252-253, 275-276, 424, 437-438, 498, 532, 538, 553, 589, 619, 653, 681) | `s.Gen.isOutputOn`, `s.Gen.OutputArmed`, `s.Rig` | contract / stays |
| `tests/TestEndToEnd.m` (435) | `s.Http.StreamOptions` (stream fault injection) | B: `s.Daq.Http` |
| `tests/TestEndToEnd.m` (94, 486, 748) | `metadata.daq.firmware`; the nine step keys; failed step `setup` | stay valid (supersets, same keys) |
| `tests/TestGui.m` (361-365, 654) | six lamps, nine checklist states | stay valid for the default drivers |
| `tests/TestValidationProcedures.m` (44, 80), `TestDsp.m` (18) | `s.Gen.isOutputOn`, `s.Rig`, `SimulatedRig` | contract / stays |
| `tests/TestCalibration.m` (22-52) | `calibrationContext` without `meta.acquisition` expects no warning | stays valid (D13) |

## Appendix B - Bus-traffic regression tests

`tests/TestBusTraffic.m` runs simulated sessions through the protocol mocks;
`tim.instr.mockBusLog` collects every SCPI command and response, every REST request with its
body and every stream open / close of all mocks in **one ordered log**, compared entry by entry
with a fixture; the first difference is reported with its section, the entry before it and the
differing character.

* **Normal path** (`tests/fixtures/bus_traffic_sim.txt`, added in stage 1, passing on 8ff47f3 =
  e8fb4fb code; 663 entries incl. 6 section markers): connect + `prepareAcquisition` + 1 s signal
  check; a complete switching calibration with the simulation default prompt (repeated
  configuration I, empty-tube check); one swept-sine measurement (2 repetitions); one
  stepped-sine measurement (5 steps, 2 repetitions); one noise measurement; close.
* **Fault paths** (`tests/fixtures/bus_traffic_faults_sim.txt`, recorded in stage 2 before any
  driver change, on d49e98d whose production code is that of e8fb4fb; 229 entries incl. 7
  section markers and 5 outcome lines `# -> error <id>`): the stream stalls in the middle of a
  sweep; operator Stop in the middle of a sweep; the operator cancels the excitation
  confirmation; the loudspeaker power limit refuses the drive; the window is closed twice inside a
  sweep (output off + `close(true)` from inside the acquisition). The order of that code was
  recorded as it was, e.g. after a stalled stream `OUTP OFF` followed the REST stop. The fast close
  ended with `MATLAB:structRefFromNonStruct` from the next stream read; since stage B it ends with
  `tim:instr:closed` and without the status request that followed (fixture edited by hand in that
  scenario, 228 entries; see section 14). **Regenerated from the code on 2026-10-11** with the
  owner's approval (D24, section 13.4; 228 entries, header note in the file, no hand edit left):
  after the stalled stream and after the Stop one `OUTP OFF` (the `AbortFcn`) now comes before
  `REST PUT /rest/rec/measurements/stop`, the other one (the disarm) after `STREAM close`; nothing
  else changed - checked line by line against the previous file, and explicitly by
  `TestBusTraffic/outputOffBeforeTheStopOnAnAbnormalEnd`.

Deterministic: `rng(1, 'twister')`, `SimulatedRig` seed 1, mock stream seed 7; the mocks change
state at once (one status poll per wait) and deliver a fixed block per read, so every scheduled
generator command falls on the same block; faults are placed on the number of samples the rig has
produced. Normalised: the body of `PUT /rest/rec/module/time` (wall-clock ms). Not logged: stream
reads (their number depends on the 0.3 s drain after a stop) and client time-outs (not on the
bus). A fixture is regenerated only after an intended, owner-approved change of the bus traffic:
`addpath tests; TestBusTraffic.writeFixture()` or `TestBusTraffic.writeFixture('faults')` (an optional second
argument adds a note, e.g. the approval, to the header).
