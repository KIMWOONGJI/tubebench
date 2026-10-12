# Work order WO-001: instrument interface and "add an instrument" skill

| | |
|---|---|
| Target version | 1.2.0 (next version; not before the start-up work of 2026-10-10 is merged) |
| Status | **done**: software complete on branch `wo-001` (2026-10-11, review fixes included; section 7); owner decisions of 2026-10-11 recorded and implemented, and the review of those stages fixed (§0 item 6); **the owner's hardware check passed on 2026-10-12** (§0.3, ten steps, `docs/hardware_status.md`); merged into `main` as version 1.2.0 on 2026-10-12. Follow-up work (after-merge items, the fixes from the check): `docs/workorder_after_hardware_check.md` |
| Requested by | the owner (Woongji Kim) |
| Scope | software only; hardware tests need the owner's approval and presence |
| Depends on | nothing else; the in-tube hardware verification stays on hold independently |

## 0. Owner decisions and design changes (2026-10-11) - these override older text below

1. **No concrete second instrument.** The contract is designed without one (see change B).
2. **Instrument choice only in the configuration** (`generator.driver`, `daq.driver`); no
   selection controls in the GUI. The GUI **shows which instruments are in use**: the driver's
   display name and the identity the instrument reports (model, serial, firmware) in the
   INSTRUMENTS section / connection view and in the metadata of every measurement.
   A user with another instrument either selects an existing driver in the configuration or
   first adds a driver (with the guide below, or with the skill in Claude Code).
3. **Hardware check at the end:** when the software work is done, the owner reconnects the
   33220A and the LAN-XI 3676; then connect and identify (output off), a short measurement at a
   level the owner approves (not above the configured default 0.2 Vpp), Stop and output-off
   checks. Only after that is the work marked hardware-verified and merged into `main`
   (version 1.2.0). Until then: software-verified only.
4. **Change A - guide and templates first, skill as a thin layer.** The knowledge for adding an
   instrument lives in files that work without Claude Code: `docs/instrument_interface.md`
   (contract), `docs/adding_an_instrument.md` (step-by-step guide for a person), templates outside
   `.claude/` (e.g. `templates/instrument/`) and the contract tests. The skill
   `.claude/skills/add-instrument/SKILL.md` only runs that procedure (facts → suitability →
   driver from the templates → offline tests → step-by-step hardware verification) and repeats
   the safety rules; it must not hold information the guide lacks.
5. **Change B - the contract must not be shaped like 33220A + LAN-XI.** The likely instruments
   of other labs are an NI DAQ (Data Acquisition Toolbox) or an audio interface (Audio Toolbox):
   one device with analog output and inputs on a **shared clock**, often block-wise instead of
   streaming acquisition, without TEDS or recorder states. Therefore:
   - one driver object may take both roles; capabilities declare the roles, whether output and
     input share a clock, streaming vs. block acquisition, TEDS yes/no, and the MATLAB products
     the driver needs;
   - optional toolboxes are needed only by the driver that uses them: the registry reports a
     clear error (`tim:instr:missingProduct`) when a selected driver lacks one, and the base
     requirements stay MATLAB + Signal Processing Toolbox;
   - prove it with a deliberately different **simulated combined driver** (output + 4 inputs,
     shared clock, block acquisition, no TEDS) at contract level on `SimulatedRig`: registered,
     selectable in the configuration, passing the contract tests and a simulated calibration +
     measurement through the session and the (hidden) GUI without driver-specific code there.
