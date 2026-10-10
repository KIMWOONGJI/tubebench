# Work order WO-001: instrument interface and "add an instrument" skill

| | |
|---|---|
| Target version | 1.2.0 (next version; not before the start-up work of 2026-10-10 is merged) |
| Status | planned - written 2026-10-10, not started |
| Requested by | the owner (Woongji Kim) |
| Scope | software only; hardware tests need the owner's approval and presence |
| Depends on | nothing else; the in-tube hardware verification stays on hold independently |

## 1. Goal

tubebench supports exactly one function generator (Keysight/Agilent 33220A, SCPI over TCP) and
one acquisition module (HBK LAN-XI Light 3676, Open API). Other instruments must be connectable
later without rewriting the measurement session, the GUI and the configuration each time.

1. **Part 1 - instrument interface:** a documented contract for the two instrument roles, a
   driver registry chosen by the configuration, and the GUI/metadata/simulation driven by the
   driver. The two existing instruments become the first two drivers; their behaviour on the bus
   does not change.
2. **Part 2 - skill:** a Claude Code skill `.claude/skills/add-instrument/` (committed with the
   repository) that guides adding a driver for an instrument that is not supported yet: collect
   facts, judge suitability, write the driver, mock and tests, verify step by step with the
   owner's approval.

Non-goals: supporting a new instrument in this version (unless the owner names one), changing the
analysis, changing the calibration method, a standalone executable.

## 2. Current state (2026-10-10, commit 3d50c6f and later)

- Drivers are already separate classes in `+tim/+instr`:
  `Keysight33220A` (transport `ScpiTcpTransport`, mock `MockScpiTransport`) and `LanXi`
  (`LanXiHttp`, `LanXiTcpStream`, `LanXiStreamParser`, mocks `MockLanXiHttp`, `MockLanXiStream`,
  `RecordingStream`). Reference notes: `docs/ref_33220A_scpi.md`, `docs/ref_lanxi_openapi.md`.
- The session uses an **implicit** interface:
  - generator: `Identity`, `configureSine(f, vpp)`, `setFrequency(f)`, `configureSweep(s)`,
    `configureNoise(vpp)`, `armOutput(tf)`, `outputOn`, `outputOff` (14 call sites),
    `isOutputOn`, `triggerSweep`, `waitComplete(timeout)`, `close`, `Transport`;
  - acquisition: `moduleInfo`, `prepare(cfg)`, `acquire(n, onBlock, timeout)`, `collect(n)`,
    `shutdown`, `Teds`, `Stream`, `LastStream`, `ProgressFcn`.
- **Hard-wired:** `tim.app.MeasurementSession.connect` creates `tim.instr.Keysight33220A` and
  `tim.instr.LanXi` by name (simulation: `MockScpiTransport` + `MockLanXiHttp` on
  `tim.sim.SimulatedRig`).
- **Device-specific text and settings outside the drivers:** "LAN-XI" appears 17 times in
  `+tim/+gui/TubeApp.m` and 19 times in `MeasurementSession.m` (connection checklist: LAN-XI
  module (REST), recorder state Idle, open recorder, TEDS, channel setup → streaming; lamps
  "Generator", "LAN-XI"). Configuration sections `generator` (host, port, timeout, maxVpp, load)
  and `lanxi` (host, timeout, connector); `acquisition.sampleRate` limited to the 3676 rates,
  `range` "10 Vpeak", `filter` "0.7 Hz". `tim.app.collectMetadata` stores the LAN-XI setup.
- **Simulation is protocol-level:** `SimulatedRig` is driven through emulated 33220A SCPI and
  LAN-XI REST/stream. A new instrument would also need a protocol mock just to run the app tests.
- **Calibration context** (`tim.cal.calibrationContext`) compares geometry, temperature, mode and
  Test E, but not the instruments. C_k is a ratio of chain gains (microphone, cable, CCLD supply,
  DAQ input), so a calibration must be flagged when the acquisition module or its input changes.

## 3. Requirements that follow from the measurement method

