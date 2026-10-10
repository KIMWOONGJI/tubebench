# Instrument interface (contract)

| | |
|---|---|
| Work order | WO-001 Part 1 (`docs/workorder_instrument_interface.md`; its §0 decides over older text) |
| Status | **design, 2026-10-11 (stage 1)** - not implemented yet. Until stage A is merged the code uses the implicit interface listed in Appendix A. |
| Applies to | `tim.app.MeasurementSession`, `tim.gui.Tubebench`, `+tim/+app`, `+tim/+cal`, `+tim/+val`, the drivers in `+tim/+instr` and `+tim/+sim` |

This document is the contract between the measurement program and an instrument driver. A
driver that follows it can be selected in the configuration without any change to the session,
the window, the configuration code or the tests. It is written for a person who adds a driver
(with or without Claude Code); `docs/adding_an_instrument.md` (WO-001 Part 2) will give the
step-by-step procedure.

Units throughout: frequencies in Hz, times in s, sample counts per channel, sample rates in S/s,
generator amplitudes in **Vpp as programmed** (see `generator.load`), input data in **volts at
the input** (no sensitivity applied).

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
checked on R2022b with a prototype: abstract static methods, `isa` for both roles, `delete`).

Life cycle, as the session uses it:

```
src = tim.instr.create('source', cfg, ctx)          % connect, identify, output OFF
acq = tim.instr.create('acquisition', cfg, ctx, src)  % connect, identify, idle (src again if combined)
acq.prepare(c)                                       % channels, range, CCLD, TEDS -> ready
src.configureSweep(s) ... src.armOutput(true)
[data, info] = acq.acquire(n, @onBlock)              % onBlock switches the output on / off
src.armOutput(false)
src.close(); acq.close()                             % output off, idle, released (idempotent)
```

## 2. Members common to both roles (`tim.instr.Instrument`)

### 2.1 Class-level (static) members - available before connecting

The window builds its checklist and lamps, `validateConfig` checks the settings and the drive
estimate needs the source impedance **before** anything is connected; therefore these members
are static and must not do any I/O.

| Member | Returns / does |
|---|---|
| `d = describe()` | `name` (registry name, lower case, = `generator.driver` / `daq.driver`); `displayName` (e.g. `'Keysight/Agilent 33220A function generator'`, shown in the window and stored in the metadata); `labels` (struct, one short lamp label per role, e.g. `source: 'Generator'`, `acquisition: 'LAN-XI'`); `defaults` (default driver settings, the sub-struct `generator.<name>` / `daq.<name>`); `simulation` (`'protocol'`: real driver that runs on its protocol mock in simulation mode; `'only'`: contract-level simulated driver, simulation mode only) |
| `c = capabilities()` | see section 5 (roles, shared clock, products, source and acquisition limits) |
| `s = connectionSteps()` | struct array `key`, `label`, `role` (`'source'`/`'acquisition'`), `phase` (`'connect'`: reported by `create`; `'prepare'`: reported by `prepare`) - section 6 |
| `report = checkConfig(cfg)` | validates the driver's part of the configuration (its sub-struct and the role settings it constrains, section 9.2); errors `tim:config:*`, returns warnings (cellstr) |
| `obj = create(cfg, ctx)` | factory used only by `tim.instr.create`: builds the transport (hardware) or the protocol mock (simulation, on `ctx.rig`), connects, identifies, puts the instrument in its safe state; reports its `'connect'` steps through `ctx.progress` |

`ctx` fields: `mode` (`'simulation'`/`'hardware'`), `rig` (`tim.sim.SimulatedRig` in simulation,
`[]` otherwise), `progress` (`@(key, state, detail)`), `roles` (the roles this object takes).

### 2.2 Instance members

| Member | Returns / does |
|---|---|
| `id = identity()` | what the instrument reports about itself: `vendor`, `model`, `serial`, `firmware` (char, `''` when unknown), `raw` (its own text, e.g. the `*IDN?` reply). Shown in the window, stored in the metadata. |
| `md = metadata()` | JSON-encodable struct stored with every measurement (section 7): at least `driver`, `displayName`, `roles`, `identity`, `sharedClock`, the driver settings in use; plus driver-specific state |
| `setTimeout(t)` | shortens every I/O time-out to `t` s (used when the window closes: `close(true)` must never wait long for a switched-off instrument). Default: no-op. |
| `close()` | safe state and release: source - disarm, output off (read-back not required), local, release; acquisition - stop, return to idle, release. **Never throws, idempotent.** |
| `delete()` | calls `close()` |
| `ProgressFcn` | `@(key, state, detail)` for the connection checklist (section 6) |

## 3. SignalSource (`tim.instr.SignalSource`)

Properties (read-only): `MaxVpp` (amplitude limit [Vpp] from `generator.maxVpp`, fixed at
creation), `Load` (`generator.load`), `OutputArmed` (logical), `Mode`
(`'none'|'sine'|'sweep'|'noise'`).