6. **Decisions of 2026-10-11 - every pending recommendation approved by the owner**
   (`docs/instrument_interface.md` section 13.4):
   - D7: `config/user_config.json` stays in the old layout until after the hardware check (§0.3);
     then it is rewritten in the new layout - after that check, not before.
   - D8 (simulation through the real drivers on their mocks plus `simcombined`), D43 (the demo
     source stays registered, simulation only) and D45 (a driver's defaults only in its
     `describe().defaults`): as built.
   - D24: the session sets `AbortFcn = @() Gen.outputOff()` at connect, so on the abnormal end of
     an acquisition the output goes off before the acquisition's stop sequence - implemented; the
     fault fixture regenerated from the code (no hand edit left).
   - The bus order of the fault-fixture scenario "window closed twice inside a sweep" (ends with
     `tim:instr:closed`) and after a Stop during the LAN-XI connect step: approved as built.
   - Audit follow-ups on the same branch (not part of the interface): every swept-sine line
     centred on its frequency and the sweep gate at an end without margin (`docs/theory.md`
     section 4); File > Open measurement… offers the recorded microphone mapping for Reprocess
     (default) when the configuration's differs (`tim.app.useRecordedMapping` for scripts); the
     hardware-only session branches tested on test-only drivers without I/O
     (`tests/TestSessionHardwareMode`); a test-only hook for a Stop before the session exists; GUI
     timing tests that time only the operation they guard.
   - Review of these stages (2026-10-11), four findings, all fixed: the configuration check uses
     the sweep-gate limits of the analysis (outer line edges, `tim.dsp.sweepGateLimits`: 91 /
     4952 Hz for 120–4500 Hz, it used 92 / 4950 Hz); the Time signals note names an end without
     the margin, whose switching transient is analysed; a close request or Stop during an action
     of a window without a session cancels that action's questions (Open measurement… closed only
     after a second request); `TestGui/closeDuringMeasurementStopsFirst` closes the window inside
     the acquisition (its timer fired before the measurement had started).
   - The hardware check follows (the owner reconnects the instruments); only after it: version
     1.2.0 and the merge into `main`.

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
  `+tim/+gui/Tubebench.m` and 19 times in `MeasurementSession.m` (connection checklist: LAN-XI
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
Reworded after the design review of 2026-10-11 (`docs/instrument_interface.md` section 13.2,
issues 3, 5, 6, 11 and 21) and the review of the implementation (section 13.3, findings 9 and 12:
the IEPE current, `vppAtFullScale` of a combined driver).

| Role | Requirement | Why |
|---|---|---|
| Acquisition | **Must:** ≥ 4 analog inputs sampled **simultaneously on one clock** | transfer functions between channels; skew is a phase error |
| Acquisition | **Must:** IEPE/CCLD supply per channel with a constant current that the microphone data sheet allows (the lab's LAN-XI supplies 4 mA; compare the device's IEPE current with the B&K 4957 data sheet), or an external supply | B&K 4957 microphones |
| Acquisition | **Must:** sample rate ≥ 2.2 × analysis fMax (4.5 kHz → ≥ 10 kS/s; now 16 384 S/s) with anti-alias filter, run at exactly the configured rate | spectral analysis to 4.5 kHz; a coerced rate mislabels the frequency axis |
| Acquisition | **Must:** continuous gap-free recording of ≥ 10 s with gap/overload detection, delivering data **while it records** (streaming, or background acquisition with a polling read); a device that delivers only whole blocks works only when it is also the generator (shared clock) | swept sine with pre/post-roll; integrity check; the session switches a separate generator on and off as samples arrive |
| Acquisition | Should: AC coupling/high-pass ≤ 1 Hz, input range ≤ 10 V peak, ≥ 24 bit, TEDS reading, data in volts (an input in full-scale units with an unknown gain gives levels in dB re FS only, unless its volts per full scale are measured) | dynamic range; sensitivities from TEDS; levels in Pa |
| Generator | **Must:** output can be switched off by command (no waveform, 0 V or disconnected - an analog output that keeps its last value must be set to 0 V), and its state read back from the instrument or, for the output of a shared-clock device that is also the DAQ, from the device session (task stopped, 0 V written). A generator that cannot report its state is accepted only when the owner allows it explicitly in the configuration (`generator.allowUnconfirmedOff`); the window then says so after every stop | safety rules (output off on connect, error, close) |
| Generator | **Must:** an amplitude limit that the driver enforces before every level command; an output programmed in full-scale units (audio interface) needs its measured volts per full scale at a fixed knob position (`generator.<driver>.vppAtFullScale`; `daq.<driver>.vppAtFullScale` for a combined driver) | loudspeaker/power limit |
| Generator | **Must:** a single logarithmic swept sine (the switching calibration and Test E always sweep); stepped sine and noise optional; frequency 80 Hz–5.5 kHz | excitation signals; the calibration method does not change |
| Generator | Should: software (bus) trigger, completion query that waits for the end of the sweep (*OPC? or equivalent, or time-based) | timing of the sweep in the record |
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
- `grep -i "lanxi\|lan-xi\|33220"` finds nothing in `MeasurementSession.m` and `Tubebench.m`
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
   protocol mock, defaults in `defaultConfig` (superseded: the driver's defaults are in its
   `describe().defaults`, not in `tim.app.defaultConfig` - `docs/instrument_interface.md` D45 and
   `docs/adding_an_instrument.md` section 6), `docs/ref_<instrument>.md` with a source for every
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
   2026-10-10 (deferred view building) is merged (3e24bc2), so `Tubebench.m` is free.
3. Open questions for the owner: answered on 2026-10-11, see §0.

## 7. Implementation notes (2026-10-11)

**What was built** (branch `wo-001`, base 8ff47f3; details, decisions D1-D47 and the review in
`docs/instrument_interface.md` sections 13 and 14):

* Part 1: the contract classes `tim.instr.Instrument`, `SignalSource` and `Acquisition`; the 33220A
  and LAN-XI drivers implement them with every SCPI command and REST request of the normal path
  unchanged (bus-traffic fixtures of the normal and the fault paths, recorded on the code before
  WO-001); the registry (`drivers`, `driverInfo`, `create`: every check before any I/O, product
  check); configuration `formatVersion` 2 (`generator.driver`, `daq.driver`, driver sub-structs;
  `migrateConfig` reads old files and scripts); the session and the window through the registry,
  naming no instrument; metadata and the calibration's DAQ chain; the simulated combined device
  `simcombined` (change B); contract tests over every registered driver.
* Part 2: the guide `docs/adding_an_instrument.md`, the templates `templates/instrument/` (a source,
  an acquisition and a combined driver, each with its protocol mock and test; a reference document;
  configuration snippets), the skill `.claude/skills/add-instrument/`, and the demo source `demo`
  made by following the guide (dry run).
* Fix stage: three reviews of the implementation, 12 findings, all addressed (contract section
  13.3): loading only warns about driver limits (files of 1.1.0 load again), 0 V after the stop on
  every end of a combined device, the contract cases for any block size, closing during connect
  and `prepare`, misplaced settings, guidance for an NI device session. Verified in simulation
  only: full suite 299 / 299 (21 test classes) in batch MATLAB, `TestBusTraffic` 5 / 5 with both
  fixtures unchanged.

**Deviations from the plan, and why**

1. Task 7: no contract-level `SimulatedSource` / `SimulatedAcquisition`. The lab drivers run on
   their protocol mocks in simulation (the only path that exercises their commands and the
   bus-traffic tests), and the contract-level simulated driver is the combined `simcombined`,
   which proves change B (D8; approved by the owner 2026-10-11).
2. `AbortFcn` was not set by the session until the owner approved it (D24): it changes the order
   on the bus after a stalled stream or a Stop. Approved on 2026-10-11 and implemented: the session
   sets it at connect, so the output goes off before the acquisition's stop sequence; the session
   then disarms the source after `acquire` returns; an interrupt is covered by the output guard.
3. Bus traffic: three intended changes of order, all documented and approved by the owner on
   2026-10-11 - closing the window inside a sweep ends the measurement with `tim:instr:closed`
   (fault fixture edited by hand in stage B), a Stop during the LAN-XI connect step returns the
   module to Idle from the driver, before the generator's close lines instead of after them (fix
   stage; an explicit test), and D24: on the abnormal end of an acquisition one `OUTP OFF` comes
   before the REST stop. The fault fixture was regenerated from the code on 2026-10-11 (no hand
   edit left); the normal-path fixture is unchanged.
