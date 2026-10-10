# Instrument interface (contract)

| | |
|---|---|
| Work order | WO-001 Part 1 (`docs/workorder_instrument_interface.md`; its §0 decides over older text) |
| Status | **design, 2026-10-11** (stage 1), **revised after the design review** (stage 2: 24 issues, resolutions in section 13.2). **Stages A and B implemented** on `wo-001` (contract classes, both drivers, registry, `tests/TestInstrumentContract.m`; configuration `formatVersion` 2, the session through the registry, metadata and the calibration's DAQ chain, `simcombined`); the window still names the 33220A and the LAN-XI in texts, labels and tooltips until stage C (its checklist, lamps, output read-back and live view already follow the drivers, section 14). |
| Applies to | `tim.app.MeasurementSession`, `tim.gui.Tubebench`, `+tim/+app`, `+tim/+cal`, `+tim/+val`, the drivers in `+tim/+instr` and `+tim/+sim` |

This document is the contract between the measurement program and an instrument driver. A
driver that follows it can be selected in the configuration without any change to the session,
the window, the configuration code or the tests. It is written for a person who adds a driver
(with or without Claude Code); `docs/adding_an_instrument.md` (WO-001 Part 2) will give the
step-by-step procedure.

Units throughout: frequencies in Hz, times in s, sample counts per channel, sample rates in S/s,
generator amplitudes in **Vpp as programmed** (see `generator.load`; a source programmed in
full-scale units converts with its measured `vppAtFullScale`, section 3.3), input data in **volts
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
│     └── tim.instr.Keysight33220A                  driver 'keysight33220a'
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
acq.AbortFcn = @() src.outputOff()                    % abnormal end of acquire: output off first (8.1)
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
| `d = describe()` | `name` (registry name, lower case, = `generator.driver` / `daq.driver`); `displayName` (e.g. `'Keysight/Agilent 33220A function generator'`, shown in the window and stored in the metadata); `labels` (struct, one short lamp label per role, e.g. `source: 'Generator'`, `acquisition: 'LAN-XI'`); `defaults.settings` (default driver settings = the sub-struct `generator.<name>` / `daq.<name>`); `defaults.acquisition` (acquisition drivers: the values `acquisition.sampleRate`, `range`, `filter` and `ccld` take when the configuration leaves them empty, section 9.2); `texts.settle` (what the settling step after `prepare` waits for, `sprintf` format with the filter, e.g. `'CCLD + %s high-pass'`; `''` = no settling needed); `simulation` (`'protocol'`: real driver that runs on its protocol mock in simulation mode; `'only'`: contract-level simulated driver, simulation mode only) |
| `c = capabilities()` | section 5 (roles, shared clock, pairing, products, source and acquisition limits) |
| `s = connectionSteps()` | struct array `key`, `label`, `role` (`'source'`, `'acquisition'` or `'both'`), `phase` (`'connect'`: reported by `fromConfig`; `'prepare'`: reported by `prepare`) - section 6 |
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
  channel after stopping and before releasing.

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

A waveform the source cannot produce raises `tim:gen:unsupported`.

The window words the state after a Stop or an error by the read-back kind (stage C):
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

* Every method that sets a level checks it **first** and sends no level command when the check
  fails (`tim:gen:amplitude`): a positive scalar, at most `generator.maxVpp` (fixed at creation),
  at least `capabilities.source.minVpp` for the configured load.
* `capabilities.source.levelKnown = true`: the driver programs an absolute voltage (SCPI
  generators, NI analog outputs).
* `levelKnown = false`: the output is programmed in full-scale units (audio interface); the volts
  at the output depend on the device and its output knob (a professional line output reaches
  +18 to +24 dBu, well over 10 Vpp at 0 dBFS), so a static `maxVpp` cannot protect anything.
  The driver setting `generator.<driver>.vppAtFullScale` (Vpp at full scale, measured once with
  a voltmeter at a fixed knob position; **no default**) is required in hardware mode
  (`checkConfig`). The driver converts Vpp to full-scale units with it and refuses any level with
  more than full scale or more than `generator.maxVpp` (`tim:gen:amplitude`); the operator
  confirmation states the calibration and the knob position. `docs/adding_an_instrument.md` and
  the suitability step of the skill (Part 2) carry this rule.

### 3.5 Block (shared-clock) source outside `acquire`

For a source whose output is played from a plan (section 8.3):

* `configure*` and `setFrequency` outside `acquire` set the initial state of the next plan;
* `outputOn` and `triggerSweep` outside `acquire` raise `tim:gen:schedule`;
* `isOutputOn` is `false` outside `acquire`;
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

| Field | Meaning | 33220A | LAN-XI 3676 | simcombined |
|---|---|---|---|---|
| `roles` | `{'source'}`, `{'acquisition'}` or both | source | acquisition | both |
| `sharedClock` | output and inputs of this object run on one sample clock | false | false | true |
| `rolesTogether` | a combined driver that works only when it takes both roles (section 9.1) | false | false | true |
| `products` | struct array `name` (as listed by `ver`) and `feature` (license key, e.g. `Data_Acq_Toolbox`) of the MATLAB products needed beyond MATLAB + Signal Processing Toolbox; checked in hardware mode only | none | none | none |
| `source.waveforms` | subset of `{'sine','sweep','noise'}`; `'sweep'` is required (section 9.2) | all | - | all |
| `source.sweepSpacing` | subset of `{'LOG','LIN'}` | both | - | both |
| `source.frequencyRange` | [fMin fMax] Hz (`Inf`: limited by the sample rate only) | [1e-6 20e6] | - | [1 Inf] |
| `source.bandFraction` | highest frequency as a fraction of the sample rate (shared clock), `NaN` for an own clock | NaN | - | 0.45 |
| `source.loads` | accepted `generator.load` values: `'INF'` = programmed value is the open-circuit voltage, `'50'` = the voltage into 50 Ω | INF, 50 | - | INF |
| `source.maxVpp` | largest programmable level per entry of `loads`; `generator.maxVpp` must not exceed it | 20, 10 | - | 10 |
| `source.minVpp` | smallest programmable level per entry of `loads` | 0.02, 0.01 | - | 0.001 |
| `source.sweepTime` | [min max] sweep duration [s] | [0.001 500] | - | [0.1 300] |
| `source.noiseCrest` | crest factor of the noise (Vpp / 2 / rms) | 3.3 | - | 3.3 |
| `source.outputImpedance_ohm` | source impedance (loudspeaker drive estimate, operator texts) | 50 | - | 0 |
| `source.trigger` | how `triggerSweep` starts the sweep: `'bus'`, `'software'`, `'clock'` (sample-exact on the shared clock) | bus | - | clock |
| `source.readback` | kind of `isOutputOn` (section 3.2): `'instrument'`, `'device'`, `'none'` | instrument | - | device |
| `source.levelKnown` | the driver programs absolute volts (section 3.4) | true | - | true |
| `acquisition.channels` | analog inputs (≥ 4) | - | 4 | 4 |
| `acquisition.simultaneous` | all inputs sampled at the same instant on one clock (must be true) | - | true | true |
| `acquisition.sampleRates` | supported rates [S/s], or `[]` with a `sampleRateRange` | - | 4096 ... 65536 | 4096 ... 65536 |
| `acquisition.sampleRateRange` | [min max] of a continuous range (`checkConfig` and `prepare` refuse rates the device cannot run exactly) | - | [] | [] |
| `acquisition.bandFraction` | usable band / sample rate (anti-alias filter); limits `analysis.fMax` and the stop frequencies | - | 0.45 | 0.45 |
| `acquisition.ranges` | values of `acquisition.range` | - | `'1 Vpeak'`, `'10 Vpeak'` | `'10 Vpeak'` |
| `acquisition.filters` | values of `acquisition.filter` (high-pass / coupling) | - | `'DC'`, `'0.7 Hz'`, ... (module list) | `'0.7 Hz'` |
| `acquisition.ccld` | switchable CCLD/IEPE supply per input | - | true | true (modelled) |
| `acquisition.teds` | reads TEDS | - | true | false |
| `acquisition.dataUnit` | `'V'`, or `'FS'` when the input scale is unknown (section 4.2) | - | V | V |
| `acquisition.mode` | `'streaming'` (data arrive while recording) or `'block'` (recorded in blocks) | - | streaming | block |
| `acquisition.needsOwnSource` | the driver cannot call `onBlock` as data arrive: usable only when it is also the source (planned, section 8.3) | - | false | true |

The static values describe what the driver supports; a driver may still refuse a value the
connected device reports as unsupported (LAN-XI: `tim:lanxi:rate` from `module/info`). The
simcombined values are those of `tim.sim.SimulatedCombined` (stage B, as designed); its settings
(`daq.simcombined`) are `blockSamples` (2048), `serial` and `seed` (noise output), its lamp labels
"Output" and "Inputs".

## 6. Connection steps (checklist of Setup > Connection)

The window shows, in this order: the source's steps, the acquisition's steps (once for a combined
device), then the session's own steps `sens` (microphone sensitivities), `settle` (settling after
the channel setup, hardware only; its text from `describe().texts.settle`) and `signal` (1 s
signal check without excitation).