| Method | Contract |
|---|---|
| `configureSine(f, vpp)` | continuous sine `f` [Hz], `vpp` [Vpp]. Output OFF first; amplitude limit checked **before** any level is sent; settings read back where the instrument allows. |
| `setFrequency(f)` | new sine frequency, phase-continuous where possible, output state unchanged. Only in sine mode (`tim:gen:mode`). |
| `configureSweep(s)` | single sweep `s.fStart`, `s.fStop` [Hz], `s.duration` [s], `s.spacing` `'LOG'|'LIN'`, `s.amplitudeVpp` [Vpp], started later by `triggerSweep`. Output OFF; limit checked first; read back. Invalid settings: `tim:gen:sweep`. |
| `configureNoise(vpp)` | broadband noise. Output OFF; limit checked first. |
| `armOutput(tf)` | permission set by the session only after the operator started a measurement; `false` also switches the output off. |
| `outputOn()` | refused unless armed (`tim:gen:notArmed`) and configured (`tim:gen:mode`); re-checks the programmed level against `MaxVpp` right before enabling (`tim:gen:amplitude`). |
| `outputOff()` | output off. **Never throws** (a failure is a warning), idempotent, allowed in every state, also during a block acquisition. |
| `tf = isOutputOn(timeout)` | **read back from the instrument** (not a cached flag); `timeout` [s] optional; throws if there is no answer. The window says "output off (confirmed)" only after this returned `false`. |
| `triggerSweep()` | starts the configured sweep now (bus trigger, software start or the shared clock, `capabilities.source.trigger`). Only in sweep mode (`tim:gen:mode`). |
| `tf = waitComplete(timeout)` | `true` when the sweep has finished (waits up to `timeout` s). |

A waveform the source cannot produce raises `tim:gen:unsupported`.

## 4. Acquisition (`tim.instr.Acquisition`)

Properties (read-only): `SampleRate` (S/s, after `prepare`), `Teds` (1 x C cell: `[]` or a struct
`typeNumber` (char), `serialNumber`, `sensitivity` [V per unit], `unit`, `requiresCcld`; `{}` when
the device reads no TEDS - `tim.cal.resolveSensitivities` then falls back to the certificate /
nominal values).

| Method | Contract |
|---|---|
| `prepare(c)` | `c.sampleRate` [S/s], `c.channels` (input numbers, 1:4), `c.names` (cellstr, `'M1'`...), `c.range` (a value of `capabilities.acquisition.ranges`), `c.filter` (a value of `...filters`), `c.ccld` (logical 1 x C), `c.detectTeds`. Driver-specific settings (e.g. the LAN-XI connector) come from the driver settings captured by `create`. Leaves the device ready to acquire; reports its `'prepare'` steps. |
| `[data, info] = acquire(n, onBlock, timeout)` | records `n` samples per channel; `data` n x C double, **volts at the input**, column c = channel c; `onBlock(nNow)` as in section 8; `timeout` [s] wall-clock limit (default `n/fs*1.5 + 10`). Stops the acquisition on every exit path and leaves the device ready for the next call. |
| `[data, info] = collect(n)` | the data the last `acquire` received so far (partial data after an error or Stop), same format; at most `n` rows. |
| `[x, nTotal] = recent(n)` | the last ≤ n samples (rows x C, volts) of the running or last acquisition and the number received so far; `[]` when none. Cheap, no I/O (live view). |
| `tf = isAcquiring()` | an acquisition (data stream) is running - the window then defers background work. |
| `shutdown()` | stops any acquisition and returns to idle, keeping the connection. **Never throws, idempotent**, bounded time. |
| `b = rawBytes()` | undecoded bytes of the last acquisition (uint8 row) for raw-data preservation, or empty when the driver keeps none. |

`info` returned by `acquire` / `collect`:

* `fs` - sample rate reported by the data (S/s);
* `integrity` - `ok` (no fatal problem), `fatal`, `warnings` (cellstr), `peak_V` and
  `peakFractionOfRange` (1 x C), `channelFaults` (1 x C cell of cellstr: device-reported channel
  faults **in the driver's words**, e.g. `'LAN-XI flag INVALID (cable or CCLD fault)'`, so the
  session needs no device vocabulary);
* any driver-specific fields (LAN-XI: `unit`, `scaleFactor`, `stats`, `qualityEvents`, `signalIds`),
  stored as they are in `meas.channelInfo`.

## 5. Capabilities

`capabilities()` (static) returns:

| Field | Meaning | 33220A | LAN-XI 3676 | simcombined |
|---|---|---|---|---|
| `roles` | `{'source'}`, `{'acquisition'}` or both | source | acquisition | both |
| `sharedClock` | output and inputs of this object run on one sample clock | false | false | true |
| `products` | MATLAB products needed beyond MATLAB + Signal Processing Toolbox, names as listed by `ver` | none | none | none |
| `source.waveforms` | subset of `{'sine','sweep','noise'}` | all | - | all |
| `source.sweepSpacing` | subset of `{'LOG','LIN'}` | both | - | both |
| `source.frequencyRange` | [fMin fMax] Hz | [1e-6 20e6] | - | [1 0.45·fs] |
| `source.maxVpp` | largest programmable amplitude; `generator.maxVpp` must not exceed it | 20 (`INF`) | - | 10 |
| `source.loads` | accepted `generator.load` values: `'INF'` = programmed value is the open-circuit voltage, `'50'` = the voltage into 50 Ω | INF, 50 | - | INF |
| `source.outputImpedance_ohm` | source impedance (loudspeaker drive estimate) | 50 | - | 0 |
| `source.trigger` | how `triggerSweep` starts the sweep: `'bus'`, `'software'`, `'clock'` (sample-exact on the shared clock) | bus | - | clock |
| `source.readback` | `isOutputOn` reads the instrument (must be true for a real instrument) | true | - | true |
| `acquisition.channels` | analog inputs (≥ 4) | - | 4 | 4 |
| `acquisition.simultaneous` | all inputs sampled at the same instant on one clock (must be true) | - | true | true |
| `acquisition.sampleRates` | supported rates [S/s] | - | 4096 ... 65536 | 4096 ... 65536 |
| `acquisition.bandFraction` | usable band / sample rate (anti-alias filter); limits `analysis.fMax` and the stop frequencies | - | 0.45 | 0.45 |
| `acquisition.ranges` | values of `acquisition.range` | - | `'1 Vpeak'`, `'10 Vpeak'` | `'10 Vpeak'` |
| `acquisition.filters` | values of `acquisition.filter` (high-pass / coupling) | - | `'DC'`, `'0.7 Hz'`, ... (module list) | `'0.7 Hz'` |
| `acquisition.ccld` | switchable CCLD/IEPE supply per input | - | true | true (modelled) |
| `acquisition.teds` | reads TEDS | - | true | false |
| `acquisition.mode` | `'streaming'` (data arrive while recording) or `'block'` (output planned, then played and recorded) | - | streaming | block |

The static values describe what the driver supports; a driver may still refuse a value the
connected device reports as unsupported (LAN-XI: `tim:lanxi:rate` from `module/info`).

## 6. Connection steps (checklist of Setup > Connection)

The window shows, in this order: the source's steps, the acquisition's steps (once for a combined
device), then the session's own steps `sens` (microphone sensitivities), `settle` (settling after
the channel setup, hardware only) and `signal` (1 s signal check without excitation).

| Driver | Steps (`key`: label, phase) |
|---|---|
| keysight33220a | `gen`: Function generator 33220A (SCPI), connect |
| lanxi | `lanxi`: LAN-XI module (REST), connect; `idle`: LAN-XI recorder state Idle, connect; `open`: Open recorder, prepare; `teds`: TEDS transducer detection, prepare; `setup`: Channel setup → streaming, prepare |
| simcombined | `device`: Simulated device (output + 4 inputs), connect; `setup`: Channel setup, prepare |

Rules:

* `state` is `run`, `ok`, `warn`, `fail` or `skip`; `detail` is free text (shown next to the step).
* Keys are unique among drivers that can be combined and never `sens`, `settle` or `signal`
  (checked by the contract test). The keys of the two existing drivers stay as they are.
* Report `run` **before** opening anything for that step. `ProgressFcn` may throw at `run`
  (operator Stop, `tim:session:stopped`): in `create` the driver then releases what it opened and
  lets the error propagate. In `prepare` a driver may swallow callback errors (LAN-XI does); the
  session honours the Stop at its next own step.
* The lamp of a role follows that role's steps (INSTRUMENTS section); its label is
  `describe().labels.<role>` and its tooltip the display name and identity.

## 7. Identity and metadata

* `identity()` feeds the window (INSTRUMENTS lamps and Setup > Connection: display name, model,
  serial number, firmware - owner decision §0.2; no selection controls) and the log line after
  connecting.
* `collectMetadata` stores `md.generator = s.Gen.metadata()` and `md.daq = s.Daq.metadata()`. Both
  are **supersets of today's fields**, so saved data and scripts keep working:
  `md.generator.identity`, `host`, `port`, `maxVpp`, `load` (33220A); `md.daq.host`, `connector`,
  `model`, `serial`, `firmware`, `setup`, `teds` (LAN-XI). A combined device appears in both with
  `roles` naming both.
* The switching calibration records the acquisition chain: `cal.meta.acquisition` = driver,
  display name, identity (model, serial, firmware), sample rate, range, filter, CCLD.
  `tim.cal.calibrationContext(cal, cfg, daqMeta)` warns when a measurement uses another driver or
  module (model / serial) or other input settings (range, filter, CCLD, sample rate): `C_k` is a
  ratio of chain gains that include the DAQ input. A calibration without `meta.acquisition`
  (made before 1.2.0) is "unknown" and gives **no** warning (the existing test
  `calibrationContextChecks` expects none).

## 8. Timing, callbacks and the shared clock