4. §5 item 3: a driver's defaults are in its `describe().defaults`, not in `defaultConfig` (D45;
   approved by the owner 2026-10-11).
5. §4 task 3 / acceptance: `validateConfig` asks the drivers, but a file is refused only where an
   instrument is needed (Connect, the session); loading warns (D29, extended in the fix stage), so
   old `user_config.json` files, files written by 1.1.0 and saved measurement folders still load.
6. The window shows the instruments in an "In use" row and an Instruments table (D40) and has no
   sample-rate or range control (D41); the choice stays in the configuration (§0.2).

**What remains**

* ~~The owner's hardware check (§0.3)~~ - **passed on 2026-10-12** (all ten steps,
  `docs/hardware_status.md`); version 1.2.0, merged into `main`. It found one known issue that
  predates WO-001: the 33220A drops an idle socket connection now and then (fix planned for 1.2.1,
  `docs/workorder_after_hardware_check.md`).
* After the merge (`docs/hardware_status.md`, "After the merge"): `config/user_config.json`
  rewritten in the new layout (D7, approved by the owner 2026-10-11; done 2026-10-12), and the five lab folders
  reprocessed into new folders because every swept-sine line is now centred on its frequency
  (which calibration they use is an open owner question).
* The NI and audio guidance (guide section 4.1) is not tried on a device: there is none in the lab.