| Driver | Steps (`key`: label, role, phase) |
|---|---|
| keysight33220a | `gen`: Function generator 33220A (SCPI), source, connect |
| lanxi | `lanxi`: LAN-XI module (REST), acquisition, connect; `idle`: LAN-XI recorder state Idle, acquisition, connect; `open`: Open recorder, acquisition, prepare; `teds`: TEDS transducer detection, acquisition, prepare; `setup`: Channel setup → streaming, acquisition, prepare |
| simcombined | `device`: Simulated device (output + 4 inputs), both, connect; `setup`: Channel setup, acquisition, prepare |

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
  lamps. A lamp's label is `describe().labels.<role>` and its tooltip the display name and
  identity. The channel cards (TEDS) are refreshed after every `'prepare'` step that ends (today
  only after the key `teds`).

## 7. Identity and metadata

* `identity()` feeds the window (INSTRUMENTS lamps and Setup > Connection: display name, model,
  serial number, firmware - owner decision §0.2; no selection controls) and the log line after
  connecting.
* `collectMetadata` stores `md.generator = s.Gen.metadata()` and `md.daq = s.Daq.metadata()`. Both
  are **supersets of today's fields**, so saved data and scripts keep working:
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
   The session sets `AbortFcn = @() s.Gen.outputOff()`, so the loudspeaker is not driven while
   the driver stops its device (with an unreachable LAN-XI module: one HTTP time-out for the
   stop request and one for the first status poll, about 20 s with the default settings).
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
   `n = B, 2B, ...` up to the requested count without waiting (B: driver block, e.g. 2048);
   `isPlanning()` is `true`. Every source call made meanwhile is **scheduled** on the device
   timeline at the current `n` (sample-exact): `outputOn`, `triggerSweep`, `setFrequency`, a
   level, and `outputOff` ("off at n", the normal end of the excitation). `waitComplete` returns
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
  must be in `source.waveforms` (`tim:config:excitation`); levels within [`minVpp`, `maxVpp`] of
  the load; sweep durations within `sweepTime`; a sample rate the device runs exactly; in hardware
  mode `vppAtFullScale` for `levelKnown = false`.