**The session schedules the excitation on the received-sample count** (unchanged): in
`onBlock(n)` it switches the output on and triggers the sweep when `n` reaches the pre-roll, steps
the stepped-sine frequency at fixed targets, waits for the sweep (`waitComplete`) and switches the
output off. Every `onBlock` first runs `BlockCallback` (window: `drawnow`, so the Stop button is
processed) and throws `tim:session:stopped` after a Stop.

Rules for every acquisition driver:

1. `n` is the number of samples per channel reached so far; non-decreasing; the last call has
   `n ≥` the requested count.
2. While the device records, `onBlock` is called **at least every 0.25 s** (Stop stays responsive).
3. An error thrown by `onBlock` stops the acquisition (and the output of a combined device),
   keeps the data received so far for `collect`, and propagates **unchanged** (same identifier).
4. `onBlock` may call SignalSource methods of the same or another object (re-entrant; the driver
   holds no lock while calling it).
5. No timer or other asynchronous callback of a driver calls session or window code.

**Streaming, independent source** (33220A + LAN-XI): `onBlock` is called as data arrive; the source
acts when called, with a network / trigger latency. The analysis only needs the excitation to lie
inside the record (`tim.dsp.detectExcitation`, sweep gate) and uses channel ratios only.

**Block acquisition on a shared clock** (combined device, e.g. NI DAQ with analog output, audio
interface):

1. *Planning pass* - before anything is played, the driver calls `onBlock(n)` for
   `n = B, 2B, ...` up to the requested count without waiting (B: driver block, e.g. 2048).
   SignalSource calls made meanwhile are placed on the device timeline at the current `n`
   (sample-exact); `waitComplete` returns `true` when the timeline says the sweep has ended; an
   `outputOff` or a Stop during planning means nothing is played.
2. *Execution* - the driver plays the planned output while recording and calls `onBlock(nDone)`
   with the real progress (rule 2). All scheduled actions already fired, so the session's
   `onBlock` only processes Stop and the live view. A level, frequency or trigger call during
   execution raises `tim:gen:schedule`; `outputOff` always stops the output at once.

This keeps the session free of device cases: the same `measureSweep` / `measureStepped` /
`measureNoise` code drives both kinds of device, and the event samples it records
(`meas.events`) are exact on a shared clock.

## 9. Registry and configuration

### 9.1 Registry API (`+tim/+instr`)

| Function | Contract |
|---|---|
| `list = tim.instr.drivers()` | the registry: struct array `name`, `class` - one line per driver, in one file |
| `d = tim.instr.driverInfo(name)` | `describe()` plus `class` and `capabilities()`; unknown name: `tim:instr:unknownDriver` |
| `obj = tim.instr.create(role, cfg, ctx, other)` | creates the driver named by `cfg.generator.driver` (`role = 'source'`) or `cfg.daq.driver` (`'acquisition'`). Checks, **before any I/O**: the driver has the role (`tim:instr:role`); every product in `capabilities().products` is installed and licensed (`tim:instr:missingProduct`, naming the product and the driver); a simulation-only driver is not used in hardware mode (`tim:instr:simulationOnly`). Returns `other` itself when both roles name the same driver and it has both roles (one object, one connection). |

The session builds `ctx` (`mode`, `rig`, `progress`) and keeps the rig as `s.Rig` (simulation
hooks: `setMicPositionsForSimulation`, `setSimulationSample`, ground truth in tests). Optional
toolboxes are therefore needed only by the driver that uses them; the base requirement stays
MATLAB + Signal Processing Toolbox. A driver file must not call product functions outside
`create` and its instance methods (class loading must work without the product).

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
  section. Their **allowed values** come from the selected driver (`loads`, `maxVpp`,
  `sampleRates`, `bandFraction`, `ranges`, `filters`, `ccld`, `teds`) through `checkConfig`.
* Driver-specific settings live in a sub-struct named after the driver. It is merged onto
  `describe().defaults`, not onto `tim.app.defaultConfig`. A sub-struct named after another
  registered driver is kept without a warning (a file can hold the settings of several drivers
  and switch with `driver`); unknown names still give `tim:config:unknownField`.
* A combined driver reads its device settings from `daq.<name>`; `generator.driver` names the same
  driver.
* `validateConfig` keeps the generic checks and calls `checkConfig` of both selected drivers;
  a missing or unknown driver name gives `tim:config:driver` (the window shows such errors as
  "Check the settings").
* `tim.app.driveEstimate` takes the source impedance from `capabilities().source.outputImpedance_ohm`
  of `generator.driver` (today a fixed 50 Ω: a DAQ output of about 0 Ω driving an 8 Ω loudspeaker
  directly would be estimated (58/8)² ≈ 50 times too low - a safety defect for any new source).

### 9.3 Migration of older files (in `tim.app.loadConfig`, before the merge)

1. A top-level `lanxi` section and no `daq` section → `daq.driver = "lanxi"`, `daq.lanxi = lanxi`;
   `lanxi` is removed (no unknown-field warning).