Use these to judge whether an instrument can work (Part 2, step 2). "Must" items are hard limits.

| Role | Requirement | Why |
|---|---|---|
| Acquisition | **Must:** ≥ 4 analog inputs sampled **simultaneously on one clock** | transfer functions between channels; skew is a phase error |
| Acquisition | **Must:** IEPE/CCLD supply (4 mA) per channel, or an external supply | B&K 4957 microphones |
| Acquisition | **Must:** sample rate ≥ 2.2 × analysis fMax (4.5 kHz → ≥ 10 kS/s; now 16 384 S/s) with anti-alias filter | spectral analysis to 4.5 kHz |
| Acquisition | **Must:** continuous gap-free streaming or block acquisition of ≥ 10 s, with gap/overload detection | swept sine with pre/post-roll; integrity check |
| Acquisition | Should: AC coupling/high-pass ≤ 1 Hz, input range ≤ 10 V peak, ≥ 24 bit, TEDS reading | dynamic range; sensitivities from TEDS |
| Generator | **Must:** output can be switched off by command and the off state read back | safety rules (output off on connect, error, close) |
| Generator | **Must:** an amplitude limit that the driver enforces before every level command | loudspeaker/power limit |
| Generator | **Must:** at least one of logarithmic sweep, stepped sine, noise; frequency 80 Hz–5.5 kHz | excitation signals |
| Generator | Should: software (bus) trigger, completion query (*OPC? or equivalent) | timing of the sweep in the record |
| Both | No hardware synchronisation between generator and DAQ is needed | the estimator uses channel ratios only (theory.md §4) |
| Both | One device may take both roles (e.g. a DAQ card with analog output) | factory must allow one object for both roles |

## 4. Part 1 - instrument interface (tasks)

1. **Contracts.** Abstract handle classes with documented methods, properties and duties:
   - `tim.instr.SignalSource` (generator): the methods listed in §2 plus `capabilities()`
     (waveforms, frequency range, max Vpp, trigger, read-back), `connectionSteps()` (keys and
     texts for the checklist) and `metadata()`. Duties: output off on creation, on `close`, in
     `delete` and after any error; enforce the amplitude limit before every level command;
     read back and report whether the output is really off.
   - `tim.instr.Acquisition` (DAQ): `moduleInfo`, `prepare(cfg)` (channels, coupling/CCLD,
     range, TEDS), `acquire(n, onBlock, timeout)` returning volts (n × C) and an integrity
     struct (gaps, overload/invalid flags, peak fraction of range), `collect`, `shutdown`
     (idempotent), `capabilities()` (channels, sample rates, ranges, CCLD, TEDS, simultaneous
     sampling), `connectionSteps()`, `metadata()`.
   - Write the contract down in `docs/instrument_interface.md` (signatures, units, error IDs,
     safety duties, threading/callback rules: `onBlock` keeps Stop responsive).
2. **Existing drivers.** Make `Keysight33220A` a `SignalSource` and `LanXi` an `Acquisition`
   (subclass or thin adapter). Keep every SCPI/REST command identical.
3. **Registry and configuration.** `tim.instr.create(role, cfg, mode)`; new keys
   `generator.driver` (`"keysight33220a"`) and `daq.driver` (`"lanxi"`), driver-specific settings
   in a sub-struct named after the driver. `tim.app.loadConfig` maps old files (no `driver` key,
   `lanxi` section) to the new layout; `validateConfig` asks the driver to validate its part.
   `config/user_config.json` must keep loading unchanged.
4. **Session.** `MeasurementSession.connect` uses the registry; no instrument names or
   LAN-XI-specific strings remain in the session (progress keys and texts come from
   `connectionSteps()`).
5. **GUI.** The connection checklist, the instrument lamps, tooltips and the acquisition choices
   (sample rate, range) come from the drivers. Keep today's look for the two existing drivers.
6. **Metadata and calibration.** `collectMetadata` stores `metadata()` of both drivers; the
   calibration records the acquisition module identity (model, serial, input settings) and
   `calibrationContext` warns when a measurement uses another module or input range.