* Driver-specific settings live in a sub-struct named after the driver. It is merged onto
  `describe().defaults.settings`, not onto `tim.app.defaultConfig`. A sub-struct named after
  another registered driver is kept without a warning (a file can hold the settings of several
  drivers and switch with `driver`); unknown names still give `tim:config:unknownField`.
* A combined driver reads its device settings from `daq.<name>`; `generator.driver` names the same
  driver.
* **Unknown driver names** (a measurement folder from another lab or from a driver removed later):
  `loadConfig` and `validateConfig` give the **warning** `tim:config:driver`, keep its sub-struct
  as it is and skip the driver-dependent limits, so File > Open measurement ("use the saved
  set-up"), Load configuration and scripts that only reprocess still work. The **error** is raised
  where an instrument is needed: by `tim.instr.create` at Connect and by
  `validateConfig(cfg, 'instruments')`, which `MeasurementSession` calls (the window shows such
  errors as "Check the settings").
* `tim.app.driveEstimate` takes the source impedance from `capabilities().source.outputImpedance_ohm`
  of `generator.driver` (today a fixed 50 Ω: a DAQ output of about 0 Ω driving an 8 Ω loudspeaker
  directly would be estimated (58/8)² ≈ 50 times too low - a safety defect for any new source).
  The operator text `ampDirect` ("via the 50 Ω generator output", `tim.app.msg`) is composed from
  the same value.

### 9.3 Migration of older files (`tim.app.migrateConfig`)

One function, used by `loadConfig` (before the merge), by the `MeasurementSession` constructor
and by `validateConfig` for configurations built in code (old scripts set `cfg.lanxi.*` or
`cfg.generator.host` on `defaultConfig`):

1. A top-level `lanxi` section and no `daq` section → `daq.driver = "lanxi"`, `daq.lanxi = lanxi`;
   `lanxi` is removed (no unknown-field warning).
2. `generator.host` / `port` / `timeout` outside a driver sub-struct move into
   `generator.keysight33220a` **only when the selected driver is `keysight33220a` or no driver is
   given**. Otherwise they stay unused and the warning `tim:config:legacyField` names the key and
   where it belongs (e.g. `generator.<driver>.host`): a user who only changed the driver name must
   not silently get the new driver's default address.
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

The rig couples a source to the microphones in one of two ways:

* `setGeneratorState(s)` - **only for the 33220A mock**: the rig synthesises the waveform from the
  33220A state (`FUNC`, `FREQ`, `VOLT` in Vpp, `FREQ_STAR`, `FREQ_STOP`, `SWE_SPAC`, `SWE_TIME`,
  `SWE_STAT`, `OUTP`), with its stepped sweep, the bus-trigger latency and `GenClockPpm`.
* `y = respond(x)` - **for every other source**: `x` n x 1 excitation volts in, n x 4 microphone
  volts out, through the same FIR, noise and clock path. A protocol mock of an NI DAQ or an audio
  driver holds a sample buffer (the planned output), not a generator state, so it calls `respond`;
  `simcombined` does too. `generate(n)` becomes `respond(sourceSignal(n))` internally, so the
  33220A path, its random-number order and its bus traffic stay unchanged.

The rig keeps an `OutputLog` filled by both paths, one row per output block
`[firstSample nSamples peak_V last_V]` (sample index on the rig's timeline; `respond(zeros(0, 1))`
adds a row `[n 0 0 0]`: the output was set to 0 V), so the contract tests can check generically
what was really played (section 11.3); `markTrigger(n)` records a sweep start of a shared-clock
source in `TriggerLog`. A new real driver brings its own protocol mock (WO-001 Part 2) and runs in
simulation mode like the two existing ones.

## 11. Safety duties (checked by `tests/TestInstrumentContract.m`)

### 11.1 Drivers

SignalSource:

1. **Output off on creation**: `fromConfig` switches the output off (section 3.1) before any other
   setting.
2. **Output off on `close`, in `delete` and after any error** a driver method raises after it may
   have changed the instrument (e.g. a read-back mismatch or an instrument error).
3. **Level limit before every level command** (section 3.4): every method that sets a level checks
   it first (`tim:gen:amplitude`) and sends no level command when it fails; `outputOn` re-checks
   the programmed level (read back where possible).
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

Combined device: 12. when the acquisition stops for any reason, the output stops too (0 V).

### 11.2 Session (defence in depth)

The output is armed only inside `measure*`. **Every exit path, including an interrupt, switches
the output off**: MATLAB does not catch Ctrl+C (from the command window of `start_here.m` or
`examples/hardware_commissioning.m`, or the console of `start_tubebench.bat`) with `try`/`catch`;
only `onCleanup` objects run. `guardedAcquire` therefore creates an output guard
(`tim.app.outputGuard`) right after `armOutput(true)`; on destruction it calls `Gen.outputOff()`
and `armOutput(false)` unless it was dismissed just before the normal return or after the error
path switched the output off itself, so neither the normal path nor the error paths send an
extra `OUTP OFF`. Every error path switches the output off, stops the acquisition and keeps the
partial data (`s.LastPartial`, emergency file).

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
a driver error; `close` from inside `onBlock`; every acquisition driver, run with a separate
source on the same rig, records the excitation inside the record; the registry refuses an unknown
driver, a wrong role or pairing and an invalid driver configuration before any I/O, and reads
the legacy configuration keys; the product check names the product and the driver. With `simcombined` and the rig's
`OutputLog` (stage B): Stop during planning plays nothing, Stop during execution ends the output
within one block, an `onBlock` error after `outputOn` leaves the output off, the last output
value is 0 after a normal plan, a Stop in either pass, an `onBlock` error and `close` during
`acquire`, and `estimateSweepLaw` of the played sweep is within tolerance.

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
| `tim:instr:noHooks` | `testHooks` | the object does not run on its protocol mock |
| `tim:config:driver` | `validateConfig`, `checkConfig`, registry | missing / unknown driver (a warning when only loading, section 9.2) |
| `tim:config:*` | `validateConfig`, `checkConfig` | a setting the driver does not support |
| `tim:config:legacyField` (warning) | `migrateConfig` | old keys ignored or not moved (section 9.3) |
| `tim:gen:notArmed` | source | `outputOn` without `armOutput(true)` |
| `tim:gen:amplitude` | source | level above the limit, not positive, below the instrument minimum or above full scale |
| `tim:gen:mode` | source | call not valid in the configured mode (unconfigured `outputOn`, `setFrequency` outside sine, `triggerSweep` outside sweep, a block source configured before any sample rate is known) |
| `tim:gen:sweep` | source | invalid sweep settings |
| `tim:gen:unsupported` | source | waveform or feature not in the capabilities |
| `tim:gen:verify` | source | read-back differs from the request |
| `tim:gen:schedule` | block source | level / frequency / trigger / `outputOn` during execution; `outputOn` / `triggerSweep` outside `acquire` |
| `tim:session:stopped` | session (`onBlock`, steps) | operator Stop; passes through drivers unchanged |
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
| D7 | `user_config.json` stays in the old layout | rewrite it in the new layout | it is the owner's lab file; loading it unchanged proves the migration every day (owner decision pending) |
| D8 | Simulation: real drivers over protocol mocks + one contract-level combined driver | contract-level `SimulatedSource` / `SimulatedAcquisition` for the app tests (WO task 7 text) | the protocol-mock path is the only one that exercises the real drivers end to end (and the bus-traffic tests need it); the combined driver covers both contracts at contract level and the case change B asks for; a separate simulated pair would add code without new coverage. **Owner decision pending** (WO §0 does not decide task 7). |
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
| D24 | Abort hook as the property `AbortFcn` | a fourth `acquire` argument `onAbort` | set once at connect, so direct callers of `acquire` (`tim.val.channelIdentification`) are covered too. The driver side is implemented in stage A (no traffic change while `AbortFcn` is empty); **the session sets it only after the owner approves** (stage B), because it moves `OUTP OFF` before the REST stop on driver-error paths (fault fixture update) |
| D25 | Re-entrant `outputOff` / `close` / `setTimeout`; `close` during `acquire` → `tim:instr:closed` | specify `onBlock` re-entry only | window callbacks run during every `pause` / `drawnow` inside a driver; a released System object would otherwise set itself up again and keep playing |
| D26 | Exact sample rate or `tim:<driver>:rate`; the rate list or range is a capability; `checkConfig` refuses rates the device cannot run exactly | a static `isRateExact(fs)` member as the review proposed | `checkConfig` is already the static place that validates the driver's settings; one member less |
| D27 | Rig `respond(x)` + `OutputLog`; `setGeneratorState` only for the 33220A mock | every source maps its state onto the 33220A fields | a sample-buffer mock cannot express its output as a 33220A state; generic safety assertions need what was really played |
| D28 | Static `testHooks(obj)` per driver (simulation only) | driver-specific contract tests | without generic hooks the duties of §11 could only be tested for the 33220A |
| D29 | Unknown driver: warning on load, error at Connect | error in `validateConfig` (stage 1) | saved folders of other labs and scripts that only reprocess must keep loading |
| D30 | Products as `name` + `feature`, hardware mode only; optional `checkInstalled()` for support packages and runtimes | `ver` names in every mode | `license` needs feature names; support packages and vendor runtimes are no MATLAB products; mocks need no toolbox |
| D31 | Second bus fixture for the fault paths, recorded before stage A on the pre-refactor code | normal-path fixture only | the fault paths (error, Stop, cancel, power refusal, fast close) are the highest refactor risk and can be recorded on the old code only once |
| D32 | Empty generic acquisition values mean the driver default; `ccld` / TEDS policy in `checkConfig` | LAN-XI values as generic defaults | a file that only names another DAQ must not fail on `'10 Vpeak'` / `'0.7 Hz'` |
| D33 | A swept sine with the configured spacing is a Must for a source | any one waveform | the switching calibration and Test E always sweep, and the calibration method must not change |
| D34 | One `migrateConfig`; legacy keys move only to the legacy driver | migration inside `loadConfig` only | configs built in code would be ignored silently; a changed driver name must not inherit the 33220A address silently |
| D35 | Waveform definitions in the contract (section 3.3) | "single sweep" without a law | the sweep gate, the sweep-law check and the power check rely on them; another generator may add hold / return times or end `*OPC?` early |
| D36 | Block source outside `acquire` specified (section 3.5) | planning and execution only | the session and the contract tests call the source outside `acquire` |
| D37 | `tim.app.outputGuard` in stage B | stage A | stage A does not change the session (stage plan); the guard is the first change of stage B |
| D38 | Stage A: the registry reads the legacy keys itself | `migrateConfig` in stage A | the configuration code changes in stage B; the registry must already work with every configuration of today |

### 13.2 Design review of 2026-10-11 (stage 2)

All 24 issues are accepted; where the resolution differs from the proposed fix the reason is in
the decision named.

| # | Issue | Resolution | Where | Stage |
|---|---|---|---|---|
| 1 | Ctrl+C leaves the output on | session output guard; rules "every exit path including an interrupt" | 4, 11.1 (7), 11.2, D15, D37 | B (guard), A (drivers) |
| 2 | Planning pass contradicts the session schedule | `outputOff` scheduled; only an `onBlock` error discards; rule 1 per pass; `isPlanning()`; one `onBlock` input | 8.1, 8.3, D17 | B |
| 3 | Block acquisition belongs to the pair | plan only for one object in both roles; `needsOwnSource`, `rolesTogether`; registry refuses pairings | 1, 5, 8.2, 9.1, D16 | A (registry), B (test) |
| 4 | Output off undefined for analog outputs | off = 0 V or disconnected; 0 V writes, fade | 3.1, 11.1 (1, 12), D18 | B (simcombined), Part 2 |
| 5 | Read-back excludes DAQ / audio outputs | kinds `instrument` / `device` / `none`; window wording; `allowUnconfirmedOff`; WO §3 reworded | 3.2, 5, 9.1, D19 | A (registry), C (window) |
| 6 | Amplitude limit meaningless for full-scale outputs | `levelKnown`, `vppAtFullScale` | 3.4, 5, 9.2, D23 | A (capability), Part 2 |
| 7 | Output off only after the driver's stop sequence | `AbortFcn` called first; session wiring after owner approval | 4, 8.1 (4), 11.1 (8), D24 | A (driver), B (session, approval) |
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
| 24 | Minimality | `shutdown`, `Mode`, `MaxVpp`, `Load` out; `minVpp`, `sweepTime`, step role `'both'`, card refresh after `'prepare'` steps | 3, 4, 5, 6, D21 | A (contract), C (window) |

## 14. Implementation plan

Each stage ends with the full test suite and both bus-traffic fixtures passing unchanged (the
fixtures are never regenerated during WO-001 except for an owner-approved change of order, D24).

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

* Step 1: the output guard is in place; `AbortFcn = @() Gen.outputOff()` is **not** set by the
  session yet - it still awaits the owner's approval (D24), and the fault fixture keeps today's
  order after a stalled stream.
* Step 3: closing the session uses the contract `close()` of each instrument, so closing the
  window inside a sweep ends the measurement with `tim:instr:closed` as planned in Appendix B. The
  fault fixture was edited by hand in that one scenario (the outcome line, and the status request
  the old code sent after the error to the module that was already Idle); every SCPI command and
  the REST return-to-Idle sequence are unchanged. The normal-path fixture is unchanged.
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
   owner's approval `AbortFcn = @() Gen.outputOff()` and the fault fixture updated.
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

**Stage C - window from the drivers, documentation (WO tasks 5, 9).**

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

Part 2 (guide with the full-scale and 0 V rules, templates, skill, dry run) and the owner's
hardware check (§0.3) follow stage C.

## Appendix A - Inventory of today's instrument-specific code (commit 8ff47f3)

Line numbers as of 8ff47f3. "→" names the stage that changes it.

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
  sweep (output off + `close(true)` from inside the acquisition). Today's order is recorded as it
  is, e.g. after a stalled stream `OUTP OFF` follows the REST stop (D24). The fast close ended
  with `MATLAB:structRefFromNonStruct` from the next stream read; since stage B it ends with
  `tim:instr:closed` and without the status request that followed (fixture edited by hand in that
  scenario, 228 entries; see section 14).

Deterministic: `rng(1, 'twister')`, `SimulatedRig` seed 1, mock stream seed 7; the mocks change
state at once (one status poll per wait) and deliver a fixed block per read, so every scheduled
generator command falls on the same block; faults are placed on the number of samples the rig has
produced. Normalised: the body of `PUT /rest/rec/module/time` (wall-clock ms). Not logged: stream
reads (their number depends on the 0.3 s drain after a stop) and client time-outs (not on the
bus). A fixture is regenerated only after an intended, owner-approved change of the bus traffic:
`addpath tests; TestBusTraffic.writeFixture()` or `TestBusTraffic.writeFixture('faults')`.