2. `generator.host` / `port` / `timeout` outside a driver sub-struct and no `generator.keysight33220a`
   → moved into `generator.keysight33220a`.
3. A missing `driver` key → the default driver of the role (`keysight33220a`, `lanxi`).
4. Both layouts in one file → the new keys win; warning `tim:config:legacyField` names the ignored
   old keys.
5. The result has `formatVersion` 2; `saveConfig` writes the new layout.

`config/user_config.json` (formatVersion 1) is **not rewritten**: it loads with the same effective
settings, which a test compares field by field with the same file in the new layout. The
`config.json` of saved measurement folders loads the same way (File > Open measurement).
`example_config.json` and `sim_thin_screen.json` are converted to the new layout (templates show
the current format). Software 1.1.0 cannot read a formatVersion 2 file (not required).

## 10. Simulation

| Driver selection in a simulation configuration | What runs | Purpose |
|---|---|---|
| `keysight33220a` + `lanxi` (default) | the **real drivers** over their protocol mocks (`MockScpiTransport`, `MockLanXiHttp` / `MockLanXiStream`) on one `tim.sim.SimulatedRig` | end-to-end coverage of every SCPI command, REST request and the stream parser; the bus-traffic test; the GUI and end-to-end tests |
| `simcombined` for both roles | `tim.sim.SimulatedCombined`: the contract implemented directly on the rig; shared clock (`GenClockPpm = 0`, no trigger latency), block acquisition (section 8), no TEDS, no recorder states | proves that the contract is not shaped like 33220A + LAN-XI (§0 change B); runs calibration and measurement through the session and the hidden window; model for a real combined driver |

A new real driver brings its own protocol mock (WO-001 Part 2) and runs in simulation mode like the
two existing ones. The rig's generator state (`setGeneratorState`) uses the field names of the
33220A mock (`FUNC`, `FREQ`, `VOLT` in Vpp, `FREQ_STAR`, `FREQ_STOP`, `SWE_SPAC`, `SWE_TIME`,
`SWE_STAT`, `OUTP`); another source's mock maps its state onto them.

## 11. Safety duties (checked by `tests/TestInstrumentContract.m`)

SignalSource:

1. **Output off on creation**: `create` switches the output off before any other setting.
2. **Output off on `close`, in `delete` and after any error** a driver method raises after it may
   have changed the instrument (e.g. a read-back mismatch or an instrument error).
3. **Amplitude limit before every level command**: every method that sets a level checks it against
   `MaxVpp` first (`tim:gen:amplitude`) and sends no level command when it fails; `outputOn` re-checks the
   programmed level (read back where possible).
4. `outputOn` only when armed and configured; `configure*` leave the output off; `armOutput(false)`
   switches it off.
5. **Read-back**: `isOutputOn` asks the instrument; the window reports "confirmed off" only from it.
6. `outputOff` and `close` never throw and may be called any number of times, in any state.

Acquisition:

7. `acquire` stops on every exit path (normal end, error, Stop) and the next `acquire` works.
8. `shutdown` / `close` are idempotent, never throw and are bounded in time (`setTimeout`).
9. Data are raw volts at the input; the driver never applies a sensitivity (the LAN-XI channel setup
   keeps the module's 1 V/V transducer and rejects a stream unit other than V).
10. Integrity problems are reported in `info.integrity`, never hidden; partial data stay available
    through `collect`.

Combined device: 11. when the acquisition stops for any reason, the output stops too.

The session keeps its own duties on top (defence in depth): the output is armed only inside
`measure*`, every error path switches the output off, stops the acquisition and keeps the partial
data (`s.LastPartial`, emergency file).

## 12. Error identifiers

| Identifier | Raised by | Meaning |
|---|---|---|
| `tim:instr:unknownDriver` | registry | driver name not registered |
| `tim:instr:role` | registry | the driver does not have the role it is configured for |
| `tim:instr:missingProduct` | registry | a required MATLAB product is not installed or not licensed |
| `tim:instr:simulationOnly` | registry | a simulation-only driver in hardware mode |
| `tim:config:driver`, `tim:config:*` | `validateConfig`, `checkConfig` | missing / unknown driver; a setting the driver does not support |
| `tim:config:legacyField` (warning) | `loadConfig` | old and new layout in one file |
| `tim:gen:notArmed` | source | `outputOn` without `armOutput(true)` |
| `tim:gen:amplitude` | source | level above `MaxVpp`, not positive, or below the instrument minimum |
| `tim:gen:mode` | source | call not valid in the configured mode (unconfigured `outputOn`, `setFrequency` outside sine, `triggerSweep` outside sweep) |
| `tim:gen:sweep` | source | invalid sweep settings |
| `tim:gen:unsupported` | source | waveform or feature not in the capabilities |
| `tim:gen:verify` | source | read-back differs from the request |
| `tim:gen:schedule` | block source | level / frequency / trigger call during the execution of a block |
| `tim:session:stopped` | session (`onBlock`, steps) | operator Stop; passes through drivers unchanged |
| `tim:<driver>:*`, `tim:scpi:*` | driver | protocol and transport faults (e.g. `tim:lanxi:http`, `tim:scpi:timeout`, `tim:gen:scpiError`); callers treat them as instrument faults |

## 13. Design decisions

| # | Decision | Alternatives considered | Reason |
|---|---|---|---|
| D1 | Abstract handle classes with a common base `tim.instr.Instrument` | duck typing as today; structs of function handles; a separate interface for combined devices | MATLAB enforces abstract methods; `isa` documents the role; the common base lets one class take both roles without member conflicts (MATLAB multiple-inheritance rules) |
| D2 | The existing drivers **become subclasses** (`Keysight33220A < SignalSource`, `LanXi < Acquisition`) | thin adapter classes around them | every SCPI / REST command stays in the same method, so the bus traffic is identical by construction; the driver tests keep constructing them directly; `s.Gen.Identity`, `s.Daq.Teds`, `s.Daq.Http` stay reachable for scripts and tests |
| D3 | Class-level (static) `describe`, `capabilities`, `connectionSteps`, `checkConfig` | instance methods only | the checklist, lamps, `validateConfig` and the drive estimate are needed before connecting |
| D4 | The session keeps its sample-count schedule; block devices run it in a planning pass on the shared clock | a declarative excitation plan built by the session; device-specific `measure*` variants | no change to the measurement code and its Stop / output-off paths (the highest risk of the refactor, WO §6.2); identical bus traffic; one schedule for both kinds of device |
| D5 | Registry = one list file + a static factory per class | scanning `+tim/+instr` with `meta.package`; class names in the configuration | explicit and fast; a typo in the configuration gives a clear error instead of running arbitrary code |
| D6 | Role sections + `driver` + a sub-struct named after the driver; generic role settings stay outside; old files migrated on load | flat keys per driver; moving every acquisition key into the driver sub-struct | smallest change for the user: only the connection settings move; the acquisition settings mean the same for every DAQ, only their allowed values differ |
| D7 | `user_config.json` stays in the old layout | rewrite it in the new layout | it is the owner's lab file; loading it unchanged proves the migration every day |
| D8 | Simulation: real drivers over protocol mocks + one contract-level combined driver | contract-level `SimulatedSource` / `SimulatedAcquisition` for the app tests (WO task 7 text) | the protocol-mock path is the only one that exercises the real drivers end to end (and the bus-traffic test needs it); the combined driver covers both contracts at contract level and the case change B asks for; a separate simulated pair would add code without new coverage |
| D9 | Products checked by the registry before any I/O | let MATLAB fail with "Undefined function" | clear `tim:instr:missingProduct`; the base requirements stay MATLAB + Signal Processing Toolbox |
| D10 | Session properties keep their names `Gen` and `Daq` (role names; one object for both roles when combined) | rename to `Source` / `Acquisition` | scripts, examples and many test lines use them; the names already describe roles |
| D11 | Device flags are worded by the driver (`integrity.channelFaults`) | flag codes interpreted by the session | the session holds no LAN-XI vocabulary and today's texts stay |
| D12 | Source impedance from the driver in the drive estimate | keep 50 Ω | the loudspeaker protection would under-estimate the power of a low-impedance source about 50 times |
| D13 | The calibration records the acquisition chain; unknown (old) calibrations give no warning | warn for every old calibration | `C_k` depends on the DAQ inputs; old lab calibrations stay usable without noise |
| D14 | One interleaved bus log (SCPI, REST, stream) as the regression fixture | one log per instrument | also catches order changes between the instruments, e.g. `OUTP ON` before the recording has started |

## 14. Implementation plan

Each stage ends with the full test suite and `TestBusTraffic` passing unchanged (the fixture is
never regenerated during WO-001).

**Stage A - contract, existing drivers, registry, contract tests (WO tasks 1, 2, 8 and the
registry).**

1. `tim.instr.Instrument`, `SignalSource`, `Acquisition` (abstract; help text = sections 2-4).
2. `Keysight33220A < SignalSource`: static members; `identity`, `metadata`, `setTimeout`
   (transport), `isOutputOn(timeout)` (same `OUTP?` query). No other method body changes.
3. `LanXi < Acquisition`: static members; `create` takes over the connect steps `lanxi` / `idle`
   (same requests in the same order); `identity` from `module/info`; `metadata`; `recent`
   (parser tail), `isAcquiring`, `rawBytes`, `close` = `shutdown`, `setTimeout` (HTTP);
   `integrity.channelFaults` from the DataQuality events; `prepare` still accepts `c.connector`.
4. `tim.instr.drivers`, `driverInfo`, `create` with the role / product / mode checks.
5. `tests/TestInstrumentContract.m`, parameterised over the registered drivers (each in
   simulation mode on its mock): output off after creation, close and an error; amplitude limit;
   sweep round trip; `acquire` shape, units and integrity; `shutdown` idempotent; Stop during
   `acquire`; metadata and identity complete; step keys unique.
   The session and the window are not touched in stage A.

**Stage B - configuration, session, metadata, calibration, contract-level simulation (WO tasks
3, 4, 6, 7).**

1. `defaultConfig` formatVersion 2; `loadConfig` migration (9.3); `validateConfig` generic +
   `checkConfig`; `driveEstimate` source impedance; `example_config.json`, `sim_thin_screen.json`
   converted; tests: old `user_config.json` = new layout, saved `config.json` loads.
2. `MeasurementSession`: `ctx` + registry; no instrument names (`grep -i "lanxi\|lan-xi\|33220"`
   empty); `Http` property removed (the stream fault injection in `TestEndToEnd` uses
   `s.Daq.Http`); `signalCheck` from `integrity`; `close(true)` via `setTimeout`; log lines from
   display name and identity.
3. `collectMetadata` from `metadata()`; `cal.meta.acquisition`; `calibrationContext(cal, cfg,
   daqMeta)` (from `processMeasurement` with `meas.metadata.daq`, from the window with the
   session's).
4. `tim.sim.SimulatedCombined` (`simcombined`): registered, in the contract tests, calibration +
   measurement through the session and the hidden window with no driver-specific code there.
5. `tim.val.testA_acquisition` without LAN-XI parser fields; examples use `identity()` /
   `metadata()` instead of `s.Daq.Info`.

**Stage C - window from the drivers, documentation (WO tasks 5, 9).**

1. Checklist keys and labels from `connectionSteps` (+ the session's steps); lamp labels,
   tooltips and the lamp of each step from the driver; texts composed from the display names, so
   they read as today for the two existing drivers.
2. Identity display: INSTRUMENTS lamps and Setup > Connection show the display name, model, serial
   and firmware of each role; no selection controls (owner decision §0.2).
3. Live view via `s.Daq.recent`, background-work check via `isAcquiring`, "output off
   (confirmed)" via `s.Gen.isOutputOn(1)`; `grep` acceptance for `Tubebench.m`.
4. Docs: this document (status: implemented), user guide (choosing instruments in the
   configuration, identity display), installation guide (products per driver), README structure
   and test count, operator texts in `tim.app.msg` ("LAN-XI inputs" → the DAQ inputs).

Part 2 (guide, templates, skill, dry run) and the owner's hardware check (§0.3) follow stage C.

## Appendix A - Inventory of today's instrument-specific code (commit 8ff47f3)

Line numbers as of 8ff47f3. "→" names the stage that changes it.

### A.1 `tim.app.MeasurementSession`

| Lines | Use | → |
|---|---|---|
| 6, 10-11, 15, 513, 686 | help / comments name LAN-XI, `MockScpiTransport`, `MockLanXiHttp` | B |
| 27-30 | properties `Gen`, `Daq`, `Rig`, `Http` (`Http` = LAN-XI REST client or its mock) | B: `Http` removed |
| 50-52 | `ProgressCallback` doc lists the keys `gen, lanxi, idle, open, teds, setup` | B |
| 77-78 | step `gen`: `'simulated generator'`, `'%s:%d (SCPI over TCP)'` from `generator.host/port` | A/B: driver `create` |
| 81-89 | creates `SimulatedRig`, `MockScpiTransport`, `MockLanXiHttp`, `RecordingStream`, `ScpiTcpTransport(generator.host, port, timeout)`, `LanXiHttp(lanxi.host, lanxi.timeout)`, `LanXiTcpStream` | B: registry |
| 91-93 | `Keysight33220A(tr, 'MaxVpp', generator.maxVpp, 'Load', generator.load)`; `Gen.Identity.raw` in log and step | B |
| 94-107 | steps `lanxi` (`'simulated LAN-XI module'`, `'%s (REST, Open API)'`), `idle`; `LanXi(Http, factory, 'Host', lanxi.host)`; `moduleInfo` (`model`, `serial`, `firmware`, `moduleState`); return to Idle via `Daq.shutdown` | A/B: LanXi `create` |
| 120-126 | channel setup struct incl. `connector` = `cfg.lanxi.connector`; `Daq.ProgressFcn`; `Daq.prepare` | B |
| 130 | `resolveSensitivities(..., Daq.Teds, ...)` | contract property |
| 143-150 | settle step text `'CCLD + %s high-pass'`, only in hardware mode | C (text) |
| 171-188 | signal check: `info.qualityEvents`, `signalIds`, texts `'LAN-XI flag INVALID (cable or CCLD fault)'`, `'clipped (LAN-XI flag)'`, range parsed with `sscanf(acquisition.range)` | B: `integrity` |
| 205 | comment: steps reported by `LanXi.prepare` cannot throw | B |
| 240, 567, 573 | `Daq.acquire`, `Daq.collect` | contract |
| 248-348 | `Gen.configureSweep/Sine/Noise`, `outputOn`, `triggerSweep`, `waitComplete(5)`, `setFrequency`, `outputOff`, `armOutput` | contract (unchanged) |
| 463-481 | `Rig.MicPosOfChannel`, `Rig.Sample` (simulation hooks) | stays (rig from `ctx`) |
| 520-533 | fast close: `Http` and `Gen.Transport` (`isa(t, 'tim.instr.Keysight33220A')`) `setTimeout(2)`; `Gen.close`; `Daq.shutdown` | B: `setTimeout`, `close` |
| 578-579, 606-607 | raw stream: `Daq.LastStream` is a `tim.instr.RecordingStream` → `bytes()` | B: `rawBytes` |
| 624-645 | excitation confirmation: `generator.maxVpp`, `generator.load` | generic (stays) |
| 628, 641, 667 | `Gen.outputOff` in error / Stop paths | contract |

### A.2 `tim.gui.Tubebench`

| Lines | Use | → |
|---|---|---|
| 22, 465, 1059, 1898 | comments "LAN-XI data stream / setup" | C |
| 212, 1515, 2099, 2881 | `Session.Gen.outputOff()` (close request, error, Stop, closing) | contract |
| 561-568 | mode label and Connect / Disconnect tooltips: "generator and LAN-XI module", "read TEDS", "LAN-XI module back to Idle" | C |
| 572-579 | lamps `{'Generator', 'LAN-XI', 'ch1'...'ch4'}`, tooltips `'function generator 33220A'`, `'LAN-XI module'` | C: `labels`, `displayName` |
| 732-733 | Connection view description "generator, LAN-XI, TEDS" | C |
| 763 | channel table column "TEDS s/n" | stays (TEDS is a standard) |
| 1063 | `s.Daq.Stream` non-empty = stream running | C: `isAcquiring` |
| 1078-1085 | `connKeys` / `connLabels`: the nine keys and labels, "Function generator 33220A (SCPI)", "LAN-XI module (REST)", "LAN-XI recorder state Idle" | C: `connectionSteps` |
| 1126-1127, 637 | frequency fields limited to `0.45 * sampleRate` | C: `bandFraction` |
| 1568-1583 | output read-back `s.Gen.Transport.query('OUTP?', 1)` | C: `isOutputOn(1)` |
| 1604-1621 | lamp 1 tooltips `'Generator (Keysight 33220A) – details in Setup > Connection'` | C |
| 1696-1702 | live view: `Daq.Parser.samplesAvailable/tail`, `Daq.SampleRate` | C: `recent` |
| 1890 | log "generator output OFF, LAN-XI Idle" | C |
| 1959-1977 | `onProgress`: key `gen` → lamp 1; `lanxi, idle, open, setup` → lamp 2; `teds` → refresh cards | C: step `role` |
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
| `loadConfig` | merge onto defaults; no migration yet | B: section 9.3 |
| `saveMeasurement` | metadata from `collectMetadata`; `config.json` | unchanged |
| `driveEstimate` (5-22, 51-55) | fixed 50 Ω source impedance of the 33220A | B: `outputImpedance_ohm` |
| `msg` (78, 83) | calibration prompt "never the cables or LAN-XI inputs" (en / ko) | C |
| `calibrationContext` | compares geometry, temperature, mode, Test E - not the instruments | B |
| `resolveSensitivities` (9) | TEDS cell from `LanXi.detectTransducers` | contract `Teds` |
| `switchingCorrection` (8) | comment "LAN-XI input" | C (comment) |
| `checkIntegrity` | integrity of decoded LAN-XI data (`info.qualityEvents`, `stats`, `unit`) | A: LanXi uses it; generic part for other drivers |
| `val.channelIdentification` (20-21, 46) | `session.Daq.acquire`, `Daq.SampleRate` (no output) | contract |
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

## Appendix B - Bus-traffic regression test

`tests/TestBusTraffic.m` (added in stage 1, passing on 8ff47f3 = e8fb4fb code) runs a simulated
session through the protocol mocks: connect + `prepareAcquisition` + 1 s signal check; a complete
switching calibration with the simulation default prompt (repeated configuration I, empty-tube
check); one swept-sine measurement (2 repetitions); one stepped-sine measurement (5 steps, 2
repetitions); one noise measurement; close. `tim.instr.mockBusLog` collects every SCPI command and
response, every REST request with its body and every stream open / close of all mocks in **one
ordered log** (663 entries incl. 6 section markers), compared entry by entry with
`tests/fixtures/bus_traffic_sim.txt`; the first difference is reported with its section, the
entry before it and the differing character.

Deterministic: `rng(1, 'twister')`, `SimulatedRig` seed 1, mock stream seed 7; the mocks change
state at once (one status poll per wait) and deliver a fixed block per read, so every scheduled
generator command falls on the same block. Normalised: the body of `PUT /rest/rec/module/time`
(wall-clock ms). Not logged: stream reads (their number depends on the 0.3 s drain after a stop)
and client time-outs (not on the bus). The fixture is regenerated only after an intended change of
the bus traffic: `addpath tests; TestBusTraffic.writeFixture()`.