7. **Simulation at contract level.** `tim.sim.SimulatedSource` / `tim.sim.SimulatedAcquisition`
   implement the contracts directly on `SimulatedRig`, so app tests do not need a protocol mock.
   Keep the protocol mocks for the two drivers' own tests.
8. **Contract tests.** `tests/TestInstrumentContract.m`, parameterised over all registered drivers
   (each with its mock): output off after creation/close/error, amplitude limit enforced, sweep
   configuration round trip, `acquire` shape/units/integrity flags, `shutdown` idempotent, Stop
   during `acquire`, metadata complete.
9. **Docs.** `docs/instrument_interface.md` (new), user guide (choosing the instruments in the
   configuration), installation guide if needed, README structure section.

**Acceptance for Part 1**
- All existing tests pass; new contract tests pass for both drivers.
- Bus behaviour unchanged: record the SCPI and REST traffic of a simulated connect, calibration
  and measurement before and after the refactor (mock transports log every command) - identical.
- `grep -i "lanxi\|lan-xi\|33220"` finds nothing in `MeasurementSession.m` and `TubeApp.m`
  outside driver-provided data.
- An old `user_config.json` and saved measurement folders still load (File > Open measurement).

## 5. Part 2 - skill `.claude/skills/add-instrument/`

`SKILL.md` (plus `templates/`): the procedure Claude follows when the owner wants to connect an
instrument that has no driver.

1. **Collect facts:** model, firmware, role(s), interface (TCP SCPI, VISA/USB-TMC, serial, REST,
   NI-DAQmx via Data Acquisition Toolbox, vendor SDK/.NET/DLL), IP or port, the programming manual
   (ask the owner for the PDF; never guess commands), licences/toolboxes needed (installed: Data
   Acquisition Toolbox 4.6, Instrument Control Toolbox 4.7).
2. **Judge suitability** against §3; report each must/should item with the manual page that
   proves it. If a must item fails, stop and say why and what would work instead.
3. **Write the driver** from `templates/`: driver class implementing the contract, transport,
   protocol mock, defaults in `defaultConfig`, `docs/ref_<instrument>.md` with a source for every
   command (manual section/page), registry entry.
4. **Test offline:** driver unit tests on the mock, the contract test suite, full test suite.
5. **Verify on hardware, step by step, each step only after the owner agrees and is present:**
   (a) connect and identify with the output off; (b) acquisition with the output off (noise
   floor, integrity flags); (c) lowest-level excitation into the tube; (d) switching calibration
   and Test E. Record results in `docs/hardware_status.md`. Never mark a hardware step passed
   without a real measurement.
6. **Report:** suitability table, files, tests, what was verified on hardware and what not.

Rules the skill must repeat: no change of IP addresses, firewall, firmware, licences or drivers
without approval; ask before raising excitation levels; raw data are never modified; output off
first; no clicking or typing on the owner's screen; commit, never push unless asked.

**Acceptance for Part 2**
- Dry run: use the skill to add a `demo` source that wraps the simulator through a protocol mock
  of its own; it must pass the contract tests without touching the session or the GUI.
- If the owner names a real candidate instrument, a suitability report for it from the manual.

## 6. Order of work, estimate, risks

1. Part 1 tasks 1–2 and 8 first (contract, existing drivers, contract tests), then 3–7, then 9.
   Medium-size refactor (session, GUI, config, tests); about one working day with the full test
   suite runs. Part 2: small (one skill file, templates, dry run).
2. Risks: changing the session can break the Stop/close safety paths - keep the existing tests on
   closing, Stop and output-off and add contract tests before refactoring; the start-up work of
   2026-10-10 (deferred view building) touches `TubeApp.m` too - start after it is merged.
3. Open questions for the owner: is there a concrete second instrument (another generator, an NI
   or other DAQ, a combined device)? Designing against a real second device makes the contract
   realistic. Should the instrument choice be selectable in the GUI or only in the configuration?
